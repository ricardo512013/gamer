# =====================================================================
# 06-WINDOWS.ps1 - Instalações do Windows nos discos (modo recuperação e backup)
#
# Usado pelas áreas Recuperação e Backup.
#   - O que é puro (sem acesso ao sistema) vale na interface E no worker
#     ($global:TIWindowsShared, mesmo padrão do Inventário).
#   - O resto roda só no worker (Invoke-TIAsync), como administrador.
#   - Hives offline: Mount-TIOfflineHive / Dismount-TIOfflineHive SEMPRE em
#     try/finally por quem chama. Nunca deixar um hive montado.
#   - Nada aqui altera a instalação que está em execução (IsRunning) nem
#     volume bloqueado pelo BitLocker (Locked): Assert-TIOfflineInstall.
# =====================================================================

$global:TIWindowsShared = @'

# Rodando no Windows PE (pendrive de recuperação)?
function Test-TIWinPE {
    try { return [bool](Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') } catch { return $false }
}

# Pasta System32 do sistema em execução (X:\Windows\System32 no WinPE).
# Comandos externos (chkdsk, sfc, dism, bcdboot, reg...) sempre por aqui.
function Get-TISystem32 {
    $sr = $env:SystemRoot
    if (-not $sr) { $sr = $env:windir }
    if (-not $sr) { $sr = 'C:\Windows' }
    return ($sr.TrimEnd('\') + '\System32')
}

# Junta caminhos do Windows por texto, sem passar pelo PSDrive: o Join-Path falha
# com letra montada depois que a tarefa começou (partição do sistema) ou que não
# existe neste runspace.
function Join-TIWinPath {
    param([string]$Path, [string]$Child)
    $p = ([string]$Path).TrimEnd('\')
    $c = ([string]$Child).TrimStart('\')
    if (-not $p) { return $c }
    if (-not $c) { return $p + '\' }
    return ($p + '\' + $c)
}

# 'c', 'c:', 'C:\Users\x' -> 'C:'  ('' quando não há letra)
function ConvertTo-TIDriveLetter {
    param([string]$Path)
    $p = ([string]$Path).Trim()
    if ($p -match '^([A-Za-z])(:|$)') { return ($Matches[1].ToUpperInvariant() + ':') }
    return ''
}

# EditionID do registro -> nome da edição como o Windows mostra
function Get-TIEditionName {
    param([string]$EditionId)
    $map = @{
        'core' = 'Home'; 'coren' = 'Home N'; 'coresinglelanguage' = 'Home Single Language'; 'corecountryspecific' = 'Home China'
        'professional' = 'Pro'; 'professionaln' = 'Pro N'; 'professionaleducation' = 'Pro Education'
        'professionaleducationn' = 'Pro Education N'; 'professionalworkstation' = 'Pro for Workstations'
        'professionalworkstationn' = 'Pro for Workstations N'; 'education' = 'Education'; 'educationn' = 'Education N'
        'enterprise' = 'Enterprise'; 'enterprisen' = 'Enterprise N'; 'enterprises' = 'Enterprise LTSC'
        'enterprisesn' = 'Enterprise LTSC N'; 'enterpriseg' = 'Enterprise G'; 'iotenterprise' = 'IoT Enterprise'
        'iotenterprises' = 'IoT Enterprise LTSC'; 'cloudedition' = 'SE'; 'cloudeditionn' = 'SE N'
        'serverrdsh' = 'Enterprise multissessão'
    }
    $k = ([string]$EditionId).Trim().ToLowerInvariant()
    if ($map.ContainsKey($k)) { return $map[$k] }
    return ([string]$EditionId).Trim()
}

# 'Windows 11 Pro 24H2 (26100.2033)'. O ProductName do registro diz "Windows 10"
# também no 11: pelo build (22000 ou mais) vira Windows 11. Sem DisplayVersion
# (Windows 10 antigo), usa o ReleaseId.
function Get-TIWindowsLabel {
    param(
        [string]$ProductName = '',
        [string]$EditionId = '',
        [int]$Build = 0,
        [int]$Ubr = 0,
        [string]$DisplayVersion = '',
        [string]$ReleaseId = ''
    )
    $pn = (([string]$ProductName).Trim() -replace '\s+', ' ') -replace '^(?i)Microsoft\s+', ''
    $ed = Get-TIEditionName $EditionId
    if (-not $pn -and -not $ed -and $Build -le 0) {
        $name = 'Windows'
    } elseif ($pn -match '(?i)\bserver\b' -or ($Build -gt 0 -and $Build -lt 10240)) {
        $name = $(if ($pn) { $pn } else { 'Windows' })
    } else {
        $fam = 'Windows 10'
        if ($Build -ge 22000) { $fam = 'Windows 11' }
        elseif ($Build -le 0 -and $pn -match '^(?i)Windows 11\b') { $fam = 'Windows 11' }
        # sem EditionID: a edição sai do nome do produto ("Windows 10 Pro" -> "Pro")
        if (-not $ed) { $ed = ($pn -replace '^(?i)Windows(\s+(10|11))?\s*', '').Trim() }
        $name = ('{0} {1}' -f $fam, $ed).Trim()
    }
    $ver = ([string]$DisplayVersion).Trim()
    if (-not $ver) { $ver = ([string]$ReleaseId).Trim() }
    if ($ver) { $name += ' ' + $ver }
    if ($Build -gt 0) {
        $b = $(if ($Ubr -gt 0) { '{0}.{1}' -f $Build, $Ubr } else { [string]$Build })
        $name += (' ({0})' -f $b)
    }
    return $name
}

# Arquitetura: 'AMD64'/'9' -> 'x64', 'x86'/'0' -> 'x86', 'ARM64'/'12' -> 'arm64'
function ConvertTo-TIArchName {
    param($Value)
    $v = ([string]$Value).Trim().ToLowerInvariant()
    if ($v -in @('amd64', 'x64', '9', 'x86_64')) { return 'x64' }
    if ($v -in @('x86', '0', 'i386')) { return 'x86' }
    if ($v -in @('arm64', '12', 'aarch64')) { return 'arm64' }
    return ''
}

# Código de saída do robocopy (bits: 1 copiou, 2 extras no destino, 4 diferenças,
# 8 falhas, 16 erro grave). Ok = menor que 8.
function Get-TIRobocopyResult {
    param([int]$ExitCode)
    $lvl = 'Success'
    if ($ExitCode -lt 0) {
        $lvl = 'Error'
        $t = 'O robocopy não terminou (cancelado, tempo esgotado ou não abriu).'
    } elseif ($ExitCode -ge 16) {
        $lvl = 'Error'
        $t = ('Erro grave do robocopy (código {0}): a cópia não foi feita. Confira se a origem e o destino estão acessíveis e se há espaço.' -f $ExitCode)
    } elseif ($ExitCode -ge 8) {
        $lvl = 'Error'
        $t = ('Falhas na cópia (código {0}): alguns arquivos não foram copiados (em uso, sem permissão ou erro de disco). Veja o _robocopy.log.' -f $ExitCode)
    } elseif ($ExitCode -ge 4) {
        $lvl = 'Warn'
        $t = ('Cópia concluída com diferenças (código {0}): alguns arquivos ou pastas não conferem entre a origem e o destino. Veja o _robocopy.log.' -f $ExitCode)
    } elseif ($ExitCode -ge 2) {
        $what = $(if ($ExitCode -band 1) { 'arquivos copiados' } else { 'nada novo para copiar' })
        $t = ('Cópia concluída (código {0}): {1}; o destino tem arquivos extras que não estão na origem (por exemplo, o próprio log).' -f $ExitCode, $what)
    } elseif ($ExitCode -eq 1) {
        $t = 'Cópia concluída (código 1): arquivos copiados com sucesso.'
    } else {
        $t = 'Nada novo para copiar (código 0): a origem e o destino já estavam iguais.'
    }
    return [pscustomobject]@{ Ok = ($ExitCode -ge 0 -and $ExitCode -lt 8); Level = $lvl; Text = $t; Code = $ExitCode }
}

# Caminho gravado no registro da instalação offline -> caminho de agora. No WinPE
# a unidade do Windows costuma mudar de letra (C: vira D:) e %SystemDrive% é X:.
function Resolve-TIOfflinePath {
    param([string]$Path, [string]$Drive)
    $p = ([string]$Path).Trim().Trim('"').Trim()
    if (-not $p) { return '' }
    $d = ConvertTo-TIDriveLetter $Drive
    if (-not $d) { return $p }
    $rep = @(
        @('%SystemDrive%', $d),
        @('%SystemRoot%', ($d + '\Windows')),
        @('%windir%', ($d + '\Windows')),
        @('%ProgramFiles(x86)%', ($d + '\Program Files (x86)')),
        @('%ProgramW6432%', ($d + '\Program Files')),
        @('%ProgramFiles%', ($d + '\Program Files')),
        @('%CommonProgramFiles(x86)%', ($d + '\Program Files (x86)\Common Files')),
        @('%CommonProgramFiles%', ($d + '\Program Files\Common Files')),
        @('%ProgramData%', ($d + '\ProgramData')),
        @('%ALLUSERSPROFILE%', ($d + '\ProgramData')),
        @('%PUBLIC%', ($d + '\Users\Public'))
    )
    foreach ($r in $rep) {
        $i = $p.IndexOf($r[0], [System.StringComparison]::OrdinalIgnoreCase)
        while ($i -ge 0) {
            $p = $p.Substring(0, $i) + $r[1] + $p.Substring($i + $r[0].Length)
            $i = $p.IndexOf($r[0], $i + $r[1].Length, [System.StringComparison]::OrdinalIgnoreCase)
        }
    }
    if ($p -match '^[A-Za-z]:(\\|$)') { $p = $d + $p.Substring(2) }
    return $p
}
'@
$global:TIWorkerLib += $global:TIWindowsShared
. ([scriptblock]::Create($global:TIWindowsShared))

$global:TIWorkerLib += @'

# ---------------------------------------------------------------------
# Instalações do Windows nos discos (06-Windows.ps1)
# ---------------------------------------------------------------------

# Valores de uma chave do HKLM lidos com .NET: a chave fecha na hora (o PSDrive do
# registro segurava identificadores até o GC e o "reg unload" falhava).
# -Path é relativo ao HKLM. Texto expansível volta SEM expandir (%SystemDrive% do WinPE é X:).
function Read-TIHklmValues {
    param([string]$Path, [string[]]$Names)
    $out = @{}
    $k = $null
    try {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path, $false)
        if ($k) {
            foreach ($n in $Names) {
                try {
                    $v = $k.GetValue($n, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    if ($null -ne $v) { $out[$n] = $v }
                } catch { }
            }
        }
    } catch { } finally {
        if ($k) { try { $k.Close() } catch { } }
    }
    return $out
}

# Todos os valores de uma chave (nome -> valor), sem expandir
function Read-TIHklmAllValues {
    param([string]$Path)
    $out = @{}
    $k = $null
    try {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path, $false)
        if ($k) {
            foreach ($n in @($k.GetValueNames())) {
                try {
                    $v = $k.GetValue($n, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    if ($null -ne $v) { $out[$n] = $v }
                } catch { }
            }
        }
    } catch { } finally {
        if ($k) { try { $k.Close() } catch { } }
    }
    return $out
}

function Get-TIHklmSubKeys {
    param([string]$Path)
    $names = @()
    $k = $null
    try {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path, $false)
        if ($k) { $names = @($k.GetSubKeyNames()) }
    } catch { } finally {
        if ($k) { try { $k.Close() } catch { } }
    }
    return $names
}

# Apaga uma subchave inteira. $false = não existia. Erro sobe para quem chamou.
function Remove-TIHklmSubKeyTree {
    param([string]$Parent, [string]$Name)
    $k = $null
    try {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Parent, $true)
        if (-not $k) { return $false }
        if (@($k.GetSubKeyNames()) -notcontains $Name) { return $false }
        $k.DeleteSubKeyTree($Name)
        return $true
    } finally {
        if ($k) { try { $k.Close() } catch { } }
    }
}

# reg.exe com tempo limite, sem laço do PowerShell (funciona até no finally de
# uma tarefa cancelada). Saída na página OEM.
function Invoke-TIRegExe {
    param([string]$Arguments, [int]$TimeoutSec = 60)
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = Join-TIWinPath (Get-TISystem32) 'reg.exe'
    $p.StartInfo.Arguments = $Arguments
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.CreateNoWindow = $true
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    try {
        $enc = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        $p.StartInfo.StandardOutputEncoding = $enc
        $p.StartInfo.StandardErrorEncoding = $enc
    } catch { }
    try {
        [void]$p.Start()
        $o = $p.StandardOutput.ReadToEndAsync()
        $e = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch { }
            return [pscustomobject]@{ Code = -1; Output = 'tempo esgotado' }
        }
        $p.WaitForExit()
        $txt = ''
        try { $txt = (([string]$o.Result + ' ' + [string]$e.Result) -replace '\s+', ' ').Trim() } catch { }
        return [pscustomobject]@{ Code = [int]$p.ExitCode; Output = $txt }
    } catch {
        return [pscustomobject]@{ Code = -1; Output = $_.Exception.Message }
    } finally {
        try { $p.Dispose() } catch { }
    }
}

# Carrega um hive (SOFTWARE, SYSTEM, NTUSER.DAT...) com nome único e devolve a
# chave montada ('HKLM\TI_OFF_1A2B3C4D'). Quem chama descarrega no finally.
function Mount-TIOfflineHive {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { throw ('Arquivo do registro não encontrado: {0}' -f $Path) }
    $name = ''
    for ($i = 0; $i -lt 5 -and -not $name; $i++) {
        $n = 'TI_OFF_' + ([guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant())
        $k = $null
        try { $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($n, $false) } catch { }
        if ($k) { try { $k.Close() } catch { }; continue }
        $name = $n
    }
    if (-not $name) { throw 'Não foi possível escolher um nome para o registro offline.' }
    $key = 'HKLM\' + $name
    $r = Invoke-TIRegExe -Arguments ('load "{0}" "{1}"' -f $key, $Path)
    if ($r.Code -ne 0) {
        # estourou o tempo: pode ter carregado mesmo assim
        if ($r.Code -eq -1) { [void](Invoke-TIRegExe -Arguments ('unload "{0}"' -f $key) -TimeoutSec 30) }
        throw ('Não foi possível abrir o registro {0} ({1}).' -f $Path, $r.Output)
    }
    return $key
}

# Descarrega o hive: GC antes (identificadores do .NET) e até 3 tentativas.
# $false (e erro no console) se continuou montado.
function Dismount-TIOfflineHive {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return $true }
    $name = $Key -replace '^(?i)(HKLM|HKEY_LOCAL_MACHINE)\\', ''
    for ($i = 1; $i -le 3; $i++) {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        $r = Invoke-TIRegExe -Arguments ('unload "HKLM\{0}"' -f $name) -TimeoutSec 30
        if ($r.Code -eq 0) { return $true }
        # já não estava carregado
        $k = $null
        try { $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($name, $false) } catch { }
        if (-not $k) { return $true }
        try { $k.Close() } catch { }
        [System.Threading.Thread]::Sleep(400 * $i)
    }
    Emit ('O registro offline HKLM\{0} continuou aberto. Feche o TI Suite (ou reinicie o pendrive) antes de mexer nesse Windows.' -f $name) 'Error'
    return $false
}

# Hives TI_OFF_ que sobraram de uma tarefa interrompida. $false = algum não fechou.
function Clear-TIOfflineHives {
    $names = @()
    try { $names = @([Microsoft.Win32.Registry]::LocalMachine.GetSubKeyNames() | Where-Object { $_ -like 'TI_OFF_*' }) } catch { }
    $ok = $true
    foreach ($n in $names) {
        Emit ('Fechando o registro offline que ficou aberto: HKLM\{0}' -f $n) 'Debug'
        if (-not (Dismount-TIOfflineHive -Key ('HKLM\' + $n))) { $ok = $false }
    }
    return $ok
}

# Firmware: no WinPE, PEFirmwareType (1 BIOS, 2 UEFI); fora dele, %firmware_type% ou
# o carregador do bcdedit (winload.efi = UEFI). '' = não deu para saber. Regra pura.
function ConvertTo-TIFirmwareType {
    param($PEFirmwareType = $null, [string]$EnvFirmware = '', [string]$BcdText = '')
    $pe = 0
    if ($null -ne $PEFirmwareType -and ([string]$PEFirmwareType) -match '^\d+$') { $pe = [int]([string]$PEFirmwareType) }
    if ($pe -eq 2) { return 'UEFI' }
    if ($pe -eq 1) { return 'BIOS' }
    $e = ([string]$EnvFirmware).Trim()
    if ($e -match '^(?i)uefi$') { return 'UEFI' }
    if ($e -match '^(?i)(legacy|bios)$') { return 'BIOS' }
    if ($BcdText -match '(?i)\\winload\.efi') { return 'UEFI' }
    if ($BcdText -match '(?i)\\winload\.exe') { return 'BIOS' }
    return ''
}

function Get-TIFirmwareType {
    if (Test-TIWinPE) {
        $v = Read-TIHklmValues -Path 'SYSTEM\CurrentControlSet\Control' -Names @('PEFirmwareType')
        return (ConvertTo-TIFirmwareType -PEFirmwareType $v['PEFirmwareType'])
    }
    $fw = [string]$env:firmware_type
    $bcd = ''
    if (-not $fw) {
        $r = Invoke-TICommand -File (Join-TIWinPath (Get-TISystem32) 'bcdedit.exe') -Arguments '/enum {current}' -TimeoutSec 20
        $bcd = [string]$r.Output
    }
    return (ConvertTo-TIFirmwareType -EnvFirmware $fw -BcdText $bcd)
}

# Desligado com hibernação ou Inicialização rápida: assinatura HIBR/RSTR no
# começo do hiberfil.sys (melhor esforço; o arquivo do Windows em execução fica preso).
function Test-TIHibernated {
    param([string]$Root)
    $f = Join-TIWinPath $Root 'hiberfil.sys'
    $fs = $null
    try {
        if (-not [System.IO.File]::Exists($f)) { return $false }
        $fs = New-Object System.IO.FileStream($f, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $b = New-Object byte[] 4
        if ($fs.Read($b, 0, 4) -lt 4) { return $false }
        $sig = [System.Text.Encoding]::ASCII.GetString($b).ToUpperInvariant()
        return ($sig -eq 'HIBR' -or $sig -eq 'RSTR')
    } catch {
        return $false
    } finally {
        if ($fs) { try { $fs.Dispose() } catch { } }
    }
}

# Volumes BitLocker bloqueados (sem leitura): aparecem na lista com Locked = $true
function Get-TILockedVolumes {
    param($Skip = @{})
    $vols = @()
    try {
        $vols = @(Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -ErrorAction Stop)
    } catch { return }
    foreach ($v in $vols) {
        $lock = -1
        try { $lock = [int](Invoke-CimMethod -InputObject $v -MethodName 'GetLockStatus' -ErrorAction Stop).LockStatus } catch { }
        if ($lock -ne 1) { continue }
        $dl = ConvertTo-TIDriveLetter ([string]$v.DriveLetter)
        if ($dl -and $Skip.ContainsKey($dl)) { continue }
        $size = 0.0
        try {
            $id = ([string]$v.DeviceID) -replace '\\', '\\'
            $wv = @(Get-CimInstance -ClassName Win32_Volume -Filter ("DeviceID='{0}'" -f $id) -ErrorAction Stop) | Select-Object -First 1
            if ($wv) { $size = [double]$wv.Capacity }
        } catch { }
        [pscustomobject]@{
            Drive = $dl; Root = $(if ($dl) { $dl + '\' } else { '' }); WinDir = ''
            Label = 'Volume protegido pelo BitLocker (bloqueado)'; ProductName = ''; Edition = ''; EditionId = ''
            Build = 0; Ubr = 0; DisplayVersion = ''; IsWin11 = $false; ComputerName = ''; Locked = $true; Arch = ''
            IsRunning = $false; SizeBytes = $size; FreeBytes = 0.0; Hibernated = $false
            InstallDate = $null; VolumeLabel = ''; FileSystem = ''; VolumeId = [string]$v.DeviceID; ReadError = ''
        }
    }
}

# Lê versão, edição, nome do PC e arquitetura de uma instalação (registro offline
# ou, para o Windows em execução, o registro ativo)
function Read-TIWindowsInstall {
    param([string]$Drive, [bool]$IsRunning = $false, $DriveInfo = $null)
    $root = $Drive + '\'
    $winDir = $root + 'Windows'
    $o = [pscustomobject]@{
        Drive = $Drive; Root = $root; WinDir = $winDir; Label = ''; ProductName = ''; Edition = ''; EditionId = ''
        Build = 0; Ubr = 0; DisplayVersion = ''; IsWin11 = $false; ComputerName = ''; Locked = $false; Arch = ''
        IsRunning = $IsRunning; SizeBytes = 0.0; FreeBytes = 0.0; Hibernated = $false
        InstallDate = $null; VolumeLabel = ''; FileSystem = ''; VolumeId = ''; ReadError = ''
    }
    if ($DriveInfo) {
        try {
            $o.SizeBytes = [double]$DriveInfo.TotalSize
            $o.FreeBytes = [double]$DriveInfo.AvailableFreeSpace
            $o.VolumeLabel = [string]$DriveInfo.VolumeLabel
            $o.FileSystem = [string]$DriveInfo.DriveFormat
        } catch { }
    }
    $cvNames = @('ProductName', 'EditionID', 'CurrentBuildNumber', 'CurrentBuild', 'UBR', 'DisplayVersion', 'ReleaseId', 'InstallDate')
    $cv = @{}; $cn = @{}; $ev = @{}
    if ($IsRunning) {
        $cv = Read-TIHklmValues -Path 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Names $cvNames
        $cn = Read-TIHklmValues -Path 'SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Names @('ComputerName')
        $ev = Read-TIHklmValues -Path 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Names @('PROCESSOR_ARCHITECTURE')
    } else {
        $key = $null
        try {
            $key = Mount-TIOfflineHive -Path (Join-TIWinPath $winDir 'System32\config\SOFTWARE')
            $cv = Read-TIHklmValues -Path (($key -replace '^HKLM\\', '') + '\Microsoft\Windows NT\CurrentVersion') -Names $cvNames
        } catch {
            $o.ReadError = $_.Exception.Message
            Emit ('{0}: não deu para ler a versão do Windows ({1}).' -f $Drive, $_.Exception.Message) 'Warn'
        } finally {
            if ($key) { [void](Dismount-TIOfflineHive -Key $key) }
        }
        $key = $null
        try {
            $key = Mount-TIOfflineHive -Path (Join-TIWinPath $winDir 'System32\config\SYSTEM')
            $hk = $key -replace '^HKLM\\', ''
            $sel = Read-TIHklmValues -Path ($hk + '\Select') -Names @('Current')
            $cs = 'ControlSet001'
            if ($sel.ContainsKey('Current') -and [int]$sel['Current'] -gt 0) { $cs = 'ControlSet{0:000}' -f [int]$sel['Current'] }
            $cn = Read-TIHklmValues -Path ($hk + '\' + $cs + '\Control\ComputerName\ComputerName') -Names @('ComputerName')
            $ev = Read-TIHklmValues -Path ($hk + '\' + $cs + '\Control\Session Manager\Environment') -Names @('PROCESSOR_ARCHITECTURE')
        } catch {
            if (-not $o.ReadError) { $o.ReadError = $_.Exception.Message }
            Emit ('{0}: não deu para ler o nome do computador ({1}).' -f $Drive, $_.Exception.Message) 'Debug'
        } finally {
            if ($key) { [void](Dismount-TIOfflineHive -Key $key) }
        }
        $o.Hibernated = Test-TIHibernated -Root $root
    }
    $num = { param($x) $n = 0; if ($null -ne $x -and ([string]$x).Trim() -match '^-?\d+$') { $n = [int]([string]$x).Trim() }; $n }
    $o.ProductName = [string]$cv['ProductName']
    $o.EditionId = [string]$cv['EditionID']
    $o.Edition = Get-TIEditionName $o.EditionId
    $o.Build = & $num $cv['CurrentBuildNumber']
    if ($o.Build -le 0) { $o.Build = & $num $cv['CurrentBuild'] }
    $o.Ubr = & $num $cv['UBR']
    $o.DisplayVersion = [string]$cv['DisplayVersion']
    if (-not $o.DisplayVersion) { $o.DisplayVersion = [string]$cv['ReleaseId'] }
    $o.IsWin11 = ($o.Build -ge 22000)
    $o.ComputerName = [string]$cn['ComputerName']
    $idt = & $num $cv['InstallDate']
    if ($idt -gt 0) { try { $o.InstallDate = ([datetime]'1970-01-01').AddSeconds($idt).ToLocalTime() } catch { } }
    $o.Arch = ConvertTo-TIArchName $ev['PROCESSOR_ARCHITECTURE']
    if (-not $o.Arch) {
        if ([System.IO.Directory]::Exists((Join-TIWinPath $winDir 'SysArm32'))) { $o.Arch = 'arm64' }
        elseif ([System.IO.Directory]::Exists((Join-TIWinPath $winDir 'SysWOW64'))) { $o.Arch = 'x64' }
        else { $o.Arch = 'x86' }
    }
    if ($o.ProductName -or $o.Build -gt 0) {
        $o.Label = Get-TIWindowsLabel -ProductName $o.ProductName -EditionId $o.EditionId -Build $o.Build -Ubr $o.Ubr -DisplayVersion $o.DisplayVersion
    } else {
        $o.Label = 'Windows (versão não identificada)'
    }
    return $o
}

# Instalações do Windows em C: a Z: (fora X: do WinPE e a partição do próprio app),
# mais os volumes BitLocker bloqueados (Locked). Fora do WinPE inclui o Windows em
# execução com IsRunning = $true (o Backup usa; a Recuperação nunca repara).
# -ExcludeRoots: raízes que ficam de fora ('E:\', 'E:').
function Get-TIWindowsInstalls {
    param([string[]]$ExcludeRoots = @())
    $pe = Test-TIWinPE
    $sysDrive = ''
    if (-not $pe -and $env:SystemDrive) { $sysDrive = ConvertTo-TIDriveLetter $env:SystemDrive }
    $skip = @{}
    foreach ($r in @($ExcludeRoots)) { $l = ConvertTo-TIDriveLetter $r; if ($l) { $skip[$l] = $true } }
    if ($pe) { $skip['X:'] = $true }
    $list = New-Object System.Collections.ArrayList
    foreach ($n in 67..90) {
        $d = ([string][char]$n) + ':'
        if ($skip.ContainsKey($d)) { continue }
        $root = $d + '\'
        $di = $null
        $ready = $false
        try { $di = New-Object System.IO.DriveInfo($d); $ready = $di.IsReady } catch { }
        if (-not $ready) { continue }
        $dt = [string]$di.DriveType
        if ($dt -ne 'Fixed' -and $dt -ne 'Removable') { continue }
        try {
            # partição do TI Suite (pendrive): não tem Windows para reparar
            if ([System.IO.File]::Exists($root + 'TI-Suite.ps1') -and [System.IO.File]::Exists($root + 'portable.config')) { continue }
            $cfg = $root + 'Windows\System32\config\'
            if (-not ([System.IO.File]::Exists($cfg + 'SYSTEM') -and [System.IO.File]::Exists($cfg + 'SOFTWARE'))) { continue }
        } catch { continue }
        Emit ('Windows encontrado em {0}: lendo a versão...' -f $d) 'Debug'
        [void]$list.Add((Read-TIWindowsInstall -Drive $d -IsRunning ($d -eq $sysDrive) -DriveInfo $di))
    }
    foreach ($lv in @(Get-TILockedVolumes -Skip $skip)) { if ($lv) { [void]$list.Add($lv) } }
    return $list.ToArray()
}

# Confere de novo, no worker, que a instalação pode ser alterada: nunca a que está
# em execução, nunca volume bloqueado, e o Windows tem de continuar lá.
function Assert-TIOfflineInstall {
    param($Install)
    if (-not $Install) { throw 'Nenhuma instalação do Windows escolhida.' }
    if ($Install.Locked) { throw ('O volume {0} está bloqueado pelo BitLocker: destrave antes.' -f $Install.Drive) }
    $d = ConvertTo-TIDriveLetter ([string]$Install.Drive)
    if (-not $d) { throw 'Instalação sem letra de unidade: procure o Windows de novo.' }
    if ($Install.IsRunning -or (-not (Test-TIWinPE) -and $env:SystemDrive -and $d -eq (ConvertTo-TIDriveLetter $env:SystemDrive))) {
        throw 'Este é o Windows em execução: ele não pode ser alterado daqui.'
    }
    if (-not [System.IO.File]::Exists($d + '\Windows\System32\config\SYSTEM')) {
        throw ('O Windows não foi encontrado em {0}: clique em Procurar de novo.' -f $d)
    }
}

# Pasta de usuário que não entra no backup nem na lista (regra pura)
function Test-TIUserFolderExcluded {
    param([string]$Name, [string]$Sid = '')
    $n = ([string]$Name).Trim().ToLowerInvariant()
    if (-not $n) { return $true }
    if (@('public', 'default', 'default user', 'all users', 'desktop.ini', 'systemprofile', 'localservice', 'networkservice', 'defaultapppool') -contains $n) { return $true }
    if ($n -match '^defaultuser\d+$') { return $true }
    if ($Sid -and $Sid -notlike 'S-1-5-21-*' -and $Sid -notlike 'S-1-12-1-*') { return $true }
    return $false
}

# Pastas de usuário da instalação: ProfileList do hive SOFTWARE (SID -> pasta, com a
# letra ajustada) junto com as pastas reais de <Root>Users. Sem Public, Default,
# perfis do sistema e junções. Para o Windows em execução usa Win32_UserProfile.
function Get-TIOfflineUsers {
    param([Parameter(Mandatory)]$Install)
    if ($Install.Locked) { throw ('O volume {0} está bloqueado pelo BitLocker: destrave antes.' -f $Install.Drive) }
    $drive = ConvertTo-TIDriveLetter ([string]$Install.Drive)
    $root = $drive + '\'
    $cand = New-Object System.Collections.ArrayList   # @{ Path; Sid; Loaded }
    if ($Install.IsRunning) {
        try {
            foreach ($p in @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop)) {
                if ($p.Special -or -not $p.LocalPath) { continue }
                [void]$cand.Add(@{ Path = [string]$p.LocalPath; Sid = [string]$p.SID; Loaded = [bool]$p.Loaded })
            }
        } catch { Emit ('Não foi possível ler os perfis do Windows: {0}' -f $_.Exception.Message) 'Warn' }
    } else {
        $key = $null
        try {
            $key = Mount-TIOfflineHive -Path ($root + 'Windows\System32\config\SOFTWARE')
            $pl = ($key -replace '^HKLM\\', '') + '\Microsoft\Windows NT\CurrentVersion\ProfileList'
            foreach ($sid in @(Get-TIHklmSubKeys -Path $pl)) {
                $v = Read-TIHklmValues -Path ($pl + '\' + $sid) -Names @('ProfileImagePath')
                $raw = [string]$v['ProfileImagePath']
                if (-not $raw) { continue }
                $path = Resolve-TIOfflinePath -Path $raw -Drive $drive
                # perfil que já estava em outra unidade (não a do Windows): mantém se existir
                if (-not [System.IO.Directory]::Exists($path) -and $raw -match '^[A-Za-z]:\\' -and $raw -notmatch '^(?i)X:' -and [System.IO.Directory]::Exists($raw)) { $path = $raw }
                [void]$cand.Add(@{ Path = $path; Sid = $sid; Loaded = $false })
            }
        } catch {
            Emit ('Não foi possível ler a lista de perfis do registro ({0}): vale a pasta Users.' -f $_.Exception.Message) 'Warn'
        } finally {
            if ($key) { [void](Dismount-TIOfflineHive -Key $key) }
        }
    }
    # pastas reais de Users (perfis sem registro também entram no backup)
    try {
        foreach ($d in @((New-Object System.IO.DirectoryInfo($root + 'Users')).GetDirectories())) {
            [void]$cand.Add(@{ Path = $d.FullName; Sid = ''; Loaded = $false })
        }
    } catch { }
    $seen = @{}
    $out = New-Object System.Collections.ArrayList
    foreach ($c in $cand) {
        $path = ([string]$c.Path).TrimEnd('\')
        $k = $path.ToLowerInvariant()
        if (-not $k) { continue }
        if ($seen.ContainsKey($k)) {
            # o mesmo perfil pela lista do registro e pela pasta: fica o SID
            $prev = $seen[$k]
            if ($prev) {
                if (-not $prev.Sid -and $c.Sid) { $prev.Sid = [string]$c.Sid }
                if ($c.Loaded) { $prev.Loaded = $true }
            }
            continue
        }
        $name = $path.Substring($path.LastIndexOf('\') + 1)
        # excluído (sistema, Público...) fica marcado para a pasta não entrar depois
        if (Test-TIUserFolderExcluded -Name $name -Sid ([string]$c.Sid)) { $seen[$k] = $null; continue }
        $di = $null
        try {
            $di = New-Object System.IO.DirectoryInfo($path)
            if (-not $di.Exists) { continue }
            if ([int]$di.Attributes -band 1024) { $seen[$k] = $null; continue }   # junção (ex.: "Documents and Settings")
        } catch { continue }
        $o = [pscustomobject]@{ Name = $name; Path = $di.FullName; Sid = [string]$c.Sid; Account = ''; LastUse = $null; Loaded = [bool]$c.Loaded }
        $seen[$k] = $o
        [void]$out.Add($o)
    }
    foreach ($o in $out) {
        try {
            $nt = New-Object System.IO.FileInfo((Join-TIWinPath $o.Path 'NTUSER.DAT'))
            if ($nt.Exists) { $o.LastUse = $nt.LastWriteTime } else { $o.LastUse = (New-Object System.IO.DirectoryInfo($o.Path)).LastWriteTime }
        } catch { }
        # traduzir SID só no Windows em execução (offline as contas não existem aqui)
        if ($Install.IsRunning -and $o.Sid) {
            try { $o.Account = (New-Object System.Security.Principal.SecurityIdentifier($o.Sid)).Translate([System.Security.Principal.NTAccount]).Value } catch { }
        }
    }
    return @($out | Sort-Object Name)
}

# Volumes onde dá para gravar o backup. Fora: X: do WinPE, as raízes passadas
# (a origem), a partição TI-BOOT do pendrive, somente leitura e sem letra.
# Type: 'USB', 'Interno' ou 'Rede'. IsTiSuite: a partição do app (pode ser destino).
function Get-TIDestinationVolumes {
    param([string[]]$ExcludeRoots = @())
    $skip = @{}
    foreach ($r in @($ExcludeRoots)) { $l = ConvertTo-TIDriveLetter $r; if ($l) { $skip[$l] = $true } }
    if (Test-TIWinPE) { $skip['X:'] = $true }
    # disco de cada letra: barramento (USB) e somente leitura (melhor esforço)
    $info = @{}
    try {
        $disks = @{}
        foreach ($dk in @(Get-Disk -ErrorAction Stop)) { $disks[[int]$dk.Number] = $dk }
        foreach ($pt in @(Get-Partition -ErrorAction Stop)) {
            $l = ConvertTo-TIDriveLetter ([string]$pt.DriveLetter)
            if (-not $l -or ([string]$pt.DriveLetter) -notmatch '^[A-Za-z]$') { continue }
            $dk = $disks[[int]$pt.DiskNumber]
            $info[$l] = @{
                ReadOnly = ([bool]$pt.IsReadOnly -or ($dk -and [bool]$dk.IsReadOnly))
                Usb = ($dk -and -not (Test-TIInternalDisk $dk))
            }
        }
    } catch { }
    $out = New-Object System.Collections.ArrayList
    foreach ($di in @([System.IO.DriveInfo]::GetDrives())) {
        $d = ConvertTo-TIDriveLetter $di.Name
        if (-not $d -or $skip.ContainsKey($d)) { continue }
        try {
            if (-not $di.IsReady) { continue }
            $dt = [string]$di.DriveType
            if ($dt -ne 'Fixed' -and $dt -ne 'Removable' -and $dt -ne 'Network') { continue }
            $label = [string]$di.VolumeLabel
            $fs = [string]$di.DriveFormat
            if ($label -ieq 'TI-BOOT') { continue }
            # partição de boot do pendrive com outro rótulo (FAT32 pequena com boot.wim)
            if ($fs -like 'FAT*' -and [double]$di.TotalSize -lt 8GB -and [System.IO.File]::Exists($di.Name + 'sources\boot.wim')) { continue }
            $i = $info[$d]
            if ($i -and $i.ReadOnly) { continue }
            $type = 'Interno'
            if ($dt -eq 'Network') { $type = 'Rede' }
            elseif ($dt -eq 'Removable' -or ($i -and $i.Usb)) { $type = 'USB' }
            [void]$out.Add([pscustomobject]@{
                Drive      = $d
                Root       = $d + '\'
                Label      = $label
                FileSystem = $fs
                SizeBytes  = [double]$di.TotalSize
                FreeBytes  = [double]$di.AvailableFreeSpace
                Type       = $type
                IsTiSuite  = ([System.IO.File]::Exists($d + '\TI-Suite.ps1') -and [System.IO.File]::Exists($d + '\portable.config'))
            })
        } catch { }
    }
    return $out.ToArray()
}

# ---------------------------------------------------------------------
# Programas da instalação offline (remoção forçada pelo pendrive)
# No WinPE o Windows do disco está desligado: o desinstalador do fabricante
# não roda. A remoção apaga a pasta do programa (só dentro das pastas de
# programas, nunca seguindo junções), os atalhos e a chave de desinstalação.
# ---------------------------------------------------------------------

# Caminho do .exe no começo de um comando ("C:\x\a.exe" /S, C:\x\a.exe,0). Regra pura.
function Get-TIExePathFromCommand {
    param([string]$Command)
    $c = ([string]$Command).Trim()
    if (-not $c) { return '' }
    if ($c.StartsWith('"')) {
        $e = $c.IndexOf('"', 1)
        if ($e -gt 1) { return $c.Substring(1, $e - 1) }
        return ''
    }
    $m = [regex]::Match($c, '^([A-Za-z]:\\.*?\.(?:exe|ico|dll))(?=$|[\s,])', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

# Pasta do programa: InstallLocation; sem ele, a pasta do ícone ou do desinstalador
# (nunca a de msiexec, do cache do Windows Installer ou do InstallShield). Regra pura.
function Get-TIProgramFolder {
    param([string]$InstallLocation = '', [string]$DisplayIcon = '', [string]$UninstallString = '', [string]$Drive = '')
    $orig = ''; $src = ''
    $il = ([string]$InstallLocation).Trim().Trim('"').Trim().TrimEnd('\')
    if ($il -match '^([A-Za-z]:|%[A-Za-z0-9()]+%)\\.+') { $orig = $il; $src = 'InstallLocation' }
    else {
        foreach ($pair in @(@('DisplayIcon', $DisplayIcon), @('UninstallString', $UninstallString))) {
            $exe = Get-TIExePathFromCommand ([string]$pair[1])
            if (-not $exe) { continue }
            if ($exe -match '(?i)\\(msiexec|rundll32|regsvr32|cmd|powershell|wscript|cscript|explorer)\.exe$') { continue }
            if ($exe -match '(?i)\\Windows\\|\\Package Cache\\|\\InstallShield Installation Information\\|\\Uninstall Information\\') { continue }
            $cut = $exe.LastIndexOf('\')
            if ($cut -lt 3) { continue }
            $orig = $exe.Substring(0, $cut)
            $src = [string]$pair[0]
            break
        }
    }
    $folder = ''
    if ($orig) { $folder = (Resolve-TIOfflinePath -Path $orig -Drive $Drive).TrimEnd('\') }
    return [pscustomobject]@{ Folder = $folder; Original = $orig; Source = $src }
}

# '' = pode ir no lote; senão o motivo do cadeado. Runtimes essenciais e
# antivírus/segurança ficam de fora (estes têm ferramenta de remoção própria). Regra pura.
function Get-TIProgramProtection {
    param([string]$Name, [string]$Publisher = '')
    $n = [string]$Name
    $both = $n + ' | ' + [string]$Publisher
    if ($n -match '(?i)visual c\+\+.*(redistributable|runtime)|\bvc_?redist\b|^microsoft visual c\+\+ \d{4}') { return 'runtime essencial (Visual C++)' }
    if ($n -match '(?i)(^|[\s(])\.net\b|\bdotnet\b|asp\.net core|windows desktop runtime') { return 'runtime essencial (.NET)' }
    if ($n -match '(?i)windows ?app ?(runtime|sdk)') { return 'runtime essencial (Windows App Runtime)' }
    if ($n -match '(?i)webview2') { return 'runtime essencial (WebView2)' }
    if ($n -match '(?i)^microsoft edge\b') { return 'navegador do Windows (Edge)' }
    $av = '(?i)\b(defender|kaspersky|eset|avast|avg|norton|nortonlifelock|symantec|mcafee|bitdefender|sophos|trend ?micro|malwarebytes|crowdstrike|sentinel ?one|webroot|f-secure|gen digital)\b'
    if ($both -match $av) { return 'antivírus ou segurança: use a ferramenta de remoção do fabricante' }
    return ''
}

# Entrada da chave Uninstall (valores num hashtable) -> programa da lista, ou $null
# para o que não aparece: sem nome, componente do sistema e atualizações. Regra pura.
function ConvertFrom-TIUninstallEntry {
    param([hashtable]$Values, [string]$KeyName = '', [string]$Drive = '', [string]$Scope = 'Máquina', [string]$User = '')
    if (-not $Values) { return $null }
    $v = $Values
    $get = { param([string]$n) if ($v.ContainsKey($n) -and $null -ne $v[$n]) { ([string]$v[$n]).Trim() } else { '' } }
    $name = & $get 'DisplayName'
    if (-not $name) { return $null }
    if ((& $get 'SystemComponent') -eq '1') { return $null }
    if (& $get 'ParentKeyName') { return $null }
    if ((& $get 'ReleaseType') -match '^(?i)(update|hotfix|security update|service pack)$') { return $null }
    if ($name -match '(?i)^(security update|update|hotfix) for |\(KB\d{6,}\)$|^KB\d{6,}') { return $null }
    $code = ''
    if ($KeyName -match '^\{[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}$') { $code = $KeyName.ToUpperInvariant() }
    $f = Get-TIProgramFolder -InstallLocation (& $get 'InstallLocation') -DisplayIcon (& $get 'DisplayIcon') `
                             -UninstallString (& $get 'UninstallString') -Drive $Drive
    $prot = Get-TIProgramProtection -Name $name -Publisher (& $get 'Publisher')
    return [pscustomobject]@{
        Name         = $name
        Version      = (& $get 'DisplayVersion')
        Publisher    = (& $get 'Publisher')
        Folder       = $f.Folder
        Original     = $f.Original
        FolderSource = $f.Source
        FolderNote   = ''
        Size         = -1.0
        Scope        = $Scope
        User         = $User
        Hive         = ''
        KeyPath      = ''
        KeyName      = $KeyName
        Msi          = ((& $get 'WindowsInstaller') -eq '1')
        ProductCode  = $code
        Protected    = [bool]$prot
        Reason       = $prot
    }
}

# '' = a pasta pode ser apagada; senão o motivo. Só DENTRO de <Root>Program Files,
# Program Files (x86), ProgramData ou <Root>Users\<nome>\AppData\Local\Programs,
# nunca a raiz delas nem as pastas do próprio Windows. Regra pura.
function Test-TIRemovableProgramFolder {
    param([string]$Folder, [string]$Root)
    $f = ([string]$Folder).Trim().TrimEnd('\')
    $r = ([string]$Root).Trim().TrimEnd('\')
    if (-not $f) { return 'sem pasta de instalação registrada' }
    if (-not $r) { return 'instalação sem unidade' }
    if ($f -match '[*?<>|"]' -or $f -match '(^|\\)\.{1,2}(\\|$)' -or $f -match '\\\\') { return 'caminho inválido' }
    if (-not $f.StartsWith($r + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return 'pasta fora da unidade do Windows' }
    $parts = @($f.Substring($r.Length + 1) -split '\\' | Where-Object { $_ })
    if ($parts.Count -lt 2) { return 'pasta raiz' }
    $base = $parts[0].ToLowerInvariant()
    $first = $parts[1].ToLowerInvariant()
    if ($base -eq 'program files' -or $base -eq 'program files (x86)') {
        $deny = @('common files', 'windowsapps', 'modifiablewindowsapps', 'windows defender', 'windows defender advanced threat protection',
                  'windows mail', 'windows media player', 'windows multimedia platform', 'windows nt', 'windows photo viewer',
                  'windows portable devices', 'windows security', 'windows sidebar', 'windowspowershell', 'internet explorer',
                  'microsoft update health tools', 'reference assemblies', 'msbuild', 'dotnet', 'uninstall information',
                  'installshield installation information')
        if ($deny -contains $first) { return 'pasta do Windows ou compartilhada' }
        if ($parts.Count -eq 2 -and @('microsoft', 'microsoft.net', 'microsoft sdks') -contains $first) { return 'pasta compartilhada da Microsoft' }
        return ''
    }
    if ($base -eq 'programdata') {
        $deny = @('microsoft', 'package cache', 'packages', 'regid.1991-06.com.microsoft', 'ssh', 'usoshared', 'usoprivate',
                  'softwaredistribution', 'windows', 'windowsholographicdevices', 'desktop', 'documents', 'start menu',
                  'templates', 'application data', 'favorites')
        if ($deny -contains $first) { return 'pasta do Windows ou compartilhada' }
        return ''
    }
    if ($base -eq 'users') {
        if ($parts.Count -ge 6 -and $parts[2] -ieq 'AppData' -and $parts[3] -ieq 'Local' -and $parts[4] -ieq 'Programs' -and
            @('public', 'default', 'default user', 'all users') -notcontains $first) { return '' }
        return 'pasta de usuário fora de AppData\Local\Programs'
    }
    return 'fora das pastas de programas'
}

# A pasta é de outro programa da lista (igual, dentro dela ou contendo-a)? Regra pura.
function Test-TIFolderShared {
    param([string]$Folder, [string[]]$Others)
    $f = ([string]$Folder).Trim().TrimEnd('\').ToLowerInvariant()
    if (-not $f) { return $false }
    foreach ($o in @($Others)) {
        $x = ([string]$o).Trim().TrimEnd('\').ToLowerInvariant()
        if (-not $x) { continue }
        if ($x -eq $f -or $x.StartsWith($f + '\') -or $f.StartsWith($x + '\')) { return $true }
    }
    return $false
}

# Código de produto do Windows Installer no formato "empacotado" do registro
# ({12345678-90AB-CDEF-1234-567890ABCDEF} -> 87654321BA09FEDC2143658709BADCFE). Regra pura.
function ConvertTo-TIPackedGuid {
    param([string]$Guid)
    $g = (([string]$Guid).Trim().Trim('{', '}') -replace '-', '').ToUpperInvariant()
    if ($g -notmatch '^[0-9A-F]{32}$') { return '' }
    $rev = { param([string]$s) $a = $s.ToCharArray(); [array]::Reverse($a); -join $a }
    $out = (& $rev $g.Substring(0, 8)) + (& $rev $g.Substring(8, 4)) + (& $rev $g.Substring(12, 4))
    for ($i = 16; $i -lt 32; $i += 2) { $out += [string]$g[$i + 1] + [string]$g[$i] }
    return $out
}

# O atalho (.lnk) aponta para dentro da pasta? Procura o caminho SEM a letra (no
# WinPE a unidade muda de letra) no texto ANSI e Unicode do arquivo. Regra pura.
function Test-TILnkPointsTo {
    param([byte[]]$Bytes, [string]$Folder)
    if (-not $Bytes -or $Bytes.Length -lt 76) { return $false }
    $f = ([string]$Folder).Trim().TrimEnd('\')
    if ($f -match '^[A-Za-z]:(\\.*)$') { $f = $Matches[1] }
    if ($f.Length -lt 4) { return $false }
    $needle = $f.ToLowerInvariant()
    $texts = @(
        [System.Text.Encoding]::Unicode.GetString($Bytes),
        [System.Text.Encoding]::Unicode.GetString($Bytes, 1, $Bytes.Length - 1),
        [System.Text.Encoding]::GetEncoding(28591).GetString($Bytes)
    )
    foreach ($t0 in $texts) {
        $t = $t0.ToLowerInvariant()
        $i = $t.IndexOf($needle, [System.StringComparison]::Ordinal)
        while ($i -ge 0) {
            $end = $i + $needle.Length
            if ($end -ge $t.Length) { return $true }
            $c = [int]$t[$end]
            if ($c -eq 92 -or $c -eq 0 -or $c -eq 34) { return $true }   # \  NUL  "
            $i = $t.IndexOf($needle, $i + 1, [System.StringComparison]::Ordinal)
        }
    }
    return $false
}

# Arquivos de uma pasta (com subpastas) sem seguir junções/links
function Get-TISafeFiles {
    param([string]$Path, [string]$Filter = '*', [int]$Max = 20000)
    $out = New-Object System.Collections.ArrayList
    try {
        $root = New-Object System.IO.DirectoryInfo($Path)
        if (-not $root.Exists -or ([int]$root.Attributes -band 1024)) { return @() }
    } catch { return @() }
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    while ($stack.Count -gt 0 -and $out.Count -lt $Max) {
        $d = $stack.Pop()
        $entries = @()
        try { $entries = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $entries) {
            if ([int]$e.Attributes -band 1024) { continue }
            if ($e -is [System.IO.DirectoryInfo]) { $stack.Push($e) }
            elseif ($e.Name -like $Filter) { [void]$out.Add($e.FullName) }
        }
    }
    return $out.ToArray()
}

# Programas da instalação offline: hive SOFTWARE (64 e 32 bits) e o NTUSER.DAT de
# cada usuário. Tamanho só das pastas que podem ser apagadas.
function Get-TIOfflinePrograms {
    param([Parameter(Mandatory)]$Install)
    Assert-TIOfflineInstall $Install
    $drive = ConvertTo-TIDriveLetter ([string]$Install.Drive)
    $root = $drive + '\'
    $names = @('DisplayName', 'DisplayVersion', 'Publisher', 'InstallLocation', 'UninstallString', 'DisplayIcon',
               'SystemComponent', 'WindowsInstaller', 'ParentKeyName', 'ReleaseType')
    $items = New-Object System.Collections.ArrayList
    Emit 'Lendo os programas instalados (registro offline)...' 'Info' 5
    $key = $null
    try {
        $key = Mount-TIOfflineHive -Path ($root + 'Windows\System32\config\SOFTWARE')
        $hk = $key -replace '^HKLM\\', ''
        foreach ($rel in @('Microsoft\Windows\CurrentVersion\Uninstall', 'WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
            foreach ($sub in @(Get-TIHklmSubKeys -Path ($hk + '\' + $rel))) {
                $vals = Read-TIHklmValues -Path ($hk + '\' + $rel + '\' + $sub) -Names $names
                $e = ConvertFrom-TIUninstallEntry -Values $vals -KeyName $sub -Drive $drive -Scope 'Máquina'
                if (-not $e) { continue }
                $e.Hive = 'SOFTWARE'
                $e.KeyPath = $rel
                [void]$items.Add($e)
            }
        }
    } finally {
        if ($key) { [void](Dismount-TIOfflineHive -Key $key) }
    }
    $users = @()
    try { $users = @(Get-TIOfflineUsers -Install $Install) } catch { Emit ('Não foi possível listar os usuários: {0}' -f $_.Exception.Message) 'Warn' }
    foreach ($u in $users) {
        $nt = Join-TIWinPath $u.Path 'NTUSER.DAT'
        if (-not [System.IO.File]::Exists($nt)) { continue }
        $key = $null
        try {
            $key = Mount-TIOfflineHive -Path $nt
            $hk = $key -replace '^HKLM\\', ''
            $rel = 'Software\Microsoft\Windows\CurrentVersion\Uninstall'
            foreach ($sub in @(Get-TIHklmSubKeys -Path ($hk + '\' + $rel))) {
                $vals = Read-TIHklmValues -Path ($hk + '\' + $rel + '\' + $sub) -Names $names
                $e = ConvertFrom-TIUninstallEntry -Values $vals -KeyName $sub -Drive $drive -Scope 'Usuário' -User $u.Name
                if (-not $e) { continue }
                $e.Hive = $nt
                $e.KeyPath = $rel
                [void]$items.Add($e)
            }
        } catch {
            Emit ('Não foi possível ler os programas do usuário {0}: {1}' -f $u.Name, $_.Exception.Message) 'Warn'
        } finally {
            if ($key) { [void](Dismount-TIOfflineHive -Key $key) }
        }
    }
    $i = 0
    $total = [Math]::Max(1, $items.Count)
    foreach ($e in $items) {
        $i++
        $why = Test-TIRemovableProgramFolder -Folder $e.Folder -Root $root
        if (-not $why -and -not [System.IO.Directory]::Exists($e.Folder)) { $why = 'a pasta não existe mais' }
        if (-not $why) {
            $lnk = Find-TIPathLink -Path $e.Folder -Base $root
            if ($lnk) { $why = 'há uma junção ou link no caminho' }
        }
        $e.FolderNote = $why
        if (-not $why) {
            Emit ('Medindo {0} ({1}/{2})...' -f $e.Name, $i, $items.Count) 'Debug' ([int](10 + 85 * $i / $total))
            $e.Size = Get-TISafeSize -Path $e.Folder
        }
    }
    Emit ('{0} programa(s) encontrado(s) em {1}.' -f $items.Count, $drive) 'Success' 100
    return @($items | Sort-Object Name)
}

# Registro do Windows Installer de um produto (para o MSI não achar que ele ainda está instalado)
function Remove-TIMsiRegistration {
    param([string]$Hk, [string]$ProductCode)
    $packed = ConvertTo-TIPackedGuid $ProductCode
    if (-not $packed) { return 0 }
    $n = 0
    foreach ($p in @('Classes\Installer\Products', 'Classes\Installer\Features', 'Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products')) {
        if (Remove-TIHklmSubKeyTree -Parent ($Hk + '\' + $p) -Name $packed) { $n++ }
    }
    $ucBase = $Hk + '\Classes\Installer\UpgradeCodes'
    foreach ($uc in @(Get-TIHklmSubKeys -Path $ucBase)) {
        $k = $null
        $empty = $false
        try {
            $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($ucBase + '\' + $uc, $true)
            if ($k -and (@($k.GetValueNames()) -contains $packed)) {
                $k.DeleteValue($packed, $false)
                $n++
                $empty = ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0)
            }
        } catch { } finally {
            if ($k) { try { $k.Close() } catch { } }
        }
        if ($empty) { try { [void](Remove-TIHklmSubKeyTree -Parent $ucBase -Name $uc) } catch { } }
    }
    return $n
}

# Remoção forçada (offline) dos programas marcados. -KeepFolders: pastas dos programas
# da lista que NÃO serão removidos (pasta compartilhada fica). Resumo por programa.
function Remove-TIOfflinePrograms {
    param([Parameter(Mandatory)]$Install, $Items, [string[]]$KeepFolders = @())
    Assert-TIOfflineInstall $Install
    if (-not (Clear-TIOfflineHives)) { throw 'Há um registro offline aberto que não fechou: reinicie o pendrive antes de remover programas.' }
    $drive = ConvertTo-TIDriveLetter ([string]$Install.Drive)
    $root = $drive + '\'
    $Items = @($Items | Where-Object { $_ -and $_.Name -and $_.KeyName })
    if ($Items.Count -eq 0) { Emit 'Nenhum programa marcado.' 'Warn'; return }

    # atalhos: Menu Iniciar de todos os usuários, área de trabalho pública e de cada usuário
    $lnkDirs = New-Object System.Collections.ArrayList
    [void]$lnkDirs.Add($root + 'ProgramData\Microsoft\Windows\Start Menu\Programs')
    [void]$lnkDirs.Add($root + 'Users\Public\Desktop')
    $users = @()
    try { $users = @(Get-TIOfflineUsers -Install $Install) } catch { }
    foreach ($u in $users) {
        [void]$lnkDirs.Add((Join-TIWinPath $u.Path 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'))
        [void]$lnkDirs.Add((Join-TIWinPath $u.Path 'Desktop'))
    }
    $lnks = New-Object System.Collections.ArrayList
    foreach ($d in $lnkDirs) { foreach ($f in @(Get-TISafeFiles -Path $d -Filter '*.lnk')) { [void]$lnks.Add($f) } }

    $results = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($it in $Items) {
        $i++
        $r = [pscustomobject]@{ Name = [string]$it.Name; Folder = ''; Shortcuts = 0; Registry = ''; Level = 'Success'; Item = $it }
        [void]$results.Add($r)
        $prot = Get-TIProgramProtection -Name ([string]$it.Name) -Publisher ([string]$it.Publisher)
        if ($prot) {
            $r.Level = 'Warn'; $r.Folder = 'mantida'; $r.Registry = 'mantido'
            Emit ('{0} é protegido ({1}): mantido.' -f $it.Name, $prot) 'Warn'
            continue
        }
        Emit ('Removendo {0} ({1}/{2})...' -f $it.Name, $i, $Items.Count) 'Info' ([int](5 + 70 * $i / $Items.Count))
        $folder = ([string]$it.Folder).TrimEnd('\')
        $why = Test-TIRemovableProgramFolder -Folder $folder -Root $root
        if (-not $why -and (Test-TIFolderShared -Folder $folder -Others $KeepFolders)) { $why = 'pasta usada por outro programa da lista' }
        if (-not $why -and -not [System.IO.Directory]::Exists($folder)) { $why = 'a pasta já não existia' }
        if (-not $why) {
            $lnk = Find-TIPathLink -Path $folder -Base $root
            if ($lnk) { $why = ('há uma junção ou link no caminho ({0})' -f $lnk) }
        }
        if ($why) {
            $r.Folder = 'mantida: ' + $why
        } else {
            # mesma limpeza segura da Manutenção: nunca entra em junções/links
            Clear-TISafeFolder -Path $folder
            try { [System.IO.Directory]::Delete($folder, $false) } catch { }
            if ([System.IO.Directory]::Exists($folder)) {
                $left = @(Get-TISafeFiles -Path $folder -Max 1000).Count
                $r.Folder = ('ficou em parte ({0} arquivo(s))' -f $left)
                $r.Level = 'Error'
                Emit ('{0}: a pasta {1} não foi apagada por inteiro ({2} arquivo(s) ficaram).' -f $it.Name, $folder, $left) 'Error'
            } else {
                $r.Folder = 'apagada'
            }
            # atalhos que apontam para a pasta (e a pasta do Menu Iniciar que ficar vazia)
            foreach ($l in @($lnks)) {
                $hit = $false
                try { $hit = Test-TILnkPointsTo -Bytes ([System.IO.File]::ReadAllBytes($l)) -Folder $folder } catch { }
                if (-not $hit) { continue }
                try {
                    [System.IO.File]::SetAttributes($l, [System.IO.FileAttributes]::Normal)
                    [System.IO.File]::Delete($l)
                    $r.Shortcuts++
                    [void]$lnks.Remove($l)
                    $dir = [System.IO.Path]::GetDirectoryName($l)
                    $leaf = [System.IO.Path]::GetFileName($dir)
                    if ($leaf -ine 'Programs' -and $leaf -ine 'Desktop' -and $leaf -ine 'Startup' -and
                        @([System.IO.Directory]::GetFileSystemEntries($dir)).Count -eq 0) {
                        [System.IO.Directory]::Delete($dir, $false)
                    }
                } catch { }
            }
        }
    }

    # registro: um hive montado por vez (máquina e cada NTUSER.DAT)
    $groups = @{}
    foreach ($r in $results) {
        if ($r.Registry) { continue }
        $h = [string]$r.Item.Hive
        if (-not $groups.ContainsKey($h)) { $groups[$h] = New-Object System.Collections.ArrayList }
        [void]$groups[$h].Add($r)
    }
    foreach ($h in @($groups.Keys)) {
        $path = $(if ($h -eq 'SOFTWARE') { $root + 'Windows\System32\config\SOFTWARE' } else { $h })
        $key = $null
        try {
            $key = Mount-TIOfflineHive -Path $path
            $hk = $key -replace '^HKLM\\', ''
            foreach ($r in $groups[$h]) {
                $it = $r.Item
                try {
                    $gone = Remove-TIHklmSubKeyTree -Parent ($hk + '\' + [string]$it.KeyPath) -Name ([string]$it.KeyName)
                    $r.Registry = $(if ($gone) { 'removido' } else { 'já não existia' })
                    if ($h -eq 'SOFTWARE' -and $it.Msi -and $it.ProductCode) {
                        $m = Remove-TIMsiRegistration -Hk $hk -ProductCode ([string]$it.ProductCode)
                        if ($m -gt 0) { Emit ('{0}: registro do Windows Installer limpo ({1} item(ns)).' -f $it.Name, $m) 'Debug' }
                    }
                } catch {
                    $r.Registry = 'falhou'
                    $r.Level = 'Error'
                    Emit ('{0}: não foi possível remover a chave de desinstalação ({1}).' -f $it.Name, $_.Exception.Message) 'Error'
                }
            }
        } catch {
            foreach ($r in $groups[$h]) { $r.Registry = 'falhou'; $r.Level = 'Error' }
            Emit ('Não foi possível abrir o registro {0}: {1}' -f $path, $_.Exception.Message) 'Error'
        } finally {
            if ($key) { [void](Dismount-TIOfflineHive -Key $key) }
        }
    }

    $ok = 0
    foreach ($r in $results) {
        if ($r.Level -eq 'Success' -and $r.Folder -match '^mantida' -and $r.Folder -notmatch 'não existia|sem pasta') { $r.Level = 'Warn' }
        $txt = ('{0}: pasta {1}; {2} atalho(s); registro {3}.' -f $r.Name, $r.Folder, $r.Shortcuts, $r.Registry)
        Emit $txt $(if ($r.Level -eq 'Error') { 'Warn' } else { $r.Level })
        if ($r.Level -ne 'Error' -and $r.Registry -ne 'mantido') { $ok++ }
    }
    Emit ('Remoção offline: {0} de {1} programa(s) removido(s).' -f $ok, $results.Count) $(if ($ok -eq $results.Count) { 'Success' } else { 'Warn' }) 100
    foreach ($r in $results) { $r.PSObject.Properties.Remove('Item') }
    return $results.ToArray()
}
'@
