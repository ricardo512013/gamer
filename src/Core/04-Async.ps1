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
            $sid = $null; $name = $null; $class = $null
            try {
                $bytes = $m.GetType().InvokeMember('objectSid', 'GetProperty', $null, $m, $null)
                $sid = (New-Object System.Security.Principal.SecurityIdentifier($bytes, 0)).Value
            } catch { }
            try { $name = [string]$m.GetType().InvokeMember('Name', 'GetProperty', $null, $m, $null) } catch { }
            try { $class = [string]$m.GetType().InvokeMember('Class', 'GetProperty', $null, $m, $null) } catch { }
            [void]$out.Add([pscustomobject]@{ Name = $name; Sid = $sid; Class = $class })
        }
        $ok = $true
    } catch { }
    if (-not $ok) {
        try {
            foreach ($m in @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)) {
                [void]$out.Add([pscustomobject]@{
                    Name  = (([string]$m.Name) -split '\\')[-1]
                    Sid   = $(if ($m.SID) { $m.SID.Value } else { $null })
                    # ObjectClass vem traduzido (Usuário/User); o resto conta como grupo
                    Class = $(if ([string]$m.ObjectClass -match '^(User|Usu)') { 'User' } else { 'Group' })
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

# (Perfis de usuários: funções do worker ficam em src/Workspaces/Limpeza.ps1)

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

# As pastas dentro de um perfil são do próprio usuário: ele pode trocar uma
# delas por um ponto de junção ou link simbólico que aponta para fora do
# perfil (Windows, Arquivos de Programas, outro perfil). A limpeza roda como
# administrador, então medir e apagar NUNCA seguem links: um link encontrado
# na pasta é apagado como link, sem entrar nele, e um alvo com link no
# caminho (entre a pasta do perfil e ele) fica de fora.
# Remove-Item -Recurse do PS 5.1 desce em pontos de junção: não usar aqui.

# Primeiro ponto de junção ou link simbólico no caminho, de $Path até $Base
# (inclusive). '' = nenhum; '?' = não deu para ler os atributos.
# Sem $Base (ou com $Path fora dele), confere até a raiz da unidade.
function Find-TIPathLink {
    param([string]$Path, [string]$Base = '')
    try {
        $sep = [System.IO.Path]::DirectorySeparatorChar
        $cur = [System.IO.Path]::GetFullPath($Path)
        $stop = ''
        if ($Base) {
            $b = [System.IO.Path]::GetFullPath($Base).TrimEnd($sep)
            $c = $cur.TrimEnd($sep)
            if ($c -ieq $b -or $c.StartsWith($b + $sep, [System.StringComparison]::OrdinalIgnoreCase)) { $stop = $b }
        }
        while ($cur) {
            $attr = $null
            try { $attr = [System.IO.File]::GetAttributes($cur) }
            catch [System.IO.FileNotFoundException] { }
            catch [System.IO.DirectoryNotFoundException] { }
            if ($null -ne $attr -and ([int]$attr -band 1024)) { return $cur }
            if ($stop -and $cur.TrimEnd($sep) -ieq $stop) { break }
            $parent = [System.IO.Path]::GetDirectoryName($cur)
            if ([string]::IsNullOrEmpty($parent)) { break }
            $cur = $parent
        }
        return ''
    } catch { return '?' }
}

# Tamanho de uma pasta sem seguir links (1024 = atributo ReparsePoint): pontos
# de junção e links simbólicos não contam nem são abertos.
# -Like: só os itens do primeiro nível com esse nome. -TopOnly: sem subpastas.
function Get-TISafeSize {
    param([string]$Path, [string]$Like = '', [switch]$TopOnly)
    $sum = 0.0
    try {
        $root = New-Object System.IO.DirectoryInfo($Path)
        if (-not $root.Exists -or ([int]$root.Attributes -band 1024)) { return 0.0 }
    } catch { return 0.0 }
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $first = $true
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        # a primeira pasta tirada da pilha é sempre a de partida
        $isTop = $first
        $first = $false
        $entries = @()
        try { $entries = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $entries) {
            if ($isTop -and $Like -and $e.Name -notlike $Like) { continue }
            if ([int]$e.Attributes -band 1024) { continue }
            if ($e -is [System.IO.DirectoryInfo]) { if (-not $TopOnly) { $stack.Push($e) } }
            else { try { $sum += [double]$e.Length } catch { } }
        }
    }
    return $sum
}

# Link encontrado na limpeza: sai só o link (RemoveDirectory/DeleteFile não
# seguem o link), o destino fica intacto
function Remove-TILinkEntry {
    param($Item)
    try {
        if ($Item -is [System.IO.DirectoryInfo]) { [System.IO.Directory]::Delete($Item.FullName, $false) }
        else { [System.IO.File]::Delete($Item.FullName) }
    } catch { }
}

# Apaga o CONTEÚDO de uma pasta (a pasta em si fica) sem seguir links.
# Arquivo em uso fica para trás sem interromper o resto.
# -Like/-TopOnly: como em Get-TISafeSize.
function Clear-TISafeFolder {
    param([string]$Path, [string]$Like = '', [switch]$TopOnly)
    try {
        $root = New-Object System.IO.DirectoryInfo($Path)
        if (-not $root.Exists -or ([int]$root.Attributes -band 1024)) { return }
    } catch { return }
    $dirs = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $first = $true
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        $isTop = $first
        $first = $false
        if (-not $isTop) {
            # confere de novo ao entrar: a pasta pode ter virado link depois de listada
            try { $d.Refresh() } catch { continue }
            if (-not $d.Exists) { continue }
            if ([int]$d.Attributes -band 1024) { Remove-TILinkEntry $d; continue }
        }
        $entries = @()
        try { $entries = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $entries) {
            if ($isTop -and $Like -and $e.Name -notlike $Like) { continue }
            if ([int]$e.Attributes -band 1024) { Remove-TILinkEntry $e; continue }
            if ($e -is [System.IO.DirectoryInfo]) {
                if (-not $TopOnly) { $stack.Push($e); [void]$dirs.Add($e) }
            } else {
                try {
                    if ([int]$e.Attributes -band 1) { $e.Attributes = [System.IO.FileAttributes]::Normal }
                    $e.Delete()
                } catch { }
            }
        }
    }
    # pastas de baixo para cima; Delete() sem recursão: a que ainda tiver algo em uso fica
    for ($i = $dirs.Count - 1; $i -ge 0; $i--) {
        $d = $dirs[$i]
        try {
            $d.Refresh()
            if (-not $d.Exists) { continue }
            if ([int]$d.Attributes -band 1024) { Remove-TILinkEntry $d; continue }
            if ([int]$d.Attributes -band 1) { $d.Attributes = [System.IO.FileAttributes]::Normal }
            $d.Delete()
        } catch { }
    }
}

# Link no caminho de um alvo da limpeza ('' = nenhum). A Lixeira confere as
# pastas dela em Get-TIRecycleBins.
function Get-TIJunkLink {
    param($Target)
    if ($Target.Special -eq 'recycle') { return '' }
    return (Find-TIPathLink -Path ([string]$Target.Path) -Base ([string]$Target.Base))
}

# Lixeira de cada conta: <unidade>:\$Recycle.Bin\<SID> em todas as unidades
# fixas, inclusive a de quem já não tem perfil (a Shell.Application só vê a
# Lixeira de quem roda o TI Suite). Sem elevação, só a própria é acessível.
function Get-TIRecycleBins {
    $out = New-Object System.Collections.ArrayList
    $me = ''
    try { $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { }
    foreach ($drv in @([System.IO.DriveInfo]::GetDrives())) {
        try {
            if ($drv.DriveType -ne [System.IO.DriveType]::Fixed -or -not $drv.IsReady) { continue }
            $bin = New-Object System.IO.DirectoryInfo([System.IO.Path]::Combine($drv.RootDirectory.FullName, '$Recycle.Bin'))
            if (-not $bin.Exists -or ([int]$bin.Attributes -band 1024)) { continue }
            $subs = @()
            try { $subs = @($bin.GetDirectories('S-1-*')) } catch { }
            if ($me -and @($subs | Where-Object { $_.Name -eq $me }).Count -eq 0) {
                $mine = New-Object System.IO.DirectoryInfo([System.IO.Path]::Combine($bin.FullName, $me))
                if ($mine.Exists) { $subs += $mine }
            }
            foreach ($s in $subs) {
                if ([int]$s.Attributes -band 1024) { continue }
                [void]$out.Add($s.FullName)
            }
        } catch { }
    }
    return $out.ToArray()
}

# Esvazia as Lixeiras: só os itens apagados ($I... = dados do item, $R... = o
# item). As pastas $Recycle.Bin e <SID> e o desktop.ini de cada uma ficam.
function Clear-TIRecycleBins {
    foreach ($b in @(Get-TIRecycleBins)) { Clear-TISafeFolder -Path $b -Like '$[IR]*' }
}

# Otimização de Entrega: o cmdlet próprio (Windows 10 1709+) limpa pelo
# serviço, que segura arquivos da pasta. Sem o cmdlet, apaga a pasta.
function Clear-TIDeliveryCache {
    param([string]$Path)
    if (Get-Command -Name 'Delete-DeliveryOptimizationCache' -ErrorAction SilentlyContinue) {
        try {
            Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null
            Emit '  Cache limpo pelo serviço da Otimização de Entrega.' 'Debug'
            return
        } catch { Emit ('  Otimização de Entrega: o cmdlet falhou ({0}); apagando a pasta.' -f $_.Exception.Message) 'Debug' }
    }
    Clear-TISafeFolder -Path $Path
}

# Religa o Windows Update pausado pela limpeza. Chamada no finally: vale
# também quando a limpeza é cancelada ou falha no meio.
function Restore-TIWuService {
    try {
        $svc = Get-Service -Name 'wuauserv' -ErrorAction Stop
        if ($svc.Status -eq 'StopPending') { try { $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15)) } catch { } }
        $svc.Refresh()
        if ($svc.Status -eq 'Stopped') { $svc.Start() }
        try { Emit 'Serviço do Windows Update retomado.' 'Debug' } catch { }
    } catch {
        try { Emit ('O Windows Update não voltou agora ({0}). Ele volta sozinho quando o Windows precisar ou ao reiniciar o computador.' -f $_.Exception.Message) 'Warn' } catch { }
    }
}

function Get-TICacheTargets {
    $win = Get-TIWinDir
    $users = Get-TIUsersDir
    $list = New-Object System.Collections.ArrayList
    # Base: a partir dela nenhum link é aceito no caminho do alvo (Find-TIPathLink)
    [void]$list.Add(@{ Id = 'temp';    Group = 'Temporários'; Path = (Join-Path $win 'Temp');     Label = 'Temporários do sistema'; Recurse = $true; Base = $win })
    $sw = Join-Path $win 'SoftwareDistribution\Download'
    [void]$list.Add(@{ Id = 'wu'; Group = 'Atualizações'; Path = $sw; Label = 'Downloads do Windows Update'; Recurse = $true; Base = $win })
    foreach ($dir in (Get-ChildItem -LiteralPath $users -Directory -ErrorAction SilentlyContinue)) {
        $n = $dir.Name
        if ($n -in @('Public','Default','Default User','All Users')) { continue }
        # pasta de perfil que é um link: fica de fora
        if ([int]$dir.Attributes -band 1024) { continue }
        $uHome = $dir.FullName
        $tmp = Join-Path $uHome 'AppData\Local\Temp'
        [void]$list.Add(@{ Id = 'utemp'; Group = 'Temporários'; Path = $tmp; Label = ('Temporários de ' + $n); Recurse = $true; Base = $uHome })
        $thumb = Join-Path $uHome 'AppData\Local\Microsoft\Windows\Explorer'
        [void]$list.Add(@{ Id = 'thumb'; Group = 'Temporários'; Path = $thumb; Label = ('Miniaturas de ' + $n); Recurse = $false; Filter = 'thumbcache_*.db'; Base = $uHome })
        # Itens recentes: só os atalhos (.lnk) da raiz de Recent. AutomaticDestinations e
        # CustomDestinations ficam: guardam as pastas FIXADAS no Acesso rápido e os itens
        # fixados nas listas de atalhos da barra de tarefas (de todos os programas).
        $recent = Join-Path $uHome 'AppData\Roaming\Microsoft\Windows\Recent'
        [void]$list.Add(@{ Id = 'recent'; Group = 'Temporários'; Path = $recent; Label = ('Itens recentes de ' + $n); Recurse = $false; Filter = '*.lnk'; Base = $uHome })
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
                        [void]$list.Add(@{ Id = ($br.Id + $(if ($sub -eq 'Cache') { '' } else { '2' })); Group = 'Navegadores'; Base = $uHome
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
                    [void]$list.Add(@{ Id = 'fx'; Group = 'Navegadores'; Path = $c2; Label = ('Cache do Firefox de ' + $n); Recurse = $true; Base = $uHome })
                }
            }
        }
        $inet = Join-Path $uHome 'AppData\Local\Microsoft\Windows\INetCache'
        [void]$list.Add(@{ Id = 'ie'; Group = 'Navegadores'; Path = $inet; Label = ('Cache de internet (legado) de ' + $n); Recurse = $true; Base = $uHome })
    }
    $doCache = Join-Path $win 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
    [void]$list.Add(@{ Id = 'do'; Group = 'Atualizações'; Path = $doCache; Label = 'Otimização de entrega'; Recurse = $true; Base = $win })
    $cbs = Join-Path $win 'Logs\CBS'
    [void]$list.Add(@{ Id = 'cbs'; Group = 'Logs'; Path = $cbs; Label = 'Logs de manutenção (CBS)'; Recurse = $true; Base = $win })
    $dmp = Join-Path $win 'Minidump'
    [void]$list.Add(@{ Id = 'dmp'; Group = 'Logs'; Path = $dmp; Label = 'Minidumps de travamento'; Recurse = $true; Base = $win })
    [void]$list.Add(@{ Id = 'memdmp'; Group = 'Logs'; Path = (Join-Path $win 'MEMORY.DMP'); Label = 'Despejo de memória (MEMORY.DMP)'; Recurse = $false; File = $true; Base = $win })
    [void]$list.Add(@{ Id = 'recycle'; Group = 'Lixeira'; Path = 'Todas as unidades fixas ($Recycle.Bin)'; Label = 'Esvaziar a Lixeira de todas as contas'; Recurse = $false; Special = 'recycle' })
    return $list
}

