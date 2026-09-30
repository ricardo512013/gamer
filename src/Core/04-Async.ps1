# =====================================================================
# 04-ASYNC.ps1 - Execução em segundo plano (runspace) sem travar a interface
#
# Contrato das tarefas:
#   - Recebem $Queue (fila thread-safe) e $Context (hashtable de entrada)
#   - Registram progresso/log com:  Emit "texto" ["Info|Success|Warn|Error|Debug"] [0-100]
#   - Devolvem resultados via pipeline (coletados em EndInvoke)
#   - Podem usar as funções da biblioteca $global:TIWorkerLib
#     (as áreas Saúde e Inventário acrescentam as suas com +=)
# =====================================================================

$global:TIWorkerLib = @'
function Get-TIFolderSize([string]$Path) {
    $sum = 0L
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
    } catch { }
    if ($null -eq $sum) { $sum = 0L }
    return [double]$sum
}

function Format-TIByte([double]$Bytes) {
    if ($Bytes -ge 1TB) { return ('{0:0.##} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:0.##} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:0.##} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:0.##} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

# ---------------------------------------------------------------------
# Administradores locais
# Get-LocalGroupMember falha quando o grupo tem SID órfão (conta de domínio
# apagada, comum em escola). ADSI lista mesmo assim; o cmdlet fica de reserva.
# Retorna $null quando não consegue ler (quem chama decide falhar fechado).
# ---------------------------------------------------------------------
function Get-TIAdminMembers {
    $out = New-Object System.Collections.ArrayList
    $ok = $false
    try {
        $sidObj = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $grpName = ($sidObj.Translate([System.Security.Principal.NTAccount]).Value -split '\\')[-1]
        $grp = [ADSI]('WinNT://{0}/{1},group' -f $env:COMPUTERNAME, $grpName)
        foreach ($m in @($grp.Invoke('Members'))) {
            $sid = $null; $name = $null
            try {
                $bytes = $m.GetType().InvokeMember('objectSid', 'GetProperty', $null, $m, $null)
                $sid = (New-Object System.Security.Principal.SecurityIdentifier($bytes, 0)).Value
            } catch { }
            try { $name = [string]$m.GetType().InvokeMember('Name', 'GetProperty', $null, $m, $null) } catch { }
            [void]$out.Add([pscustomobject]@{ Name = $name; Sid = $sid })
        }
        $ok = $true
    } catch { }
    if (-not $ok) {
        try {
            foreach ($m in @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)) {
                [void]$out.Add([pscustomobject]@{
                    Name = (([string]$m.Name) -split '\\')[-1]
                    Sid  = $(if ($m.SID) { $m.SID.Value } else { $null })
                })
            }
            $ok = $true
        } catch { }
    }
    if (-not $ok) { return $null }
    return ,($out.ToArray())
}

function Get-TIAdminSidSet {
    $m = Get-TIAdminMembers
    if ($null -eq $m) { return $null }
    $set = @{}
    foreach ($x in @($m)) { if ($x.Sid) { $set[[string]$x.Sid] = $true } }
    return $set
}

function Get-TICurrentAdminNames {
    $m = Get-TIAdminMembers
    if ($null -eq $m) { return @() }
    return @($m | Where-Object { $_.Name } | ForEach-Object { $_.Name })
}

# ---------------------------------------------------------------------
# Perfis de alunos (RM)
# Pasta "12345", ou com sufixo criado pelo Windows quando o perfil é recriado
# ou vem do domínio: "12345.000", "12345.ESCOLA".
# ---------------------------------------------------------------------
function Test-TIStudentProfileName {
    param([string]$Name)
    return ([string]$Name -match '^\d{3,}(\.[^\\/]+)?$')
}

function Get-StudentProfiles {
    Emit 'Verificando os perfis locais do computador...' 'Info'
    $adminSids = Get-TIAdminSidSet
    $all = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
             Where-Object { -not $_.Special })
    $rows = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($p in $all) {
        $i++
        $name = Split-Path -Leaf $p.LocalPath
        if (-not (Test-TIStudentProfileName $name)) { continue }
        if ($adminSids -and $adminSids[[string]$p.SID]) {
            Emit ('Perfil {0} pertence a um administrador: fica fora da lista.' -f $name) 'Debug'
            continue
        }
        Emit ('Medindo o perfil {0} ({1}/{2})...' -f $name, $i, $all.Count) 'Debug' ([int](100 * $i / [Math]::Max(1, $all.Count)))
        $size = Get-TIFolderSize $p.LocalPath
        [void]$rows.Add([pscustomobject]@{
            Name     = $name
            Path     = $p.LocalPath
            Size     = $size
            LastUse  = $p.LastUseTime
            Loaded   = [bool]$p.Loaded
            Sid      = $p.SID
        })
    }
    Emit ('{0} perfil(is) de aluno encontrado(s).' -f $rows.Count) 'Success'
    return ($rows.ToArray())
}

function Remove-StudentProfiles {
    param($Items)
    $removed = 0
    $freed = 0.0
    $skipped = 0
    $total = @($Items).Count
    if ($total -eq 0) { Emit 'Nenhum perfil selecionado.' 'Warn'; return }
    $live = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue)
    $i = 0
    foreach ($item in $Items) {
        $i++
        $match = $live | Where-Object { $_.LocalPath -eq $item.Path } | Select-Object -First 1
        if (-not $match) {
            Emit ('O perfil {0} não está mais registrado no Windows.' -f $item.Name) 'Warn'
            $skipped++
            continue
        }
        if ($match.Loaded) {
            Emit ('O perfil {0} está em uso (usuário conectado): mantido.' -f $item.Name) 'Warn'
            $skipped++
            continue
        }
        Emit ('Removendo o perfil {0} ({1}/{2})...' -f $item.Name, $i, $total) 'Info' ([int](100 * $i / $total))
        try {
            Remove-CimInstance -InputObject $match -ErrorAction Stop
            $removed++
            $freed += [double]$item.Size
            Emit ('Perfil {0} removido do disco e do registro.' -f $item.Name) 'Success'
        } catch {
            Emit ('Falha ao remover {0}: {1}' -f $item.Name, $_.Exception.Message) 'Error'
        }
    }
    Emit ('Concluído: {0} removido(s), {1} mantido(s), {2} liberados.' -f $removed, $skipped, (Format-TIByte $freed)) 'Success'
    return ([pscustomobject]@{ Removed = $removed; Skipped = $skipped; Freed = $freed })
}

