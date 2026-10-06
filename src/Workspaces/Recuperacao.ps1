# =====================================================================
# ÁREA: RECUPERAÇÃO - repara o Windows do disco a partir do pendrive
#   Só no modo recuperação (pendrive bootável ou -Recovery). Nada é
#   reinstalado: disco (chkdsk), inicialização (bcdboot), arquivos do sistema
#   (SFC/DISM offline), atualizações pendentes, atualização e driver
#   problemáticos, modo de segurança e remoção offline de programas.
#   Segurança dos dados:
#     - confirmação em toda ação que altera o disco;
#     - nunca o Windows em execução (IsRunning) nem volume bloqueado (Locked);
#     - cópia do BCD em logs\bcd-backup\<data> antes do bcdboot/bcdedit;
#     - letra temporária da partição do sistema sai no finally;
#     - hives offline sempre descarregados (06-Windows.ps1);
#     - a chave de recuperação do BitLocker nunca vai para console, log ou auditoria.
# =====================================================================

# ---------------------------------------------------------------------
# Regras usadas na interface E no worker
# ---------------------------------------------------------------------
$global:TIRecoveryShared = @'

# Chave de recuperação do BitLocker: 48 números em 8 grupos de 6, com ou sem hífens
# (ou espaços). Cada grupo é múltiplo de 11 e menor que 720896: pega erro de digitação.
# '' = serve; senão a mensagem para o técnico. NUNCA registre a chave.
function Get-TIRecoveryKeyError {
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if (-not $t) { return 'Digite a chave de recuperação (48 números).' }
    if ($t -match '[^\d\s\-]') { return 'A chave tem só números e hífens. Confira se não entrou uma letra.' }
    if ($t -match '[\s\-]') {
        $groups = @($t -split '[\s\-]+' | Where-Object { $_ })
        if ($groups.Count -ne 8 -or @($groups | Where-Object { $_.Length -ne 6 }).Count -gt 0) {
            return 'A chave tem 8 grupos de 6 números (ex.: 123456-123456-...). Confira os grupos.'
        }
        $d = $groups -join ''
    } else {
        $d = $t
        if ($d.Length -ne 48) { return ('A chave tem 48 números; foram digitados {0}.' -f $d.Length) }
    }
    for ($i = 0; $i -lt 8; $i++) {
        $b = [int]$d.Substring($i * 6, 6)
        if (($b % 11) -ne 0 -or $b -ge 720896) { return ('O grupo {0} não confere: confira a digitação.' -f ($i + 1)) }
    }
    return ''
}

# Chave no formato do WMI (xxxxxx-xxxxxx-...), ou '' quando não serve
function ConvertTo-TIRecoveryKey {
    param([string]$Text)
    if (Get-TIRecoveryKeyError $Text) { return '' }
    $d = ([string]$Text) -replace '[\s\-]', ''
    $g = for ($i = 0; $i -lt 8; $i++) { $d.Substring($i * 6, 6) }
    return ($g -join '-')
}

# Nome do laudo: recuperacao-<PC>-<AAAAMMDD-HHmm>.txt (nome do PC limpo para arquivo)
function Get-TIRecoveryLaudoName {
    param([string]$Computer, [datetime]$When = (Get-Date))
    $pc = (([string]$Computer).Trim() -replace '[\\/:*?"<>|\s]+', '_').Trim('_', '.')
    if (-not $pc) { $pc = 'PC' }
    return ('recuperacao-{0}-{1}.txt' -f $pc, $When.ToString('yyyyMMdd-HHmm'))
}
'@
$global:TIWorkerLib += $global:TIRecoveryShared
. ([scriptblock]::Create($global:TIRecoveryShared))

$global:TIWorkerLib += @'

# ---------------------------------------------------------------------
# RECUPERAÇÃO (roda no worker)
# ---------------------------------------------------------------------

# --- Regras (funções puras, testadas sem Windows) -----------------------

# Codificação da saída: o sfc escreve UTF-16; chkdsk, bcdboot e dism, na página OEM
function Get-TIOutputEncodingKind {
    param([byte[]]$Bytes)
    if (-not $Bytes -or $Bytes.Length -lt 2) { return 'oem' }
    if ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return 'utf16' }
    $pairs = [Math]::Min(256, [int][Math]::Floor($Bytes.Length / 2))
    $z = 0
    for ($i = 0; $i -lt $pairs; $i++) { if ($Bytes[2 * $i + 1] -eq 0) { $z++ } }
    if ($pairs -gt 0 -and ($z / $pairs) -ge 0.3) { return 'utf16' }
    return 'oem'
}

# Texto -> segmentos. \n (ou \r\n) fecha uma linha; \r sozinho fecha um segmento
# de progresso (o programa reescreve a mesma linha). \r no fim espera o próximo
# pedaço (pode ser \r\n). -Final: o que sobrou também sai.
function Split-TIOutputSegments {
    param([string]$Text, [switch]$Final)
    $segs = New-Object System.Collections.ArrayList
    $t = [string]$Text
    $seps = [char[]]@([char]13, [char]10)
    $pos = 0
    while ($pos -lt $t.Length) {
        $i = $t.IndexOfAny($seps, $pos)
        if ($i -lt 0) { break }
        if ($t[$i] -eq [char]10) {
            [void]$segs.Add([pscustomobject]@{ Text = $t.Substring($pos, $i - $pos); Cr = $false })
            $pos = $i + 1
            continue
        }
        if ($i + 1 -ge $t.Length) {
            if ($Final) { [void]$segs.Add([pscustomobject]@{ Text = $t.Substring($pos, $i - $pos); Cr = $true }); $pos = $i + 1 }
            break
        }
        if ($t[$i + 1] -eq [char]10) {
            [void]$segs.Add([pscustomobject]@{ Text = $t.Substring($pos, $i - $pos); Cr = $false })
            $pos = $i + 2
            continue
        }
        [void]$segs.Add([pscustomobject]@{ Text = $t.Substring($pos, $i - $pos); Cr = $true })
        $pos = $i + 1
    }
    $rest = ''
    if ($pos -lt $t.Length) { $rest = $t.Substring($pos) }
    if ($Final -and $rest) { [void]$segs.Add([pscustomobject]@{ Text = $rest; Cr = $false }); $rest = '' }
    return [pscustomobject]@{ Segments = $segs.ToArray(); Rest = $rest }
}

# Último percentual do texto ('Estágio: 18%; Total: 12%' -> 12; '[==  45.0%  ]' -> 45). -1 = nenhum
function Get-TIProgressPercent {
    param([string]$Text)
    $ms = [regex]::Matches([string]$Text, '(\d{1,3})(?:[.,]\d+)?\s*%')
    if ($ms.Count -eq 0) { return -1 }
    $v = [int]$ms[$ms.Count - 1].Groups[1].Value
    if ($v -gt 100) { return -1 }
    return $v
}

# Linha de progresso (não vai para o console; só move a barra)
function Test-TIProgressLine {
    param([string]$Text, [bool]$Cr = $false)
    if ((Get-TIProgressPercent $Text) -lt 0) { return $false }
    if ($Cr) { return $true }
    $t = ([string]$Text).Trim()
    if ($t.Length -gt 160) { return $false }
    if ($t -match '^[\[\s=\-]*\d{1,3}(?:[.,]\d+)?\s*%[\s=\]\-.]*$') { return $true }
    return ($t -match '^\[[=\s\-]*\d' -or $t -match '(?i)conclu|complete|progress|total|est.gio|stage|feitos|verifica')
}

