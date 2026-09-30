# =====================================================================
# TI-SUITE.ps1 - Ponto de entrada
# Uso:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\TI-Suite.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\TI-Suite.ps1 -SelfTest
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\TI-Suite.ps1 -NoElevate
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\TI-Suite.ps1 -SkipIntegrity   (desenvolvimento)
# =====================================================================

#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$NoElevate,
    [switch]$SkipIntegrity
)

$ErrorActionPreference = 'Stop'
$script:TIRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:TIRoot = $script:TIRoot
$global:TIEntryPoint = $MyInvocation.MyCommand.Path
$global:TISkipIntegrity = $SkipIntegrity.IsPresent
try { Set-Location -LiteralPath $script:TIRoot } catch { }

# ---------------------------------------------------------------------
# Modo portátil: se portable.config existir ao lado do script,
# configurações, logs e inventário ficam na própria pasta (rodar de USB).
# ---------------------------------------------------------------------
$global:TIPortable = (Test-Path (Join-Path $script:TIRoot 'portable.config'))

function Get-TIAppDataDir {
    if ($global:TIPortable) { return $script:TIRoot }
    return (Join-Path $env:LOCALAPPDATA 'TI-Suite')
}

function Initialize-TILogPath {
    $root = Get-TIAppDataDir
    $logDir = if ($global:TIPortable) { Join-Path $root 'logs' } else { $root }
    try {
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
    } catch { }
    $global:TILogPath = Join-Path $logDir 'exceptions.log'
}

Initialize-TILogPath

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
# Elevação (UAC) - omitida em modo SelfTest/NoElevate
# ---------------------------------------------------------------------
function Test-EntryIsAdmin {
    try {
        $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# WinForms exige STA em qualquer PC
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $reArgs = '-NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f $global:TIEntryPoint
    if ($SelfTest) { $reArgs += ' -SelfTest' }
    if ($NoElevate) { $reArgs += ' -NoElevate' }
    if ($SkipIntegrity) { $reArgs += ' -SkipIntegrity' }
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $reArgs -Wait -NoNewWindow -PassThru
        exit $(if ($p) { $p.ExitCode } else { 1 })
    } catch {
        Write-Host 'Não foi possível reabrir em modo STA. Use o Iniciar.cmd.' -ForegroundColor Red
        exit 1
    }
}

if (-not $SelfTest -and -not $NoElevate) {
    if (-not (Test-EntryIsAdmin)) {
        $argLine = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $global:TIEntryPoint
        if ($SkipIntegrity) { $argLine += ' -SkipIntegrity' }
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argLine -ErrorAction Stop
            exit 0
        } catch {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                [void][System.Windows.Forms.MessageBox]::Show(
                    'O TI Suite precisa de administrador para cuidar de perfis, contas, programas e rede.',
                    'TI Suite - elevação necessária', 'OK', 'Warning')
            } catch { }
            exit 1
        }
    }
}

# ---------------------------------------------------------------------
# Carregamento dos componentes
# ---------------------------------------------------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [void][System.Windows.Forms.Application]::EnableVisualStyles()

    # Rede de segurança: exceções em handlers WinForms não podem abrir diálogo
    # modal (congelaria a interface). Vão para exceptions.log.
    if (-not $global:TILogPath) { Initialize-TILogPath }
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        try {
            ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $e.Exception.ToString() + "`r`n" + ('-' * 70)) |
                Add-Content -LiteralPath $global:TILogPath -Encoding UTF8
        } catch { }
    })
    [System.AppDomain]::CurrentDomain.add_UnhandledException({
        param($sender, $e)
        try {
            ('FATAL [' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $e.ExceptionObject.ToString() + "`r`n" + ('-' * 70)) |
                Add-Content -LiteralPath $global:TILogPath -Encoding UTF8
        } catch { }
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
    $logDir = if ($global:TIPortable) { Join-Path $script:TIRoot 'logs' } else { Join-Path $env:LOCALAPPDATA 'TI-Suite' }
    try {
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $msg | Set-Content -LiteralPath (Join-Path $logDir 'crash.log') -Encoding UTF8
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
exit 0