# ---------------------------------------------------------------------
# Limpeza profunda
# ---------------------------------------------------------------------
function Get-TIWinDir { if ($env:SystemRoot) { return $env:SystemRoot } return 'C:\Windows' }
function Get-TIUsersDir {
    if ($env:SystemDrive) {
        $p = Join-Path $env:SystemDrive 'Users'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return 'C:\Users'
}

function Get-TICacheTargets {
    $win = Get-TIWinDir
    $users = Get-TIUsersDir
    $list = New-Object System.Collections.ArrayList
    [void]$list.Add(@{ Id = 'temp';    Group = 'Temporários'; Path = (Join-Path $win 'Temp');     Label = 'Temporários do sistema'; Recurse = $true })
    $sw = Join-Path $win 'SoftwareDistribution\Download'
    [void]$list.Add(@{ Id = 'wu'; Group = 'Atualizações'; Path = $sw; Label = 'Downloads do Windows Update'; Recurse = $true })
    foreach ($dir in (Get-ChildItem -Path $users -Directory -ErrorAction SilentlyContinue)) {
        $n = $dir.Name
        if ($n -in @('Public','Default','Default User','All Users')) { continue }
        $uHome = $dir.FullName
        $tmp = Join-Path $uHome 'AppData\Local\Temp'
        [void]$list.Add(@{ Id = 'utemp'; Group = 'Temporários'; Path = $tmp; Label = ('Temporários de ' + $n); Recurse = $true })
        $thumb = Join-Path $uHome 'AppData\Local\Microsoft\Windows\Explorer'
        [void]$list.Add(@{ Id = 'thumb'; Group = 'Temporários'; Path = $thumb; Label = ('Miniaturas de ' + $n); Recurse = $false; Filter = 'thumbcache_*.db' })
        $recent = Join-Path $uHome 'AppData\Roaming\Microsoft\Windows\Recent'
        [void]$list.Add(@{ Id = 'recent'; Group = 'Temporários'; Path = $recent; Label = ('Itens recentes de ' + $n); Recurse = $true })
        # Chrome e Edge: todos os perfis (Default, Profile 1, Profile 2...)
        foreach ($br in @(
            @{ Id = 'chrome'; Name = 'Chrome'; Root = (Join-Path $uHome 'AppData\Local\Google\Chrome\User Data') },
            @{ Id = 'edge';   Name = 'Edge';   Root = (Join-Path $uHome 'AppData\Local\Microsoft\Edge\User Data') }
        )) {
            if (-not (Test-Path -LiteralPath $br.Root)) { continue }
            foreach ($prof in (Get-ChildItem -LiteralPath $br.Root -Directory -ErrorAction SilentlyContinue |
                               Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })) {
                foreach ($sub in @('Cache', 'Code Cache')) {
                    $cp = Join-Path $prof.FullName $sub
                    if (Test-Path -LiteralPath $cp) {
                        [void]$list.Add(@{ Id = ($br.Id + $(if ($sub -eq 'Cache') { '' } else { '2' })); Group = 'Navegadores'
                                           Path = $cp; Label = ('{0} do {1} de {2} ({3})' -f $(if ($sub -eq 'Cache') { 'Cache' } else { 'Cache de código' }), $br.Name, $n, $prof.Name); Recurse = $true })
                    }
                }
            }
        }
        $fxRoot = Join-Path $uHome 'AppData\Local\Mozilla\Firefox\Profiles'
        if (Test-Path -LiteralPath $fxRoot) {
            foreach ($prof in (Get-ChildItem -LiteralPath $fxRoot -Directory -ErrorAction SilentlyContinue)) {
                $c2 = Join-Path $prof.FullName 'cache2'
                if (Test-Path -LiteralPath $c2) {
                    [void]$list.Add(@{ Id = 'fx'; Group = 'Navegadores'; Path = $c2; Label = ('Cache do Firefox de ' + $n); Recurse = $true })
                }
            }
        }
        $inet = Join-Path $uHome 'AppData\Local\Microsoft\Windows\INetCache'
        [void]$list.Add(@{ Id = 'ie'; Group = 'Navegadores'; Path = $inet; Label = ('Cache de internet (legado) de ' + $n); Recurse = $true })
    }
    $doCache = Join-Path $win 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
    [void]$list.Add(@{ Id = 'do'; Group = 'Atualizações'; Path = $doCache; Label = 'Otimização de entrega'; Recurse = $true })
    $cbs = Join-Path $win 'Logs\CBS'
    [void]$list.Add(@{ Id = 'cbs'; Group = 'Logs'; Path = $cbs; Label = 'Logs de manutenção (CBS)'; Recurse = $true })
    $dmp = Join-Path $win 'Minidump'
    [void]$list.Add(@{ Id = 'dmp'; Group = 'Logs'; Path = $dmp; Label = 'Minidumps de travamento'; Recurse = $true })
    [void]$list.Add(@{ Id = 'memdmp'; Group = 'Logs'; Path = (Join-Path $win 'MEMORY.DMP'); Label = 'Despejo de memória (MEMORY.DMP)'; Recurse = $false; File = $true })
    [void]$list.Add(@{ Id = 'recycle'; Group = 'Lixeira'; Path = 'Lixeira (todas as unidades)'; Label = 'Esvaziar a Lixeira'; Recurse = $false; Special = 'recycle' })
    return $list
}

function Get-TIRecycleSize {
    $sum = 0.0
    try {
        $sh = New-Object -ComObject Shell.Application
        $bin = $sh.NameSpace(0xA)
        if ($bin) { foreach ($it in $bin.Items()) { try { $sum += [double]$it.Size } catch { } } }
    } catch { }
    return $sum
}