# Valor de argumento: entre aspas só quando tem espaço (aspas com \ no fim viram escape)
function Format-TIArgValue {
    param([string]$Path)
    $p = [string]$Path
    if ($p -notmatch '\s') { return $p }
    if ($p.EndsWith('\')) { $p += '\' }
    return ('"{0}"' -f $p)
}

# Código de saída do chkdsk. Stop = o reparo automático para e o técnico decide.
function Get-TIChkdskResult {
    param([int]$ExitCode)
    switch ($ExitCode) {
        0 { return [pscustomobject]@{ Ok = $true; Level = 'Success'; Stop = $false; Code = 0; Text = 'Nenhum erro no sistema de arquivos (código 0).' } }
        1 { return [pscustomobject]@{ Ok = $true; Level = 'Success'; Stop = $false; Code = 1; Text = 'Erros encontrados e corrigidos (código 1).' } }
        2 { return [pscustomobject]@{ Ok = $true; Level = 'Success'; Stop = $false; Code = 2; Text = 'Limpeza de manutenção do disco feita, sem erros a corrigir (código 2).' } }
        3 { return [pscustomobject]@{ Ok = $false; Level = 'Error'; Stop = $true; Code = 3; Text = 'O chkdsk não conseguiu verificar o disco ou corrigir os erros (código 3). Faça o backup dos dados (área Backup) e rode Verificar disco com a verificação completa (/r); se continuar, o disco pode estar falhando.' } }
        -1 { return [pscustomobject]@{ Ok = $false; Level = 'Error'; Stop = $true; Code = -1; Text = 'O chkdsk não terminou (cancelado, tempo esgotado ou não abriu): o estado do disco é desconhecido.' } }
    }
    return [pscustomobject]@{ Ok = $false; Level = 'Warn'; Stop = $true; Code = $ExitCode; Text = ('O chkdsk terminou com o código {0}, que não é documentado. Veja as mensagens no console.' -f $ExitCode) }
}

# Resultado do SFC pelo texto final (o código de saída do sfc não é documentado)
function Get-TISfcResult {
    param([int]$ExitCode, [string]$Output = '')
    $t = [string]$Output
    $mk = { param($ok, $lvl, $kind, $txt) [pscustomobject]@{ Ok = $ok; Level = $lvl; Kind = $kind; Text = $txt } }
    if ($ExitCode -eq -1) { return (& $mk $false 'Error' 'failed' 'O SFC não terminou (cancelado, tempo esgotado ou não abriu).') }
    if ($t -match '(?i)repair pending|system repair pending|reparo do sistema pendente|repara..o do sistema pendente|exige reinicializa') {
        return (& $mk $false 'Warn' 'pending' 'Há um reparo pendente de uma atualização: rode Desfazer atualização (ações pendentes) e depois o SFC de novo.')
    }
    if ($t -match '(?i)did not find any integrity violations|n.o encontrou (nenhuma )?viola') {
        return (& $mk $true 'Success' 'clean' 'Nenhum arquivo do sistema corrompido.')
    }
    if ($t -match '(?i)unable to fix some|n.o (p.de|conseguiu) corrigir alguns|mas n.o p.de corrigir') {
        return (& $mk $false 'Warn' 'partial' 'Arquivos corrompidos encontrados, mas alguns não puderam ser corrigidos. O DISM com uma imagem da mesma versão (pasta reparo\) completa o reparo; detalhes no log do SFC.')
    }
    if ($t -match '(?i)successfully repaired|reparou com .xito|e os reparou') {
        return (& $mk $true 'Success' 'repaired' 'Arquivos corrompidos encontrados e reparados.')
    }
    if ($t -match '(?i)could not perform the requested operation|n.o p.de executar a opera') {
        return (& $mk $false 'Error' 'failed' 'O SFC não conseguiu fazer a verificação. Rode Verificar disco e o DISM; se continuar, veja o log do SFC.')
    }
    if ($t -match '(?i)could not start the repair service|n.o p.de iniciar o servi') {
        return (& $mk $false 'Error' 'failed' 'O SFC não conseguiu iniciar o serviço de reparo para este Windows.')
    }
    if ($ExitCode -eq 0) { return (& $mk $true 'Success' 'ok' 'Verificação concluída (código 0).') }
    return (& $mk $false 'Error' 'failed' ('O SFC terminou com o código {0}. Veja o log do SFC na pasta logs.' -f $ExitCode))
}

# Código de saída do DISM (erro do Windows ou HRESULT) em português
function Get-TIDismCodeText {
    param([int64]$ExitCode)
    if ($ExitCode -eq -1) { return 'O DISM não terminou (cancelado, tempo esgotado ou não abriu).' }
    $u = $(if ($ExitCode -lt 0) { [uint32]($ExitCode + 4294967296) } else { [uint32]$ExitCode })
    $hex = '0x{0:X8}' -f $u
    $mapHr = @{
        '0x800F081F' = 'arquivos de origem não encontrados: a imagem de reparo não é da mesma versão e edição do Windows (ou não há fonte)'
        '0x800F0906' = 'não foi possível baixar os arquivos de origem'
        '0x800F0907' = 'a política do computador impede baixar os arquivos de origem'
        '0x800F0825' = 'esta atualização é permanente e não pode ser removida (comum nas cumulativas que vêm com a pilha de manutenção)'
        '0x800F0831' = 'falta um pacote no repositório de componentes (a fonte precisa ser da mesma versão)'
        '0x80073712' = 'o repositório de componentes está corrompido'
        '0x80070490' = 'elemento não encontrado'
        '0x8007000E' = 'memória insuficiente'
    }
    if ($mapHr.ContainsKey($hex)) { return ('Falha do DISM ({0}): {1}.' -f $hex, $mapHr[$hex]) }
    $w32 = -1
    if ($u -le 0xFFFF) { $w32 = [int]$u }
    elseif (($u -shr 16) -eq 0x8007) { $w32 = [int]($u -band 0xFFFF) }
    $map32 = @{
        2 = 'arquivo ou pasta não encontrado'; 3 = 'caminho não encontrado'; 5 = 'acesso negado (o TI Suite precisa de administrador)'
        32 = 'arquivo em uso por outro programa'; 50 = 'operação não suportada nesta imagem'
        87 = 'opção não reconhecida para esta versão do Windows'; 112 = 'sem espaço em disco: libere espaço no disco do Windows'
        1392 = 'arquivo ou pasta corrompido: rode Verificar disco com a verificação completa (/r)'
        1393 = 'estrutura do disco corrompida: rode Verificar disco'; 1726 = 'falha na comunicação com o serviço do DISM'
        14098 = 'o repositório de componentes está corrompido'
    }
    if ($w32 -ge 0 -and $map32.ContainsKey($w32)) { return ('Falha do DISM (erro {0}): {1}.' -f $w32, $map32[$w32]) }
    $shown = $(if ($u -gt 0xFFFF) { $hex } else { [string]$u })
    return ('Falha do DISM (código {0}). Veja o log do DISM na pasta logs.' -f $shown)
}

# Resultado do DISM pelo código e pelo texto (/English). Kind: clean | repairable |
# notrepairable | restored | ok | failed
function Get-TIDismResult {
    param([int64]$ExitCode, [string]$Output = '')
    $t = [string]$Output
    $kind = 'ok'
    if ($t -match '(?i)no component store corruption detected|nenhuma corrup..o') { $kind = 'clean' }
    elseif ($t -match '(?i)component store cannot be repaired|n.o pode ser reparado') { $kind = 'notrepairable' }
    elseif ($t -match '(?i)component store is repairable|pode ser reparado|repar.vel') { $kind = 'repairable' }
    elseif ($t -match '(?i)restore operation completed successfully|opera..o de restaura..o foi conclu') { $kind = 'restored' }
    if ($ExitCode -ne 0 -and $ExitCode -ne 3010) {
        return [pscustomobject]@{ Ok = $false; Level = 'Error'; Kind = 'failed'; Reboot = $false; Text = (Get-TIDismCodeText $ExitCode) }
    }
    $r = switch ($kind) {
        'clean'         { @($true, 'Success', 'Nenhum defeito no repositório de componentes do Windows.') }
        'repairable'    { @($true, 'Warn', 'O repositório de componentes do Windows tem defeitos que podem ser reparados.') }
        'notrepairable' { @($false, 'Error', 'O repositório de componentes do Windows tem defeitos que não podem ser reparados por aqui.') }
        'restored'      { @($true, 'Success', 'Repositório de componentes reparado.') }
        default         { @($true, 'Success', 'Operação concluída.') }
    }
    $txt = [string]$r[2]
    if ($ExitCode -eq 3010) { $txt += ' O Windows termina a operação ao ligar.' }
    return [pscustomobject]@{ Ok = [bool]$r[0]; Level = [string]$r[1]; Kind = $kind; Reboot = ($ExitCode -eq 3010); Text = $txt }
}

# Arquivos de boot para o bcdboot /f: disco GPT só liga em UEFI; MBR com BIOS = BIOS;
# MBR com UEFI (ou sem saber) = ALL (cobre os dois)
function Get-TIBcdbootTarget {
    param([string]$Firmware = '', [string]$PartitionStyle = '')
    $s = ([string]$PartitionStyle).ToUpperInvariant()
    $f = ([string]$Firmware).ToUpperInvariant()
    if ($s -eq 'GPT') { return 'UEFI' }
    if ($s -eq 'MBR' -and $f -eq 'BIOS') { return 'BIOS' }
    return 'ALL'
}

function Get-TIBcdbootArgs {
    param([string]$WinDir, [string]$Letter, [string]$Target = 'ALL', [string]$Locale = '')
    $a = '"{0}" /s {1} /f {2}' -f ([string]$WinDir).TrimEnd('\'), (ConvertTo-TIDriveLetter $Letter), ([string]$Target).ToUpperInvariant()
    if ($Locale) { $a += ' /l ' + $Locale }
    return $a
}

# BCD na partição do sistema: UEFI em \EFI\Microsoft\Boot, BIOS em \Boot
function Get-TIBcdStorePaths {
    param([string]$Letter, [string]$Target = 'ALL')
    $l = ConvertTo-TIDriveLetter $Letter
    $t = ([string]$Target).ToUpperInvariant()
    $out = @()
    if ($t -ne 'BIOS') { $out += ($l + '\EFI\Microsoft\Boot\BCD') }
    if ($t -ne 'UEFI') { $out += ($l + '\Boot\BCD') }
    return $out
}

# Entrada do Windows no texto do "bcdedit /enum osloader /v": a que aponta para a
# unidade (device partition=D:); sem isso, a única entrada sem letra. O nome
# "identifier" muda com o idioma, então vale a primeira linha com {GUID} do bloco.
function Get-TIBcdLoaderInfo {
    param([string]$Text, [string]$Drive = '')
    $d = ConvertTo-TIDriveLetter $Drive
    $loaders = New-Object System.Collections.ArrayList
    foreach ($b in [regex]::Split([string]$Text, '\r?\n[ \t]*\r?\n')) {
        $m = [regex]::Match($b, '(?im)^\S+[ \t]+(\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\})[ \t]*\r?$')
        if (-not $m.Success) { continue }
        $sb = [regex]::Match($b, '(?im)^[ \t]*safeboot[ \t]+(\S+)')
        $dev = [regex]::Match($b, '(?im)^[ \t]*(?:os)?device[ \t]+partition=([A-Za-z]:)')
        [void]$loaders.Add([pscustomobject]@{
            Id       = $m.Groups[1].Value
            SafeBoot = $(if ($sb.Success) { $sb.Groups[1].Value } else { '' })
            Drive    = $(if ($dev.Success) { $dev.Groups[1].Value.ToUpperInvariant() } else { '' })
        })
    }
    $pick = $null
    if ($d) { $pick = @($loaders | Where-Object { $_.Drive -eq $d }) | Select-Object -First 1 }
    if (-not $pick -and $loaders.Count -eq 1 -and -not $loaders[0].Drive) { $pick = $loaders[0] }
    return [pscustomobject]@{
        Id       = $(if ($pick) { $pick.Id } else { '' })
        SafeBoot = $(if ($pick) { $pick.SafeBoot } else { '' })
        Count    = $loaders.Count
    }
}

# Letra livre para a partição do sistema (nunca X:, a do WinPE)
function Select-TIFreeDriveLetter {
    param([string[]]$Used)
    $set = @{}
    foreach ($x in @($Used)) { $l = ConvertTo-TIDriveLetter $x; if ($l) { $set[$l] = $true } }
    foreach ($c in @('S', 'R', 'Q', 'P', 'O', 'N', 'M', 'L', 'K', 'J', 'T', 'U', 'V', 'W', 'Y', 'I', 'H', 'G')) {
        if (-not $set.ContainsKey($c + ':')) { return ($c + ':') }
    }
    return ''
}

# Builds da mesma base (atualização de ativação): 19041-19045, 22621/22631, 26100/26200
function Get-TIBuildFamily {
    param([int]$Build)
    if ($Build -ge 19041 -and $Build -le 19045) { return 19041 }
    if ($Build -eq 18362 -or $Build -eq 18363) { return 18362 }
    if ($Build -eq 22621 -or $Build -eq 22631) { return 22621 }
    if ($Build -eq 26100 -or $Build -eq 26200) { return 26100 }
    return $Build
}

# Imagem de reparo para o DISM: mesma edição (EditionId) e arquitetura; build igual
# primeiro, depois a mesma base. $null = nenhuma serve.
function Select-TIRepairImage {
    param($Images, [int]$Build, [string]$EditionId, [string]$Arch = '')
    $best = $null; $bestScore = 0
    $fam = Get-TIBuildFamily $Build
    foreach ($im in @($Images)) {
        if (-not $im -or -not $EditionId) { continue }
        if ([string]$im.EditionId -ne $EditionId) { continue }
        if ($Arch -and $im.Arch -and [string]$im.Arch -ne $Arch) { continue }
        $b = [int]$im.Build
        $score = 0
        if ($b -eq $Build -and $b -gt 0) { $score = 3 }
        elseif ($b -gt 0 -and (Get-TIBuildFamily $b) -eq $fam) { $score = 2 }
        if ($score -eq 0) { continue }
        # empate: .wim antes de .esd (mais rápido)
        if ([string]$im.Path -match '(?i)\.wim$') { $score += 0.5 }
        if ($score -gt $bestScore) { $best = $im; $bestScore = $score }
    }
    return $best
}

function Get-TIDismSourceArg {
    param([string]$Path, [int]$Index)
    $kind = $(if ([string]$Path -match '(?i)\.esd$') { 'ESD' } else { 'WIM' })
    $a = '/Source:{0}:{1}:{2}' -f $kind, $Path, $Index
    if ($a -match '\s') { $a = '"' + $a + '"' }
    return $a
}

# Nome curto do pacote: KB, cumulativa ou pilha de manutenção
function Get-TIPackageDisplayName {
    param([string]$PackageName)
    $parts = @(([string]$PackageName) -split '~')
    $head = $parts[0]
    $short = ''
    if ($parts.Count -ge 5 -and $parts[4] -match '^(\d+\.\d+)') { $short = $Matches[1] }
    $suffix = $(if ($short) { ' ({0})' -f $short } else { '' })
    if ($head -match '(?i)KB(\d{6,8})') { return ('KB' + $Matches[1]) }
    if ($head -match '(?i)RollupFix') { return ('Atualização cumulativa' + $suffix) }
    if ($head -match '(?i)ServicingStack') { return ('Pilha de manutenção' + $suffix) }
    if ($head -match '(?i)DotNetRollup') { return ('Atualização do .NET' + $suffix) }
    return ($head -replace '^(?i)Package_for_', '')
}

function ConvertTo-TIPackageStateText {
    param([string]$State)
    switch -regex ([string]$State) {
        '^(?i)installpending$'      { return 'Instalação pendente' }
        '^(?i)uninstallpending$'    { return 'Remoção pendente' }
        '^(?i)installed$'           { return 'Instalada' }
        '^(?i)partiallyinstalled$'  { return 'Instalada em parte' }
    }
    return [string]$State
}

function ConvertTo-TIReleaseTypeText {
    param([string]$Type)
    $map = @{ 'update' = 'Atualização'; 'securityupdate' = 'Segurança'; 'criticalupdate' = 'Crítica'; 'updaterollup' = 'Cumulativa'
              'hotfix' = 'Correção'; 'softwareupdate' = 'Atualização'; 'servicepack' = 'Service Pack'; 'driver' = 'Driver' }
    $k = ([string]$Type).ToLowerInvariant()
    if ($map.ContainsKey($k)) { return $map[$k] }
    return [string]$Type
}

# Saúde do disco para o card e o laudo. Tone: ok | warn | crit | none
function Get-TIRecoveryDiskVerdict {
    param([string]$Health = '', [string]$Operational = '', [int]$Wear = 0, [int64]$Uncorrected = 0, [int]$Temp = 0, [string]$Media = '')
    $crit = New-Object System.Collections.ArrayList
    $warn = New-Object System.Collections.ArrayList
    $h = ([string]$Health).Trim()
    if ($h -eq 'Unhealthy' -or $h -eq '2') { [void]$crit.Add('o Windows informa que o disco está com falha') }
    elseif ($h -eq 'Warning' -or $h -eq '1') { [void]$warn.Add('o Windows informa atenção na saúde do disco') }
    $op = [string]$Operational
    if ($op -match '(?i)predictive failure|failed|lost communication|not usable') { [void]$crit.Add(('estado: {0}' -f $op)) }
    elseif ($op -match '(?i)degraded|stressed|transient error|abnormal latency|io error') { [void]$warn.Add(('estado: {0}' -f $op)) }
    if ($Uncorrected -gt 0) { [void]$crit.Add($(if ($Uncorrected -eq 1) { '1 erro de leitura não corrigido' } else { '{0} erros de leitura não corrigidos' -f $Uncorrected })) }
    if ($Wear -ge 100) { [void]$crit.Add('SSD no fim da vida útil (100% de desgaste)') }
    elseif ($Wear -ge 90) { [void]$warn.Add(('SSD com {0}% de desgaste' -f $Wear)) }
    $lim = $(if ($Media -match 'NVMe') { 75 } elseif ($Media -match 'SSD') { 70 } else { 55 })
    if ($Temp -gt 0 -and $Temp -ge $lim) { [void]$warn.Add(('temperatura alta ({0} °C)' -f $Temp)) }
    $all = @($crit) + @($warn)
    if ($crit.Count -gt 0) { return [pscustomobject]@{ Tone = 'crit'; Text = ('Com falha: ' + ($all -join '; ') + '.') } }
    if ($warn.Count -gt 0) { return [pscustomobject]@{ Tone = 'warn'; Text = ('Atenção: ' + ($all -join '; ') + '.') } }
    if ($h -eq 'Healthy' -or $h -eq '0') { return [pscustomobject]@{ Tone = 'ok'; Text = 'Saudável' } }
    return [pscustomobject]@{ Tone = 'none'; Text = 'Saúde não informada pelo Windows' }
}

# --- Programas externos (chkdsk, sfc, dism, bcdboot) -----------------------
function Get-TIOemEncoding {
    try { return [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) } catch { }
    try { return [System.Text.Encoding]::GetEncoding(850) } catch { }
    return [System.Text.Encoding]::Default
}

# Mata o processo e os filhos (o dism.exe deixa o DismHost.exe trabalhando)
function Stop-TIProcessTree {
    param($Process)
    $id = 0
    try { $id = [int]$Process.Id } catch { return }
    $kids = New-Object System.Collections.ArrayList
    try {
        $all = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | Select-Object ProcessId, ParentProcessId)
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue($id)
        while ($queue.Count -gt 0) {
            $pp = [int]$queue.Dequeue()
            foreach ($x in $all) {
                $cid = [int]$x.ProcessId
                if ([int]$x.ParentProcessId -eq $pp -and $cid -ne $pp -and $cid -ne $id -and -not $kids.Contains($cid)) {
                    [void]$kids.Add($cid)
                    $queue.Enqueue($cid)
                }
            }
        }
    } catch { }
    try { $Process.Kill() } catch { }
    foreach ($k in $kids) { try { ([System.Diagnostics.Process]::GetProcessById($k)).Kill() } catch { } }
    try { [void]$Process.WaitForExit(5000) } catch { }
}

# Uma linha (ou segmento) da saída: progresso só move a barra; o resto vai ao console
function Write-TIToolSegment {
    param($State, [string]$Text, [bool]$Cr)
    $t = ([string]$Text).Trim()
    if (-not $t) { return }
    if (Test-TIProgressLine -Text $t -Cr $Cr) {
        $pct = Get-TIProgressPercent $t
        if ($pct -ne $State.LastPct) {
            $State.LastPct = $pct
            $g = [int]($State.From + ($State.To - $State.From) * $pct / 100)
            Emit $t 'Debug' $g
        }
        return
    }
    if ($t -eq $State.Prev) { return }
    $State.Prev = $t
    [void]$State.Lines.Add($t)
    $State.Count++
    Emit $t $(if ($State.Count -le $State.Max) { $State.Level } else { 'Debug' })
}

# Bytes lidos da saída: decide a codificação no primeiro pedaço e decodifica aos poucos
function Add-TIToolOutput {
    param($State, [byte[]]$Bytes, [int]$Count, [switch]$Final)
    $chunk = ''
    if (-not $State.Dec) {
        for ($i = 0; $i -lt $Count; $i++) { $State.Pend.Add($Bytes[$i]) }
        if ($State.Pend.Count -lt 2 -and -not $Final) { return }
        $arr = $State.Pend.ToArray()
        $State.Pend.Clear()
        $kind = Get-TIOutputEncodingKind -Bytes $arr
        $State.Enc = $(if ($kind -eq 'utf16') { [System.Text.Encoding]::Unicode } else { $State.Oem })
        $State.Dec = $State.Enc.GetDecoder()
        $start = 0
        if ($kind -eq 'utf16' -and $arr.Length -ge 2 -and $arr[0] -eq 0xFF -and $arr[1] -eq 0xFE) { $start = 2 }
        if ($arr.Length -gt $start) {
            $chars = New-Object char[] ($State.Enc.GetMaxCharCount($arr.Length) + 4)
            $nc = $State.Dec.GetChars($arr, $start, $arr.Length - $start, $chars, 0, $Final.IsPresent)
            $chunk = New-Object System.String -ArgumentList $chars, 0, $nc
        }
    } elseif ($Count -gt 0 -or $Final) {
        $chars = New-Object char[] ($State.Enc.GetMaxCharCount([Math]::Max(1, $Count)) + 4)
        $nc = $State.Dec.GetChars($Bytes, 0, $Count, $chars, 0, $Final.IsPresent)
        $chunk = New-Object System.String -ArgumentList $chars, 0, $nc
    }
    $State.Buf += $chunk
    $seg = Split-TIOutputSegments -Text $State.Buf -Final:$Final
    $State.Buf = $seg.Rest
    foreach ($s in $seg.Segments) { Write-TIToolSegment -State $State -Text $s.Text -Cr ([bool]$s.Cr) }
}

# Roda um programa com caminho completo, repassa a saída ao console (linhas de
# progresso só movem a barra entre -PctFrom e -PctTo), com tempo limite. Cancelar
# (BeginStop) ou estourar o tempo: o finally mata o programa e os filhos.
# Code = -1 quando não abriu, estourou o tempo ou foi interrompido.
function Invoke-TIToolRun {
    param(
        [Parameter(Mandatory)][string]$File,
        [string]$Arguments = '',
        [int]$TimeoutMin = 60,
        [int]$PctFrom = 0,
        [int]$PctTo = 100,
        [string]$Level = 'Info',
        [int]$MaxLines = 300
    )
    $res = [pscustomobject]@{ Code = -1; Output = ''; TimedOut = $false; Started = $false; Killed = $false; Error = '' }
    if (-not [System.IO.File]::Exists($File)) { $res.Error = ('programa não encontrado: {0}' -f $File); return $res }
    $st = @{
        Oem = (Get-TIOemEncoding); Enc = $null; Dec = $null; Buf = ''; LastPct = -1; Prev = ''; Count = 0
        Pend = (New-Object 'System.Collections.Generic.List[byte]'); Lines = (New-Object System.Collections.ArrayList)
        From = $PctFrom; To = $PctTo; Level = $Level; Max = $MaxLines
    }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = $File
    $p.StartInfo.Arguments = $Arguments
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.CreateNoWindow = $true
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    $p.StartInfo.RedirectStandardInput = $true
    try { $p.StartInfo.WorkingDirectory = [System.IO.Path]::GetDirectoryName($File) } catch { }
    try { $p.StartInfo.StandardErrorEncoding = $st.Oem } catch { }
    Emit ('Executando: {0} {1}' -f [System.IO.Path]::GetFileName($File), $Arguments) 'Debug'
    try {
        try { [void]$p.Start(); $res.Started = $true } catch { $res.Error = $_.Exception.Message; return $res }
        # sem entrada: uma pergunta (S/N) recebe fim de arquivo em vez de travar
        try { $p.StandardInput.Close() } catch { }
        $errTask = $p.StandardError.ReadToEndAsync()
        $stream = $p.StandardOutput.BaseStream
        $buf = New-Object byte[] 4096
        $task = $stream.ReadAsync($buf, 0, $buf.Length)
        $deadline = [datetime]::MaxValue
        if ($TimeoutMin -gt 0) { $deadline = (Get-Date).AddMinutes($TimeoutMin) }
        # espera em fatias curtas: o Cancelar consegue interromper
        while ($true) {
            if ($task) {
                $done = $false
                try { $done = $task.Wait(250) } catch { $task = $null }
                if ($done) {
                    $n = 0
                    try { $n = [int]$task.Result } catch { }
                    if ($n -gt 0) {
                        Add-TIToolOutput -State $st -Bytes $buf -Count $n
                        $task = $stream.ReadAsync($buf, 0, $buf.Length)
                    } else { $task = $null }
                }
            } elseif ($p.WaitForExit(250)) { break }
            if ((Get-Date) -gt $deadline) { $res.TimedOut = $true; break }
        }
        if (-not $res.TimedOut) {
            $p.WaitForExit()
            Add-TIToolOutput -State $st -Bytes $buf -Count 0 -Final
            $et = ''
            try { $et = [string]$errTask.Result } catch { }
            foreach ($l in @($et -split "`r?`n")) { Write-TIToolSegment -State $st -Text $l -Cr $false }
            $res.Code = [int]$p.ExitCode
        }
    } finally {
        if ($res.Started) {
            $alive = $false
            try { $alive = -not $p.HasExited } catch { }
            if ($alive) {
                Stop-TIProcessTree -Process $p
                $res.Killed = $true
                $res.Code = -1
                Emit ('{0} foi interrompido.' -f [System.IO.Path]::GetFileName($File)) 'Warn'
            }
        }
        try { $p.Dispose() } catch { }
    }
    $res.Output = ($st.Lines -join "`n")
    return $res
}

# --- Resultado das ações (vai para o laudo) --------------------------------
function New-TIRecoveryResult {
    param([string]$Action, [string]$Title, $Install)
    return [pscustomobject]@{
        Kind = 'RecoveryAction'; Action = $Action; Title = $Title
        Drive = $(if ($Install) { [string]$Install.Drive } else { '' })
        Started = (Get-Date); Steps = (New-Object System.Collections.ArrayList)
        Stopped = $false; StopReason = ''; HiberDiscarded = $false; Data = $null
    }
}

function Add-TIRecoveryStep {
    param($Result, [string]$Name, [string]$Level = 'Info', [string]$Text = '', $Code = $null, [switch]$NoEmit)
    [void]$Result.Steps.Add([pscustomobject]@{ When = (Get-Date); Name = $Name; Level = $Level; Text = $Text; Code = $Code })
    if (-not $NoEmit) { Emit ('{0}: {1}' -f $Name, $Text) $Level }
}

function Join-TILogSub {
    param([string]$LogDir, [string]$Sub)
    if (-not $LogDir) { return '' }
    return (Join-TIWinPath $LogDir $Sub)
}

function Get-TIDismLogArg {
    param([string]$LogDir)
    if (-not $LogDir) { return '' }
    return (' /LogPath:' + (Format-TIArgValue (Join-TIWinPath $LogDir ('dism-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss')))))
}

# --- Disco, hibernação, pendências e pasta temporária ------------------------
function Get-TIRecoveryDiskInfo {
    param([string]$Drive)
    $o = [pscustomobject]@{
        Drive = $Drive; Read = $false; Model = ''; Media = ''; SizeText = ''; Style = ''; Bus = ''
        Health = ''; Operational = ''; Temp = 0; Wear = 0; Uncorrected = 0; Hours = 0
        Tone = 'none'; Text = 'Não foi possível ler a saúde do disco'
    }
    try {
        $p = Get-Partition -DriveLetter ($Drive.Substring(0, 1)) -ErrorAction Stop
        $dk = Get-Disk -Number $p.DiskNumber -ErrorAction Stop
        $o.Style = [string]$dk.PartitionStyle
        $o.Bus = [string]$dk.BusType
        $o.Model = ([string]$dk.FriendlyName).Trim()
        $o.SizeText = Format-TIDiskSize ([double]$dk.Size)
        $o.Health = [string]$dk.HealthStatus
        $o.Operational = (@($dk.OperationalStatus) -join ', ')
        $o.Media = ConvertTo-TIMediaWord '' $dk.BusType
        $pd = $null
        try { $pd = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$dk.Number }) | Select-Object -First 1 } catch { }
        if ($pd) {
            $o.Health = [string]$pd.HealthStatus
            $o.Operational = (@($pd.OperationalStatus) -join ', ')
            $o.Media = ConvertTo-TIMediaWord $pd.MediaType $pd.BusType
            if ($pd.FriendlyName) { $o.Model = ([string]$pd.FriendlyName).Trim() }
            $rel = $null
            try { $rel = Get-StorageReliabilityCounter -PhysicalDisk $pd -ErrorAction Stop } catch { }
            if ($rel) {
                try { $o.Temp = [int]$rel.Temperature } catch { }
                try { $o.Wear = [int]$rel.Wear } catch { }
                try { $o.Uncorrected = [int64]$rel.ReadErrorsUncorrected } catch { }
                try { $o.Hours = [int64]$rel.PowerOnHours } catch { }
            }
        }
        $o.Read = $true
        $v = Get-TIRecoveryDiskVerdict -Health $o.Health -Operational $o.Operational -Wear $o.Wear -Uncorrected $o.Uncorrected -Temp $o.Temp -Media $o.Media
        $o.Tone = $v.Tone
        $o.Text = $v.Text
    } catch {
        Emit ('Saúde do disco de {0}: {1}' -f $Drive, $_.Exception.Message) 'Debug'
    }
    return $o
}

# Windows desligado com hibernação/Inicialização rápida: a sessão hibernada é
# descartada antes de mexer no disco (senão ele "volta" para um disco que mudou)
function Remove-TIHibernation {
    param($Install, $Result)
    $f = [string]$Install.Root + 'hiberfil.sys'
    if (-not [System.IO.File]::Exists($f)) { return }
    if (-not (Test-TIHibernated -Root ([string]$Install.Root))) { return }
    try {
        [System.IO.File]::SetAttributes($f, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::Delete($f)
        $Result.HiberDiscarded = $true
        Add-TIRecoveryStep $Result 'Hibernação' 'Info' 'A sessão hibernada (Inicialização rápida) foi descartada: o Windows fará uma inicialização completa.'
    } catch {
        Add-TIRecoveryStep $Result 'Hibernação' 'Warn' ('Não foi possível descartar a sessão hibernada ({0}). Se ao ligar o Windows oferecer "Excluir dados de restauração e continuar", escolha essa opção.' -f $_.Exception.Message)
    }
}

function Test-TIPendingActions {
    param($Install)
    try { return [System.IO.File]::Exists((Join-TIWinPath ([string]$Install.WinDir) 'WinSxS\pending.xml')) } catch { return $false }
}

# Pasta temporária do DISM no próprio disco do Windows (a do WinPE tem só 512 MB)
function New-TIScratchDir {
    param($Install)
    $p = [string]$Install.Root + '$TI-Scratch'
    if ([System.IO.Directory]::Exists($p)) { Clear-TISafeFolder -Path $p }
    [void][System.IO.Directory]::CreateDirectory($p)
    return $p
}

function Remove-TIScratchDir {
    param([string]$Path)
    if (-not $Path) { return }
    try {
        if ([System.IO.Directory]::Exists($Path)) {
            Clear-TISafeFolder -Path $Path
            [System.IO.Directory]::Delete($Path, $false)
        }
    } catch {
        Emit ('Não foi possível apagar a pasta temporária {0}: {1}' -f $Path, $_.Exception.Message) 'Warn'
    }
}

# --- Partição do sistema e BCD ---------------------------------------------
# GPT: a partição EFI do mesmo disco (ou de outro disco interno, nunca USB);
# MBR: a ativa ("Reservado pelo sistema") ou, sem nenhuma ativa, a do Windows.
function Find-TISystemPartition {
    param([string]$Drive)
    $esp = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
    $l = (ConvertTo-TIDriveLetter $Drive).Substring(0, 1)
    $wp = Get-Partition -DriveLetter $l -ErrorAction Stop
    $disk = Get-Disk -Number $wp.DiskNumber -ErrorAction Stop
    $style = ([string]$disk.PartitionStyle).ToUpperInvariant()
    $parts = @(Get-Partition -DiskNumber $wp.DiskNumber -ErrorAction Stop)
    $pick = $null; $kind = ''; $needsActive = $false
    if ($style -eq 'GPT') {
        $pick = @($parts | Where-Object { ([string]$_.GptType) -eq $esp }) | Select-Object -First 1
        if (-not $pick) {
            foreach ($dk in @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.Number -ne $disk.Number -and ([string]$_.PartitionStyle) -eq 'GPT' -and (Test-TIInternalDisk $_) })) {
                $pick = @(Get-Partition -DiskNumber $dk.Number -ErrorAction SilentlyContinue | Where-Object { ([string]$_.GptType) -eq $esp }) | Select-Object -First 1
                if ($pick) { break }
            }
        }
        if (-not $pick) { throw 'A partição EFI do sistema não foi encontrada neste disco: o reparo automático da inicialização não é possível (é preciso recriar a partição EFI com o diskpart).' }
        $kind = 'partição EFI'
    } elseif ($style -eq 'MBR') {
        $pick = @($parts | Where-Object { $_.IsActive }) | Select-Object -First 1
        $kind = 'partição ativa'
        if (-not $pick) { $pick = $wp; $kind = 'partição do Windows'; $needsActive = $true }
    } else {
        throw ('Estilo de partição não reconhecido no disco {0}.' -f $disk.Number)
    }
    $letter = ''
    if (([string]$pick.DriveLetter) -match '^[A-Za-z]$') { $letter = ([string]$pick.DriveLetter).ToUpperInvariant() + ':' }
    $vp = @(@($pick.AccessPaths) | Where-Object { [string]$_ -like '\\?\Volume*' }) | Select-Object -First 1
    return [pscustomobject]@{
        DiskNumber = [int]$pick.DiskNumber; PartitionNumber = [int]$pick.PartitionNumber; Style = $style
        KindText = $kind; Letter = $letter; VolumePath = [string]$vp; NeedsActive = $needsActive
    }
}

