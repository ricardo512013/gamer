<#
.SYNOPSIS
    Cria o pendrive de recuperação do TI Suite: Windows PE com boot (BIOS e UEFI) e o app na partição TI-SUITE.

.DESCRIPTION
    Roda num PC com Windows 10 ou 11, como administrador, com o Windows ADK (Ferramentas de Implantação) e o
    complemento Windows PE instalados. Os dois estão na página oficial da Microsoft "Baixar e instalar o Windows ADK":
    https://learn.microsoft.com/pt-br/windows-hardware/get-started/adk-install

    O pendrive fica com duas partições (tabela MBR, boot BIOS e UEFI):
      TI-BOOT   FAT32, 2 GB, ativa: o Windows PE (pt-BR, teclado ABNT2, PowerShell, WMI, DISM e BitLocker).
      TI-SUITE  NTFS (ou exFAT), o resto: o TI Suite na raiz e os dados de campo.
    Com o Windows aberto, o pendrive funciona como sempre (Iniciar.cmd). No boot, o TI Suite abre sozinho em
    modo recuperação.

    TUDO no pendrive é apagado. Antes de formatar, os dados de campo do TI Suite que já estiverem nele
    (inventario, logs, laudos, relatorios, wifi, backup, Backup-TI, reparo e config.json) são guardados numa
    pasta temporária e devolvidos no fim. Se não der para guardar, nada é apagado.
    O log de cada execução fica em dist\criar-pendrive-<data>.log.

.PARAMETER SomenteAtualizar
    Só recopia o TI Suite para a partição TI-SUITE de um pendrive já criado. Não formata, não mexe no boot nem nos
    dados de campo e não precisa do ADK.

.PARAMETER SomenteISO
    Só gera dist\TI-Recuperacao.iso (Windows PE + TI Suite) para testar numa máquina virtual, sem pendrive.
    No ISO o TI Suite fica em mídia somente leitura: logs e laudos não são gravados.

.PARAMETER Disco
    Número do disco do pendrive (o mesmo do Get-Disk e do diskpart), para não perguntar.
    A confirmação digitando APAGAR continua valendo.

.PARAMETER SistemaArquivos
    Sistema de arquivos da partição TI-SUITE: NTFS (padrão) ou exFAT. Os dois aceitam arquivos maiores que 4 GB,
    como o install.wim da pasta reparo.

.PARAMETER Boot2023
    Usa os arquivos de boot assinados com a "Windows UEFI CA 2023" (MakeWinPEMedia /bootex; precisa do ADK
    10.1.26100.2454, de dezembro de 2024, ou mais novo). Use só para PCs que já revogaram o certificado antigo de
    boot da Microsoft (Windows Production PCA 2011): neles o pendrive padrão não dá boot com o Secure Boot ligado.
    ATENÇÃO: pendrive feito assim NÃO dá boot, com o Secure Boot ligado, em PCs antigos que ainda não têm a
    CA 2023 no firmware. Sem esta opção o boot é o compatível, que funciona na grande maioria dos PCs.

.PARAMETER Drivers
    Pasta com drivers (.inf, procurados também nas subpastas) para pôr no Windows PE, com o caminho completo.
    Ex.: Intel RST/VMD, para o Windows PE enxergar o SSD NVMe de notebooks com o Intel VMD ligado. Use drivers de
    64 bits (x64). Padrão: dev\drivers, se existir.

.PARAMETER Ajuda
    Mostra esta ajuda.

.EXAMPLE
    Criar-Pendrive.cmd
    Lista os pendrives, pergunta o número do disco, pede para digitar APAGAR e cria o pendrive de recuperação.

.EXAMPLE
    Criar-Pendrive.cmd -SomenteAtualizar
    Depois de mudar o código, recopia o TI Suite para um pendrive já criado, sem formatar.

.EXAMPLE
    Criar-Pendrive.cmd -SomenteISO
    Gera dist\TI-Recuperacao.iso para testar no Hyper-V ou no VirtualBox.

.EXAMPLE
    Criar-Pendrive.cmd -Disco 2 -SistemaArquivos exFAT -Drivers D:\drivers\vmd

.NOTES
    Uso direto: powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\Criar-Pendrive.ps1 [opções]
    Códigos de saída: 0 = pronto; 1 = erro ou cancelado (a mensagem diz se algo foi apagado);
    2 = pendrive criado, mas os dados de campo não voltaram (ficam guardados na pasta indicada).
    As funções puras (antes da linha "Daqui para baixo") são testadas pelo dev\Test-Logic.ps1, que carrega este
    arquivo com ". .\dev\Criar-Pendrive.ps1" (dot-source): nesse caso o script só define as funções.
#>
[CmdletBinding()]
param(
    [switch]$SomenteAtualizar,
    [switch]$SomenteISO,
    [int]$Disco = -1,
    [ValidateSet('NTFS', 'exFAT')]
    [string]$SistemaArquivos = 'NTFS',
    [switch]$Boot2023,
    [string]$Drivers = '',
    [switch]$Ajuda
)

# =====================================================================
# Funções puras: só texto e listas, sem cmdlets do Windows (testáveis no
# pwsh do Linux). Caminhos montados com '\' de propósito.
# =====================================================================

# BusType do Get-Disk: texto ('USB') ou número do MSFT_Disk (7 = USB, 12 = SD, 13 = MMC)
function ConvertTo-TIPEBusType {
    param($Value)
    if ($null -eq $Value) { return '' }
    $n = 0
    if ([int]::TryParse([string]$Value, [ref]$n)) {
        $map = @{ 1 = 'SCSI'; 2 = 'ATAPI'; 3 = 'ATA'; 4 = '1394'; 5 = 'SSA'; 6 = 'Fibre Channel'; 7 = 'USB'; 8 = 'RAID'
                  9 = 'iSCSI'; 10 = 'SAS'; 11 = 'SATA'; 12 = 'SD'; 13 = 'MMC'; 14 = 'Virtual'; 15 = 'File Backed Virtual'
                  16 = 'Spaces'; 17 = 'NVMe'; 18 = 'SCM'; 19 = 'UFS' }
        if ($map.ContainsKey($n)) { return $map[$n] }
        return 'Desconhecido'
    }
    return ([string]$Value).Trim()
}

# Tamanho para a tela: '28,6 GB' (vírgula decimal, sem depender da cultura do PC)
function Format-TIPESize {
    param([double]$Bytes)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -ge 1TB) { return (($Bytes / 1TB).ToString('0.0', $inv).Replace('.', ',') + ' TB') }
    if ($Bytes -ge 1GB) { return (($Bytes / 1GB).ToString('0.0', $inv).Replace('.', ',') + ' GB') }
    if ($Bytes -ge 1MB) { return (($Bytes / 1MB).ToString('0', $inv) + ' MB') }
    return (($Bytes / 1KB).ToString('0', $inv) + ' KB')
}

# Quais discos podem virar o pendrive de recuperação. Entrada: objetos com Number, FriendlyName, Size,
# BusType, MediaType (do Win32_DiskDrive), IsBoot, IsSystem, IsReadOnly, HasRunningWindows, HasProject e
# UniqueId. Só USB/SD/MMC ou mídia removível; nunca o disco do Windows em execução nem o da pasta do projeto
# (ou do %TEMP%, onde ficam a pasta de trabalho e a cópia dos dados de campo).
# Code: ok | notremovable | windows | project | readonly | nomedia | small
function Get-TIPEDiskCandidates {
    param([object[]]$Disks, [double]$MinBytes = 7000000000)
    foreach ($d in @($Disks)) {
        if ($null -eq $d) { continue }
        $bus = ConvertTo-TIPEBusType $d.BusType
        $removable = ((@('USB', 'SD', 'MMC') -contains $bus) -or ([string]$d.MediaType -match '(?i)removable|remov[ií]vel'))
        $size = [double]0
        if ($null -ne $d.Size) { $size = [double]$d.Size }
        $code = 'ok'; $reason = ''
        if (-not $removable) { $code = 'notremovable'; $reason = 'não é USB nem removível' }
        elseif ($d.IsBoot -or $d.IsSystem -or $d.HasRunningWindows) { $code = 'windows'; $reason = 'tem o Windows em execução' }
        elseif ($d.HasProject) { $code = 'project'; $reason = 'tem a pasta do projeto ou a pasta temporária deste script' }
        elseif ($d.IsReadOnly) { $code = 'readonly'; $reason = 'está protegido contra gravação' }
        elseif ($size -le 0) { $code = 'nomedia'; $reason = 'está sem mídia (leitor de cartão vazio?)' }
        elseif ($size -lt $MinBytes) { $code = 'small'; $reason = 'tem menos de 8 GB' }
        [pscustomobject]@{
            Number    = [int]$d.Number
            Name      = ([string]$d.FriendlyName).Trim()
            Size      = $size
            SizeText  = (Format-TIPESize $size)
            BusType   = $bus
            UniqueId  = [string]$d.UniqueId
            Removable = [bool]$removable
            Eligible  = ($code -eq 'ok')
            Code      = $code
            Reason    = $reason
        }
    }
}

# A palavra de confirmação antes de apagar o pendrive (sem diferença de maiúsculas; espaços nas pontas não contam)
function Test-TIPEConfirmWord {
    param([string]$Text, [string]$Word = 'APAGAR')
    return (([string]$Text).Trim() -eq $Word)
}

# Letras livres para as partições novas (sem A/B, C e X, que é a do Windows PE)
function Get-TIPEFreeLetters {
    param([string[]]$Used, [int]$Count = 2)
    $busy = @{}
    foreach ($u in @($Used)) {
        $s = [string]$u
        if ($s.Length -ge 1) { $busy[$s.Substring(0, 1).ToUpperInvariant()] = $true }
    }
    $free = New-Object System.Collections.ArrayList
    foreach ($c in 'DEFGHIJKLMNOPQRSTUVWYZ'.ToCharArray()) {
        if ($free.Count -ge $Count) { break }
        if (-not $busy.ContainsKey([string]$c)) { [void]$free.Add([string]$c) }
    }
    return @($free)
}

# Script do diskpart: o roteiro da documentação da Microsoft para WinPE com duas partições (depois do
# "clean" o disco fica sem tabela e o "create partition" cria em MBR; o script confere depois).
# Sem "noerr": qualquer erro para o diskpart com código diferente de 0.
# A letra só é dada depois de formatar: assim o Windows não pergunta "Formatar o disco?".
function Get-TIPEDiskpartScript {
    param([int]$DiskNumber, [string]$BootLetter, [string]$DataLetter, [string]$FileSystem = 'NTFS', [int]$BootMB = 2048)
    $fs = 'ntfs'
    if ($FileSystem -eq 'exFAT') { $fs = 'exfat' }
    return @(
        ('select disk {0}' -f $DiskNumber),
        'clean',
        ('create partition primary size={0}' -f $BootMB),
        'format fs=fat32 quick label="TI-BOOT"',
        'active',
        ('assign letter={0}' -f $BootLetter),
        'create partition primary',
        ('format fs={0} quick label="TI-SUITE"' -f $fs),
        ('assign letter={0}' -f $DataLetter),
        'exit'
    )
}

# startnet.cmd do Windows PE (ASCII: o cmd do WinPE lê na página de código OEM).
# Procura TI-Suite.ps1 + portable.config na raiz de C: a Z: (o pendrive pode demorar a aparecer),
# abre o TI Suite em modo recuperação e, quando ele fecha, mostra um menu simples.
function New-TIPEStartnet {
    return @(
        '@echo off',
        'rem =====================================================================',
        'rem  TI Suite - modo recuperacao (Windows PE). Gerado pelo dev\Criar-Pendrive.ps1.',
        'rem  Procura a pasta do TI Suite (TI-Suite.ps1 e portable.config na raiz de uma',
        'rem  unidade), abre o app com -Recovery e mostra um menu quando ele fecha.',
        'rem =====================================================================',
        'wpeinit',
        'powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1',
        'title TI Suite - Recuperacao',
        'set "TIPS=X:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"',
        'set "TIDRV="',
        'set "TITRY=0"',
        '',
        ':procurar',
        'for %%L in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (',
        '    if not defined TIDRV if exist "%%L:\TI-Suite.ps1" if exist "%%L:\portable.config" set "TIDRV=%%L:"',
        ')',
        'if defined TIDRV goto abrir',
        'set /a TITRY+=1',
        'if %TITRY% GEQ 10 goto naoachou',
        'echo Procurando o pendrive do TI Suite... (tentativa %TITRY% de 10)',
        'ping -n 3 127.0.0.1 >nul',
        'goto procurar',
        '',
        ':abrir',
        'if not exist "%TIPS%" goto semps',
        'echo.',
        'echo Abrindo o TI Suite em modo recuperacao (%TIDRV%)...',
        '"%TIPS%" -NoProfile -STA -ExecutionPolicy Bypass -File "%TIDRV%\TI-Suite.ps1" -Recovery',
        'goto menu',
        '',
        ':naoachou',
        'echo.',
        'echo  Nao encontrei o TI Suite: nenhuma unidade tem TI-Suite.ps1 e portable.config na raiz.',
        'echo  Confira se o pendrive esta conectado e escolha 1 para procurar de novo.',
        'echo  No prompt de comando, DISKPART e depois LIST VOLUME mostram as unidades.',
        'goto menu',
        '',
        ':semps',
        'echo.',
        'echo  Este Windows PE nao tem o PowerShell. Recrie o pendrive com o Criar-Pendrive.cmd.',
        'goto menu',
        '',
        ':menu',
        'echo.',
        'echo  ===== TI Suite - modo recuperacao =====',
        'echo    1 = Abrir o TI Suite de novo',
        'echo    2 = Prompt de comando',
        'echo    3 = Reiniciar o computador',
        'echo    4 = Desligar o computador',
        'echo.',
        'set "TIOP="',
        'set /p "TIOP=Digite o numero e tecle Enter: "',
        'if "%TIOP%"=="1" goto reabrir',
        'if "%TIOP%"=="2" goto prompt',
        'if "%TIOP%"=="3" goto reiniciar',
        'if "%TIOP%"=="4" goto desligar',
        'goto menu',
        '',
        ':reabrir',
        'if defined TIDRV if exist "%TIDRV%\TI-Suite.ps1" goto abrir',
        'set "TIDRV="',
        'set "TITRY=0"',
        'goto procurar',
        '',
        ':prompt',
        'echo.',
        'echo  Prompt de comando. Digite EXIT para voltar a este menu.',
        'cmd /k',
        'goto menu',
        '',
        ':reiniciar',
        'wpeutil reboot',
        'goto menu',
        '',
        ':desligar',
        'wpeutil shutdown',
        'goto menu'
    )
}