function Get-TIItemSize {
    param($Target)
    $size = 0.0
    try {
        if ($Target.Special -eq 'recycle') { return (Get-TIRecycleSize) }
        if ($Target.File) {
            if (Test-Path -LiteralPath $Target.Path) { $size = [double](Get-Item -LiteralPath $Target.Path -Force -ErrorAction SilentlyContinue).Length }
        } elseif (Test-Path -LiteralPath $Target.Path) {
            if ($Target.Filter) {
                $size = [double]((Get-ChildItem -LiteralPath $Target.Path -Filter $Target.Filter -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
            } else {
                $size = Get-TIFolderSize $Target.Path
            }
        }
    } catch { }
    return $size
}

function Get-TIJunkScan {
    Emit 'Analisando o que pode ser limpo...' 'Info'
    $targets = Get-TICacheTargets
    $rows = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($t in $targets) {
        $i++
        Emit ('Medindo {0}...' -f $t.Label) 'Debug' ([int](100 * $i / [Math]::Max(1, $targets.Count)))
        $size = Get-TIItemSize $t
        if ($size -le 0) { continue }
        [void]$rows.Add([pscustomobject]@{
            Id = $t.Id; Group = $t.Group; Label = $t.Label; Path = $t.Path
            Size = $size; Recurse = [bool]$t.Recurse; Filter = $t.Filter; File = [bool]$t.File; Special = $t.Special
        })
    }
    $total = ($rows | Measure-Object -Property Size -Sum).Sum
    Emit ('Análise: {0} item(ns), {1} recuperáveis.' -f $rows.Count, (Format-TIByte $total)) 'Success'
    return ($rows.ToArray())
}

function Clear-TIJunkItems {
    param($Items)
    $freed = 0.0
    $okN = 0; $failN = 0
    $all = @($Items)
    $total = $all.Count
    if ($total -eq 0) { Emit 'Nenhum item para limpar.' 'Warn'; return ([pscustomobject]@{ Freed = 0; Ok = 0; Fail = 0 }) }

    # Windows Update: o serviço segura arquivos abertos em SoftwareDistribution\Download
    $wuStopped = $false
    if (@($all | Where-Object { $_.Id -eq 'wu' }).Count -gt 0) {
        try {
            $svc = Get-Service -Name 'wuauserv' -ErrorAction Stop
            if ($svc.Status -eq 'Running') {
                Stop-Service -Name 'wuauserv' -Force -ErrorAction Stop
                $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
                $wuStopped = $true
                Emit 'Serviço do Windows Update pausado durante a limpeza.' 'Debug'
            }
        } catch { Emit ('Não foi possível pausar o Windows Update: {0}' -f $_.Exception.Message) 'Warn' }
    }

    $i = 0
    foreach ($it in $all) {
        $i++
        Emit ('Limpando {0}...' -f $it.Label) 'Info' ([int](100 * $i / $total))
        try {
            $before = Get-TIItemSize $it
            if ($it.Special -eq 'recycle') {
                Clear-RecycleBin -Force -ErrorAction Stop
            } elseif ($it.File) {
                if (Test-Path -LiteralPath $it.Path) { Remove-Item -LiteralPath $it.Path -Force -ErrorAction SilentlyContinue }
            } elseif ($it.Filter) {
                Get-ChildItem -LiteralPath $it.Path -Filter $it.Filter -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            } else {
                Get-ChildItem -LiteralPath $it.Path -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
            # tamanho REAL liberado = antes - depois (arquivos em uso não contam)
            $after = Get-TIItemSize $it
            $got = [Math]::Max(0.0, $before - $after)
            $freed += $got
            if ($got -gt 0 -or $before -le 0) { $okN++ } else { $failN++ }
            if ($after -gt 0 -and $before -gt 0) {
                Emit ('  {0} liberados ({1} em uso, mantidos)' -f (Format-TIByte $got), (Format-TIByte $after)) 'Warn'
            } else {
                Emit ('  {0} liberados' -f (Format-TIByte $got)) 'Success'
            }
        } catch {
            $failN++; Emit ('  Falha em {0}: {1}' -f $it.Label, $_.Exception.Message) 'Warn'
        }
    }

    if ($wuStopped) {
        try { Start-Service -Name 'wuauserv' -ErrorAction Stop; Emit 'Serviço do Windows Update retomado.' 'Debug' }
        catch { Emit ('O Windows Update não voltou sozinho: {0}' -f $_.Exception.Message) 'Warn' }
    }
    Emit ('Limpeza: {0} concluído(s), {1} parcial(is), {2} liberados.' -f $okN, $failN, (Format-TIByte $freed)) 'Success'
    return ([pscustomobject]@{ Freed = $freed; Ok = $okN; Fail = $failN })
}

function Clear-TISystemCache {
    $scan = Get-TIJunkScan
    return (Clear-TIJunkItems -Items $scan)
}

# ---------------------------------------------------------------------
# Programas instalados
# Fora da lista: componentes de sistema (SystemComponent=1), atualizações
# (ParentKeyName / ReleaseType) e entradas sem comando de desinstalação.
# ---------------------------------------------------------------------
function Get-TIInstalledApps {
    Emit 'Lendo os programas instalados...' 'Info'
    $rows = New-Object System.Collections.ArrayList
    $seen = @{}
    $hives = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $hidden = 0
    foreach ($hive in $hives) {
        if (-not (Test-Path $hive)) { continue }
        Get-ChildItem -Path $hive -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                $name = [string]$p.DisplayName
                if ([string]::IsNullOrWhiteSpace($name)) { return }
                $uninst = [string]$p.UninstallString
                if ([string]::IsNullOrWhiteSpace($uninst)) { return }
                if ($p.SystemComponent -eq 1) { $hidden++; return }
                if (-not [string]::IsNullOrWhiteSpace([string]$p.ParentKeyName)) { $hidden++; return }
                if ([string]$p.ReleaseType -match 'Update|Hotfix') { $hidden++; return }
                $key = ($name + '|' + $uninst).ToLower()
                if ($seen.ContainsKey($key)) { return }
                $seen[$key] = $true
                $size = 0.0
                if ($p.EstimatedSize) { $size = [double]$p.EstimatedSize * 1KB }
                [void]$rows.Add([pscustomobject]@{
                    Name = $name.Trim(); Version = [string]$p.DisplayVersion; Publisher = [string]$p.Publisher
                    Size = $size; Uninstall = $uninst; Quiet = [string]$p.QuietUninstallString
                    Hive = $hive; Key = $_.PSPath
                })
            } catch { }
        }
    }
    $arr = $rows.ToArray() | Sort-Object Name
    Emit ('{0} programa(s) encontrado(s); {1} componente(s) de sistema/atualização ocultos.' -f @($arr).Count, $hidden) 'Success'
    return @($arr)
}

# Separa executável e argumentos (com ou sem aspas, com espaço no caminho)
function Split-TICommandLine {
    param([string]$CommandLine)
    $cmd = ([string]$CommandLine).Trim()
    $exe = $cmd; $argList = ''
    if ($cmd -match '^"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $argList = $Matches[2] }
    elseif ($cmd -match '^(.+?\.exe)(\s+(.*))?$') { $exe = $Matches[1]; $argList = [string]$Matches[3] }
    elseif ($cmd -match '^(\S+)\s*(.*)$') { $exe = $Matches[1]; $argList = $Matches[2] }
    return [pscustomobject]@{ Exe = $exe.Trim(); Args = ([string]$argList).Trim() }
}

# Desinstaladores NSIS trazem a assinatura "Nullsoft" no executável
function Test-TINsisFile {
    param([string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $len = [int][Math]::Min($fs.Length, 4MB)
            $buf = New-Object byte[] $len
            $read = $fs.Read($buf, 0, $len)
            $txt = [System.Text.Encoding]::ASCII.GetString($buf, 0, $read)
            return ($txt.IndexOf('Nullsoft', [System.StringComparison]::Ordinal) -ge 0)
        } finally { $fs.Dispose() }
    } catch { return $false }
}

# Decide COMO desinstalar. Silencioso só quando o tipo é conhecido;
# desconhecido abre a janela do fabricante (antes ia escondido com /S e travava).
function Get-TIUninstallPlan {
    param([string]$Uninstall, [string]$Quiet, [bool]$IsNsis = $false)
    if (-not [string]::IsNullOrWhiteSpace($Quiet)) {
        $q = Split-TICommandLine $Quiet
        return [pscustomobject]@{ Exe = $q.Exe; Args = $q.Args; Kind = 'quiet'; Silent = $true }
    }
    if ([string]::IsNullOrWhiteSpace($Uninstall)) { return $null }
    $s = Split-TICommandLine $Uninstall
    $exe = $s.Exe; $a = $s.Args
    $leaf = (($exe -split '[\\/]')[-1]).ToLowerInvariant()
    if ($leaf -eq 'msiexec.exe' -or $leaf -eq 'msiexec') {
        $a = ($a -replace '(?i)/i(?=\s*\{)', '/X')
        if ($a -notmatch '(?i)/x' -and $a -match '\{[0-9A-Fa-f\-]{36}\}') { $a = '/X' + $Matches[0] }
        if ($a -notmatch '(?i)/q') { $a = ($a + ' /qn /norestart').Trim() }
        return [pscustomobject]@{ Exe = $exe; Args = $a; Kind = 'msi'; Silent = $true }
    }
    if ($leaf -match '^unins\d+\.exe$') {
        if ($a -notmatch '(?i)/(very)?silent') { $a = ($a + ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART').Trim() }
        return [pscustomobject]@{ Exe = $exe; Args = $a; Kind = 'inno'; Silent = $true }
    }
    if ($IsNsis) {
        if ($a -cnotmatch '(^|\s)/S(\s|$)') { $a = ($a + ' /S').Trim() }
        return [pscustomobject]@{ Exe = $exe; Args = $a; Kind = 'nsis'; Silent = $true }
    }
    return [pscustomobject]@{ Exe = $exe; Args = $a; Kind = 'interactive'; Silent = $false }
}

function Uninstall-TIApp {
    param($App, [int]$TimeoutMinutes = 10)
    if (-not $App) { throw 'Programa não informado.' }
    $hasQuiet = -not [string]::IsNullOrWhiteSpace([string]$App.Quiet)
    $isNsis = $false
    if (-not $hasQuiet) {
        $probe = Split-TICommandLine ([string]$App.Uninstall)
        $leaf = (($probe.Exe -split '[\\/]')[-1]).ToLowerInvariant()
        if ($leaf -notmatch '^msiexec' -and $leaf -notmatch '^unins\d+\.exe$') { $isNsis = Test-TINsisFile $probe.Exe }
    }
    $plan = Get-TIUninstallPlan -Uninstall ([string]$App.Uninstall) -Quiet ([string]$App.Quiet) -IsNsis $isNsis
    if (-not $plan) { throw 'O registro não traz comando de desinstalação.' }
    $kindTxt = switch ($plan.Kind) {
        'quiet' { 'comando silencioso do fabricante' }
        'msi'   { 'Windows Installer, sem janelas' }
        'inno'  { 'Inno Setup, sem janelas' }
        'nsis'  { 'NSIS, sem janelas' }
        default { 'desinstalador do fabricante (com janela)' }
    }
    Emit ('Desinstalando {0} ({1})...' -f $App.Name, $kindTxt) 'Warn'
    if (-not $plan.Silent) { Emit 'O desinstalador abre a própria janela: conclua as etapas por lá.' 'Warn' }

    $sp = @{ FilePath = $plan.Exe; PassThru = $true; ErrorAction = 'Stop' }
    if ($plan.Silent) { $sp.WindowStyle = 'Hidden' }
    if ($plan.Args) { $sp.ArgumentList = $plan.Args }
    $timeout = if ($plan.Silent) { $TimeoutMinutes } else { 30 }
    $started = Get-Date
    $deadline = $started.AddMinutes($timeout)
    $p = Start-Process @sp
    $null = $p.Handle
    # Espera em fatias curtas: o botão Cancelar consegue interromper
    while (-not $p.WaitForExit(500)) {
        if ((Get-Date) -gt $deadline) {
            try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch { }
            throw ('tempo esgotado ({0} min). O desinstalador deve estar esperando um clique: use o Painel de Controle.' -f $timeout)
        }
    }
    $code = $p.ExitCode

    # NSIS se copia para %TEMP% (Au_.exe / Un_A.exe) e o processo original sai na hora
    if ($plan.Kind -eq 'nsis' -or $plan.Kind -eq 'quiet') {
        Start-Sleep -Milliseconds 800
        while ($true) {
            $kids = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
                $_.ProcessName -match '^(Au_|Un_[A-Z])$' -and $(try { $_.StartTime -ge $started.AddSeconds(-5) } catch { $false })
            })
            if ($kids.Count -eq 0) { break }
            if ((Get-Date) -gt $deadline) {
                foreach ($k in $kids) { try { $k.Kill() } catch { } }
                throw 'tempo esgotado aguardando o desinstalador terminar.'
            }
            Start-Sleep -Milliseconds 500
        }
    }

    if ($code -ne 0 -and $code -ne 3010 -and $code -ne 1641) {
        throw ('o desinstalador terminou com o código {0}' -f $code)
    }
    if ($code -eq 3010 -or $code -eq 1641) { Emit 'O Windows pede reinício para concluir a remoção.' 'Warn' }

    # Conferência: a entrada de desinstalação deve sumir do registro
    Start-Sleep -Milliseconds 800
    if ($App.Key -and (Test-Path -LiteralPath $App.Key)) {
        Emit ('{0} ainda aparece no registro. Se a janela do desinstalador foi fechada, repita; se pediu reinício, reinicie o PC.' -f $App.Name) 'Warn'
        return [pscustomobject]@{ Removed = $false; Code = $code }
    }
    Emit ('{0} desinstalado.' -f $App.Name) 'Success'
    return [pscustomobject]@{ Removed = $true; Code = $code }
}

# ---------------------------------------------------------------------
# Senha padrão em lote: nunca mexe em administrador nem na conta em uso.
# Sem conseguir ler o grupo Administradores, não altera nada (falha fechado).
# ---------------------------------------------------------------------
function Set-TISchoolPasswords {
    param([string]$Password, [string]$Pattern = '^[0-9]{3,}$', [switch]$ForceChange)
    $adminSids = Get-TIAdminSidSet
    if ($null -eq $adminSids) {
        throw 'Não foi possível ler o grupo Administradores. Por segurança, nenhuma senha foi alterada.'
    }
    $me = ''
    try { $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { }
    $cands = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Name -match $Pattern -and $_.Enabled })
    $users = New-Object System.Collections.ArrayList
    foreach ($u in $cands) {
        $sid = [string]$u.SID.Value
        if ($adminSids[$sid]) { Emit ('{0} é administrador: senha mantida.' -f $u.Name) 'Warn'; continue }
        if ($sid -eq $me) { Emit ('{0} é a conta em uso: senha mantida.' -f $u.Name) 'Warn'; continue }
        [void]$users.Add($u)
    }
    $okN = 0; $failN = 0
    $i = 0
    foreach ($u in $users) {
        $i++
        Emit ('Aplicando a senha padrão em {0} ({1}/{2})...' -f $u.Name, $i, $users.Count) 'Info' ([int](100 * $i / [Math]::Max(1, $users.Count)))
        try {
            $sec = ConvertTo-SecureString $Password -AsPlainText -Force
            Set-LocalUser -Name $u.Name -Password $sec -ErrorAction Stop
            if ($ForceChange) {
                $out = (& net.exe user $u.Name /logonpasswordchg:yes 2>&1 | Out-String)
                if ($LASTEXITCODE -ne 0) { Emit ('Senha aplicada em {0}, mas não deu para exigir a troca: {1}' -f $u.Name, $out.Trim()) 'Warn' }
            }
            $okN++
        } catch { $failN++; Emit ('Falha em {0}: {1}' -f $u.Name, $_.Exception.Message) 'Error' }
    }
    Emit ('Senha padrão: {0} conta(s) alterada(s), {1} falha(s).' -f $okN, $failN) 'Success'
    return ([pscustomobject]@{ Ok = $okN; Fail = $failN })
}

# ---------------------------------------------------------------------
# Visão geral (Início)
# ---------------------------------------------------------------------
function Get-TISystemSnapshot {
    $os  = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs  = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $bios= Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $sysLetter = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
    $disk= Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $sysLetter) -ErrorAction SilentlyContinue

    $ip = $null; $gw = $null; $adapterName = $null
    try {
        $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
               Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } |
               Select-Object -First 1
        if ($cfg) {
            $ip = @($cfg.IPv4Address)[0].IPAddress
            $gw = @($cfg.IPv4DefaultGateway)[0].NextHop
            $adapterName = $cfg.NetAdapter.Name
        }
    } catch { }

    $freePct = 0; $freeBytes = 0L; $totalBytes = 0L
    if ($disk) {
        $freeBytes = [double]$disk.FreeSpace
        $totalBytes = [double]$disk.Size
        if ($totalBytes -gt 0) { $freePct = [int](100 * $freeBytes / $totalBytes) }
    }

    $uptime = $null
    if ($os -and $os.LastBootUpTime) { $uptime = (Get-Date) - $os.LastBootUpTime }

    $usedMem = 0L; $totalMem = 0L
    if ($os) {
        $totalMem = [double]$os.TotalVisibleMemorySize * 1KB
        $freeMem  = [double]$os.FreePhysicalMemory * 1KB
        $usedMem  = $totalMem - $freeMem
    }

    Emit 'Dados do sistema coletados.' 'Debug'

    $serial = '-'
    if ($bios -and $bios.SerialNumber) { $serial = ([string]$bios.SerialNumber).Trim() }
    $domain = '-'
    if ($cs) { $domain = $(if ($cs.PartOfDomain) { [string]$cs.Domain } else { [string]$cs.Workgroup }) }

    return [pscustomobject]@{
        Computer   = $env:COMPUTERNAME
        User       = $env:USERNAME
        Domain     = $domain
        InDomain   = $(if ($cs) { [bool]$cs.PartOfDomain } else { $false })
        Model      = $(if ($cs) { ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim() } else { '-' })
        Serial     = $serial
        OsName     = $(if ($os) { ([string]$os.Caption) -replace '^Microsoft\s+', '' } else { '-' })
        OsBuild    = $(if ($os) { $os.BuildNumber } else { '-' })
        Cpu        = $(if ($cpu) { (([string]$cpu.Name) -split '@')[0].Trim() } else { '-' })
        Uptime     = $uptime
        DiskFree   = $freeBytes
        DiskTotal  = $totalBytes
        DiskFreePct= $freePct
        MemUsed    = $usedMem
        MemTotal   = $totalMem
        Ip         = $ip
        Gateway    = $gw
        Adapter    = $adapterName
    }
}

