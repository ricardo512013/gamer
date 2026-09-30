# =====================================================================
# TI-SUITE.ps1 - Ponto de entrada
# Uso:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\TI-Suite.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\TI-Suite.ps1 -SelfTest
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\TI-Suite.ps1 -NoElevate
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\TI-Suite.ps1 -SkipIntegrity   (desenvolvimento)
# Códigos de saída: 0 = normal; 1 = erro já explicado na tela;
#                   3 = a política do computador bloqueia scripts (o Iniciar.cmd explica).
# =====================================================================

#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$NoElevate,
    [switch]$SkipIntegrity,
    # Interno: reaberto pelo selo "Sem elevação"; espera a janela anterior fechar
    [switch]$Reopen
)

# AppLocker/WDAC deixam scripts não liberados em "Constrained Language": nada de
# WinForms nem C#. Avisa com clareza em vez de falhar com erro técnico.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host ''
    Write-Host 'A política deste computador (AppLocker, WDAC ou GPO) bloqueia scripts do PowerShell.' -ForegroundColor Red
    Write-Host 'Peça ao responsável pela rede uma exceção para a pasta do TI Suite.' -ForegroundColor Red
    exit 3
}

$ErrorActionPreference = 'Stop'
$script:TIRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:TIRoot = $script:TIRoot
$global:TIEntryPoint = $MyInvocation.MyCommand.Path
$global:TISkipIntegrity = $SkipIntegrity.IsPresent
try { Set-Location -LiteralPath $script:TIRoot } catch { }

