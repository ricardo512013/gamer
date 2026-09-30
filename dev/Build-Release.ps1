# =====================================================================
# Build-Release.ps1 - Gera o pacote de distribuição (sem a pasta dev\)
#   1. confere a sintaxe de todos os .ps1 (para no primeiro erro)
#   2. roda dev\Test-Logic.ps1 (para se algum teste falhar)
#   3. compila src\Core\Controls.cs em bin\TISuite.Controls.dll (+ carimbo)
#   4. monta o pacote numa pasta temporária e grava nela o manifest.sha256
#      (só código: .ps1, .cs, .cmd e bin\*; documentação e portable.config ficam de fora)
#   5. cria dist\TI-Suite-vX.Y.Z.zip (sem dev\, logs\, inventario\, config.json da máquina, .git)
# O manifesto vai só no pacote: na pasta do projeto ele travaria o app a cada edição.
# Uso:  powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\Build-Release.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

# A DLL precisa ser do .NET Framework (Windows PowerShell 5.1), não do .NET do pwsh 7
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host 'Reabrindo no Windows PowerShell 5.1 (a DLL precisa ser do .NET Framework)...' -ForegroundColor Yellow
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit $LASTEXITCODE
}

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location -LiteralPath $root

$themeText = Get-Content -Raw -LiteralPath (Join-Path $root 'src\Core\01-Theme.ps1') -Encoding UTF8
$ver = if ($themeText -match "TI\.Version\s*=\s*'([^']+)'") { $Matches[1] } else { '0.0.0' }
Write-Host ('TI Suite v{0}' -f $ver) -ForegroundColor Cyan

# 1. Sintaxe -----------------------------------------------------------
$bad = 0
$psFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -Filter '*.ps1') + @(Get-Item -LiteralPath (Join-Path $root 'TI-Suite.ps1'))
foreach ($f in $psFiles) {
    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
    foreach ($x in @($e)) {
        $bad++
        Write-Host ('  {0}:{1}  {2}' -f $f.Name, $x.Extent.StartLineNumber, $x.Message) -ForegroundColor Red
    }
}
if ($bad -gt 0) { Write-Host 'Build cancelado: corrija os erros de sintaxe acima.' -ForegroundColor Red; exit 1 }
Write-Host ('Sintaxe: {0} arquivos OK' -f $psFiles.Count) -ForegroundColor Green

# 2. Testes das regras (processo separado: não carrega nada neste) -------------
$testScript = Join-Path $root 'dev\Test-Logic.ps1'
if (-not (Test-Path -LiteralPath $testScript)) { Write-Host 'Build cancelado: dev\Test-Logic.ps1 não encontrado.' -ForegroundColor Red; exit 1 }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testScript
if ($LASTEXITCODE -ne 0) {
    Write-Host ('Build cancelado: dev\Test-Logic.ps1 falhou (código {0}).' -f $LASTEXITCODE) -ForegroundColor Red
    exit 1
}
Write-Host 'Testes: OK' -ForegroundColor Green