# ---------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------
function Test-TINetwork {
    $rows = New-Object System.Collections.ArrayList
    $targets = New-Object System.Collections.ArrayList
    try {
        $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
               Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4DefaultGateway } |
               Select-Object -First 1
        $gw = @($cfg.IPv4DefaultGateway)[0].NextHop
        if ($gw) { [void]$targets.Add(@{ Label = 'Roteador (gateway)'; Addr = $gw }) }
    } catch { }
    if ($targets.Count -eq 0) {
        [void]$rows.Add([pscustomobject]@{ Target = 'Roteador (gateway)'; Addr = '-'; Ok = $false; Latency = -1; Detail = 'Nenhum adaptador com gateway configurado' })
        Emit '  Nenhum adaptador ativo com gateway.' 'Error'
    }
    [void]$targets.Add(@{ Label = 'Servidor público Google'; Addr = '8.8.8.8' })
    [void]$targets.Add(@{ Label = 'Servidor público Cloudflare'; Addr = '1.1.1.1' })

    $ping = New-Object System.Net.NetworkInformation.Ping
    $i = 0
    foreach ($t in $targets) {
        $i++
        Emit ('Testando {0}...' -f $t.Label) 'Info' ([int](60 * $i / $targets.Count))
        $ok = $false; $ms = -1; $detail = 'Sem resposta ao ping'
        try {
            $res = $ping.Send($t.Addr, 2500)
            if ($res.Status.ToString() -eq 'Success') { $ok = $true; $ms = [int]$res.RoundtripTime; $detail = 'Responde ao ping' }
        } catch { }
        if ($ok) { Emit ('  {0}: {1} ms' -f $t.Label, $ms) 'Success' }
        else     { Emit ('  {0}: sem resposta' -f $t.Label) 'Warn' }
        [void]$rows.Add([pscustomobject]@{ Target = $t.Label; Addr = $t.Addr; Ok = $ok; Latency = $ms; Detail = $detail })
    }

    # DNS: o nome precisa virar endereço (falha comum com DNS manual errado)
    Emit 'Testando a resolução de nomes (DNS)...' 'Info' 75
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $dnsOk = $false; $dnsDetail = 'Não resolveu o nome'
    try {
        $addrs = @([System.Net.Dns]::GetHostAddresses('www.microsoft.com'))
        $v4 = @($addrs | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | Select-Object -First 1)
        if ($addrs.Count -gt 0) { $dnsOk = $true; $dnsDetail = ('Resolveu para {0}' -f $(if ($v4.Count -gt 0) { $v4[0].ToString() } else { $addrs[0].ToString() })) }
    } catch { }
    $sw.Stop()
    [void]$rows.Add([pscustomobject]@{ Target = 'Resolução de nomes (DNS)'; Addr = 'www.microsoft.com'; Ok = $dnsOk; Latency = $(if ($dnsOk) { [int]$sw.ElapsedMilliseconds } else { -1 }); Detail = $dnsDetail })
    if ($dnsOk) { Emit ('  DNS: {0} ms' -f [int]$sw.ElapsedMilliseconds) 'Success' } else { Emit '  DNS: não resolveu' 'Warn' }

    # HTTP: o teste que o próprio Windows usa (detecta portal de login e proxy)
    Emit 'Testando o acesso à internet (HTTP)...' 'Info' 90
    $url = 'http://www.msftconnecttest.com/connecttest.txt'
    $httpOk = $false; $httpMs = -1; $httpDetail = 'Sem acesso'
    $viaProxy = ''
    try {
        $sysProxy = [System.Net.WebRequest]::DefaultWebProxy
        if ($sysProxy) {
            $sysProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            $via = $sysProxy.GetProxy([uri]$url)
            if ($via -and $via.AbsoluteUri -ne ([uri]$url).AbsoluteUri) { $viaProxy = $via.Authority }
        }
    } catch { }
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Timeout = 6000
        $req.ReadWriteTimeout = 6000
        $req.AllowAutoRedirect = $false
        $req.UserAgent = 'Microsoft NCSI'
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $sr.ReadToEnd()
        $sr.Close(); $resp.Close()
        $sw.Stop()
        $httpMs = [int]$sw.ElapsedMilliseconds
        if ($code -ge 300 -and $code -lt 400) {
            $httpDetail = 'Redirecionado: a rede pede login (portal de acesso)'
        } elseif ($body -match 'Microsoft Connect Test') {
            $httpOk = $true
            $httpDetail = $(if ($viaProxy) { 'Acesso via proxy ' + $viaProxy } else { 'Acesso direto' })
        } else {
            $httpDetail = 'Resposta inesperada (portal de acesso ou filtro de conteúdo)'
        }
    } catch [System.Net.WebException] {
        $st = [string]$_.Exception.Status
        $httpDetail = switch ($st) {
            'NameResolutionFailure'      { 'O DNS não resolveu o endereço de teste' }
            'ProxyNameResolutionFailure' { 'Proxy configurado não encontrado' }
            'Timeout'                    { 'Tempo esgotado' }
            'ConnectFailure'             { 'Conexão recusada ou bloqueada' }
            'ProtocolError'              {
                $sc = 0
                try { $sc = [int]$_.Exception.Response.StatusCode } catch { }
                if ($sc -eq 407) { 'O proxy exige usuário e senha' } else { ('Erro HTTP {0}' -f $sc) }
            }
            default                      { ('Falha: {0}' -f $st) }
        }
    } catch {
        $httpDetail = ('Falha: {0}' -f $_.Exception.Message)
    }
    [void]$rows.Add([pscustomobject]@{ Target = 'Acesso à internet (HTTP)'; Addr = 'msftconnecttest.com'; Ok = $httpOk; Latency = $httpMs; Detail = $httpDetail })
    if ($httpOk) { Emit ('  Internet: {0}' -f $httpDetail) 'Success' } else { Emit ('  Internet: {0}' -f $httpDetail) 'Warn' }

    $up = @($rows | Where-Object { $_.Ok }).Count
    Emit ('Diagnóstico: {0} de {1} testes OK.' -f $up, $rows.Count) $(if ($up -eq $rows.Count) { 'Success' } else { 'Warn' })
    return ($rows.ToArray())
}