# ---------------------------------------------------------------------
# Escopo global e STA. Os handlers de eventos (.GetNewClosure()) só enxergam
# funções do escopo global: com "powershell -File" (Iniciar.cmd) o script já
# roda nele; chamado como .\TI-Suite.ps1 num console aberto, não. WinForms
# exige STA. Nos dois casos reabre com powershell.exe -STA -File.
# ---------------------------------------------------------------------
$script:TIScopeProbe = $true
$inGlobalScope = [bool](Get-Variable -Name TIScopeProbe -Scope Global -ValueOnly -ErrorAction SilentlyContinue)
Remove-Variable -Name TIScopeProbe -Scope Script -ErrorAction SilentlyContinue
# Reabre uma vez só (a variável de ambiente evita laço se a detecção falhar)
$relaunched = ($env:TI_SUITE_RELAUNCHED -eq '1')
$env:TI_SUITE_RELAUNCHED = $null
if (-not $relaunched -and (-not $inGlobalScope -or [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA')) {
    $env:TI_SUITE_RELAUNCHED = '1'
    $reArgs = '-NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f $global:TIEntryPoint
    if ($SelfTest) { $reArgs += ' -SelfTest' }
    if ($NoElevate) { $reArgs += ' -NoElevate' }
    if ($SkipIntegrity) { $reArgs += ' -SkipIntegrity' }
    if ($Reopen) { $reArgs += ' -Reopen' }
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $reArgs -Wait -NoNewWindow -PassThru
        exit $(if ($p) { $p.ExitCode } else { 1 })
    } catch {
        Write-Host 'Não foi possível reabrir o TI Suite no modo certo (STA). Use o Iniciar.cmd.' -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------------
# Modo portátil: se portable.config existir ao lado do script,
# configurações, logs e inventário ficam na própria pasta (rodar de USB).
# -LiteralPath: pasta com colchetes no nome ("TI [2024]") não é curinga.
# ---------------------------------------------------------------------
$global:TIPortable = (Test-Path -LiteralPath (Join-Path $script:TIRoot 'portable.config'))

# Única regra de pastas do app: portátil = pasta do app; instalado = %LOCALAPPDATA%\TI-Suite
function Get-TIAppDataDir {
    if ($global:TIPortable) { return $global:TIRoot }
    return (Join-Path $env:LOCALAPPDATA 'TI-Suite')
}

# exceptions.log, audit.csv e crash.log: <app>\logs (portátil) ou %LOCALAPPDATA%\TI-Suite.
# Os outros módulos usam só $global:TILogPath e $global:TI.SettingsPath.
$logDir0 = if ($global:TIPortable) { Join-Path (Get-TIAppDataDir) 'logs' } else { Get-TIAppDataDir }
$global:TILogPath = Join-Path $logDir0 'exceptions.log'
try {
    if (-not (Test-Path -LiteralPath $logDir0)) { New-Item -ItemType Directory -Path $logDir0 -Force | Out-Null }
} catch { }
if (-not $global:TI) { $global:TI = @{} }
$global:TI.SettingsPath = Join-Path (Get-TIAppDataDir) 'config.json'

# Pasta copiada da internet: remove a marca de download para o Windows não bloquear
try {
    Get-ChildItem -LiteralPath $script:TIRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(ps1|cmd|json|config|dll|cs|stamp)$' } |
        Unblock-File -ErrorAction SilentlyContinue
} catch { }

# ---------------------------------------------------------------------
# Integridade: se manifest.sha256 existir (gerado por dev\Build-Release.ps1),
# confere o hash de cada arquivo ANTES de pedir UAC. Detecta corrupção do
# pendrive e adulteração casual; não substitui assinatura digital nem BitLocker.
# ---------------------------------------------------------------------
$manifestPath = Join-Path $script:TIRoot 'manifest.sha256'
if (-not $SelfTest -and -not $SkipIntegrity -and (Test-Path -LiteralPath $manifestPath)) {
    $integrityIssues = New-Object System.Collections.ArrayList
    try {
        foreach ($mline in (Get-Content -LiteralPath $manifestPath -Encoding UTF8)) {
            if ($mline -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') {
                $expected = $Matches[1].ToUpperInvariant()
                $rel = $Matches[2]
                $full = Join-Path $script:TIRoot $rel
                if (-not (Test-Path -LiteralPath $full)) { [void]$integrityIssues.Add('faltando:  ' + $rel); continue }
                $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash
                if ($actual -ne $expected) { [void]$integrityIssues.Add('alterado:  ' + $rel) }
            }
        }
    } catch { [void]$integrityIssues.Add('falha ao verificar: ' + $_.Exception.Message) }
    if ($integrityIssues.Count -gt 0) {
        $txt = "O TI Suite não foi aberto: os arquivos não conferem com o manifesto de integridade.`n`n" +
               (($integrityIssues | Select-Object -First 12) -join "`n") +
               "`n`nCopie de novo a pasta original para o pendrive. (Em desenvolvimento: -SkipIntegrity)"
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show($txt, 'TI Suite - integridade', 'OK', 'Error')
        } catch { Write-Host $txt -ForegroundColor Red }
        exit 1
    }
}

# ---------------------------------------------------------------------
# Elevação, caminho para reabrir e instância única
# ---------------------------------------------------------------------
function Test-TIIsAdmin {
    try {
        $p = New-Object System.Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# Unidade de rede mapeada (Z:) não existe para o token elevado do UAC: troca pelo caminho UNC
function Get-TILaunchPath {
    $path = $global:TIEntryPoint
    try {
        if ($path -match '^[A-Za-z]:\\') {
            $q = $path.Substring(0, 2)
            if ((New-Object System.IO.DriveInfo($q)).DriveType -eq [System.IO.DriveType]::Network) {
                $unc = $null
                try { $unc = [string](Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $q) -ErrorAction Stop).ProviderName } catch { }
                if (-not $unc) { try { $unc = [string](Get-PSDrive -Name $q.Substring(0, 1) -ErrorAction Stop).DisplayRoot } catch { } }
                if ($unc -and $unc.StartsWith('\\')) { return ($unc.TrimEnd('\') + $path.Substring(2)) }
            }
        }
    } catch { }
    return $path
}

# Argumentos para reabrir como administrador (a janela do PowerShell fica oculta)
function Get-TIElevatedArgs {
    param([switch]$Reopen)
    $a = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Get-TILaunchPath)
    if ($global:TISkipIntegrity) { $a += ' -SkipIntegrity' }
    if ($Reopen) { $a += ' -Reopen' }
    return $a
}

# $false = o processo elevado saiu logo com código estranho (ex.: -File não encontrado)
function Test-TIElevatedStart {
    param($Process, [int]$TimeoutMs = 4000)
    try {
        if (-not $Process) { return $true }
        if (-not $Process.WaitForExit($TimeoutMs)) { return $true }
        $code = $Process.ExitCode
        if ($code -eq 0 -or $code -eq 1) { return $true }
        return $false
    } catch { return $true }
}

$script:TIMutexName = 'Local\TISuite'

# Outra janela do TI Suite nesta sessão? (sem tomar posse; sem acesso = existe e é elevada)
function Test-TIOtherInstance {
    $m = $null
    try {
        if ([System.Threading.Mutex]::TryOpenExisting($script:TIMutexName, [ref]$m)) { $m.Dispose(); return $true }
    } catch [System.UnauthorizedAccessException] { return $true } catch { }
    return $false
}

# Toma posse da instância única. -WaitMs: tempo para a janela anterior fechar (reabertura).
# Sem acesso ao mutex = criado por outra conta ou por uma instância elevada: na reabertura
# espera ele sumir (a janela anterior fecha logo depois do UAC); fora dela, desiste.
function Enter-TISingleInstance {
    param([int]$WaitMs = 0)
    $deadline = (Get-Date).AddMilliseconds($WaitMs)
    while ($true) {
        try {
            $created = $false
            $m = New-Object System.Threading.Mutex($false, $script:TIMutexName, [ref]$created)
            $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
            $got = $false
            try { $got = $m.WaitOne($left) } catch [System.Threading.AbandonedMutexException] { $got = $true }
            if ($got) { $global:TIInstanceMutex = $m; return $true }
            $m.Dispose()
            return $false
        } catch [System.UnauthorizedAccessException] {
            if ((Get-Date) -ge $deadline) { return $false }
            Start-Sleep -Milliseconds 250
        } catch {
            return $true     # sem como conferir: não impede a abertura
        }
    }
}

function Exit-TISingleInstance {
    if ($global:TIInstanceMutex) {
        try { $global:TIInstanceMutex.ReleaseMutex() } catch { }
        try { $global:TIInstanceMutex.Dispose() } catch { }
        $global:TIInstanceMutex = $null
    }
}

# Traz a janela já aberta para a frente; se não der, avisa
function Show-TIOtherInstance {
    $shown = $false
    try {
        if (-not ('TISuiteEntry.Win' -as [type])) {
            Add-Type -Namespace TISuiteEntry -Name Win -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
'@
        }
        $h = [TISuiteEntry.Win]::FindWindow([NullString]::Value, 'TI Suite')
        if ($h -ne [IntPtr]::Zero) {
            if ([TISuiteEntry.Win]::IsIconic($h)) { [void][TISuiteEntry.Win]::ShowWindowAsync($h, 9) }   # SW_RESTORE
            $shown = [TISuiteEntry.Win]::SetForegroundWindow($h)
        }
    } catch { }
    if (-not $shown) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show(
                "O TI Suite já está aberto neste computador.`n`nUse a janela que já está aberta (procure na barra de tarefas).",
                'TI Suite', 'OK', 'Information')
        } catch { Write-Host 'O TI Suite já está aberto neste computador.' -ForegroundColor Yellow }
    }
}

$useMutex = -not $SelfTest

# Já aberto: não pede UAC à toa, só mostra a janela existente
if ($useMutex -and -not $Reopen -and (Test-TIOtherInstance)) {
    Show-TIOtherInstance
    exit 0
}

if (-not $SelfTest -and -not $NoElevate -and -not (Test-TIIsAdmin)) {
    $elevated = $false
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList (Get-TIElevatedArgs -Reopen:$Reopen) -PassThru -ErrorAction Stop
        $elevated = $true
    } catch { }
    if ($elevated) {
        if (-not (Test-TIElevatedStart $proc)) {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                [void][System.Windows.Forms.MessageBox]::Show(
                    ("O TI Suite não conseguiu abrir como administrador (código {0}).`n`nSe a pasta está numa unidade de rede, copie-a para este computador ou para o pendrive e abra de lá." -f $proc.ExitCode),
                    'TI Suite - elevação', 'OK', 'Warning')
            } catch { }
            exit 1
        }
        exit 0
    }
    # UAC recusado (ou sem a senha de administrador): oferece o modo consulta
    $answer = 'No'
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $answer = [System.Windows.Forms.MessageBox]::Show(
            ("O Windows não liberou o modo administrador (UAC).`n`n" +
             "Abrir o TI Suite só para consulta? Início, Saúde do PC, Rede e Inventário funcionam; " +
             "as ações que mudam o computador ficam bloqueadas.`n`n" +
             "Para liberar tudo depois, clique no selo ""Sem elevação"" da barra lateral."),
            'TI Suite - elevação', 'YesNo', 'Question')
    } catch { }
    if ([string]$answer -ne 'Yes') { exit 0 }
}