function Get-TIUsedDriveLetters {
    $u = New-Object System.Collections.ArrayList
    try { foreach ($d in [System.IO.DriveInfo]::GetDrives()) { [void]$u.Add((ConvertTo-TIDriveLetter $d.Name)) } } catch { }
    try {
        foreach ($p in @(Get-Partition -ErrorAction Stop)) {
            $l = [string]$p.DriveLetter
            if ($l -match '^[A-Za-z]$') { [void]$u.Add($l.ToUpperInvariant() + ':') }
        }
    } catch { }
    try {
        foreach ($v in @(Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop)) {
            $l = ConvertTo-TIDriveLetter ([string]$v.DriveLetter)
            if ($l) { [void]$u.Add($l) }
        }
    } catch { }
    return $u.ToArray()
}

# -Mount é criado por quem chama ANTES do try ({ Part; Letter; Added }): mesmo
# cancelando no meio, o finally sabe que a letra foi dada e a tira.
function Mount-TISystemPartition {
    param($Mount)
    $part = $Mount.Part
    if ($part.Letter) { $Mount.Letter = $part.Letter; return }
    $L = Select-TIFreeDriveLetter -Used (Get-TIUsedDriveLetters)
    if (-not $L) { throw 'Não há letra de unidade livre para abrir a partição do sistema.' }
    $Mount.Letter = $L
    $err = ''
    $Mount.Added = $true
    $done = $false
    try {
        Add-PartitionAccessPath -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath ($L + '\') -ErrorAction Stop
        $Mount.Method = 'partition'
        $done = $true
    } catch { $err = $_.Exception.Message }
    if (-not $done -and $part.VolumePath) {
        $r = Invoke-TICommand -File (Join-TIWinPath (Get-TISystem32) 'mountvol.exe') -Arguments ('{0} {1}' -f $L, $part.VolumePath) -TimeoutSec 30
        if ($r.Code -eq 0) { $Mount.Method = 'mountvol'; $done = $true }
        else { $err = ('{0} / mountvol: {1}' -f $err, (Get-TIOutputTail $r.Output)).Trim() }
    }
    if (-not $done) {
        $Mount.Added = $false
        throw ('Não foi possível dar uma letra à partição do sistema ({0}).' -f $err)
    }
    for ($i = 0; $i -lt 20 -and -not [System.IO.Directory]::Exists($L + '\'); $i++) { [System.Threading.Thread]::Sleep(250) }
    Emit ('Partição do sistema aberta temporariamente como {0}.' -f $L) 'Debug'
}

function Dismount-TISystemPartition {
    param($Mount)
    if (-not $Mount -or -not $Mount.Added -or -not $Mount.Letter) { return }
    $L = [string]$Mount.Letter
    $part = $Mount.Part
    try { Remove-PartitionAccessPath -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath ($L + '\') -ErrorAction Stop } catch { }
    if ([System.IO.Directory]::Exists($L + '\')) {
        try { [void](Invoke-TICommand -File (Join-TIWinPath (Get-TISystem32) 'mountvol.exe') -Arguments ('{0} /d' -f $L) -TimeoutSec 30) } catch { }
    }
    if ([System.IO.Directory]::Exists($L + '\')) {
        Emit ('A letra temporária {0} da partição do sistema continua montada (some ao reiniciar). Não grave arquivos nela.' -f $L) 'Warn'
    } else {
        $Mount.Added = $false
        Emit ('Letra temporária {0} removida.' -f $L) 'Debug'
    }
}

# Cópia do BCD (UEFI e/ou BIOS) para logs\bcd-backup\<data>. Sem a cópia, nada muda.
function Backup-TIBcdStores {
    param([string]$Letter, [string]$BackupDir)
    $src = @(Get-TIBcdStorePaths -Letter $Letter -Target 'ALL' | Where-Object { [System.IO.File]::Exists($_) })
    if ($src.Count -eq 0) { Emit 'Não havia BCD na partição do sistema (nada para copiar).' 'Info'; return @() }
    if (-not $BackupDir) { throw 'Pasta de logs indisponível: sem a cópia do BCD a inicialização não é alterada.' }
    $dest = Join-TIWinPath $BackupDir (Get-Date -Format 'yyyyMMdd-HHmmss')
    [void][System.IO.Directory]::CreateDirectory($dest)
    $out = @()
    foreach ($s in $src) {
        $d = Join-TIWinPath $dest ($s.Substring(3) -replace '\\', '-')
        [System.IO.File]::Copy($s, $d, $true)
        $out += $d
    }
    Emit ('Cópia do BCD guardada em {0}' -f $dest) 'Info'
    return $out
}

function Invoke-TIBootStep {
    param($Install, $Result, [string]$Firmware = '', [string]$BackupDir = '', [int]$PctFrom = 0, [int]$PctTo = 100)
    $name = 'Reparar inicialização (bcdboot)'
    Emit ('{0}: procurando a partição do sistema...' -f $name) 'Info' $PctFrom
    $sp = $null
    try { $sp = Find-TISystemPartition -Drive $Install.Drive }
    catch { Add-TIRecoveryStep $Result $name 'Error' $_.Exception.Message; return $false }
    $target = Get-TIBcdbootTarget -Firmware $Firmware -PartitionStyle $sp.Style
    Emit ('Disco {0} ({1}), {2}; firmware {3}; arquivos de boot: {4}.' -f $sp.DiskNumber, $sp.Style, $sp.KindText, $(if ($Firmware) { $Firmware } else { 'não identificado' }), $target) 'Info'
    $mount = [pscustomobject]@{ Part = $sp; Letter = ''; Added = $false; Method = '' }
    try {
        Mount-TISystemPartition -Mount $mount
        [void](Backup-TIBcdStores -Letter $mount.Letter -BackupDir $BackupDir)
        if ($sp.NeedsActive) {
            Set-Partition -DiskNumber $sp.DiskNumber -PartitionNumber $sp.PartitionNumber -IsActive $true -ErrorAction Stop
            Emit 'Não havia partição ativa no disco: a partição do Windows foi marcada como ativa.' 'Info'
        }
        $loc = ''
        $res = $(if ($target -eq 'BIOS') { 'Boot\PCAT\pt-BR' } else { 'Boot\EFI\pt-BR' })
        if ([System.IO.Directory]::Exists((Join-TIWinPath $Install.WinDir $res))) { $loc = 'pt-BR' }
        $a = Get-TIBcdbootArgs -WinDir $Install.WinDir -Letter $mount.Letter -Target $target -Locale $loc
        $r = Invoke-TIToolRun -File (Join-TIWinPath (Get-TISystem32) 'bcdboot.exe') -Arguments $a -TimeoutMin 10 -PctFrom $PctFrom -PctTo $PctTo
        if ($r.Started -and -not $r.TimedOut -and -not $r.Killed -and $r.Code -eq 0) {
            Add-TIRecoveryStep $Result $name 'Success' ('Arquivos de inicialização recriados na {0} ({1}).' -f $sp.KindText, $target) 0
            return $true
        }
        $why = $(if (-not $r.Started) { $r.Error } elseif ($r.TimedOut) { 'tempo esgotado' } else { Get-TIOutputTail $r.Output })
        Add-TIRecoveryStep $Result $name 'Error' ('O bcdboot falhou (código {0}): {1}. A cópia do BCD anterior está em logs\bcd-backup.' -f $r.Code, $why) $r.Code
        return $false
    } catch {
        Add-TIRecoveryStep $Result $name 'Error' $_.Exception.Message
        return $false
    } finally {
        Dismount-TISystemPartition -Mount $mount
    }
}

# Estado do modo de segurança em cada BCD da partição do sistema
function Get-TISafeModeInfo {
    param($Install, [string]$Letter)
    $bcdedit = Join-TIWinPath (Get-TISystem32) 'bcdedit.exe'
    $out = @()
    foreach ($s in @(Get-TIBcdStorePaths -Letter $Letter -Target 'ALL')) {
        if (-not [System.IO.File]::Exists($s)) { continue }
        $r = Invoke-TICommand -File $bcdedit -Arguments ('/store "{0}" /enum osloader /v' -f $s) -TimeoutSec 30
        $info = Get-TIBcdLoaderInfo -Text ([string]$r.Output) -Drive ([string]$Install.Drive)
        if (-not $info.Id) { Emit ('{0}: entrada deste Windows não encontrada ({1} entrada(s) do Windows).' -f $s, $info.Count) 'Debug' }
        $out += [pscustomobject]@{ Store = $s; Id = $info.Id; SafeBoot = $info.SafeBoot }
    }
    return $out
}

function Invoke-TISafeModeStep {
    param($Install, $Result, [string]$Mode = 'read', [string]$BackupDir = '')
    $name = 'Modo de segurança'
    $sp = Find-TISystemPartition -Drive $Install.Drive
    $mount = [pscustomobject]@{ Part = $sp; Letter = ''; Added = $false; Method = '' }
    try {
        Mount-TISystemPartition -Mount $mount
        $st = @(Get-TISafeModeInfo -Install $Install -Letter $mount.Letter | Where-Object { $_.Id })
        if ($st.Count -eq 0) { throw 'A entrada de inicialização deste Windows não foi encontrada no BCD: rode Reparar inicialização antes.' }
        $cur = @($st | Where-Object { $_.SafeBoot } | ForEach-Object { $_.SafeBoot }) | Select-Object -First 1
        $Result.Data = [pscustomobject]@{ On = [bool]$cur; SafeBoot = [string]$cur; Stores = $st.Count }
        if ($Mode -eq 'read') {
            Emit ('Modo de segurança neste Windows: {0}.' -f $(if ($cur) { 'LIGADO (' + $cur + ')' } else { 'desligado' })) 'Info'
            return
        }
        [void](Backup-TIBcdStores -Letter $mount.Letter -BackupDir $BackupDir)
        $bcdedit = Join-TIWinPath (Get-TISystem32) 'bcdedit.exe'
        $fail = 0; $n = 0
        foreach ($s in $st) {
            if ($Mode -eq 'off' -and -not $s.SafeBoot) { continue }
            $n++
            $a = $(if ($Mode -eq 'on') { '/store "{0}" /set {1} safeboot minimal' -f $s.Store, $s.Id } else { '/store "{0}" /deletevalue {1} safeboot' -f $s.Store, $s.Id })
            $r = Invoke-TICommand -File $bcdedit -Arguments $a -TimeoutSec 30
            if ($r.Code -ne 0) { $fail++; Emit ('bcdedit: {0}' -f (Get-TIOutputTail $r.Output)) 'Warn' }
        }
        if ($fail -gt 0) {
            Add-TIRecoveryStep $Result $name 'Error' ('O bcdedit falhou em {0} de {1} BCD(s); a cópia anterior está em logs\bcd-backup.' -f $fail, $n)
            return
        }
        if ($Mode -eq 'on') {
            $Result.Data.On = $true
            Add-TIRecoveryStep $Result $name 'Success' 'Ligado: o Windows vai iniciar no modo de segurança (mínimo) até ser desligado aqui ou pelo msconfig.'
        } else {
            $Result.Data.On = $false
            Add-TIRecoveryStep $Result $name 'Success' 'Desligado: o Windows volta a iniciar normalmente.'
        }
    } finally {
        Dismount-TISystemPartition -Mount $mount
    }
}

# --- Disco, SFC e DISM -------------------------------------------------------
function Invoke-TIChkdskStep {
    param($Install, $Result, [switch]$Full, [int]$PctFrom = 0, [int]$PctTo = 100)
    $name = $(if ($Full) { 'Verificar disco (chkdsk /r)' } else { 'Verificar disco (chkdsk /f)' })
    Emit ('{0}: verificando {1}...' -f $name, $Install.Drive) 'Info' $PctFrom
    # /x desmonta a unidade antes (nada do Windows dela está em uso aqui)
    $a = '{0} {1} /x' -f $Install.Drive, $(if ($Full) { '/r' } else { '/f' })
    $r = Invoke-TIToolRun -File (Join-TIWinPath (Get-TISystem32) 'chkdsk.exe') -Arguments $a -TimeoutMin $(if ($Full) { 2880 } else { 360 }) -PctFrom $PctFrom -PctTo $PctTo
    $code = $(if ($r.Started -and -not $r.TimedOut -and -not $r.Killed) { $r.Code } else { -1 })
    $info = Get-TIChkdskResult -ExitCode $code
    $txt = $info.Text
    if (-not $r.Started -and $r.Error) { $txt = ('Não foi possível abrir o chkdsk: {0}' -f $r.Error) }
    elseif ($r.TimedOut) { $txt = 'Tempo esgotado. ' + $txt }
    Add-TIRecoveryStep $Result $name $info.Level $txt $code
    return [pscustomobject]@{ Stop = $info.Stop; Text = $txt; Ok = $info.Ok }
}

function Invoke-TISfcStep {
    param($Install, $Result, [string]$LogDir = '', [int]$PctFrom = 0, [int]$PctTo = 100, [switch]$Again)
    $name = $(if ($Again) { 'Reparar arquivos do sistema (SFC, de novo)' } else { 'Reparar arquivos do sistema (SFC)' })
    Emit ('{0}: conferindo os arquivos protegidos do Windows (10 a 30 minutos)...' -f $name) 'Info' $PctFrom
    $a = '/scannow /offbootdir={0} /offwindir={1}' -f $Install.Root, $Install.WinDir
    $log = ''
    if ($LogDir) {
        $log = Join-TIWinPath $LogDir ('sfc-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $a += ' /offlogfile=' + (Format-TIArgValue $log)
    }
    $r = Invoke-TIToolRun -File (Join-TIWinPath (Get-TISystem32) 'sfc.exe') -Arguments $a -TimeoutMin 180 -PctFrom $PctFrom -PctTo $PctTo
    $code = $(if ($r.Started -and -not $r.TimedOut -and -not $r.Killed) { $r.Code } else { -1 })
    $info = Get-TISfcResult -ExitCode $code -Output $r.Output
    $txt = $info.Text
    if (-not $r.Started -and $r.Error) { $txt = ('Não foi possível abrir o SFC: {0}' -f $r.Error) }
    elseif ($r.TimedOut) { $txt = 'Tempo esgotado (3 horas). ' + $txt }
    if ($log -and [System.IO.File]::Exists($log)) { $txt += (' Log: {0}' -f $log) }
    Add-TIRecoveryStep $Result $name $info.Level $txt $code
    return $info
}

# Imagens (install.wim / install.esd) da pasta reparo\ do pendrive, com versão e edição
function Get-TIRepairImages {
    param([string]$Dir)
    $out = New-Object System.Collections.ArrayList
    if (-not $Dir -or -not [System.IO.Directory]::Exists($Dir)) { return @() }
    $files = @(Get-TISafeFiles -Path $Dir -Filter '*.wim') + @(Get-TISafeFiles -Path $Dir -Filter '*.esd')
    foreach ($f in $files) {
        $idx = @()
        try { $idx = @(Get-WindowsImage -ImagePath $f -ErrorAction Stop) }
        catch { Emit ('Não foi possível ler a imagem {0}: {1}' -f $f, $_.Exception.Message) 'Warn'; continue }
        foreach ($i in $idx) {
            try {
                $d = Get-WindowsImage -ImagePath $f -Index ([int]$i.ImageIndex) -ErrorAction Stop
                $build = 0
                try { $build = [int]$d.Build } catch { }
                if ($build -le 0 -and ([string]$d.Version) -match '^\d+\.\d+\.(\d+)') { $build = [int]$Matches[1] }
                [void]$out.Add([pscustomobject]@{
                    Path = $f; Index = [int]$i.ImageIndex; Name = [string]$d.ImageName; EditionId = [string]$d.EditionId
                    Build = $build; Arch = (ConvertTo-TIArchName $d.Architecture); Version = [string]$d.Version
                })
            } catch { }
        }
    }
    return $out.ToArray()
}

# DISM ScanHealth e, havendo defeito e uma imagem da mesma versão no pendrive,
# RestoreHealth com /LimitAccess (sem internet). Saída técnica só em Detalhes.
function Invoke-TIDismStep {
    param($Install, $Result, [string]$Scratch, [string]$LogDir = '', [string]$AppRoot = '', [int]$PctFrom = 0, [int]$PctTo = 100, [switch]$AllowRestore)
    $dism = Join-TIWinPath (Get-TISystem32) 'dism.exe'
    $out = [pscustomobject]@{ Kind = ''; Restored = $false }
    $mid = [int]($PctFrom + ($PctTo - $PctFrom) / 3)
    $name = 'Verificar a imagem do Windows (DISM ScanHealth)'
    Emit ('{0}: pode levar de 5 a 20 minutos...' -f $name) 'Info' $PctFrom
    $a = '/Image:{0} /Cleanup-Image /ScanHealth /ScratchDir:{1} /English{2}' -f $Install.Root, (Format-TIArgValue $Scratch), (Get-TIDismLogArg $LogDir)
    $r = Invoke-TIToolRun -File $dism -Arguments $a -TimeoutMin 120 -PctFrom $PctFrom -PctTo $mid -Level 'Debug'
    $code = $(if ($r.Started -and -not $r.TimedOut -and -not $r.Killed) { $r.Code } else { -1 })
    $info = Get-TIDismResult -ExitCode $code -Output $r.Output
    Add-TIRecoveryStep $Result $name $info.Level $info.Text $code
    $out.Kind = $info.Kind
    if ($info.Kind -ne 'repairable' -or -not $AllowRestore) { return $out }

    $rname = 'Reparar a imagem do Windows (DISM RestoreHealth)'
    $dir = $(if ($AppRoot) { Join-TIWinPath $AppRoot 'reparo' } else { '' })
    $images = @(Get-TIRepairImages -Dir $dir)
    $pick = Select-TIRepairImage -Images $images -Build ([int]$Install.Build) -EditionId ([string]$Install.EditionId) -Arch ([string]$Install.Arch)
    if (-not $pick) {
        $have = $(if ($images.Count -gt 0) {
            ('Há {0} imagem(ns) na pasta reparo\, mas nenhuma é da mesma versão e edição (build {1}, {2}). ' -f $images.Count, $Install.Build, $(if ($Install.Edition) { $Install.Edition } else { 'edição desconhecida' }))
        } else { 'Não há imagem na pasta reparo\ do pendrive. ' })
        $txt = $have + ('O SFC usa o próprio Windows como fonte; para o DISM completar o reparo, copie o install.wim (ou install.esd) do ISO oficial da MESMA versão ({0}) para a pasta reparo\ do pendrive e rode de novo. É só fonte de reparo: nada é reinstalado.' -f $Install.Label)
        Add-TIRecoveryStep $Result $rname 'Warn' $txt
        return $out
    }
    $same = ([int]$pick.Build -eq [int]$Install.Build)
    Emit ('Fonte de reparo: {0}, índice {1} ({2}, build {3}{4}).' -f $pick.Path, $pick.Index, $pick.Name, $pick.Build, $(if ($same) { '' } else { ', mesma base' })) 'Info'
    if ([double]$Install.FreeBytes -gt 0 -and [double]$Install.FreeBytes -lt 3GB) {
        Emit ('Pouco espaço livre em {0}: o reparo do DISM pode falhar por falta de espaço.' -f $Install.Drive) 'Warn'
    }
    $a2 = '/Image:{0} /Cleanup-Image /RestoreHealth {1} /LimitAccess /ScratchDir:{2} /English{3}' -f $Install.Root, (Get-TIDismSourceArg -Path $pick.Path -Index $pick.Index), (Format-TIArgValue $Scratch), (Get-TIDismLogArg $LogDir)
    Emit ('{0}: pode levar de 10 a 40 minutos...' -f $rname) 'Info' $mid
    $r2 = Invoke-TIToolRun -File $dism -Arguments $a2 -TimeoutMin 240 -PctFrom $mid -PctTo $PctTo -Level 'Debug'
    $code2 = $(if ($r2.Started -and -not $r2.TimedOut -and -not $r2.Killed) { $r2.Code } else { -1 })
    $info2 = Get-TIDismResult -ExitCode $code2 -Output $r2.Output
    $txt2 = $(if ($info2.Ok) { 'Repositório de componentes reparado com a imagem da pasta reparo\.' + $(if ($info2.Reboot) { ' O Windows termina ao ligar.' } else { '' }) } else { $info2.Text })
    Add-TIRecoveryStep $Result $rname $(if ($info2.Ok) { 'Success' } else { 'Error' }) $txt2 $code2
    $out.Restored = $info2.Ok
    return $out
}

function Invoke-TIRevertStep {
    param($Install, $Result, [string]$Scratch, [string]$LogDir = '', [int]$PctFrom = 0, [int]$PctTo = 100)
    $name = 'Desfazer ações pendentes (DISM RevertPendingActions)'
    Emit ('{0}...' -f $name) 'Info' $PctFrom
    $a = '/Image:{0} /Cleanup-Image /RevertPendingActions /ScratchDir:{1} /English{2}' -f $Install.Root, (Format-TIArgValue $Scratch), (Get-TIDismLogArg $LogDir)
    $r = Invoke-TIToolRun -File (Join-TIWinPath (Get-TISystem32) 'dism.exe') -Arguments $a -TimeoutMin 120 -PctFrom $PctFrom -PctTo $PctTo -Level 'Debug'
    $code = $(if ($r.Started -and -not $r.TimedOut -and -not $r.Killed) { $r.Code } else { -1 })
    $info = Get-TIDismResult -ExitCode $code -Output $r.Output
    $txt = $(if ($info.Ok) { 'Atualizações pendentes desfeitas. Ao ligar, o Windows termina a limpeza (pode reiniciar uma vez).' } else { $info.Text })
    Add-TIRecoveryStep $Result $name $(if ($info.Ok) { 'Success' } else { 'Error' }) $txt $code
    return $info.Ok
}

function Invoke-TIPackageRemoveStep {
    param($Install, $Result, [string]$PackageName, [string]$Scratch, [string]$LogDir = '')
    if ($PackageName -notmatch '^[A-Za-z0-9_.~\-]+$') { throw 'Nome de pacote inválido.' }
    $name = ('Remover atualização {0}' -f (Get-TIPackageDisplayName $PackageName))
    Emit ('{0}...' -f $name) 'Info' 5
    $a = '/Image:{0} /Remove-Package /PackageName:{1} /ScratchDir:{2} /English{3}' -f $Install.Root, $PackageName, (Format-TIArgValue $Scratch), (Get-TIDismLogArg $LogDir)
    $r = Invoke-TIToolRun -File (Join-TIWinPath (Get-TISystem32) 'dism.exe') -Arguments $a -TimeoutMin 120 -Level 'Debug'
    $code = $(if ($r.Started -and -not $r.TimedOut -and -not $r.Killed) { $r.Code } else { -1 })
    $info = Get-TIDismResult -ExitCode $code -Output $r.Output
    $txt = $(if ($info.Ok) { 'Atualização removida.' + $(if ($info.Reboot) { ' O Windows termina a remoção ao ligar.' } else { '' }) } else { $info.Text })
    Add-TIRecoveryStep $Result $name $(if ($info.Ok) { 'Success' } else { 'Error' }) $txt $code
}

function Invoke-TIDriverRemoveStep {
    param($Install, $Result, [string]$Driver, [string]$Scratch, [string]$LogDir = '')
    if ($Driver -notmatch '^(?i)oem\d+\.inf$') { throw 'Só drivers de terceiros (oemNN.inf) podem ser removidos.' }
    $name = ('Remover driver {0}' -f $Driver)
    Emit ('{0}...' -f $name) 'Info' 5
    $a = '/Image:{0} /Remove-Driver /Driver:{1} /ScratchDir:{2} /English{3}' -f $Install.Root, $Driver, (Format-TIArgValue $Scratch), (Get-TIDismLogArg $LogDir)
    $r = Invoke-TIToolRun -File (Join-TIWinPath (Get-TISystem32) 'dism.exe') -Arguments $a -TimeoutMin 60 -Level 'Debug'
    $code = $(if ($r.Started -and -not $r.TimedOut -and -not $r.Killed) { $r.Code } else { -1 })
    $info = Get-TIDismResult -ExitCode $code -Output $r.Output
    $txt = $(if ($info.Ok) { 'Driver removido. O Windows usa um driver genérico no lugar.' } else { $info.Text })
    Add-TIRecoveryStep $Result $name $(if ($info.Ok) { 'Success' } else { 'Error' }) $txt $code
}

# Reparo automático: disco, inicialização, pendências, SFC, DISM. Para no primeiro
# passo que exige decisão do técnico (disco que o chkdsk não conseguiu corrigir).
function Invoke-TIAutoRepair {
    param($Install, $Result, $Ctx)
    $logDir = [string]$Ctx.LogDir
    Emit ('Reparo automático: {0} em {1}.' -f $Install.Label, $Install.Drive) 'Info' 1
    $ck = Invoke-TIChkdskStep -Install $Install -Result $Result -PctFrom 1 -PctTo 30
    if ($ck.Stop) {
        $Result.Stopped = $true
        $Result.StopReason = ('Parou na verificação do disco: {0}' -f $ck.Text)
        Emit ('Reparo automático interrompido: {0}' -f $Result.StopReason) 'Warn'
        return
    }
    [void](Invoke-TIBootStep -Install $Install -Result $Result -Firmware ([string]$Ctx.Firmware) -BackupDir (Join-TILogSub $logDir 'bcd-backup') -PctFrom 30 -PctTo 35)
    $scratch = $null
    try {
        $scratch = New-TIScratchDir -Install $Install
        if (Test-TIPendingActions -Install $Install) {
            [void](Invoke-TIRevertStep -Install $Install -Result $Result -Scratch $scratch -LogDir $logDir -PctFrom 35 -PctTo 45)
        } else {
            Add-TIRecoveryStep $Result 'Atualizações pendentes' 'Success' 'Nenhuma atualização pendente.'
        }
        $sfc = Invoke-TISfcStep -Install $Install -Result $Result -LogDir $logDir -PctFrom 45 -PctTo 70
        $d = Invoke-TIDismStep -Install $Install -Result $Result -Scratch $scratch -LogDir $logDir -AppRoot ([string]$Ctx.AppRoot) -PctFrom 70 -PctTo 95 -AllowRestore
        if ($d.Restored -and @('partial', 'failed') -contains [string]$sfc.Kind) {
            [void](Invoke-TISfcStep -Install $Install -Result $Result -LogDir $logDir -PctFrom 95 -PctTo 99 -Again)
        }
    } finally {
        Remove-TIScratchDir -Path $scratch
    }
    Emit 'Reparo automático concluído: confira o resumo e o laudo.' 'Info' 100
}

# Ponto de entrada das ações de reparo (uma tarefa por ação)
function Invoke-TIRecoveryAction {
    param($Ctx)
    $inst = $Ctx.Install
    $act = [string]$Ctx.Action
    $res = New-TIRecoveryResult -Action $act -Title ([string]$Ctx.Title) -Install $inst
    $logDir = [string]$Ctx.LogDir
    $bcdDir = Join-TILogSub $logDir 'bcd-backup'
    $scratch = $null
    try {
        Assert-TIOfflineInstall $inst
        if (-not (Clear-TIOfflineHives)) { throw 'Há um registro offline aberto que não fechou: reinicie o pendrive antes de reparar.' }
        if ($act -ne 'safemode-read' -and $inst.Hibernated) { Remove-TIHibernation -Install $inst -Result $res }
        switch ($act) {
            'auto'   { Invoke-TIAutoRepair -Install $inst -Result $res -Ctx $Ctx }
            'boot'   { [void](Invoke-TIBootStep -Install $inst -Result $res -Firmware ([string]$Ctx.Firmware) -BackupDir $bcdDir) }
            'chkdsk' { [void](Invoke-TIChkdskStep -Install $inst -Result $res -Full:([bool]$Ctx.Full)) }
            'sfc' {
                $sfc = Invoke-TISfcStep -Install $inst -Result $res -LogDir $logDir -PctFrom 0 -PctTo 50
                $scratch = New-TIScratchDir -Install $inst
                $d = Invoke-TIDismStep -Install $inst -Result $res -Scratch $scratch -LogDir $logDir -AppRoot ([string]$Ctx.AppRoot) -PctFrom 50 -PctTo 95 -AllowRestore
                if ($d.Restored -and @('partial', 'failed') -contains [string]$sfc.Kind) {
                    [void](Invoke-TISfcStep -Install $inst -Result $res -LogDir $logDir -PctFrom 95 -PctTo 99 -Again)
                }
            }
            'revert' {
                $scratch = New-TIScratchDir -Install $inst
                [void](Invoke-TIRevertStep -Install $inst -Result $res -Scratch $scratch -LogDir $logDir)
            }
            'pkgremove' {
                $scratch = New-TIScratchDir -Install $inst
                Invoke-TIPackageRemoveStep -Install $inst -Result $res -PackageName ([string]$Ctx.PackageName) -Scratch $scratch -LogDir $logDir
            }
            'drvremove' {
                $scratch = New-TIScratchDir -Install $inst
                Invoke-TIDriverRemoveStep -Install $inst -Result $res -Driver ([string]$Ctx.Driver) -Scratch $scratch -LogDir $logDir
            }
            'safemode-read' { Invoke-TISafeModeStep -Install $inst -Result $res -Mode 'read' }
            'safemode-on'   { Invoke-TISafeModeStep -Install $inst -Result $res -Mode 'on' -BackupDir $bcdDir }
            'safemode-off'  { Invoke-TISafeModeStep -Install $inst -Result $res -Mode 'off' -BackupDir $bcdDir }
            default { throw ('Ação desconhecida: {0}' -f $act) }
        }
    } catch {
        Add-TIRecoveryStep $res $(if ($res.Title) { $res.Title } else { 'Recuperação' }) 'Error' $_.Exception.Message
    } finally {
        if ($scratch) { Remove-TIScratchDir -Path $scratch }
    }
    return $res
}

# --- Leituras: Windows, atualizações e drivers ---------------------------------
function Get-TIRecoveryScan {
    param([string]$AppRoot = '')
    [void](Clear-TIOfflineHives)
    # partição do app na raiz (pendrive): fica de fora da procura
    $ex = @()
    if ($AppRoot -match '^[A-Za-z]:\\?$') { $ex += (ConvertTo-TIDriveLetter $AppRoot) }
    Emit 'Procurando o Windows nos discos...' 'Info' 5
    $list = @(Get-TIWindowsInstalls -ExcludeRoots $ex)
    $disks = @{}; $pending = @{}
    $i = 0
    foreach ($w in $list) {
        $i++
        if ($w.Locked -or -not $w.Drive) { continue }
        Emit ('Lendo a saúde do disco de {0}...' -f $w.Drive) 'Debug' ([int](40 + 50 * $i / [Math]::Max(1, $list.Count)))
        $disks[[string]$w.Drive] = Get-TIRecoveryDiskInfo -Drive $w.Drive
        $pending[[string]$w.Drive] = Test-TIPendingActions -Install $w
    }
    $fw = ''
    try { $fw = Get-TIFirmwareType } catch { }
    $img = 0
    if ($AppRoot) {
        $rd = Join-TIWinPath $AppRoot 'reparo'
        $img = @(Get-TISafeFiles -Path $rd -Filter '*.wim').Count + @(Get-TISafeFiles -Path $rd -Filter '*.esd').Count
    }
    $ok = @($list | Where-Object { -not $_.Locked }).Count
    $lk = @($list | Where-Object { $_.Locked }).Count
    $msg = $(if ($list.Count -eq 0) { 'Nenhum Windows encontrado nos discos.' } else { '{0} Windows encontrado(s){1}.' -f $ok, $(if ($lk -gt 0) { ' e {0} volume(s) bloqueado(s) pelo BitLocker' -f $lk } else { '' }) })
    Emit $msg $(if ($list.Count -eq 0) { 'Warn' } else { 'Success' }) 100
    return [pscustomobject]@{
        Kind = 'RecoveryScan'; Ok = $true; Installs = $list; Disks = $disks; Pending = $pending
        Firmware = $fw; RepairImages = $img; WinPE = (Test-TIWinPE)
    }
}

# Atualizações instaladas nos últimos -Days dias e as pendentes
function Get-TIOfflinePackages {
    param([Parameter(Mandatory)]$Install, [int]$Days = 60)
    Assert-TIOfflineInstall $Install
    Emit 'Lendo as atualizações instaladas neste Windows (pode levar um minuto)...' 'Info' 10
    $all = @(Get-WindowsPackage -Path $Install.Root -ErrorAction Stop)
    $cut = (Get-Date).AddDays(-$Days)
    $out = New-Object System.Collections.ArrayList
    foreach ($p in $all) {
        $state = [string]$p.PackageState
        if ($state -match '^(?i)(superseded|staged|absent|resolved|resolving|staging)$') { continue }
        $pend = ($state -match '(?i)pending')
        $t = $null
        try { if ($p.InstallTime) { $t = [datetime]$p.InstallTime } } catch { }
        if (-not $pend -and -not ($t -and $t -ge $cut)) { continue }
        $rt = [string]$p.ReleaseType
        if (-not $pend -and $rt -match '^(?i)(foundation|languagepack|ondemandpack|featurepack|product|localpack)$') { continue }
        [void]$out.Add([pscustomobject]@{
            PackageName = [string]$p.PackageName; Name = (Get-TIPackageDisplayName ([string]$p.PackageName))
            State = $state; StateText = (ConvertTo-TIPackageStateText $state); ReleaseType = $rt
            TypeText = (ConvertTo-TIReleaseTypeText $rt); InstallTime = $t; Pending = $pend
        })
    }
    $px = Test-TIPendingActions -Install $Install
    $np = @($out | Where-Object { $_.Pending }).Count
    Emit ('{0} atualização(ões) recente(s) ou pendente(s){1}.' -f $out.Count, $(if ($px -or $np -gt 0) { '; há ações pendentes de atualização' } else { '' })) 'Success' 100
    return [pscustomobject]@{
        Kind = 'RecoveryPackages'; Ok = $true; Drive = [string]$Install.Drive
        Items = @($out | Sort-Object @{ Expression = { if ($_.InstallTime) { [datetime]$_.InstallTime } else { [datetime]::MaxValue } } } -Descending)
        Pending = ($px -or $np -gt 0)
    }
}

# Drivers de terceiros (oemNN.inf) da instalação
function Get-TIOfflineDrivers {
    param([Parameter(Mandatory)]$Install)
    Assert-TIOfflineInstall $Install
    Emit 'Lendo os drivers de terceiros deste Windows (pode levar um minuto)...' 'Info' 10
    $out = New-Object System.Collections.ArrayList
    foreach ($d in @(Get-WindowsDriver -Path $Install.Root -ErrorAction Stop)) {
        if ($d.Inbox) { continue }
        $pub = [string]$d.Driver
        if ($pub -notmatch '^(?i)oem\d+\.inf$') { continue }
        $date = $null
        try { if ($d.Date) { $date = [datetime]$d.Date } } catch { }
        [void]$out.Add([pscustomobject]@{
            Driver = $pub; File = ([string]$d.OriginalFileName).Substring(([string]$d.OriginalFileName).LastIndexOf('\') + 1)
            Provider = [string]$d.ProviderName; Class = [string]$d.ClassName; Date = $date
            Version = [string]$d.Version; BootCritical = [bool]$d.BootCritical
        })
    }
    Emit ('{0} driver(s) de terceiros.' -f $out.Count) 'Success' 100
    return [pscustomobject]@{ Kind = 'RecoveryDrivers'; Ok = $true; Drive = [string]$Install.Drive; Items = @($out | Sort-Object Class, Provider) }
}

# Destrava um volume BitLocker com a chave de recuperação (48 números).
# A chave não aparece em nenhuma mensagem.
function Unlock-TIBitLockerVolume {
    param([string]$VolumeId, [string]$Drive, [string]$Key)
    if (-not $Key) { throw 'Chave de recuperação vazia.' }
    $vols = @(Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -ErrorAction Stop)
    $v = $null
    foreach ($x in $vols) {
        if ($VolumeId -and [string]$x.DeviceID -eq $VolumeId) { $v = $x; break }
        if (-not $VolumeId -and $Drive -and (ConvertTo-TIDriveLetter ([string]$x.DriveLetter)) -eq (ConvertTo-TIDriveLetter $Drive)) { $v = $x; break }
    }
    if (-not $v) { throw 'O volume bloqueado não foi encontrado: clique em Procurar de novo.' }
    $rv = [int64]-1
    try {
        $r = Invoke-CimMethod -InputObject $v -MethodName 'UnlockWithNumericalPassword' -Arguments @{ NumericalPassword = $Key } -ErrorAction Stop
        $rv = [int64]$r.ReturnValue
    } catch {
        throw ('Falha ao destravar: {0}' -f ([string]$_.Exception.Message).Replace($Key, '***'))
    }
    if ($rv -eq 0) { return $true }
    $hex = $(if ($rv -ge 0) { '0x{0:X8}' -f [uint32]$rv } else { [string]$rv })
    $why = switch ($hex) {
        '0x80310027' { 'a chave de recuperação não confere com este volume' }
        '0x8031006A' { 'formato de chave inválido' }
        default { 'erro ' + $hex }
    }
    throw ('Não foi possível destravar o volume: {0}.' -f $why)
}
'@

# ---------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------
$global:Recuperacao = @{
    Scanned      = $false
    Installs     = @()
    Disks        = @{}
    Pending      = @{}
    Firmware     = ''
    RepairImages = 0
    WinPE        = $false
    Selected     = $null
    Filling      = $false
    OpenLaudo    = $false
    Grid         = $null
    Info         = $null
    UnlockBtn    = $null
    DiskBody     = $null
    TargetInfo   = $null
    SourceInfo   = $null
    AutoBtn      = $null
    RepairBtns   = @()
    FullSwitch   = $null
    PkgGrid      = $null
    PkgInfo      = $null
    PkgFor       = ''
    PkgPending   = $false
    PkgBtns      = @{}
    DrvGrid      = $null
    DrvInfo      = $null
    DrvFor       = ''
    DrvBtns      = @{}
    ProgGrid     = $null
    ProgInfo     = $null
    ProgFor      = ''
    ProgRows     = @()
    ProgBtns     = @{}
    Cards        = @{}
    LaudoBtn     = $null
    LastLaudo    = ''
    Session      = @{}
}

# Coluna 0 da lista de programas: caixa desenhada com glifo (mesmo visual da Manutenção)
$global:RecuperacaoGlyph = @{
    On   = [string][char]0xE73A   # CheckboxComposite
    Off  = [string][char]0xE739   # Checkbox
    Lock = [string][char]0xE72E   # Lock
}

# Situação de uma instalação na lista (regra pura). CanRepair: pode receber reparos.
function Get-RecuperacaoInstallState {
    param($Install)
    if (-not $Install) { return [pscustomobject]@{ Text = ''; Tone = 'dim'; CanRepair = $false } }
    if ($Install.Locked) { return [pscustomobject]@{ Text = 'Bloqueado pelo BitLocker: destrave para reparar'; Tone = 'warn'; CanRepair = $false } }
    if ($Install.IsRunning) { return [pscustomobject]@{ Text = 'Em execução: não pode ser reparado daqui'; Tone = 'dim'; CanRepair = $false } }
    if ($Install.Hibernated) { return [pscustomobject]@{ Text = 'Pronto para reparo (estava hibernado)'; Tone = 'warn'; CanRepair = $true } }
    if ($Install.ReadError -and [int]$Install.Build -le 0) { return [pscustomobject]@{ Text = 'Pronto para reparo (registro ilegível)'; Tone = 'warn'; CanRepair = $true } }
    return [pscustomobject]@{ Text = 'Pronto para reparo'; Tone = 'ok'; CanRepair = $true }
}

function Get-RecuperacaoKey {
    param($Install)
    if (-not $Install) { return '' }
    if ($Install.Drive) { return [string]$Install.Drive }
    return [string]$Install.VolumeId
}

function Get-RecuperacaoAuditDetail {
    param($Install)
    return ('Windows: {0} em {1}' -f $Install.Label, $Install.Drive)
}

# Texto do laudo (.txt): instalação, disco, cada ação e resultado. Regra pura.
function New-RecuperacaoLaudoText {
    param($Install, $Disk = $null, $Actions = @(), [string]$Firmware = '', [string]$Version = '',
          [datetime]$When = (Get-Date), [bool]$WinPE = $false)
    $sb = New-Object System.Text.StringBuilder
    $line = '=' * 69
    $dash = { param($s) if ([string]::IsNullOrWhiteSpace([string]$s)) { '-' } else { [string]$s } }
    $gb = { param([double]$b) if ($b -ge 1TB) { '{0:0.##} TB' -f ($b / 1TB) } elseif ($b -ge 1GB) { '{0:0.#} GB' -f ($b / 1GB) } else { '{0:0} MB' -f ($b / 1MB) } }
    $row = { param($k, $v) [void]$sb.AppendLine((' {0,-16}: {1}' -f $k, (& $dash $v))) }
    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine(' TI Suite - laudo de recuperação do Windows')
    [void]$sb.AppendLine($line)
    & $row 'Computador' $Install.ComputerName
    & $row 'Windows' $Install.Label
    & $row 'Unidade' $(if ($Install.Drive) { '{0} ({1}{2})' -f $Install.Drive, $Install.WinDir, $(if ($Install.Arch) { ', ' + $Install.Arch } else { '' }) } else { '' })
    if ($Install.InstallDate) { & $row 'Instalado em' ([datetime]$Install.InstallDate).ToString('dd/MM/yyyy') }
    if ([double]$Install.SizeBytes -gt 0) { & $row 'Espaço livre' ('{0} de {1}' -f (& $gb ([double]$Install.FreeBytes)), (& $gb ([double]$Install.SizeBytes))) }
    if ($Disk -and $Disk.Read) {
        & $row 'Disco' (('{0} - {1} {2} ({3})' -f $Disk.Model, $Disk.Media, $Disk.SizeText, $Disk.Style) -replace '\s+', ' ')
        $mark = $(if ($Disk.Tone -eq 'crit') { '[X] ' } elseif ($Disk.Tone -eq 'warn') { '[!] ' } else { '' })
        & $row 'Saúde do disco' ($mark + $Disk.Text)
    }
    & $row 'Firmware' $Firmware
    & $row 'Ambiente' $(if ($WinPE) { 'pendrive de recuperação (Windows PE)' } else { 'Windows (modo recuperação)' })
    & $row 'Gerado em' $When.ToString('dd/MM/yyyy HH:mm')
    & $row 'Técnico' ''
    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(' Ações ([OK] concluído, [!] atenção, [X] falha)')
    $acts = @($Actions | Where-Object { $_ })
    if ($acts.Count -eq 0) { [void]$sb.AppendLine('   Nenhuma ação nesta sessão.') }
    foreach ($a in $acts) {
        [void]$sb.AppendLine('')
        $t = ' {0} {1}' -f ([datetime]$a.Started).ToString('HH:mm'), $a.Title
        if ($a.Stopped) { $t += ' (parou: requer decisão do técnico)' }
        [void]$sb.AppendLine($t)
        foreach ($s in @($a.Steps)) {
            $m = switch ([string]$s.Level) { 'Success' { '[OK]' } 'Warn' { '[!] ' } 'Error' { '[X] ' } default { '    ' } }
            [void]$sb.AppendLine(('   {0} {1}: {2}' -f $m, $s.Name, $s.Text))
        }
        if ($a.Stopped -and $a.StopReason) { [void]$sb.AppendLine(('   >>  {0}' -f $a.StopReason)) }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine((' Gerado pelo TI Suite v{0}' -f $Version))
    return $sb.ToString()
}

# Pastas: laudos\ e logs\ do pendrive (no WinPE o X: some ao desligar)
function Get-RecuperacaoLaudoDir {
    $cands = @()
    if ($global:TIPortable -and $global:TIRoot) { $cands += (Join-Path $global:TIRoot 'laudos') }
    try { $cands += [Environment]::GetFolderPath('MyDocuments') } catch { }
    foreach ($d in $cands) {
        if (-not $d) { continue }
        try {
            if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null }
            return $d
        } catch { }
    }
    return ''
}

function Get-RecuperacaoLogDir {
    $d = ''
    try { $d = [string](Get-TILogDir) } catch { }
    if (-not $d) { return '' }
    try { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null } } catch { return '' }
    return $d
}

function Get-RecuperacaoSession {
    param($Install)
    $k = Get-RecuperacaoKey $Install
    if (-not $k) { return $null }
    if (-not $global:Recuperacao.Session.ContainsKey($k)) {
        $global:Recuperacao.Session[$k] = @{ Install = $Install; Actions = (New-Object System.Collections.ArrayList); File = '' }
    }
    $s = $global:Recuperacao.Session[$k]
    $s.Install = $Install
    return $s
}

# Grava (ou regrava) o laudo desta instalação nesta sessão. Devolve o caminho ou ''.
function Save-RecuperacaoLaudo {
    param($Install, [switch]$Quiet)
    if (-not $Install) { return '' }
    $s = Get-RecuperacaoSession $Install
    if (-not $s) { return '' }
    try {
        if (-not $s.File) {
            $dir = Get-RecuperacaoLaudoDir
            if (-not $dir) { throw 'nenhuma pasta disponível para o laudo' }
            $pc = $(if ($Install.ComputerName) { $Install.ComputerName } else { 'PC-' + ([string]$Install.Drive).TrimEnd(':') })
            $s.File = Join-Path $dir (Get-TIRecoveryLaudoName -Computer $pc -When (Get-Date))
        }
        $txt = New-RecuperacaoLaudoText -Install $Install -Disk $global:Recuperacao.Disks[[string]$Install.Drive] -Actions @($s.Actions) `
                    -Firmware $global:Recuperacao.Firmware -Version $global:TI.Version -When (Get-Date) -WinPE ([bool]$global:Recuperacao.WinPE)
        [System.IO.File]::WriteAllText($s.File, $txt, (New-Object System.Text.UTF8Encoding($true)))
        $global:Recuperacao.LastLaudo = $s.File
        if ($global:Recuperacao.LaudoBtn) { $global:Recuperacao.LaudoBtn.Enabled = $true }
        Write-TILog -Level $(if ($Quiet) { 'Debug' } else { 'Success' }) -Message ('Laudo salvo: {0}' -f $s.File)
        if (-not $Quiet) { Show-TIToast -Text ('Laudo salvo: {0}' -f (Split-Path -Leaf $s.File)) -Type 'Success' }
        return $s.File
    } catch {
        Write-TILog -Level 'Error' -Message ('Não foi possível salvar o laudo: {0}' -f $_.Exception.Message)
        if (-not $Quiet) { Show-TIToast -Text 'Não foi possível salvar o laudo (pendrive protegido ou cheio?).' -Type 'Error' }
        return ''
    }
}

function Export-RecuperacaoLaudo {
    $s = $global:Recuperacao.Selected
    if (-not $s) { Show-TIToast -Text 'Escolha o Windows na lista para salvar o laudo.' -Type 'Warn'; return }
    [void](Save-RecuperacaoLaudo -Install $s)
}

# --- Lista de instalações -----------------------------------------------------
function Update-RecuperacaoInfo {
    param([string]$Text, [string]$Tone = 'muted')
    $l = $global:Recuperacao.Info
    if ($l -and -not $l.IsDisposed) { $l.Text = $Text; $l.ForeColor = Get-TIToneColor $Tone }
}

function Update-RecuperacaoButtons {
    $r = $global:Recuperacao
    $s = $r.Selected
    $st = Get-RecuperacaoInstallState $s
    $busy = [bool]$global:TI.Busy
    $can = ($s -and $st.CanRepair -and -not $busy)
    $key = Get-RecuperacaoKey $s
    foreach ($b in @($r.RepairBtns)) { if ($b) { $b.Enabled = $can } }
    if ($r.UnlockBtn) { $r.UnlockBtn.Enabled = ($s -and $s.Locked -and -not $busy) }
    if ($r.TargetInfo -and -not $r.TargetInfo.IsDisposed) {
        if (-not $s) { $r.TargetInfo.Text = 'Escolha o Windows na lista acima.'; $r.TargetInfo.ForeColor = $global:Pal.TextMuted }
        elseif (-not $st.CanRepair) { $r.TargetInfo.Text = ('{0} ({1}): {2}.' -f $s.Label, $(if ($s.Drive) { $s.Drive } else { 'sem letra' }), $st.Text.ToLower()); $r.TargetInfo.ForeColor = $global:Pal.Warning }
        else { $r.TargetInfo.Text = ('Windows escolhido: {0} em {1}.' -f $s.Label, $s.Drive); $r.TargetInfo.ForeColor = $global:Pal.Primary }
    }
    $pkgSel = ($r.PkgGrid -and $r.PkgGrid.SelectedRows.Count -gt 0 -and $r.PkgFor -eq $key)
    if ($r.PkgBtns.List) { $r.PkgBtns.List.Enabled = $can }
    if ($r.PkgBtns.Remove) { $r.PkgBtns.Remove.Enabled = ($can -and $pkgSel) }
    # o técnico decide: o pending.xml nem sempre existe quando há pendências
    if ($r.PkgBtns.Revert) { $r.PkgBtns.Revert.Enabled = $can }
    $drvSel = ($r.DrvGrid -and $r.DrvGrid.SelectedRows.Count -gt 0 -and $r.DrvFor -eq $key)
    if ($r.DrvBtns.List) { $r.DrvBtns.List.Enabled = $can }
    if ($r.DrvBtns.Remove) { $r.DrvBtns.Remove.Enabled = ($can -and $drvSel) }
    $marked = @(Get-RecuperacaoProgMarked).Count
    $free = @($r.ProgRows | Where-Object { $_ -and -not $_.Protected }).Count
    if ($r.ProgBtns.List) { $r.ProgBtns.List.Enabled = $can }
    if ($r.ProgBtns.Remove) {
        $r.ProgBtns.Remove.Enabled = ($can -and $marked -gt 0 -and $r.ProgFor -eq $key)
        $r.ProgBtns.Remove.Text = $(if ($marked -gt 0) { 'Remover marcados ({0})' -f $marked } else { 'Remover marcados' })
    }
    if ($r.ProgBtns.None) { $r.ProgBtns.None.Enabled = (-not $busy -and $free -gt 0 -and $marked -gt 0) }
}

function Fill-RecuperacaoGrid {
    param([string]$KeepKey = '')
    $grid = $global:Recuperacao.Grid
    if (-not $grid) { return }
    # durante o preenchimento a seleção muda sozinha: só a escolha final vale
    $global:Recuperacao.Filling = $true
    try {
        $grid.Rows.Clear()
        $list = @($global:Recuperacao.Installs | Where-Object { $_ })
        $pick = $null
        foreach ($w in $list) {
            $st = Get-RecuperacaoInstallState $w
            $free = $(if ([double]$w.SizeBytes -gt 0 -and -not $w.Locked) { '{0} de {1}' -f (Format-TIBytes $w.FreeBytes), (Format-TIBytes $w.SizeBytes) } elseif ([double]$w.SizeBytes -gt 0) { Format-TIBytes $w.SizeBytes } else { '-' })
            $row = Add-TIRow -Grid $grid -Tag $w -Cells @($(if ($w.Drive) { $w.Drive } else { '-' }), $w.Label, $(if ($w.ComputerName) { $w.ComputerName } else { '-' }), $free, $st.Text) `
                             -SortKeys @([string]$w.Drive, [string]$w.Label, [string]$w.ComputerName, [double]$w.FreeBytes, $st.Text)
            $row.Cells[4].Style.ForeColor = Get-TIToneColor $st.Tone
            $row.Cells[4].Style.SelectionForeColor = $row.Cells[4].Style.ForeColor
            $tip = @()
            if ($w.WinDir) { $tip += $w.WinDir }
            if ($w.Arch) { $tip += ('Arquitetura: {0}' -f $w.Arch) }
            if ($w.InstallDate) { $tip += ('Instalado em {0}' -f (Format-TIDate $w.InstallDate)) }
            if ($w.ReadError) { $tip += ('Registro: {0}' -f $w.ReadError) }
            $row.Cells[1].ToolTipText = ($tip -join "`n")
            if ($KeepKey -and (Get-RecuperacaoKey $w) -eq $KeepKey) { $pick = $row }
        }
        Clear-TIGridSelection $grid
        Set-TIGridEmptyText $grid 'Nenhum Windows encontrado nos discos. Confira se o disco aparece no BIOS/UEFI e clique em Procurar de novo.'
        # uma só instalação que pode ser reparada: já vem escolhida
        if (-not $pick) {
            $cands = @($grid.Rows | Where-Object { (Get-RecuperacaoInstallState $_.Tag).CanRepair })
            if ($cands.Count -eq 1) { $pick = $cands[0] }
        }
        if ($pick) { $pick.Selected = $true }
    } finally {
        $global:Recuperacao.Filling = $false
    }
    Select-RecuperacaoInstall
}

function Select-RecuperacaoInstall {
    if ($global:Recuperacao.Filling) { return }
    $grid = $global:Recuperacao.Grid
    $old = Get-RecuperacaoKey $global:Recuperacao.Selected
    $sel = $null
    if ($grid -and $grid.SelectedRows.Count -gt 0) { $sel = $grid.SelectedRows[0].Tag }
    $global:Recuperacao.Selected = $sel
    $new = Get-RecuperacaoKey $sel
    if ($old -ne $new) {
        # listas da instalação anterior ficam velhas
        if ($global:Recuperacao.PkgFor -and $global:Recuperacao.PkgFor -ne $new) { Clear-RecuperacaoList 'Pkg' }
        if ($global:Recuperacao.DrvFor -and $global:Recuperacao.DrvFor -ne $new) { Clear-RecuperacaoList 'Drv' }
        if ($global:Recuperacao.ProgFor -and $global:Recuperacao.ProgFor -ne $new) { Clear-RecuperacaoList 'Prog' }
    }
    Fill-RecuperacaoDiskCard
    Update-RecuperacaoButtons
}

function Clear-RecuperacaoList {
    param([string]$Which)
    $r = $global:Recuperacao
    switch ($Which) {
        'Pkg' {
            $r.PkgFor = ''; $r.PkgPending = $false
            if ($r.PkgGrid) { $r.PkgGrid.Rows.Clear(); Set-TIGridEmptyText $r.PkgGrid 'Clique em Listar atualizações.' }
            if ($r.PkgInfo) { $r.PkgInfo.Text = 'Lista as atualizações dos últimos 60 dias e as pendentes do Windows escolhido.'; $r.PkgInfo.ForeColor = $global:Pal.TextMuted }
        }
        'Drv' {
            $r.DrvFor = ''
            if ($r.DrvGrid) { $r.DrvGrid.Rows.Clear(); Set-TIGridEmptyText $r.DrvGrid 'Clique em Listar drivers.' }
            if ($r.DrvInfo) { $r.DrvInfo.Text = 'Lista os drivers de terceiros (fabricantes) do Windows escolhido.'; $r.DrvInfo.ForeColor = $global:Pal.TextMuted }
        }
        'Prog' {
            $r.ProgFor = ''; $r.ProgRows = @()
            if ($r.ProgGrid) { $r.ProgGrid.Rows.Clear(); Set-TIGridEmptyText $r.ProgGrid 'Clique em Listar programas.' }
            if ($r.ProgInfo) { $r.ProgInfo.Text = 'Lista os programas instalados no Windows escolhido. Nada vem marcado.'; $r.ProgInfo.ForeColor = $global:Pal.TextMuted }
        }
    }
}

function Fill-RecuperacaoDiskCard {
    $b = $global:Recuperacao.DiskBody
    if (-not $b -or $b.IsDisposed) { return }
    $s = $global:Recuperacao.Selected
    $b.SuspendLayout()
    foreach ($c in @($b.Controls)) { $b.Controls.Remove($c); $c.Dispose() }
    $iw = Get-TIInnerWidth $b
    $d = $null
    if ($s -and $s.Drive) { $d = $global:Recuperacao.Disks[[string]$s.Drive] }
    if (-not $s) {
        $null = New-TIHint -Parent $b -Text 'Escolha o Windows na lista para ver a saúde do disco.'
        Set-TICardStatus $b 'none' 'Aguardando'
    } elseif ($s.Locked) {
        $null = New-TIHint -Parent $b -Text 'Volume bloqueado pelo BitLocker: destrave para ler o disco.'
        Set-TICardStatus $b 'none'
    } elseif (-not $d -or -not $d.Read) {
        $null = New-TIHint -Parent $b -Text 'O Windows não informou a saúde deste disco. Rode Verificar disco e acompanhe as mensagens.'
        Set-TICardStatus $b 'none'
    } else {
        $rows = @(
            @('Disco', $d.Model, ''),
            @('Tipo', (('{0} {1} ({2})' -f $d.Media, $d.SizeText, $d.Style) -replace '\s+', ' ').Trim(), ''),
            @('Saúde', $d.Text, $(if ($d.Tone -eq 'none') { 'dim' } else { $d.Tone }))
        )
        if ($d.Temp -gt 0) { $rows += , @('Temperatura', ('{0} °C' -f $d.Temp), '') }
        if ($d.Wear -gt 0) { $rows += , @('Desgaste', ('{0}%' -f $d.Wear), '') }
        if ($d.Uncorrected -gt 0) { $rows += , @('Erros de leitura', [string]$d.Uncorrected, 'crit') }
        if ($d.Hours -gt 0) { $rows += , @('Horas de uso', ('{0:N0} h' -f $d.Hours), '') }
        foreach ($x in $rows) {
            $row = New-TIRow -Label $x[0] -Width $iw -LabelWidth 120
            Set-TIRowValue $row $x[1] $x[2]
            $b.Controls.Add($row.Panel)
        }
        if ($d.Tone -eq 'crit') {
            $null = New-TIHint -Parent $b -Text 'Disco com falha: faça o backup dos dados (área Backup) ANTES de reparar. Os reparos escrevem no disco e podem piorar um disco que está falhando.' -Color $global:Pal.Danger -Size 9 -TopGap 6
        }
        Set-TICardStatus $b $(if ($d.Tone -eq 'none') { 'none' } else { $d.Tone })
    }
    $b.ResumeLayout()
}

function Invoke-RecuperacaoScan {
    if ($global:TI.Busy) { return }
    $keep = Get-RecuperacaoKey $global:Recuperacao.Selected
    Update-RecuperacaoInfo 'Procurando o Windows nos discos...' 'primary'
    [void](Invoke-TIAsync -Name 'Procura do Windows nos discos' -Quiet -Context @{ AppRoot = [string]$global:TIRoot; Keep = $keep } -Script {
        $res = $null
        try { $res = Get-TIRecoveryScan -AppRoot $Context.AppRoot }
        catch { Emit ('Não foi possível procurar o Windows: {0}' -f $_.Exception.Message) 'Error' }
        if (-not $res) { $res = [pscustomobject]@{ Kind = 'RecoveryScan'; Ok = $false } }
        Add-Member -InputObject $res -NotePropertyName 'Keep' -NotePropertyValue ([string]$Context.Keep) -Force
        $res
    } -OnComplete {
        param($r)
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'RecoveryScan' }) | Select-Object -First 1
        Complete-RecuperacaoScan -Result $res
    })
}

function Complete-RecuperacaoScan {
    param($Result)
    $r = $global:Recuperacao
    if (-not $Result -or -not $Result.Ok) {
        $r.Scanned = $false
        $r.Installs = @()
        if ($r.Grid) { $r.Grid.Rows.Clear(); Set-TIGridEmptyText $r.Grid 'Não foi possível procurar o Windows. Veja o console (F12) e clique em Procurar de novo.' }
        Update-RecuperacaoInfo 'Não foi possível procurar o Windows nos discos (detalhes no console).' 'crit'
        $r.Selected = $null
        Fill-RecuperacaoDiskCard
        Update-RecuperacaoButtons
        return
    }
    $r.Scanned = $true
    $r.Installs = @($Result.Installs | Where-Object { $_ })
    $r.Disks = $(if ($Result.Disks) { $Result.Disks } else { @{} })
    $r.Pending = $(if ($Result.Pending) { $Result.Pending } else { @{} })
    $r.Firmware = [string]$Result.Firmware
    $r.RepairImages = [int]$Result.RepairImages
    $r.WinPE = [bool]$Result.WinPE
    $ok = @($r.Installs | Where-Object { (Get-RecuperacaoInstallState $_).CanRepair }).Count
    $lk = @($r.Installs | Where-Object { $_.Locked }).Count
    $txt = $(if ($r.Installs.Count -eq 0) { 'Nenhum Windows encontrado nos discos.' }
             else { '{0} Windows para reparo{1}. Clique na linha para escolher.' -f $ok, $(if ($lk -gt 0) { ('; {0} volume(s) bloqueado(s) pelo BitLocker: escolha e clique em Destravar BitLocker' -f $lk) } else { '' }) })
    $fwTxt = $(if ($r.Firmware) { ' Firmware: {0}.' -f $r.Firmware } else { '' })
    Update-RecuperacaoInfo ($txt + $fwTxt) $(if ($r.Installs.Count -eq 0) { 'warn' } else { 'muted' })
    if ($r.SourceInfo -and -not $r.SourceInfo.IsDisposed) {
        $r.SourceInfo.Text = $(if ($r.RepairImages -gt 0) { 'Fonte para o DISM: {0} imagem(ns) na pasta reparo\ do pendrive (usa a da mesma versão e edição).' -f $r.RepairImages }
                               else { 'Fonte para o DISM (opcional): copie o install.wim ou install.esd do ISO oficial da mesma versão do Windows para a pasta reparo\ do pendrive.' })
    }
    Fill-RecuperacaoGrid -KeepKey ([string]$Result.Keep)
}

# --- Ações de reparo -----------------------------------------------------------
function Get-RecuperacaoTarget {
    param([string]$What)
    if ($global:TI.Busy) { return $null }
    $s = $global:Recuperacao.Selected
    if (-not $s) { Show-TIToast -Text 'Escolha o Windows na lista "Windows encontrados".' -Type 'Warn'; return $null }
    if ($s.Locked) { Show-TIToast -Text 'Este volume está bloqueado pelo BitLocker: clique em Destravar BitLocker antes.' -Type 'Warn'; return $null }
    if ($s.IsRunning) { Show-TIToast -Text 'Este é o Windows em execução: ele não pode ser reparado daqui. Use o pendrive de recuperação.' -Type 'Warn'; return $null }
    if (-not $global:TI.Elevated) { Show-TIToast -Text ('{0} precisa do TI Suite aberto como administrador.' -f $What) -Type 'Error'; return $null }
    return $s
}

function Get-RecuperacaoHiberNote {
    param($Install)
    if (-not $Install -or -not $Install.Hibernated) { return '' }
    return "`n`nEste Windows foi desligado com hibernação ou Inicialização rápida: a sessão hibernada será descartada (o que estava aberto e não foi salvo se perde) e ele fará uma inicialização completa."
}

# Disco com falha: o técnico decide (backup antes)
function Confirm-RecuperacaoDisk {
    param($Install)
    $d = $global:Recuperacao.Disks[[string]$Install.Drive]
    if (-not $d -or $d.Tone -ne 'crit') { return $true }
    return (Show-TIConfirm -Title 'Disco com falha' -Style 'Danger' -Icon 'Warning' -ConfirmText 'Continuar sem backup' `
        -Message ("O disco deste Windows apresenta falha:`n{0}`n`nOs reparos escrevem no disco e podem piorar um disco que está falhando. Faça o backup dos dados (área Backup) antes.`n`nContinuar mesmo assim?" -f $d.Text))
}

function Start-RecuperacaoAction {
    param(
        $Install,
        [string]$Action,
        [string]$Title,
        [string]$TaskName,
        [string]$Message,
        [string]$ConfirmText,
        [ValidateSet('Primary','Danger','Success')][string]$Style = 'Primary',
        [string]$Icon = 'Repair',
        [hashtable]$Extra = @{},
        [switch]$SkipDiskCheck
    )
    if (-not $SkipDiskCheck -and -not (Confirm-RecuperacaoDisk $Install)) { return }
    $msg = $Message + (Get-RecuperacaoHiberNote $Install)
    if (-not (Show-TIConfirm -Title $Title -Message $msg -ConfirmText $ConfirmText -Style $Style -Icon $Icon)) { return }
    $ctx = @{
        Install = $Install; Action = $Action; Title = $Title; LogDir = (Get-RecuperacaoLogDir)
        AppRoot = [string]$global:TIRoot; Firmware = [string]$global:Recuperacao.Firmware
    }
    foreach ($k in @($Extra.Keys)) { $ctx[$k] = $Extra[$k] }
    if (-not $ctx.LogDir -and @('auto', 'boot', 'safemode-on', 'safemode-off') -contains $Action) {
        Show-TIMessage -Title $Title -Icon 'Error' -Message 'A pasta logs do pendrive não pode ser gravada (protegido contra gravação ou cheio). Sem a cópia do BCD a inicialização não é alterada.'
        if ($Action -ne 'auto') { return }
    }
    Write-TILog -Level 'Warn' -Message ('{0} solicitado para {1} em {2}.' -f $Title, $Install.Label, $Install.Drive)
    [void](Invoke-TIAsync -Name $TaskName -RequiresAdmin -Context $ctx -AuditDetail (Get-RecuperacaoAuditDetail $Install) -Script {
        Invoke-TIRecoveryAction -Ctx $Context
    } -OnComplete {
        param($r)
        Complete-RecuperacaoAction -Result $r
    })
}

function Get-RecuperacaoInstallByKey {
    param([string]$Key)
    return (@($global:Recuperacao.Installs | Where-Object { $_ -and (Get-RecuperacaoKey $_) -eq $Key }) | Select-Object -First 1)
}

function Get-RecuperacaoStepsText {
    param($Result, [int]$Max = 12)
    $l = @(@($Result.Steps) | Select-Object -First $Max | ForEach-Object {
        $st = $_
        $m = switch ([string]$st.Level) { 'Success' { '[OK]' } 'Warn' { '[!]' } 'Error' { '[X]' } default { '-' } }
        ('{0} {1}' -f $m, $st.Name)
    })
    return ($l -join "`n")
}

function Complete-RecuperacaoAction {
    param($Result)
    $res = @($Result | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'RecoveryAction' }) | Select-Object -First 1
    if (-not $res) { return }
    $inst = Get-RecuperacaoInstallByKey ([string]$res.Drive)
    if ($inst -and $res.HiberDiscarded) { $inst.Hibernated = $false }
    if ($res.Action -eq 'safemode-read') {
        Continue-RecuperacaoSafeMode -Install $inst -Result $res
        return
    }
    $file = ''
    if ($inst) {
        $s = Get-RecuperacaoSession $inst
        [void]$s.Actions.Add($res)
        $file = Save-RecuperacaoLaudo -Install $inst -Quiet
    }
    if ($res.Action -eq 'revert' -or $res.Action -eq 'auto') { if ($inst) { $global:Recuperacao.Pending[[string]$inst.Drive] = $false } }
    $errs = @(@($res.Steps) | Where-Object { $_.Level -eq 'Error' }).Count
    $where = $(if ($file) { "`n`nLaudo: {0}" -f $file } else { '' })
    if ($res.Stopped) {
        Show-TIMessage -Title ('{0}: parou' -f $res.Title) -Icon 'Warning' -Message ("{0}`n`n{1}{2}" -f $res.StopReason, (Get-RecuperacaoStepsText $res), $where)
    } elseif ($res.Action -eq 'auto') {
        $tail = $(if ($errs -gt 0) { "`n`nAlgum passo falhou: veja o console (F12) e o laudo." } else { "`n`nReinicie o computador sem o pendrive para testar o Windows." })
        Show-TIMessage -Title 'Reparo automático: resumo' -Icon $(if ($errs -gt 0) { 'Warning' } else { 'Info' }) -Message ((Get-RecuperacaoStepsText $res) + $tail + $where)
    } elseif ($file) {
        Write-TILog -Level 'Info' -Message ('Resultado gravado no laudo: {0}' -f $file)
    }
    # listas que mudaram com a ação
    if (@('pkgremove', 'revert') -contains $res.Action -and $global:Recuperacao.PkgFor) { Invoke-RecuperacaoListPackages -Quiet }
    elseif ($res.Action -eq 'drvremove' -and $global:Recuperacao.DrvFor) { Invoke-RecuperacaoListDrivers -Quiet }
    else {
        Fill-RecuperacaoGrid -KeepKey (Get-RecuperacaoKey $inst)
    }
}

function Invoke-RecuperacaoAuto {
    $inst = Get-RecuperacaoTarget 'O reparo automático'
    if (-not $inst) { return }
    $src = $(if ($global:Recuperacao.RepairImages -gt 0) { ' (com a imagem da pasta reparo\ quando for da mesma versão)' } else { '' })
    $msg = ("Windows: {0}`nUnidade: {1}`n`nEm sequência, para este Windows:`n" +
            "  1. Verifica e corrige o disco (chkdsk /f)`n" +
            "  2. Recria os arquivos de inicialização (cópia do BCD em logs\bcd-backup)`n" +
            "  3. Desfaz atualizações pendentes, se houver`n" +
            "  4. Repara os arquivos do sistema (SFC) e verifica a imagem (DISM){2}`n" +
            "  5. Grava o laudo na pasta laudos`n`n" +
            "Para no primeiro passo que exigir sua decisão. Leva de 20 minutos a mais de uma hora; evite cancelar no meio. " +
            "Nada é reinstalado e os arquivos dos usuários não são tocados.") -f $inst.Label, $inst.Drive, $src
    Start-RecuperacaoAction -Install $inst -Action 'auto' -Title 'Reparo automático' -TaskName 'Reparo automático do Windows' `
        -Message $msg -ConfirmText 'Iniciar o reparo'
}

function Invoke-RecuperacaoBoot {
    $inst = Get-RecuperacaoTarget 'Reparar a inicialização'
    if (-not $inst) { return }
    $fw = $(if ($global:Recuperacao.Firmware) { $global:Recuperacao.Firmware } else { 'não identificado (usa UEFI e BIOS)' })
    $msg = ("Recria os arquivos de inicialização do {0} ({1}) com o bcdboot, na partição do sistema do mesmo disco " +
            "(EFI no disco GPT; a partição ativa no MBR).`n`nAntes, o BCD atual é copiado para logs\bcd-backup. " +
            "Use quando o PC não acha o Windows (""No bootable device"", ""BOOTMGR is missing"", erro 0xc000000f ou 0xc0000034).`n`nFirmware: {2}.") -f $inst.Label, $inst.Drive, $fw
    Start-RecuperacaoAction -Install $inst -Action 'boot' -Title 'Reparar inicialização' -TaskName 'Reparo da inicialização' `
        -Message $msg -ConfirmText 'Reparar a inicialização' -Icon 'Power'
}

function Invoke-RecuperacaoChkdsk {
    $inst = Get-RecuperacaoTarget 'Verificar o disco'
    if (-not $inst) { return }
    $full = ($global:Recuperacao.FullSwitch -and $global:Recuperacao.FullSwitch.Checked)
    $how = $(if ($full) { "chkdsk {0} /r: verificação COMPLETA, procura setores defeituosos em todo o disco. Pode levar várias horas em HD grande." }
             else { "chkdsk {0} /f: corrige erros do sistema de arquivos. Leva de 5 a 30 minutos." }) -f $inst.Drive
    $msg = ("Verifica e corrige a unidade {0} ({1}).`n`n{2}`n`nEvite cancelar no meio: o chkdsk estará corrigindo o disco.") -f $inst.Drive, $inst.Label, $how
    Start-RecuperacaoAction -Install $inst -Action 'chkdsk' -Title 'Verificar disco' -TaskName $(if ($full) { 'Verificação completa do disco' } else { 'Verificação do disco' }) `
        -Message $msg -ConfirmText 'Verificar o disco' -Icon 'Diagnostic' -Extra @{ Full = [bool]$full }
}

function Invoke-RecuperacaoSfc {
    $inst = Get-RecuperacaoTarget 'Reparar os arquivos do sistema'
    if (-not $inst) { return }
    $src = $(if ($global:Recuperacao.RepairImages -gt 0) { 'Se o DISM achar defeitos, usa a imagem da pasta reparo\ com a mesma versão e edição (sem internet).' }
             else { 'Sem imagem na pasta reparo\: o SFC usa o próprio Windows como fonte. Se o DISM achar defeitos, copie o install.wim/install.esd do ISO oficial da mesma versão para reparo\ (é só fonte de reparo, nada é reinstalado).' })
    $msg = ("Repara os arquivos protegidos do {0} ({1}) com o SFC offline e verifica a imagem do Windows com o DISM.`n`n{2}`n`nLeva de 15 a 60 minutos.") -f $inst.Label, $inst.Drive, $src
    Start-RecuperacaoAction -Install $inst -Action 'sfc' -Title 'Reparar arquivos do sistema' -TaskName 'Reparo dos arquivos do sistema' `
        -Message $msg -ConfirmText 'Reparar os arquivos' -Icon 'Shield'
}

function Invoke-RecuperacaoSafeMode {
    $inst = Get-RecuperacaoTarget 'O modo de segurança'
    if (-not $inst) { return }
    [void](Invoke-TIAsync -Name 'Leitura do modo de segurança' -Quiet -Context @{
            Install = $inst; Action = 'safemode-read'; Title = 'Modo de segurança'; LogDir = ''; AppRoot = ''; Firmware = [string]$global:Recuperacao.Firmware
        } -Script {
        Invoke-TIRecoveryAction -Ctx $Context
    } -OnComplete {
        param($r)
        Complete-RecuperacaoAction -Result $r
    })
}

function Continue-RecuperacaoSafeMode {
    param($Install, $Result)
    if (-not $Install) { return }
    if (-not $Result.Data) {
        $e = @(@($Result.Steps) | Where-Object { $_.Level -eq 'Error' }) | Select-Object -First 1
        Show-TIMessage -Title 'Modo de segurança' -Icon 'Error' -Message $(if ($e) { $e.Text } else { 'Não foi possível ler o estado do modo de segurança.' })
        return
    }
    if ($Result.Data.On) {
        $msg = ("O modo de segurança está LIGADO no {0} ({1}): ele sempre inicia no modo de segurança.`n`nDesligar? O Windows volta a iniciar normalmente. Antes, o BCD é copiado para logs\bcd-backup.") -f $Install.Label, $Install.Drive
        Start-RecuperacaoAction -Install $Install -Action 'safemode-off' -Title 'Modo de segurança' -TaskName 'Modo de segurança (desligar)' `
            -Message $msg -ConfirmText 'Desligar o modo de segurança' -Icon 'Lock' -SkipDiskCheck
    } else {
        $msg = ("O modo de segurança está desligado no {0} ({1}).`n`nLigar? Na próxima vez, o Windows inicia no modo de segurança mínimo (só drivers essenciais, sem rede): " +
                "útil para remover um driver ou programa que trava o Windows. Ele continua iniciando assim até você desligar aqui (ou pelo msconfig, dentro do Windows). " +
                "Antes, o BCD é copiado para logs\bcd-backup.") -f $Install.Label, $Install.Drive
        Start-RecuperacaoAction -Install $Install -Action 'safemode-on' -Title 'Modo de segurança' -TaskName 'Modo de segurança (ligar)' `
            -Message $msg -ConfirmText 'Ligar o modo de segurança' -Icon 'Lock' -SkipDiskCheck
    }
}

function Invoke-RecuperacaoUnlock {
    if ($global:TI.Busy) { return }
    $s = $global:Recuperacao.Selected
    if (-not $s -or -not $s.Locked) { Show-TIToast -Text 'Escolha na lista o volume bloqueado pelo BitLocker.' -Type 'Warn'; return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text 'Destravar o BitLocker precisa do TI Suite aberto como administrador.' -Type 'Error'; return }
    $txt = Show-TIInput -Title 'Destravar BitLocker' -Label 'Chave de recuperação (48 números)' -Password -MaxLength 64 -OkText 'Destravar' `
        -Validate { param($t) Get-TIRecoveryKeyError $t } `
        -Message ("Volume {0}. A chave de recuperação fica na conta Microsoft do dono do PC (aka.ms/myrecoverykey) ou no Active Directory/Intune da escola.`nEla não é gravada em lugar nenhum." -f $(if ($s.Drive) { $s.Drive } else { 'sem letra' }))
    if (-not $txt) { return }
    $key = ConvertTo-TIRecoveryKey $txt
    $txt = $null
    if (-not $key) { return }
    $vol = $(if ($s.Drive) { $s.Drive } else { 'volume sem letra' })
    # a chave vai só no contexto da tarefa (memória); nunca no nome, na auditoria ou no console
    [void](Invoke-TIAsync -Name 'Destravar BitLocker' -RequiresAdmin -NoCancel -AuditDetail ('Volume: {0}' -f $vol) `
            -Context @{ VolumeId = [string]$s.VolumeId; Drive = [string]$s.Drive; Key = $key } -Script {
        $ok = $false
        try {
            $ok = Unlock-TIBitLockerVolume -VolumeId $Context.VolumeId -Drive $Context.Drive -Key $Context.Key
            if ($ok) { Emit 'Volume destravado. Procurando o Windows de novo...' 'Success' }
        } catch {
            Emit ([string]$_.Exception.Message) 'Error'
        } finally {
            $Context.Key = $null
        }
        [pscustomobject]@{ Kind = 'RecoveryUnlock'; Ok = [bool]$ok }
    } -OnComplete {
        param($r)
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'RecoveryUnlock' }) | Select-Object -First 1
        if ($res -and $res.Ok) { Invoke-RecuperacaoScan }
    })
    $key = $null
}

# --- Atualizações (Desfazer atualização) ---------------------------------------
function Invoke-RecuperacaoListPackages {
    param([switch]$Quiet)
    $inst = Get-RecuperacaoTarget 'Listar as atualizações'
    if (-not $inst) { return }
    Show-RecuperacaoCard 'pkg'
    [void](Invoke-TIAsync -Name 'Leitura das atualizações' -Quiet -Context @{ Install = $inst } -Script {
        $res = $null
        try { $res = Get-TIOfflinePackages -Install $Context.Install }
        catch { Emit ('Não foi possível ler as atualizações: {0}' -f $_.Exception.Message) 'Error' }
        if (-not $res) { $res = [pscustomobject]@{ Kind = 'RecoveryPackages'; Ok = $false; Drive = [string]$Context.Install.Drive; Items = @(); Pending = $false } }
        $res
    } -OnComplete {
        param($r)
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'RecoveryPackages' }) | Select-Object -First 1
        Fill-RecuperacaoPkgGrid -Result $res
    })
}

function Fill-RecuperacaoPkgGrid {
    param($Result)
    $r = $global:Recuperacao
    $grid = $r.PkgGrid
    if (-not $grid -or -not $Result) { return }
    $grid.Rows.Clear()
    if (-not $Result.Ok) {
        $r.PkgFor = ''
        Set-TIGridEmptyText $grid 'Não foi possível ler as atualizações (detalhes no console).'
        $r.PkgInfo.Text = 'Não foi possível ler as atualizações deste Windows.'; $r.PkgInfo.ForeColor = $global:Pal.Danger
        Update-RecuperacaoButtons
        return
    }
    $r.PkgFor = [string]$Result.Drive
    $r.PkgPending = [bool]$Result.Pending
    foreach ($p in @($Result.Items | Where-Object { $_ })) {
        $row = Add-TIRow -Grid $grid -Tag $p -Cells @($p.Name, $p.TypeText, (Format-TIDate $p.InstallTime -Relative), $p.StateText) `
                         -SortKeys @($p.Name, $p.TypeText, $(if ($p.InstallTime) { [datetime]$p.InstallTime } else { [datetime]::MinValue }), $p.StateText)
        $row.Cells[0].ToolTipText = $p.PackageName
        if ($p.Pending) { $row.Cells[3].Style.ForeColor = $global:Pal.Warning; $row.Cells[3].Style.SelectionForeColor = $global:Pal.Warning }
    }
    Clear-TIGridSelection $grid
    Set-TIGridEmptyText $grid 'Nenhuma atualização nos últimos 60 dias.'
    $n = @($Result.Items).Count
    $r.PkgInfo.Text = ('{0} atualização(ões) dos últimos 60 dias ou pendente(s).{1} Selecione uma para remover.' -f $n, $(if ($r.PkgPending) { ' Há ações pendentes: use Desfazer ações pendentes primeiro.' } else { '' }))
    $r.PkgInfo.ForeColor = $(if ($r.PkgPending) { $global:Pal.Warning } else { $global:Pal.TextMuted })
    Update-RecuperacaoButtons
}

function Invoke-RecuperacaoRevert {
    $inst = Get-RecuperacaoTarget 'Desfazer as ações pendentes'
    if (-not $inst) { return }
    $msg = ("Desfaz as ações pendentes de atualização do {0} ({1}) com o DISM (RevertPendingActions).`n`n" +
            "Use quando o Windows fica preso em ""Preparando o Windows"" ou ""Desfazendo alterações"", ou não liga depois de uma atualização. " +
            "As atualizações que estavam sendo instaladas são descartadas; o Windows Update baixa de novo depois.") -f $inst.Label, $inst.Drive
    Start-RecuperacaoAction -Install $inst -Action 'revert' -Title 'Desfazer ações pendentes' -TaskName 'Desfazer ações pendentes de atualização' `
        -Message $msg -ConfirmText 'Desfazer as pendências' -Icon 'Undo'
}

function Invoke-RecuperacaoRemovePackage {
    $inst = Get-RecuperacaoTarget 'Remover a atualização'
    if (-not $inst) { return }
    $g = $global:Recuperacao.PkgGrid
    if (-not $g -or $g.SelectedRows.Count -eq 0 -or $global:Recuperacao.PkgFor -ne (Get-RecuperacaoKey $inst)) { Show-TIToast -Text 'Liste as atualizações e selecione uma.' -Type 'Warn'; return }
    $p = $g.SelectedRows[0].Tag
    $msg = ("Remove a atualização {0} do {1} ({2}).`nPacote: {3}`nInstalada em: {4}`n`n" +
            "Use quando o Windows parou de ligar depois desta atualização. Algumas atualizações cumulativas (as que vêm junto com a pilha de manutenção) " +
            "são permanentes e não podem ser removidas offline: nesse caso o DISM avisa e nada muda.") -f $p.Name, $inst.Label, $inst.Drive, $p.PackageName, (Format-TIDate $p.InstallTime)
    Start-RecuperacaoAction -Install $inst -Action 'pkgremove' -Title 'Remover atualização' -TaskName ('Remoção da atualização {0}' -f $p.Name) `
        -Message $msg -ConfirmText 'Remover a atualização' -Style 'Danger' -Icon 'Undo' -Extra @{ PackageName = [string]$p.PackageName }
}

# --- Drivers ---------------------------------------------------------------------
function Invoke-RecuperacaoListDrivers {
    param([switch]$Quiet)
    $inst = Get-RecuperacaoTarget 'Listar os drivers'
    if (-not $inst) { return }
    Show-RecuperacaoCard 'drv'
    [void](Invoke-TIAsync -Name 'Leitura dos drivers' -Quiet -Context @{ Install = $inst } -Script {
        $res = $null
        try { $res = Get-TIOfflineDrivers -Install $Context.Install }
        catch { Emit ('Não foi possível ler os drivers: {0}' -f $_.Exception.Message) 'Error' }
        if (-not $res) { $res = [pscustomobject]@{ Kind = 'RecoveryDrivers'; Ok = $false; Drive = [string]$Context.Install.Drive; Items = @() } }
        $res
    } -OnComplete {
        param($r)
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'RecoveryDrivers' }) | Select-Object -First 1
        Fill-RecuperacaoDrvGrid -Result $res
    })
}

function Fill-RecuperacaoDrvGrid {
    param($Result)
    $r = $global:Recuperacao
    $grid = $r.DrvGrid
    if (-not $grid -or -not $Result) { return }
    $grid.Rows.Clear()
    if (-not $Result.Ok) {
        $r.DrvFor = ''
        Set-TIGridEmptyText $grid 'Não foi possível ler os drivers (detalhes no console).'
        $r.DrvInfo.Text = 'Não foi possível ler os drivers deste Windows.'; $r.DrvInfo.ForeColor = $global:Pal.Danger
        Update-RecuperacaoButtons
        return
    }
    $r.DrvFor = [string]$Result.Drive
    foreach ($d in @($Result.Items | Where-Object { $_ })) {
        $row = Add-TIRow -Grid $grid -Tag $d -Cells @($d.Driver, $d.Provider, $d.Class, (Format-TIDate $d.Date), $d.Version, $d.File) `
                         -SortKeys @($d.Driver, $d.Provider, $d.Class, $(if ($d.Date) { [datetime]$d.Date } else { [datetime]::MinValue }), $d.Version, $d.File)
        if ($d.BootCritical) {
            $row.Cells[2].Style.ForeColor = $global:Pal.Warning
            $row.Cells[2].Style.SelectionForeColor = $global:Pal.Warning
            $row.Cells[2].ToolTipText = 'Crítico para a inicialização (armazenamento/controladora)'
        }
    }
    Clear-TIGridSelection $grid
    Set-TIGridEmptyText $grid 'Nenhum driver de terceiros neste Windows.'
    $r.DrvInfo.Text = ('{0} driver(s) de terceiros. Em amarelo, os críticos para a inicialização. Selecione um para remover.' -f @($Result.Items).Count)
    $r.DrvInfo.ForeColor = $global:Pal.TextMuted
    Update-RecuperacaoButtons
}

function Invoke-RecuperacaoRemoveDriver {
    $inst = Get-RecuperacaoTarget 'Remover o driver'
    if (-not $inst) { return }
    $g = $global:Recuperacao.DrvGrid
    if (-not $g -or $g.SelectedRows.Count -eq 0 -or $global:Recuperacao.DrvFor -ne (Get-RecuperacaoKey $inst)) { Show-TIToast -Text 'Liste os drivers e selecione um.' -Type 'Warn'; return }
    $d = $g.SelectedRows[0].Tag
    $msg = ("Remove o driver {0} ({1}) do {2} ({3}).`nFornecedor: {4}`nClasse: {5}`nVersão: {6} de {7}`n`n" +
            "Use para o driver que trava o Windows (tela azul ao ligar). O Windows usa um driver genérico no lugar; o do fabricante pode ser instalado de novo depois. Não dá para desfazer.") -f `
            $d.File, $d.Driver, $inst.Label, $inst.Drive, $d.Provider, $d.Class, $d.Version, (Format-TIDate $d.Date)
    if ($d.BootCritical) {
        $msg += "`n`nATENÇÃO: este driver é CRÍTICO PARA A INICIALIZAÇÃO (disco/controladora). Sem ele o Windows pode não ligar (INACCESSIBLE_BOOT_DEVICE)."
        $ok = Show-TIConfirm -Title 'Driver crítico para a inicialização' -Style 'Danger' -Icon 'Warning' -ConfirmText 'Entendi, continuar' `
            -Message ("{0} ({1}) é um driver de disco ou controladora usado para ligar o Windows. Remova só se tiver certeza de que ele é a causa do problema." -f $d.File, $d.Driver)
        if (-not $ok) { return }
    }
    Start-RecuperacaoAction -Install $inst -Action 'drvremove' -Title 'Remover driver' -TaskName ('Remoção do driver {0}' -f $d.Driver) `
        -Message $msg -ConfirmText 'Remover o driver' -Style 'Danger' -Icon 'Remove' -Extra @{ Driver = [string]$d.Driver }
}

# --- Programas (remoção offline) ---------------------------------------------------
function Get-RecuperacaoProgMarked {
    return @($global:Recuperacao.ProgRows | Where-Object { $_ -and $_.Marked })
}

function Set-RecuperacaoProgMark {
    param($Row, [bool]$On)
    if (-not $Row -or -not $Row.Tag) { return }
    $Row.Tag.Marked = $On
    $Row.Cells[0].Value = $(if ($On) { $global:RecuperacaoGlyph.On } else { $global:RecuperacaoGlyph.Off })
    $Row.Cells[0].Style.ForeColor = $(if ($On) { $global:Pal.Primary } else { $global:Pal.TextMuted })
    $Row.Cells[0].Style.SelectionForeColor = $Row.Cells[0].Style.ForeColor
}

function Update-RecuperacaoProgInfo {
    $r = $global:Recuperacao
    if (-not $r.ProgInfo) { return }
    $rows = @($r.ProgRows | Where-Object { $_ })
    $marked = @(Get-RecuperacaoProgMarked)
    if ($rows.Count -eq 0) {
        $r.ProgInfo.Text = 'Nenhum programa encontrado neste Windows.'
        $r.ProgInfo.ForeColor = $global:Pal.TextMuted
    } else {
        $sz = [double](($marked | Where-Object { $_.Size -gt 0 } | Measure-Object -Property Size -Sum).Sum)
        $t = '{0} programa(s); {1} marcado(s) para remover ({2}).' -f $rows.Count, $marked.Count, (Format-TIBytes $sz)
        $t += ' Clique na caixa ou use Espaço para marcar.'
        $r.ProgInfo.Text = $t
        $r.ProgInfo.ForeColor = $(if ($marked.Count -gt 0) { $global:Pal.Primary } else { $global:Pal.TextMuted })
    }
    Update-RecuperacaoButtons
}

function Switch-RecuperacaoProgRows {
    param($Rows)
    $all = @($Rows | Where-Object { $_ -and $_.Tag })
    $rows = @($all)
    if ($rows.Count -eq 0) { return }
    $on = (@($rows | Where-Object { -not $_.Tag.Marked }).Count -gt 0)
    foreach ($x in $rows) { Set-RecuperacaoProgMark -Row $x -On $on }
    Update-RecuperacaoProgInfo
}

function Set-RecuperacaoProgMarkAll {
    param([bool]$On)
    $grid = $global:Recuperacao.ProgGrid
    if (-not $grid) { return }
    foreach ($x in $grid.Rows) { if ($x.Tag) { Set-RecuperacaoProgMark -Row $x -On $On } }
    Update-RecuperacaoProgInfo
}

function Invoke-RecuperacaoListPrograms {
    $inst = Get-RecuperacaoTarget 'Listar os programas'
    if (-not $inst) { return }
    Show-RecuperacaoCard 'prog'
    [void](Invoke-TIAsync -Name 'Leitura dos programas (offline)' -Quiet -Context @{ Install = $inst } -Script {
        $ok = $true
        $items = @()
        try { $items = @(Get-TIOfflinePrograms -Install $Context.Install) }
        catch { $ok = $false; Emit ('Não foi possível ler os programas: {0}' -f $_.Exception.Message) 'Error' }
        [pscustomobject]@{ Kind = 'RecoveryPrograms'; Ok = $ok; Drive = [string]$Context.Install.Drive; Items = $items }
    } -OnComplete {
        param($r)
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'RecoveryPrograms' }) | Select-Object -First 1
        Fill-RecuperacaoProgGrid -Result $res
    })
}

function Fill-RecuperacaoProgGrid {
    param($Result)
    $r = $global:Recuperacao
    $grid = $r.ProgGrid
    if (-not $grid -or -not $Result) { return }
    $grid.Rows.Clear()
    if (-not $Result.Ok) {
        $r.ProgFor = ''; $r.ProgRows = @()
        Set-TIGridEmptyText $grid 'Não foi possível ler os programas (detalhes no console).'
        $r.ProgInfo.Text = 'Não foi possível ler os programas deste Windows.'; $r.ProgInfo.ForeColor = $global:Pal.Danger
        Update-RecuperacaoButtons
        return
    }
    $list = @($Result.Items | Where-Object { $_ -and $_.PSObject.Properties['KeyName'] } | Sort-Object Name)
    $r.ProgFor = [string]$Result.Drive
    $r.ProgRows = $list
    foreach ($p in $list) {
        # nada vem marcado: o técnico escolhe
        Add-Member -InputObject $p -NotePropertyName 'Marked' -NotePropertyValue $false -Force
        $leftover = ($p.PSObject.Properties['Leftover'] -and $p.Leftover)
        $orig = $(if ($p.Scope -eq 'Usuário') { 'Usuário: ' + $p.User } elseif ($p.Scope) { [string]$p.Scope } else { 'Máquina' })
        $ver = $(if ($leftover) { 'restos' } else { $p.Version })
        $size = $(if ($p.Size -ge 0) { Format-TIBytes $p.Size } else { '-' })
        $row = Add-TIRow -Grid $grid -Tag $p -Cells @('', $p.Name, $ver, $p.Publisher, $size, $orig) `
                         -SortKeys @($null, $p.Name, $ver, $p.Publisher, [double]$p.Size, $orig)
        if ($leftover) {
            $ns = @($p.Services).Count; $nf = @($p.Folders).Count
            $row.Cells[1].ToolTipText = ('Resto de antivírus ({0}): {1} serviço(s)/driver(s) e {2} pasta(s) que sobraram no PC.{3}' -f $p.Vendor, $ns, $nf, $(if ($nf) { "`n" + (@($p.Folders) -join "`n") } else { '' }))
            $row.Cells[1].Style.ForeColor = $global:Pal.Warning
            $row.Cells[1].Style.SelectionForeColor = $global:Pal.Warning
        } else {
            $row.Cells[1].ToolTipText = $(if ($p.FolderNote) { 'Pasta não será apagada: {0}{1}' -f $p.FolderNote, $(if ($p.Folder) { "`n" + $p.Folder } else { '' }) } else { 'Pasta: ' + $p.Folder })
        }
        Set-RecuperacaoProgMark -Row $row -On $false
        # Nada fica travado: runtime/antivírus só ganha um aviso ao passar o mouse.
        if ($p.Sensitive) {
            $row.Cells[0].ToolTipText = 'Atenção: ' + $p.Reason + '. Dá para remover; faça com cuidado.'
        } else {
            $row.Cells[0].ToolTipText = 'Marcar ou desmarcar'
        }
    }
    Clear-TIGridSelection $grid
    Set-TIGridEmptyText $grid 'Nenhum programa encontrado neste Windows.'
    Update-RecuperacaoProgInfo
}

function Get-RecuperacaoProgListText {
    param($Items, [int]$Max = 12)
    $txt = (@($Items | Select-Object -First $Max | ForEach-Object {
        if ($_.PSObject.Properties['Leftover'] -and $_.Leftover) {
            $ns = $(if ($_.PSObject.Properties['Services']) { @($_.Services).Count } else { 0 })
            $nf = $(if ($_.PSObject.Properties['Folders']) { @($_.Folders).Count } else { 0 })
            $f = ('restos: {0} serviço(s)/driver(s), {1} pasta(s)' -f $ns, $nf)
        } elseif ($_.FolderNote) { $f = 'pasta mantida: ' + $_.FolderNote } else { $f = 'apaga ' + $_.Folder }
        '  {0}  ({1})' -f $_.Name, $f
    }) -join "`n")
    if (@($Items).Count -gt $Max) { $txt += ("`n  e mais {0}" -f (@($Items).Count - $Max)) }
    return $txt
}

function Invoke-RecuperacaoRemovePrograms {
    $inst = Get-RecuperacaoTarget 'Remover programas'
    if (-not $inst) { return }
    if ($global:Recuperacao.ProgFor -ne (Get-RecuperacaoKey $inst)) { Show-TIToast -Text 'Liste os programas deste Windows antes.' -Type 'Warn'; return }
    $items = @(Get-RecuperacaoProgMarked)
    if ($items.Count -eq 0) { Show-TIToast -Text 'Marque ao menos um programa na lista.' -Type 'Warn'; return }
    $keep = New-Object System.Collections.ArrayList
    foreach ($row in @($global:Recuperacao.ProgRows | Where-Object { $_ -and -not $_.Marked })) {
        if ($row.PSObject.Properties['Folders'] -and @($row.Folders).Count) { foreach ($f in @($row.Folders)) { if ($f) { [void]$keep.Add([string]$f) } } }
        elseif ($row.Folder) { [void]$keep.Add([string]$row.Folder) }
    }
    $keep = @($keep)
    $msg = ("Remoção FORÇADA (offline) de {0} item(ns) do {1} ({2}):`n`n{3}`n`n" +
            "O que é feito: apaga a pasta do programa (só dentro de Arquivos de Programas, ProgramData ou AppData\Local\Programs, nunca seguindo junções), " +
            "os atalhos, a entrada na lista de programas e — quando é antivírus/segurança — também os SERVIÇOS e DRIVERS dele e as pastas de dados (ProgramData). " +
            "Em pasta travada pelo antivírus, o TI Suite toma posse e devolve a permissão para conseguir apagar.`n`n" +
            "O desinstalador do fabricante NÃO roda (o Windows está desligado). Nunca toca nos serviços essenciais do Windows nem nas pastas do sistema. " +
            "Use isto para o antivírus/programa que não sai com o PC ligado. Não dá para desfazer.") -f `
            $items.Count, $inst.Label, $inst.Drive, (Get-RecuperacaoProgListText $items)
    $sens = @($items | Where-Object { $_.Sensitive })
    if ($sens.Count -gt 0) {
        $sl = (@($sens | Select-Object -First 8 | ForEach-Object { '  ' + $_.Name + ' (' + $_.Reason + ')' }) -join "`n")
        if ($sens.Count -gt 8) { $sl += ("`n  e mais {0}" -f ($sens.Count - 8)) }
        $msg += ("`n`nATENÇÃO: a seleção inclui runtime(s)/antivírus. Remover pode afetar o Windows ou outros programas:`n{0}" -f $sl)
    }
    $msg += (Get-RecuperacaoHiberNote $inst)
    if (-not (Show-TIConfirm -Title 'Remover programas (offline)' -Message $msg -ConfirmText ('Remover {0} programa(s)' -f $items.Count) -Style 'Danger' -Icon 'Warning')) { return }
    $names = @($items | ForEach-Object { $_.Name })
    $audit = ($names | Select-Object -First 20) -join ', '
    if ($names.Count -gt 20) { $audit += (' e mais {0}' -f ($names.Count - 20)) }
    Write-TILog -Level 'Warn' -Message ('Remoção offline de {0} programa(s) solicitada para {1} em {2}.' -f $items.Count, $inst.Label, $inst.Drive)
    [void](Invoke-TIAsync -Name ('Remoção offline de {0} programa(s)' -f $items.Count) -RequiresAdmin `
            -AuditDetail ('Windows: {0}; Programas: {1}' -f $inst.Label, $audit) `
            -Context @{ Install = $inst; Items = $items; Keep = $keep } -Script {
        $res = New-TIRecoveryResult -Action 'programs' -Title 'Remoção offline de programas' -Install $Context.Install
        try {
            Assert-TIOfflineInstall $Context.Install
            if ($Context.Install.Hibernated) { Remove-TIHibernation -Install $Context.Install -Result $res }
            foreach ($o in @(Remove-TIOfflinePrograms -Install $Context.Install -Items $Context.Items -KeepFolders $Context.Keep)) {
                if (-not $o) { continue }
                $svc = $(if ($o.PSObject.Properties['Services'] -and $o.Services -gt 0) { '; {0} serviço(s)/driver(s)' -f $o.Services } else { '' })
                Add-TIRecoveryStep $res $o.Name $o.Level ('pasta {0}; {1} atalho(s); registro {2}{3}' -f $o.Folder, $o.Shortcuts, $o.Registry, $svc) -NoEmit
            }
        } catch {
            Add-TIRecoveryStep $res 'Remoção offline de programas' 'Error' $_.Exception.Message
        }
        $res
    } -OnComplete {
        param($r)
        Complete-RecuperacaoAction -Result $r
        Invoke-RecuperacaoListPrograms
    })
}

# --- Ferramentas --------------------------------------------------------------------
function Show-RecuperacaoCard {
    param([string]$Name)
    $c = $global:Recuperacao.Cards[$Name]
    if (-not $c -or $c.IsDisposed) { return }
    try {
        $card = $c.Parent
        $flow = $card.Parent
        if ($flow -is [System.Windows.Forms.ScrollableControl]) { $flow.ScrollControlIntoView($card) }
    } catch { }
}

function Start-RecuperacaoTool {
    param([string]$Name)
    $exe = Join-Path (Get-TISystem32) $Name
    try {
        $wd = $(if ($global:TIRoot -and (Test-Path -LiteralPath $global:TIRoot)) { $global:TIRoot } else { Get-TISystem32 })
        if ($Name -eq 'notepad.exe' -and $global:Recuperacao.LastLaudo -and (Test-Path -LiteralPath $global:Recuperacao.LastLaudo) -and $global:Recuperacao.OpenLaudo) {
            Start-Process -FilePath $exe -ArgumentList ('"{0}"' -f $global:Recuperacao.LastLaudo) -WorkingDirectory $wd
        } else {
            Start-Process -FilePath $exe -WorkingDirectory $wd
        }
    } catch {
        Show-TIToast -Text ('Não foi possível abrir {0}: {1}' -f $Name, $_.Exception.Message) -Type 'Error'
    } finally {
        $global:Recuperacao.OpenLaudo = $false
    }
}

function Open-RecuperacaoLaudo {
    $f = $global:Recuperacao.LastLaudo
    if (-not $f -or -not (Test-Path -LiteralPath $f)) { Show-TIToast -Text 'Nenhum laudo salvo nesta sessão.' -Type 'Info'; return }
    $global:Recuperacao.OpenLaudo = $true
    Start-RecuperacaoTool 'notepad.exe'
}

function Invoke-RecuperacaoPower {
    param([ValidateSet('reboot', 'shutdown')][string]$Mode)
    if ($global:TI.Busy) { Show-TIToast -Text 'Espere a tarefa atual terminar.' -Type 'Warn'; return }
    $isReboot = ($Mode -eq 'reboot')
    $ok = Show-TIConfirm -Title $(if ($isReboot) { 'Reiniciar' } else { 'Desligar' }) -Style 'Primary' -Icon 'Power' `
            -ConfirmText $(if ($isReboot) { 'Reiniciar agora' } else { 'Desligar agora' }) `
            -Message $(if ($isReboot) { "Reinicia o computador agora.`n`nPara testar o Windows reparado, retire o pendrive (ou escolha o disco no menu de boot). Os laudos e logs já estão gravados no pendrive." }
                       else { "Desliga o computador agora. Os laudos e logs já estão gravados no pendrive." })
    if (-not $ok) { return }
    try { [void](Save-TIAuditPending -Quiet -Final) } catch { }
    Write-TILog -Level 'Warn' -Message $(if ($isReboot) { 'Reiniciando o computador (wpeutil reboot).' } else { 'Desligando o computador (wpeutil shutdown).' })
    try {
        Start-Process -FilePath (Join-Path (Get-TISystem32) 'wpeutil.exe') -ArgumentList $Mode -WindowStyle Hidden
    } catch {
        Show-TIToast -Text ('Não foi possível {0}: {1}' -f $(if ($isReboot) { 'reiniciar' } else { 'desligar' }), $_.Exception.Message) -Type 'Error'
    }
}

# --- Montagem da área ------------------------------------------------------------------
# Faixa com interruptor e texto (verificação completa do disco)
function New-RecuperacaoSwitchRow {
    param($Parent, [string]$Text)
    $row = New-Object System.Windows.Forms.Panel
    $row.Tag = 'tirow'
    $row.Size = New-Object System.Drawing.Size((Get-TIInnerWidth $Parent), 30)
    $row.BackColor = [System.Drawing.Color]::Transparent
    $row.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 4)
    $sw = New-Object TISuite.ToggleSwitch
    $sw.Location = New-Object System.Drawing.Point(0, 3)
    $sw.AccessibleName = $Text
    $row.Controls.Add($sw)
    $lbl = New-TILabel -Text $Text -Size 8.5 -Muted
    $lbl.AutoSize = $false
    $lbl.AutoEllipsis = $true
    $lbl.Location = New-Object System.Drawing.Point(50, 6)
    $lbl.Size = New-Object System.Drawing.Size(([Math]::Max(60, $row.Width - 50)), 20)
    $lbl.Anchor = 'Top,Left,Right'
    $lbl.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lbl.Tag = $sw
    $lbl.Add_Click({ $this.Tag.Checked = -not $this.Tag.Checked })
    $row.Controls.Add($lbl)
    $Parent.Controls.Add($row)
    return $sw
}