function Get-TIAdapters {
    $rows = New-Object System.Collections.ArrayList
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object -Property Status, Name)
    foreach ($a in $adapters) {
        $cfg = $null
        try { $cfg = Get-NetIPConfiguration -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue } catch { }
        $ipv4 = ''; $gw = ''; $dns = ''
        if ($cfg) {
            $ipv4 = (@($cfg.IPv4Address) | ForEach-Object { $_.IPAddress }) -join ', '
            $gw   = (@($cfg.IPv4DefaultGateway) | ForEach-Object { $_.NextHop }) -join ', '
            $dns  = (@($cfg.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) -join ', ')
        }
        [void]$rows.Add([pscustomobject]@{
            Name    = $a.Name
            Desc    = $a.InterfaceDescription
            Status  = $a.Status.ToString()
            Speed   = $a.LinkSpeed
            Mac     = $a.MacAddress
            Ip      = $ipv4
            Gateway = $gw
            Dns     = $dns
        })
    }
    return ($rows.ToArray())
}

# Lê a saída do "netsh wlan show interfaces" em português OU inglês.
# Casa pelo começo do rótulo (sem acento), então sobrevive a erro de codificação.
function ConvertFrom-TIWifiText {
    param([string]$Text)
    $map = @(
        @{ Rx = '^SSID$';                          L = 'Rede (SSID)' },
        @{ Rx = '^(Estado|State)$';                L = 'Estado' },
        @{ Rx = '^(Sinal|Signal)$';                L = 'Sinal' },
        @{ Rx = '^(Canal|Channel)$';               L = 'Canal' },
        @{ Rx = '^(Banda|Band)$';                  L = 'Banda' },
        @{ Rx = '^(Tipo de r.{1,2}dio|Radio type)'; L = 'Padrão' },
        @{ Rx = '^(Autentica|Authentication)';     L = 'Segurança' },
        @{ Rx = '^(Taxa de recep|Receive rate)';   L = 'Recepção (Mbps)' },
        @{ Rx = '^(Taxa de transm|Transmit rate)'; L = 'Transmissão (Mbps)' }
    )
    $found = [ordered]@{}
    foreach ($line in ([string]$Text -split "`r?`n")) {
        if ($line -notmatch '^\s*([^:]+?)\s*:\s*(.*?)\s*$') { continue }
        $k = $Matches[1].Trim()
        $v = $Matches[2].Trim()
        foreach ($m in $map) {
            if ($k -match $m.Rx) {
                if (-not $found.Contains($m.L)) { $found[$m.L] = $v }
                break
            }
        }
    }
    $rows = New-Object System.Collections.ArrayList
    if ($found.Count -eq 0) {
        [void]$rows.Add([pscustomobject]@{ Label = 'Wi-Fi'; Value = 'Nenhuma interface sem fio encontrada (ou o serviço WLAN está parado)'; Tone = 'dim' })
        return ($rows.ToArray())
    }
    foreach ($m in $map) {
        if (-not $found.Contains($m.L)) { continue }
        $v = [string]$found[$m.L]
        $tone = ''
        if ($m.L -eq 'Estado') {
            $tone = $(if ($v -match '(?i)^(conectado|connected)') { 'ok' } else { 'warn' })
        } elseif ($m.L -eq 'Sinal' -and $v -match '(\d+)') {
            $pct = [int]$Matches[1]
            $tone = $(if ($pct -ge 60) { 'ok' } elseif ($pct -ge 35) { 'warn' } else { 'crit' })
        }
        [void]$rows.Add([pscustomobject]@{ Label = $m.L; Value = $v; Tone = $tone })
    }
    return ($rows.ToArray())
}