# Lixeira de todas as contas em todas as unidades fixas (só $I... e $R...)
function Get-TIRecycleSize {
    $sum = 0.0
    foreach ($b in @(Get-TIRecycleBins)) { $sum += Get-TISafeSize -Path $b -Like '$[IR]*' }
    return $sum
}

# Tamanho de um alvo da limpeza, sem seguir links. Alvo com link no caminho
# conta 0 (fica de fora da análise e da limpeza).
function Get-TIItemSize {
    param($Target)
    $size = 0.0
    try {
        if ($Target.Special -eq 'recycle') { return (Get-TIRecycleSize) }
        if (Get-TIJunkLink $Target) { return 0.0 }
        if ($Target.File) {
            $f = New-Object System.IO.FileInfo([string]$Target.Path)
            if ($f.Exists -and -not ([int]$f.Attributes -band 1024)) { $size = [double]$f.Length }
        } elseif ($Target.Filter) {
            $size = Get-TISafeSize -Path ([string]$Target.Path) -Like ([string]$Target.Filter) -TopOnly
        } else {
            $size = Get-TISafeSize -Path ([string]$Target.Path)
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
        $link = Get-TIJunkLink $t
        if ($link) {
            # '?' = atributos ilegíveis (sem elevação, perfil de outra conta): fica de fora sem alarde
            if ($link -ne '?') { Emit ('{0}: fica de fora, porque "{1}" é um ponto de junção ou link simbólico.' -f $t.Label, $link) 'Warn' }
            continue
        }
        $size = Get-TIItemSize $t
        if ($size -le 0) { continue }
        [void]$rows.Add([pscustomobject]@{
            Id = $t.Id; Group = $t.Group; Label = $t.Label; Path = $t.Path; Base = $t.Base
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
    $all = @($Items | Where-Object { $_ })
    $total = $all.Count
    if ($total -eq 0) { Emit 'Nenhum item para limpar.' 'Warn'; return ([pscustomobject]@{ Freed = 0; Ok = 0; Fail = 0 }) }

    # Windows Update: o serviço segura arquivos abertos em SoftwareDistribution\Download.
    # O finally religa o serviço mesmo se a limpeza for cancelada ou falhar no meio.
    $wuStopped = $false
    try {
        if (@($all | Where-Object { $_.Id -eq 'wu' }).Count -gt 0) {
            try {
                $svc = Get-Service -Name 'wuauserv' -ErrorAction Stop
                if ($svc.Status -eq 'Running') {
                    # marcado já no pedido: se a espera estourar, o serviço ainda volta no finally
                    $wuStopped = $true
                    Stop-Service -Name 'wuauserv' -Force -ErrorAction Stop
                    $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
                    Emit 'Serviço do Windows Update pausado durante a limpeza.' 'Debug'
                }
            } catch { Emit ('Não foi possível pausar o Windows Update: {0}' -f $_.Exception.Message) 'Warn' }
        }

        $i = 0
        foreach ($it in $all) {
            $i++
            Emit ('Limpando {0}...' -f $it.Label) 'Info' ([int](100 * $i / $total))
            try {
                if ($it.Special -ne 'recycle') {
                    # confere de novo na hora de apagar (a pasta pode ter mudado depois da análise)
                    $link = Get-TIJunkLink $it
                    if ($link) {
                        $failN++
                        if ($link -eq '?') { Emit ('  {0}: não deu para conferir o caminho; ficou de fora.' -f $it.Label) 'Warn' }
                        else { Emit ('  {0}: ficou de fora, porque "{1}" é um ponto de junção ou link simbólico.' -f $it.Label, $link) 'Warn' }
                        continue
                    }
                }
                $before = Get-TIItemSize $it
                if ($it.Special -eq 'recycle') {
                    Clear-TIRecycleBins
                } elseif ($it.Id -eq 'do') {
                    Clear-TIDeliveryCache -Path ([string]$it.Path)
                } elseif ($it.File) {
                    $f = New-Object System.IO.FileInfo([string]$it.Path)
                    if ($f.Exists -and -not ([int]$f.Attributes -band 1024)) { $f.Delete() }
                } elseif ($it.Filter) {
                    Clear-TISafeFolder -Path ([string]$it.Path) -Like ([string]$it.Filter) -TopOnly
                } else {
                    Clear-TISafeFolder -Path ([string]$it.Path)
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
    } finally {
        if ($wuStopped) { Restore-TIWuService }
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
# Scope: 'Máquina' (HKLM, todos os usuários) ou 'Usuário' (HKCU da conta
# que abriu o TI Suite).
# ---------------------------------------------------------------------
# InstallDate do registro: quase sempre aaaammdd; alguns instaladores gravam
# aaaa-mm-dd ou m/d/aaaa. Data inválida ou no futuro vira $null.
function ConvertFrom-TIInstallDate {
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if (-not $t) { return $null }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $d = [datetime]::MinValue
    foreach ($fmt in @('yyyyMMdd', 'yyyy-MM-dd', 'M/d/yyyy', 'd/M/yyyy', 'd.M.yyyy')) {
        if ([datetime]::TryParseExact($t, $fmt, $inv, [System.Globalization.DateTimeStyles]::None, [ref]$d)) {
            if ($d.Year -ge 1990 -and $d -le (Get-Date).AddDays(1)) { return $d }
            return $null
        }
    }
    return $null
}

function Get-TIInstalledApps {
    Emit 'Lendo os programas instalados...' 'Info'
    $rows = New-Object System.Collections.ArrayList
    $seen = @{}
    $hives = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';             Scope = 'Máquina' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Scope = 'Máquina' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';             Scope = 'Usuário' }
    )
    $hidden = 0
    foreach ($hive in $hives) {
        if (-not (Test-Path $hive.Path)) { continue }
        $scope = $hive.Scope
        Get-ChildItem -Path $hive.Path -ErrorAction SilentlyContinue | ForEach-Object {
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
                $cleanName = $name.Trim()
                # Nada fica travado: runtime essencial ou antivírus/segurança só recebe a marca
                # "Sensitive", para avisar na confirmação. Tudo pode entrar no lote (pedido do técnico).
                $lock = Get-TIAppBatchLock -Name $cleanName -Publisher ([string]$p.Publisher)
                [void]$rows.Add([pscustomobject]@{
                    Name = $cleanName; Version = [string]$p.DisplayVersion; Publisher = [string]$p.Publisher
                    Size = $size; InstallDate = (ConvertFrom-TIInstallDate ([string]$p.InstallDate)); Scope = $scope
                    Uninstall = $uninst; Quiet = [string]$p.QuietUninstallString; Key = $_.PSPath
                    InstallLocation = [string]$p.InstallLocation; Icon = [string]$p.DisplayIcon
                    Locked = $false; Sensitive = [bool]$lock.Locked; LockReason = [string]$lock.Reason
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

# Código de saída do desinstalador em linguagem simples (Windows Installer e a
# maioria dos instaladores seguem os mesmos números). Ok = não é falha.
function Get-TIUninstallCodeInfo {
    param([int]$Code)
    $ok = $false; $reboot = $false
    $txt = switch ($Code) {
        0    { $ok = $true; '' }
        3010 { $ok = $true; $reboot = $true; 'O Windows pede reinício para concluir a remoção (código 3010).' }
        1641 { $ok = $true; $reboot = $true; 'O desinstalador mandou reiniciar o Windows para concluir (código 1641).' }
        1614 { $ok = $true; 'O Windows Installer informa que o programa já foi removido (código 1614).' }
        1605 { 'O Windows Installer informa que o programa já não está instalado (código 1605): a entrada ficou esquecida na lista.' }
        1602 { 'A desinstalação foi cancelada na janela do desinstalador (código 1602).' }
        1603 { 'Erro grave durante a desinstalação (código 1603): feche o programa, reinicie o PC e tente de novo.' }
        1618 { 'Outra instalação está em andamento (código 1618), talvez o Windows Update: espere terminar e tente de novo.' }
        1612 { 'O instalador original não foi encontrado (código 1612): use o instalador do fabricante.' }
        1619 { 'O pacote de instalação não foi encontrado (código 1619): use o instalador do fabricante.' }
        1625 { 'Uma política do Windows bloqueou a desinstalação (código 1625).' }
        5    { 'Acesso negado (código 5): o desinstalador precisa de administrador.' }
        default { ('O desinstalador terminou com o código {0}.' -f $Code) }
    }
    return [pscustomobject]@{ Ok = $ok; Reboot = $reboot; Text = [string]$txt }
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
    try { $p = Start-Process @sp }
    catch {
        throw ('o desinstalador não abriu ({0}): {1} Se o arquivo não existe mais, a entrada ficou esquecida na lista.' -f $plan.Exe, $_.Exception.Message)
    }
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

    $info = Get-TIUninstallCodeInfo -Code $code

    # Conferência: a entrada de desinstalação deve sumir do registro.
    # Programa que continua na lista é falha (Emit 'Error'): a auditoria
    # registra ERRO e o aviso fica vermelho, em vez de "concluída".
    Start-Sleep -Milliseconds 800
    $still = [bool]($App.Key -and (Test-Path -LiteralPath $App.Key))
    if (-not $still) {
        Emit ('{0} desinstalado.' -f $App.Name) 'Success'
        if ($info.Text) { Emit $info.Text 'Warn' }
        return [pscustomobject]@{ Removed = $true; Reboot = $info.Reboot; Code = $code; Message = $info.Text }
    }
    if ($info.Reboot) {
        $msg = ('{0}: {1} Ele sai da lista depois do reinício.' -f $App.Name, $info.Text)
        Emit $msg 'Warn'
        return [pscustomobject]@{ Removed = $false; Reboot = $true; Code = $code; Message = $msg }
    }
    if (-not $info.Ok) {
        $msg = ('{0} continua instalado. {1}' -f $App.Name, $info.Text)
    } elseif (-not $plan.Silent) {
        $msg = ('{0} continua instalado: a janela do desinstalador foi fechada ou cancelada antes do fim. Repita e conclua as etapas.' -f $App.Name)
    } else {
        $msg = ('{0} continua instalado: o desinstalador terminou sem remover (código {1}). Reinicie o PC e repita, ou use o Painel de Controle.' -f $App.Name, $code)
    }
    Emit $msg 'Error'
    return [pscustomobject]@{ Removed = $false; Reboot = $false; Code = $code; Message = $msg }
}

# ---------------------------------------------------------------------
# Desinstalação em lote (conveniência): funções puras testadas no
# dev\Test-Logic.ps1, SEM acessar o disco. As que mexem em processos e
# serviços (Parte B) e a que roda o lote vêm logo depois.
# ---------------------------------------------------------------------

# Normaliza um caminho só para COMPARAÇÃO (não acessa o disco): barras viram
# "\", colapsa barras repetidas, tira aspas e a barra final. Preserva o "\\"
# inicial de caminhos de rede (UNC).
function ConvertTo-TINormPath {
    param([string]$Path)
    $p = ([string]$Path).Trim()
    if (-not $p) { return '' }
    $p = $p.Trim('"').Trim()
    if (-not $p) { return '' }
    $p = $p.Replace('/', '\')
    $unc = $p.StartsWith('\\')
    while ($p.Contains('\\')) { $p = $p.Replace('\\', '\') }
    if ($unc) { $p = '\' + $p }
    return $p.TrimEnd('\')
}

# Pasta-pai de um caminho ('' quando não há separador)
function Get-TIParentFolder {
    param([string]$Path)
    $p = ConvertTo-TINormPath $Path
    if (-not $p) { return '' }
    $idx = $p.LastIndexOf('\')
    if ($idx -le 0) { return '' }
    return $p.Substring(0, $idx)
}

# Regra "o caminho do executável está DENTRO da pasta?" (comparação segura, sem
# disco): igual à pasta ou começando por "pasta\". Não confunde C:\App com C:\App2.
function Test-TIPathInside {
    param([string]$Child, [string]$Folder)
    $c = ConvertTo-TINormPath $Child
    $f = ConvertTo-TINormPath $Folder
    if (-not $c -or -not $f) { return $false }
    if ($c.Equals($f, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $c.StartsWith($f + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

# A pasta do programa é específica o bastante para ali encerrar processos e
# parar serviços? Recusa pastas amplas (raiz de unidade, C:\Program Files) e
# tudo dentro do Windows/System32 ou em WindowsApps (Microsoft Store).
function Test-TIKillableFolder {
    param([string]$Folder, [string]$WinDir = 'C:\Windows')
    $f = ConvertTo-TINormPath $Folder
    if (-not $f) { return $false }
    $parts = @($f -split '\\' | Where-Object { $_ -ne '' })
    if ($parts.Count -lt 3) { return $false }   # precisa de unidade + 2 níveis
    $win = ConvertTo-TINormPath $WinDir
    if ($win -and (Test-TIPathInside -Child $f -Folder $win)) { return $false }
    if ($f -match '(?i)(^|\\)windows(\\|$)') { return $false }
    if ($f -match '(?i)(^|\\)windowsapps(\\|$)') { return $false }
    return $true
}

# Pasta de instalação do programa (sem acessar o disco): InstallLocation; na
# falta dela, a pasta do executável do UninstallString; por último, do
# DisplayIcon (que pode trazer ",índice" no fim).
function Get-TIAppFolder {
    param([string]$InstallLocation = '', [string]$Uninstall = '', [string]$Icon = '')
    $loc = ([string]$InstallLocation).Trim().Trim('"').Trim()
    if ($loc) { return (ConvertTo-TINormPath $loc) }
    $exe = (Split-TICommandLine ([string]$Uninstall)).Exe
    $dir = Get-TIParentFolder $exe
    if ($dir) { return $dir }
    $ic = ([string]$Icon) -replace ',\s*-?\d+\s*$', ''
    $dir = Get-TIParentFolder $ic
    if ($dir) { return $dir }
    return ''
}

# Produto de antivírus/segurança: desinstalar só com a ferramenta do fabricante.
# Detecta pelo nome e pelo editor (nomes em ASCII, sem distinção de acento).
function Test-TISecurityProduct {
    param([string]$Name, [string]$Publisher)
    $hay = ('{0} {1}' -f [string]$Name, [string]$Publisher).ToLowerInvariant()
    return [bool]($hay -match 'defender|kaspersky|\beset\b|nod32|\bavast\b|\bavg\b|norton|symantec|mcafee|bitdefender|sophos|trend ?micro|malwarebytes')
}

# Runtime essencial do qual outros programas dependem: fica fora do lote.
function Test-TIEssentialRuntime {
    param([string]$Name, [string]$Publisher)
    $hay = ('{0} {1}' -f [string]$Name, [string]$Publisher).ToLowerInvariant()
    if ($hay -match 'visual c\+\+.*redistributab') { return $true }
    if ($hay -match '\.net (framework|core|runtime|host)|microsoft \.net|windows desktop runtime|asp\.net core') { return $true }
    if ($hay -match 'windows app runtime|windowsappruntime') { return $true }
    if ($hay -match 'webview2') { return $true }
    return $false
}

# Trava de lote: segurança (ferramenta do fabricante) ou runtime essencial.
# Componentes de sistema e atualizações já saem antes (Get-TIInstalledApps).
function Get-TIAppBatchLock {
    param([string]$Name, [string]$Publisher)
    if (Test-TISecurityProduct -Name $Name -Publisher $Publisher) {
        return [pscustomobject]@{ Locked = $true; Reason = 'use a ferramenta oficial do fabricante' }
    }
    if (Test-TIEssentialRuntime -Name $Name -Publisher $Publisher) {
        return [pscustomobject]@{ Locked = $true; Reason = 'outros programas dependem dele' }
    }
    return [pscustomobject]@{ Locked = $false; Reason = '' }
}

# Texto do resumo da desinstalação em lote (no card e no console), por programa:
# Desinstalado / Não desinstalado (com o motivo) / Cancelado.
function Get-TIUninstallSummaryText {
    param($Results)
    $all  = @($Results | Where-Object { $_ })
    $done = @($all | Where-Object { $_.Status -eq 'removed' })
    $fail = @($all | Where-Object { $_.Status -eq 'failed' })
    $canc = @($all | Where-Object { $_.Status -eq 'cancelled' })
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add(('Desinstalados: {0}' -f $done.Count))
    foreach ($r in $done) {
        [void]$lines.Add(('  - {0}{1}' -f $r.Name, $(if ($r.Reboot) { ' (reinício pendente)' } else { '' })))
    }
    [void]$lines.Add(('Não desinstalados: {0}' -f $fail.Count))
    foreach ($r in $fail) {
        $why = if ($r.Message) { [string]$r.Message } else { 'motivo não informado' }
        [void]$lines.Add(('  - {0}: {1}' -f $r.Name, $why))
    }
    if ($canc.Count -gt 0) {
        [void]$lines.Add(('Cancelados: {0}' -f $canc.Count))
        foreach ($r in $canc) { [void]$lines.Add(('  - {0}' -f $r.Name)) }
    }
    return ($lines -join "`n")
}

# PARTE B: antes de desinstalar, encerra os componentes DAQUELE programa para os
# arquivos não ficarem presos — sempre DENTRO da pasta de instalação dele. Fecha
# janelas e encerra os processos cujo executável está na pasta (primeiro
# CloseMainWindow; se seguir aberto, Kill) e para os serviços cujo binário está
# na pasta (a desinstalação remove o serviço). Nunca toca em nada fora da pasta,
# nem no Windows/System32/WindowsApps.
function Close-TIAppComponents {
    param([string]$Folder, [string]$Name = '')
    $win = Get-TIWinDir
    if (-not (Test-TIKillableFolder -Folder $Folder -WinDir $win)) {
        Emit ('  Sem pasta de instalação confiável para {0}: nada foi encerrado antes.' -f $Name) 'Debug'
        return
    }
    if (-not (Test-Path -LiteralPath $Folder)) {
        Emit ('  A pasta de {0} não existe mais: nada para encerrar.' -f $Name) 'Debug'
        return
    }

    # Serviços cujo binário está na pasta (sem -Force: não derruba dependentes de fora)
    try {
        foreach ($svc in @(Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue)) {
            $exe = (Split-TICommandLine ([string]$svc.PathName)).Exe
            if (-not $exe) { continue }
            if (-not (Test-TIPathInside -Child $exe -Folder $Folder)) { continue }
            if (Test-TIPathInside -Child $exe -Folder $win) { continue }
            if ([string]$svc.State -ne 'Running' -and [string]$svc.State -ne 'Paused') { continue }
            try {
                Stop-Service -Name ([string]$svc.Name) -ErrorAction Stop
                Emit ('  Serviço parado: {0}' -f $svc.Name) 'Debug'
            } catch {
                Emit ('  Não deu para parar o serviço {0}: {1}' -f $svc.Name, $_.Exception.Message) 'Debug'
            }
        }
    } catch { }

    # Processos cujo executável está na pasta
    $toKill = New-Object System.Collections.ArrayList
    try {
        foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
            if ($proc.Id -eq $PID) { continue }
            $path = $null
            try { $path = [string]$proc.MainModule.FileName } catch { }
            if (-not $path) { try { $path = [string]$proc.Path } catch { } }
            if (-not $path) { continue }
            if (-not (Test-TIPathInside -Child $path -Folder $Folder)) { continue }
            if (Test-TIPathInside -Child $path -Folder $win) { continue }
            try { if ($proc.MainWindowHandle -ne [System.IntPtr]::Zero) { [void]$proc.CloseMainWindow() } } catch { }
            [void]$toKill.Add($proc)
        }
    } catch { }

    if ($toKill.Count -gt 0) {
        # dá um tempo para as janelas fecharem sozinhas depois do CloseMainWindow
        $deadline = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $deadline) {
            $alive = @($toKill | Where-Object { try { -not $_.HasExited } catch { $false } })
            if ($alive.Count -eq 0) { break }
            Start-Sleep -Milliseconds 300
        }
        foreach ($proc in $toKill) {
            try {
                if (-not $proc.HasExited) {
                    $proc.Kill()
                    Emit ('  Processo encerrado: {0}' -f $proc.ProcessName) 'Debug'
                } else {
                    Emit ('  Janela fechada: {0}' -f $proc.ProcessName) 'Debug'
                }
            } catch {
                Emit ('  Não deu para encerrar {0}: {1}' -f $proc.ProcessName, $_.Exception.Message) 'Debug'
            }
        }
    }
}

# PARTE A: desinstala vários programas, um a um. Para cada um, encerra antes os
# componentes dele (Parte B) e usa o modo silencioso quando conhecido (quem
# decide é Get-TIUninstallPlan). Devolve um objeto com os resultados por programa.
function Uninstall-TIAppBatch {
    param($Apps)
    $apps = @($Apps | Where-Object { $_ -and $_.PSObject.Properties['Name'] })
    $results = New-Object System.Collections.ArrayList
    $total = $apps.Count
    if ($total -gt 0) {
        $i = 0
        foreach ($app in $apps) {
            $i++
            $name = [string]$app.Name
            # Runtime/antivírus não trava mais: avisa, mas desinstala assim mesmo (pedido do técnico).
            $lock = Get-TIAppBatchLock -Name $name -Publisher ([string]$app.Publisher)
            if ($lock.Locked) { Emit ('{0}: atenção, {1}. Desinstalando mesmo assim.' -f $name, $lock.Reason) 'Warn' }
            Emit ('Programa {0} de {1}: {2}' -f $i, $total, $name) 'Info' ([int](100 * $i / $total))

            # Parte B: encerra os componentes do programa (dentro da pasta dele)
            $folder = Get-TIAppFolder -InstallLocation ([string]$app.InstallLocation) -Uninstall ([string]$app.Uninstall) -Icon ([string]$app.Icon)
            if ($folder) { Close-TIAppComponents -Folder $folder -Name $name }

            $res = $null
            try {
                $res = Uninstall-TIApp -App $app
            } catch {
                $msg = $_.Exception.Message
                Emit ('{0}: {1}' -f $name, $msg) 'Error'
                [void]$results.Add([pscustomobject]@{ Name = $name; Status = 'failed'; Reboot = $false; Code = $null; Message = $msg })
                continue
            }
            $status = 'failed'
            if ($res.Removed) { $status = 'removed' }
            elseif ($res.Reboot) { $status = 'removed' }
            elseif ([int]$res.Code -eq 1602) { $status = 'cancelled' }
            [void]$results.Add([pscustomobject]@{
                Name = $name; Status = $status; Reboot = [bool]$res.Reboot; Code = $res.Code; Message = [string]$res.Message
            })
        }
    } else {
        Emit 'Nenhum programa marcado.' 'Warn'
    }

    $summary = Get-TIUninstallSummaryText -Results $results
    foreach ($line in ($summary -split "`n")) { Emit $line 'Info' }
    return [pscustomobject]@{
        Kind      = 'UninstallBatch'
        Results   = $results.ToArray()
        Summary   = $summary
        Done      = @($results | Where-Object { $_.Status -eq 'removed' }).Count
        Fail      = @($results | Where-Object { $_.Status -eq 'failed' }).Count
        Cancelled = @($results | Where-Object { $_.Status -eq 'cancelled' }).Count
        Reboot    = (@($results | Where-Object { $_.Reboot }).Count -gt 0)
    }
}

# ---------------------------------------------------------------------
# Senha padrão em lote: nunca mexe em administrador nem na conta em uso.
# Sem conseguir ler o grupo Administradores, não altera nada (falha fechado).
# ---------------------------------------------------------------------

# "Exigir troca de senha no próximo login": PasswordExpired = 1 pelo ADSI (a
# saída do net.exe é traduzida e o código 0 dele não prova nada). O Windows
# IGNORA a exigência quando a senha está como "nunca expira" (o lusrmgr avisa
# isso), então essa opção sai antes. Efeito inevitável: a conta passa a seguir
# a validade de senha do Windows (padrão: 42 dias).
function Set-TIMustChangePassword {
    param([string]$User)
    $u = Get-LocalUser -Name $User -ErrorAction Stop
    Set-LocalUser -Name $User -PasswordNeverExpires $false -ErrorAction Stop
    if (-not $u.UserMayChangePassword) { Set-LocalUser -Name $User -UserMayChangePassword $true -ErrorAction Stop }
    $flag = $null
    $flags = 0
    $de = [ADSI]('WinNT://{0}/{1},user' -f $env:COMPUTERNAME, $User)
    try {
        $de.Put('PasswordExpired', 1)
        $de.SetInfo()
        $de.RefreshCache()
        try { $flag = [int]$de.InvokeGet('PasswordExpired') } catch { }
        try { $flags = [int]$de.InvokeGet('UserFlags') } catch { }
    } finally { $de.Dispose() }
    if ($flags -band 0x10000) { throw 'a senha continua marcada como "nunca expira".' }
    if ($null -ne $flag -and $flag -ne 1) { throw 'o Windows não confirmou a exigência de troca.' }
}

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
    $okN = 0; $failN = 0; $noForce = 0
    $i = 0
    foreach ($u in $users) {
        $i++
        Emit ('Aplicando a senha padrão em {0} ({1}/{2})...' -f $u.Name, $i, $users.Count) 'Info' ([int](100 * $i / [Math]::Max(1, $users.Count)))
        try {
            $sec = ConvertTo-SecureString $Password -AsPlainText -Force
            Set-LocalUser -Name $u.Name -Password $sec -ErrorAction Stop
            $okN++
        } catch { $failN++; Emit ('Falha em {0}: {1}' -f $u.Name, $_.Exception.Message) 'Error'; continue }
        if ($ForceChange) {
            try { Set-TIMustChangePassword -User $u.Name }
            catch {
                $noForce++
                Emit ('Senha aplicada em {0}, mas não deu para exigir a troca no próximo login: {1}' -f $u.Name, $_.Exception.Message) 'Error'
            }
        }
    }
    $sumTxt = ('Senha padrão: {0} conta(s) alterada(s), {1} falha(s).' -f $okN, $failN)
    if ($ForceChange -and $okN -gt 0) {
        if ($noForce -gt 0) { $sumTxt += (' A troca no próximo login não ficou valendo em {0} conta(s).' -f $noForce) }
        else { $sumTxt += ' Cada uma vai pedir uma senha nova no próximo login.' }
    }
    Emit $sumTxt $(if ($failN -gt 0 -or $noForce -gt 0) { 'Warn' } else { 'Success' })
    return ([pscustomobject]@{ Ok = $okN; Fail = $failN; NoForce = $noForce })
}

# ---------------------------------------------------------------------
# Programas de linha de comando com tempo limite (netsh e ipconfig podem
# travar com driver ruim). Saída lida na página de código OEM do console,
# como o próprio cmd mostra. Code = -1 quando não abriu ou estourou o tempo.
# ---------------------------------------------------------------------
function Invoke-TICommand {
    param([string]$File, [string]$Arguments = '', [int]$TimeoutSec = 30)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    try {
        $enc = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        $psi.StandardOutputEncoding = $enc
        $psi.StandardErrorEncoding = $enc
    } catch { }
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) }
    catch { return [pscustomobject]@{ Code = -1; Output = $_.Exception.Message; TimedOut = $false } }
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    # Espera em fatias curtas: o botão Cancelar consegue interromper
    while (-not $p.WaitForExit(250)) {
        if ((Get-Date) -gt $deadline) {
            try { $p.Kill() } catch { }
            return [pscustomobject]@{ Code = -1; Output = ''; TimedOut = $true }
        }
    }
    $p.WaitForExit()
    $out = ''
    try { $out = [string]$outTask.Result + [string]$errTask.Result } catch { }
    return [pscustomobject]@{ Code = [int]$p.ExitCode; Output = $out; TimedOut = $false }
}

# Última linha com texto (mensagem final do netsh/ipconfig)
function Get-TIOutputTail {
    param([string]$Text)
    $l = @(([string]$Text -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($l.Count -eq 0) { return '' }
    return $l[-1]
}

# ---------------------------------------------------------------------
# Rede: uma consulta de cada tipo (endereços, rotas padrão, DNS), juntadas
# por placa. Get-NetIPConfiguration por placa levava de 0,3 a 1 s cada.
# ---------------------------------------------------------------------
function Get-TINetInfo {
    $adapters = @()
    try { $adapters = @(Get-NetAdapter -ErrorAction Stop) } catch { Emit ('Não foi possível listar as placas de rede: {0}' -f $_.Exception.Message) 'Warn' }
    $ips = @{}; $gws = @{}; $dns = @{}; $ifMetric = @{}; $conflict = @{}
    try {
        foreach ($x in @(Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop)) {
            $st = [string]$x.AddressState
            if ($st -eq 'Tentative' -or $st -eq 'Invalid') { continue }
            $k = [int]$x.InterfaceIndex
            if (-not $ips.ContainsKey($k)) { $ips[$k] = New-Object System.Collections.ArrayList }
            if (-not $ips[$k].Contains([string]$x.IPAddress)) { [void]$ips[$k].Add([string]$x.IPAddress) }
            if ($st -eq 'Duplicate') { $conflict[$k] = $true }
        }
    } catch { }
    try {
        foreach ($x in @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction Stop)) { $ifMetric[[int]$x.InterfaceIndex] = [int64]$x.InterfaceMetric }
    } catch { }
    try {
        foreach ($x in @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -PolicyStore ActiveStore -ErrorAction Stop)) {
            $hop = [string]$x.NextHop
            if (-not $hop -or $hop -eq '0.0.0.0') { continue }
            $k = [int]$x.InterfaceIndex
            # Métrica efetiva = rota + interface: é assim que o Windows escolhe a saída
            $m = [int64]$x.RouteMetric
            if ($ifMetric.ContainsKey($k)) { $m += $ifMetric[$k] }
            if (-not $gws.ContainsKey($k)) { $gws[$k] = New-Object System.Collections.ArrayList }
            [void]$gws[$k].Add([pscustomobject]@{ Hop = $hop; Metric = $m })
        }
    } catch { }
    try {
        foreach ($x in @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop)) {
            $list = @($x.ServerAddresses | Where-Object { $_ })
            if ($list.Count -gt 0) { $dns[[int]$x.InterfaceIndex] = $list }
        }
    } catch { }

    $out = New-Object System.Collections.ArrayList
    foreach ($a in $adapters) {
        $k = [int]$a.ifIndex
        $ipList = @(); if ($ips.ContainsKey($k)) { $ipList = @($ips[$k]) }
        $gwList = @(); $metric = [int64]::MaxValue
        if ($gws.ContainsKey($k)) {
            $sorted = @($gws[$k] | Sort-Object Metric)
            $gwList = @($sorted | ForEach-Object { $_.Hop } | Select-Object -Unique)
            $metric = $sorted[0].Metric
        }
        $real = @($ipList | Where-Object { $_ -notlike '169.254.*' })
        # Placa física x virtual (Hyper-V, WSL, VirtualBox, VPN)
        $phys = $true
        if ($a.PSObject.Properties['HardwareInterface'] -and $null -ne $a.HardwareInterface) { $phys = [bool]$a.HardwareInterface }
        if ($a.PSObject.Properties['Virtual'] -and [bool]$a.Virtual) { $phys = $false }
        $isWifi = ([string]$a.PhysicalMediaType -match '802\.11' -or [string]$a.NdisPhysicalMedium -eq '9' -or
                   [string]$a.InterfaceDescription -match '(?i)wi-?fi|wireless|wlan|802\.11')
        $bps = 0.0
        try { if ($null -ne $a.Speed) { $bps = [double]$a.Speed } } catch { }
        [void]$out.Add([pscustomobject]@{
            Index    = $k
            Name     = [string]$a.Name
            Desc     = [string]$a.InterfaceDescription
            Status   = [string]$a.Status
            Up       = ([string]$a.Status -eq 'Up')
            Physical = $phys
            Wifi     = $isWifi
            Mac      = [string]$a.MacAddress
            LinkSpeed= [string]$a.LinkSpeed
            SpeedBps = $bps
            Ips      = $ipList
            Gateways = $gwList
            Dns      = @($dns[$k] | Where-Object { $_ })
            Metric   = $metric
            Apipa    = ($ipList.Count -gt 0 -and $real.Count -eq 0)
            Conflict = [bool]$conflict[$k]
        })
    }
    return ($out.ToArray())
}

# Conexão principal: placa ligada com gateway (menor métrica, como o Windows
# escolhe a saída). Sem gateway: a primeira placa física com IPv4, e só depois
# as virtuais (vEthernet, VirtualBox, TAP de VPN), que estão sempre "ligadas".
# Regra pura: recebe o resultado de Get-TINetInfo.
function Select-TIPrimaryNet {
    param($Nets)
    $up = @($Nets | Where-Object { $_ -and $_.Up -and @($_.Ips).Count -gt 0 })
    $withGw = @($up | Where-Object { @($_.Gateways).Count -gt 0 } | Sort-Object Metric, Index)
    if ($withGw.Count -gt 0) { return $withGw[0] }
    $phys = @($up | Where-Object { $_.Physical } | Sort-Object Index)
    if ($phys.Count -gt 0) { return $phys[0] }
    if ($up.Count -gt 0) { return @($up | Sort-Object Index)[0] }
    return $null
}

# ---------------------------------------------------------------------
# Visão geral (Início)
# ---------------------------------------------------------------------
# Nível do espaço livre: absoluto (GB) e percentual. 9% de 1 TB (90 GB) não
# é crítico; 12% de 64 GB (7,6 GB) é pouco até para atualizar o Windows.
# Regra pura: 'crit' | 'warn' | 'ok' | 'none' (sem leitura).
function Get-TIDiskLevel {
    param([double]$Free, [double]$Total)
    if ($Total -le 0) { return 'none' }
    if ($Free -lt 10GB) { return 'crit' }
    if ($Free -lt 20GB -or (100 * $Free / $Total) -lt 10) { return 'warn' }
    return 'ok'
}

function Get-TISystemSnapshot {
    $t = 15
    $os   = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec $t -ErrorAction SilentlyContinue
    $cs   = Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec $t -ErrorAction SilentlyContinue
    $cpu  = @(Get-CimInstance Win32_Processor -OperationTimeoutSec $t -ErrorAction SilentlyContinue) | Select-Object -First 1
    $bios = @(Get-CimInstance Win32_BIOS -OperationTimeoutSec $t -ErrorAction SilentlyContinue) | Select-Object -First 1
    $enc  = @(Get-CimInstance Win32_SystemEnclosure -OperationTimeoutSec $t -ErrorAction SilentlyContinue) | Select-Object -First 1
    $mods = @(Get-CimInstance Win32_PhysicalMemory -OperationTimeoutSec $t -ErrorAction SilentlyContinue)
    $cv   = $null
    try { $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop } catch { }

    # Discos: DriveInfo não depende do WMI (que costuma estar corrompido em PC antigo)
    $sysLetter = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd('\').ToUpperInvariant() } else { 'C:' }
    $sysDisk = $null
    $others = New-Object System.Collections.ArrayList
    try {
        foreach ($d in @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' })) {
            try {
                if (-not $d.IsReady -or $d.TotalSize -le 0) { continue }
                $item = [pscustomobject]@{
                    Letter = $d.Name.TrimEnd('\').ToUpperInvariant(); Label = [string]$d.VolumeLabel
                    Free = [double]$d.AvailableFreeSpace; Total = [double]$d.TotalSize
                    Level = (Get-TIDiskLevel -Free ([double]$d.AvailableFreeSpace) -Total ([double]$d.TotalSize))
                }
                if ($item.Letter -eq $sysLetter) { $sysDisk = $item } else { [void]$others.Add($item) }
            } catch { }
        }
    } catch { }
    $freePct = 0; $freeBytes = 0.0; $totalBytes = 0.0
    if ($sysDisk) {
        $freeBytes = $sysDisk.Free; $totalBytes = $sysDisk.Total
        $freePct = [int](100 * $freeBytes / $totalBytes)
    }

    $uptime = $null
    if ($os -and $os.LastBootUpTime) { $uptime = (Get-Date) - $os.LastBootUpTime }
    # Inicialização rápida: "Desligar" hiberna o núcleo e não zera o tempo ligado
    $fast = $false
    try {
        $hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction Stop).HiberbootEnabled
        $he = $null
        try { $he = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -ErrorAction Stop).HibernateEnabled } catch { }
        $fast = ($hb -eq 1 -and $he -ne 0)
    } catch { }

    $usedMem = 0.0; $totalMem = 0.0
    if ($os) {
        $totalMem = [double]$os.TotalVisibleMemorySize * 1KB
        $freeMem  = [double]$os.FreePhysicalMemory * 1KB
        $usedMem  = $totalMem - $freeMem
    }
    $installed = 0.0
    foreach ($m in $mods) { if ($m.Capacity) { $installed += [double]$m.Capacity } }

    # Série de fábrica inválida ("To be filled by O.E.M.", "Default string") não vale
    $serial = ''
    if ($bios -and $bios.SerialNumber) { $serial = ([string]$bios.SerialNumber).Trim() }
    $asset = ''
    if ($enc -and $enc.SMBIOSAssetTag) { $asset = ([string]$enc.SMBIOSAssetTag).Trim() }
    if (Get-Command Test-TIValidSerial -ErrorAction SilentlyContinue) {
        if (-not (Test-TIValidSerial $serial)) { $serial = '' }
        if (-not (Test-TIValidSerial $asset)) { $asset = '' }
    } else { $asset = '' }

    $domain = ''
    if ($cs) { $domain = $(if ($cs.PartOfDomain) { [string]$cs.Domain } else { 'grupo ' + [string]$cs.Workgroup }) }

    # Quem está conectado no PC (o TI Suite roda elevado com a conta do técnico)
    $who = ''
    if ($cs -and $cs.UserName) { $who = [string]$cs.UserName }
    if (-not $who) {
        # Sessão remota ou campo vazio: dono do explorer.exe
        try {
            foreach ($pr in @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -OperationTimeoutSec $t -ErrorAction Stop)) {
                $o = Invoke-CimMethod -InputObject $pr -MethodName GetOwner -OperationTimeoutSec $t -ErrorAction Stop
                if ($o -and $o.User) { $who = $(if ($o.Domain) { '{0}\{1}' -f $o.Domain, $o.User } else { [string]$o.User }); break }
            }
        } catch { }
    }
    $userName = $who; $userDom = ''
    if ($who -match '^(.+?)\\(.+)$') { $userDom = $Matches[1]; $userName = $Matches[2] }
    if ($userDom -and $userDom -eq $env:COMPUTERNAME) { $userDom = 'conta local' }

    $osName = '-'
    if ($os) { $osName = ([string]$os.Caption) -replace '^Microsoft\s+', '' }
    $disp = ''
    if ($cv) { $disp = [string]$cv.DisplayVersion; if (-not $disp) { $disp = [string]$cv.ReleaseId } }
    $build = '-'
    if ($os) { $build = [string]$os.BuildNumber; if ($cv -and $null -ne $cv.UBR) { $build += '.' + [string]$cv.UBR } }

    $pri = Select-TIPrimaryNet @(Get-TINetInfo)
    $ip = ''
    if ($pri) { $ip = [string](@($pri.Ips | Where-Object { $_ -notlike '169.254.*' }) + @($pri.Ips) | Select-Object -First 1) }

    Emit 'Dados do sistema coletados.' 'Debug'

    return [pscustomobject]@{
        Computer    = $env:COMPUTERNAME
        Domain      = $domain
        User        = $userName
        UserDomain  = $userDom
        Operator    = $env:USERNAME
        Model       = $(if ($cs) { ('{0} {1}' -f ([string]$cs.Manufacturer).Trim(), ([string]$cs.Model).Trim()).Trim() } else { '' })
        Serial      = $serial
        AssetTag    = $asset
        OsName      = $osName
        OsVersion   = $disp
        OsBuild     = $build
        Cpu         = $(if ($cpu) { (((([string]$cpu.Name) -split '@')[0]).Trim() -replace '\s{2,}', ' ') } else { '' })
        Uptime      = $uptime
        FastStartup = $fast
        DiskLetter  = $sysLetter
        DiskFree    = $freeBytes
        DiskTotal   = $totalBytes
        DiskFreePct = $freePct
        DiskLevel   = (Get-TIDiskLevel -Free $freeBytes -Total $totalBytes)
        OtherDisks  = @($others.ToArray() | Sort-Object Letter)
        MemUsed     = $usedMem
        MemTotal    = $totalMem
        MemInstalled= $installed
        Adapter     = $(if ($pri) { $pri.Name } else { '' })
        AdapterDesc = $(if ($pri) { $pri.Desc } else { '' })
        Mac         = $(if ($pri) { $pri.Mac } else { '' })
        Ip          = $ip
        Gateway     = $(if ($pri) { (@($pri.Gateways) | Select-Object -First 1) } else { '' })
        Dns         = $(if ($pri) { (@($pri.Dns) -join ', ') } else { '' })
        Apipa       = $(if ($pri) { [bool]$pri.Apipa } else { $false })
        NoGateway   = $(if ($pri) { @($pri.Gateways).Count -eq 0 } else { $false })
        IpConflict  = $(if ($pri) { [bool]$pri.Conflict } else { $false })
    }
}

# ---------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------
# Conclusão do teste de conexão em linguagem simples. Regra pura (testável):
# Http = 'ok' | 'portal' (redirecionado/filtrado) | 'proxyauth' (407) | 'fail'.
function Get-TINetVerdict {
    param(
        [bool]$HasIp, [bool]$Apipa, [bool]$HasGateway, [bool]$GatewayOk, [bool]$PublicOk,
        [int]$DnsTotal = 0, [int]$DnsOkCount = 0, [string[]]$DnsFailed = @(), [string]$Http = 'fail'
    )
    $v = { param($t, $tone) [pscustomobject]@{ Text = $t; Tone = $tone } }
    if (-not $HasIp) { return (& $v 'Sem conexão: nenhuma placa de rede está conectada. Confira o cabo ou o Wi-Fi.' 'crit') }
    if ($Apipa) { return (& $v 'O servidor DHCP não respondeu (IP automático 169.254): confira o cabo, o Wi-Fi e o switch; depois use Renovar endereço IP.' 'crit') }
    if ($Http -eq 'ok') {
        if ($DnsTotal -gt 0 -and $DnsOkCount -lt $DnsTotal) {
            $which = (@($DnsFailed | Where-Object { $_ }) -join ', ')
            if (-not $which) { $which = 'configurado' }
            return (& $v ('A internet funciona, mas o DNS {0} não responde: corrija os servidores DNS da placa (sites podem demorar ou falhar).' -f $which) 'warn')
        }
        if (-not $PublicOk) { return (& $v 'A internet funciona. A rede só bloqueia o ping (comum em rede escolar): nada a corrigir.' 'ok') }
        if ($HasGateway -and -not $GatewayOk) { return (& $v 'A internet funciona. O roteador só não responde ao ping: nada a corrigir.' 'ok') }
        return (& $v 'Tudo certo: a internet funciona normalmente.' 'ok')
    }
    if ($Http -eq 'portal') { return (& $v 'A rede pede login no navegador (portal de acesso) ou filtra o conteúdo: abra o navegador e faça o login.' 'warn') }
    if ($Http -eq 'proxyauth') { return (& $v 'O proxy da rede exige usuário e senha: faça o login no navegador ou confira o proxy do Windows.' 'warn') }
    if (-not $HasGateway) { return (& $v 'A placa não tem gateway: não há rota para a internet. Confira a configuração de IP (automático/DHCP).' 'crit') }
    if ($PublicOk -and $DnsOkCount -eq 0) { return (& $v 'Há conexão com a internet, mas o DNS não resolve nomes: confira os servidores DNS da placa.' 'crit') }
    if ($PublicOk) { return (& $v 'Há conexão com a internet, mas o acesso a sites falhou: proxy ou firewall bloqueando.' 'warn') }
    if ($GatewayOk -and $DnsOkCount -gt 0) { return (& $v 'A rede local e o DNS respondem, mas a internet não: firewall ou proxy bloqueando.' 'warn') }
    if ($GatewayOk) { return (& $v 'A rede local funciona, mas não sai para a internet: link do provedor ou roteador sem internet.' 'crit') }
    if ($DnsOkCount -gt 0) { return (& $v 'O DNS responde, mas o acesso a sites falhou: proxy ou firewall bloqueando.' 'warn') }
    return (& $v 'O roteador não responde: confira o cabo, o Wi-Fi e o switch (ou reinicie o roteador).' 'crit')
}

function Test-TINetwork {
    $rows = New-Object System.Collections.ArrayList
    $targets = New-Object System.Collections.ArrayList
    $pri = Select-TIPrimaryNet @(Get-TINetInfo)
    $gw = $null
    if ($pri) {
        Emit ('Conexão principal: {0} ({1})' -f $pri.Name, (@($pri.Ips) -join ', ')) 'Info'
        $gw = @($pri.Gateways) | Select-Object -First 1
    }
    if ($gw) { [void]$targets.Add(@{ Label = 'Roteador (gateway)'; Addr = $gw; Gw = $true }) }
    else {
        $why = if (-not $pri) { 'Nenhuma placa conectada' } elseif ($pri.Apipa) { 'O DHCP não respondeu (IP 169.254)' } else { 'A placa não tem gateway configurado' }
        [void]$rows.Add([pscustomobject]@{ Target = 'Roteador (gateway)'; Addr = '-'; Ok = $false; Latency = -1; Detail = $why })
        Emit ('  Roteador: {0}' -f $why) 'Warn'
    }
    [void]$targets.Add(@{ Label = 'Servidor público Google'; Addr = '8.8.8.8'; Gw = $false })
    [void]$targets.Add(@{ Label = 'Servidor público Cloudflare'; Addr = '1.1.1.1'; Gw = $false })

    $gwOk = $false; $pubOk = $false
    $ping = New-Object System.Net.NetworkInformation.Ping
    $i = 0
    foreach ($t in $targets) {
        $i++
        Emit ('Testando {0}...' -f $t.Label) 'Info' ([int](50 * $i / $targets.Count))
        $ok = $false; $ms = -1; $detail = 'Sem resposta ao ping'
        try {
            $res = $ping.Send($t.Addr, 2500)
            if ($res.Status.ToString() -eq 'Success') { $ok = $true; $ms = [int]$res.RoundtripTime; $detail = 'Responde ao ping' }
        } catch { }
        if ($ok) { Emit ('  {0}: {1} ms' -f $t.Label, $ms) 'Success' }
        else     { Emit ('  {0}: sem resposta' -f $t.Label) 'Warn' }
        if ($ok -and $t.Gw) { $gwOk = $true }
        if ($ok -and -not $t.Gw) { $pubOk = $true }
        [void]$rows.Add([pscustomobject]@{ Target = $t.Label; Addr = $t.Addr; Ok = $ok; Latency = $ms; Detail = $detail })
    }
    try { $ping.Dispose() } catch { }

    # DNS: pergunta direto a cada servidor configurado, sem o cache do Windows
    # (DNS manual errado é comum e o cache escondia a falha)
    $name = 'www.microsoft.com'
    $servers = @()
    if ($pri) { $servers = @($pri.Dns) }
    $dnsOkN = 0; $dnsFailed = New-Object System.Collections.ArrayList; $dnsTotal = 0
    $canResolve = [bool](Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)
    if ($servers.Count -gt 0 -and $canResolve) {
        $j = 0
        foreach ($s in @($servers | Select-Object -First 4)) {
            $j++; $dnsTotal++
            Emit ('Testando o servidor DNS {0}...' -f $s) 'Info' (50 + [int](30 * $j / [Math]::Min(4, $servers.Count)))
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $ok = $false; $detail = 'Não respondeu (servidor errado, fora do ar ou bloqueado)'
            try {
                $ans = @(Resolve-DnsName -Name $name -Server $s -Type A -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop |
                         Where-Object { [string]$_.Type -eq 'A' -and $_.IPAddress })
                if ($ans.Count -gt 0) { $ok = $true; $detail = ('Resolveu {0} para {1}' -f $name, $ans[0].IPAddress) }
                else { $detail = 'Respondeu sem nenhum endereço' }
            } catch {
                $fq = [string]$_.FullyQualifiedErrorId
                if ($fq -match 'NAME_ERROR|9003') { $detail = 'Diz que o nome não existe (filtro de DNS ou servidor com defeito)' }
                elseif ($fq -notmatch 'TIMEOUT|1460') { $detail = ('Falhou: {0}' -f $_.Exception.Message) }
            }
            $sw.Stop()
            if ($ok) { $dnsOkN++; Emit ('  DNS {0}: {1} ms' -f $s, [int]$sw.ElapsedMilliseconds) 'Success' }
            else { [void]$dnsFailed.Add([string]$s); Emit ('  DNS {0}: {1}' -f $s, $detail) 'Warn' }
            [void]$rows.Add([pscustomobject]@{ Target = 'Servidor DNS'; Addr = [string]$s; Ok = $ok; Latency = $(if ($ok) { [int]$sw.ElapsedMilliseconds } else { -1 }); Detail = $detail })
        }
    } else {
        # Sem servidor na placa (ou Windows sem Resolve-DnsName): resolvedor do sistema
        Emit 'Testando a resolução de nomes (DNS)...' 'Info' 70
        $dnsTotal = 1
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ok = $false; $detail = $(if ($pri -and $servers.Count -eq 0) { 'Nenhum servidor DNS configurado na placa' } else { 'Não resolveu o nome' })
        try {
            $addrs = @([System.Net.Dns]::GetHostAddresses($name))
            $v4 = @($addrs | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork })
            if ($addrs.Count -gt 0) { $ok = $true; $detail = ('Resolveu para {0}' -f $(if ($v4.Count -gt 0) { $v4[0].ToString() } else { $addrs[0].ToString() })) }
        } catch { }
        $sw.Stop()
        if ($ok) { $dnsOkN = 1; Emit ('  DNS: {0} ms' -f [int]$sw.ElapsedMilliseconds) 'Success' }
        else { [void]$dnsFailed.Add('configurado'); Emit ('  DNS: {0}' -f $detail) 'Warn' }
        [void]$rows.Add([pscustomobject]@{ Target = 'Resolução de nomes (DNS)'; Addr = $name; Ok = $ok; Latency = $(if ($ok) { [int]$sw.ElapsedMilliseconds } else { -1 }); Detail = $detail })
    }

    # HTTP: o teste que o próprio Windows usa (detecta portal de login e proxy)
    Emit 'Testando o acesso à internet (HTTP)...' 'Info' 90
    $url = 'http://www.msftconnecttest.com/connecttest.txt'
    $httpOk = $false; $httpMs = -1; $httpDetail = 'Sem acesso'; $httpKind = 'fail'
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
            $httpKind = 'portal'
        } elseif ($body -match 'Microsoft Connect Test') {
            $httpOk = $true
            $httpDetail = $(if ($viaProxy) { 'Acesso via proxy ' + $viaProxy } else { 'Acesso direto' })
        } else {
            $httpDetail = 'Resposta inesperada (portal de acesso ou filtro de conteúdo)'
            $httpKind = 'portal'
        }
    } catch {
        # Guardar a exceção ANTES do switch: dentro dele, $_ vira o valor testado
        $wex = $_.Exception
        while ($wex -and -not ($wex -is [System.Net.WebException])) { $wex = $wex.InnerException }
        if ($wex) {
            $st = [string]$wex.Status
            $sc = 0
            if ($wex.Response) {
                try { $sc = [int]$wex.Response.StatusCode } catch { }
                try { $wex.Response.Close() } catch { }
            }
            if ($sc -eq 407) { $httpKind = 'proxyauth' }
            elseif ($sc -eq 403 -or $sc -eq 511) { $httpKind = 'portal' }
            $httpDetail = switch ($st) {
                'NameResolutionFailure'      { 'O DNS não resolveu o endereço de teste' }
                'ProxyNameResolutionFailure' { 'O proxy configurado não foi encontrado' }
                'Timeout'                    { 'Tempo esgotado' }
                'ConnectFailure'             { 'Conexão recusada ou bloqueada' }
                'ProtocolError' {
                    if ($sc -eq 407) { 'O proxy exige usuário e senha' }
                    elseif ($sc -eq 403) { 'Acesso negado (403): filtro de conteúdo ou proxy' }
                    elseif ($sc -eq 511) { 'A rede pede login (portal de acesso)' }
                    elseif ($sc -gt 0) { 'Erro HTTP {0}' -f $sc }
                    else { 'O servidor respondeu com erro' }
                }
                { $_ -in @('ReceiveFailure', 'ConnectionClosed', 'KeepAliveFailure', 'PipelineFailure', 'SendFailure') } {
                    'Conexão interrompida no meio (firewall, proxy ou rede instável)'
                }
                { $_ -in @('SecureChannelFailure', 'TrustFailure') } { 'Falha de segurança (TLS ou certificado)' }
                'ProxyAuthenticationRequired' { 'O proxy exige usuário e senha' }
                'RequestCanceled'            { 'O pedido foi cancelado' }
                default                      { ('Falha de conexão ({0})' -f $st) }
            }
            if ($st -eq 'ProxyAuthenticationRequired') { $httpKind = 'proxyauth' }
        } else {
            $m = $_.Exception
            if ($m.InnerException) { $m = $m.InnerException }
            $httpDetail = ('Falha: {0}' -f $m.Message)
        }
    }
    if ($httpOk) { $httpKind = 'ok' }
    [void]$rows.Add([pscustomobject]@{ Target = 'Acesso à internet (HTTP)'; Addr = 'msftconnecttest.com'; Ok = $httpOk; Latency = $httpMs; Detail = $httpDetail })
    if ($httpOk) { Emit ('  Internet: {0}' -f $httpDetail) 'Success' } else { Emit ('  Internet: {0}' -f $httpDetail) 'Warn' }

    $up = @($rows | Where-Object { $_.Ok }).Count
    Emit ('Diagnóstico: {0} de {1} testes OK.' -f $up, $rows.Count) 'Debug'
    $verdict = Get-TINetVerdict -HasIp ([bool]$pri) -Apipa $(if ($pri) { [bool]$pri.Apipa } else { $false }) `
                                -HasGateway ([bool]$gw) -GatewayOk $gwOk -PublicOk $pubOk `
                                -DnsTotal $dnsTotal -DnsOkCount $dnsOkN -DnsFailed @($dnsFailed) -Http $httpKind
    # Achado do teste é aviso, não erro da tarefa (o resumo na tela fica vermelho)
    Emit ('Conclusão: {0}' -f $verdict.Text) $(if ($verdict.Tone -eq 'ok') { 'Success' } else { 'Warn' })
    # Última saída: a conclusão (a tela separa pela propriedade Verdict)
    return (@($rows.ToArray()) + @([pscustomobject]@{ Verdict = $verdict.Text; Tone = $verdict.Tone }))
}

# Conectadas primeiro (Status vem como texto: a ordem alfabética punha
# "Up" por último), depois desconectadas, desativadas e o resto.
function Get-TIAdapters {
    $rank = @{ 'Up' = 0; 'Disconnected' = 1; 'Disabled' = 2 }
    $nets = @(Get-TINetInfo | Sort-Object @{ Expression = { if ($rank.ContainsKey([string]$_.Status)) { $rank[[string]$_.Status] } else { 3 } } }, Name)
    $rows = New-Object System.Collections.ArrayList
    foreach ($n in $nets) {
        $speed = ''
        if ($n.Up -and $n.LinkSpeed -and $n.LinkSpeed -notmatch '^0\s') { $speed = $n.LinkSpeed }
        [void]$rows.Add([pscustomobject]@{
            Name     = $n.Name
            Desc     = $n.Desc
            Status   = $n.Status
            Speed    = $speed
            SpeedBps = $(if ($speed) { $n.SpeedBps } else { 0.0 })
            Mac      = $n.Mac
            Ip       = (@($n.Ips) -join ', ')
            Gateway  = (@($n.Gateways) -join ', ')
            Dns      = (@($n.Dns) -join ', ')
            Physical = $n.Physical
            Apipa    = $n.Apipa
            Conflict = $n.Conflict
            # Placa física ligada, com IP de verdade e sem gateway: sem rota para a internet
            NoGateway = ($n.Up -and $n.Physical -and -not $n.Apipa -and @($n.Ips).Count -gt 0 -and @($n.Gateways).Count -eq 0)
        })
    }
    if ($rows.Count -eq 0) { Emit 'Nenhum adaptador de rede encontrado.' 'Warn' }
    return ($rows.ToArray())
}

# Lê a saída do "netsh wlan show interfaces" em português OU inglês.
# Casa pelo começo do rótulo (sem acento), então sobrevive a erro de codificação.
# A ordem do mapa é a ordem na tela. Linhas de aviso vêm com Note = $true.
function ConvertFrom-TIWifiText {
    param([string]$Text)
    $map = @(
        @{ Rx = '^(Estado|State)$';                L = 'Estado' },
        @{ Rx = '^SSID$';                          L = 'Rede (SSID)' },
        @{ Rx = '^(Sinal|Signal)$';                L = 'Sinal' },
        @{ Rx = '^(AP\s+)?BSSID$';                 L = 'Ponto de acesso' },
        @{ Rx = '^(Canal|Channel)$';               L = 'Canal' },
        @{ Rx = '^(Banda|Band)$';                  L = 'Banda' },
        @{ Rx = '^(Tipo de r.{1,2}dio|Radio type)'; L = 'Padrão' },
        @{ Rx = '^(Autentica|Authentication)';     L = 'Segurança' },
        @{ Rx = '^(Taxa de recep|Receive rate)';   L = 'Recepção (Mbps)' },
        @{ Rx = '^(Taxa de transm|Transmit rate)'; L = 'Transmissão (Mbps)' },
        @{ Rx = '^(Perfil|Profile)$';              L = 'Perfil salvo' }
    )
    # Windows 11 24H2+: sem a Localização ligada, o netsh só devolve um aviso
    $needLoc = ([string]$Text -match '(?i)privacy-location|location permission|permiss\S{1,4}o de localiza|servi\S{1,4}os de localiza')
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
    if ($needLoc) {
        [void]$rows.Add([pscustomobject]@{ Label = 'Localização'; Tone = 'warn'; Note = $true
            Value = 'O Windows só mostra os dados do Wi-Fi com a Localização ligada: Configurações > Privacidade e segurança > Localização (ligue também "Permitir que aplicativos da área de trabalho acessem sua localização").' })
    }
    if ($found.Count -eq 0) {
        if (-not $needLoc) {
            $msg = 'Nenhuma interface sem fio encontrada (ou o serviço WLAN está parado)'
            if ([string]$Text -match '(?i)wlansvc') { $msg = 'O serviço de Wi-Fi do Windows (Configuração Automática de WLAN) está parado.' }
            [void]$rows.Add([pscustomobject]@{ Label = 'Wi-Fi'; Value = $msg; Tone = 'dim'; Note = $true })
        }
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
        [void]$rows.Add([pscustomobject]@{ Label = $m.L; Value = $v; Tone = $tone; Note = $false })
    }
    return ($rows.ToArray())
}

# Nomes das redes salvas no "netsh wlan show profiles" (português ou inglês):
# linhas "rótulo : nome" recuadas, depois da linha de traços da seção de perfis.
function ConvertFrom-TIWifiProfiles {
    param([string]$Text)
    $names = New-Object System.Collections.ArrayList
    $afterDash = $false
    foreach ($line in ([string]$Text -split "`r?`n")) {
        if ($line -match '^\s*-{3,}\s*$') { $afterDash = $true; continue }
        if (-not $afterDash) { continue }
        if ($line -match '^\s+[^:]+?\s*:\s*(.+?)\s*$') {
            $n = $Matches[1]
            if ($n -and -not $names.Contains($n)) { [void]$names.Add($n) }
        }
    }
    return ($names.ToArray())
}

# Linhas Label/Value/Tone para a tela e, no fim, as redes salvas (objetos com Profile)
function Get-TIWifiInfo {
    $rows = New-Object System.Collections.ArrayList
    $r = Invoke-TICommand -File 'netsh.exe' -Arguments 'wlan show interfaces' -TimeoutSec 20
    if ($r.TimedOut) { [void]$rows.Add([pscustomobject]@{ Label = 'Wi-Fi'; Value = 'O netsh não respondeu a tempo.'; Tone = 'warn'; Note = $true }) }
    else { foreach ($x in @(ConvertFrom-TIWifiText -Text $r.Output)) { [void]$rows.Add($x) } }

    # Sem dados do netsh (Localização desligada, serviço parado): estado da placa pelo Windows
    if (@($rows | Where-Object { $_.Label -eq 'Estado' }).Count -eq 0) {
        foreach ($n in @(Get-TINetInfo | Where-Object { $_.Wifi })) {
            $st = switch ($n.Status) { 'Up' { 'conectada' } 'Disconnected' { 'desconectada' } 'Disabled' { 'desativada' } default { [string]$n.Status } }
            if ($n.Up -and $n.LinkSpeed) { $st += (' ({0})' -f $n.LinkSpeed) }
            [void]$rows.Add([pscustomobject]@{ Label = ('Placa ' + $n.Name); Value = $st; Tone = $(if ($n.Up) { 'ok' } else { 'warn' }); Note = $false })
        }
    }

    # Redes salvas (para "Esquecer rede")
    $pr = Invoke-TICommand -File 'netsh.exe' -Arguments 'wlan show profiles' -TimeoutSec 20
    if (-not $pr.TimedOut -and $pr.Code -eq 0) {
        foreach ($name in @(ConvertFrom-TIWifiProfiles -Text $pr.Output)) { [void]$rows.Add([pscustomobject]@{ Profile = $name }) }
    }
    return ($rows.ToArray())
}

# Perfis .xml (exportados com netsh wlan export profile) para todos os usuários
function Import-TIWifiProfiles {
    param([string]$Folder)
    $files = @(Get-ChildItem -LiteralPath $Folder -Filter '*.xml' -File -ErrorAction Stop | Sort-Object Name)
    if ($files.Count -eq 0) { throw ('Nenhum arquivo .xml em {0}.' -f $Folder) }
    $ok = 0; $fail = 0; $i = 0
    foreach ($f in $files) {
        $i++
        Emit ('Importando {0} ({1}/{2})...' -f $f.Name, $i, $files.Count) 'Info' ([int](100 * $i / $files.Count))
        $r = Invoke-TICommand -File 'netsh.exe' -Arguments ('wlan add profile filename="{0}" user=all' -f $f.FullName) -TimeoutSec 30
        $tail = $(if ($r.TimedOut) { 'o netsh não respondeu a tempo' } else { Get-TIOutputTail $r.Output })
        if (-not $r.TimedOut -and $r.Code -eq 0) { $ok++; Emit ('  {0}: {1}' -f $f.Name, $tail) 'Success' }
        else { $fail++; Emit ('  {0}: {1}' -f $f.Name, $tail) 'Error' }
    }
    Emit ('Perfis de Wi-Fi: {0} importado(s), {1} com falha.' -f $ok, $fail) $(if ($fail -eq 0) { 'Success' } else { 'Warn' })
    return [pscustomobject]@{ Ok = $ok; Fail = $fail }
}

# Esquece a rede salva (resolve senha antiga gravada no notebook)
function Remove-TIWifiProfile {
    param([string]$Name)
    $n = ([string]$Name).Replace('"', '').Trim()
    if (-not $n) { throw 'Rede não informada.' }
    $r = Invoke-TICommand -File 'netsh.exe' -Arguments ('wlan delete profile name="{0}"' -f $n) -TimeoutSec 30
    if ($r.TimedOut) { throw 'o netsh não respondeu a tempo.' }
    if ($r.Code -ne 0) {
        Emit ('Não foi possível esquecer a rede "{0}": {1}' -f $n, (Get-TIOutputTail $r.Output)) 'Error'
        return $false
    }
    Emit ('Rede "{0}" esquecida: na próxima conexão o Windows pede a senha de novo.' -f $n) 'Success'
    return $true
}

function Clear-TIDnsCache {
    Emit 'Limpando o cache de DNS...' 'Info'
    try {
        Clear-DnsClientCache -ErrorAction Stop
        Emit 'Cache de DNS limpo.' 'Success'
        return $true
    } catch {
        $first = $_.Exception.Message
        $r = Invoke-TICommand -File 'ipconfig.exe' -Arguments '/flushdns' -TimeoutSec 30
        if (-not $r.TimedOut -and $r.Code -eq 0) {
            Emit 'Cache de DNS limpo (ipconfig /flushdns).' 'Success'
            return $true
        }
        $why = $(if ($r.TimedOut) { 'o ipconfig não respondeu a tempo' } else { Get-TIOutputTail $r.Output })
        if (-not $why) { $why = $first }
        Emit ('Não foi possível limpar o cache de DNS: {0} (o serviço Cliente DNS pode estar parado).' -f $why) 'Error'
        return $false
    }
}

function Reset-TINetwork {
    Emit 'Renovando o endereço IP (release/renew)...' 'Info' 10
    $rel = Invoke-TICommand -File 'ipconfig.exe' -Arguments '/release' -TimeoutSec 60
    if ($rel.TimedOut) { Emit '  O ipconfig /release não respondeu a tempo.' 'Warn' }
    else { Emit '  Endereço liberado' 'Info' 30 }
    Start-Sleep -Seconds 2
    Emit '  Pedindo um novo endereço ao servidor DHCP (pode levar até 1 minuto)...' 'Info' 40
    $ren = Invoke-TICommand -File 'ipconfig.exe' -Arguments '/renew' -TimeoutSec 90
    if ($ren.TimedOut) { Emit '  O ipconfig /renew não respondeu a tempo.' 'Warn' }
    elseif ($ren.Code -ne 0) { Emit ('  O ipconfig /renew relatou: {0}' -f (Get-TIOutputTail $ren.Output)) 'Warn' }
    Start-Sleep -Seconds 2
    # Mesmo critério do teste de conexão: placa com gateway primeiro, virtuais por último
    $pri = Select-TIPrimaryNet @(Get-TINetInfo)
    if (-not $pri) {
        Emit 'Nenhum endereço IPv4 depois da renovação: confira o cabo ou o Wi-Fi.' 'Error'
        return [pscustomobject]@{ Ok = $false; Reason = 'noip'; Ip = ''; Adapter = '' }
    }
    $ip = [string](@($pri.Ips) | Select-Object -First 1)
    if ($pri.Apipa) {
        Emit ('O servidor DHCP não respondeu: {0} ficou com o endereço automático {1}. Confira o cabo, o Wi-Fi e o switch/roteador.' -f $pri.Name, $ip) 'Error'
        return [pscustomobject]@{ Ok = $false; Reason = 'apipa'; Ip = $ip; Adapter = $pri.Name }
    }
    if (@($pri.Gateways).Count -eq 0) {
        Emit ('Novo IPv4 {0} em {1}, mas sem gateway: não há rota para a internet.' -f $ip, $pri.Name) 'Warn'
        return [pscustomobject]@{ Ok = $false; Reason = 'nogw'; Ip = $ip; Adapter = $pri.Name }
    }
    Emit ('Novo IPv4: {0} em {1} (gateway {2}).' -f $ip, $pri.Name, @($pri.Gateways)[0]) 'Success' 100
    return [pscustomobject]@{ Ok = $true; Reason = ''; Ip = $ip; Adapter = $pri.Name }
}

# Reinicia (desativa e ativa) ou só ativa a placa. A reativação fica no
# finally: com Cancelar ou erro no meio, o PC não pode ficar sem rede.
function Repair-TIAdapter {
    param([string]$Name, [switch]$EnableOnly)
    $find = { @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1 }
    $a = & $find
    if (-not $a) { throw ('adaptador "{0}" não encontrado.' -f $Name) }
    if ($EnableOnly) {
        Emit ('Ativando o adaptador {0}...' -f $Name) 'Info'
        Enable-NetAdapter -InputObject $a -Confirm:$false -ErrorAction Stop
        Emit '  Adaptador ativado' 'Info'
    } else {
        Emit ('Reiniciando o adaptador {0} (desativar e ativar)...' -f $Name) 'Warn'
        try {
            Disable-NetAdapter -InputObject $a -Confirm:$false -ErrorAction Stop
            Emit '  Adaptador desativado' 'Info'
            Start-Sleep -Seconds 3
        } finally {
            try {
                Enable-NetAdapter -InputObject $a -Confirm:$false -ErrorAction Stop
                Emit '  Adaptador reativado' 'Info'
            } catch {
                Emit ('Não foi possível reativar {0}: {1}. Ative pelo botão Ativar adaptador ou nas Conexões de Rede (ncpa.cpl).' -f $Name, $_.Exception.Message) 'Error'
            }
        }
    }
    # Wi-Fi e DHCP levam alguns segundos para voltar: espera até 15 s
    $st = ''
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $cur = & $find
        $st = $(if ($cur) { [string]$cur.Status } else { '' })
        if ($st -eq 'Up') { break }
    }
    if ($st -eq 'Up') { Emit ('Adaptador {0} funcionando.' -f $Name) 'Success' }
    elseif ($st -eq 'Disabled') { Emit ('O adaptador {0} continua desativado.' -f $Name) 'Error' }
    else { Emit ('O adaptador {0} está ativo, mas ainda não conectou (cabo, Wi-Fi ou driver).' -f $Name) 'Warn' }
    return [pscustomobject]@{ Name = $Name; Status = $st }
}

# Winsock e TCP/IP de volta ao padrão (resolve "conectado sem internet" depois
# de vírus, VPN ou proxy quebrado). Só vale depois de reiniciar o Windows.
function Reset-TINetStack {
    Emit 'Redefinindo o Winsock (netsh winsock reset)...' 'Info' 20
    $w = Invoke-TICommand -File 'netsh.exe' -Arguments 'winsock reset' -TimeoutSec 60
    if ($w.TimedOut) { Emit '  Winsock: o netsh não respondeu a tempo.' 'Error' }
    elseif ($w.Code -ne 0) { Emit ('  Winsock: {0}' -f (Get-TIOutputTail $w.Output)) 'Error' }
    else { Emit '  Winsock redefinido.' 'Success' }
    Emit 'Redefinindo o TCP/IP (netsh int ip reset)...' 'Info' 60
    $i = Invoke-TICommand -File 'netsh.exe' -Arguments 'int ip reset' -TimeoutSec 90
    if ($i.TimedOut) { Emit '  TCP/IP: o netsh não respondeu a tempo.' 'Error' }
    elseif ($i.Code -ne 0) {
        # Um item protegido costuma dar "Acesso negado" mesmo como administrador; o resto é aplicado
        Emit ('  TCP/IP: parte dos itens não foi redefinida ({0}). É comum em alguns PCs; o resto foi aplicado.' -f (Get-TIOutputTail $i.Output)) 'Warn'
    }
    else { Emit '  TCP/IP redefinido.' 'Success' }
    Emit 'Reinicie o computador para concluir a redefinição da rede.' 'Warn' 100
    return [pscustomobject]@{ NeedsReboot = $true }
}

# ---------------------------------------------------------------------
# Contas locais
# ---------------------------------------------------------------------
function Get-TICurrentSid {
    try { return [string][System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { return '' }
}

# Conta local pelo SID quando a interface manda (vale mesmo se ela foi
# renomeada depois da leitura) ou pelo nome
function Get-TILocalAccount {
    param([string]$User, [string]$Sid = '')
    if ($Sid) { return (Get-LocalUser -SID $Sid -ErrorAction Stop) }
    return (Get-LocalUser -Name $User -ErrorAction Stop)
}

# Devolve as contas e, por último, o marcador { AccountsRead = $true }: sem ele
# a interface sabe que a leitura falhou (lista vazia não é o mesmo que erro).
function Get-TIAccounts {
    $adminSids = Get-TIAdminSidSet
    $rows = New-Object System.Collections.ArrayList
    $all = $null
    try { $all = @(Get-LocalUser -ErrorAction Stop | Sort-Object Name) }
    catch { throw ('Não foi possível ler as contas locais: {0}' -f $_.Exception.Message) }
    foreach ($u in $all) {
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
    $n = $rows.Count
    [void]$rows.Add([pscustomobject]@{ AccountsRead = $true; Count = $n; AdminKnown = ($null -ne $adminSids) })
    return ($rows.ToArray())
}

# Grupo especial dentro de Administradores (Todos, Usuários autenticados,
# INTERATIVO, LOCAL, Logon do console) torna QUALQUER conta administradora
function Test-TIAccountIsAdmin {
    param([hashtable]$AdminSids, [string]$Sid)
    if ($AdminSids[$Sid]) { return $true }
    foreach ($w in @('S-1-1-0', 'S-1-5-11', 'S-1-5-4', 'S-1-2-0', 'S-1-2-1')) { if ($AdminSids[$w]) { return $true } }
    return $false
}

# Deixa a conta sem senha e confere. No PS 5.1 um argumento vazio some da linha
# de comando: "net user x """ vira "net user x", que só MOSTRA a conta e sai com
# código 0 (a senha continuava a mesma). Por isso: ADSI SetPassword(''), com
# Set-LocalUser (SecureString vazia) de reserva, e a data da senha conferida no fim.
function Remove-TIAccountPassword {
    param($Account)
    $name = [string]$Account.Name
    $sid = [string]$Account.SID.Value
    $before = $Account.PasswordLastSet
    $why = ''
    $done = $false
    try {
        $de = [ADSI]('WinNT://{0}/{1},user' -f $env:COMPUTERNAME, $name)
        try { [void]$de.Invoke('SetPassword', @('')); $done = $true } finally { $de.Dispose() }
    } catch {
        $ex = $_.Exception
        while ($ex.InnerException) { $ex = $ex.InnerException }
        $why = $ex.Message
    }
    if (-not $done) {
        try {
            Set-LocalUser -SID $sid -Password (New-Object System.Security.SecureString) -ErrorAction Stop
            $done = $true
        } catch { if (-not $why) { $why = $_.Exception.Message } }
    }
    if (-not $done) {
        throw ('O Windows recusou a senha em branco para "{0}": {1} (a política de senha do computador pode exigir um tamanho mínimo).' -f $name, ([string]$why).Trim())
    }
    # A data da última troca de senha tem de ter mudado agora
    $after = $null
    try { $after = (Get-LocalUser -SID $sid -ErrorAction Stop).PasswordLastSet } catch { }
    if ($after) {
        $recent = (((Get-Date) - $after).TotalMinutes -lt 5)
        $moved = (($null -eq $before) -or (($after - $before).TotalSeconds -gt 5))
        if (-not ($recent -and $moved)) { throw ('O Windows não confirmou a remoção da senha de "{0}" (a data da senha não mudou).' -f $name) }
    } else {
        Emit ('Não deu para conferir a remoção da senha de "{0}" pela data da senha.' -f $name) 'Debug'
    }
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

# Senha nova ou -Remove (conta sem senha). As regras valem aqui também, não só
# na tela: nunca a conta em uso; sem senha, nunca uma conta administradora.
function Set-TIAccountPassword {
    param([string]$User, [string]$Password, [switch]$Remove, [string]$Sid = '')
    $u = Get-TILocalAccount -User $User -Sid $Sid
    $User = [string]$u.Name
    $uSid = [string]$u.SID.Value
    if ($uSid -and $uSid -eq (Get-TICurrentSid)) { throw ('"{0}" é a conta em uso: a senha dela não é alterada por aqui.' -f $User) }
    if ($Remove) {
        # Conta administradora sem senha = controle total para quem sentar no teclado
        $adminSids = Get-TIAdminSidSet
        if ($null -eq $adminSids) { throw 'Não foi possível ler o grupo Administradores. Por segurança, a senha não foi removida.' }
        if (Test-TIAccountIsAdmin -AdminSids $adminSids -Sid $uSid) {
            throw ('"{0}" é administradora: contas administradoras não podem ficar sem senha.' -f $User)
        }
        Remove-TIAccountPassword -Account $u
        Emit ('A conta "{0}" agora entra sem senha.' -f $User) 'Warn'
    } else {
        if ([string]::IsNullOrEmpty($Password)) { throw 'Senha vazia: para deixar a conta sem senha, use "Remover senha".' }
        $sec = ConvertTo-SecureString $Password -AsPlainText -Force
        Set-LocalUser -Name $User -Password $sec -ErrorAction Stop
        Emit ('Senha da conta "{0}" redefinida.' -f $User) 'Success'
    }
    try { if (Unlock-TIAccount -User $User) { Emit ('A conta "{0}" estava bloqueada e foi desbloqueada.' -f $User) 'Success' } } catch { }
    return $true
}

function Enable-TIAccount {
    param([string]$User, [switch]$Disable, [string]$Sid = '')
    if ($Disable) {
        $d = Get-TILocalAccount -User $User -Sid $Sid
        $User = [string]$d.Name
        if ([string]$d.SID.Value -eq (Get-TICurrentSid)) { throw ('"{0}" é a conta em uso e não pode ser desativada.' -f $User) }
        Disable-LocalUser -Name $User -ErrorAction Stop
        Emit ('Conta "{0}" desativada.' -f $User) 'Warn'
        return $true
    }
    $u = Get-TILocalAccount -User $User -Sid $Sid
    $User = [string]$u.Name
    $wasDisabled = -not $u.Enabled
    if ($wasDisabled) { Enable-LocalUser -Name $User -ErrorAction Stop }
    $unlocked = $false
    try { $unlocked = Unlock-TIAccount -User $User } catch { Emit ('Não foi possível desbloquear "{0}": {1}' -f $User, $_.Exception.Message) 'Error' }
    if ($wasDisabled -and $unlocked) { Emit ('Conta "{0}" ativada e desbloqueada.' -f $User) 'Success' }
    elseif ($wasDisabled) { Emit ('Conta "{0}" ativada.' -f $User) 'Success' }
    elseif ($unlocked) { Emit ('Conta "{0}" desbloqueada.' -f $User) 'Success' }
    else { Emit ('A conta "{0}" já estava ativa e desbloqueada.' -f $User) 'Info' }
    return $true
}

function Set-TIAccountAdmin {
    param([string]$User, [switch]$Remove, [string]$Sid = '')
    $u = Get-TILocalAccount -User $User -Sid $Sid
    $User = [string]$u.Name
    $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
    if ($Remove) {
        if ([string]$u.SID.Value -eq (Get-TICurrentSid)) { throw ('"{0}" é a conta em uso: ela não perde o acesso de administrador por aqui.' -f $User) }
        Remove-LocalGroupMember -SID $adminSid -Member $User -ErrorAction Stop
        Emit ('"{0}" saiu do grupo Administradores.' -f $User) 'Warn'
    } else {
        Add-LocalGroupMember -SID $adminSid -Member $User -ErrorAction Stop
        Emit ('"{0}" entrou no grupo Administradores.' -f $User) 'Success'
    }
    return $true
}

# -MustChange: "Exigir troca de senha no próximo login" (a conta nasce SEM
# "senha nunca expira", senão o Windows ignora a exigência).
function New-TIAccount {
    param([string]$User, [string]$Password, [string]$Description, [switch]$MustChange)
    $sec = ConvertTo-SecureString $Password -AsPlainText -Force
    if ($MustChange) {
        New-LocalUser -Name $User -Password $sec -Description $Description -ErrorAction Stop | Out-Null
    } else {
        New-LocalUser -Name $User -Password $sec -PasswordNeverExpires -Description $Description -ErrorAction Stop | Out-Null
    }
    Emit ('Conta local "{0}" criada.' -f $User) 'Success'
    # New-LocalUser, ao contrário de "net user /add" e do lusrmgr, não põe a conta
    # em Usuários (S-1-5-32-545): sem isso ela fica diferente das outras
    try {
        $usersSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
        Add-LocalGroupMember -SID $usersSid -Member $User -ErrorAction Stop
        Emit ('"{0}" entrou no grupo Usuários.' -f $User) 'Debug'
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'MemberExists*' -and $_.Exception.GetType().Name -ne 'MemberExistsException') {
            Emit ('A conta "{0}" foi criada, mas não entrou no grupo Usuários: {1}' -f $User, $_.Exception.Message) 'Warn'
        }
    }
    if ($MustChange) {
        try {
            Set-TIMustChangePassword -User $User
            Emit ('No primeiro login, "{0}" vai trocar a senha inicial por uma própria.' -f $User) 'Info'
        } catch {
            Emit ('A conta "{0}" foi criada, mas não deu para exigir a troca de senha no primeiro login: {1}' -f $User, $_.Exception.Message) 'Error'
        }
    }
    return $true
}
'@

$global:TIAsync = @{
    Ps          = $null
    Pool        = $null
    Handle      = $null
    Timer       = $null
    Queue       = $null
    OnComplete  = $null
    Name        = ''
    ErrorCount  = 0
    Cancelled   = $false
    Quiet       = $false
    Audit       = $false
    AuditDetail = ''
    Started     = $null
}

# Test-TIIsAdmin fica no TI-Suite.ps1 (usado antes do UAC e no Start-TIApp)

# Barra de progresso da janela e do botão na barra de tarefas (Update-TITaskbar, 05-Shell)
function Set-TIAsyncProgress {
    param([int]$Percent = -1)
    if ($global:ProgressBar) { $global:ProgressBar.Percent = $Percent }
    if ($global:TI.Busy -and $global:TIShown) { try { Update-TITaskbar -State 'Progress' -Percent $Percent } catch { } }
}

# -AuditDetail: texto curto (sem senhas) que vai para a coluna "detalhe" do audit.csv,
#   junto com o tempo e a contagem de erros. Só vale com -Audit ou -RequiresAdmin.
# -NoCancel: esconde o Cancelar (tarefa curta que não pode parar no meio).
function Invoke-TIAsync {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [string]$Name = 'Tarefa',
        [hashtable]$Context = @{},
        [scriptblock]$OnComplete,
        [switch]$RequiresAdmin,
        [switch]$Audit,
        [string]$AuditDetail = '',
        [switch]$NoCancel,
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
    $global:TIAsync.AuditDetail = [string]$AuditDetail
    $global:TIAsync.Quiet = $Quiet.IsPresent
    $global:TIAsync.Started = Get-Date
    Set-TIBusy -Busy $true -Name $Name -NoCancel:$NoCancel
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

    # Até 500 itens por volta. O limite é testado ANTES do TryDequeue: ao
    # contrário, o 501º item saía da fila e se perdia.
    $item = $null
    $guard = 0
    $lastText = ''
    $lastPct = -1
    while ($guard -lt 500 -and $st.Queue.TryDequeue([ref]$item)) {
        $guard++
        if ($item.Kind -eq 'Log') {
            $lvl = if ($item.Level -in @('Debug','Info','Success','Warn','Error')) { $item.Level } else { 'Info' }
            Write-TILog -Level $lvl -Message $item.Text
            # Falha relatada pela tarefa (Emit ... 'Error') conta como erro dela:
            # auditoria ERRO e aviso vermelho no fim
            if ($lvl -eq 'Error' -and -not $st.Cancelled) { $st.ErrorCount++ }
            if ($lvl -ne 'Debug' -and $item.Text) { $lastText = [string]$item.Text }
            if ($item.Progress -ge 0) { $lastPct = [int]$item.Progress }
        }
        $item = $null
    }
    # Sobreposição e barras atualizadas uma vez por volta (última mensagem e percentual)
    if ($lastPct -ge 0) { Set-TIAsyncProgress -Percent $lastPct }
    if ($lastText -or $lastPct -ge 0) { try { Set-TIBusyDetail -Text $lastText -Percent $lastPct } catch { } }

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
            if ($lvl -eq 'Error' -and -not $st.Cancelled) { $st.ErrorCount++ }
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
    $auditDetail = [string]$st.AuditDetail
    $errs = $st.ErrorCount
    $cancelled = $st.Cancelled
    $quiet = $st.Quiet
    $secs = if ($st.Started) { [int]((Get-Date) - $st.Started).TotalSeconds } else { 0 }
    $st.OnComplete = $null
    $st.Name = ''
    $st.Cancelled = $false
    $st.Quiet = $false
    $st.Audit = $false
    $st.AuditDetail = ''

    $global:TI.Busy = $false
    Set-TIAsyncProgress -Percent -1
    Set-TIBusy -Busy $false -Name ''
    # Barra de tarefas: vermelha por alguns segundos se houve erro; pisca se a janela está atrás
    try {
        Update-TITaskbar -State $(if ($errs -gt 0 -and -not $cancelled) { 'Error' } else { 'Done' }) -Flash:(-not $quiet -and -not $cancelled)
    } catch { }

    if ($cancelled) {
        Write-TILog -Level 'Warn' -Message ("{0}: cancelada pelo operador." -f $name)
        Show-TIToast -Text ("{0}: cancelada" -f $name) -Type 'Warn'
        if ($audit) {
            $d = '{0}s' -f $secs
            if ($auditDetail) { $d = '{0} ({1})' -f $auditDetail, $d }
            try { Write-TIAudit -Action $name -Result 'CANCELADA' -Detail $d } catch { }
        }
        return
    }
    if ($audit) {
        $d = '{0}s; {1} erro(s)' -f $secs, $errs
        if ($auditDetail) { $d = '{0} ({1})' -f $auditDetail, $d }
        try { Write-TIAudit -Action $name -Result $(if ($errs -gt 0) { 'ERRO' } else { 'OK' }) -Detail $d } catch { }
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

# Cancelamento sem congelar a janela (BeginStop em vez de Stop); o pump grava o fim.
# -ForExit (janela fechando): o pump não roda mais, então aqui mesmo espera a
# tarefa parar (até -TimeoutSeconds, para os finally dela rodarem), registra no
# console, grava 'INTERROMPIDA' na auditoria e libera o estado. Não chama o OnComplete.
function Stop-TIAsync {
    param(
        [switch]$ForExit,
        [int]$TimeoutSeconds = 10,
        [string]$Reason = 'app fechado durante a tarefa'
    )
    $st = $global:TIAsync
    if (-not $global:TI.Busy -or -not $st.Ps) { return }

    if (-not $ForExit) {
        if ($st.Cancelled) { return }
        $st.Cancelled = $true
        Write-TILog -Level 'Warn' -Message ("Cancelando: {0}..." -f $st.Name)
        if ($global:CancelBtn) { $global:CancelBtn.Enabled = $false }
        if ($global:OverlayLabel) {
            try { $global:OverlayLabel.Text = ('Cancelando: {0}...' -f $st.Name); & $global:LayoutOverlay } catch { }
        }
        try { [void]$st.Ps.BeginStop($null, $null) } catch { }
        return
    }

    try { if ($st.Timer) { $st.Timer.Stop(); $st.Timer.Dispose() } } catch { }
    $st.Timer = $null
    $name = $st.Name
    if ($global:OverlayLabel) {
        try {
            $global:OverlayLabel.Text = ('Encerrando: interrompendo {0}...' -f $name)
            & $global:LayoutOverlay
            $global:Overlay.Refresh()
        } catch { }
    }
    if (-not $st.Cancelled) {
        $st.Cancelled = $true
        try { [void]$st.Ps.BeginStop($null, $null) } catch { }
    }
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
    while ($st.Handle -and -not $st.Handle.IsCompleted -and (Get-Date) -lt $deadline) {
        try { [void]$st.Handle.AsyncWaitHandle.WaitOne(100) } catch { Start-Sleep -Milliseconds 100 }
    }
    $stopped = ($null -eq $st.Handle -or $st.Handle.IsCompleted)

    # O que a tarefa ainda tinha na fila vai para o console (e conta os erros)
    $item = $null
    while ($st.Queue -and $st.Queue.TryDequeue([ref]$item)) {
        if ($item.Kind -eq 'Log') {
            $lvl = if ($item.Level -in @('Debug','Info','Success','Warn','Error')) { $item.Level } else { 'Info' }
            Write-TILog -Level $lvl -Message $item.Text
            if ($lvl -eq 'Error') { $st.ErrorCount++ }
        }
        $item = $null
    }

    $secs = if ($st.Started) { [int]((Get-Date) - $st.Started).TotalSeconds } else { 0 }
    $d = '{0}; {1}s; {2} erro(s)' -f $Reason, $secs, $st.ErrorCount
    if (-not $stopped) { $d += '; não parou a tempo' }
    if ($st.AuditDetail) { $d = '{0} ({1})' -f $st.AuditDetail, $d }
    if ($st.Audit) { try { Write-TIAudit -Action $name -Result 'INTERROMPIDA' -Detail $d } catch { } }
    Write-TILog -Level 'Warn' -Message ("{0}: interrompida ({1})." -f $name, $Reason)

    # Dispose de um pipeline que não parou bloquearia o fechamento: só se parou
    if ($stopped) {
        try { $st.Ps.Dispose() } catch { }
        try { $st.Pool.Close(); $st.Pool.Dispose() } catch { }
    }
    $st.Ps = $null; $st.Pool = $null; $st.Handle = $null; $st.Queue = $null
    $st.OnComplete = $null; $st.Name = ''; $st.Cancelled = $false; $st.Quiet = $false
    $st.Audit = $false; $st.AuditDetail = ''

    $global:TI.Busy = $false
    try { Set-TIAsyncProgress -Percent -1 } catch { }
    try { Set-TIBusy -Busy $false -Name '' } catch { }
    try { Update-TITaskbar -State 'Done' } catch { }
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