# 3. DLL dos controles -------------------------------------------------
$cs     = Join-Path $root 'src\Core\Controls.cs'
$binDir = Join-Path $root 'bin'
$dll    = Join-Path $binDir 'TISuite.Controls.dll'
$stamp  = Join-Path $binDir 'TISuite.Controls.stamp'
New-Item -ItemType Directory -Path $binDir -Force | Out-Null
foreach ($old in @($dll, $stamp)) {
    if (Test-Path -LiteralPath $old) {
        try { Remove-Item -LiteralPath $old -Force }
        catch { Write-Host ('Feche o TI Suite antes do build (arquivo em uso): {0}' -f $old) -ForegroundColor Red; exit 1 }
    }
}
$src = Get-Content -LiteralPath $cs -Raw -Encoding UTF8
Add-Type -TypeDefinition $src -ReferencedAssemblies System.dll, System.Drawing.dll, System.Windows.Forms.dll `
         -OutputAssembly $dll -OutputType Library
(Get-FileHash -LiteralPath $cs -Algorithm SHA256).Hash | Set-Content -LiteralPath $stamp -Encoding ASCII
Write-Host ('DLL: {0}' -f $dll) -ForegroundColor Green

# 4. Arquivos do pacote e manifesto de integridade ---------------------------
# dados de campo (laudos, relatórios, perfis de Wi-Fi com senha) nunca vão para o pacote
$excludeDirs  = @('dev', 'logs', 'dist', '.git', 'inventario', 'laudos', 'relatorios', 'wifi')
$excludeFiles = @('manifest.sha256', 'config.json', 'exceptions.log', 'crash.log', 'audit.csv', 'inventario.csv')

function Get-RelPath([System.IO.FileInfo]$f) {
    return $f.FullName.Substring($root.Length).TrimStart('\', '/')
}

function Test-Included([System.IO.FileInfo]$f) {
    $rel = Get-RelPath $f
    $first = ($rel -split '[\\/]')[0]
    if ($excludeDirs -contains $first) { return $false }
    if ($excludeFiles -contains $f.Name) { return $false }
    if ($f.Extension -eq '.zip' -or $f.Extension -eq '.tmp') { return $false }
    return $true
}

# O manifesto confere só o que roda: .ps1, .cs, .cmd e bin\*. README.md, CHANGELOG.md,
# .gitignore e portable.config vão no pacote, mas editar ou apagar um deles (o README
# manda apagar o portable.config para o modo instalado) não pode travar a abertura.
function Test-InManifest([System.IO.FileInfo]$f) {
    $first = ((Get-RelPath $f) -split '[\\/]')[0]
    if ($first -eq 'bin') { return $true }
    return (@('.ps1', '.cs', '.cmd') -contains $f.Extension.ToLowerInvariant())
}

$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object { Test-Included $_ } | Sort-Object FullName)
$lines = @(foreach ($f in ($files | Where-Object { Test-InManifest $_ })) {
    $rel = (Get-RelPath $f).Replace('\', '/')
    '{0} *{1}' -f (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash, $rel
})

# Manifesto de builds antigos na pasta do projeto: travaria o app depois de qualquer edição
$oldManifest = Join-Path $root 'manifest.sha256'
if (Test-Path -LiteralPath $oldManifest) {
    Remove-Item -LiteralPath $oldManifest -Force
    Write-Host 'Removido manifest.sha256 antigo da pasta do projeto (agora ele vai só no pacote).' -ForegroundColor DarkGray
}

# 5. Pacote -------------------------------------------------------------
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('ti-suite-stage-' + [guid]::NewGuid().ToString('N'))
$dst = Join-Path $stage 'TI-Suite'
New-Item -ItemType Directory -Path $dst -Force | Out-Null
foreach ($f in $files) {
    $target = Join-Path $dst (Get-RelPath $f)
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $f.FullName -Destination $target
}
Set-Content -LiteralPath (Join-Path $dst 'manifest.sha256') -Value $lines -Encoding UTF8
Write-Host ('Manifesto: {0} arquivos de código' -f $lines.Count) -ForegroundColor Green

# config.json padrão (sem dados da máquina de desenvolvimento)
Set-Content -LiteralPath (Join-Path $dst 'config.json') -Encoding UTF8 -Value @'
{
    "CompactConsole": true,
    "ConsoleHeight": 0,
    "CrispText": false,
    "ForceChangeOnLogon": false,
    "WindowMaximized": false
}
'@

$distDir = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
$zip = Join-Path $distDir ('TI-Suite-v{0}.zip' -f $ver)
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path $dst -DestinationPath $zip
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host ('Pacote: {0}' -f $zip) -ForegroundColor Green
Write-Host 'Obs.: o manifesto detecta corrupção e adulteração casual; para proteção forte use BitLocker To Go ou assinatura Authenticode.' -ForegroundColor DarkGray