function Get-TIWifiInfo {
    try {
        $out = (& netsh.exe wlan show interfaces 2>&1 | Out-String)
        return (ConvertFrom-TIWifiText -Text $out)
    } catch {
        return @([pscustomobject]@{ Label = 'Erro'; Value = $_.Exception.Message; Tone = 'crit' })
    }
}

function Clear-TIDnsCache {
    Emit 'Limpando o cache de DNS...' 'Info'
    try {
        Clear-DnsClientCache -ErrorAction Stop
        Emit 'Cache de DNS limpo.' 'Success'
    } catch {
        $out = (& ipconfig /flushdns 2>&1 | Out-String)
        Emit ('ipconfig /flushdns: ' + (($out.Trim() -split "`n") | Select-Object -Last 1)) 'Success'
    }
    return $true
}

function Reset-TINetwork {
    Emit 'Renovando o endereço IP (release/renew)...' 'Info'
    $null = (& ipconfig /release 2>&1 | Out-String)
    Emit '  Endereço liberado' 'Info'
    Start-Sleep -Seconds 2
    $null = (& ipconfig /renew 2>&1 | Out-String)
    Emit '  Novo endereço solicitado' 'Info'
    Start-Sleep -Seconds 1
    $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
           Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } |
           Select-Object -First 1
    if ($cfg) {
        Emit ('Novo IPv4: {0}' -f (@($cfg.IPv4Address)[0].IPAddress)) 'Success'
    } else {
        Emit 'Nenhum IPv4 recebido após a renovação.' 'Warn'
    }
    return $true
}

function Repair-TIAdapter {
    param($Name)
    Emit ('Reiniciando o adaptador {0} (desativar e ativar)...' -f $Name) 'Warn'
    Disable-NetAdapter -Name $Name -Confirm:$false -ErrorAction Stop
    Emit '  Adaptador desativado' 'Info'
    Start-Sleep -Seconds 3
    Enable-NetAdapter -Name $Name -Confirm:$false -ErrorAction Stop
    Emit '  Adaptador reativado' 'Info'
    Start-Sleep -Seconds 4
    $a = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
    if ($a -and $a.Status.ToString() -eq 'Up') { Emit ('Adaptador {0} funcionando.' -f $Name) 'Success' }
    else { Emit ('O adaptador {0} ainda não conectou (cabo, Wi-Fi ou driver).' -f $Name) 'Warn' }
    return $true
}