$wsRecuperacao = @{
    Id       = 'recuperacao'
    Title    = 'Recuperação'
    Sub      = 'Repara o Windows instalado no disco, sem reinstalar'
    Icon     = 'Repair'
    Modes    = 'Recovery'
    Keywords = 'recuperacao reparo reparar boot inicializacao bcd bcdboot chkdsk disco sfc dism arquivos sistema atualizacao pendente driver modo seguranca bitlocker winpe pendrive programas remover offline laudo'

    OnActivate = { if (-not $global:Recuperacao.Scanned) { Invoke-RecuperacaoScan } }
    Refresh    = { Invoke-RecuperacaoScan }

    Actions = {
        param($Bar)
        $b1 = New-TIButton -Text 'Procurar de novo' -Style 'Outline' -Width 150 -Height 34 -Icon 'Refresh' -Tip 'Procurar o Windows nos discos de novo (Ctrl+R)'
        $b1.Add_Click({ Invoke-RecuperacaoScan })
        $Bar.Controls.Add($b1)
        $b2 = New-TIButton -Text 'Salvar laudo' -Style 'Ghost' -Width 126 -Height 34 -Icon 'Report' -Tip 'Grava o laudo do Windows escolhido na pasta laudos do pendrive'
        $b2.Add_Click({ Export-RecuperacaoLaudo })
        $Bar.Controls.Add($b2)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $w = $global:Theme.CardWidth
        $pe = Test-TIWinPE

        # --- Windows encontrados ------------------------------------------------
        $b0 = New-TICard -Parent $flow -Title 'Windows encontrados' -Stretch -Icon 'PC' -Width $w -Height 280 `
                -Desc 'Escolha o Windows a reparar. O Windows em execução nunca é alterado'
        $bar0 = New-TIButtonBar -Parent $b0
        $btnScan = New-TIButton -Text 'Procurar de novo' -Style 'Outline' -Width 150 -Height 36 -Icon 'Search'
        $btnScan.Add_Click({ Invoke-RecuperacaoScan })
        $bar0.Controls.Add($btnScan)
        $btnUnlock = New-TIButton -Text 'Destravar BitLocker' -Style 'Soft' -Width 170 -Height 36 -Icon 'Unlock' -Tip 'Destrava o volume escolhido com a chave de recuperação (48 números)'
        $btnUnlock.Enabled = $false
        $btnUnlock.Add_Click({ Invoke-RecuperacaoUnlock })
        $bar0.Controls.Add($btnUnlock)
        $global:Recuperacao.UnlockBtn = $btnUnlock
        $global:Recuperacao.Info = New-TIHint -Parent $b0 -Text 'Procurando o Windows nos discos...' -TopGap 0 -BottomGap 6
        $g0 = New-TIGrid -Parent $b0 -Headers @('Unidade', 'Windows', 'Computador', 'Livre', 'Situação') `
                         -Widths @(66, 290, 120, 140, 230) -EmptyText 'Procurando o Windows nos discos...'
        $g0.Tag = 'tistretch'
        $g0.Height = 150
        $g0.Add_SelectionChanged({ Select-RecuperacaoInstall })
        $global:Recuperacao.Grid = $g0

        # --- Reparos ------------------------------------------------------------
        $b1 = New-TICard -Parent $flow -Title 'Reparos' -Half -Icon 'Repair' -Width $w -Height 300 `
                -Desc 'Comece pelo Reparo automático; cada ação pede confirmação'
        $global:Recuperacao.TargetInfo = New-TIHint -Parent $b1 -Text 'Escolha o Windows na lista acima.' -Size 9 -BottomGap 8
        $btnAuto = New-TIButton -Text 'Reparo automático (recomendado)' -Style 'Primary' -Width 280 -Height 42 -Icon 'Repair' -GlyphSize 13 `
                -Tip 'Disco, inicialização, atualizações pendentes, SFC e DISM, na ordem certa'
        $btnAuto.Enabled = $false
        $btnAuto.Add_Click({ Invoke-RecuperacaoAuto })
        $b1.Controls.Add($btnAuto)
        $null = New-TIHint -Parent $b1 -Text 'Faz os passos abaixo na ordem certa e para se algo exigir sua decisão. Nada é reinstalado.' -BottomGap 6
        $bar1 = New-TIButtonBar -Parent $b1
        $defs = @(
            @('Reparar inicialização', 'Power', 'Recria os arquivos de boot (bcdboot), com cópia do BCD', { Invoke-RecuperacaoBoot }),
            @('Verificar disco', 'Diagnostic', 'chkdsk /f (ou /r com a verificação completa ligada)', { Invoke-RecuperacaoChkdsk }),
            @('Reparar arquivos do sistema', 'Shield', 'SFC offline e DISM (ScanHealth/RestoreHealth)', { Invoke-RecuperacaoSfc }),
            @('Desfazer atualização', 'Undo', 'Ações pendentes e atualizações recentes', { Invoke-RecuperacaoListPackages }),
            @('Remover driver', 'Remove', 'Drivers de terceiros que travam o Windows', { Invoke-RecuperacaoListDrivers }),
            @('Modo de segurança', 'Lock', 'Liga ou desliga o modo de segurança no BCD deste Windows', { Invoke-RecuperacaoSafeMode })
        )
        $btns = @($btnAuto)
        foreach ($d in $defs) {
            $bt = New-TIButton -Text $d[0] -Style 'Outline' -Width 196 -Height 36 -Icon $d[1] -Tip $d[2]
            $bt.Enabled = $false
            $bt.Add_Click($d[3])
            $bar1.Controls.Add($bt)
            $btns += $bt
        }
        $global:Recuperacao.RepairBtns = $btns
        $global:Recuperacao.FullSwitch = New-RecuperacaoSwitchRow -Parent $b1 -Text 'Verificação completa no Verificar disco (/r: setores defeituosos; pode levar horas)'
        $global:Recuperacao.SourceInfo = New-TIHint -Parent $b1 -Text 'Fonte para o DISM (opcional): pasta reparo\ do pendrive.' -Size 8 -BottomGap 2

        # --- Disco ----------------------------------------------------------------
        $b2 = New-TICard -Parent $flow -Title 'Disco' -Half -Icon 'Diagnostic' -Width $w -Height 230 -WithStatus `
                -Desc 'Saúde do disco do Windows escolhido'
        $null = New-TIHint -Parent $b2 -Text 'Escolha o Windows na lista para ver a saúde do disco.'
        $global:Recuperacao.DiskBody = $b2

        # --- Ferramentas ----------------------------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Ferramentas' -Half -Icon 'Terminal' -Width $w -Height 170 `
                -Desc $(if ($pe) { 'Prompt, Bloco de notas, laudo, reiniciar e desligar' } else { 'Prompt, Bloco de notas e laudo' })
        $bar3 = New-TIButtonBar -Parent $b3
        $t1 = New-TIButton -Text 'Prompt de comando' -Style 'Outline' -Width 160 -Height 36 -Icon 'Terminal'
        $t1.Add_Click({ Start-RecuperacaoTool 'cmd.exe' })
        $bar3.Controls.Add($t1)
        $t2 = New-TIButton -Text 'Bloco de notas' -Style 'Outline' -Width 140 -Height 36 -Icon 'Edit'
        $t2.Add_Click({ Start-RecuperacaoTool 'notepad.exe' })
        $bar3.Controls.Add($t2)
        $t3 = New-TIButton -Text 'Ver laudo' -Style 'Outline' -Width 116 -Height 36 -Icon 'Report' -Tip 'Abre o último laudo salvo no Bloco de notas'
        $t3.Enabled = $false
        $t3.Add_Click({ Open-RecuperacaoLaudo })
        $bar3.Controls.Add($t3)
        $global:Recuperacao.LaudoBtn = $t3
        $t4 = New-TIButton -Text 'Reiniciar' -Style 'Ghost' -Width 116 -Height 36 -Icon 'Sync'
        $t4.Add_Click({ Invoke-RecuperacaoPower -Mode 'reboot' })
        $t4.Visible = $pe
        $bar3.Controls.Add($t4)
        $t5 = New-TIButton -Text 'Desligar' -Style 'Ghost' -Width 110 -Height 36 -Icon 'Power'
        $t5.Add_Click({ Invoke-RecuperacaoPower -Mode 'shutdown' })
        $t5.Visible = $pe
        $bar3.Controls.Add($t5)
        if ($pe) {
            $null = New-TIHint -Parent $b3 -Text 'Aqui não há Explorer: o Bloco de notas abre arquivos (Arquivo > Abrir) e o Prompt copia arquivos. Ao reiniciar, retire o pendrive para o Windows ligar pelo disco.' -BottomGap 2
        }

        # --- Atualizações ---------------------------------------------------------
        $b4 = New-TICard -Parent $flow -Title 'Atualizações' -Stretch -Icon 'Update' -Width $w -Height 300 `
                -Desc 'Desfazer ações pendentes ou remover uma atualização recente que impede o Windows de ligar'
        $bar4 = New-TIButtonBar -Parent $b4
        $p1 = New-TIButton -Text 'Listar atualizações' -Style 'Outline' -Width 166 -Height 36 -Icon 'Search'
        $p1.Enabled = $false
        $p1.Add_Click({ Invoke-RecuperacaoListPackages })
        $bar4.Controls.Add($p1)
        $p2 = New-TIButton -Text 'Desfazer ações pendentes' -Style 'Primary' -Width 206 -Height 36 -Icon 'Undo' -Tip 'DISM /RevertPendingActions'
        $p2.Enabled = $false
        $p2.Add_Click({ Invoke-RecuperacaoRevert })
        $bar4.Controls.Add($p2)
        $p3 = New-TIButton -Text 'Remover a selecionada' -Style 'Danger' -Width 186 -Height 36 -Icon 'Remove'
        $p3.Enabled = $false
        $p3.Add_Click({ Invoke-RecuperacaoRemovePackage })
        $bar4.Controls.Add($p3)
        $global:Recuperacao.PkgBtns = @{ List = $p1; Revert = $p2; Remove = $p3 }
        $global:Recuperacao.PkgInfo = New-TIHint -Parent $b4 -Text 'Lista as atualizações dos últimos 60 dias e as pendentes do Windows escolhido.' -TopGap 0 -BottomGap 6
        $g4 = New-TIGrid -Parent $b4 -Headers @('Atualização', 'Tipo', 'Instalada em', 'Estado') -Widths @(300, 130, 200, 170) -EmptyText 'Clique em Listar atualizações.'
        $g4.Tag = 'tistretch'
        $g4.Height = 150
        $g4.Add_SelectionChanged({ Update-RecuperacaoButtons })
        $global:Recuperacao.PkgGrid = $g4
        $global:Recuperacao.Cards['pkg'] = $b4

        # --- Drivers ----------------------------------------------------------------
        $b5 = New-TICard -Parent $flow -Title 'Drivers de terceiros' -Stretch -Icon 'Settings' -Width $w -Height 300 `
                -Desc 'Remover o driver que causa tela azul ao ligar'
        $bar5 = New-TIButtonBar -Parent $b5
        $d1 = New-TIButton -Text 'Listar drivers' -Style 'Outline' -Width 140 -Height 36 -Icon 'Search'
        $d1.Enabled = $false
        $d1.Add_Click({ Invoke-RecuperacaoListDrivers })
        $bar5.Controls.Add($d1)
        $d2 = New-TIButton -Text 'Remover o selecionado' -Style 'Danger' -Width 186 -Height 36 -Icon 'Remove'
        $d2.Enabled = $false
        $d2.Add_Click({ Invoke-RecuperacaoRemoveDriver })
        $bar5.Controls.Add($d2)
        $global:Recuperacao.DrvBtns = @{ List = $d1; Remove = $d2 }
        $global:Recuperacao.DrvInfo = New-TIHint -Parent $b5 -Text 'Lista os drivers de terceiros (fabricantes) do Windows escolhido.' -TopGap 0 -BottomGap 6
        $g5 = New-TIGrid -Parent $b5 -Headers @('Driver', 'Fornecedor', 'Classe', 'Data', 'Versão', 'Arquivo') -Widths @(90, 190, 130, 100, 130, 170) -EmptyText 'Clique em Listar drivers.'
        $g5.Tag = 'tistretch'
        $g5.Height = 150
        $g5.Add_SelectionChanged({ Update-RecuperacaoButtons })
        $global:Recuperacao.DrvGrid = $g5
        $global:Recuperacao.Cards['drv'] = $b5

        # --- Programas (remoção offline) -------------------------------------------------
        $b6 = New-TICard -Parent $flow -Title 'Programas (remoção offline)' -Stretch -Icon 'Apps' -Width $w -Height 360 `
                -Desc 'Remoção forçada do antivírus/programa que não sai com o PC ligado: tira a pasta, os serviços, os drivers e os dados, de raiz. Também acha os restos de antivírus que sobraram no PC'
        $bar6 = New-TIButtonBar -Parent $b6
        $q1 = New-TIButton -Text 'Listar programas' -Style 'Outline' -Width 156 -Height 36 -Icon 'Search'
        $q1.Enabled = $false
        $q1.Add_Click({ Invoke-RecuperacaoListPrograms })
        $bar6.Controls.Add($q1)
        $q2 = New-TIButton -Text 'Remover marcados' -Style 'Danger' -Width 196 -Height 36 -Icon 'Remove'
        $q2.Enabled = $false
        $q2.Add_Click({ Invoke-RecuperacaoRemovePrograms })
        $bar6.Controls.Add($q2)
        $q3 = New-TIButton -Text 'Desmarcar todos' -Style 'Ghost' -Width 150 -Height 36 -Icon 'Undo'
        $q3.Enabled = $false
        $q3.Add_Click({ Set-RecuperacaoProgMarkAll -On $false })
        $bar6.Controls.Add($q3)
        $global:Recuperacao.ProgBtns = @{ List = $q1; Remove = $q2; None = $q3 }
        $global:Recuperacao.ProgInfo = New-TIHint -Parent $b6 -Text 'Lista os programas instalados no Windows escolhido. Nada vem marcado.' -TopGap 0 -BottomGap 6
        $g6 = New-TIGrid -Parent $b6 -Headers @('', 'Programa', 'Versão', 'Editor', 'Tamanho', 'Origem') `
                         -Widths @(40, 280, 110, 190, 96, 150) -Multi -EmptyText 'Clique em Listar programas.'
        $g6.Tag = 'tistretch'
        $g6.Height = 210
        $chk = $g6.Columns[0]
        $chk.AutoSizeMode = 'None'
        $chk.Width = 40
        $chk.SortMode = 'NotSortable'
        $chk.Resizable = 'False'
        $chk.DefaultCellStyle.Font = New-TIFont 12 Regular 'Segoe MDL2 Assets'
        $chk.DefaultCellStyle.Alignment = 'MiddleCenter'
        $chk.ToolTipText = 'Clique para marcar ou desmarcar todos'
        $g6.Add_CellMouseUp({
            param($s, $e)
            if ($e.Button -ne 'Left' -or $e.RowIndex -lt 0 -or $e.ColumnIndex -ne 0 -or $global:TI.Busy) { return }
            Switch-RecuperacaoProgRows @($s.Rows[$e.RowIndex])
        })
        $g6.Add_CellMouseDoubleClick({
            param($s, $e)
            if ($e.Button -ne 'Left' -or $e.RowIndex -lt 0 -or $e.ColumnIndex -le 0 -or $global:TI.Busy) { return }
            Switch-RecuperacaoProgRows @($s.Rows[$e.RowIndex])
        })
        $g6.Add_ColumnHeaderMouseClick({
            param($s, $e)
            if ($e.ColumnIndex -ne 0 -or $global:TI.Busy) { return }
            $free = @($global:Recuperacao.ProgRows | Where-Object { $_ -and -not $_.Protected })
            $allOn = ($free.Count -gt 0 -and @($free | Where-Object { -not $_.Marked }).Count -eq 0)
            Set-RecuperacaoProgMarkAll -On (-not $allOn)
        })
        $g6.Add_KeyDown({
            param($s, $e)
            if ($e.KeyCode -eq 'Space' -and -not $global:TI.Busy) {
                $e.Handled = $true
                $e.SuppressKeyPress = $true
                Switch-RecuperacaoProgRows @($s.SelectedRows)
            }
        })
        $global:Recuperacao.ProgGrid = $g6
        $global:Recuperacao.Cards['prog'] = $b6
    }
}

Register-TIWorkspace @wsRecuperacao