if ($useMutex) {
    $waitMs = if ($Reopen) { 20000 } else { 0 }
    if (-not (Enter-TISingleInstance -WaitMs $waitMs)) {
        Show-TIOtherInstance
        exit 0
    }
}

# ---------------------------------------------------------------------
# Carregamento dos componentes
# ---------------------------------------------------------------------

# Erro inesperado também aparece no console (sem diálogo modal) e num aviso
# discreto no máximo a cada 15 s. Protegido contra reentrada.
function Write-TIUnexpectedError {
    param([string]$Message)
    if ($global:TIInErrorReport) { return }
    $global:TIInErrorReport = $true
    try {
        if ($global:Form -and $global:Form.InvokeRequired) { return }   # outra thread: fica só no arquivo
        if (Get-Command Write-TILog -ErrorAction SilentlyContinue) {
            Write-TILog -Level 'Error' -Message ('Erro inesperado: {0} (detalhes no exceptions.log: Configurações > Abrir pasta de logs).' -f $Message)
        }
        $now = Get-Date
        if ($global:Form -and $global:Form.Visible -and (Get-Command Show-TIToast -ErrorAction SilentlyContinue) -and
            (-not $global:TILastErrorToast -or ($now - $global:TILastErrorToast).TotalSeconds -ge 15)) {
            $global:TILastErrorToast = $now
            Show-TIToast -Text 'Erro inesperado: detalhes no console (F12).' -Type 'Error'
        }
    } catch { } finally { $global:TIInErrorReport = $false }
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [void][System.Windows.Forms.Application]::EnableVisualStyles()

    # Rede de segurança: exceções em handlers WinForms não podem abrir diálogo
    # modal (congelaria a interface). Vão para exceptions.log e para o console.
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        try {
            ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $e.Exception.ToString() + "`r`n" + ('-' * 70)) |
                Add-Content -LiteralPath $global:TILogPath -Encoding UTF8
        } catch { }
        Write-TIUnexpectedError -Message $e.Exception.Message
    })
    [System.AppDomain]::CurrentDomain.add_UnhandledException({
        param($sender, $e)
        try {
            ('FATAL [' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $e.ExceptionObject.ToString() + "`r`n" + ('-' * 70)) |
                Add-Content -LiteralPath $global:TILogPath -Encoding UTF8
        } catch { }
        $msg = if ($e.ExceptionObject -is [System.Exception]) { $e.ExceptionObject.Message } else { [string]$e.ExceptionObject }
        Write-TIUnexpectedError -Message $msg
    })

    $core = Join-Path $script:TIRoot 'src\Core'
    $wsp  = Join-Path $script:TIRoot 'src\Workspaces'

    . (Join-Path $core '00-Controls.ps1')
    . (Join-Path $core '01-Theme.ps1')
    . (Join-Path $core '02-Dialogs.ps1')
    . (Join-Path $core '03-Logging.ps1')
    . (Join-Path $core '04-Async.ps1')
    . (Join-Path $core '05-Shell.ps1')
    . (Join-Path $core '99-SelfTest.ps1')

    # A ordem aqui é a ordem da barra lateral e dos atalhos Ctrl+1 a Ctrl+7
    . (Join-Path $wsp 'Dashboard.ps1')
    . (Join-Path $wsp 'Saude.ps1')
    . (Join-Path $wsp 'Limpeza.ps1')
    . (Join-Path $wsp 'Programas.ps1')
    . (Join-Path $wsp 'Contas.ps1')
    . (Join-Path $wsp 'Rede.ps1')
    . (Join-Path $wsp 'Inventario.ps1')

    Start-TIApp
} catch {
    $msg = $_ | Out-String
    try {
        $crashDir = Split-Path -Parent $global:TILogPath
        if (-not (Test-Path -LiteralPath $crashDir)) { New-Item -ItemType Directory -Path $crashDir -Force | Out-Null }
        $msg | Set-Content -LiteralPath (Join-Path $crashDir 'crash.log') -Encoding UTF8
    } catch { }
    try {
        if ($env:TI_SUITE_QUIET -ne '1') {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show(
                ("O TI Suite não conseguiu abrir:`n`n" + $msg),
                'TI Suite - erro ao abrir', 'OK', 'Error')
        } else {
            Write-Host $msg -ForegroundColor Red
        }
    } catch {
        Write-Host $msg -ForegroundColor Red
    }
    Exit-TISingleInstance
    exit 1
}

# ---------------------------------------------------------------------
# Modo de autoverificação
# ---------------------------------------------------------------------
if ($SelfTest) {
    $code = Invoke-TISelfTest
    exit $code
}

# ---------------------------------------------------------------------
# Execução normal
# ---------------------------------------------------------------------
[void]$global:Form.ShowDialog()
try { $global:Form.Dispose() } catch { }
Exit-TISingleInstance
exit 0