# ---------------------------------------------------------------------
# Contas locais
# ---------------------------------------------------------------------
function Get-TIAccounts {
    $adminSids = Get-TIAdminSidSet
    $rows = New-Object System.Collections.ArrayList
    foreach ($u in (Get-LocalUser -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $locked = $false
        try {
            $de = [ADSI]('WinNT://{0}/{1},user' -f $env:COMPUTERNAME, $u.Name)
            $locked = [bool]$de.InvokeGet('IsAccountLocked')
            $de.Dispose()
        } catch { }
        $sid = [string]$u.SID.Value
        [void]$rows.Add([pscustomobject]@{
            Name        = $u.Name
            Enabled     = [bool]$u.Enabled
            Locked      = $locked
            Admin       = $(if ($adminSids) { [bool]$adminSids[$sid] } else { $false })
            AdminKnown  = ($null -ne $adminSids)
            Sid         = $sid
            Description = [string]$u.Description
            LastLogon   = $u.LastLogon
            PasswordSet = $u.PasswordLastSet
        })
    }
    if ($null -eq $adminSids) { Emit 'Não foi possível ler o grupo Administradores: a coluna Admin pode estar incompleta.' 'Warn' }
    return ($rows.ToArray())
}

# Bloqueio por senhas erradas: Enable-LocalUser NÃO desbloqueia; o ADSI sim.
function Unlock-TIAccount {
    param([string]$User)
    $de = [ADSI]('WinNT://{0}/{1},user' -f $env:COMPUTERNAME, $User)
    try {
        $locked = $false
        try { $locked = [bool]$de.InvokeGet('IsAccountLocked') } catch { }
        if (-not $locked) { return $false }
        $de.InvokeSet('IsAccountLocked', $false)
        $de.CommitChanges()
        return $true
    } finally { $de.Dispose() }
}

function Set-TIAccountPassword {
    param([string]$User, [string]$Password, [switch]$Remove)
    if ($Remove) {
        $out = (& net.exe user "$User" "" 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw ("net user falhou: " + $out.Trim()) }
        Emit ('A conta "{0}" agora entra sem senha.' -f $User) 'Warn'
    } else {
        $sec = ConvertTo-SecureString $Password -AsPlainText -Force
        Set-LocalUser -Name $User -Password $sec -ErrorAction Stop
        Emit ('Senha da conta "{0}" redefinida.' -f $User) 'Success'
    }
    try { if (Unlock-TIAccount -User $User) { Emit ('A conta "{0}" estava bloqueada e foi desbloqueada.' -f $User) 'Success' } } catch { }
    return $true
}

function Enable-TIAccount {
    param([string]$User, [switch]$Disable)
    if ($Disable) {
        Disable-LocalUser -Name $User -ErrorAction Stop
        Emit ('Conta "{0}" desativada.' -f $User) 'Warn'
        return $true
    }
    $u = Get-LocalUser -Name $User -ErrorAction Stop
    $wasDisabled = -not $u.Enabled
    if ($wasDisabled) { Enable-LocalUser -Name $User -ErrorAction Stop }
    $unlocked = $false
    try { $unlocked = Unlock-TIAccount -User $User } catch { Emit ('Não foi possível desbloquear "{0}": {1}' -f $User, $_.Exception.Message) 'Warn' }
    if ($wasDisabled -and $unlocked) { Emit ('Conta "{0}" ativada e desbloqueada.' -f $User) 'Success' }
    elseif ($wasDisabled) { Emit ('Conta "{0}" ativada.' -f $User) 'Success' }
    elseif ($unlocked) { Emit ('Conta "{0}" desbloqueada.' -f $User) 'Success' }
    else { Emit ('A conta "{0}" já estava ativa e desbloqueada.' -f $User) 'Info' }
    return $true
}

function Set-TIAccountAdmin {
    param([string]$User, [switch]$Remove)
    $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
    if ($Remove) {
        Remove-LocalGroupMember -SID $adminSid -Member $User -ErrorAction Stop
        Emit ('"{0}" saiu do grupo Administradores.' -f $User) 'Warn'
    } else {
        Add-LocalGroupMember -SID $adminSid -Member $User -ErrorAction Stop
        Emit ('"{0}" entrou no grupo Administradores.' -f $User) 'Success'
    }
    return $true
}

function New-TIAccount {
    param([string]$User, [string]$Password, [string]$Description)
    $sec = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $User -Password $sec -PasswordNeverExpires -ErrorAction Stop `
                  -Description $Description | Out-Null
    Emit ('Conta local "{0}" criada.' -f $User) 'Success'
    return $true
}
'@

$global:TIAsync = @{
    Ps         = $null
    Pool       = $null
    Handle     = $null
    Timer      = $null
    Queue      = $null
    OnComplete = $null
    Name       = ''
    ErrorCount = 0
    Cancelled  = $false
    Quiet      = $false
}

function Test-TIIsAdmin {
    try {
        $p = New-Object System.Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Set-TIAsyncProgress {
    param([int]$Percent = -1, [string]$Text = '')
    if ($global:ProgressBar) { $global:ProgressBar.Percent = $Percent }
    if ($Text -and $global:StatusLabel) { $global:StatusLabel.Text = $Text }
}

function Invoke-TIAsync {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [string]$Name = 'Tarefa',
        [hashtable]$Context = @{},
        [scriptblock]$OnComplete,
        [switch]$RequiresAdmin,
        [switch]$Audit,
        [switch]$Quiet
    )

    if ($global:TI.Busy) {
        Show-TIToast -Text 'Aguarde: já existe uma tarefa em andamento.' -Type 'Warn'
        return $false
    }
    if ($RequiresAdmin -and -not $global:TI.Elevated) {
        Show-TIToast -Text 'Esta ação precisa do TI Suite aberto como administrador.' -Type 'Error'
        Write-TILog -Level 'Error' -Message ("{0}: bloqueada (sem elevação). Clique no selo da barra lateral para reabrir como administrador." -f $Name)
        return $false
    }

    $global:TI.Busy = $true
    $global:TIAsync.Name = $Name
    $global:TIAsync.OnComplete = $OnComplete
    $global:TIAsync.ErrorCount = 0
    $global:TIAsync.Cancelled = $false
    $global:TIAsync.Audit = ($Audit.IsPresent -or $RequiresAdmin.IsPresent)
    $global:TIAsync.Quiet = $Quiet.IsPresent
    $global:TIAsync.Started = Get-Date
    Set-TIBusy -Busy $true -Name $Name
    Write-TILog -Level 'Info' -Message ("Iniciando: {0}" -f $Name)

    $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    $global:TIAsync.Queue = $queue

    $preamble = @"
param(`$Queue, `$Context)
function Emit([string]`$Text, [string]`$Level = 'Info', [int]`$Progress = -1) {
    `$Queue.Enqueue([pscustomobject]@{ Kind = 'Log'; Text = `$Text; Level = `$Level; Progress = `$Progress })
}
"@

    $pool = [runspacefactory]::CreateRunspacePool(1, 2)
    $pool.Open()
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($preamble + "`r`n" + $global:TIWorkerLib + "`r`n" + $Script.ToString()).AddArgument($queue).AddArgument($Context)

    $global:TIAsync.Pool = $pool
    $global:TIAsync.Ps = $ps
    $global:TIAsync.Handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 110
    $timer.Add_Tick({ Invoke-TIAsyncPump })
    $timer.Start()
    $global:TIAsync.Timer = $timer
    return $true
}

