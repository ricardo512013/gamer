# =====================================================================
# 00-CONTROLS.ps1 - Carrega a biblioteca de controles visuais (C#)
#
#   1. bin\TISuite.Controls.dll pré-compilada (gerada pelo dev\Build-Release.ps1),
#      desde que o carimbo confira com o Controls.cs atual: abre bem mais rápido
#      e não depende de compilar nada no PC.
#   2. Sem a DLL (ou com Controls.cs editado depois do build), compila
#      src\Core\Controls.cs na hora com o Add-Type (C# 5).
#   O WinPE do pendrive de recuperação não tem o compilador C#: lá só a DLL
#   serve, e sem ela o app explica como resolver ($global:TIStartupErrorText,
#   mostrado pelo TI-Suite.ps1) em vez de um erro técnico.
# =====================================================================

# Origem para o log ("Controles visuais: {0}.") e o autoteste; o motivo de não
# usar a DLL (quando havia uma) fica em $global:TIControlsError.
$global:TIControlsSource = 'já carregados'
$global:TIControlsError = $null
if (-not ('TISuite.Native' -as [type])) {
    $csPath    = Join-Path $global:TIRoot 'src\Core\Controls.cs'
    $dllPath   = Join-Path $global:TIRoot 'bin\TISuite.Controls.dll'
    $stampPath = Join-Path $global:TIRoot 'bin\TISuite.Controls.stamp'
    # Por que a DLL não serviu (para a mensagem do WinPE)
    $dllState = 'não foi encontrada'

    if ((Test-Path -LiteralPath $dllPath) -and (Test-Path -LiteralPath $stampPath) -and (Test-Path -LiteralPath $csPath)) {
        try {
            $want = ([string](Get-Content -LiteralPath $stampPath -Raw -Encoding UTF8)).Trim()
            $have = (Get-FileHash -LiteralPath $csPath -Algorithm SHA256).Hash
            if ($want -eq $have) {
                Add-Type -LiteralPath $dllPath -ErrorAction Stop
                $global:TIControlsSource = 'DLL pré-compilada'
            } else {
                $global:TIControlsSource = 'compilados (DLL desatualizada)'
                $global:TIControlsError = 'carimbo diferente do Controls.cs'
                $dllState = 'não confere com o src\Core\Controls.cs (DLL de outra versão)'
            }
        } catch {
            $global:TIControlsSource = 'compilados (DLL não carregou)'
            $global:TIControlsError = $_.Exception.Message
            $dllState = ('não carregou ({0})' -f $_.Exception.Message)
        }
    } elseif (Test-Path -LiteralPath $dllPath) {
        $dllState = 'está sem o carimbo (bin\TISuite.Controls.stamp)'
    }

    if (-not ('TISuite.Native' -as [type])) {
        try {
            $src = Get-Content -LiteralPath $csPath -Raw -Encoding UTF8 -ErrorAction Stop
            Add-Type -TypeDefinition $src -ReferencedAssemblies System.dll, System.Drawing.dll, System.Windows.Forms.dll -ErrorAction Stop
        } catch {
            if ($global:TIWinPE) {
                $global:TIStartupErrorText = ("O TI Suite não pode abrir no modo recuperação: a biblioteca dos controles visuais " +
                    "(bin\TISuite.Controls.dll) {0}, e o WinPE não tem o compilador C# para prepará-la na hora.`n`n" +
                    "Gere o pendrive de novo com o Criar-Pendrive.ps1, que compila a DLL.") -f $dllState
            } else {
                $global:TIStartupErrorText = ("O TI Suite não conseguiu preparar os controles visuais (src\Core\Controls.cs): {0}`n`n" +
                    "Copie de novo a pasta completa do TI Suite. O pacote gerado pelo dev\Build-Release.ps1 traz a DLL pronta em bin\ " +
                    "e não depende de compilar nada neste computador.") -f $_.Exception.Message
            }
            throw
        }
        if ($global:TIControlsSource -eq 'já carregados') { $global:TIControlsSource = 'compilados na hora' }
    }
}

# DPI: o layout usa posições/tamanhos fixos em pixels (AutoScaleMode = None).
# Com o processo "DPI aware", notebooks em 125%/150% aumentam só as FONTES e o layout
# desalinha (textos cortados/sobrepostos). Por padrão o Windows escala a janela inteira
# (modo compatível: layout sempre igual, texto levemente suave). Quem quiser texto nítido
# liga "CrispText" no config.json / Configurações (vale no próximo início).
$script:TICrisp = $false
try {
    $cfgPath = if ($global:TIPortable) { Join-Path $global:TIRoot 'config.json' } else { Join-Path $env:LOCALAPPDATA 'TI-Suite\config.json' }
    if (Test-Path -LiteralPath $cfgPath) {
        $cfgJ = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $cfgJ.CrispText) { $script:TICrisp = [bool]$cfgJ.CrispText }
    }
} catch { }
# No WinPE não há escala de tela (nem a opção nas Configurações)
if ($script:TICrisp -and -not $global:TIWinPE) { [TISuite.Native]::EnableDpi() | Out-Null }