# Ordem dos pacotes do WinPE_OCs: o pacote de idioma (lp.cab) primeiro; depois cada componente seguido
# dos seus pacotes de idioma (en-us e pt-br, quando existem). $Available: caminhos relativos à pasta
# WinPE_OCs (ex.: 'WinPE-WMI.cab', 'pt-br\lp.cab', 'pt-br\WinPE-WMI_pt-br.cab'), sem diferença de maiúsculas.
function Get-TIPEPackagePlan {
    param(
        [string[]]$Available,
        [string]$Language = 'pt-br',
        [string[]]$Components = @('WinPE-WMI', 'WinPE-NetFx', 'WinPE-Scripting', 'WinPE-PowerShell', 'WinPE-StorageWMI',
                                  'WinPE-DismCmdlets', 'WinPE-SecureStartup', 'WinPE-EnhancedStorage')
    )
    $have = @{}
    foreach ($a in @($Available)) {
        if ($a) { $norm = ([string]$a).Replace('/', '\').TrimStart('\'); $have[$norm.ToLowerInvariant()] = $norm }
    }
    $plan = New-Object System.Collections.ArrayList
    $missing = New-Object System.Collections.ArrayList
    $lang = $Language.ToLowerInvariant()
    $lp = '{0}\lp.cab' -f $lang
    $hasLp = $have.ContainsKey($lp)
    if ($hasLp) { [void]$plan.Add($have[$lp]) }
    $langs = @('en-us')
    if ($lang -ne 'en-us') { $langs += $lang }
    foreach ($c in $Components) {
        $key = ('{0}.cab' -f $c).ToLowerInvariant()
        if (-not $have.ContainsKey($key)) { [void]$missing.Add($c); continue }
        [void]$plan.Add($have[$key])
        foreach ($l in $langs) {
            $lk = ('{0}\{1}_{0}.cab' -f $l, $c).ToLowerInvariant()
            if ($have.ContainsKey($lk)) { [void]$plan.Add($have[$lk]) }
        }
    }
    return [pscustomobject]@{ Packages = @($plan); Missing = @($missing); LanguagePack = $hasLp }
}

# Nome do valor em HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts para um arquivo de fonte:
# o mesmo do Windows que está criando o pendrive (ex.: 'Segoe UI Bold (TrueType)'); sem ele, '<nome> (TrueType)'.
function Get-TIPEFontValueName {
    param([string]$FileName, [System.Collections.IDictionary]$HostFonts)
    if ($HostFonts) {
        foreach ($k in @($HostFonts.Keys | Sort-Object)) {
            $v = [string]$HostFonts[$k]
            if ($v -and ([System.IO.Path]::GetFileName($v.Replace('\', '/')) -ieq $FileName)) { return [string]$k }
        }
    }
    return ('{0} (TrueType)' -f [System.IO.Path]::GetFileNameWithoutExtension($FileName))
}

# O que NÃO vai do projeto para o pendrive: desenvolvimento, pacotes, a DLL antiga (é compilada de novo),
# dados de campo (voltam do backup do pendrive antigo) e arquivos da máquina (config.json é gravado à parte).
# $RelativePath: relativo à raiz do projeto ('src\Core\01-Theme.ps1').
function Test-TIPEAppExcluded {
    param([string]$RelativePath)
    $rel = ([string]$RelativePath).Replace('/', '\').TrimStart('\')
    if (-not $rel) { return $true }
    $parts = $rel.Split('\')
    $first = $parts[0]
    $name = $parts[$parts.Length - 1]
    $dirs = @('dev', 'dist', 'bin', 'drivers', 'logs', 'inventario', 'laudos', 'relatorios', 'wifi', 'backup',
              'Backup-TI', 'reparo', 'dados-anteriores')
    if ($parts.Length -gt 1 -and (($dirs -contains $first) -or $first.StartsWith('.'))) { return $true }
    if ($parts.Length -eq 1) {
        $rootFiles = @('Criar-Pendrive.cmd', 'config.json', 'manifest.sha256', 'LEIA-ME-PENDRIVE.txt')
        if (($rootFiles -contains $name) -or $name.StartsWith('.')) { return $true }
    }
    if ($name -match '(?i)\.(zip|iso|wim|esd|tmp|log|bak)$') { return $true }
    if (@('exceptions.log', 'crash.log', 'audit.csv', 'inventario.csv', 'Thumbs.db', 'desktop.ini') -contains $name) { return $true }
    return $false
}

# Dados de campo guardados antes de formatar e devolvidos depois
function Get-TIPEFieldItems {
    return [pscustomobject]@{
        Dirs  = @('inventario', 'logs', 'laudos', 'relatorios', 'wifi', 'backup', 'Backup-TI', 'reparo', 'dados-anteriores')
        Files = @('config.json')
    }
}

# Para onde voltam os dados de cada pasta do TI Suite achada no pendrive antigo: a da raiz (ou a de
# caminho mais curto) volta para a raiz da TI-SUITE; as outras vão para dados-anteriores\<caminho>.
function Get-TIPERestorePlan {
    param([string[]]$Folders)
    $list = @(@($Folders) | Where-Object { $_ } |
        Sort-Object @{ Expression = { ([string]$_).TrimEnd('\').Split('\').Length } }, @{ Expression = { [string]$_ } })
    $i = 0
    foreach ($f in $list) {
        $target = ''
        if ($i -gt 0) {
            $clean = (([string]$f).TrimEnd('\') -replace '[:\\/]+', '_') -replace '[^\w\.\- ]', '_'
            $target = 'dados-anteriores\' + $clean.Trim('_', ' ')
        }
        [pscustomobject]@{ Source = [string]$f; Target = $target }
        $i++
    }
}

# Caminho que o cmd.exe e os scripts do ADK aceitam sem susto (ASCII, sem % ! ^ & " < > |)
function Test-TIPEAsciiPath {
    param([string]$Path)
    return (([string]$Path -match '^[\x20-\x7E]+$') -and ([string]$Path -notmatch '[%!\^&"<>|]'))
}

# Pasta de trabalho: %TEMP%\TI-PE-<id>; com acento ou símbolo no %TEMP% (ex.: usuário "João"), C:\TI-PE-<id>
function Get-TIPEWorkRoot {
    param([string]$Temp, [string]$SystemDrive = 'C:', [string]$Id)
    $base = ([string]$Temp).TrimEnd('\')
    if (-not $base -or $base -notmatch '^[A-Za-z]:\\' -or -not (Test-TIPEAsciiPath $base)) { $base = ([string]$SystemDrive).TrimEnd('\') }
    return ('{0}\TI-PE-{1}' -f $base, $Id)
}

# Argumentos para reabrir este script no Windows PowerShell 5.1 com as mesmas opções
function Get-TIPERelaunchArgs {
    param([System.Collections.IDictionary]$Bound)
    $out = New-Object System.Collections.ArrayList
    if (-not $Bound) { return @() }
    foreach ($k in @($Bound.Keys | Sort-Object)) {
        $v = $Bound[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) {
            if ($v.IsPresent) { [void]$out.Add('-' + $k) }
        } elseif ($v -is [bool]) {
            if ($v) { [void]$out.Add('-' + $k) }
        } elseif ($null -ne $v -and [string]$v -ne '') {
            [void]$out.Add('-' + $k)
            [void]$out.Add(([string]$v).TrimEnd('\'))
        }
    }
    return @($out)
}

# Linha de barra de progresso do DISM ("[=====  50.0%  ]"): não vai para a tela nem para o log
function Test-TIPEProgressLine {
    param([string]$Line)
    return ([string]$Line -match '^\s*\[[=\s]*(\d{1,3}([.,]\d+)?%)?[=\s]*\]\s*$')
}

# Texto entre aspas simples do PowerShell (para montar o comando do processo que compila a DLL)
function ConvertTo-TIPEQuoted {
    param([string]$Text)
    return ("'" + ([string]$Text).Replace("'", "''") + "'")
}

# Código de saída do robocopy: 0 a 7 = deu certo (com ou sem arquivos copiados); 8 ou mais = falhou
function Test-TIPERobocopyOk {
    param([int]$Code)
    return ($Code -ge 0 -and $Code -lt 8)
}

# Caminhos do ADK a partir do KitsRoot10 (ex.: 'C:\Program Files (x86)\Windows Kits\10\')
function Get-TIPEAdkLayout {
    param([string]$KitsRoot)
    $adk = ([string]$KitsRoot).TrimEnd('\') + '\Assessment and Deployment Kit'
    $dt = $adk + '\Deployment Tools'
    $pe = $adk + '\Windows Preinstallation Environment'
    return [pscustomobject]@{
        KitsRoot    = [string]$KitsRoot
        DeployTools = $dt
        SetEnv      = $dt + '\DandISetEnv.bat'
        Dism        = $dt + '\amd64\DISM\dism.exe'
        Bootsect    = $dt + '\amd64\BCDBoot\bootsect.exe'
        Oscdimg     = $dt + '\amd64\Oscdimg'
        PeRoot      = $pe
        CopyPE      = $pe + '\copype.cmd'
        MakeMedia   = $pe + '\MakeWinPEMedia.cmd'
        PeArch      = $pe + '\amd64'
        WinpeWim    = $pe + '\amd64\en-us\winpe.wim'
        Media       = $pe + '\amd64\Media'
        OCs         = $pe + '\amd64\WinPE_OCs'
    }
}

# Linha "Boot deste pendrive: ..." do LEIA-ME antigo (a atualização não sabe como o boot foi feito)
function Get-TIPEBootLine {
    param([string]$Text)
    foreach ($l in ([string]$Text -split "`r?`n")) {
        if ($l -match '^\s*Boot deste pendrive:') { return $l.Trim() }
    }
    return ''
}

function Get-TIPEBootText {
    param([bool]$Boot2023)
    if ($Boot2023) {
        return 'Boot deste pendrive: 2023 (Windows UEFI CA 2023). Com o Secure Boot ligado, só dá boot em PCs que já têm a CA 2023.'
    }
    return 'Boot deste pendrive: compatível (certificado de boot Microsoft de 2011; dá boot na grande maioria dos PCs).'
}

# LEIA-ME-PENDRIVE.txt da raiz da partição TI-SUITE (texto para o técnico)
function New-TIPELeiaMe {
    param([string]$StampLine, [string]$BootLine)
    $head = @('TI SUITE - PENDRIVE DE RECUPERAÇÃO', '==================================')
    if ($StampLine) { $head += $StampLine }
    if ($BootLine) { $head += $BootLine }
    $body = @'

O pendrive tem duas partes (partições):
  TI-BOOT   (2 GB, FAT32)  o sistema de recuperação (Windows PE) que dá boot. Não mexa nos arquivos dela.
  TI-SUITE  (esta unidade) o TI Suite e os dados de campo: inventario\, logs\, laudos\, relatorios\,
                           wifi\, Backup-TI\ e reparo\.

COM O WINDOWS FUNCIONANDO
  Abra o Iniciar.cmd desta unidade, como sempre.

QUANDO O WINDOWS NÃO ABRE: DAR BOOT PELO PENDRIVE
  1. Desligue o computador e conecte o pendrive (no PC de mesa, prefira uma porta USB de trás).
  2. Ligue e toque várias vezes a tecla do menu de boot assim que a tela acender:
       Dell, Lenovo e Acer .... F12 (Lenovo IdeaPad: Fn+F12 ou o botãozinho Novo)
       HP ..................... Esc e depois F9 (ou direto F9)
       Asus ................... F8 (PC de mesa) ou Esc (notebook)
       MSI e ASRock ........... F11
       Outros ................. tente F12, F11, F10, F9, F8 ou Esc
  3. Escolha o pendrive na lista (nos PCs mais novos aparece como "UEFI: <nome do pendrive>").
  4. Em 1 ou 2 minutos o TI Suite abre sozinho, em modo recuperação.
  O Secure Boot pode ficar ligado: o Windows PE é assinado pela Microsoft.
  Se o PC recusar o pendrive com o Secure Boot ligado ("violação de segurança", "assinatura inválida"), ele já
  revogou o certificado de boot antigo: recrie o pendrive com a opção -Boot2023. Evite desligar o Secure Boot
  num PC com BitLocker: o Windows pede a chave de recuperação no próximo início.

O QUE TEM NO MODO RECUPERAÇÃO
  Nada aqui reinstala o Windows nem apaga os arquivos dos usuários.
  - Recuperação: acha os Windows 10 e 11 instalados no PC (destrava o BitLocker com a chave de recuperação de
    48 dígitos), mostra a saúde do disco e faz os reparos: reparo automático, reparar a inicialização (boot),
    verificar o disco (chkdsk), reparar os arquivos do sistema (SFC e DISM), desfazer atualização, remover
    driver e ligar ou desligar o modo de segurança. Os laudos ficam na pasta laudos\.
  - Backup: copia a pasta do usuário (C:\Users\<nome>) para outro disco ou para este pendrive (Backup-TI\).
  Ao fechar o TI Suite aparece um menu: 1 = abrir de novo, 2 = prompt de comando, 3 = reiniciar, 4 = desligar.
  Não há Explorer nem área de trabalho: use o TI Suite ou o prompt de comando (notepad, robocopy, diskpart).

PASTA reparo\ (opcional)
  O reparo dos arquivos do sistema usa o próprio Windows como fonte. Quando isso não basta, o DISM precisa de
  uma imagem igual ao Windows instalado: copie para reparo\ o arquivo sources\install.wim (ou install.esd) do
  ISO oficial da Microsoft da MESMA versão do Windows do PC (ex.: Windows 11 24H2; Home e Pro vêm no mesmo
  arquivo). Esse arquivo serve só de fonte para o reparo: ele NÃO reinstala o Windows.
  Pode guardar mais de um (ex.: win11-24h2.wim e win10-22h2.esd): o TI Suite usa o da mesma versão e edição.
  A partição TI-SUITE é NTFS (ou exFAT) justamente para aceitar arquivos com mais de 4 GB.

PASTA Backup-TI\
  Cópias das pastas de usuários feitas pela área Backup quando o destino é este pendrive. São arquivos
  pessoais: guarde o pendrive com cuidado e apague o backup depois de devolver os arquivos ao usuário.

ATUALIZAR O TI SUITE NESTE PENDRIVE
  No computador com a pasta de código-fonte do TI Suite, rode:
    Criar-Pendrive.cmd -SomenteAtualizar
  Só os arquivos do app são trocados; os dados de campo ficam. Recriar o pendrive inteiro (Criar-Pendrive.cmd
  sem opções) também guarda e devolve os dados de campo.
'@
    return ((($head -join "`r`n") + "`r`n" + $body.Replace("`r`n", "`n").Replace("`n", "`r`n")).TrimEnd() + "`r`n")
}

# =====================================================================
# Daqui para baixo: só quando o script é executado. Carregado com ". arquivo"
# (dot-source, pelo dev\Test-Logic.ps1), ele para aqui com as funções puras definidas.
# =====================================================================
if ($MyInvocation.InvocationName -eq '.') { return }

if ($Ajuda) {
    Get-Help -Name $PSCommandPath -Detailed
    exit 0
}

# DISM, Storage e a DLL dos controles (.NET Framework) pedem o Windows PowerShell 5.1
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host 'Reabrindo no Windows PowerShell 5.1 (a DLL precisa ser do .NET Framework)...' -ForegroundColor Yellow
    $relArgs = @(Get-TIPERelaunchArgs -Bound $PSBoundParameters)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @relArgs
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
$script:DevDir = Split-Path -Parent $PSCommandPath
$script:Root = Split-Path -Parent $script:DevDir
$script:Started = Get-Date
$script:State = @{
    WorkRoot      = $null      # %TEMP%\TI-PE-<guid> (apagada no fim, mesmo com erro)
    DataBackup    = $null      # dados de campo guardados antes de formatar (só sai depois de devolvidos)
    DataRestored  = $false
    Formatted     = $false
    UpdateStarted = $false
    MountDir      = $null
    Mounted       = $false
    HiveKey       = $null
    IsoPath       = $null      # ISO montado agora (Mount-DiskImage)
    IsoTempLetter = $null
    Adk           = $null
    Dism          = $null
    StepNo        = 0
    Warnings      = (New-Object System.Collections.ArrayList)
    Summary       = (New-Object System.Collections.ArrayList)
}
$script:Reg = Join-Path $env:windir 'System32\reg.exe'
$script:Robocopy = Join-Path $env:windir 'System32\robocopy.exe'
$script:Diskpart = Join-Path $env:windir 'System32\diskpart.exe'
$script:Mountvol = Join-Path $env:windir 'System32\mountvol.exe'
$script:PS51 = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:Mutex = $null

# --- Mensagens -------------------------------------------------------------
function Write-TIPEStep {
    param([string]$Text)
    $script:State.StepNo++
    Write-Host ''
    Write-Host ('[{0}] {1}' -f $script:State.StepNo, $Text) -ForegroundColor Cyan
}
function Write-TIPEInfo { param([string]$Text) Write-Host ('    ' + $Text) }
function Write-TIPEOk { param([string]$Text) Write-Host ('    OK: ' + $Text) -ForegroundColor Green }
function Write-TIPEWarn {
    param([string]$Text)
    [void]$script:State.Warnings.Add($Text)
    Write-Host ('    ATENÇÃO: ' + $Text) -ForegroundColor Yellow
}
function Add-TIPESummary { param([string]$Label, [string]$Value) [void]$script:State.Summary.Add(('{0,-16}{1}' -f ($Label + ':'), $Value)) }
function Stop-TIPECancel { param([string]$Text) throw (New-Object System.OperationCanceledException $Text) }

# --- Programas externos ------------------------------------------------------
# Roda um programa, repassa a saída para a tela (e para o log do Start-Transcript) e devolve o código.
# A saída de erro vem junto (2>&1) com $ErrorActionPreference local em Continue: no 5.1, com Stop,
# a primeira linha de erro de um programa externo viraria exceção.
function Invoke-TIPETool {
    param([string]$FilePath, [string[]]$Arguments = @(), [switch]$Quiet)
    $ErrorActionPreference = 'Continue'
    $lines = New-Object System.Collections.ArrayList
    $global:LASTEXITCODE = -1
    $argList = @($Arguments | Where-Object { $null -ne $_ -and [string]$_ -ne '' })
    & $FilePath @argList 2>&1 | ForEach-Object {
        $s = ''
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $s = [string]$_.Exception.Message } else { $s = [string]$_ }
        # barra de progresso redesenhada com CR: fica só o último pedaço
        if ($s.IndexOf([char]13) -ge 0) {
            $segs = @($s.Split([char]13) | Where-Object { $_.Trim() })
            if ($segs.Count) { $s = $segs[$segs.Count - 1] } else { $s = '' }
        }
        $s = $s.TrimEnd()
        if ($s.Trim() -and -not (Test-TIPEProgressLine $s)) {
            [void]$lines.Add($s)
            if (-not $Quiet) { Write-Host ('      ' + $s.Trim()) -ForegroundColor DarkGray }
        }
    }
    return [pscustomobject]@{ ExitCode = [int]$global:LASTEXITCODE; Output = @($lines) }
}

# DISM do ADK para tudo (montar, pacotes, idioma, drivers, salvar): o DISM do Windows que cria o pendrive
# pode ser mais velho que o Windows PE do ADK, e a Microsoft manda usar o do ADK nesse caso.
function Invoke-TIPEDism {
    param([string[]]$Arguments, [string]$What, [switch]$Optional)
    $r = Invoke-TIPETool -FilePath $script:State.Dism -Arguments $Arguments
    if ($r.ExitCode -eq 0 -or $r.ExitCode -eq 3010) { return $true }
    $msg = '{0}: o DISM terminou com o código {1} (detalhes acima e em {2}).' -f $What, $r.ExitCode, (Join-Path $env:windir 'Logs\DISM\dism.log')
    if ($Optional) { Write-TIPEWarn $msg; return $false }
    throw $msg
}

# Comandos do ADK (copype, MakeWinPEMedia) num .cmd temporário, depois do DandISetEnv.bat: usa a lógica
# da própria Microsoft sem brigar com as aspas do "cmd /c".
function Invoke-TIPEAdkCommand {
    param([string]$Command, [string]$Name)
    $bat = Join-Path $script:State.WorkRoot ($Name + '.cmd')
    $lines = @('@echo off', ('call "{0}" >nul 2>&1' -f $script:State.Adk.SetEnv), $Command, 'exit /b %errorlevel%')
    [System.IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
    # "call" logo depois do /c: o cmd não mexe nas aspas do caminho (com parênteses no %TEMP%, mexeria)
    $r = Invoke-TIPETool -FilePath $env:ComSpec -Arguments @('/d', '/c', 'call', $bat)
    return $r.ExitCode
}

# robocopy com o código interpretado. Origem/destino sem barra no fim (a barra antes da aspa confunde o
# robocopy), menos a raiz de uma unidade ('E:\'), que não tem espaço e vai sem aspas.
function Invoke-TIPERobocopy {
    param([string]$Source, [string]$Destination, [string[]]$Extra = @())
    $fix = {
        param($p)
        $p = [string]$p
        if ($p -match '^[A-Za-z]:\\?$') { return ($p.Substring(0, 2) + '\') }
        return $p.TrimEnd('\')
    }
    $args0 = @((& $fix $Source), (& $fix $Destination), '/E', '/R:1', '/W:1', '/NP', '/NFL', '/NDL') + @($Extra)
    $r = Invoke-TIPETool -FilePath $script:Robocopy -Arguments $args0 -Quiet
    if (-not (Test-TIPERobocopyOk $r.ExitCode)) {
        foreach ($l in @($r.Output | Select-Object -Last 12)) { Write-Host ('      ' + $l.Trim()) -ForegroundColor DarkGray }
    }
    return $r.ExitCode
}

function Get-TIPEFolderStats {
    param([string]$Path)
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
    $sum = [double]0
    foreach ($f in $files) { $sum += [double]$f.Length }
    return [pscustomobject]@{ Bytes = $sum; Files = $files.Count }
}

function Get-TIPEFreeBytes {
    param([string]$Path)
    try {
        $q = (New-Object System.IO.DriveInfo(([System.IO.Path]::GetPathRoot($Path))))
        return [double]$q.AvailableFreeSpace
    } catch { return [double]-1 }
}

function Remove-TIPEFolder {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $true }
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop } catch { }
    if (Test-Path -LiteralPath $Path) {
        # Remove-Item do 5.1 às vezes falha em árvores grandes; o rd do cmd resolve
        Invoke-TIPETool -FilePath $env:ComSpec -Arguments @('/d', '/c', 'rd', '/s', '/q', $Path) -Quiet | Out-Null
    }
    return (-not (Test-Path -LiteralPath $Path))
}

# --- Ambiente ----------------------------------------------------------------
function Test-TIPEAdmin {
    try {
        $p = New-Object System.Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-TIPEAppVersion {
    try {
        $t = Get-Content -Raw -LiteralPath (Join-Path $script:Root 'src\Core\01-Theme.ps1') -Encoding UTF8
        if ($t -match "TI\.Version\s*=\s*'([^']+)'") { return $Matches[1] }
    } catch { }
    return '0.0.0'
}

function Find-TIPEAdk {
    $roots = New-Object System.Collections.ArrayList
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots')) {
        try {
            $v = [string](Get-ItemProperty -LiteralPath $key -Name 'KitsRoot10' -ErrorAction Stop).KitsRoot10
            if ($v -and -not ($roots -contains $v)) { [void]$roots.Add($v) }
        } catch { }
    }
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($pf86) {
        $def = Join-Path $pf86 'Windows Kits\10\'
        if (-not ($roots -contains $def)) { [void]$roots.Add($def) }
    }
    foreach ($r in $roots) {
        $lay = Get-TIPEAdkLayout -KitsRoot $r
        if (Test-Path -LiteralPath $lay.SetEnv) { return $lay }
    }
    if ($roots.Count -gt 0) { return (Get-TIPEAdkLayout -KitsRoot $roots[0]) }
    return $null
}

function Assert-TIPEAdk {
    param($Adk)
    $missAdk = New-Object System.Collections.ArrayList
    $missPe = New-Object System.Collections.ArrayList
    if (-not $Adk) {
        [void]$missAdk.Add('Windows ADK (nenhuma instalação encontrada)')
    } else {
        foreach ($p in @($Adk.SetEnv, $Adk.Dism, $Adk.Bootsect, (Join-Path $Adk.Oscdimg 'oscdimg.exe'))) {
            if (-not (Test-Path -LiteralPath $p)) { [void]$missAdk.Add($p) }
        }
        foreach ($p in @($Adk.CopyPE, $Adk.MakeMedia, $Adk.WinpeWim, $Adk.Media, $Adk.OCs)) {
            if (-not (Test-Path -LiteralPath $p)) { [void]$missPe.Add($p) }
        }
    }
    if ($missAdk.Count -eq 0 -and $missPe.Count -eq 0) { return }
    Write-Host ''
    if ($missAdk.Count) {
        Write-Host '    Falta o Windows ADK (Ferramentas de Implantação):' -ForegroundColor Red
        foreach ($m in $missAdk) { Write-Host ('      ' + $m) -ForegroundColor DarkGray }
    }
    if ($missPe.Count) {
        Write-Host '    Falta o complemento Windows PE do ADK:' -ForegroundColor Red
        foreach ($m in $missPe) { Write-Host ('      ' + $m) -ForegroundColor DarkGray }
    }
    Write-Host ''
    Write-Host '    Baixe na página oficial da Microsoft "Baixar e instalar o Windows ADK":' -ForegroundColor Yellow
    Write-Host '      https://learn.microsoft.com/pt-br/windows-hardware/get-started/adk-install' -ForegroundColor Yellow
    Write-Host '    1. Instale o "Windows ADK" e marque "Ferramentas de Implantação" (Deployment Tools).' -ForegroundColor Yellow
    Write-Host '    2. Instale o "Complemento do Windows PE para o Windows ADK" (Windows PE add-on), da mesma versão.' -ForegroundColor Yellow
    Write-Host '    Use a versão mais nova da página: ela cria o pendrive também a partir do Windows 10.' -ForegroundColor Yellow
    throw 'Instale o Windows ADK e o complemento Windows PE e rode de novo.'
}

# Informações dos discos para o Get-TIPEDiskCandidates
function Get-TIPEDiskOfPath {
    param([string]$Path)
    if ([string]$Path -notmatch '^([A-Za-z]):') { return $null }
    try { return [int](@(Get-Partition -DriveLetter $Matches[1] -ErrorAction Stop)[0].DiskNumber) } catch { return $null }
}

function Get-TIPEDiskInfo {
    $media = @{}
    try { foreach ($w in @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop)) { $media[[int]$w.Index] = [string]$w.MediaType } } catch { }
    $sysNum = Get-TIPEDiskOfPath $env:SystemDrive
    $projNum = Get-TIPEDiskOfPath $script:Root
    $tempNum = Get-TIPEDiskOfPath $env:TEMP
    foreach ($d in @(Get-Disk -ErrorAction Stop)) {
        $n = [int]$d.Number
        [pscustomobject]@{
            Number            = $n
            FriendlyName      = [string]$d.FriendlyName
            Size              = [double]$d.Size
            BusType           = $d.BusType
            MediaType         = $media[$n]
            IsBoot            = [bool]$d.IsBoot
            IsSystem          = [bool]$d.IsSystem
            IsReadOnly        = [bool]$d.IsReadOnly
            HasRunningWindows = ($null -ne $sysNum -and $n -eq $sysNum)
            HasProject        = (($null -ne $projNum -and $n -eq $projNum) -or ($null -ne $tempNum -and $n -eq $tempNum))
            UniqueId          = [string]$d.UniqueId
        }
    }
}

function Get-TIPEUsedLetters {
    $used = New-Object System.Collections.ArrayList
    try { foreach ($d in [System.IO.DriveInfo]::GetDrives()) { [void]$used.Add($d.Name.Substring(0, 1)) } } catch { }
    try { foreach ($v in @(Get-Volume -ErrorAction Stop)) { if ($v.DriveLetter) { [void]$used.Add([string]$v.DriveLetter) } } } catch { }
    # unidades de rede mapeadas na sessão do usuário (a sessão elevada não as enxerga)
    try { foreach ($k in @(Get-ChildItem -LiteralPath 'HKCU:\Network' -ErrorAction Stop)) { [void]$used.Add([string]$k.PSChildName) } } catch { }
    return @($used)
}

function Get-TIPEDiskLetters {
    param([int]$DiskNumber)
    return @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
        Where-Object { [string]$_.DriveLetter -match '^[A-Za-z]$' } | ForEach-Object { [string]$_.DriveLetter })
}

# Pastas do TI Suite (TI-Suite.ps1 + portable.config) nas partições do disco: raiz e até 2 níveis abaixo
function Find-TIPEAppFolders {
    param([int]$DiskNumber)
    $found = New-Object System.Collections.ArrayList
    foreach ($l in (Get-TIPEDiskLetters -DiskNumber $DiskNumber)) {
        $root = '{0}:\' -f $l
        $dirs = New-Object System.Collections.ArrayList
        [void]$dirs.Add($root)
        foreach ($d1 in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -notmatch '^(\$|System Volume Information$)' })) {
            [void]$dirs.Add($d1.FullName)
            foreach ($d2 in @(Get-ChildItem -LiteralPath $d1.FullName -Directory -Force -ErrorAction SilentlyContinue)) { [void]$dirs.Add($d2.FullName) }
        }
        foreach ($d in $dirs) {
            if ((Test-Path -LiteralPath (Join-Path $d 'TI-Suite.ps1')) -and (Test-Path -LiteralPath (Join-Path $d 'portable.config'))) { [void]$found.Add($d) }
        }
    }
    return @($found)
}

function Get-TIPEFieldDataStats {
    param([string[]]$Folders)
    $items = Get-TIPEFieldItems
    $sum = [double]0
    foreach ($f in @($Folders)) {
        foreach ($d in $items.Dirs) {
            $p = Join-Path $f $d
            if (Test-Path -LiteralPath $p -PathType Container) { $sum += (Get-TIPEFolderStats $p).Bytes }
        }
        foreach ($x in $items.Files) {
            $p = Join-Path $f $x
            if (Test-Path -LiteralPath $p -PathType Leaf) { $sum += [double](Get-Item -LiteralPath $p -Force).Length }
        }
    }
    return $sum
}

# --- Escolha e confirmação do pendrive -----------------------------------------
function Show-TIPEDiskList {
    param([object[]]$All)
    $ok = @($All | Where-Object { $_.Eligible })
    $other = @($All | Where-Object { -not $_.Eligible -and $_.Removable })
    Write-Host ''
    if ($ok.Count) {
        Write-Host '    Pendrives que podem ser usados:'
        foreach ($c in $ok) { Write-Host ('      Disco {0,-3} {1,-42} {2,10}   ({3})' -f $c.Number, $c.Name, $c.SizeText, $c.BusType) -ForegroundColor White }
    }
    foreach ($c in $other) { Write-Host ('      Disco {0,-3} {1,-42} {2,10}   fora da lista: {3}' -f $c.Number, $c.Name, $c.SizeText, $c.Reason) -ForegroundColor DarkGray }
}

function Select-TIPEDisk {
    param([int]$Wanted)
    $all = @(Get-TIPEDiskCandidates -Disks @(Get-TIPEDiskInfo))
    $ok = @($all | Where-Object { $_.Eligible })
    Show-TIPEDiskList -All $all
    if (-not $ok.Count) { throw 'Nenhum pendrive USB de 8 GB ou mais foi encontrado. Conecte o pendrive e rode de novo.' }
    if ($Wanted -ge 0) {
        $sel = @($ok | Where-Object { $_.Number -eq $Wanted })
        if ($sel.Count) { Write-TIPEInfo ('Disco {0} escolhido pela opção -Disco.' -f $Wanted); return $sel[0] }
        $why = @($all | Where-Object { $_.Number -eq $Wanted })
        if ($why.Count) { throw ('O disco {0} não pode ser usado: {1}.' -f $Wanted, $why[0].Reason) }
        throw ('O disco {0} não existe. Rode sem -Disco para ver a lista.' -f $Wanted)
    }
    while ($true) {
        Write-Host ''
        $ans = [string](Read-Host '    Digite o número do disco do pendrive (Enter vazio cancela)')
        if (-not $ans.Trim()) { Stop-TIPECancel 'Cancelado: nenhum disco escolhido. Nada foi apagado.' }
        $n = 0
        if ([int]::TryParse($ans.Trim(), [ref]$n)) {
            $sel = @($ok | Where-Object { $_.Number -eq $n })
            if ($sel.Count) { return $sel[0] }
        }
        Write-Host '    Número inválido: escolha um dos discos da lista acima.' -ForegroundColor Yellow
    }
}

function Confirm-TIPEErase {
    param($Disk, [string[]]$AppFolders)
    Write-Host ''
    Write-Host ('    Disco {0}: {1} ({2})' -f $Disk.Number, $Disk.Name, $Disk.SizeText) -ForegroundColor White
    foreach ($p in @(Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue)) {
        $desc = 'partição {0}: {1}' -f $p.PartitionNumber, (Format-TIPESize ([double]$p.Size))
        if ([string]$p.DriveLetter -match '^[A-Za-z]$') {
            $v = $null
            try { $v = Get-Volume -DriveLetter $p.DriveLetter -ErrorAction Stop } catch { }
            $desc += '  {0}:  "{1}"  {2}' -f $p.DriveLetter, $(if ($v) { $v.FileSystemLabel } else { '' }), $(if ($v) { $v.FileSystem } else { '' })
        }
        Write-Host ('      ' + $desc)
    }
    Write-Host ''
    Write-Host '    TUDO neste pendrive será apagado (todas as partições e arquivos).' -ForegroundColor Red
    if (@($AppFolders).Count) {
        Write-Host '    Dados de campo do TI Suite encontrados (serão guardados e devolvidos no fim):' -ForegroundColor Yellow
        foreach ($a in $AppFolders) { Write-Host ('      ' + $a) -ForegroundColor Yellow }
        Write-Host '    Outros arquivos do pendrive NÃO são guardados: copie antes o que precisar.' -ForegroundColor Yellow
    }
    Write-Host ''
    $ans = Read-Host '    Para confirmar, digite APAGAR (qualquer outra coisa cancela)'
    if (-not (Test-TIPEConfirmWord $ans)) { Stop-TIPECancel 'Cancelado: nada foi apagado.' }
}

# O disco ainda é o mesmo que foi confirmado? (montar o Windows PE demora: dá tempo de trocar o pendrive)
function Assert-TIPESameDisk {
    param($Disk)
    $now = @(Get-TIPEDiskCandidates -Disks @(Get-TIPEDiskInfo | Where-Object { $_.Number -eq $Disk.Number }))
    if (-not $now.Count) { throw ('O pendrive (disco {0}) não está mais conectado. Nada foi apagado.' -f $Disk.Number) }
    $n = $now[0]
    if (-not $n.Eligible -or $n.UniqueId -ne $Disk.UniqueId -or $n.Size -ne $Disk.Size) {
        throw ('O disco {0} mudou desde a confirmação (outro pendrive conectado?). Nada foi apagado; rode de novo.' -f $Disk.Number)
    }
}

# --- Controles visuais (DLL) ----------------------------------------------------
# Igual ao Build-Release, mas num processo separado: o Add-Type deixa a DLL presa no processo que compilou,
# e a pasta de trabalho precisa ser apagada no fim.
function Build-TIPEControlsDll {
    param([string]$OutDir)
    $cs = Join-Path $script:Root 'src\Core\Controls.cs'
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    $dll = Join-Path $OutDir 'TISuite.Controls.dll'
    $stamp = Join-Path $OutDir 'TISuite.Controls.stamp'
    $code = "`$ErrorActionPreference = 'Stop'`n" +
            ("`$src = Get-Content -LiteralPath {0} -Raw -Encoding UTF8`n" -f (ConvertTo-TIPEQuoted $cs)) +
            ("Add-Type -TypeDefinition `$src -ReferencedAssemblies System.dll, System.Drawing.dll, System.Windows.Forms.dll -OutputAssembly {0} -OutputType Library`n" -f (ConvertTo-TIPEQuoted $dll)) +
            ("(Get-FileHash -LiteralPath {0} -Algorithm SHA256).Hash | Set-Content -LiteralPath {1} -Encoding ASCII`n" -f (ConvertTo-TIPEQuoted $cs), (ConvertTo-TIPEQuoted $stamp))
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($code))
    $r = Invoke-TIPETool -FilePath $script:PS51 -Arguments @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc)
    if ($r.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $dll) -or -not (Test-Path -LiteralPath $stamp)) {
        throw ('Não consegui compilar bin\TISuite.Controls.dll (código {0}). Rode o dev\Build-Release.ps1 para ver o erro de compilação.' -f $r.ExitCode)
    }
    Write-TIPEOk 'bin\TISuite.Controls.dll e o carimbo compilados.'
}

# --- Windows PE ---------------------------------------------------------------
function Dismount-TIPEHive {
    $key = $script:State.HiveKey
    if (-not $key) { return }
    for ($i = 1; $i -le 3; $i++) {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        $r = Invoke-TIPETool -FilePath $script:Reg -Arguments @('unload', $key) -Quiet
        if ($r.ExitCode -eq 0) { $script:State.HiveKey = $null; return }
        Start-Sleep -Seconds 2
    }
    Write-TIPEWarn ('Não consegui descarregar o registro {0}. Rode "reg unload {0}" como administrador.' -f $key)
}

function Dismount-TIPEImageDiscard {
    if (-not $script:State.Mounted -or -not $script:State.MountDir) { return }
    Dismount-TIPEHive
    Write-TIPEInfo 'Desmontando a imagem do Windows PE sem salvar...'
    $r = Invoke-TIPETool -FilePath $script:State.Dism -Arguments @('/Unmount-Image', ('/MountDir:' + $script:State.MountDir), '/Discard')
    if ($r.ExitCode -ne 0) {
        Invoke-TIPETool -FilePath $script:State.Dism -Arguments @('/Cleanup-Mountpoints') -Quiet | Out-Null
        Write-TIPEWarn ('Não consegui desmontar a imagem em {0}. Reinicie o PC e rode "dism /Cleanup-Mountpoints" como administrador.' -f $script:State.MountDir)
        return
    }
    $script:State.Mounted = $false
}

# Pastas TI-PE-<guid> de execuções interrompidas (imagem montada, registro carregado)
function Clear-TIPELeftovers {
    param([string]$Base)
    foreach ($k in @(Get-ChildItem -LiteralPath 'HKLM:\' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'TI_PE_*' })) {
        Invoke-TIPETool -FilePath $script:Reg -Arguments @('unload', ('HKLM\' + $k.PSChildName)) -Quiet | Out-Null
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $Base -Directory -Filter 'TI-PE-*' -ErrorAction SilentlyContinue)) {
        if ($d.Name -match '^TI-PE-dados-') {
            Write-TIPEWarn ('Há dados de campo guardados por uma execução anterior em {0}. Confira se já estão no pendrive antes de apagar a pasta.' -f $d.FullName)
            continue
        }
        if ($d.Name -notmatch '^TI-PE-[0-9a-f]{32}$') { continue }
        $m = Join-Path $d.FullName 'pe\mount'
        if (Test-Path -LiteralPath (Join-Path $m 'Windows')) {
            Write-TIPEInfo ('Desmontando uma imagem esquecida por uma execução anterior: {0}' -f $m)
            $r = Invoke-TIPETool -FilePath $script:State.Dism -Arguments @('/Unmount-Image', ('/MountDir:' + $m), '/Discard') -Quiet
            if ($r.ExitCode -ne 0) {
                Invoke-TIPETool -FilePath $script:State.Dism -Arguments @('/Cleanup-Mountpoints') -Quiet | Out-Null
                Write-TIPEWarn ('A imagem em {0} continua montada; reinicie o PC para liberar a pasta.' -f $m)
                continue
            }
        }
        [void](Remove-TIPEFolder $d.FullName)
    }
}

# Pasta de trabalho do copype: media\ (com sources\boot.wim), mount\ e fwfiles\
function New-TIPEWorkTree {
    param([string]$PeDir)
    $adk = $script:State.Adk
    Write-TIPEInfo 'Copiando os arquivos base do Windows PE (copype)...'
    $code = Invoke-TIPEAdkCommand -Name 'copype' -Command ('call copype amd64 "{0}" 2>&1' -f $PeDir)
    $wim = Join-Path $PeDir 'media\sources\boot.wim'
    if ($code -eq 0 -and (Test-Path -LiteralPath $wim)) { return $wim }
    Write-TIPEWarn ('O copype não terminou bem (código {0}); montando a pasta de trabalho do jeito manual.' -f $code)
    if (Test-Path -LiteralPath $PeDir) { [void](Remove-TIPEFolder $PeDir) }
    New-Item -ItemType Directory -Path (Join-Path $PeDir 'mount') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $PeDir 'fwfiles') -Force | Out-Null
    $rc = Invoke-TIPERobocopy -Source $adk.Media -Destination (Join-Path $PeDir 'media')
    if (-not (Test-TIPERobocopyOk $rc)) { throw ('Não consegui copiar {0} (robocopy {1}).' -f $adk.Media, $rc) }
    New-Item -ItemType Directory -Path (Join-Path $PeDir 'media\sources') -Force | Out-Null
    Copy-Item -LiteralPath $adk.WinpeWim -Destination $wim -Force
    foreach ($f in @(Get-ChildItem -LiteralPath $adk.Oscdimg -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'efisys*.bin' -or $_.Name -eq 'etfsboot.com' })) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $PeDir 'fwfiles') -Force
    }
    if (-not (Test-Path -LiteralPath $wim)) { throw 'Não consegui preparar o boot.wim do Windows PE.' }
    return $wim
}

# Fontes do app (Segoe UI, Segoe MDL2 Assets, Consolas) que faltam no Windows PE: copia do Windows deste
# PC e registra no hive SOFTWARE da imagem (reg load/unload; sempre descarregado no finally).
function Add-TIPEFonts {
    param([string]$MountDir)
    $srcDir = Join-Path $env:windir 'Fonts'
    $dstDir = Join-Path $MountDir 'Windows\Fonts'
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    $want = @(foreach ($pat in @('segoeui*.ttf', 'segmdl2.ttf', 'consola*.ttf')) {
        Get-ChildItem -LiteralPath $srcDir -Filter $pat -File -ErrorAction SilentlyContinue
    })
    $toAdd = @($want | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dstDir $_.Name)) })
    if (-not $want.Count) { Write-TIPEWarn 'Não achei Segoe UI, Segoe MDL2 Assets nem Consolas neste Windows: o Windows PE fica com as fontes dele.'; return 0 }
    if (-not $toAdd.Count) { Write-TIPEInfo 'Fontes: o Windows PE já tem todas.'; return 0 }
    $hostFonts = @{}
    try {
        $hk = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction Stop
        foreach ($n in $hk.GetValueNames()) { $hostFonts[$n] = [string]$hk.GetValue($n) }
        $hk.Close()
    } catch { }
    foreach ($f in $toAdd) { Copy-Item -LiteralPath $f.FullName -Destination $dstDir -Force }
    $key = 'HKLM\TI_PE_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $hive = Join-Path $MountDir 'Windows\System32\config\SOFTWARE'
    $r = Invoke-TIPETool -FilePath $script:Reg -Arguments @('load', $key, $hive) -Quiet
    if ($r.ExitCode -ne 0) { throw ('Não consegui abrir o registro da imagem ({0}).' -f (@($r.Output) -join ' ')) }
    $script:State.HiveKey = $key
    $bad = 0
    try {
        foreach ($f in $toAdd) {
            $name = Get-TIPEFontValueName -FileName $f.Name -HostFonts $hostFonts
            $r = Invoke-TIPETool -FilePath $script:Reg -Quiet -Arguments @('add', ($key + '\Microsoft\Windows NT\CurrentVersion\Fonts'), '/v', $name, '/t', 'REG_SZ', '/d', $f.Name, '/f')
            if ($r.ExitCode -ne 0) { $bad++ }
        }
    } finally {
        Dismount-TIPEHive
    }
    if ($bad) { Write-TIPEWarn ('{0} fonte(s) copiada(s) mas não registrada(s) no Windows PE.' -f $bad) }
    Write-TIPEOk ('{0} fonte(s) adicionada(s): {1}' -f $toAdd.Count, (($toAdd | ForEach-Object { $_.Name }) -join ', '))
    return $toAdd.Count
}

function New-TIPEImage {
    param([string]$PeDir, [string]$DriversDir)
    $adk = $script:State.Adk
    $wim = New-TIPEWorkTree -PeDir $PeDir
    try { (Get-Item -LiteralPath $wim).IsReadOnly = $false } catch { }
    $mount = Join-Path $PeDir 'mount'
    New-Item -ItemType Directory -Path $mount -Force | Out-Null

    # Pacotes disponíveis: raiz do WinPE_OCs, en-us e pt-br
    $avail = New-Object System.Collections.ArrayList
    foreach ($sub in @('', 'en-us', 'pt-br')) {
        $dir = $adk.OCs
        if ($sub) { $dir = Join-Path $adk.OCs $sub }
        foreach ($c in @(Get-ChildItem -LiteralPath $dir -Filter '*.cab' -File -ErrorAction SilentlyContinue)) {
            if ($sub) { [void]$avail.Add($sub + '\' + $c.Name) } else { [void]$avail.Add($c.Name) }
        }
    }
    $plan = Get-TIPEPackagePlan -Available @($avail)
    if ($plan.Missing.Count) {
        throw ('Faltam componentes no complemento Windows PE: {0}. Reinstale o "Complemento do Windows PE para o Windows ADK".' -f ($plan.Missing -join ', '))
    }
    if (-not $plan.LanguagePack) { Write-TIPEWarn 'Sem o pacote de idioma pt-br do Windows PE: as mensagens do próprio Windows PE ficam em inglês (o TI Suite continua em português).' }

    Write-TIPEInfo 'Abrindo (montando) o boot.wim...'
    $script:State.MountDir = $mount
    try {
        Invoke-TIPEDism -What 'Montar o boot.wim' -Arguments @('/Mount-Image', ('/ImageFile:' + $wim), '/Index:1', ('/MountDir:' + $mount)) | Out-Null
    } catch {
        # montagem pela metade: descarta em silêncio para a pasta de trabalho poder ser apagada
        Invoke-TIPETool -FilePath $script:State.Dism -Arguments @('/Unmount-Image', ('/MountDir:' + $mount), '/Discard') -Quiet | Out-Null
        throw
    }
    $script:State.Mounted = $true
    $saved = $false
    try {
        $n = 0
        foreach ($p in $plan.Packages) {
            $n++
            Write-TIPEInfo ('Pacote {0} de {1}: {2}' -f $n, $plan.Packages.Count, $p)
            Invoke-TIPEDism -What ('Adicionar ' + $p) -Arguments @(('/Image:' + $mount), '/Add-Package', ('/PackagePath:' + (Join-Path $adk.OCs $p))) | Out-Null
        }
        Add-TIPESummary 'Componentes' ((@($plan.Packages | Where-Object { $_ -notmatch '\\' }) -replace '\.cab$', '') -join ', ')

        Write-TIPEInfo 'Idioma pt-BR, teclado ABNT2, fuso de Brasília e espaço de rascunho...'
        $intlOk = $false
        if ($plan.LanguagePack) { $intlOk = Invoke-TIPEDism -Optional -What 'Idioma pt-BR' -Arguments @(('/Image:' + $mount), '/Set-AllIntl:pt-BR') }
        if (-not $intlOk) { Invoke-TIPEDism -Optional -What 'Formatos pt-BR' -Arguments @(('/Image:' + $mount), '/Set-SysLocale:pt-BR', '/Set-UserLocale:pt-BR') | Out-Null }
        Invoke-TIPEDism -Optional -What 'Teclado ABNT2' -Arguments @(('/Image:' + $mount), '/Set-InputLocale:0416:00010416') | Out-Null
        Invoke-TIPEDism -Optional -What 'Fuso de Brasília' -Arguments @(('/Image:' + $mount), '/Set-TimeZone:E. South America Standard Time') | Out-Null
        Invoke-TIPEDism -Optional -What 'Espaço de rascunho' -Arguments @(('/Image:' + $mount), '/Set-ScratchSpace:512') | Out-Null

        if ($DriversDir) {
            $infs = @(Get-ChildItem -LiteralPath $DriversDir -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)
            Write-TIPEInfo ('Drivers: {0} arquivo(s) .inf em {1}' -f $infs.Count, $DriversDir)
            $drvOk = Invoke-TIPEDism -Optional -What 'Adicionar drivers' -Arguments @(('/Image:' + $mount), '/Add-Driver', ('/Driver:' + $DriversDir), '/Recurse')
            if ($drvOk) { Add-TIPESummary 'Drivers' ('{0} .inf de {1}' -f $infs.Count, $DriversDir) }
            else { Add-TIPESummary 'Drivers' ('com falhas ({0}); confira se são x64 e assinados' -f $DriversDir) }
        }

        Write-TIPEInfo 'Fontes do TI Suite...'
        $nf = Add-TIPEFonts -MountDir $mount
        Add-TIPESummary 'Fontes' ('{0} adicionada(s) ao Windows PE' -f $nf)

        Write-TIPEInfo 'Gravando o startnet.cmd (abre o TI Suite em modo recuperação)...'
        $sn = Join-Path $mount 'Windows\System32\startnet.cmd'
        [System.IO.File]::WriteAllText($sn, (((New-TIPEStartnet) -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)

        Write-TIPEInfo 'Limpando componentes substituídos (deixa o boot.wim menor)...'
        Invoke-TIPEDism -Optional -What 'Limpar componentes' -Arguments @(('/Image:' + $mount), '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase') | Out-Null

        Write-TIPEInfo 'Salvando e desmontando o boot.wim...'
        Invoke-TIPEDism -What 'Salvar o boot.wim' -Arguments @('/Unmount-Image', ('/MountDir:' + $mount), '/Commit') | Out-Null
        $saved = $true
        $script:State.Mounted = $false
    } finally {
        if (-not $saved) { Dismount-TIPEImageDiscard }
    }

    # Exportar recria o .wim sem as sobras das mudanças (opcional: se falhar, fica o original)
    Write-TIPEInfo 'Encolhendo o boot.wim (exportar)...'
    $tmp = Join-Path $PeDir 'boot-export.wim'
    if (Invoke-TIPEDism -Optional -What 'Exportar o boot.wim' -Arguments @('/Export-Image', ('/SourceImageFile:' + $wim), '/SourceIndex:1', ('/DestinationImageFile:' + $tmp))) {
        Remove-Item -LiteralPath $wim -Force
        Move-Item -LiteralPath $tmp -Destination $wim
    }
    Write-TIPEOk ('Windows PE pronto: boot.wim com {0}.' -f (Format-TIPESize ([double](Get-Item -LiteralPath $wim).Length)))
}

# MakeWinPEMedia /ISO [/bootex]: a Microsoft monta a mídia (boot BIOS + UEFI, ou os arquivos da CA 2023)
function New-TIPEIso {
    param([string]$PeDir, [string]$IsoPath, [bool]$Use2023)
    $adk = $script:State.Adk
    # Sem o "Press any key to boot from CD or DVD" (só faz diferença no ISO da máquina virtual)
    $fw = Join-Path $PeDir 'fwfiles'
    foreach ($pair in @(@('efisys_noprompt.bin', 'efisys.bin'), @('efisys_noprompt_EX.bin', 'efisys_EX.bin'))) {
        $src = Join-Path $adk.Oscdimg $pair[0]
        $dst = Join-Path $fw $pair[1]
        if ((Test-Path -LiteralPath $src) -and (Test-Path -LiteralPath $dst)) { Copy-Item -LiteralPath $src -Destination $dst -Force }
    }
    $flags = '/ISO /F'
    if ($Use2023) { $flags += ' /bootex' }
    $code = Invoke-TIPEAdkCommand -Name 'makemedia' -Command ('call MakeWinPEMedia {0} "{1}" "{2}" 2>&1' -f $flags, $PeDir, $IsoPath)
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $IsoPath) -or (Get-Item -LiteralPath $IsoPath).Length -lt 50MB) {
        throw ('O MakeWinPEMedia não gerou o ISO (código {0}).' -f $code)
    }
    Write-TIPEOk ('ISO gerado: {0}' -f (Format-TIPESize ([double](Get-Item -LiteralPath $IsoPath).Length)))
}

function Dismount-TIPEIso {
    if ($script:State.IsoTempLetter) {
        Invoke-TIPETool -FilePath $script:Mountvol -Arguments @(('{0}:' -f $script:State.IsoTempLetter), '/D') -Quiet | Out-Null
        $script:State.IsoTempLetter = $null
    }
    if ($script:State.IsoPath) {
        try { Dismount-DiskImage -ImagePath $script:State.IsoPath -ErrorAction Stop | Out-Null } catch { Write-TIPEWarn ('Não consegui desmontar o ISO {0}.' -f $script:State.IsoPath) }
        $script:State.IsoPath = $null
    }
}

# Copia o conteúdo do ISO para a partição TI-BOOT
function Copy-TIPEIsoToBoot {
    param([string]$IsoPath, [string]$BootLetter)
    Mount-DiskImage -ImagePath $IsoPath -StorageType ISO -ErrorAction Stop | Out-Null
    $script:State.IsoPath = $IsoPath
    try {
        $src = $null
        $vol = $null
        for ($i = 0; $i -lt 30 -and -not $src; $i++) {
            try { $vol = Get-DiskImage -ImagePath $IsoPath -ErrorAction Stop | Get-Volume -ErrorAction Stop } catch { $vol = $null }
            if ($vol -and [string]$vol.DriveLetter -match '^[A-Za-z]$') { $src = '{0}:\' -f $vol.DriveLetter } else { Start-Sleep -Milliseconds 500 }
        }
        if (-not $src) {
            # Montagem automática de letras desligada: dá uma letra temporária com o mountvol
            if (-not $vol -or -not $vol.Path) { throw 'o ISO montado não apareceu como unidade' }
            $l = @(Get-TIPEFreeLetters -Used (Get-TIPEUsedLetters) -Count 1)
            if (-not $l.Count) { throw 'não há letra livre para o ISO' }
            $r = Invoke-TIPETool -FilePath $script:Mountvol -Arguments @(('{0}:' -f $l[0]), $vol.Path) -Quiet
            if ($r.ExitCode -ne 0) { throw 'o mountvol não deu letra ao ISO' }
            $script:State.IsoTempLetter = $l[0]
            $src = '{0}:\' -f $l[0]
        }
        Write-TIPEInfo ('Copiando o Windows PE do ISO ({0}) para TI-BOOT ({1}:)...' -f $src, $BootLetter)
        $rc = Invoke-TIPERobocopy -Source $src -Destination ('{0}:\' -f $BootLetter) -Extra @('/A-:R')
        if (-not (Test-TIPERobocopyOk $rc)) { throw ('o robocopy falhou (código {0})' -f $rc) }
    } finally {
        Dismount-TIPEIso
    }
}

# --- Pendrive -----------------------------------------------------------------
function Backup-TIPEFieldData {
    param([string[]]$Folders, [string]$Dest)
    $items = Get-TIPEFieldItems
    $plan = @(Get-TIPERestorePlan -Folders $Folders)
    $need = Get-TIPEFieldDataStats -Folders $Folders
    $free = Get-TIPEFreeBytes $Dest
    if ($free -ge 0 -and $free -lt ($need * 1.1 + 200MB)) {
        throw ('Não há espaço para guardar os dados de campo ({0}; livre: {1}). Nada foi apagado.' -f (Format-TIPESize $need), (Format-TIPESize $free))
    }
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    $script:State.DataBackup = $Dest
    $saved = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($p in $plan) {
        $slot = Join-Path $Dest ('{0:D2}' -f $i)
        New-Item -ItemType Directory -Path $slot -Force | Out-Null
        foreach ($d in $items.Dirs) {
            $src = Join-Path $p.Source $d
            if (-not (Test-Path -LiteralPath $src -PathType Container)) { continue }
            $dst = Join-Path $slot $d
            $rc = Invoke-TIPERobocopy -Source $src -Destination $dst -Extra @('/COPY:DAT', '/DCOPY:T', '/XJ')
            $a = Get-TIPEFolderStats $src
            $b = Get-TIPEFolderStats $dst
            if (-not (Test-TIPERobocopyOk $rc) -or $a.Files -ne $b.Files -or $a.Bytes -ne $b.Bytes) {
                throw ('Não consegui guardar {0} (robocopy {1}; {2} de {3} arquivos). Nada foi apagado.' -f $src, $rc, $b.Files, $a.Files)
            }
            Write-TIPEInfo ('Guardado: {0} ({1} arquivos, {2})' -f $src, $a.Files, (Format-TIPESize $a.Bytes))
        }
        foreach ($x in $items.Files) {
            $src = Join-Path $p.Source $x
            if (Test-Path -LiteralPath $src -PathType Leaf) {
                try { Copy-Item -LiteralPath $src -Destination (Join-Path $slot $x) -Force -ErrorAction Stop }
                catch { throw ('Não consegui guardar {0}: {1} Nada foi apagado.' -f $src, $_.Exception.Message) }
            }
        }
        [void]$saved.Add([pscustomobject]@{ Slot = $slot; Source = $p.Source; Target = $p.Target })
        $i++
    }
    return @($saved)
}

function Restore-TIPEFieldData {
    param([object[]]$Saved, [string]$DataRoot)
    $ok = $true
    foreach ($s in @($Saved)) {
        $target = $DataRoot
        if ($s.Target) { $target = Join-Path $DataRoot $s.Target }
        $rc = Invoke-TIPERobocopy -Source $s.Slot -Destination $target -Extra @('/COPY:DAT', '/DCOPY:T')
        if (Test-TIPERobocopyOk $rc) { Write-TIPEOk ('Dados de {0} devolvidos em {1}' -f $s.Source, $target) }
        else { $ok = $false; Write-TIPEWarn ('Não consegui devolver os dados de {0} (robocopy {1}).' -f $s.Source, $rc) }
    }
    return $ok
}

# Apaga e particiona com o diskpart (roteiro da Microsoft); confere o resultado com o Get-Partition
function Format-TIPEPendrive {
    param($Disk, [string]$FileSystem)
    Assert-TIPESameDisk -Disk $Disk
    $letters = @(Get-TIPEFreeLetters -Used (Get-TIPEUsedLetters) -Count 2)
    if ($letters.Count -lt 2) { throw 'Não há duas letras de unidade livres para as partições do pendrive.' }
    $bootL = $letters[0]; $dataL = $letters[1]
    $dpFile = Join-Path $script:State.WorkRoot 'diskpart.txt'
    $lines = Get-TIPEDiskpartScript -DiskNumber $Disk.Number -BootLetter $bootL -DataLetter $dataL -FileSystem $FileSystem
    [System.IO.File]::WriteAllText($dpFile, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
    $code = -1
    for ($try = 1; $try -le 2; $try++) {
        if ($try -gt 1) {
            Write-TIPEInfo 'Tentando de novo (alguns pendrives só aceitam o "clean" na segunda vez)...'
            try { Update-HostStorageCache -ErrorAction SilentlyContinue } catch { }
            Start-Sleep -Seconds 3
            Assert-TIPESameDisk -Disk $Disk
        }
        $script:State.Formatted = $true
        $r = Invoke-TIPETool -FilePath $script:Diskpart -Arguments @('/s', $dpFile)
        $code = $r.ExitCode
        if ($code -eq 0) { break }
    }
    if ($code -ne 0) {
        throw ('O diskpart não conseguiu preparar o pendrive (código {0}). Feche janelas e programas que estejam usando o pendrive, desconecte, conecte de novo e rode outra vez.' -f $code)
    }
    try { Update-HostStorageCache -ErrorAction SilentlyContinue } catch { }
    for ($i = 0; $i -lt 30; $i++) {
        if ((Test-Path -LiteralPath ('{0}:\' -f $bootL)) -and (Test-Path -LiteralPath ('{0}:\' -f $dataL))) { break }
        Start-Sleep -Seconds 1
    }
    $parts = @(Get-Partition -DiskNumber $Disk.Number -ErrorAction Stop | Sort-Object PartitionNumber)
    $style = ''
    try { $style = [string](Get-Disk -Number $Disk.Number -ErrorAction Stop).PartitionStyle } catch { }
    $vb = $null; $vd = $null
    try { $vb = Get-Volume -DriveLetter $bootL -ErrorAction Stop } catch { }
    try { $vd = Get-Volume -DriveLetter $dataL -ErrorAction Stop } catch { }
    $problems = @()
    if ($style -and $style -ne 'MBR' -and $style -ne '1') { $problems += ('tabela {0} em vez de MBR' -f $style) }
    if ($parts.Count -ne 2) { $problems += ('{0} partições em vez de 2' -f $parts.Count) }
    elseif (-not $parts[0].IsActive) { $problems += 'a partição TI-BOOT não ficou ativa' }
    if (-not $vb -or [string]$vb.FileSystem -ne 'FAT32') { $problems += ('TI-BOOT ({0}:) não está em FAT32' -f $bootL) }
    if (-not $vd -or [string]$vd.FileSystem -ne $FileSystem) { $problems += ('TI-SUITE ({0}:) não está em {1}' -f $dataL, $FileSystem) }
    if ($problems.Count) { throw ('O pendrive não ficou como esperado: {0}.' -f ($problems -join '; ')) }
    Write-TIPEOk ('TI-BOOT = {0}: (FAT32, {1});  TI-SUITE = {2}: ({3}, {4})' -f $bootL, (Format-TIPESize ([double]$vb.Size)), $dataL, $FileSystem, (Format-TIPESize ([double]$vd.Size)))
    return [pscustomobject]@{ Boot = $bootL; Data = $dataL }
}

# Copia o app (Test-TIPEAppExcluded decide o que fica de fora), a DLL recém-compilada e o portable.config
function Copy-TIPEApp {
    param([string]$Destination, [string]$DllDir, [switch]$Update)
    $files = @(Get-ChildItem -LiteralPath $script:Root -Recurse -File -Force -ErrorAction Stop | Where-Object {
        -not (Test-TIPEAppExcluded ($_.FullName.Substring($script:Root.Length).TrimStart('\', '/')))
    })
    if (-not @($files | Where-Object { $_.Name -eq 'TI-Suite.ps1' }).Count) { throw 'TI-Suite.ps1 não foi encontrado na pasta do projeto.' }
    if ($Update) {
        $script:State.UpdateStarted = $true
        # bin\ primeiro: DLL presa = TI Suite aberto a partir do pendrive (aí nada é apagado)
        foreach ($sub in @('bin', 'src')) {
            $old = Join-Path $Destination $sub
            if (Test-Path -LiteralPath $old) {
                try { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction Stop }
                catch { throw ('Não consegui trocar a pasta {0} (arquivo em uso). Feche o TI Suite aberto a partir do pendrive e rode de novo.' -f $old) }
            }
        }
        $man = Join-Path $Destination 'manifest.sha256'
        if (Test-Path -LiteralPath $man) {
            Remove-Item -LiteralPath $man -Force
            Write-TIPEInfo 'Removido o manifest.sha256 antigo (travaria o app depois da atualização).'
        }
    }
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($script:Root.Length).TrimStart('\', '/')
        $t = Join-Path $Destination $rel
        $dir = Split-Path -Parent $t
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $f.FullName -Destination $t -Force
    }
    $bin = Join-Path $Destination 'bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    foreach ($n in @('TISuite.Controls.dll', 'TISuite.Controls.stamp')) { Copy-Item -LiteralPath (Join-Path $DllDir $n) -Destination (Join-Path $bin $n) -Force }
    $pc = Join-Path $Destination 'portable.config'
    if (-not (Test-Path -LiteralPath $pc)) {
        [System.IO.File]::WriteAllText($pc, "# Modo portátil: ative colocando este arquivo ao lado do TI-Suite.ps1`r`n# Quando presente, config e logs ficam na própria pasta (rodar de USB)`r`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-TIPEOk ('{0} arquivos do app copiados para {1} (com bin\TISuite.Controls.dll).' -f ($files.Count + 2), $Destination)
}

# config.json padrão (o mesmo do Build-Release): nada da máquina de desenvolvimento vai para o pendrive
function Write-TIPEDefaultConfig {
    param([string]$Destination)
    $p = Join-Path $Destination 'config.json'
    if (Test-Path -LiteralPath $p) { return }
    $json = "{`r`n    ""CompactConsole"": true,`r`n    ""ConsoleHeight"": 0,`r`n    ""CrispText"": false,`r`n    ""ForceChangeOnLogon"": false,`r`n    ""WindowMaximized"": false`r`n}`r`n"
    [System.IO.File]::WriteAllText($p, $json, (New-Object System.Text.UTF8Encoding($true)))
}

function Write-TIPELeiaMe {
    param([string]$Destination, [string]$StampLine, [string]$BootLine)
    $p = Join-Path $Destination 'LEIA-ME-PENDRIVE.txt'
    [System.IO.File]::WriteAllText($p, (New-TIPELeiaMe -StampLine $StampLine -BootLine $BootLine), (New-Object System.Text.UTF8Encoding($true)))
}

function Assert-TIPEFiles {
    param([string]$Root, [string[]]$Relative, [string]$What)
    $miss = @($Relative | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_)) })
    if ($miss.Count) { throw ('{0}: faltam {1}' -f $What, ($miss -join ', ')) }
}

# Partições TI-SUITE (ou qualquer partição com TI-Suite.ps1 + portable.config na raiz) em discos USB/removíveis
function Find-TIPEUpdateTargets {
    param([int]$Wanted)
    $cands = @(Get-TIPEDiskCandidates -Disks @(Get-TIPEDiskInfo) | Where-Object {
        $_.Removable -and @('windows', 'readonly', 'nomedia') -notcontains $_.Code -and ($Wanted -lt 0 -or $_.Number -eq $Wanted)
    })
    $out = New-Object System.Collections.ArrayList
    foreach ($c in $cands) {
        foreach ($l in (Get-TIPEDiskLetters -DiskNumber $c.Number)) {
            $root = '{0}:\' -f $l
            if ((Test-Path -LiteralPath (Join-Path $root 'TI-Suite.ps1')) -and (Test-Path -LiteralPath (Join-Path $root 'portable.config'))) {
                $label = ''
                try { $label = [string](Get-Volume -DriveLetter $l -ErrorAction Stop).FileSystemLabel } catch { }
                [void]$out.Add([pscustomobject]@{ Letter = $l; Root = $root; Label = $label; Disk = $c })
            }
        }
    }
    return @($out)
}

# --- Modos --------------------------------------------------------------------
function Invoke-TIPEUpdate {
    param([string]$Version)
    Write-TIPEStep 'Procurando o pendrive do TI Suite'
    $targets = @(Find-TIPEUpdateTargets -Wanted $Disco)
    if (-not $targets.Count) {
        throw 'Nenhum pendrive com o TI Suite na raiz (TI-Suite.ps1 e portable.config) foi encontrado. Para criar um, rode sem -SomenteAtualizar.'
    }
    foreach ($t in $targets) { Write-Host ('      {0}  "{1}"  disco {2}: {3} ({4})' -f $t.Root, $t.Label, $t.Disk.Number, $t.Disk.Name, $t.Disk.SizeText) -ForegroundColor White }
    $sel = $targets[0]
    if ($targets.Count -gt 1) {
        $ans = [string](Read-Host '    Digite a letra da unidade a atualizar (Enter vazio cancela)')
        $ans = $ans.Trim().TrimEnd(':', '\').ToUpperInvariant()
        if (-not $ans) { Stop-TIPECancel 'Cancelado: nada foi alterado.' }
        $m = @($targets | Where-Object { $_.Letter -eq $ans })
        if (-not $m.Count) { Stop-TIPECancel ('Cancelado: a unidade {0}: não está na lista.' -f $ans) }
        $sel = $m[0]
    }
    if ($sel.Root.TrimEnd('\') -ieq $script:Root.TrimEnd('\')) { throw 'A pasta do projeto é a própria raiz do pendrive: não há o que atualizar.' }
    $ans = [string](Read-Host ('    Atualizar o TI Suite em {0}? Os dados de campo e o boot não são mexidos. [S/N]' -f $sel.Root))
    if ($ans.Trim() -notmatch '^(?i)(s|sim)$') { Stop-TIPECancel 'Cancelado: nada foi alterado.' }

    Write-TIPEStep 'Compilando os controles visuais (bin\TISuite.Controls.dll)'
    Build-TIPEControlsDll -OutDir (Join-Path $script:State.WorkRoot 'bin')

    Write-TIPEStep ('Copiando o TI Suite para {0}' -f $sel.Root)
    Copy-TIPEApp -Destination $sel.Root -DllDir (Join-Path $script:State.WorkRoot 'bin') -Update
    Write-TIPEDefaultConfig -Destination $sel.Root
    # LEIA-ME e reparo\ só no pendrive de recuperação (num pendrive só portátil o texto do boot confundiria)
    $old = Join-Path $sel.Root 'LEIA-ME-PENDRIVE.txt'
    if ((Test-Path -LiteralPath $old) -or $sel.Label -eq 'TI-SUITE') {
        New-Item -ItemType Directory -Path (Join-Path $sel.Root 'reparo') -Force | Out-Null
        $bootLine = ''
        if (Test-Path -LiteralPath $old) { try { $bootLine = Get-TIPEBootLine ([System.IO.File]::ReadAllText($old)) } catch { } }
        $stamp = 'Atualizado em {0} no computador {1} com o TI Suite v{2}.' -f (Get-Date -Format 'dd/MM/yyyy HH:mm'), $env:COMPUTERNAME, $Version
        Write-TIPELeiaMe -Destination $sel.Root -StampLine $stamp -BootLine $bootLine
    } else {
        Write-TIPEInfo 'Pendrive só portátil (sem a partição de boot): para ele dar boot, recrie com o Criar-Pendrive.cmd sem opções.'
    }
    Assert-TIPEFiles -Root $sel.Root -What 'Atualização' -Relative @('TI-Suite.ps1', 'Iniciar.cmd', 'portable.config', 'bin\TISuite.Controls.dll', 'bin\TISuite.Controls.stamp', 'src\Core\Controls.cs')
    Add-TIPESummary 'Pendrive' ('{0} ("{1}") - disco {2}: {3}' -f $sel.Root, $sel.Label, $sel.Disk.Number, $sel.Disk.Name)
    Add-TIPESummary 'TI Suite' ('v{0} copiado; dados de campo e boot sem mudança' -f $Version)
    return 0
}

function Invoke-TIPEBuild {
    param([string]$Version, [string]$DriversDir, [bool]$IsoOnly)
    $disk = $null
    $appFolders = @()
    if (-not $IsoOnly) {
        Write-TIPEStep 'Escolha do pendrive'
        $disk = Select-TIPEDisk -Wanted $Disco
        $appFolders = @(Find-TIPEAppFolders -DiskNumber $disk.Number)
        Confirm-TIPEErase -Disk $disk -AppFolders $appFolders
        if (($disk.Size - 2.2GB) -lt (Get-TIPEFieldDataStats -Folders $appFolders)) {
            throw 'Os dados de campo do pendrive não cabem na partição TI-SUITE nova. Nada foi apagado.'
        }
        Add-TIPESummary 'Pendrive' ('disco {0}: {1} ({2})' -f $disk.Number, $disk.Name, $disk.SizeText)
        Write-TIPEInfo 'Confirmado. O pendrive só é apagado depois que o Windows PE estiver pronto (10 a 20 minutos).'
    }

    Write-TIPEStep 'Compilando os controles visuais (bin\TISuite.Controls.dll)'
    $dllDir = Join-Path $script:State.WorkRoot 'bin'
    Build-TIPEControlsDll -OutDir $dllDir

    Write-TIPEStep 'Montando o Windows PE (pacotes, idioma, drivers, fontes e startnet.cmd)'
    $peDir = Join-Path $script:State.WorkRoot 'pe'
    New-TIPEImage -PeDir $peDir -DriversDir $DriversDir

    $bootText = Get-TIPEBootText -Boot2023 $Boot2023.IsPresent
    $stamp = 'Criado em {0} no computador {1} com o TI Suite v{2} e o Windows PE do ADK {3}.' -f (Get-Date -Format 'dd/MM/yyyy HH:mm'), $env:COMPUTERNAME, $Version, $script:State.AdkVersion
    if ($IsoOnly) {
        Write-TIPEStep 'Pondo o TI Suite dentro do ISO (para o teste na máquina virtual)'
        $media = Join-Path $peDir 'media'
        Copy-TIPEApp -Destination $media -DllDir $dllDir
        Write-TIPEDefaultConfig -Destination $media
        Write-TIPELeiaMe -Destination $media -StampLine $stamp -BootLine $bootText
    }

    Write-TIPEStep 'Gerando a mídia de boot (MakeWinPEMedia)'
    $iso = Join-Path $script:State.WorkRoot 'TI.iso'
    New-TIPEIso -PeDir $peDir -IsoPath $iso -Use2023 $Boot2023.IsPresent

    if ($IsoOnly) {
        $final = Join-Path (Join-Path $script:Root 'dist') 'TI-Recuperacao.iso'
        if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Force }
        Move-Item -LiteralPath $iso -Destination $final
        Add-TIPESummary 'ISO' ('{0} ({1})' -f $final, (Format-TIPESize ([double](Get-Item -LiteralPath $final).Length)))
        Add-TIPESummary 'Boot' $bootText.Replace('Boot deste pendrive: ', '')
        return 0
    }

    Write-TIPEStep 'Guardando os dados de campo do pendrive antigo'
    Assert-TIPESameDisk -Disk $disk
    $appFolders = @(Find-TIPEAppFolders -DiskNumber $disk.Number)
    $saved = @()
    if ($appFolders.Count) {
        $dataDir = Join-Path (Split-Path -Parent $script:State.WorkRoot) ('TI-PE-dados-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $saved = @(Backup-TIPEFieldData -Folders $appFolders -Dest $dataDir)
        Write-TIPEOk ('Dados guardados em {0}' -f $dataDir)
    } else {
        Write-TIPEInfo 'Nenhuma pasta do TI Suite no pendrive: não há dados de campo para guardar.'
    }

    Write-TIPEStep 'Apagando e particionando o pendrive'
    $letters = Format-TIPEPendrive -Disk $disk -FileSystem $SistemaArquivos
    $bootRoot = '{0}:\' -f $letters.Boot
    $dataRoot = '{0}:\' -f $letters.Data

    Write-TIPEStep 'Copiando o Windows PE para a partição TI-BOOT'
    $copied = $false
    try {
        Copy-TIPEIsoToBoot -IsoPath $iso -BootLetter $letters.Boot
        $copied = $true
    } catch {
        Write-TIPEWarn ('Não deu para copiar do ISO ({0}); usando o MakeWinPEMedia /UFD direto na partição TI-BOOT.' -f $_.Exception.Message)
    }
    if (-not $copied) {
        $bx = ''
        if ($Boot2023) { $bx = ' /bootex' }
        $code = Invoke-TIPEAdkCommand -Name 'makeufd' -Command ('call MakeWinPEMedia /UFD /F{0} "{1}" {2}: 2>&1' -f $bx, $peDir, $letters.Boot)
        if ($code -ne 0) { throw ('O MakeWinPEMedia /UFD falhou (código {0}).' -f $code) }
        try { Set-Volume -DriveLetter $letters.Boot -NewFileSystemLabel 'TI-BOOT' -ErrorAction Stop | Out-Null } catch { }
        if (-not (Test-Path -LiteralPath $dataRoot)) { throw 'A partição TI-SUITE sumiu depois do MakeWinPEMedia /UFD.' }
    }
    Write-TIPEInfo 'Gravando o código de boot BIOS (bootsect /nt60 /mbr)...'
    $r = Invoke-TIPETool -FilePath $script:State.Adk.Bootsect -Arguments @('/nt60', ('{0}:' -f $letters.Boot), '/force', '/mbr')
    if ($r.ExitCode -ne 0) { throw ('O bootsect falhou (código {0}): o boot BIOS (legado) não vai funcionar.' -f $r.ExitCode) }
    Assert-TIPEFiles -Root $bootRoot -What 'Partição TI-BOOT' -Relative @('EFI\Boot\bootx64.efi', 'sources\boot.wim')
    if (-not (Test-Path -LiteralPath (Join-Path $bootRoot 'bootmgr'))) { Write-TIPEWarn 'TI-BOOT sem o arquivo bootmgr: o boot BIOS (legado) pode não funcionar; o UEFI funciona.' }
    Write-TIPEOk 'Boot UEFI (EFI\Boot\bootx64.efi) e BIOS (bootsect) prontos.'

    Write-TIPEStep 'Copiando o TI Suite para a partição TI-SUITE'
    Copy-TIPEApp -Destination $dataRoot -DllDir $dllDir
    $exit = 0
    if ($saved.Count) {
        if (Restore-TIPEFieldData -Saved $saved -DataRoot $dataRoot) {
            $script:State.DataRestored = $true
            if (Remove-TIPEFolder $script:State.DataBackup) { $script:State.DataBackup = $null }
            Add-TIPESummary 'Dados de campo' ('{0} pasta(s) do TI Suite devolvida(s)' -f $saved.Count)
        } else {
            $exit = 2
            Add-TIPESummary 'Dados de campo' ('NÃO voltaram todos: copie de {0} para {1}' -f $script:State.DataBackup, $dataRoot)
        }
    } else {
        $script:State.DataRestored = $true
        Add-TIPESummary 'Dados de campo' 'nenhum (pendrive sem TI Suite)'
    }
    Write-TIPEDefaultConfig -Destination $dataRoot
    New-Item -ItemType Directory -Path (Join-Path $dataRoot 'reparo') -Force | Out-Null
    Write-TIPELeiaMe -Destination $dataRoot -StampLine $stamp -BootLine $bootText
    Assert-TIPEFiles -Root $dataRoot -What 'Partição TI-SUITE' -Relative @('TI-Suite.ps1', 'Iniciar.cmd', 'portable.config', 'config.json', 'bin\TISuite.Controls.dll', 'bin\TISuite.Controls.stamp', 'LEIA-ME-PENDRIVE.txt')
    Add-TIPESummary 'TI-BOOT' ('{0}  Windows PE; {1}' -f $bootRoot, $bootText.Replace('Boot deste pendrive: ', ''))
    Add-TIPESummary 'TI-SUITE' ('{0}  {1}, TI Suite v{2}' -f $dataRoot, $SistemaArquivos, $Version)
    return $exit
}

function Invoke-TIPEMain {
    $version = Get-TIPEAppVersion
    $modeText = 'criar o pendrive de recuperação (apaga o pendrive)'
    if ($SomenteISO) { $modeText = 'gerar dist\TI-Recuperacao.iso (sem pendrive)' }
    elseif ($SomenteAtualizar) { $modeText = 'atualizar o TI Suite num pendrive já criado (sem formatar)' }
    Write-Host ''
    Write-Host ('TI Suite v{0} - pendrive de recuperação' -f $version) -ForegroundColor Cyan
    Write-Host ('Modo: {0}' -f $modeText)
    Add-TIPESummary 'Modo' $modeText

    Write-TIPEStep 'Conferindo os requisitos'
    if ($SomenteAtualizar -and $SomenteISO) { throw 'Use -SomenteAtualizar ou -SomenteISO, não os dois.' }
    if (-not (Test-TIPEAdmin)) {
        throw 'Rode como administrador: abra o Criar-Pendrive.cmd e aceite o aviso do Windows (UAC), ou abra o Windows PowerShell como administrador.'
    }
    # Uma execução por vez: outra limparia a imagem montada e a pasta de trabalho desta
    $script:Mutex = New-Object System.Threading.Mutex($false, 'Global\TISuite-CriarPendrive')
    $got = $false
    try { $got = $script:Mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { $script:Mutex.Dispose(); $script:Mutex = $null; throw 'Já há outro Criar-Pendrive rodando neste PC: espere ele terminar.' }
    if ([Environment]::OSVersion.Version.Major -lt 10) { throw 'Este script precisa do Windows 10 ou 11.' }
    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Rode num Windows normal, não no Windows PE.' }
    if (-not [Environment]::Is64BitProcess) { throw 'Abra o Windows PowerShell de 64 bits (o de 32 bits não enxerga as ferramentas do ADK direito).' }
    foreach ($f in @('TI-Suite.ps1', 'Iniciar.cmd', 'src\Core\Controls.cs')) {
        if (-not (Test-Path -LiteralPath (Join-Path $script:Root $f))) { throw ('Arquivo do projeto não encontrado: {0}' -f $f) }
    }
    if ($SomenteISO -and $Disco -ge 0) { Write-TIPEWarn 'A opção -Disco não vale com -SomenteISO (nenhum pendrive é usado).' }

    # Drivers: -Drivers ou dev\drivers
    $drv = ''
    if ($Drivers) {
        if (-not (Test-Path -LiteralPath $Drivers -PathType Container)) { throw ('A pasta de drivers não existe: {0}' -f $Drivers) }
        $drv = (Resolve-Path -LiteralPath $Drivers).ProviderPath
    } elseif (Test-Path -LiteralPath (Join-Path $script:DevDir 'drivers') -PathType Container) {
        $drv = Join-Path $script:DevDir 'drivers'
    }
    if ($drv -and -not @(Get-ChildItem -LiteralPath $drv -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue).Count) {
        if ($Drivers) { throw ('A pasta {0} não tem nenhum arquivo .inf (driver).' -f $drv) }
        $drv = ''
    }
    if ($SomenteAtualizar -and ($Drivers -or $Boot2023)) { Write-TIPEWarn '-Drivers e -Boot2023 só valem para criar o pendrive; na atualização o boot não é mexido.' }

    # Pasta de trabalho (apagada no fim, mesmo com erro)
    $work = Get-TIPEWorkRoot -Temp $env:TEMP -SystemDrive $env:SystemDrive -Id ([guid]::NewGuid().ToString('N'))
    if ($SomenteAtualizar) {
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $script:State.WorkRoot = $work
        Write-TIPEOk 'Administrador, Windows e arquivos do projeto.'
        return (Invoke-TIPEUpdate -Version $version)
    }

    $adk = Find-TIPEAdk
    Assert-TIPEAdk -Adk $adk
    $script:State.Adk = $adk
    $script:State.Dism = $adk.Dism
    $script:State.AdkVersion = '?'
    try { $script:State.AdkVersion = [string](Get-Item -LiteralPath $adk.Dism).VersionInfo.ProductVersion } catch { }
    if (-not (Test-TIPEAsciiPath $adk.KitsRoot)) { throw ('O ADK está numa pasta com acento ou símbolo ({0}); reinstale na pasta padrão.' -f $adk.KitsRoot) }
    if ($Boot2023 -and -not (Select-String -LiteralPath $adk.MakeMedia -Pattern 'bootex' -SimpleMatch -Quiet)) {
        throw 'Este ADK não tem o boot da "Windows UEFI CA 2023" (opção /bootex do MakeWinPEMedia). Atualize o ADK e o complemento Windows PE (10.1.26100.2454, de dezembro de 2024, ou mais novo) ou crie sem -Boot2023.'
    }
    Write-TIPEOk ('Administrador, Windows {0}, ADK {1} em {2}' -f [Environment]::OSVersion.Version.Build, $script:State.AdkVersion, $adk.KitsRoot)
    if ($drv) { Write-TIPEInfo ('Drivers para o Windows PE: {0}' -f $drv) }

    $base = Split-Path -Parent $work
    Clear-TIPELeftovers -Base $base
    $free = Get-TIPEFreeBytes $work
    if ($free -ge 0 -and $free -lt 4GB) { throw ('Pouco espaço livre em {0} ({1}): o Windows PE precisa de uns 4 GB de pasta de trabalho.' -f ([System.IO.Path]::GetPathRoot($work)), (Format-TIPESize $free)) }
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $script:State.WorkRoot = $work
    Write-TIPEInfo ('Pasta de trabalho: {0}' -f $work)

    return (Invoke-TIPEBuild -Version $version -DriversDir $drv -IsoOnly $SomenteISO.IsPresent)
}

function Invoke-TIPECleanup {
    try { Dismount-TIPEHive } catch { }
    try { Dismount-TIPEIso } catch { }
    try { Dismount-TIPEImageDiscard } catch { }
    # Cópia dos dados de campo: se o pendrive nem chegou a ser apagado, os dados continuam nele
    # (a cópia tem senhas de Wi-Fi e não deve ficar esquecida no %TEMP%)
    if ($script:State.DataBackup -and -not $script:State.Formatted) {
        if (Remove-TIPEFolder $script:State.DataBackup) { $script:State.DataBackup = $null }
    }
    $w = $script:State.WorkRoot
    if ($w -and (Test-Path -LiteralPath $w)) {
        if ($script:State.Mounted) {
            Write-Host ('    A imagem continua montada: a pasta de trabalho {0} fica. Reinicie o PC, rode "dism /Cleanup-Mountpoints" e apague a pasta.' -f $w) -ForegroundColor Yellow
        } elseif (-not (Remove-TIPEFolder $w)) {
            Write-Host ('    Não consegui apagar a pasta de trabalho {0}: apague-a depois.' -f $w) -ForegroundColor Yellow
        }
    }
    if ($script:Mutex) {
        try { $script:Mutex.ReleaseMutex() } catch { }
        $script:Mutex.Dispose()
        $script:Mutex = $null
    }
}

function Write-TIPEFinalSummary {
    param([int]$Code, [string]$LogPath)
    $mins = [Math]::Round(((Get-Date) - $script:Started).TotalMinutes, 1)
    Write-Host ''
    Write-Host '==================================== RESUMO ====================================' -ForegroundColor Cyan
    foreach ($l in $script:State.Summary) { Write-Host ('  ' + $l) }
    if ($script:State.Warnings.Count) {
        Write-Host ('  Avisos ({0}):' -f $script:State.Warnings.Count) -ForegroundColor Yellow
        foreach ($w in $script:State.Warnings) { Write-Host ('    - ' + $w) -ForegroundColor Yellow }
    }
    if ($LogPath) { Write-Host ('  Log:            {0}' -f $LogPath) }
    Write-Host ('  Tempo:          {0} min' -f $mins.ToString([System.Globalization.CultureInfo]::InvariantCulture).Replace('.', ','))
    if ($script:State.DataBackup -and -not $script:State.DataRestored) {
        Write-Host ''
        Write-Host ('  Os dados de campo do pendrive antigo estão guardados em: {0}' -f $script:State.DataBackup) -ForegroundColor Yellow
        Write-Host '  Copie o conteúdo da pasta 00 para a raiz da partição TI-SUITE (e as outras para dados-anteriores\).' -ForegroundColor Yellow
    }
    if ($Code -eq 0) {
        Write-Host ''
        if ($SomenteISO) {
            Write-Host '  Pronto. Para testar: crie uma máquina virtual (Hyper-V geração 2 ou VirtualBox com EFI), use o ISO como' -ForegroundColor Green
            Write-Host '  DVD e dê boot. O TI Suite do ISO é somente leitura; conecte também um disco com Windows para testar os reparos.' -ForegroundColor Green
        } elseif ($SomenteAtualizar) {
            Write-Host '  Pronto. O TI Suite do pendrive está atualizado.' -ForegroundColor Green
        } else {
            Write-Host '  Pronto. Com o Windows aberto, use o Iniciar.cmd da partição TI-SUITE. Para o boot, veja o' -ForegroundColor Green
            Write-Host '  LEIA-ME-PENDRIVE.txt (tecla do menu de boot de cada fabricante, pastas reparo\ e Backup-TI\).' -ForegroundColor Green
        }
    }
}

# =====================================================================
# Execução
# =====================================================================
$exitCode = 1
$logPath = $null
try {
    $distDir = Join-Path $script:Root 'dist'
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    $logPath = Join-Path $distDir ('criar-pendrive-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -LiteralPath $logPath | Out-Null
} catch {
    $logPath = $null
    Write-Host 'Aviso: não consegui gravar o log em dist\ (o processo continua).' -ForegroundColor Yellow
}

try {
    $res = @(Invoke-TIPEMain)
    $exitCode = 0
    if ($res.Count) { $exitCode = [int]$res[$res.Count - 1] }
} catch [System.OperationCanceledException] {
    Write-Host ''
    Write-Host ('  ' + $_.Exception.Message) -ForegroundColor Yellow
    $exitCode = 1
} catch {
    Write-Host ''
    Write-Host ('ERRO: {0}' -f $_.Exception.Message) -ForegroundColor Red
    if ($_.ScriptStackTrace) { Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray }
    if ($script:State.Formatted) {
        Write-Host 'O pendrive já tinha sido apagado quando o erro aconteceu: rode de novo para recriá-lo.' -ForegroundColor Red
    } elseif ($script:State.UpdateStarted) {
        Write-Host 'O TI Suite do pendrive pode ter ficado pela metade: rode -SomenteAtualizar de novo (os dados de campo não foram mexidos).' -ForegroundColor Red
    } elseif (-not $SomenteISO -and -not $SomenteAtualizar) {
        Write-Host 'O pendrive não foi apagado.' -ForegroundColor Yellow
    }
    $exitCode = 1
} finally {
    Invoke-TIPECleanup
    Write-TIPEFinalSummary -Code $exitCode -LogPath $logPath
    if ($logPath) { try { Stop-Transcript | Out-Null } catch { } }
}
exit $exitCode