function Invoke-TIAsyncPump {
    $st = $global:TIAsync
    if (-not $st.Ps) { return }

    $item = $null
    $guard = 0
    while ($st.Queue.TryDequeue([ref]$item) -and $guard -lt 500) {
        $guard++
        if ($item.Kind -eq 'Log') {
            $lvl = if ($item.Level -in @('Debug','Info','Success','Warn','Error')) { $item.Level } else { 'Info' }
            Write-TILog -Level $lvl -Message $item.Text
            if ($item.Progress -ge 0) { Set-TIAsyncProgress -Percent $item.Progress }
        }
        $item = $null
    }

    if (-not $st.Handle.IsCompleted) { return }

    $st.Timer.Stop()
    $st.Timer.Dispose()

    $results = $null
    try {
        $results = $st.Ps.EndInvoke($st.Handle)
    } catch {
        if (-not $st.Cancelled) {
            $msg = $_.Exception.Message
            if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message }
            Write-TILog -Level 'Error' -Message ("{0}: {1}" -f $st.Name, $msg)
            $st.ErrorCount++
        }
    }
    if (-not $st.Cancelled) {
        foreach ($err in @($st.Ps.Streams.Error)) {
            Write-TILog -Level 'Error' -Message $err.ToString()
            $st.ErrorCount++
        }
    }

    # drena o restante da fila
    $item = $null
    while ($st.Queue.TryDequeue([ref]$item)) {
        if ($item.Kind -eq 'Log') {
            $lvl = if ($item.Level -in @('Debug','Info','Success','Warn','Error')) { $item.Level } else { 'Info' }
            Write-TILog -Level $lvl -Message $item.Text
        }
        $item = $null
    }

    try { $st.Ps.Dispose() } catch { }
    try { $st.Pool.Close(); $st.Pool.Dispose() } catch { }
    $st.Ps = $null; $st.Pool = $null; $st.Handle = $null; $st.Queue = $null

    # Estado copiado e zerado ANTES do OnComplete: se ele iniciar outra tarefa
    # (ex.: remover perfis e listar de novo), nada daqui sobrescreve a nova.
    $name = $st.Name
    $onDone = $st.OnComplete
    $audit = $st.Audit
    $errs = $st.ErrorCount
    $cancelled = $st.Cancelled
    $quiet = $st.Quiet
    $secs = if ($st.Started) { [int]((Get-Date) - $st.Started).TotalSeconds } else { 0 }
    $st.OnComplete = $null
    $st.Name = ''
    $st.Cancelled = $false
    $st.Quiet = $false

    $global:TI.Busy = $false
    Set-TIAsyncProgress -Percent -1
    Set-TIBusy -Busy $false -Name ''

    if ($cancelled) {
        Write-TILog -Level 'Warn' -Message ("{0}: cancelada pelo operador." -f $name)
        Show-TIToast -Text ("{0}: cancelada" -f $name) -Type 'Warn'
        if ($audit) { try { Write-TIAudit -Action $name -Result 'CANCELADA' -Detail ('{0}s' -f $secs) } catch { } }
        return
    }
    if ($audit) {
        try { Write-TIAudit -Action $name -Result $(if ($errs -gt 0) { 'ERRO' } else { 'OK' }) -Detail ('{0}s; {1} erro(s)' -f $secs, $errs) } catch { }
    }
    if ($errs -gt 0) {
        Write-TILog -Level 'Warn' -Message ("{0}: terminou com {1} erro(s)." -f $name, $errs)
        Show-TIToast -Text ("{0}: terminou com erros (veja o console)" -f $name) -Type 'Error'
    } elseif ($quiet) {
        Write-TILog -Level 'Debug' -Message ("{0}: concluída." -f $name)
    } else {
        Write-TILog -Level 'Success' -Message ("{0}: concluída." -f $name)
        Show-TIToast -Text ("{0}: concluída" -f $name) -Type 'Success'
    }
    if ($onDone) {
        try { & $onDone $results } catch {
            Write-TILog -Level 'Error' -Message ("Erro ao finalizar {0}: {1}" -f $name, $_.Exception.Message)
        }
    }
}

# Cancelamento sem congelar a janela (BeginStop em vez de Stop)
function Stop-TIAsync {
    if (-not $global:TI.Busy -or -not $global:TIAsync.Ps) { return }
    if ($global:TIAsync.Cancelled) { return }
    $global:TIAsync.Cancelled = $true
    Write-TILog -Level 'Warn' -Message ("Cancelando: {0}..." -f $global:TIAsync.Name)
    if ($global:CancelBtn) { $global:CancelBtn.Enabled = $false }
    try { [void]$global:TIAsync.Ps.BeginStop($null, $null) } catch { }
}

# ---------------------------------------------------------------------
# Auxiliares de hardware compartilhados (Saúde do PC e Inventário)
# ---------------------------------------------------------------------
$global:TIWorkerLib += @'

# Tamanho "de etiqueta" (base 1000, como o fabricante anuncia): 256 GB, 500 GB, 1 TB
function Format-TIDiskSize {
    param([double]$Bytes)
    if ($Bytes -le 0) { return '?' }
    $gb = $Bytes / 1e9
    if ($gb -ge 999) {
        $tb = $gb / 1000
        if ([Math]::Abs($tb - [Math]::Round($tb)) -lt 0.05) { return ('{0} TB' -f [Math]::Round($tb)) }
        return ('{0:0.#} TB' -f $tb)
    }
    $std = @(16, 32, 60, 64, 80, 120, 128, 160, 180, 240, 250, 256, 320, 480, 500, 512, 640, 750, 960)
    $best = 0; $bestDiff = 1.0
    foreach ($s in $std) {
        $diff = [Math]::Abs($gb - $s) / $s
        if ($diff -lt $bestDiff) { $bestDiff = $diff; $best = $s }
    }
    if ($best -gt 0 -and $bestDiff -le 0.06) { return ('{0} GB' -f $best) }
    return ('{0} GB' -f [Math]::Round($gb))
}

# MediaType/BusType chegam como texto ("SSD", "NVMe") ou número (4, 17), conforme o Windows
function ConvertTo-TIMediaWord {
    param($MediaType, $BusType)
    $m = [string]$MediaType
    $b = [string]$BusType
    if ($b -eq 'NVMe' -or $b -eq '17') { return 'SSD NVMe' }
    if ($m -eq 'SSD' -or $m -eq '4') { return 'SSD' }
    if ($m -eq 'HDD' -or $m -eq '3') { return 'HD' }
    if ($m -eq 'SCM' -or $m -eq '5') { return 'SCM' }
    return 'Disco'
}

function ConvertTo-TIHealthWord {
    param($HealthStatus)
    $h = [string]$HealthStatus
    if ($h -eq 'Healthy' -or $h -eq '0')   { return [pscustomobject]@{ Word = 'Saudável'; Tone = 'ok' } }
    if ($h -eq 'Warning' -or $h -eq '1')   { return [pscustomobject]@{ Word = 'Atenção'; Tone = 'warn' } }
    if ($h -eq 'Unhealthy' -or $h -eq '2') { return [pscustomobject]@{ Word = 'Com falha'; Tone = 'crit' } }
    return [pscustomobject]@{ Word = 'Estado desconhecido'; Tone = 'dim' }
}

function Test-TIInternalDisk {
    param($Disk)
    $b = [string]$Disk.BusType
    return -not ($b -eq 'USB' -or $b -eq '7' -or $b -eq 'SD' -or $b -eq '12' -or $b -eq 'MMC' -or $b -eq '13')
}
'@
