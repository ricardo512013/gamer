# =====================================================================
# ÁREA: BACKUP DE USUÁRIOS - cópia literal da pasta do usuário para um disco conectado
#   Funciona no Windows aberto (modo normal) e no boot pelo pendrive (modo recuperação).
#   Pasta: <destino>\Backup-TI\<PC>\<usuario>-<AAAAMMDD-HHmm>\ com LEIA-ME.txt e _robocopy.log
#   Cópia com o robocopy, um usuário de cada vez. Nunca segue pontos de junção (/XJ) e
#   nada é apagado nem alterado na origem.
#   Instalações, usuários, volumes e o significado do código do robocopy vêm do
#   src\Core\06-Windows.ps1 (Get-TIWindowsInstalls, Get-TIOfflineUsers,
#   Get-TIDestinationVolumes, Get-TIRobocopyResult e Test-TIWinPE).
# =====================================================================

# ---------------------------------------------------------------------
# Regras usadas na interface E no worker (funções puras: dev\Test-Logic.ps1)
# ---------------------------------------------------------------------
$global:TIBackupShared = @'

# Nome seguro para pasta: troca \ / : * ? " < > | e caracteres de controle por _,
# tira espaço e ponto do fim e evita os nomes reservados do Windows (CON, NUL, COM1...)
function ConvertTo-TIBackupName {
    param([string]$Name, [string]$Fallback = 'sem-nome', [int]$MaxLength = 60)
    $t = [regex]::Replace([string]$Name, '[\\/:*?"<>|\x00-\x1F]', '_')
    $t = $t.Trim().TrimEnd([char[]]@('.', ' '))
    if ($t.Length -gt $MaxLength) { $t = $t.Substring(0, $MaxLength).TrimEnd([char[]]@('.', ' ')) }
    if ($t -eq '') { $t = $Fallback }
    if ($t -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') { $t = '_' + $t }
    return $t
}

# <destino>\Backup-TI\<PC> (sempre com \: é caminho do Windows, mesmo nos testes)
function Get-TIBackupBase {
    param([string]$DestRoot, [string]$Computer)
    $root = ([string]$DestRoot).Trim().TrimEnd('\')
    if ($root -match '^[A-Za-z]$') { $root += ':' }
    return ('{0}\Backup-TI\{1}' -f $root, (ConvertTo-TIBackupName -Name $Computer -Fallback 'PC'))
}

# Pasta de um usuário: <base>\<usuario>-<AAAAMMDD-HHmm>; -Attempt 2, 3... quando ela já existe
function Get-TIBackupFolder {
    param([string]$DestRoot, [string]$Computer, [string]$User, [datetime]$Date, [int]$Attempt = 1)
    $leaf = '{0}-{1}' -f (ConvertTo-TIBackupName -Name $User -Fallback 'usuario'), $Date.ToString('yyyyMMdd-HHmm')
    if ($Attempt -gt 1) { $leaf += ('-{0}' -f $Attempt) }
    return ('{0}\{1}' -f (Get-TIBackupBase -DestRoot $DestRoot -Computer $Computer), $leaf)
}

# Cabe no destino? Precisa do tamanho estimado mais a folga (5%).
# Free nulo ou negativo = espaço desconhecido: não libera a cópia.
function Test-TIBackupSpace {
    param([double]$Needed, $Free, [double]$MarginPct = 5)
    $need = [Math]::Ceiling([Math]::Max(0.0, $Needed) * (1 + $MarginPct / 100))
    $known = $false
    $f = -1.0
    if ($null -ne $Free -and [string]$Free -ne '') {
        try { $f = [double]$Free; $known = ($f -ge 0) } catch { $f = -1.0 }
    }
    $ok = ($known -and $f -ge $need)
    $missing = 0.0
    if ($known -and -not $ok) { $missing = $need - $f }
    return [pscustomobject]@{ Ok = $ok; Known = $known; Need = $need; Free = $f; Missing = $missing }
}

# Quanto vai para o destino: a pasta inteira, menos temporários e caches quando pulados
function Get-TIBackupEstimate {
    param($Items, [bool]$SkipCache = $true)
    $sum = 0.0
    foreach ($u in @($Items)) {
        if (-not $u) { continue }
        $s = 0.0
        $c = 0.0
        try { $s = [Math]::Max(0.0, [double]$u.Size) } catch { }
        if ($SkipCache) { try { $c = [Math]::Max(0.0, [double]$u.CacheSize) } catch { } }
        $sum += [Math]::Max(0.0, $s - $c)
    }
    return $sum
}

# Detalhe da auditoria: 'Usuários: a, b -> E:\Backup-TI\PC01' (sem inflar a linha)
function Get-TIBackupAuditDetail {
    param([string[]]$Names, [string]$Base, [int]$Max = 25)
    $n = @($Names | Where-Object { $_ })
    $txt = (@($n | Select-Object -First $Max)) -join ', '
    if ($n.Count -gt $Max) { $txt += (' e mais {0}' -f ($n.Count - $Max)) }
    return ('Usuários: {0} -> {1}' -f $txt, $Base)
}

# Avisos sobre o destino escolhido. Short vai para a tabela, Text para a dica e a confirmação.
function Get-TIBackupDestNotes {
    param($Dest, [int]$SourceDisk = -1)
    $out = New-Object System.Collections.ArrayList
    if (-not $Dest) { return }
    $disk = -1
    try { if ($null -ne $Dest.DiskNumber -and [string]$Dest.DiskNumber -ne '') { $disk = [int]$Dest.DiskNumber } } catch { }
    if ($SourceDisk -ge 0 -and $disk -ge 0 -and $disk -eq $SourceDisk) {
        [void]$out.Add([pscustomobject]@{ Kind = 'samedisk'; Short = 'Mesmo disco da origem'
            Text = 'Este destino fica no mesmo disco físico da origem: se o disco estiver com defeito, o backup se perde junto. Prefira um HD externo ou pendrive.' })
    }
    if ([string]$Dest.FileSystem -match '^FAT(12|16|32)?$') {
        [void]$out.Add([pscustomobject]@{ Kind = 'fat'; Short = 'FAT32: até 4 GB por arquivo'
            Text = 'Disco em FAT32: arquivos com mais de 4 GB não cabem (aparecem como falha). Prefira um disco em NTFS ou exFAT.' })
    }
    if ([string]$Dest.Type -eq 'Rede') {
        [void]$out.Add([pscustomobject]@{ Kind = 'net'; Short = 'Unidade de rede'
            Text = 'Unidade de rede: a cópia depende da rede até o fim.' })
    }
    if ($Dest.IsTiSuite -eq $true) {
        [void]$out.Add([pscustomobject]@{ Kind = 'tisuite'; Short = 'Pendrive do TI Suite'
            Text = 'É a partição de dados do pendrive do TI Suite: serve se couber, mas para backups grandes um HD externo é mais seguro.' })
    }
    return $out.ToArray()
}
'@
$global:TIWorkerLib += $global:TIBackupShared
. ([scriptblock]::Create($global:TIBackupShared))

# ---------------------------------------------------------------------
# BACKUP DE USUÁRIOS (roda no worker)
# ---------------------------------------------------------------------
$global:TIWorkerLib += @'

function Test-TIBackupAdmin {
    try {
        $p = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
        return [bool]$p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# Primeiro campo (entre os nomes dados) que existir e tiver valor
function Get-TIBackupProp {
    param($Obj, [string[]]$Names, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    foreach ($n in $Names) {
        $v = $null
        if ($Obj -is [System.Collections.IDictionary]) {
            if ($Obj.Contains($n)) { $v = $Obj[$n] }
        } else {
            $p = $Obj.PSObject.Properties[$n]
            if ($p) { $v = $p.Value }
        }
        if ($null -ne $v -and [string]$v -ne '') { return $v }
    }
    return $Default
}

# Volume de destino (Get-TIDestinationVolumes) num formato só: Drive 'E:', Root 'E:\', Label,
# FileSystem, Size, Free (-1 = desconhecido), Type, IsTiSuite, DiskNumber (-1 = desconhecido)
function ConvertTo-TIBackupVolume {
    param($Volume)
    if ($null -eq $Volume) { return $null }
    $drive = [string](Get-TIBackupProp $Volume @('Drive', 'Letter', 'DriveLetter') '')
    $root = [string](Get-TIBackupProp $Volume @('Root', 'RootPath', 'Path') '')
    if ($drive -match '^\s*([A-Za-z])(:\\?)?\s*$') { $drive = $Matches[1].ToUpperInvariant() + ':' }
    if (-not $drive -and $root -match '^([A-Za-z]):') { $drive = $Matches[1].ToUpperInvariant() + ':' }
    if (-not $root -and $drive) { $root = $drive + '\' }
    if (-not $drive -and -not $root) { return $null }
    $free = -1.0
    $fv = Get-TIBackupProp $Volume @('FreeBytes', 'Free', 'FreeSpace', 'SizeRemaining') $null
    if ($null -ne $fv) { try { $free = [double]$fv } catch { $free = -1.0 } }
    $size = 0.0
    try { $size = [double](Get-TIBackupProp $Volume @('SizeBytes', 'Size', 'TotalBytes', 'Capacity') 0) } catch { }
    $disk = -1
    try { $disk = [int](Get-TIBackupProp $Volume @('DiskNumber', 'Disk') -1) } catch { }
    return [pscustomobject]@{
        Drive      = $drive
        Root       = $root
        Label      = [string](Get-TIBackupProp $Volume @('Label', 'VolumeLabel', 'FileSystemLabel') '')
        FileSystem = [string](Get-TIBackupProp $Volume @('FileSystem', 'FileSystemType') '')
        Size       = $size
        Free       = $free
        Type       = [string](Get-TIBackupProp $Volume @('Type', 'Kind', 'BusType') '')
        IsTiSuite  = ((Get-TIBackupProp $Volume @('IsTiSuite') $false) -eq $true)
        DiskNumber = $disk
    }
}

# Pastas de perfil do Chrome/Edge (Default, Profile 1, ...)
function Test-TIBackupChromiumProfile {
    param([string]$Name)
    return ($Name -eq 'Default' -or $Name -like 'Profile *' -or $Name -eq 'Guest Profile' -or $Name -eq 'System Profile')
}

# Pastas puladas com "Pular temporários e caches" (/XD do robocopy). Caminhos completos,
# nunca só o nome: /XD Cache pularia também uma pasta "Cache" do próprio usuário.
function Get-TIBackupCacheDirs {
    param([string]$UserPath, [string[]]$ChromeProfiles = @(), [string[]]$EdgeProfiles = @(), [string[]]$FirefoxProfiles = @())
    $u = ([string]$UserPath).TrimEnd('\')
    $out = New-Object System.Collections.ArrayList
    foreach ($rel in @('AppData\Local\Temp', 'AppData\Local\Microsoft\Windows\INetCache',
                       'AppData\Local\Microsoft\Windows\WebCache', 'AppData\Local\Microsoft\Windows\Explorer')) {
        [void]$out.Add($u + '\' + $rel)
    }
    $chromium = @(
        @{ Root = 'AppData\Local\Google\Chrome\User Data'; Profiles = @($ChromeProfiles) },
        @{ Root = 'AppData\Local\Microsoft\Edge\User Data'; Profiles = @($EdgeProfiles) }
    )
    foreach ($b in $chromium) {
        $profs = @($b.Profiles | Where-Object { $_ -and (Test-TIBackupChromiumProfile $_) })
        if ($profs.Count -eq 0) { continue }
        $r = $u + '\' + $b.Root
        [void]$out.Add($r + '\ShaderCache')
        [void]$out.Add($r + '\GrShaderCache')
        foreach ($p in $profs) {
            foreach ($c in @('Cache', 'Code Cache', 'GPUCache')) { [void]$out.Add(('{0}\{1}\{2}' -f $r, $p, $c)) }
        }
    }
    # Firefox: o cache fica no perfil "local"; favoritos e senhas ficam no Roaming (copiado)
    foreach ($p in @($FirefoxProfiles | Where-Object { $_ })) {
        foreach ($c in @('cache2', 'startupCache')) {
            [void]$out.Add(('{0}\AppData\Local\Mozilla\Firefox\Profiles\{1}\{2}' -f $u, $p, $c))
        }
    }
    return $out.ToArray()
}

# Perfis dos navegadores de um usuário (só os nomes das pastas; não entra em links)
function Get-TIBackupBrowserProfiles {
    param([string]$UserPath)
    $res = @{ Chrome = @(); Edge = @(); Firefox = @() }
    $map = [ordered]@{
        Chrome  = 'AppData\Local\Google\Chrome\User Data'
        Edge    = 'AppData\Local\Microsoft\Edge\User Data'
        Firefox = 'AppData\Local\Mozilla\Firefox\Profiles'
    }
    foreach ($k in @($map.Keys)) {
        try {
            $di = New-Object System.IO.DirectoryInfo((([string]$UserPath).TrimEnd('\') + '\' + $map[$k]))
            if (-not $di.Exists -or ([int]$di.Attributes -band 1024)) { continue }
            $res[$k] = @($di.GetDirectories() | Where-Object { -not ([int]$_.Attributes -band 1024) } | ForEach-Object { $_.Name })
        } catch { }
    }
    return $res
}

# Pastas de temporários e caches que existem neste usuário, sem link no caminho
# (um link no caminho não é copiado com /XJ, então também não entra na conta)
function Get-TIBackupUserCacheDirs {
    param([string]$UserPath)
    $pr = Get-TIBackupBrowserProfiles -UserPath $UserPath
    $out = New-Object System.Collections.ArrayList
    foreach ($d in @(Get-TIBackupCacheDirs -UserPath $UserPath -ChromeProfiles $pr.Chrome -EdgeProfiles $pr.Edge -FirefoxProfiles $pr.Firefox)) {
        try {
            if (-not [System.IO.Directory]::Exists($d)) { continue }
            if ((Find-TIPathLink -Path $d -Base $UserPath) -ne '') { continue }
            [void]$out.Add($d)
        } catch { }
    }
    return $out.ToArray()
}

# Registro do usuário carregado (usuário conectado, no Windows aberto): o NTUSER.DAT fica
# preso pelo Windows e nem o modo de backup (/ZB) consegue lê-lo.
function Test-TIBackupHiveLoaded {
    param([string]$Sid, [string]$Path)
    if ($Sid) {
        try { if (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $Sid)) { return $true } } catch { }
    }
    $f = ([string]$Path).TrimEnd('\') + '\NTUSER.DAT'
    $s = $null
    try {
        if (-not [System.IO.File]::Exists($f)) { return $false }
        $s = [System.IO.File]::Open($f, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        return $false
    } catch {
        $ex = $_.Exception
        while ($ex) {
            if ($ex -is [System.IO.FileNotFoundException] -or $ex -is [System.IO.DirectoryNotFoundException]) { return $false }
            if ($ex -is [System.IO.IOException]) { return $true }
            $ex = $ex.InnerException
        }
        return $false
    } finally {
        if ($s) { try { $s.Dispose() } catch { } }
    }
}

# Disco físico de uma unidade (-1 = não deu para saber: volume em vários discos, rede...)
function Get-TIBackupDiskNumber {
    param([string]$Drive)
    if ([string]$Drive -notmatch '^\s*([A-Za-z])') { return -1 }
    $letter = $Matches[1]
    try {
        $p = @(Get-Partition -DriveLetter $letter -ErrorAction Stop) | Select-Object -First 1
        if ($p -and $null -ne $p.DiskNumber) { return [int]$p.DiskNumber }
    } catch { }
    return -1
}

# Um argumento para a linha de comando (regras do C do Windows, que o robocopy segue):
# entre aspas quando tem espaço (ou com -Force); barras antes de aspas e no fim são
# dobradas ("E:\" sem isso chegaria ao programa como E:").
function ConvertTo-TIBackupArg {
    param([string]$Arg, [switch]$Force)
    if ($Arg -eq '') { return '""' }
    if (-not $Force -and $Arg -notmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq [char]'\') { $bs++; continue }
        if ($ch -eq [char]'"') {
            [void]$sb.Append([char]'\', (2 * $bs + 1))
            [void]$sb.Append([char]'"')
            $bs = 0
            continue
        }
        if ($bs -gt 0) { [void]$sb.Append([char]'\', $bs); $bs = 0 }
        [void]$sb.Append($ch)
    }
    if ($bs -gt 0) { [void]$sb.Append([char]'\', (2 * $bs)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Linha de comando completa: caminhos sempre entre aspas; /OPÇÃO:caminho vira /OPÇÃO:"caminho"
function Join-TIBackupArgs {
    param([string[]]$Arguments)
    $parts = New-Object System.Collections.ArrayList
    foreach ($a in @($Arguments)) {
        $s = [string]$a
        if ($s -match '^(/[A-Za-z]+\+?:)(.+)$') {
            $pre = $Matches[1]
            $val = $Matches[2]
            if ($val -match '[\\\s"]') { [void]$parts.Add($pre + (ConvertTo-TIBackupArg -Arg $val -Force)) }
            else { [void]$parts.Add($s) }
        } elseif ($s.StartsWith('/')) {
            [void]$parts.Add($s)
        } else {
            [void]$parts.Add((ConvertTo-TIBackupArg -Arg $s -Force))
        }
    }
    return ($parts -join ' ')
}

# Argumentos do robocopy. /XJ é obrigatório: a pasta do usuário tem pontos de junção
# ("Dados de Aplicativos", "Meus Documentos"...) que apontam para dentro dela mesma.
# /ZB (modo de backup) só como administrador. -ExcludeFiles: hives do usuário conectado.
function Get-TIBackupRobocopyArgs {
    param(
        [string]$Source,
        [string]$Dest,
        [string]$LogPath,
        [bool]$IsAdmin = $false,
        [string[]]$ExcludeDirs = @(),
        [string[]]$ExcludeFiles = @(),
        [int]$Threads = 8
    )
    $trim = { param($p) $t = [string]$p; if ($t.Length -gt 3) { $t = $t.TrimEnd('\') }; $t }
    $a = New-Object System.Collections.ArrayList
    [void]$a.Add((& $trim $Source))
    [void]$a.Add((& $trim $Dest))
    foreach ($o in @('/E', '/COPY:DAT', '/DCOPY:DAT', '/XJ', '/R:1', '/W:1', ('/MT:{0}' -f $Threads), '/NP', '/NFL', '/NDL', '/BYTES')) {
        [void]$a.Add($o)
    }
    if ($IsAdmin) { [void]$a.Add('/ZB') }
    $xd = @($ExcludeDirs | Where-Object { $_ })
    if ($xd.Count -gt 0) {
        [void]$a.Add('/XD')
        foreach ($d in $xd) { [void]$a.Add((& $trim $d)) }
    }
    $xf = @($ExcludeFiles | Where-Object { $_ })
    if ($xf.Count -gt 0) {
        [void]$a.Add('/XF')
        foreach ($f in $xf) { [void]$a.Add([string]$f) }
    }
    [void]$a.Add('/UNILOG+:' + [string]$LogPath)
    return [string[]]$a.ToArray()
}

# A pasta do backup é sempre nova: o único "extra" possível no destino (bit 2 do código)
# é o próprio _robocopy.log. Tirado para o resultado não dizer "com extras no destino".
function Get-TIBackupEffectiveCode {
    param([int]$Code)
    if ($Code -lt 0) { return $Code }
    return ($Code -band (-bnot 2))
}

# Resumo do fim do log do robocopy (em inglês ou português). As três linhas antes de
# "Times"/"Tempos" são diretórios, arquivos e bytes, cada uma com Total, Copiados,
# Ignorados, Incompatíveis, FALHAS e Extras (com /BYTES, os bytes vêm em números).
function ConvertFrom-TIBackupRobocopySummary {
    param([string]$Text)
    $res = [pscustomobject]@{
        Found = $false
        DirsTotal = 0; DirsCopied = 0; DirsFailed = 0
        FilesTotal = 0; FilesCopied = 0; FilesSkipped = 0; FilesFailed = 0; FilesExtras = 0
        BytesTotal = -1.0; BytesCopied = -1.0; BytesFailed = -1.0
    }
    $lines = @(([string]$Text) -split "`r?`n")
    $ti = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ([string]$lines[$i] -match '^\s*[^:\d\s][^:\d]*:\s+\d+:\d{2}:\d{2}') { $ti = $i; break }
    }
    if ($ti -lt 0) { return $res }
    $rows = New-Object System.Collections.ArrayList
    for ($j = $ti - 1; $j -ge 0 -and $rows.Count -lt 3; $j--) {
        $l = [string]$lines[$j]
        if ($l.Trim() -eq '') { if ($rows.Count -eq 0) { continue } else { break } }
        $k = $l.IndexOf(':')
        if ($k -lt 0) { break }
        $vals = @(($l.Substring($k + 1).Trim() -replace '[.,]', '') -split '\s+')
        $rows.Insert(0, $vals)
    }
    if ($rows.Count -lt 3) { return $res }
    $isNum = { param($v) (@($v).Count -eq 6) -and (@($v | Where-Object { $_ -notmatch '^\d+$' }).Count -eq 0) }
    $d = @($rows[0])
    $f = @($rows[1])
    $b = @($rows[2])
    if (-not (& $isNum $f)) { return $res }
    $res.Found = $true
    $res.FilesTotal = [int64]$f[0]
    $res.FilesCopied = [int64]$f[1]
    $res.FilesSkipped = [int64]$f[2]
    $res.FilesFailed = [int64]$f[4]
    $res.FilesExtras = [int64]$f[5]
    if (& $isNum $d) {
        $res.DirsTotal = [int64]$d[0]
        $res.DirsCopied = [int64]$d[1]
        $res.DirsFailed = [int64]$d[4]
    }
    if (& $isNum $b) {
        $res.BytesTotal = [double]$b[0]
        $res.BytesCopied = [double]$b[1]
        $res.BytesFailed = [double]$b[4]
    }
    return $res
}

# Linhas de erro do log do robocopy ("ERRO 32 (0x00000020) Copiando arquivo ..." e a
# mensagem da linha seguinte), sem a data e sem repetir as novas tentativas
function Get-TIBackupRobocopyErrors {
    param([string]$Text, [int]$Max = 8)
    $lines = @(([string]$Text) -split "`r?`n")
    $seen = @{}
    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = ([string]$lines[$i]).Trim()
        if ($l -notmatch '\(0x[0-9A-Fa-f]{8}\)') { continue }
        $l = $l -replace '^\d{4}/\d{2}/\d{2}\s+\d{1,2}:\d{2}:\d{2}\s+', ''
        $next = ''
        if ($i + 1 -lt $lines.Count) { $next = ([string]$lines[$i + 1]).Trim() }
        if ($next -and $next -notmatch '\(0x[0-9A-Fa-f]{8}\)' -and $next -notmatch '^\d{4}/\d{2}/\d{2}') { $l = '{0} - {1}' -f $l, $next }
        if ($seen.ContainsKey($l)) { continue }
        $seen[$l] = $true
        [void]$out.Add($l)
    }
    return [pscustomobject]@{ Count = $out.Count; Lines = @($out | Select-Object -First $Max) }
}

function Format-TIBackupDuration {
    param([double]$Seconds)
    $s = [int][Math]::Round([Math]::Max(0.0, $Seconds))
    if ($s -lt 60) { return ('{0} s' -f $s) }
    $m = [int][Math]::Floor($s / 60)
    $r = $s % 60
    if ($m -lt 60) { return ('{0} min {1:00} s' -f $m, $r) }
    $h = [int][Math]::Floor($m / 60)
    return ('{0} h {1:00} min' -f $h, ($m % 60))
}

# Percentual da barra (0 a 99: os 100% ficam para quando o robocopy termina)
function Get-TIBackupPercent {
    param([double]$Done, [double]$Total)
    if ($Total -le 0) { return 0 }
    return [int][Math]::Max(0, [Math]::Min(99, [Math]::Floor(100 * $Done / $Total)))
}

# Situação de um usuário a partir do código (já sem o bit do _robocopy.log)
function Get-TIBackupStatus {
    param([int]$Code, [bool]$Interrupted = $false)
    if ($Interrupted) { return [pscustomobject]@{ Word = 'Interrompido'; Level = 'Warn'; Text = 'INCOMPLETO: a cópia foi interrompida antes do fim.' } }
    if ($Code -lt 0) { return [pscustomobject]@{ Word = 'Falhou'; Level = 'Error'; Text = 'FALHOU: o robocopy não rodou.' } }
    if ($Code -ge 16) { return [pscustomobject]@{ Word = 'Falhou'; Level = 'Error'; Text = 'FALHOU: erro grave do robocopy; nada (ou quase nada) foi copiado.' } }
    if ($Code -ge 8) { return [pscustomobject]@{ Word = 'Com falhas'; Level = 'Error'; Text = 'COPIADO COM FALHAS: alguns arquivos não foram copiados (lista no _robocopy.log).' } }
    if ($Code -ge 4) { return [pscustomobject]@{ Word = 'Com avisos'; Level = 'Warn'; Text = 'COPIADO COM AVISOS: o robocopy encontrou diferenças (veja o _robocopy.log).' } }
    return [pscustomobject]@{ Word = 'Concluído'; Level = 'Success'; Text = 'COMPLETO' }
}

# Texto do LEIA-ME.txt gravado em cada pasta de backup (CRLF: abre certo no Bloco de Notas)
function Get-TIBackupReadme {
    param($Info)
    $L = New-Object System.Collections.ArrayList
    $add = { param($k, $v) [void]$L.Add(('{0,-21}{1}' -f ($k + ':'), $v)) }
    $dt = { param($d) if ($d -is [datetime]) { $d.ToString('dd/MM/yyyy HH:mm:ss') } else { '-' } }
    $title = 'TI Suite {0} - backup de usuário' -f $Info.Version
    [void]$L.Add($title)
    [void]$L.Add(('=' * $title.Length))
    [void]$L.Add('')
    & $add 'Situação' $Info.Status
    & $add 'Computador' $Info.Computer
    & $add 'Windows' $Info.Windows
    $who = [string]$Info.User
    if ($Info.Account -and [string]$Info.Account -ne $who) { $who = '{0} ({1})' -f $who, $Info.Account }
    & $add 'Usuário' $who
    & $add 'Pasta de origem' $Info.Source
    & $add 'Pasta do backup' $Info.Folder
    & $add 'Início' (& $dt $Info.Start)
    $end = & $dt $Info.End
    if ($null -ne $Info.Seconds) { $end = '{0} ({1})' -f $end, (Format-TIBackupDuration -Seconds ([double]$Info.Seconds)) }
    & $add 'Fim' $end
    if ($Info.Interrupted) {
        & $add 'Tamanho copiado' ('cerca de {0} (cópia interrompida)' -f (Format-TIByte ([Math]::Max(0.0, [double]$Info.Bytes))))
    } else {
        & $add 'Tamanho copiado' (Format-TIByte ([Math]::Max(0.0, [double]$Info.Bytes)))
        $files = [string]$Info.Files
        if ([int64]$Info.FilesTotal -gt 0) { $files = '{0} de {1}' -f $Info.Files, $Info.FilesTotal }
        & $add 'Arquivos copiados' $files
        & $add 'Arquivos com falha' ([string]$Info.Failed)
        # o texto do Get-TIRobocopyResult já traz "(código N)"
        $code = [string]$Info.CodeText
        if ($code -notmatch ('c[oó]digo\s+{0}\b' -f [int]$Info.Code)) { $code = 'código {0} - {1}' -f $Info.Code, $code }
        if ($null -ne $Info.CodeRaw -and [int]$Info.CodeRaw -ne [int]$Info.Code) {
            $code += (' (no log, código {0}: o próprio _robocopy.log conta como arquivo extra)' -f $Info.CodeRaw)
        }
        & $add 'Robocopy' $code
    }
    [void]$L.Add('')
    [void]$L.Add('O que tem aqui')
    [void]$L.Add('- Cópia literal da pasta do usuário: Desktop (Área de Trabalho), Documents (Documentos),')
    [void]$L.Add('  Downloads, Pictures (Imagens), Music (Músicas), Videos (Vídeos) e AppData (configurações')
    [void]$L.Add('  dos programas, como favoritos e senhas salvas dos navegadores).')
    [void]$L.Add('- Pontos de junção do Windows (como "Dados de Aplicativos" e "Meus Documentos") não são')
    [void]$L.Add('  copiados: são atalhos para pastas que já estão na cópia.')
    if ($Info.CacheSkipped) {
        [void]$L.Add('- Temporários e caches (pasta Temp e cache dos navegadores) não foram copiados.')
    }
    if ($Info.HivesSkipped) {
        [void]$L.Add('- O usuário estava conectado durante a cópia: o registro dele (NTUSER.DAT e UsrClass.dat)')
        [void]$L.Add('  não foi copiado, porque o Windows mantém esses arquivos presos.')
    }
    if ($Info.Interrupted) {
        [void]$L.Add('- ATENÇÃO: a cópia foi interrompida. Faça o backup de novo antes de apagar ou formatar')
        [void]$L.Add('  qualquer coisa no computador de origem.')
    } elseif ([int64]$Info.Failed -gt 0) {
        [void]$L.Add('- Os arquivos que falharam estão no _robocopy.log, nesta pasta (procure por ERRO ou ERROR).')
    }
    [void]$L.Add('')
    [void]$L.Add('Para devolver os arquivos, copie as pastas (Desktop, Documents, Pictures...) para a pasta')
    [void]$L.Add('do usuário no computador. Não copie o NTUSER.DAT por cima de um perfil em uso.')
    return (($L.ToArray()) -join "`r`n") + "`r`n"
}

function Write-TIBackupReadmeFile {
    param([string]$Folder, [string]$Text)
    [System.IO.File]::WriteAllText(($Folder + '\LEIA-ME.txt'), $Text, (New-Object System.Text.UTF8Encoding($true)))
}

# Leitura da área: instalações (só na leitura completa, sem -Source), usuários da origem
# com tamanho (sem seguir junções) e discos de destino. Cada parte falha sozinha.
function Get-TIBackupScan {
    param($Source = $null, [string]$PreferRoot = '')
    $res = [pscustomobject]@{
        Kind = 'BackupScan'; Ok = $true; Full = ($null -eq $Source); Installs = @(); Locked = 0
        Source = $Source; Users = @(); UsersOk = $false; Volumes = @(); VolumesOk = $false; SourceDisk = -1
        IsAdmin = (Test-TIBackupAdmin)
    }
    if ($res.Full) {
        Emit 'Procurando instalações do Windows nos discos...' 'Info'
        $all = @()
        try { $all = @(Get-TIWindowsInstalls | Where-Object { $_ }) }
        catch {
            Emit ('Não foi possível procurar as instalações do Windows: {0}' -f $_.Exception.Message) 'Error'
            $res.Ok = $false
            return $res
        }
        $res.Locked = @($all | Where-Object { $_.Locked }).Count
        # este PC primeiro (modo normal), depois pela letra
        $list = @($all | Where-Object { -not $_.Locked } |
                  Sort-Object @{ Expression = { -not [bool]$_.IsRunning } }, @{ Expression = { [string]$_.Drive } })
        $res.Installs = $list
        if ($res.Locked -gt 0) { Emit ('{0} Windows com BitLocker travado: destrave para copiar os usuários dele.' -f $res.Locked) 'Warn' }
        $pick = $null
        if ($PreferRoot) { $pick = @($list | Where-Object { [string]$_.Root -eq $PreferRoot }) | Select-Object -First 1 }
        if (-not $pick) { $pick = @($list | Where-Object { $_.IsRunning }) | Select-Object -First 1 }
        if (-not $pick) { $pick = $list | Select-Object -First 1 }
        $res.Source = $pick
        if (-not $pick) {
            Emit 'Nenhum Windows encontrado para copiar usuários.' 'Warn'
            return $res
        }
    }
    $src = $res.Source

    try {
        Emit ('Lendo os usuários de {0} ({1})...' -f $src.Label, $src.Drive) 'Info' 2
        $users = @(Get-TIOfflineUsers -Install $src | Where-Object { $_ -and $_.Path })
        $rows = New-Object System.Collections.ArrayList
        $i = 0
        foreach ($u in $users) {
            $i++
            $path = ([string]$u.Path).TrimEnd('\')
            Emit ('Medindo a pasta de {0} ({1}/{2})...' -f $u.Name, $i, $users.Count) 'Debug' ([int](90 * $i / [Math]::Max(1, $users.Count)))
            $exists = [System.IO.Directory]::Exists($path)
            $size = 0.0
            $cache = 0.0
            if ($exists) {
                # não segue pontos de junção (igual ao /XJ do robocopy)
                $size = [double](Get-TISafeSize -Path $path)
                foreach ($d in @(Get-TIBackupUserCacheDirs -UserPath $path)) { $cache += [double](Get-TISafeSize -Path $d) }
            }
            # perfil carregado (Win32_UserProfile.Loaded no Windows aberto) ou NTUSER.DAT preso
            $loaded = $false
            if ($src.IsRunning -and $exists) { $loaded = ([bool]$u.Loaded -or (Test-TIBackupHiveLoaded -Sid ([string]$u.Sid) -Path $path)) }
            [void]$rows.Add([pscustomobject]@{
                Name      = [string]$u.Name
                Path      = $path
                Sid       = [string]$u.Sid
                Account   = [string]$u.Account
                LastUse   = $u.LastUse
                Size      = $size
                CacheSize = [Math]::Min($cache, $size)
                Loaded    = [bool]$loaded
                Exists    = [bool]$exists
            })
        }
        $res.Users = $rows.ToArray()
        $res.UsersOk = $true
        $total = 0.0
        foreach ($r in $rows) { $total += $r.Size }
        Emit ('{0} pasta(s) de usuário em {1} ({2}).' -f $rows.Count, $src.Drive, (Format-TIByte $total)) 'Info'
    } catch {
        Emit ('Não foi possível ler os usuários de {0}: {1}' -f $src.Drive, $_.Exception.Message) 'Error'
    }

    try {
        Emit 'Procurando discos para gravar o backup...' 'Info' 95
        $vols = @(Get-TIDestinationVolumes -ExcludeRoots @([string]$src.Root) | ForEach-Object { ConvertTo-TIBackupVolume $_ } | Where-Object { $_ })
        $res.SourceDisk = Get-TIBackupDiskNumber -Drive ([string]$src.Drive)
        foreach ($v in $vols) {
            if ($v.DiskNumber -lt 0 -and $v.Drive) { $v.DiskNumber = Get-TIBackupDiskNumber -Drive $v.Drive }
        }
        $res.Volumes = $vols
        $res.VolumesOk = $true
        if ($vols.Count -eq 0) { Emit 'Nenhum disco para gravar o backup: conecte um HD externo ou pendrive e clique em Atualizar.' 'Warn' }
    } catch {
        Emit ('Não foi possível listar os discos de destino: {0}' -f $_.Exception.Message) 'Error'
    }
    return $res
}

# Copia um usuário (robocopy como processo filho). O tamanho do destino é medido a cada
# ~2 s (mais espaçado se a medição demorar) para o percentual. Cancelar (BeginStop) cai
# no finally: o robocopy é encerrado e a pasta ganha um LEIA-ME de cópia INCOMPLETA.
function Invoke-TIBackupUser {
    param(
        $User, $Source, $Dest,
        [string]$Computer, [datetime]$Stamp, [bool]$SkipCache, [bool]$IsAdmin, [string]$Robocopy,
        [int]$Index, [int]$Count, [double]$DoneBefore, [double]$Total, [string]$Version
    )
    $name = [string]$User.Name
    $src = ([string]$User.Path).TrimEnd('\')
    $r = [pscustomobject]@{
        Name = $name; Source = $src; Folder = ''; Code = -1; CodeRaw = -1; Level = 'Error'; Word = 'Falhou'; Text = ''
        Files = 0; FilesTotal = 0; Failed = 0; Bytes = 0.0; Seconds = 0; Duration = '-'
        HivesSkipped = $false; CacheSkipped = $SkipCache
    }
    if (-not [System.IO.Directory]::Exists($src)) {
        $r.Text = 'A pasta do usuário não existe mais.'
        Emit ('{0}: a pasta {1} não existe mais; nada foi copiado.' -f $name, $src) 'Error'
        return $r
    }

    $folder = ''
    for ($n = 1; $n -le 99; $n++) {
        $folder = Get-TIBackupFolder -DestRoot ([string]$Dest.Root) -Computer $Computer -User $name -Date $Stamp -Attempt $n
        if (-not (Test-Path -LiteralPath $folder)) { break }
    }
    try { [void][System.IO.Directory]::CreateDirectory($folder) }
    catch {
        $r.Text = 'Não foi possível criar a pasta do backup.'
        Emit ('{0}: não foi possível criar a pasta {1}: {2}' -f $name, $folder, $_.Exception.Message) 'Error'
        return $r
    }
    $r.Folder = $folder
    $log = $folder + '\_robocopy.log'

    $xd = @()
    if ($SkipCache) { $xd = @(Get-TIBackupUserCacheDirs -UserPath $src) }
    $xf = @()
    if ($Source.IsRunning -and (Test-TIBackupHiveLoaded -Sid ([string]$User.Sid) -Path $src)) {
        $xf = @('NTUSER.DAT*', 'UsrClass.dat*')
        $r.HivesSkipped = $true
        Emit ('{0} está conectado: NTUSER.DAT e UsrClass.dat (registro do usuário) ficam de fora, porque o Windows mantém esses arquivos presos. O resto da pasta é copiado.' -f $name) 'Warn'
    }
    $roboArgs = @(Get-TIBackupRobocopyArgs -Source $src -Dest $folder -LogPath $log -IsAdmin $IsAdmin -ExcludeDirs $xd -ExcludeFiles $xf)
    $cmdLine = Join-TIBackupArgs -Arguments $roboArgs
    $est = Get-TIBackupEstimate -Items @($User) -SkipCache $SkipCache
    Emit ('Copiando {0} ({1}/{2}, cerca de {3}) para {4}...' -f $name, $Index, $Count, (Format-TIByte $est), $folder) 'Info' (Get-TIBackupPercent -Done $DoneBefore -Total $Total)
    Emit ('robocopy {0}' -f $cmdLine) 'Debug'

    $start = Get-Date
    $cur = 0.0
    $readme = {
        param([bool]$Interrupted)
        $stCode = $r.Code
        if (-not $Interrupted -and $r.Failed -gt 0 -and $stCode -ge 0 -and $stCode -lt 8) { $stCode = 8 }
        $st = Get-TIBackupStatus -Code $stCode -Interrupted $Interrupted
        $txt = Get-TIBackupReadme -Info ([pscustomobject]@{
            Version = $Version; Status = $st.Text; Computer = $Computer; Windows = [string]$Source.Label
            User = $name; Account = [string]$User.Account; Source = $src; Folder = $folder
            Start = $start; End = (Get-Date); Seconds = ((Get-Date) - $start).TotalSeconds
            Bytes = $(if ($Interrupted) { $cur } else { $r.Bytes }); Files = $r.Files; FilesTotal = $r.FilesTotal; Failed = $r.Failed
            Code = $r.Code; CodeRaw = $r.CodeRaw; CodeText = $r.Text
            CacheSkipped = $SkipCache; HivesSkipped = $r.HivesSkipped; Interrupted = $Interrupted
        })
        Write-TIBackupReadmeFile -Folder $folder -Text $txt
    }

    $p = $null
    $finished = $false
    $out = ''
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Robocopy
        $psi.Arguments = $cmdLine
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        try {
            $enc = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
            $psi.StandardOutputEncoding = $enc
            $psi.StandardErrorEncoding = $enc
        } catch { }
        try { $p = [System.Diagnostics.Process]::Start($psi) }
        catch { Emit ('{0}: o robocopy não abriu: {1}' -f $name, $_.Exception.Message) 'Error' }
        if ($p) {
            $outTask = $p.StandardOutput.ReadToEndAsync()
            $errTask = $p.StandardError.ReadToEndAsync()
            $next = (Get-Date).AddSeconds(2)
            $step = 10
            while (-not $p.WaitForExit(400)) {
                if ((Get-Date) -lt $next) { continue }
                $t0 = Get-Date
                $cur = [double](Get-TISafeSize -Path $folder)
                $took = ((Get-Date) - $t0).TotalSeconds
                $next = (Get-Date).AddSeconds([Math]::Max(2.0, 3 * $took))
                $pct = Get-TIBackupPercent -Done ($DoneBefore + $cur) -Total $Total
                $upct = Get-TIBackupPercent -Done $cur -Total $est
                # no console só a cada 10% (o resto fica nos detalhes técnicos)
                $lvl = 'Debug'
                if ($upct -ge $step) { $lvl = 'Info'; $step = ([int][Math]::Floor($upct / 10) + 1) * 10 }
                Emit ('Copiando {0} ({1}/{2}): {3} de {4}' -f $name, $Index, $Count, (Format-TIByte $cur), (Format-TIByte $est)) $lvl $pct
            }
            $p.WaitForExit()
            $r.CodeRaw = [int]$p.ExitCode
            $finished = $true
            try { $out = ([string]$outTask.Result + [string]$errTask.Result).Trim() } catch { }
        }
    } finally {
        if ($p -and -not $finished) {
            try { if (-not $p.HasExited) { $p.Kill(); [void]$p.WaitForExit(5000) } } catch { }
            try { & $readme $true } catch { }
            Emit ('Cópia de {0} interrompida: a pasta {1} ficou INCOMPLETA (veja o LEIA-ME.txt).' -f $name, $folder) 'Warn'
        }
        if ($p) { try { $p.Dispose() } catch { } }
    }
    if (-not $finished) {
        # o robocopy nem abriu: não deixa uma pasta vazia para trás
        try { [System.IO.Directory]::Delete($folder, $false) } catch { }
        $r.Folder = ''
        $r.Text = 'O robocopy não rodou.'
        return $r
    }

    $r.Seconds = [int]((Get-Date) - $start).TotalSeconds
    $r.Duration = Format-TIBackupDuration -Seconds $r.Seconds
    $r.Code = Get-TIBackupEffectiveCode -Code $r.CodeRaw
    $logText = ''
    try { if ([System.IO.File]::Exists($log)) { $logText = [System.IO.File]::ReadAllText($log, [System.Text.Encoding]::Unicode) } } catch { }
    $sum = ConvertFrom-TIBackupRobocopySummary -Text $logText
    if ($sum.Found) {
        $r.Files = $sum.FilesCopied
        $r.FilesTotal = $sum.FilesTotal
        $r.Failed = $sum.FilesFailed + $sum.DirsFailed
    }
    if ($sum.BytesCopied -ge 0) { $r.Bytes = $sum.BytesCopied } else { $r.Bytes = [double](Get-TISafeSize -Path $folder) }

    $rr = Get-TIRobocopyResult -ExitCode $r.Code
    $st = Get-TIBackupStatus -Code $r.Code
    $r.Word = $st.Word
    $r.Level = [string]$rr.Level
    if (-not $r.Level) { $r.Level = $st.Level }
    # falha no resumo sem o bit 8 no código (não deveria acontecer): não sai verde
    if ($r.Failed -gt 0 -and $r.Level -eq 'Success') { $r.Level = 'Warn'; $r.Word = 'Com falhas' }
    $r.Text = [string]$rr.Text

    $errs = Get-TIBackupRobocopyErrors -Text $logText -Max 6
    foreach ($e in @($errs.Lines)) { Emit ('  {0}' -f $e) 'Warn' }
    if ($errs.Count -gt @($errs.Lines).Count) {
        Emit ('  ... e mais {0} falha(s): lista completa em {1}' -f ($errs.Count - @($errs.Lines).Count), $log) 'Warn'
    }
    if ($out -and $r.Code -ge 16) {
        foreach ($l in @(($out -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 6)) { Emit ('  robocopy: {0}' -f $l.Trim()) 'Warn' }
    }

    try { & $readme $false }
    catch { Emit ('{0}: não foi possível gravar o LEIA-ME.txt: {1}' -f $name, $_.Exception.Message) 'Warn' }

    $lvl = 'Success'
    if (-not $rr.Ok) { $lvl = 'Error' }
    elseif ($rr.Level -eq 'Warn' -or $r.Failed -gt 0) { $lvl = 'Warn' }
    Emit ('{0}: {1} - {2} arquivo(s), {3}, {4} falha(s), {5}. {6}' -f $name, $r.Word, $r.Files, (Format-TIByte $r.Bytes),
        $r.Failed, $r.Duration, $rr.Text) $lvl (Get-TIBackupPercent -Done ($DoneBefore + $est) -Total $Total)
    return $r
}

# Backup dos usuários marcados, um de cada vez. Espaço conferido de novo na hora.
function Invoke-TIBackupRun {
    param($Items, $Source, $Dest, [bool]$SkipCache = $true, [string]$Computer = '', [string]$Version = '')
    $Items = @($Items | Where-Object { $_ -and $_.Path })
    if ($Items.Count -eq 0) { Emit 'Nenhum usuário marcado.' 'Warn'; return }
    if (-not $Source -or -not $Dest -or -not $Dest.Root) { throw 'Origem ou destino não informados.' }
    $robo = Join-Path (Get-TIWinDir) 'System32\robocopy.exe'
    if (-not (Test-Path -LiteralPath $robo)) { throw ('robocopy.exe não encontrado em {0}.' -f $robo) }
    $isAdmin = Test-TIBackupAdmin
    $total = Get-TIBackupEstimate -Items $Items -SkipCache $SkipCache

    $free = -1.0
    try {
        $di = New-Object System.IO.DriveInfo([string]$Dest.Root)
        if ($di.IsReady) { $free = [double]$di.AvailableFreeSpace }
    } catch { }
    if ($free -lt 0) { try { $free = [double]$Dest.Free } catch { $free = -1.0 } }
    $chk = Test-TIBackupSpace -Needed $total -Free $free
    if (-not $chk.Ok) {
        if ($chk.Known) {
            Emit ('Não cabe em {0}: precisa de {1} (com 5% de folga) e há {2} livres. Nada foi copiado.' -f $Dest.Root, (Format-TIByte $chk.Need), (Format-TIByte $chk.Free)) 'Error'
        } else {
            Emit ('Não foi possível ler o espaço livre de {0}. Nada foi copiado.' -f $Dest.Root) 'Error'
        }
        return
    }

    $stamp = Get-Date
    $base = Get-TIBackupBase -DestRoot ([string]$Dest.Root) -Computer $Computer
    try { [void][System.IO.Directory]::CreateDirectory($base) }
    catch { throw ('Não foi possível criar a pasta {0} (disco protegido contra gravação?): {1}' -f $base, $_.Exception.Message) }
    Emit ('Backup de {0} usuário(s) de {1} ({2}) para {3}: cerca de {4}, {5} livres.' -f $Items.Count, $Source.Label, $Source.Drive, $base,
        (Format-TIByte $total), (Format-TIByte $chk.Free)) 'Info' 0
    if (-not $isAdmin) { Emit 'Sem administrador: arquivos protegidos podem falhar (cópia sem o modo de backup /ZB).' 'Warn' }

    $results = New-Object System.Collections.ArrayList
    $done = 0.0
    $i = 0
    foreach ($u in $Items) {
        $i++
        $one = Invoke-TIBackupUser -User $u -Source $Source -Dest $Dest -Computer $Computer -Stamp $stamp -SkipCache $SkipCache `
                                   -IsAdmin $isAdmin -Robocopy $robo -Index $i -Count $Items.Count -DoneBefore $done -Total $total -Version $Version
        [void]$results.Add($one)
        $done += Get-TIBackupEstimate -Items @($u) -SkipCache $SkipCache
    }

    Emit '--- Resumo do backup ---' 'Info' 100
    $bad = 0
    foreach ($x in $results) {
        if ($x.Level -eq 'Error') { $bad++ }
        $lvl = 'Success'
        if ($x.Level -ne 'Success') { $lvl = 'Warn' }
        Emit ('{0}: {1}; {2} arquivo(s); {3}; {4} falha(s); {5}' -f $x.Name, $x.Word, $x.Files, (Format-TIByte $x.Bytes), $x.Failed, $x.Duration) $lvl
    }
    if ($bad -gt 0) { Emit ('Backup gravado em {0}, com falhas em {1} usuário(s): veja o _robocopy.log na pasta de cada um.' -f $base, $bad) 'Warn' }
    else { Emit ('Backup gravado em {0}.' -f $base) 'Success' }

    $destFree = -1.0
    try {
        $di2 = New-Object System.IO.DriveInfo([string]$Dest.Root)
        if ($di2.IsReady) { $destFree = [double]$di2.AvailableFreeSpace }
    } catch { }
    return [pscustomobject]@{ Kind = 'BackupRun'; Base = $base; Results = $results.ToArray(); DestFree = $destFree; Started = $stamp }
}
'@

# ---------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------
$global:Backup = @{
    Scanned    = $false
    Installs   = @()
    Locked     = 0
    Source     = $null
    UsersRoot  = ''
    Users      = @()
    UsersOk    = $false
    Volumes    = @()
    Dest       = $null
    DestRoot   = ''
    SourceDisk = -1
    SkipCache  = $true
    LastBase   = ''
    Filling    = $false
    SrcGrid    = $null
    SrcInfo    = $null
    UserGrid   = $null
    UserInfo   = $null
    MarkBtns   = @()
    DestGrid   = $null
    DestInfo   = $null
    ResultGrid = $null
    RunInfo    = $null
    RunBtn     = $null
    OpenBtn    = $null
    Summary    = @{}
}

# Coluna 0 da lista de usuários: caixa desenhada com glifo (mesmo visual dos perfis da Manutenção)
$global:BackupGlyph = @{
    On  = [string][char]0xE73A   # CheckboxComposite
    Off = [string][char]0xE739   # Checkbox
}

function Test-BackupWinPE {
    if (Get-Command Test-TIWinPE -ErrorAction SilentlyContinue) { try { return [bool](Test-TIWinPE) } catch { } }
    return [bool]$global:TIWinPE
}

function Set-BackupHint {
    param($Label, [string]$Text, [string]$Tone = 'muted')
    if ($Label -and -not $Label.IsDisposed) { $Label.Text = $Text; $Label.ForeColor = Get-TIToneColor $Tone }
}

function Set-BackupSummary {
    param([string]$Key, [string]$Text, [string]$Tone = '')
    $r = $global:Backup.Summary[$Key]
    if ($r) { Set-TIRowValue $r $Text $Tone }
}

function Get-BackupSourceText {
    param($Src)
    if (-not $Src) { return '' }
    $label = [string]$Src.Label
    if (-not $label) { $label = 'Windows' }
    return ('{0} em {1}{2}' -f $label, $Src.Drive, $(if ($Src.IsRunning) { ' (este PC)' } else { '' }))
}

# Nome do PC na pasta do backup: o da instalação de origem (no WinPE, o $env:COMPUTERNAME
# é o do próprio WinPE e não serve)
function Get-BackupComputer {
    $s = $global:Backup.Source
    if (-not $s) { return 'PC' }
    $n = [string]$s.ComputerName
    if (-not $n -and $s.IsRunning) { $n = [string]$env:COMPUTERNAME }
    if (-not $n) { $n = 'Windows-' + ([string]$s.Drive).TrimEnd(':', '\') }
    return $n
}

function Get-BackupMarked {
    return @($global:Backup.Users | Where-Object { $_ -and $_.Marked })
}

function Set-BackupRowMark {
    param($Row, [bool]$On)
    if (-not $Row -or -not $Row.Tag) { return }
    $Row.Tag.Marked = $On
    $Row.Cells[0].Value = $(if ($On) { $global:BackupGlyph.On } else { $global:BackupGlyph.Off })
    $Row.Cells[0].Style.ForeColor = $(if ($On) { $global:Pal.Primary } else { $global:Pal.TextMuted })
    $Row.Cells[0].Style.SelectionForeColor = $Row.Cells[0].Style.ForeColor
}

# Clique na caixa, Espaço ou duplo clique: se alguma linha estiver desmarcada, marca todas; senão desmarca
function Switch-BackupRows {
    param($Rows)
    $rows = @($Rows | Where-Object { $_ -and $_.Tag })
    if ($rows.Count -eq 0) { return }
    $on = (@($rows | Where-Object { -not $_.Tag.Marked }).Count -gt 0)
    foreach ($r in $rows) { Set-BackupRowMark -Row $r -On $on }
    Update-BackupSummary
}

function Set-BackupMarkAll {
    param([bool]$On)
    $grid = $global:Backup.UserGrid
    if (-not $grid) { return }
    foreach ($r in $grid.Rows) { Set-BackupRowMark -Row $r -On $On }
    Update-BackupSummary
}

# Seleciona na tabela Origem a instalação escolhida (sem disparar nova leitura).
# -SetCurrent move também a célula atual (senão, ao entrar na tabela com Tab, a
# primeira linha seria selecionada sozinha). Nunca dentro do SelectionChanged:
# mudar a célula atual ali dá erro de chamada reentrante no DataGridView.
function Select-BackupSourceRow {
    param([switch]$SetCurrent)
    $grid = $global:Backup.SrcGrid
    if (-not $grid) { return }
    $src = $global:Backup.Source
    $global:Backup.Filling = $true
    try {
        $grid.ClearSelection()
        if ($src) {
            foreach ($r in $grid.Rows) {
                if ($r.Tag -and [string]$r.Tag.Root -eq [string]$src.Root) {
                    if ($SetCurrent) { try { $grid.CurrentCell = $r.Cells[0] } catch { } }
                    $r.Selected = $true
                    break
                }
            }
        }
    } catch { } finally { $global:Backup.Filling = $false }
}

function Fill-BackupSources {
    $grid = $global:Backup.SrcGrid
    if (-not $grid) { return }
    $global:Backup.Filling = $true
    try {
        $grid.Rows.Clear()
        foreach ($i in @($global:Backup.Installs)) {
            if (-not $i) { continue }
            $situ = 'Pronto para copiar'
            if ($i.IsRunning) { $situ = 'Este PC (Windows em uso)' }
            elseif ($i.Hibernated) { $situ = 'Desligado com Inicialização rápida' }
            $label = [string]$i.Label
            if (-not $label) { $label = 'Windows' }
            $row = Add-TIRow -Grid $grid -Tag $i -Cells @($label, [string]$i.Drive, [string]$i.ComputerName, $situ)
            $row.Cells[0].ToolTipText = ('{0}{1}' -f $i.WinDir, $(if ($i.Arch) { ' (' + $i.Arch + ')' } else { '' }))
        }
        Clear-TIGridSelection $grid
        Set-TIGridEmptyText $grid 'Nenhum Windows encontrado nos discos deste computador.'
    } finally { $global:Backup.Filling = $false }
    Select-BackupSourceRow -SetCurrent
}

function Fill-BackupUsers {
    param($Rows, [bool]$KeepMarks = $false)
    $keep = @{}
    if ($KeepMarks) { foreach ($u in @($global:Backup.Users)) { if ($u -and $u.Marked) { $keep[[string]$u.Path] = $true } } }
    $list = @($Rows | Where-Object { $_ } | Sort-Object Name)
    $global:Backup.Users = $list
    $grid = $global:Backup.UserGrid
    foreach ($u in $list) {
        # vêm DESMARCADOS: o técnico marca quem quer copiar
        Add-Member -InputObject $u -NotePropertyName 'Marked' -NotePropertyValue ([bool]$keep[[string]$u.Path]) -Force
    }
    if (-not $grid) { return }
    $grid.Rows.Clear()
    foreach ($u in $list) {
        $obs = ''
        if (-not $u.Exists) { $obs = 'Pasta não encontrada' }
        elseif ($u.Loaded) { $obs = 'Conectado: registro do usuário fica de fora' }
        $acct = [string]$u.Account
        $lastKey = [datetime]::MinValue
        if ($u.LastUse -is [datetime]) { $lastKey = [datetime]$u.LastUse }
        $row = Add-TIRow -Grid $grid -Tag $u `
                -Cells @('', $u.Name, $acct, (Format-TIBytes $u.Size), (Format-TIDate $u.LastUse -Relative -Empty 'sem registro'), $obs) `
                -SortKeys @($null, $u.Name, $acct, [double]$u.Size, $lastKey, $obs)
        $row.Cells[1].ToolTipText = ('{0}{1}' -f $u.Path, $(if ($u.Sid) { "`n" + $u.Sid } else { '' }))
        if ($u.CacheSize -gt 0) { $row.Cells[3].ToolTipText = ('Temporários e caches: {0}' -f (Format-TIBytes $u.CacheSize)) }
        $row.Cells[0].ToolTipText = 'Marcar ou desmarcar'
        if ($u.Loaded -or -not $u.Exists) { $row.Cells[5].Style.ForeColor = $global:Pal.Warning; $row.Cells[5].Style.SelectionForeColor = $global:Pal.Warning }
        Set-BackupRowMark -Row $row -On ([bool]$u.Marked)
    }
    Clear-TIGridSelection $grid
    Set-TIGridEmptyText $grid 'Nenhuma pasta de usuário neste Windows.'
}

function Fill-BackupVolumes {
    param($Vols)
    # pendrive do TI Suite por último: um HD externo é o destino mais comum
    $list = @($Vols | Where-Object { $_ } | Sort-Object @{ Expression = { [bool]$_.IsTiSuite } }, @{ Expression = { [string]$_.Drive } })
    $global:Backup.Volumes = $list
    # o destino escolhido continua escolhido (pela raiz) se ainda estiver na lista
    $global:Backup.Dest = $null
    if ($global:Backup.DestRoot) {
        $global:Backup.Dest = @($list | Where-Object { [string]$_.Root -eq [string]$global:Backup.DestRoot }) | Select-Object -First 1
    }
    $grid = $global:Backup.DestGrid
    if (-not $grid) { return }
    $global:Backup.Filling = $true
    try {
        $grid.Rows.Clear()
        $pick = $null
        foreach ($v in $list) {
            $notes = @(Get-TIBackupDestNotes -Dest $v -SourceDisk $global:Backup.SourceDisk)
            $obs = (@($notes | ForEach-Object { $_.Short })) -join '; '
            $label = [string]$v.Label
            if (-not $label) { $label = '(sem nome)' }
            $type = [string]$v.Type
            if (-not $type) { $type = '-' }
            $freeTxt = '?'
            if ($v.Free -ge 0) { $freeTxt = Format-TIBytes $v.Free }
            $row = Add-TIRow -Grid $grid -Tag $v `
                    -Cells @([string]$v.Drive, $label, $type, [string]$v.FileSystem, $freeTxt, (Format-TIBytes $v.Size), $obs) `
                    -SortKeys @([string]$v.Drive, $label, $type, [string]$v.FileSystem, [double]$v.Free, [double]$v.Size, $obs)
            if ($notes.Count -gt 0) {
                $row.Cells[6].ToolTipText = (@($notes | ForEach-Object { $_.Text })) -join "`n"
                if (@($notes | Where-Object { $_.Kind -eq 'samedisk' -or $_.Kind -eq 'fat' }).Count -gt 0) {
                    $row.Cells[6].Style.ForeColor = $global:Pal.Warning
                    $row.Cells[6].Style.SelectionForeColor = $global:Pal.Warning
                }
            }
            if ($global:Backup.Dest -and [object]::ReferenceEquals($v, $global:Backup.Dest)) { $pick = $row }
        }
        Clear-TIGridSelection $grid
        if ($pick) { $pick.Selected = $true }
        Set-TIGridEmptyText $grid 'Nenhum disco para o backup. Conecte um HD externo ou pendrive e clique em Atualizar.'
    } finally { $global:Backup.Filling = $false }
}

function Fill-BackupResults {
    param($Results)
    $grid = $global:Backup.ResultGrid
    if (-not $grid) { return }
    $grid.Rows.Clear()
    foreach ($r in @($Results)) {
        if (-not $r) { continue }
        $row = Add-TIRow -Grid $grid -Tag $r `
                -Cells @([string]$r.Name, [string]$r.Word, [string]$r.Files, (Format-TIBytes $r.Bytes), [string]$r.Failed, [string]$r.Duration, [string]$r.Folder) `
                -SortKeys @([string]$r.Name, [string]$r.Word, [double]$r.Files, [double]$r.Bytes, [double]$r.Failed, [double]$r.Seconds, [string]$r.Folder)
        $tone = $global:Pal.Success
        if ($r.Level -eq 'Error') { $tone = $global:Pal.Danger }
        elseif ($r.Level -eq 'Warn') { $tone = $global:Pal.Warning }
        $row.Cells[1].Style.ForeColor = $tone
        $row.Cells[1].Style.SelectionForeColor = $tone
        $row.Cells[1].ToolTipText = [string]$r.Text
        $row.Cells[6].ToolTipText = [string]$r.Folder
    }
    Clear-TIGridSelection $grid
}

function Update-BackupSourceInfo {
    $b = $global:Backup
    $parts = New-Object System.Collections.ArrayList
    $tone = 'muted'
    if (-not $b.Scanned) {
        [void]$parts.Add('Procurando o Windows nos discos...')
    } elseif (@($b.Installs).Count -eq 0) {
        [void]$parts.Add('Nenhum Windows para copiar nos discos deste computador.')
        $tone = 'warn'
    } elseif ($global:TIRecovery) {
        [void]$parts.Add('No boot pelo pendrive o Windows do disco está desligado: tudo pode ser copiado, inclusive o registro dos usuários.')
    } else {
        [void]$parts.Add('Este PC vem primeiro. Outro Windows encontrado nos discos também pode ser a origem: clique na linha dele.')
    }
    if ($b.Locked -gt 0) {
        $tone = 'warn'
        if ($global:TIRecovery) {
            [void]$parts.Add(('{0} Windows com BitLocker travado não aparece(m) aqui: destrave na área Recuperação (com a chave de recuperação) e clique em Atualizar.' -f $b.Locked))
        } else {
            [void]$parts.Add(('{0} Windows com BitLocker travado não aparece(m) aqui: destrave a unidade no Explorador de Arquivos (ou no boot pelo pendrive, na área Recuperação) e clique em Atualizar.' -f $b.Locked))
        }
    }
    if ($b.Source -and $b.Source.Hibernated -and -not $b.Source.IsRunning) {
        [void]$parts.Add('Este Windows foi desligado com a Inicialização rápida: arquivos abertos na última sessão podem estar um pouco desatualizados.')
    }
    if (-not $global:TI.Elevated) {
        $tone = 'warn'
        [void]$parts.Add('Sem administrador, o tamanho das pastas de outros usuários pode sair menor, e o backup precisa do TI Suite aberto como administrador.')
    }
    Set-BackupHint $b.SrcInfo (($parts.ToArray()) -join ' ') $tone
}

# Resumo, dicas e botões (chamado a cada mudança de marcação, destino ou opção)
function Update-BackupSummary {
    $b = $global:Backup
    $src = $b.Source
    if ($src) { Set-BackupSummary 'source' (Get-BackupSourceText $src) }
    elseif ($b.Scanned) { Set-BackupSummary 'source' 'Nenhum Windows para copiar' 'warn' }
    else { Set-BackupSummary 'source' 'Procurando...' 'muted' }

    $users = @($b.Users | Where-Object { $_ })
    $marked = @(Get-BackupMarked)
    $est = Get-TIBackupEstimate -Items $marked -SkipCache ([bool]$b.SkipCache)
    if ($marked.Count -eq 0) {
        Set-BackupSummary 'users' 'Nenhum marcado (marque na lista Usuários)' 'muted'
        Set-BackupSummary 'size' '-' 'muted'
    } else {
        $names = (@($marked | Select-Object -First 4 | ForEach-Object { $_.Name })) -join ', '
        if ($marked.Count -gt 4) { $names += (' e mais {0}' -f ($marked.Count - 4)) }
        Set-BackupSummary 'users' ('{0}: {1}' -f $marked.Count, $names)
        Set-BackupSummary 'size' ('{0}{1}' -f (Format-TIBytes $est), $(if ($b.SkipCache) { ' (sem temporários e caches)' } else { ' (pasta inteira)' }))
    }

    $dest = $b.Dest
    if ($dest) {
        Set-BackupSummary 'dest' ((Get-TIBackupBase -DestRoot ([string]$dest.Root) -Computer (Get-BackupComputer)) + '\')
        if ($dest.Free -ge 0) {
            $chk = Test-TIBackupSpace -Needed $est -Free $dest.Free
            if ($marked.Count -eq 0) { Set-BackupSummary 'free' ('{0} livres' -f (Format-TIBytes $dest.Free)) }
            elseif ($chk.Ok) { Set-BackupSummary 'free' ('{0} livres: cabe' -f (Format-TIBytes $dest.Free)) 'ok' }
            else { Set-BackupSummary 'free' ('{0} livres: não cabe (faltam {1})' -f (Format-TIBytes $dest.Free), (Format-TIBytes $chk.Missing)) 'crit' }
        } else {
            Set-BackupSummary 'free' 'Desconhecido (clique em Atualizar)' 'warn'
        }
    } else {
        Set-BackupSummary 'dest' 'Escolha o disco na tabela Destino' 'muted'
        Set-BackupSummary 'free' '-' 'muted'
    }

    # Dica dos usuários
    if (-not $src) {
        Set-BackupHint $b.UserInfo $(if ($b.Scanned) { 'Nenhum Windows de origem para listar usuários.' } else { 'Procurando o Windows...' })
    } elseif ($b.Scanned -and -not $b.UsersOk -and $users.Count -eq 0) {
        Set-BackupHint $b.UserInfo 'Não foi possível ler os usuários deste Windows (detalhes no console). Clique em Atualizar.' 'crit'
    } elseif ($users.Count -eq 0) {
        Set-BackupHint $b.UserInfo 'Nenhuma pasta de usuário neste Windows.'
    } else {
        $txt = '{0} de {1} usuário(s) marcado(s) ({2}). Nada vem marcado: clique na caixa ou use Espaço para marcar quem vai ser copiado.' -f $marked.Count, $users.Count, (Format-TIBytes $est)
        $tone = 'muted'
        if ($marked.Count -gt 0) { $tone = 'primary' }
        $on = @($users | Where-Object { $_.Loaded })
        if ($on.Count -gt 0) {
            $txt += (' Conectado agora: {0} (o registro do usuário, NTUSER.DAT e UsrClass.dat, fica de fora porque o Windows prende esses arquivos).' -f ((@($on | ForEach-Object { $_.Name })) -join ', '))
        }
        Set-BackupHint $b.UserInfo $txt $tone
    }

    # Dica do destino
    if ($dest) {
        $notes = @(Get-TIBackupDestNotes -Dest $dest -SourceDisk $b.SourceDisk)
        $head = '{0} ({1}{2}{3}): {4} livres de {5}.' -f $dest.Drive, $(if ($dest.Label) { $dest.Label } else { 'sem nome' }),
                $(if ($dest.Type) { ', ' + $dest.Type } else { '' }), $(if ($dest.FileSystem) { ', ' + $dest.FileSystem } else { '' }),
                $(if ($dest.Free -ge 0) { Format-TIBytes $dest.Free } else { '?' }), (Format-TIBytes $dest.Size)
        if ($notes.Count -gt 0) { Set-BackupHint $b.DestInfo ($head + ' ' + ((@($notes | ForEach-Object { $_.Text })) -join ' ')) 'warn' }
        else { Set-BackupHint $b.DestInfo $head 'muted' }
    } elseif ($b.Scanned -and $src -and @($b.Volumes).Count -eq 0) {
        Set-BackupHint $b.DestInfo 'Nenhum disco disponível. Conecte um HD externo ou pendrive e clique em Atualizar (Ctrl+R).' 'warn'
    } else {
        Set-BackupHint $b.DestInfo 'Clique na linha do disco que vai receber o backup (HD externo ou pendrive). O disco da origem não aparece.'
    }

    if ($b.RunBtn) {
        $b.RunBtn.Enabled = ($marked.Count -gt 0 -and $null -ne $src -and $null -ne $dest)
        $b.RunBtn.Text = $(if ($marked.Count -gt 0) { 'Fazer backup ({0})' -f $marked.Count } else { 'Fazer backup' })
    }
    if ($b.OpenBtn) { $b.OpenBtn.Enabled = [bool]$b.LastBase }
    foreach ($x in @($b.MarkBtns)) { if ($x) { $x.Enabled = ($users.Count -gt 0) } }
}

# Leitura da área. Sem -Source: tudo (instalações, usuários e discos), mantendo a origem
# já escolhida. Com -Source: só os usuários e os discos da instalação clicada.
function Invoke-BackupScan {
    param($Source = $null)
    if ($global:TI.Busy) { return }
    $prefer = ''
    if ($Source) {
        $global:Backup.Source = $Source
        $global:Backup.UsersRoot = ''
        $global:Backup.UsersOk = $false
        Fill-BackupUsers -Rows @()
        Fill-BackupVolumes -Vols @()
        Update-BackupSourceInfo
        Update-BackupSummary
        Set-BackupHint $global:Backup.UserInfo ('Lendo os usuários de {0}...' -f (Get-BackupSourceText $Source))
    } elseif ($global:Backup.Source) {
        $prefer = [string]$global:Backup.Source.Root
    }
    $name = 'Leitura para o backup'
    if ($Source) { $name = 'Leitura dos usuários' }
    [void](Invoke-TIAsync -Name $name -Quiet -Context @{ Source = $Source; Prefer = $prefer } -Script {
        $res = $null
        try { $res = Get-TIBackupScan -Source $Context.Source -PreferRoot ([string]$Context.Prefer) }
        catch { Emit ('Não foi possível ler os dados para o backup: {0}' -f $_.Exception.Message) 'Error' }
        if ($res) { $res }
    } -OnComplete {
        param($r)
        Complete-BackupScan (@($r | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'BackupScan' }) | Select-Object -First 1)
    })
}

function Complete-BackupScan {
    param($Res)
    $b = $global:Backup
    if (-not $Res -or ($Res.Full -and -not $Res.Ok)) {
        $b.Scanned = $true
        if (-not $Res -or $Res.Full) {
            $b.Installs = @()
            $b.Source = $null
            Fill-BackupSources
            Set-TIGridEmptyText $b.SrcGrid 'Não foi possível procurar o Windows. Veja o console (F12) e clique em Atualizar.'
        }
        Fill-BackupUsers -Rows @()
        Fill-BackupVolumes -Vols @()
        Update-BackupSummary
        Set-BackupHint $b.SrcInfo 'Não foi possível ler os dados para o backup (detalhes no console). Clique em Atualizar.' 'crit'
        return
    }
    $b.Scanned = $true
    if ($Res.Full) {
        $b.Installs = @($Res.Installs)
        $b.Locked = [int]$Res.Locked
        $b.Source = $Res.Source
        Fill-BackupSources
    }
    $b.SourceDisk = [int]$Res.SourceDisk
    $root = ''
    if ($b.Source) { $root = [string]$b.Source.Root }
    $same = ($root -ne '' -and $root -eq [string]$b.UsersRoot)
    $b.UsersOk = [bool]$Res.UsersOk
    Fill-BackupUsers -Rows @($Res.Users) -KeepMarks $same
    $b.UsersRoot = $root
    Fill-BackupVolumes -Vols @($Res.Volumes)
    Update-BackupSourceInfo
    Update-BackupSummary
}

function Invoke-BackupRun {
    if ($global:TI.Busy) { return }
    $b = $global:Backup
    $items = @(Get-BackupMarked)
    if ($items.Count -eq 0) { Show-TIToast -Text 'Marque ao menos um usuário na lista.' -Type 'Warn'; return }
    if (-not $b.Source) { Show-TIToast -Text 'Escolha o Windows de origem.' -Type 'Warn'; return }
    if (-not $b.Dest) { Show-TIToast -Text 'Escolha na tabela Destino o disco que vai receber o backup.' -Type 'Warn'; return }
    if (-not $global:TI.Elevated) {
        Show-TIToast -Text 'O backup precisa do TI Suite aberto como administrador (clique no selo da barra lateral).' -Type 'Error'
        return
    }
    $dest = $b.Dest
    $est = Get-TIBackupEstimate -Items $items -SkipCache ([bool]$b.SkipCache)
    $chk = Test-TIBackupSpace -Needed $est -Free $dest.Free
    if (-not $chk.Ok) {
        if ($chk.Known) {
            Show-TIMessage -Title 'Não cabe no destino' -Icon 'Warning' -Message ("O backup precisa de {0} (tamanho estimado de {1} mais 5% de folga), e {2} tem {3} livres. Faltam {4}.`n`nEscolha outro disco, desmarque alguns usuários ou ligue 'Pular temporários e caches'." -f `
                (Format-TIBytes $chk.Need), (Format-TIBytes $est), $dest.Drive, (Format-TIBytes $chk.Free), (Format-TIBytes $chk.Missing))
        } else {
            Show-TIMessage -Title 'Espaço livre desconhecido' -Icon 'Warning' -Message ('Não foi possível ler o espaço livre de {0}. Clique em Atualizar (Ctrl+R) e tente de novo.' -f $dest.Drive)
        }
        return
    }

    $src = $b.Source
    $computer = Get-BackupComputer
    $base = Get-TIBackupBase -DestRoot ([string]$dest.Root) -Computer $computer
    $lines = @($items | Select-Object -First 15 | ForEach-Object {
        $extra = Format-TIBytes (Get-TIBackupEstimate -Items @($_) -SkipCache ([bool]$b.SkipCache))
        if ($_.Loaded) { $extra += '; conectado agora' }
        '  {0}  ({1})' -f $_.Name, $extra
    })
    if ($items.Count -gt 15) { $lines += ('  e mais {0}' -f ($items.Count - 15)) }
    $destName = [string]$dest.Drive
    $destDesc = @(@([string]$dest.Label, [string]$dest.Type) | Where-Object { $_ })
    if ($destDesc.Count -gt 0) { $destName += (' (' + ($destDesc -join ', ') + ')') }
    $example = '{0}-{1}' -f (ConvertTo-TIBackupName -Name $items[0].Name -Fallback 'usuario'), (Get-Date -Format 'yyyyMMdd-HHmm')
    $msg = ("Copiar a pasta de {0} usuário(s) de {1}:`n`n{2}`n`nTamanho estimado: {3}{4}`nDestino: {5}\ em {6}`nEspaço livre: {7}`n`nCada usuário vai para uma pasta própria com data e hora (ex.: {8}), com um LEIA-ME.txt. Nada é apagado nem alterado na origem." -f `
            $items.Count, (Get-BackupSourceText $src), ($lines -join "`n"), (Format-TIBytes $est),
            $(if ($b.SkipCache) { ' (sem temporários e caches)' } else { ' (pasta inteira)' }),
            $base, $destName, (Format-TIBytes $dest.Free), $example)
    foreach ($n in @(Get-TIBackupDestNotes -Dest $dest -SourceDisk $b.SourceDisk)) { $msg += ("`n`nAtenção: " + $n.Text) }
    $on = @($items | Where-Object { $_.Loaded })
    if ($on.Count -gt 0) {
        $msg += ("`n`nConectado agora: {0}. O registro desse(s) usuário(s) (NTUSER.DAT e UsrClass.dat) fica de fora, porque o Windows mantém esses arquivos presos; o resto da pasta é copiado." -f ((@($on | ForEach-Object { $_.Name })) -join ', '))
    }
    $ok = Show-TIConfirm -Title 'Fazer backup' -Message $msg -ConfirmText ('Copiar {0} usuário(s)' -f $items.Count) -Style 'Primary' -Icon 'Copy'
    if (-not $ok) { return }

    $ctx = @{
        Items = $items; Source = $src; Dest = $dest; SkipCache = [bool]$b.SkipCache
        Computer = $computer; Version = [string]$global:TI.Version
    }
    [void](Invoke-TIAsync -Name ('Backup de {0} usuário(s)' -f $items.Count) -RequiresAdmin -Context $ctx `
            -AuditDetail (Get-TIBackupAuditDetail -Names @($items | ForEach-Object { $_.Name }) -Base $base) -Script {
        Invoke-TIBackupRun -Items $Context.Items -Source $Context.Source -Dest $Context.Dest -SkipCache ([bool]$Context.SkipCache) `
                           -Computer ([string]$Context.Computer) -Version ([string]$Context.Version)
    } -OnComplete {
        param($r)
        Complete-BackupRun (@($r | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'BackupRun' }) | Select-Object -First 1)
    })
}

function Complete-BackupRun {
    param($Res)
    if (-not $Res) { return }
    $b = $global:Backup
    $b.LastBase = [string]$Res.Base
    $all = @($Res.Results | Where-Object { $_ })
    Fill-BackupResults $all
    if ($b.Dest -and $null -ne $Res.DestFree -and [double]$Res.DestFree -ge 0) { $b.Dest.Free = [double]$Res.DestFree }
    # espaço livre novo na tabela (mantém o destino escolhido)
    Fill-BackupVolumes -Vols @($b.Volumes)
    $bad = @($all | Where-Object { $_.Level -eq 'Error' }).Count
    $warn = @($all | Where-Object { $_.Level -eq 'Warn' }).Count
    $txt = 'Último backup às {0}: {1} usuário(s) em {2}.' -f (Get-Date -Format 'HH:mm'), $all.Count, $Res.Base
    if ($bad -gt 0) { $txt += (' {0} com falhas: veja o LEIA-ME.txt e o _robocopy.log na pasta de cada um.' -f $bad) }
    elseif ($warn -gt 0) { $txt += (' {0} com avisos (veja o console).' -f $warn) }
    if (Test-BackupWinPE) { $txt += ' Antes de desconectar o disco, feche o TI Suite e desligue o computador pelo menu.' }
    else { $txt += ' Use "Remover hardware com segurança" antes de desconectar o disco.' }
    $tone = 'ok'
    if ($bad -gt 0) { $tone = 'crit' } elseif ($warn -gt 0) { $tone = 'warn' }
    Set-BackupHint $b.RunInfo $txt $tone
    Update-BackupSummary
}

# Só fora do WinPE (lá não há Explorador de Arquivos)
function Open-BackupFolder {
    $dir = [string]$global:Backup.LastBase
    if (-not $dir) { return }
    if (Test-BackupWinPE) { Show-TIToast -Text ('Backup em {0}' -f $dir) -Type 'Info'; return }
    try {
        if (-not (Test-Path -LiteralPath $dir)) {
            Show-TIToast -Text 'A pasta do backup não foi encontrada (o disco foi desconectado?).' -Type 'Warn'
            return
        }
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $dir)
    } catch {
        Show-TIToast -Text ('Não foi possível abrir a pasta: {0}' -f $_.Exception.Message) -Type 'Error'
    }
}

$wsBackup = @{
    Id       = 'backup'
    Title    = 'Backup de usuários'
    Sub      = 'Copia a pasta dos usuários (C:\Users\<nome>) para um HD externo ou pendrive'
    Icon     = 'Copy'
    Modes    = 'Both'
    Keywords = 'backup copia copiar salvar usuario usuarios pasta perfil documentos desktop area de trabalho fotos arquivos disco externo hd pendrive robocopy recuperacao'

    OnActivate = { if (-not $global:Backup.Scanned) { Invoke-BackupScan } }
    Refresh    = { Invoke-BackupScan }

    Actions = {
        param($Bar)
        $b = New-TIButton -Text 'Atualizar' -Style 'Outline' -Width 116 -Height 34 -Icon 'Refresh' -Tip 'Procurar de novo o Windows, os usuários e os discos (Ctrl+R)'
        $b.Add_Click({ Invoke-BackupScan })
        $Bar.Controls.Add($b)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $w = $global:Theme.CardWidth

        # --- Origem ---------------------------------------------------------
        $bSrc = New-TICard -Parent $flow -Title 'Origem' -Desc 'Windows de onde as pastas dos usuários serão copiadas' -Icon 'PC' -Half -Width $w -Height 236
        $global:Backup.SrcInfo = New-TIHint -Parent $bSrc -Text 'Procurando o Windows nos discos...' -TopGap 0 -BottomGap 6
        $gSrc = New-TIGrid -Parent $bSrc -Headers @('Windows', 'Unidade', 'Computador', 'Situação') -Widths @(230, 70, 120, 170) `
                           -EmptyText 'Procurando o Windows nos discos...'
        $gSrc.Tag = 'tistretch'
        $gSrc.Height = 128
        $gSrc.Add_SelectionChanged({
            if ($global:Backup.Filling) { return }
            $row = @($this.SelectedRows) | Select-Object -First 1
            if (-not $row -or -not $row.Tag) { Select-BackupSourceRow; return }
            $inst = $row.Tag
            $cur = $global:Backup.Source
            if ($cur -and [string]$cur.Root -eq [string]$inst.Root) { return }
            if ($global:TI.Busy) { Select-BackupSourceRow; return }
            Invoke-BackupScan -Source $inst
        })
        $global:Backup.SrcGrid = $gSrc

        # --- Destino --------------------------------------------------------
        $bDest = New-TICard -Parent $flow -Title 'Destino' -Desc 'Disco conectado que vai receber o backup' -Icon 'Usb' -Half -Width $w -Height 236
        $global:Backup.DestInfo = New-TIHint -Parent $bDest -Text 'Clique na linha do disco que vai receber o backup.' -TopGap 0 -BottomGap 6
        $gDest = New-TIGrid -Parent $bDest -Headers @('Unidade', 'Nome', 'Tipo', 'Sistema', 'Livre', 'Tamanho', 'Observação') `
                            -Widths @(66, 120, 74, 70, 86, 86, 180) -EmptyText 'Procurando discos...'
        $gDest.Tag = 'tistretch'
        $gDest.Height = 158
        $gDest.Add_SelectionChanged({
            if ($global:Backup.Filling) { return }
            $row = @($this.SelectedRows) | Select-Object -First 1
            if ($row -and $row.Tag) {
                $global:Backup.Dest = $row.Tag
                $global:Backup.DestRoot = [string]$row.Tag.Root
            } else {
                $global:Backup.Dest = $null
                $global:Backup.DestRoot = ''
            }
            Update-BackupSummary
        })
        $global:Backup.DestGrid = $gDest

        # --- Usuários ---------------------------------------------------------
        $bUsers = New-TICard -Parent $flow -Title 'Usuários' -Stretch `
                -Desc 'Marque quem vai ser copiado: a pasta inteira do usuário vai para o backup' -Icon 'People' -Width $w -Height 380
        $barU = New-TIButtonBar -Parent $bUsers
        $btnAll = New-TIButton -Text 'Marcar todos' -Style 'Ghost' -Width 132 -Height 36 -Icon 'CheckList'
        $btnAll.Enabled = $false
        $btnAll.Add_Click({ Set-BackupMarkAll -On $true })
        $barU.Controls.Add($btnAll)
        $btnNone = New-TIButton -Text 'Desmarcar todos' -Style 'Ghost' -Width 150 -Height 36 -Icon 'Undo'
        $btnNone.Enabled = $false
        $btnNone.Add_Click({ Set-BackupMarkAll -On $false })
        $barU.Controls.Add($btnNone)
        $global:Backup.MarkBtns = @($btnAll, $btnNone)
        $global:Backup.UserInfo = New-TIHint -Parent $bUsers -Text 'Procurando o Windows...' -TopGap 0 -BottomGap 6

        $gUsers = New-TIGrid -Parent $bUsers -Headers @('', 'Usuário', 'Conta', 'Tamanho', 'Último uso', 'Observação') `
                             -Widths @(40, 150, 180, 96, 180, 230) -Multi -EmptyText 'Os usuários do Windows de origem aparecem aqui.'
        $gUsers.Tag = 'tistretch'
        $gUsers.Height = 240
        $chk = $gUsers.Columns[0]
        $chk.AutoSizeMode = 'None'
        $chk.Width = 40
        $chk.SortMode = 'NotSortable'
        $chk.Resizable = 'False'
        $chk.DefaultCellStyle.Font = New-TIFont 12 Regular 'Segoe MDL2 Assets'
        $chk.DefaultCellStyle.Alignment = 'MiddleCenter'
        $chk.ToolTipText = 'Clique para marcar ou desmarcar todos'
        # Clique na caixa (MouseUp conta os dois cliques de um duplo clique rápido)
        $gUsers.Add_CellMouseUp({
            param($s, $e)
            if ($e.Button -ne 'Left' -or $e.RowIndex -lt 0 -or $e.ColumnIndex -ne 0 -or $global:TI.Busy) { return }
            Switch-BackupRows @($s.Rows[$e.RowIndex])
        })
        $gUsers.Add_CellMouseDoubleClick({
            param($s, $e)
            if ($e.Button -ne 'Left' -or $e.RowIndex -lt 0 -or $e.ColumnIndex -le 0 -or $global:TI.Busy) { return }
            Switch-BackupRows @($s.Rows[$e.RowIndex])
        })
        $gUsers.Add_ColumnHeaderMouseClick({
            param($s, $e)
            if ($e.ColumnIndex -ne 0 -or $global:TI.Busy) { return }
            $all = @($global:Backup.Users | Where-Object { $_ })
            $allOn = ($all.Count -gt 0 -and @($all | Where-Object { -not $_.Marked }).Count -eq 0)
            Set-BackupMarkAll -On (-not $allOn)
        })
        $gUsers.Add_KeyDown({
            param($s, $e)
            if ($e.KeyCode -eq 'Space' -and -not $global:TI.Busy) {
                $e.Handled = $true
                $e.SuppressKeyPress = $true
                Switch-BackupRows @($s.SelectedRows)
            }
        })
        $global:Backup.UserGrid = $gUsers

        # --- Fazer backup -------------------------------------------------------
        $bRun = New-TICard -Parent $flow -Title 'Fazer backup' -Stretch `
                -Desc 'Confere o espaço, copia com o robocopy e grava um LEIA-ME.txt em cada pasta' -Icon 'Copy' -Width $w -Height 420
        $iw = Get-TIInnerWidth $bRun
        foreach ($p in @(
            @{ K = 'source'; L = 'Origem' },
            @{ K = 'users';  L = 'Usuários' },
            @{ K = 'size';   L = 'Tamanho estimado' },
            @{ K = 'dest';   L = 'Pasta do backup' },
            @{ K = 'free';   L = 'Espaço livre' }
        )) {
            $r = New-TIRow -Label $p.L -Value '-' -Width $iw -LabelWidth 132
            $r.Value.ForeColor = $global:Pal.TextMuted
            $bRun.Controls.Add($r.Panel)
            $global:Backup.Summary[$p.K] = $r
        }

        $optRow = New-Object System.Windows.Forms.Panel
        $optRow.Tag = 'tirow'
        $optRow.Size = New-Object System.Drawing.Size($iw, 30)
        $optRow.BackColor = [System.Drawing.Color]::Transparent
        $optRow.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 8)
        $bRun.Controls.Add($optRow)
        $sw = New-Object TISuite.ToggleSwitch
        $sw.Location = New-Object System.Drawing.Point(0, 3)
        $sw.AccessibleName = 'Pular temporários e caches'
        $sw.Checked = [bool]$global:Backup.SkipCache
        $sw.Add_CheckedChanged({
            $global:Backup.SkipCache = [bool]$this.Checked
            Update-BackupSummary
        })
        $optRow.Controls.Add($sw)
        $swLbl = New-TILabel -Text 'Pular temporários e caches (pasta Temp e cache dos navegadores, que não fazem falta)' -Size 8.5 -Muted
        $swLbl.Location = New-Object System.Drawing.Point(50, 6)
        $swLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
        $swLbl.Add_Click({ $sw.Checked = -not $sw.Checked }.GetNewClosure())
        $optRow.Controls.Add($swLbl)
        $global:TITip.SetToolTip($swLbl, 'Desligado, a pasta do usuário é copiada inteira, inclusive temporários e caches.')

        $barRun = New-TIButtonBar -Parent $bRun
        $btnRun = New-TIButton -Text 'Fazer backup' -Style 'Primary' -Width 200 -Height 40 -Icon 'Copy' -GlyphSize 13
        $btnRun.Enabled = $false
        $btnRun.Add_Click({ Invoke-BackupRun })
        $barRun.Controls.Add($btnRun)
        $global:Backup.RunBtn = $btnRun
        $btnOpen = New-TIButton -Text 'Abrir pasta do backup' -Style 'Outline' -Width 196 -Height 40 -Icon 'FolderOpen'
        $btnOpen.Enabled = $false
        $btnOpen.Visible = -not (Test-BackupWinPE)
        $btnOpen.Add_Click({ Open-BackupFolder })
        $barRun.Controls.Add($btnOpen)
        $global:Backup.OpenBtn = $btnOpen

        $global:Backup.RunInfo = New-TIHint -Parent $bRun -Text 'Nenhum backup feito nesta sessão.' -TopGap 2 -BottomGap 6
        $gRes = New-TIGrid -Parent $bRun -Headers @('Usuário', 'Situação', 'Arquivos', 'Tamanho', 'Falhas', 'Tempo', 'Pasta') `
                           -Widths @(130, 110, 80, 90, 70, 90, 280) -EmptyText 'O resultado de cada usuário aparece aqui depois do backup.'
        $gRes.Tag = 'tistretch'
        $gRes.Height = 130
        $global:Backup.ResultGrid = $gRes

        Update-BackupSourceInfo
        Update-BackupSummary
    }
}

Register-TIWorkspace @wsBackup
