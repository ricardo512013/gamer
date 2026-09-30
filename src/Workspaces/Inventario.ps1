# =====================================================================
# ÁREA: INVENTÁRIO - registro dos computadores numa planilha única
#   Arquivo: <pasta do app>\inventario\inventario.csv (modo portátil)
#            %LOCALAPPDATA%\TI-Suite\inventario.csv   (modo instalado)
#   Antes de cada gravação, uma cópia vai para inventario\backup (10 últimas;
#   no modo instalado, %LOCALAPPDATA%\TI-Suite\inventario-backup).
#   CSV com ";" e UTF-8 com BOM: abre certo no Excel em português.
#   Um PC nunca é duplicado: casa pelo número de série (da BIOS ou, em PC
#   montado, da placa-mãe), pelo UUID, pelo MAC e, por último, pelo nome.
#   Se a planilha não puder ser lida, nada é gravado (evita apagar linhas).
# =====================================================================

# ---------------------------------------------------------------------
# Regras usadas no worker (coleta) E na interface (planilha)
# ---------------------------------------------------------------------
$global:TIInventoryShared = @'

function Test-TIValidSerial {
    param([string]$Value)
    $v = ([string]$Value).Trim()
    if ($v.Length -lt 3) { return $false }
    $low = $v.ToLowerInvariant()
    $flat = ($low -replace '[_\s]+', ' ')
    $bad = @('to be filled by o.e.m.', 'to be filled by o.e.m', 'to be filled by oem', 'default string', 'system serial number',
             'not specified', 'not applicable', 'not available', 'none', 'n/a', 'invalid', '0123456789', '1234567890',
             '123456789', '12345678', 'chassis serial number', 'serial number', 'base board serial number',
             'baseboard serial number', 'system product name', 'system manufacturer', 'no asset tag', 'no asset information',
             'asset-1234567890', 'unknown', 'oem', 'o.e.m.', 'empty', 'xxxxxxxxxx', 'default', 'sn12345678')
    if ($bad -contains $low -or $bad -contains $flat) { return $false }
    if ($v -match '^0+$' -or $v -match '^(.)\1+$') { return $false }
    return $true
}
'@
$global:TIWorkerLib += $global:TIInventoryShared
. ([scriptblock]::Create($global:TIInventoryShared))

$global:TIWorkerLib += @'

# ---------------------------------------------------------------------
# INVENTÁRIO (roda no worker)
# ---------------------------------------------------------------------
# UUID da placa (Win32_ComputerSystemProduct): descarta os genéricos de fábrica
function Test-TIValidUuid {
    param([string]$Value)
    $v = ([string]$Value).Trim().Trim('{', '}').ToUpperInvariant()
    if ($v -notmatch '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$') { return $false }
    if (($v -replace '-', '') -match '^(.)\1+$') { return $false }
    $bad = @('03000200-0400-0500-0006-000700080009', '00020003-0004-0005-0006-000700080009', '12345678-1234-5678-90AB-CDDEEFAABBCC')
    if ($bad -contains $v) { return $false }
    return $true
}

function Format-TIMemoryText {
    param([double[]]$Modules)
    $mods = @($Modules | Where-Object { $_ -gt 0 })
    if ($mods.Count -eq 0) { return '' }
    $fmt = { param($b) if ($b -lt 1GB) { '{0} MB' -f [Math]::Round($b / 1MB) } else { '{0} GB' -f [Math]::Round($b / 1GB) } }
    $tot = ($mods | Measure-Object -Sum).Sum
    $totTxt = & $fmt $tot
    if ($mods.Count -eq 1) { return ('{0} (1 módulo)' -f $totTxt) }
    $sizes = @($mods | ForEach-Object { & $fmt $_ } | Select-Object -Unique)
    if ($sizes.Count -eq 1) { return ('{0} ({1} x {2})' -f $totTxt, $mods.Count, $sizes[0]) }
    return ('{0} ({1})' -f $totTxt, ((@($mods | ForEach-Object { & $fmt $_ })) -join ' + '))
}

# MAC de cabo e de Wi-Fi a partir de Get-NetAdapter -Physical.
# Bluetooth e banda larga móvel ficam de fora; adaptador USB (muitas vezes o
# do técnico) não vale como cabo; cabo de verdade é 802.3 (NdisPhysicalMedium 14).
function Select-TIInventoryMacs {
    param($Adapters)
    $wired = ''; $wiredAlt = ''; $wifi = ''; $wifiUsb = ''
    foreach ($n in @(@($Adapters | Where-Object { $_ }) | Sort-Object { [int]$_.ifIndex })) {
        $mac = ([string]$n.MacAddress).Trim()
        if (-not $mac -or ($mac -replace '[^0-9A-Fa-f]', '') -match '^0+$') { continue }
        $pmt  = [string]$n.PhysicalMediaType
        $desc = [string]$n.InterfaceDescription
        $ndis = -1
        try { if ($null -ne $n.NdisPhysicalMedium) { $ndis = [int]$n.NdisPhysicalMedium } } catch { }
        if ($pmt -match '(?i)blue|wireless wan' -or $ndis -eq 10 -or $ndis -eq 8 -or $desc -match '(?i)bluetooth') { continue }
        $usb = ([string]$n.PnPDeviceID -match '^(?i)USB\\')
        $isWifi = ($pmt -match '802\.11' -or [string]$n.MediaType -match '802\.11' -or $ndis -eq 9 -or
                   $desc -match '(?i)wi-?fi|wireless|wlan|802\.11')
        if ($isWifi) {
            if ($usb) { if (-not $wifiUsb) { $wifiUsb = $mac } }
            elseif (-not $wifi) { $wifi = $mac }
            continue
        }
        if ($usb) { continue }
        if ($pmt -match '802\.3' -or $ndis -eq 14) { if (-not $wired) { $wired = $mac } }
        elseif (-not $wiredAlt) { $wiredAlt = $mac }
    }
    if (-not $wired) { $wired = $wiredAlt }
    if (-not $wifi) { $wifi = $wifiUsb }
    return [pscustomobject]@{ Cabo = $wired; WiFi = $wifi }
}

# IP principal: prefere a placa com gateway e que não seja virtual (VirtualBox,
# Hyper-V, VMware, WSL); ignora 169.254.x.x (sem DHCP)
function Select-TIInventoryIp {
    param($Configs)
    $best = ''; $bestScore = -1
    foreach ($c in @($Configs | Where-Object { $_ })) {
        $st = ''
        try { $st = [string]$c.NetAdapter.Status } catch { }
        if ($st -and $st -ne 'Up') { continue }
        $ips = @(@($c.IPv4Address) | Where-Object { $_ } | ForEach-Object { [string]$_.IPAddress } |
                 Where-Object { $_ -and $_ -notmatch '^169\.254\.' -and $_ -notmatch '^127\.' })
        if ($ips.Count -eq 0) { continue }
        $desc = ('{0} {1}' -f [string]$c.InterfaceDescription, [string]$c.InterfaceAlias)
        $virtual = ($desc -match '(?i)hyper-v|virtualbox|vmware|vethernet|virtual|wsl|tap-|loopback|docker')
        $gw = $false
        try { $gw = (@(@($c.IPv4DefaultGateway) | Where-Object { $_ -and [string]$_.NextHop -and [string]$_.NextHop -ne '0.0.0.0' }).Count -gt 0) } catch { }
        $score = 0
        if ($gw) { $score += 4 }
        if (-not $virtual) { $score += 2 }
        if ($score -gt $bestScore) { $best = $ips[0]; $bestScore = $score }
    }
    return $best
}

function Get-TIInventoryData {
    Emit 'Coletando os dados do equipamento...' 'Info' 10
    $cs    = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $csp   = @(Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue) | Select-Object -First 1
    $bios  = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $board = @(Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue) | Select-Object -First 1
    $enc   = @(Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue) | Select-Object -First 1
    $os    = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu   = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue) | Select-Object -First 1
    $mods  = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $cv    = $null
    try { $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop } catch { }

    Emit 'Lendo memória, discos e placas de rede...' 'Info' 50
    $memTxt = Format-TIMemoryText -Modules ([double[]]@($mods | Where-Object { $_.Capacity } | ForEach-Object { [double]$_.Capacity }))
    if (-not $memTxt -and $cs -and $cs.TotalPhysicalMemory) { $memTxt = ('{0} GB' -f [Math]::Round([double]$cs.TotalPhysicalMemory / 1GB)) }

    $stor = New-Object System.Collections.ArrayList
    try {
        foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { Test-TIInternalDisk $_ } | Sort-Object DeviceId)) {
            [void]$stor.Add(('{0} {1}' -f (ConvertTo-TIMediaWord $d.MediaType $d.BusType), (Format-TIDiskSize ([double]$d.Size))))
        }
    } catch { }
    if ($stor.Count -eq 0) {
        foreach ($d in @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceType -ne 'USB' })) {
            [void]$stor.Add(('Disco {0}' -f (Format-TIDiskSize ([double]$d.Size))))
        }
    }

    $macs = [pscustomobject]@{ Cabo = ''; WiFi = '' }
    try { $macs = Select-TIInventoryMacs -Adapters @(Get-NetAdapter -Physical -ErrorAction Stop) } catch { }
    $ip = ''
    try { $ip = Select-TIInventoryIp -Configs @(Get-NetIPConfiguration -ErrorAction SilentlyContinue) } catch { }

    # Série: a da BIOS; em PC montado ("To be filled by O.E.M."), a da placa-mãe
    $biosSerial = ''
    if ($bios) { $biosSerial = ([string]$bios.SerialNumber).Trim() }
    $boardSerial = ''
    if ($board) { $boardSerial = ([string]$board.SerialNumber).Trim() }
    $serial = ''; $serialFrom = ''
    if (Test-TIValidSerial $biosSerial) { $serial = $biosSerial; $serialFrom = 'bios' }
    elseif (Test-TIValidSerial $boardSerial) { $serial = $boardSerial; $serialFrom = 'placa' }
    $uuid = ''
    if ($csp -and (Test-TIValidUuid ([string]$csp.UUID))) { $uuid = ([string]$csp.UUID).Trim().Trim('{', '}').ToUpperInvariant() }

    # Etiqueta de patrimônio gravada na BIOS; HP e outros repetem nela a própria série
    $asset = ''
    if ($enc) { $asset = ([string]$enc.SMBIOSAssetTag).Trim() }
    if (-not (Test-TIValidSerial $asset)) { $asset = '' }
    $flatAsset = ($asset -replace '\s', '').ToUpperInvariant()
    foreach ($s in @($biosSerial, $boardSerial, $serial)) {
        if ($flatAsset -and $flatAsset -eq (([string]$s) -replace '\s', '').ToUpperInvariant()) { $asset = '' }
    }

    $osName = ''
    if ($os) { $osName = ([string]$os.Caption) -replace '^Microsoft\s+', '' }
    $disp = ''
    if ($cv) { $disp = [string]$cv.DisplayVersion; if (-not $disp) { $disp = [string]$cv.ReleaseId } }
    $build = ''
    if ($os) { $build = [string]$os.BuildNumber; if ($cv -and $null -ne $cv.UBR) { $build += '.' + [string]$cv.UBR } }
    $dom = ''
    if ($cs) { $dom = $(if ($cs.PartOfDomain) { [string]$cs.Domain } else { 'Grupo ' + [string]$cs.Workgroup }) }

    Emit 'Dados do equipamento coletados.' 'Debug' 100
    return [pscustomobject]@{
        Computador    = $env:COMPUTERNAME
        Fabricante    = $(if ($cs) { ([string]$cs.Manufacturer).Trim() } else { '' })
        Modelo        = $(if ($cs) { ([string]$cs.Model).Trim() } else { '' })
        Serie         = $serial
        SerieFonte    = $serialFrom
        Uuid          = $uuid
        AssetTag      = $asset
        Processador   = $(if ($cpu) { (((([string]$cpu.Name) -split '@')[0]).Trim() -replace '\s{2,}', ' ') } else { '' })
        Memoria       = $memTxt
        Armazenamento = ($stor -join ' + ')
        Sistema       = ('{0} {1}' -f $osName, $disp).Trim()
        Build         = $build
        MacCabo       = [string]$macs.Cabo
        MacWifi       = [string]$macs.WiFi
        Ip            = $ip
        Dominio       = $dom
        Bios          = $(if ($bios) { ([string]$bios.SMBIOSBIOSVersion).Trim() } else { '' })
    }
}
'@

# ---------------------------------------------------------------------
# Planilha (roda na interface; funções puras testadas em dev\Test-Logic.ps1)
# ---------------------------------------------------------------------
$global:TIInventoryColumns = @(
    @{ K = 'Computador';    H = 'Computador' },
    @{ K = 'Patrimonio';    H = 'Patrimônio' },
    @{ K = 'Local';         H = 'Local' },
    @{ K = 'Fabricante';    H = 'Fabricante' },
    @{ K = 'Modelo';        H = 'Modelo' },
    @{ K = 'Serie';         H = 'Número de série' },
    @{ K = 'Processador';   H = 'Processador' },
    @{ K = 'Memoria';       H = 'Memória' },
    @{ K = 'Armazenamento'; H = 'Armazenamento' },
    @{ K = 'Sistema';       H = 'Sistema' },
    @{ K = 'Build';         H = 'Build' },
    @{ K = 'MacCabo';       H = 'MAC (cabo)' },
    @{ K = 'MacWifi';       H = 'MAC (Wi-Fi)' },
    @{ K = 'Ip';            H = 'IP' },
    @{ K = 'Dominio';       H = 'Domínio ou grupo' },
    @{ K = 'Bios';          H = 'BIOS' },
    @{ K = 'Uuid';          H = 'UUID' },
    @{ K = 'Observacao';    H = 'Observação' },
    @{ K = 'RegistradoEm';  H = 'Registrado em' },
    @{ K = 'AtualizadoEm';  H = 'Atualizado em' },
    @{ K = 'Tecnico';       H = 'Técnico' }
)

# Cabeçalhos que a coordenação costuma digitar à mão (valem só se a coluna
# oficial não existir na planilha)
$global:TIInventoryAliases = @{
    Computador = @('nomedocomputador', 'nomedopc', 'nomedamaquina', 'hostname', 'maquina')
    Patrimonio = @('numerodepatrimonio', 'nºdepatrimonio', 'ndepatrimonio', 'nodepatrimonio', 'plaqueta', 'tombamento',
                   'numerodetombamento', 'nºdetombamento')
    Serie      = @('serie', 'nºdeserie', 'ndeserie', 'nodeserie', 'numeroserial', 'serial', 'servicetag')
    Local      = @('localizacao', 'sala', 'setor')
    Observacao = @('observacoes', 'obs')
    Ip         = @('enderecoip')
    Sistema    = @('sistemaoperacional')
    Memoria    = @('memoriaram', 'ram')
}

# Colunas que o Excel estragaria ao abrir o CSV (zeros à esquerda, série longa
# em notação científica, IP virando número): vão como fórmula de texto ="000123"
$global:TIInventoryTextKeys = @('Patrimonio', 'Serie', 'Ip')

function Get-TIInventoryPath {
    if ($global:TIPortable) { return (Join-Path (Join-Path $global:TIRoot 'inventario') 'inventario.csv') }
    return (Join-Path (Join-Path $env:LOCALAPPDATA 'TI-Suite') 'inventario.csv')
}

function Get-TIInventoryBackupDir {
    param([string]$Path = (Get-TIInventoryPath))
    return (Join-Path (Split-Path -Parent $Path) $(if ($global:TIPortable) { 'backup' } else { 'inventario-backup' }))
}

# "Número de série" -> "numerodeserie" (cabeçalho reconhecido mesmo sem acento)
function ConvertTo-TIInventoryKey {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $norm = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([char]::IsLetterOrDigit($ch) -and [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append([char]::ToLowerInvariant($ch))
        }
    }
    return $sb.ToString()
}

# Excel não executa fórmula vinda da planilha (=, +, -, @ no começo viram texto)
function Protect-TICsvValue {
    param([string]$Value)
    if ($Value -match '^[=+\-@]') { return ("'" + $Value) }
    return $Value
}

function Unprotect-TICsvValue {
    param([string]$Value)
    if ($Value -match "^'[=+\-@]") { return $Value.Substring(1) }
    return $Value
}

# O Excel converteria (e estragaria) este texto ao abrir o CSV?
function Test-TIExcelNumber {
    param([string]$Value)
    $v = [string]$Value
    if ($v -notmatch '^\d[\d.,/eE+\-]*$') { return $false }
    if ($v -match '^0\d') { return $true }                                  # 000123 -> 123
    if ($v -match '^\d{12,}$') { return $true }                             # série longa -> 1,23457E+17
    if ($v -match '^\d+([.,]\d+)+$') { return $true }                       # IP, 1.234 -> número
    if ($v -match '^\d+[eE][+-]?\d+$') { return $true }                     # 12E3 -> 12000
    if ($v -match '^\d{1,4}[-/]\d{1,4}([-/]\d{1,4})?$') { return $true }    # 10-5, 01/02 -> data
    return $false
}

function Protect-TIInventoryCell {
    param([string]$Key, [string]$Value)
    $v = Protect-TICsvValue $Value
    if ($global:TIInventoryTextKeys -contains $Key -and (Test-TIExcelNumber $v)) { return ('="' + $v + '"') }
    return $v
}

function ConvertFrom-TIInventoryCell {
    param([string]$Value)
    $v = [string]$Value
    if ($v -match '^="(.*)"$') { $v = $Matches[1].Replace('""', '"') }
    return (Unprotect-TICsvValue $v)
}

# Valor de um registro da planilha (dicionário) ou dos dados coletados (objeto)
function Get-TIInventoryValue {
    param($Obj, [string]$Key)
    if ($null -eq $Obj) { return '' }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Key)) { return [string]$Obj[$Key] }
        return ''
    }
    $p = $Obj.PSObject.Properties[$Key]
    if ($p) { return [string]$p.Value }
    return ''
}

# Forma de comparar identificadores: sem espaços, maiúsculas e, se for só
# número, sem zeros à esquerda (o Excel costuma tirá-los)
function ConvertTo-TIInventoryId {
    param([string]$Value)
    $v = (([string]$Value).Trim() -replace '\s+', '').ToUpperInvariant()
    if ($v -match '^\d+$') { $v = $v.TrimStart('0'); if (-not $v) { $v = '0' } }
    return $v
}

function New-TIInventoryRecord {
    param($Data, [string]$Patrimonio = '', [string]$Local = '', [string]$Observacao = '', [string]$Tecnico = '', $When = $null)
    if (-not $When) { $When = Get-Date }
    $now = ([datetime]$When).ToString('dd/MM/yyyy HH:mm')
    $r = [ordered]@{}
    foreach ($c in $global:TIInventoryColumns) { $r[$c.K] = '' }
    foreach ($k in @('Computador', 'Fabricante', 'Modelo', 'Serie', 'Processador', 'Memoria', 'Armazenamento', 'Sistema', 'Build', 'MacCabo', 'MacWifi', 'Ip', 'Dominio', 'Bios', 'Uuid')) {
        if ($Data.PSObject.Properties[$k]) { $r[$k] = [string]$Data.$k }
    }
    $r['Patrimonio']   = $Patrimonio.Trim()
    $r['Local']        = $Local.Trim()
    $r['Observacao']   = $Observacao.Trim()
    $r['RegistradoEm'] = $now
    $r['AtualizadoEm'] = $now
    $r['Tecnico']      = $Tecnico
    return $r
}

# O que identifica um computador (linha da planilha ou dados coletados)
function Get-TIInventoryIdentity {
    param($Obj)
    $s = Get-TIInventoryValue $Obj 'Serie'
    # série inválida ou estragada pelo Excel (1,23457E+17) não identifica ninguém
    $serie = ''
    if ((Test-TIValidSerial $s) -and $s.Trim() -notmatch '^\d+([.,]\d+)?[eE][+-]?\d+$') { $serie = ConvertTo-TIInventoryId $s }
    $uuid = (Get-TIInventoryValue $Obj 'Uuid').Trim().Trim('{', '}').ToUpperInvariant()
    $macs = @(foreach ($k in @('MacCabo', 'MacWifi')) {
        $m = ((Get-TIInventoryValue $Obj $k) -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
        if ($m.Length -eq 12 -and $m -notmatch '^0+$') { $m }
    })
    return [pscustomobject]@{
        Serie = $serie
        Uuid  = $uuid
        Macs  = $macs
        Nome  = (Get-TIInventoryValue $Obj 'Computador').Trim().ToUpperInvariant()
    }
}

# Série ou UUID diferentes nos dois lados: com certeza são computadores diferentes
function Test-TIInventoryConflict {
    param($A, $B)
    if ($A.Serie -and $B.Serie -and $A.Serie -ne $B.Serie) { return $true }
    if ($A.Uuid -and $B.Uuid -and $A.Uuid -ne $B.Uuid) { return $true }
    return $false
}

# A regra única de "mesmo computador" (registrar, status e remover):
#   1. número de série; 2. UUID; 3. MAC, só para linha sem série (PC montado
#   renomeado); 4. nome, desde que série e UUID não digam que é outro PC.
# Devolve o índice e por onde casou (serie, uuid, mac, nome).
function Find-TIInventoryMatch {
    param($Rows, $Row)
    $list = @($Rows)
    $me = Get-TIInventoryIdentity $Row
    $ids = @(foreach ($r in $list) { Get-TIInventoryIdentity $r })
    if ($me.Serie) {
        for ($i = 0; $i -lt $ids.Count; $i++) {
            if ($ids[$i].Serie -eq $me.Serie) { return [pscustomobject]@{ Index = $i; By = 'serie' } }
        }
    }
    if ($me.Uuid) {
        for ($i = 0; $i -lt $ids.Count; $i++) {
            if ($ids[$i].Uuid -eq $me.Uuid -and -not (Test-TIInventoryConflict $me $ids[$i])) { return [pscustomobject]@{ Index = $i; By = 'uuid' } }
        }
    }
    if ($me.Macs.Count -gt 0) {
        for ($i = 0; $i -lt $ids.Count; $i++) {
            $o = $ids[$i]
            if ($o.Serie -or (Test-TIInventoryConflict $me $o)) { continue }
            foreach ($m in $o.Macs) {
                if ($me.Macs -contains $m) { return [pscustomobject]@{ Index = $i; By = 'mac' } }
            }
        }
    }
    if ($me.Nome) {
        for ($i = 0; $i -lt $ids.Count; $i++) {
            if ($ids[$i].Nome -eq $me.Nome -and -not (Test-TIInventoryConflict $me $ids[$i])) { return [pscustomobject]@{ Index = $i; By = 'nome' } }
        }
    }
    return [pscustomobject]@{ Index = -1; By = '' }
}

# -Row: registro ou dados coletados. -Serie/-Computador continuam aceitos.
function Find-TIInventoryIndex {
    param($Rows, $Row = $null, [string]$Serie = '', [string]$Computador = '')
    if ($null -eq $Row) { $Row = @{ Serie = $Serie; Computador = $Computador } }
    return (Find-TIInventoryMatch -Rows $Rows -Row $Row).Index
}

# Para remover: a linha exatamente igual à da lista; se o arquivo mudou
# desde então, a linha do mesmo computador (regra acima)
function Find-TIInventoryRowIndex {
    param($Rows, $Row)
    $list = @($Rows)
    for ($i = 0; $i -lt $list.Count; $i++) {
        $same = ($null -ne $list[$i])
        if ($same) {
            foreach ($c in $global:TIInventoryColumns) {
                if ((Get-TIInventoryValue $list[$i] $c.K) -cne (Get-TIInventoryValue $Row $c.K)) { $same = $false; break }
            }
        }
        if ($same) { return $i }
    }
    return (Find-TIInventoryIndex -Rows $list -Row $Row)
}

function Merge-TIInventoryRow {
    param($Rows, $New)
    $list = New-Object System.Collections.ArrayList
    foreach ($r in @($Rows)) { if ($r) { [void]$list.Add($r) } }
    $idx = Find-TIInventoryIndex -Rows $list.ToArray() -Row $New
    if ($idx -ge 0) {
        $old = $list[$idx]
        if ([string]$old['RegistradoEm']) { $New['RegistradoEm'] = [string]$old['RegistradoEm'] }
        # colunas que a coordenação acrescentou na planilha continuam na linha
        if ($old -is [System.Collections.IDictionary] -and $old.Contains('_extra') -and -not $New.Contains('_extra')) { $New['_extra'] = $old['_extra'] }
        $list[$idx] = $New
        return [pscustomobject]@{ Rows = $list.ToArray(); Updated = $true }
    }
    [void]$list.Add($New)
    return [pscustomobject]@{ Rows = $list.ToArray(); Updated = $false }
}

# Outro computador com o mesmo patrimônio (erro de digitação da plaqueta)
function Find-TIInventoryPatrimonio {
    param($Rows, [string]$Patrimonio, [int]$ExceptIndex = -1)
    $p = ConvertTo-TIInventoryId $Patrimonio
    if (-not $p) { return $null }
    $list = @($Rows)
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ($i -eq $ExceptIndex -or $null -eq $list[$i]) { continue }
        if ((ConvertTo-TIInventoryId (Get-TIInventoryValue $list[$i] 'Patrimonio')) -eq $p) { return $list[$i] }
    }
    return $null
}

# Peças que mudaram desde o último registro (memória retirada, SSD trocado...)
function Get-TIInventoryChanges {
    param($Old, $New)
    $out = New-Object System.Collections.ArrayList
    foreach ($f in @(
        @{ K = 'Processador';   L = 'Processador' },
        @{ K = 'Memoria';       L = 'Memória' },
        @{ K = 'Armazenamento'; L = 'Armazenamento' },
        @{ K = 'MacCabo';       L = 'MAC (cabo)' },
        @{ K = 'MacWifi';       L = 'MAC (Wi-Fi)' }
    )) {
        $a = (Get-TIInventoryValue $Old $f.K).Trim()
        $b = (Get-TIInventoryValue $New $f.K).Trim()
        if (-not $a) { continue }   # linha sem o dado (digitada à mão): nada a comparar
        $same = if ($f.K -like 'Mac*') { ($a -replace '[^0-9A-Fa-f]', '') -eq ($b -replace '[^0-9A-Fa-f]', '') } else { $a -eq $b }
        if (-not $same) { [void]$out.Add(('{0} {1} → {2}' -f $f.L, $a, $(if ($b) { $b } else { 'não encontrado' }))) }
    }
    return $out.ToArray()
}

# Chaves de ordenação da lista: data real e tamanho em bytes
function ConvertTo-TIInventoryDate {
    param([string]$Text)
    $fmts = [string[]]@('dd/MM/yyyy HH:mm', 'd/M/yyyy H:mm', 'dd/MM/yyyy HH:mm:ss', 'd/M/yyyy H:mm:ss', 'dd/MM/yyyy', 'd/M/yyyy')
    $dt = [datetime]::MinValue
    if ([datetime]::TryParseExact(([string]$Text).Trim(), $fmts, [System.Globalization.CultureInfo]::InvariantCulture,
                                  [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { return $dt }
    return [datetime]::MinValue
}

function ConvertTo-TIInventoryBytes {
    param([string]$Text, [switch]$First)
    $total = 0.0
    foreach ($m in [regex]::Matches([string]$Text, '(\d+(?:[.,]\d+)?)\s*(TB|GB|MB)')) {
        $n = [double]::Parse($m.Groups[1].Value.Replace(',', '.'), [System.Globalization.CultureInfo]::InvariantCulture)
        $mul = switch ($m.Groups[2].Value) { 'TB' { 1e12 } 'GB' { 1e9 } default { 1e6 } }
        $total += $n * $mul
        if ($First) { break }
    }
    return [double]$total
}

function ConvertTo-TIInventoryText {
    param($Rows)
    $list = @($Rows | Where-Object { $_ })
    # colunas extras (acrescentadas no Excel) voltam depois das colunas do app
    $extraNames = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($r in $list) {
        $x = $r['_extra']
        if ($x) { foreach ($n in @($x.Keys)) { if (-not $seen.ContainsKey($n)) { $seen[$n] = $true; [void]$extraNames.Add($n) } } }
    }
    $objs = New-Object System.Collections.ArrayList
    foreach ($r in $list) {
        $o = [ordered]@{}
        foreach ($c in $global:TIInventoryColumns) { $o[$c.H] = Protect-TIInventoryCell $c.K ([string]$r[$c.K]) }
        $x = $r['_extra']
        foreach ($n in $extraNames) { $o[$n] = $(if ($x -and $x.Contains($n)) { [string]$x[$n] } else { '' }) }
        [void]$objs.Add([pscustomobject]$o)
    }
    if ($objs.Count -eq 0) {
        return ((@($global:TIInventoryColumns | ForEach-Object { '"' + $_.H + '"' })) -join ';')
    }
    return ((@($objs.ToArray() | ConvertTo-Csv -NoTypeInformation -Delimiter ';')) -join "`r`n")
}

# Separador mais provável de uma linha (; do Excel pt-BR, vírgula ou tabulação)
function Get-TICsvDelimiter {
    param([string]$Line)
    $best = ';'
    $max = $Line.Split(';').Count - 1
    foreach ($d in @(',', "`t")) {
        $c = $Line.Split($d.ToCharArray()).Count - 1
        if ($c -gt $max) { $best = $d; $max = $c }
    }
    return $best
}

# Células de uma linha de CSV (respeita aspas)
function Split-TICsvLine {
    param([string]$Line, [string]$Delimiter = ';')
    $out = New-Object System.Collections.ArrayList
    $sb = New-Object System.Text.StringBuilder
    $inQ = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $ch = [string]$Line[$i]
        if ($inQ) {
            if ($ch -eq '"') {
                if ($i + 1 -lt $Line.Length -and [string]$Line[$i + 1] -eq '"') { [void]$sb.Append('"'); $i++ }
                else { $inQ = $false }
            } else { [void]$sb.Append($ch) }
        } elseif ($ch -eq '"') { $inQ = $true }
        elseif ($ch -eq $Delimiter) { [void]$out.Add($sb.ToString().Trim()); [void]$sb.Clear() }
        else { [void]$sb.Append($ch) }
    }
    [void]$out.Add($sb.ToString().Trim())
    return $out.ToArray()
}

function Get-TIInventoryHeaderMap {
    $canon = @{}
    foreach ($c in $global:TIInventoryColumns) {
        $canon[(ConvertTo-TIInventoryKey $c.H)] = $c.K
        $canon[(ConvertTo-TIInventoryKey $c.K)] = $c.K
    }
    $alias = @{}
    foreach ($k in $global:TIInventoryAliases.Keys) {
        foreach ($a in $global:TIInventoryAliases[$k]) { if (-not $canon.ContainsKey($a)) { $alias[$a] = $k } }
    }
    return [pscustomobject]@{ Canon = $canon; Alias = $alias }
}

# Lê o texto da planilha. O cabeçalho é procurado nas primeiras linhas (o Excel
# pode ter "sep=;" ou uma linha de título em cima). Sem cabeçalho reconhecido,
# lança erro: devolver lista vazia faria o próximo registro apagar a planilha.
function ConvertFrom-TIInventoryText {
    param([string]$Text)
    $rows = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($Text)) { return $rows.ToArray() }
    $lines = @($Text.TrimStart([char]0xFEFF) -split "`r?`n")
    $map = Get-TIInventoryHeaderMap

    $hdr = -1; $delim = ';'; $cells = @(); $forced = ''; $looked = 0
    for ($i = 0; $i -lt $lines.Count -and $looked -lt 10; $i++) {
        $t = $lines[$i].Trim()
        if (-not $t) { continue }
        $looked++
        if ($t -match '^"?sep=(.)"?$') { $forced = $Matches[1]; continue }
        $d = if ($forced) { $forced } else { Get-TICsvDelimiter $t }
        $c = @(Split-TICsvLine -Line $lines[$i] -Delimiter $d)
        $known = @{}
        foreach ($h in $c) {
            $key = ConvertTo-TIInventoryKey $h
            $k = $map.Canon[$key]
            if (-not $k) { $k = $map.Alias[$key] }
            if ($k) { $known[$k] = $true }
        }
        if ($known.Count -ge 2) { $hdr = $i; $delim = $d; $cells = $c; break }
    }
    if ($hdr -lt 0) {
        throw (New-Object System.IO.InvalidDataException('Cabeçalho da planilha não reconhecido: nenhuma das primeiras linhas tem as colunas Computador, Patrimônio, Número de série...'))
    }

    # Coluna -> chave do app (primeiro o nome oficial, depois os apelidos)
    $n = $cells.Count
    $colKey = New-Object 'string[]' $n
    $used = @{}
    for ($j = 0; $j -lt $n; $j++) {
        $k = $map.Canon[(ConvertTo-TIInventoryKey $cells[$j])]
        if ($k -and -not $used.ContainsKey($k)) { $colKey[$j] = $k; $used[$k] = $true }
    }
    for ($j = 0; $j -lt $n; $j++) {
        if ($colKey[$j]) { continue }
        $k = $map.Alias[(ConvertTo-TIInventoryKey $cells[$j])]
        if ($k -and -not $used.ContainsKey($k)) { $colKey[$j] = $k; $used[$k] = $true }
    }

    $body = ''
    if ($hdr + 1 -lt $lines.Count) { $body = ($lines[($hdr + 1)..($lines.Count - 1)]) -join "`n" }
    $names = @(for ($j = 0; $j -lt $n; $j++) { 'c' + $j })
    $objs = @()
    if (-not [string]::IsNullOrWhiteSpace($body)) { $objs = @($body | ConvertFrom-Csv -Delimiter $delim -Header $names) }

    # Colunas desconhecidas são guardadas (e regravadas) em vez de sumirem
    $reserved = @{}
    foreach ($c in $global:TIInventoryColumns) { $reserved[$c.H] = $true }
    $extraName = @{}
    for ($j = 0; $j -lt $n; $j++) {
        if ($colKey[$j]) { continue }
        $raw = ([string]$cells[$j]).Trim()
        $hasData = $false
        foreach ($o in $objs) { if (([string]$o.($names[$j])).Trim()) { $hasData = $true; break } }
        if (-not $raw -and -not $hasData) { continue }   # ";" sobrando no fim da linha
        $name = if ($raw) { $raw } else { 'Coluna {0}' -f ($j + 1) }
        $base = $name; $dup = 2
        while ($reserved.ContainsKey($name)) { $name = '{0} ({1})' -f $base, $dup; $dup++ }
        $reserved[$name] = $true
        $extraName[$j] = $name
    }

    foreach ($o in $objs) {
        $r = [ordered]@{}
        foreach ($c in $global:TIInventoryColumns) { $r[$c.K] = '' }
        $extra = $null
        $any = $false
        for ($j = 0; $j -lt $n; $j++) {
            $raw = $o.($names[$j])
            $v = if ($null -eq $raw) { '' } else { [string]$raw }
            if ($colKey[$j]) {
                $v = ConvertFrom-TIInventoryCell $v
                $r[$colKey[$j]] = $v
                if ($v.Trim()) { $any = $true }
            } elseif ($extraName.ContainsKey($j)) {
                if (-not $extra) { $extra = [ordered]@{} }
                $extra[$extraName[$j]] = $v
                if ($v.Trim()) { $any = $true }
            }
        }
        if ($extra) { $r['_extra'] = $extra }
        if ($any) { [void]$rows.Add($r) }
    }
    return $rows.ToArray()
}

# Lê o arquivo mesmo com o Excel aberto (ele tranca para escrita, não para leitura)
function Read-TIFileBytes {
    param([string]$Path)
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                                 ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try {
        $ms = New-Object System.IO.MemoryStream
        $fs.CopyTo($ms)
        return ,($ms.ToArray())
    } finally {
        $fs.Dispose()
    }
}

# Lê UTF-8 (com ou sem BOM), UTF-16 ou ANSI (Excel às vezes salva assim)
function Read-TITextAuto {
    param([string]$Path)
    $bytes = Read-TIFileBytes -Path $Path
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        return $strict.GetString($bytes)
    } catch {
        return [System.Text.Encoding]::GetEncoding(1252).GetString($bytes)
    }
}

function Read-TIInventory {
    param([string]$Path = (Get-TIInventoryPath))
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return (ConvertFrom-TIInventoryText -Text (Read-TITextAuto -Path $Path))
}

# Mantém só as $Keep cópias mais novas (o nome tem data e hora)
function Remove-TIOldBackups {
    param([string]$Dir, [int]$Keep = 10)
    if (-not (Test-Path -LiteralPath $Dir)) { return }
    $old = @(Get-ChildItem -LiteralPath $Dir -Filter 'inventario-*.csv' -File -ErrorAction SilentlyContinue |
             Sort-Object Name -Descending | Select-Object -Skip $Keep)
    foreach ($f in $old) { try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { } }
}

# Cópia de segurança antes de gravar: backup\inventario-AAAAMMDD-HHmmss.csv
function Backup-TIInventory {
    param([string]$Path = (Get-TIInventoryPath), [string]$BackupDir = '', [int]$Keep = 10)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    if (-not $BackupDir) { $BackupDir = Get-TIInventoryBackupDir -Path $Path }
    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $dest = Join-Path $BackupDir ('inventario-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [System.IO.File]::WriteAllBytes($dest, (Read-TIFileBytes -Path $Path))
    Remove-TIOldBackups -Dir $BackupDir -Keep $Keep
    return $dest
}

function Get-TIIoErrorCode {
    param($Exception)
    $ex = $Exception
    while ($ex) {
        if ($ex -is [System.IO.IOException]) { return ($ex.HResult -band 0xFFFF) }
        $ex = $ex.InnerException
    }
    return 0
}

# Grava num temporário e troca pelo arquivo antigo (File.Replace = renomeação):
# se o pendrive sair no meio, a planilha antiga fica inteira. Antes, faz a cópia
# de segurança na pasta backup.
function Save-TIInventory {
    param($Rows, [string]$Path = (Get-TIInventoryPath))
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $txt = ConvertTo-TIInventoryText -Rows $Rows
    $exists = [System.IO.File]::Exists($Path)
    if ($exists) {
        # Aberta no Excel ou somente leitura: falha aqui, antes de mexer em qualquer arquivo
        $probe = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
        $probe.Dispose()
        try { [void](Backup-TIInventory -Path $Path) } catch {
            if (Get-Command Write-TILog -ErrorAction SilentlyContinue) {
                Write-TILog -Level 'Warn' -Message ('Inventário: não foi possível guardar a cópia de segurança: {0}' -f $_.Exception.Message)
            }
        }
    }
    $tmp = $Path + '.tmp'
    $old = $Path + '.old'
    try {
        [System.IO.File]::WriteAllText($tmp, ($txt + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
        if ($exists) {
            if ([System.IO.File]::Exists($old)) { [System.IO.File]::Delete($old) }
            try {
                [System.IO.File]::Replace($tmp, $Path, $old)
            } catch {
                $err = $_
                # a troca falhou: a planilha antiga volta para o lugar, se tiver saído
                if (-not [System.IO.File]::Exists($Path) -and [System.IO.File]::Exists($old)) { try { [System.IO.File]::Move($old, $Path) } catch { } }
                $code = Get-TIIoErrorCode $err.Exception
                if ($code -in @(32, 33, 1175) -or -not [System.IO.File]::Exists($tmp)) { throw $err }
                # sistema de arquivos sem suporte à troca: cópia simples (a cópia de segurança já foi feita)
                [System.IO.File]::Copy($tmp, $Path, $true)
            }
            try { if ([System.IO.File]::Exists($old)) { [System.IO.File]::Delete($old) } } catch { }
        } else {
            [System.IO.File]::Move($tmp, $Path)
        }
    } finally {
        try { if ([System.IO.File]::Exists($tmp)) { [System.IO.File]::Delete($tmp) } } catch { }
    }
}

# ---------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------
$global:Inventario = @{
    Data        = $null
    Rows        = @()
    Search      = @()
    Loaded      = $false
    ReadError   = $null
    Collecting  = $false
    CollectName = 'Coleta dos dados do equipamento'
    Grid        = $null
    Values      = @{}
    Fields      = @{}
    Status      = $null
    RegisterBtn = $null
    RemoveBtn   = $null
    CountLabel  = $null
    FilterBox   = $null
}

# Motivo de uma falha de leitura/gravação, em português
function Get-InventarioErrorText {
    param($Exception)
    $ex = $Exception
    while ($ex) {
        if ($ex -is [System.IO.InvalidDataException]) {
            return 'o cabeçalho não foi reconhecido (falta a linha com Computador, Patrimônio, Número de série...)'
        }
        if ($ex -is [System.UnauthorizedAccessException]) {
            return 'sem permissão no arquivo ou na pasta (pendrive protegido contra gravação?)'
        }
        if ($ex -is [System.IO.DirectoryNotFoundException] -or $ex -is [System.IO.DriveNotFoundException] -or $ex -is [System.IO.FileNotFoundException]) {
            return 'a pasta da planilha não está acessível (o pendrive foi removido?)'
        }
        if ($ex -is [System.IO.IOException]) {
            if (($ex.HResult -band 0xFFFF) -in @(32, 33, 1175)) { return 'o arquivo está aberto em outro programa (feche-o no Excel)' }
            return ([string]$ex.Message).TrimEnd('.', ' ')
        }
        $ex = $ex.InnerException
    }
    return ([string]$Exception.Message).TrimEnd('.', ' ')
}

# Sem leitura, nada é gravado: Registrar e Remover ficam bloqueados até Atualizar
function Set-InventarioReadError {
    param([string]$Message)
    $global:Inventario.ReadError = $Message
    Write-TILog -Level 'Error' -Message ('Inventário: não foi possível ler a planilha: {0}.' -f $Message)
    Update-InventarioCount
    Update-InventarioSelection
    Update-InventarioThisPcStatus
}

function Update-InventarioSelection {
    $g = $global:Inventario.Grid
    $has = ($g -and $g.SelectedRows.Count -gt 0)
    if ($global:Inventario.RemoveBtn) {
        $global:Inventario.RemoveBtn.Enabled = ($has -and -not $global:TI.Busy -and -not $global:Inventario.ReadError)
    }
}

function Update-InventarioCount {
    $lbl = $global:Inventario.CountLabel
    if (-not $lbl) { return }
    $total = @($global:Inventario.Rows).Count
    $shown = $total
    if ($global:Inventario.Grid) { $shown = $global:Inventario.Grid.Rows.Count }
    if ($global:Inventario.ReadError) { $lbl.Text = 'Planilha não lida' }
    elseif ($shown -ne $total) { $lbl.Text = ('{0} de {1} computadores' -f $shown, $total) }
    elseif ($total -eq 1) { $lbl.Text = '1 computador registrado' }
    else { $lbl.Text = ('{0} computadores registrados' -f $total) }
}

function Update-InventarioThisPcStatus {
    $d = $global:Inventario.Data
    $st = $global:Inventario.Status
    $btn = $global:Inventario.RegisterBtn
    if (-not $st) { return }
    if ($global:Inventario.ReadError) {
        $st.Text = ('Não deu para ler a planilha: {0}. Registrar e remover ficam bloqueados para não apagar dados; resolva e clique em Atualizar.' -f $global:Inventario.ReadError)
        $st.ForeColor = $global:Pal.Danger
        if ($btn) { $btn.Enabled = $false }
        return
    }
    if (-not $d) {
        if ($global:Inventario.Collecting) {
            $st.Text = 'Coletando os dados deste computador...'
            $st.ForeColor = $global:Pal.TextMuted
        } else {
            $st.Text = 'Coleta não concluída. Clique em Atualizar para tentar de novo.'
            $st.ForeColor = $global:Pal.Warning
            foreach ($row in @($global:Inventario.Values.Values)) {
                if ($row.Value.Text -eq 'Lendo...') { Set-TIRowValue $row 'Não lido' 'dim' }
            }
        }
        if ($btn) { $btn.Enabled = $false }
        return
    }
    $m = Find-TIInventoryMatch -Rows $global:Inventario.Rows -Row $d
    if ($m.Index -ge 0) {
        $r = @($global:Inventario.Rows)[$m.Index]
        $reg = ([string]$r['RegistradoEm']).Trim()
        $upd = ([string]$r['AtualizadoEm']).Trim()
        # a data mais recente ganha a idade: "20/09/2026 15:30 (há 10 dias)"
        $rel = {
            param([string]$Text)
            $dt = ConvertTo-TIInventoryDate $Text
            if ($dt -eq [datetime]::MinValue) { return $Text }
            return (Format-TIDate $dt -Relative)
        }
        $when = if ($reg -and $upd -and $reg -ne $upd) { 'registrado em {0}, atualizado em {1}' -f $reg, (& $rel $upd) }
                elseif ($reg) { 'registrado em {0}' -f (& $rel $reg) }
                elseif ($upd) { 'atualizado em {0}' -f (& $rel $upd) }
                else { '' }
        $txt = if ($when) { 'Já está no inventário: {0}.' -f $when } else { 'Já está na planilha (linha sem data de registro).' }
        $oldName = ([string]$r['Computador']).Trim()
        if ($oldName -and $oldName -ne ([string]$d.Computador)) {
            $how = switch ($m.By) { 'serie' { 'pelo número de série' } 'uuid' { 'pelo UUID da placa-mãe' } 'mac' { 'pelo MAC' } default { '' } }
            $txt += (' Reconhecido {0}: na planilha o nome é {1}.' -f $how, $oldName)
        }
        $txt += ' Salvar de novo atualiza a mesma linha.'
        $chg = @(Get-TIInventoryChanges -Old $r -New $d)
        if ($chg.Count -gt 0) {
            $since = if ($upd) { 'desde ' + ($upd -split '\s+')[0] } elseif ($reg) { 'desde ' + ($reg -split '\s+')[0] } else { 'desde o último registro' }
            $txt += ("`n" + ('Mudou {0}: {1}.' -f $since, ($chg -join '; ')))
            $st.ForeColor = $global:Pal.Warning
        } else {
            $st.ForeColor = $global:Pal.Success
        }
        $st.Text = $txt
        if ($btn) { $btn.Text = 'Atualizar registro' }
        foreach ($k in @('Patrimonio', 'Local', 'Observacao')) {
            $tb = $global:Inventario.Fields[$k]
            if ($tb -and -not $tb.Text -and [string]$r[$k]) { $tb.Text = [string]$r[$k] }
        }
    } else {
        $st.Text = 'Este computador ainda não está no inventário.'
        $st.ForeColor = $global:Pal.TextMuted
        if ($btn) { $btn.Text = 'Registrar no inventário' }
        # etiqueta da BIOS só é sugerida quando não é a própria série (HP repete)
        $tb = $global:Inventario.Fields['Patrimonio']
        $tag = [string]$d.AssetTag
        if ($tb -and -not $tb.Text -and $tag -and (ConvertTo-TIInventoryId $tag) -ne (ConvertTo-TIInventoryId ([string]$d.Serie))) { $tb.Text = $tag }
    }
    if ($btn) { $btn.Enabled = -not $global:TI.Busy }
}

# Sugestões do campo Local: os locais que já estão na planilha
function Update-InventarioLocalSuggestions {
    $tb = $global:Inventario.Fields['Local']
    if (-not $tb) { return }
    try {
        $vals = @($global:Inventario.Rows | ForEach-Object { ([string]$_['Local']).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        $ac = New-Object System.Windows.Forms.AutoCompleteStringCollection
        if ($vals.Count -gt 0) { $ac.AddRange([string[]]$vals) }
        $tb.AutoCompleteCustomSource = $ac
    } catch { }
}

# Linhas que contêm todas as palavras do filtro (sem depender de acento)
function Select-InventarioRows {
    $all = @($global:Inventario.Rows)
    $q = ''
    if ($global:Inventario.FilterBox) { $q = $global:Inventario.FilterBox.Text.Trim() }
    $words = @((ConvertTo-TIPlain $q) -split '\s+' | Where-Object { $_ })
    if ($words.Count -eq 0) { return $all }
    $hay = @($global:Inventario.Search)
    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $all.Count; $i++) {
        $h = if ($i -lt $hay.Count) { [string]$hay[$i] } else { '' }
        $ok = $true
        foreach ($w in $words) { if (-not $h.Contains($w)) { $ok = $false; break } }
        if ($ok) { [void]$out.Add($all[$i]) }
    }
    return $out.ToArray()
}

function Fill-InventarioGrid {
    $grid = $global:Inventario.Grid
    if ($grid) {
        $rows = @(Select-InventarioRows)
        $grid.Rows.Clear()
        foreach ($r in $rows) {
            $upd = [string]$r['AtualizadoEm']
            [void](Add-TIRow -Grid $grid -Cells @(
                [string]$r['Computador'], [string]$r['Patrimonio'], [string]$r['Local'],
                (('{0} {1}' -f $r['Fabricante'], $r['Modelo']).Trim()), [string]$r['Serie'],
                [string]$r['Memoria'], [string]$r['Armazenamento'], [string]$r['Sistema'], $upd
            ) -SortKeys @($null, $null, $null, $null, $null,
                (ConvertTo-TIInventoryBytes ([string]$r['Memoria']) -First), (ConvertTo-TIInventoryBytes ([string]$r['Armazenamento'])),
                $null, (ConvertTo-TIInventoryDate $upd)
            ) -Tag $r)
        }
        $total = @($global:Inventario.Rows).Count
        if ($global:Inventario.ReadError -and $total -eq 0) {
            Set-TIGridEmptyText $grid 'A planilha não foi lida. Veja o aviso em Identificação e clique em Atualizar.'
        } elseif ($total -gt 0 -and $rows.Count -eq 0) {
            Set-TIGridEmptyText $grid 'Nenhum computador corresponde ao filtro.'
        } else {
            Set-TIGridEmptyText $grid 'Nenhum computador registrado ainda. Preencha a identificação e clique em Registrar.'
        }
        Clear-TIGridSelection $grid
    }
    Update-InventarioCount
    Update-InventarioSelection
}

function Load-InventarioList {
    try {
        $rows = @(Read-TIInventory)
        $global:Inventario.ReadError = $null
        $global:Inventario.Rows = $rows
        $global:Inventario.Search = @(foreach ($r in $rows) {
            ConvertTo-TIPlain (@($r['Computador'], $r['Patrimonio'], $r['Local'], $r['Serie'], $r['Fabricante'], $r['Modelo']) -join ' ')
        })
    } catch {
        # A lista anterior continua na tela (nada de "nenhum computador registrado")
        $msg = Get-InventarioErrorText $_.Exception
        Show-TIToast -Text ('Não deu para ler a planilha: {0}.' -f $msg) -Type 'Error' -Duration 5000
        $global:Inventario.ReadError = $msg
        Write-TILog -Level 'Error' -Message ('Inventário: não foi possível ler a planilha: {0} ({1})' -f $msg, $_.Exception.Message)
    }
    Update-InventarioLocalSuggestions
    Fill-InventarioGrid
    Update-InventarioThisPcStatus
}

# Depois de registrar: seleciona e mostra a linha deste PC
function Select-InventarioRow {
    param($Record)
    $grid = $global:Inventario.Grid
    if (-not $grid -or -not $Record) { return }
    $tags = @(foreach ($gr in $grid.Rows) { $gr.Tag })
    $idx = Find-TIInventoryIndex -Rows $tags -Row $Record
    if ($idx -lt 0 -and $global:Inventario.FilterBox -and $global:Inventario.FilterBox.Text) {
        $global:Inventario.FilterBox.Text = ''   # o filtro escondia a linha (TextChanged refaz a lista)
        $tags = @(foreach ($gr in $grid.Rows) { $gr.Tag })
        $idx = Find-TIInventoryIndex -Rows $tags -Row $Record
    }
    if ($idx -lt 0) { return }
    try {
        $row = $grid.Rows[$idx]
        $grid.ClearSelection()
        $grid.CurrentCell = $row.Cells[0]
        $row.Selected = $true
        $first = $grid.FirstDisplayedScrollingRowIndex
        $count = $grid.DisplayedRowCount($false)
        if ($first -lt 0 -or $idx -lt $first -or $idx -ge ($first + $count)) { $grid.FirstDisplayedScrollingRowIndex = $idx }
    } catch { }
    Update-InventarioSelection
}

# Cancelar não chama o OnComplete: este relógio percebe o fim da coleta
function Watch-InventarioCollect {
    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = 300
    $t.Add_Tick({
        if ($global:TI.Busy -and $global:TIAsync.Name -eq $global:Inventario.CollectName) { return }
        $this.Stop()
        $this.Dispose()
        if ($global:Inventario.Collecting) {
            $global:Inventario.Collecting = $false
            Update-InventarioThisPcStatus
        }
    })
    $t.Start()
}

function Invoke-InventarioCollect {
    if ($global:TI.Busy) { return }
    $global:Inventario.Collecting = $true
    $res = @(Invoke-TIAsync -Name $global:Inventario.CollectName -Quiet -Script {
        Get-TIInventoryData
    } -OnComplete {
        param($r)
        $global:Inventario.Collecting = $false
        $d = @($r | Where-Object { $_ -and $_.PSObject.Properties['Computador'] }) | Select-Object -First 1
        if (-not $d) { Update-InventarioThisPcStatus; return }
        $global:Inventario.Data = $d
        foreach ($k in @($global:Inventario.Values.Keys)) {
            $row = $global:Inventario.Values[$k]
            switch ($k) {
                'Modelo' { Set-TIRowValue $row (('{0} {1}' -f $d.Fabricante, $d.Modelo).Trim()) }
                'Serie'  {
                    $row.Label.Text = $(if ($d.SerieFonte -eq 'placa') { 'Série (placa-mãe)' } else { 'Número de série' })
                    if ($d.Serie) { Set-TIRowValue $row $d.Serie } else { Set-TIRowValue $row 'Não gravado pelo fabricante' 'warn' }
                }
                default  { Set-TIRowValue $row ([string]$d.$k) }
            }
        }
        Update-InventarioThisPcStatus
    })
    $started = ($res.Count -gt 0 -and $res[-1] -eq $true)
    if (-not $started) {
        $global:Inventario.Collecting = $false
        Update-InventarioThisPcStatus
        return
    }
    Update-InventarioThisPcStatus
    Watch-InventarioCollect
}

function Invoke-InventarioRegister {
    if ($global:TI.Busy) { Show-TIToast -Text 'Espere a tarefa atual terminar.' -Type 'Warn'; return }
    $d = $global:Inventario.Data
    if (-not $d) {
        if ($global:Inventario.Collecting) { Show-TIToast -Text 'Espere a coleta dos dados terminar.' -Type 'Warn' }
        else { Show-TIToast -Text 'Coleta não concluída. Clique em Atualizar para tentar de novo.' -Type 'Warn' }
        return
    }
    if ($global:Inventario.ReadError) {
        Show-TIToast -Text 'A planilha não foi lida: resolva o aviso e clique em Atualizar antes de registrar.' -Type 'Warn' -Duration 4500
        return
    }
    $fields = $global:Inventario.Fields
    $pat = $fields['Patrimonio'].Text.Trim()
    $loc = $fields['Local'].Text.Trim()
    $obs = $fields['Observacao'].Text.Trim()

    # Relê do disco (outro técnico pode ter gravado): sem leitura, nada é gravado
    try {
        $rows = @(Read-TIInventory)
    } catch {
        $msg = Get-InventarioErrorText $_.Exception
        Set-InventarioReadError $msg
        Show-TIToast -Text ('Nada foi gravado: {0}.' -f $msg) -Type 'Error' -Duration 5000
        return
    }
    $match = Find-TIInventoryMatch -Rows $rows -Row $d
    $old = if ($match.Index -ge 0) { $rows[$match.Index] } else { $null }

    # Campos vazios apagariam o que a planilha já tem para este PC: pergunta antes
    $patConfirmed = $false
    if ($old) {
        $lost = New-Object System.Collections.ArrayList
        foreach ($f in @(@{ K = 'Patrimonio'; L = 'Patrimônio'; V = $pat }, @{ K = 'Local'; L = 'Local'; V = $loc }, @{ K = 'Observacao'; L = 'Observação'; V = $obs })) {
            $was = ([string]$old[$f.K]).Trim()
            if ($was -and -not $f.V) { [void]$lost.Add(('{0}: {1}' -f $f.L, $was)) }
        }
        if ($lost.Count -gt 0) {
            $ok = Show-TIConfirm -Title 'Apagar dados da planilha?' -Icon 'Warning' -Style 'Danger' `
                    -Message ("A planilha já tem, para este computador:`n`n{0}`n`nOs campos estão vazios agora. Salvar assim apaga esses dados da planilha." -f ($lost -join "`n")) `
                    -ConfirmText 'Apagar e salvar' -CancelText 'Manter os dados'
            if (-not $ok) {
                foreach ($k in @('Patrimonio', 'Local', 'Observacao')) {
                    if (-not $fields[$k].Text.Trim() -and [string]$old[$k]) { $fields[$k].Text = [string]$old[$k] }
                }
                Show-TIToast -Text 'Os dados da planilha voltaram para os campos. Confira e registre de novo.' -Type 'Info' -Duration 4000
                return
            }
            $patConfirmed = (-not $pat -and ([string]$old['Patrimonio']).Trim())
        }
    }
    if (-not $pat -and -not $patConfirmed) {
        $ok = Show-TIConfirm -Title 'Registrar sem patrimônio?' -Icon 'Tag' -Style 'Primary' `
                -Message 'O número de patrimônio está vazio. Sem ele, o computador fica identificado só pelo número de série e pelo nome.' `
                -ConfirmText 'Registrar assim mesmo'
        if (-not $ok) { [void]$fields['Patrimonio'].Focus(); return }
    }
    # Patrimônio repetido em outro PC: quase sempre erro de digitação da plaqueta
    if ($pat) {
        $dup = Find-TIInventoryPatrimonio -Rows $rows -Patrimonio $pat -ExceptIndex $match.Index
        if ($dup) {
            $where = ([string]$dup['Local']).Trim()
            $ok = Show-TIConfirm -Title 'Patrimônio repetido' -Icon 'Tag' -Style 'Primary' `
                    -Message ("O patrimônio {0} já está no computador {1}{2}.`n`nConfira a plaqueta. Registrar assim mesmo deixa o número repetido na planilha." -f `
                              $pat, $(if ([string]$dup['Computador']) { [string]$dup['Computador'] } else { '(sem nome)' }), $(if ($where) { ' (' + $where + ')' } else { '' })) `
                    -ConfirmText 'Registrar assim mesmo'
            if (-not $ok) { [void]$fields['Patrimonio'].Focus(); return }
        }
    }

    $rec = New-TIInventoryRecord -Data $d -Patrimonio $pat -Local $loc -Observacao $obs -Tecnico $env:USERNAME
    $m = Merge-TIInventoryRow -Rows $rows -New $rec
    try {
        Save-TIInventory -Rows $m.Rows
    } catch {
        $msg = Get-InventarioErrorText $_.Exception
        Write-TILog -Level 'Error' -Message ('Falha ao salvar o inventário: {0} ({1})' -f $msg, $_.Exception.Message)
        Show-TIToast -Text ('Não deu para salvar: {0}. Nada foi alterado.' -f $msg) -Type 'Error' -Duration 5000
        return
    }
    $what = if ($m.Updated) { 'Registro atualizado' } else { 'Computador registrado' }
    Write-TILog -Level 'Success' -Message ('Inventário: {0} ({1}{2}).' -f $what.ToLower(), $d.Computador, $(if ($pat) { ', patrimônio ' + $pat } else { '' }))
    Write-TIAudit -Action 'Inventário' -Result $(if ($m.Updated) { 'ATUALIZADO' } else { 'REGISTRADO' }) -Detail ('patrimônio {0}; série {1}' -f $pat, $d.Serie)
    Show-TIToast -Text ($what + ' no inventário.') -Type 'Success'
    Load-InventarioList
    Select-InventarioRow -Record $rec
}

function Invoke-InventarioRemove {
    if ($global:TI.Busy) { Show-TIToast -Text 'Espere a tarefa atual terminar.' -Type 'Warn'; return }
    if ($global:Inventario.ReadError) {
        Show-TIToast -Text 'A planilha não foi lida: resolva o aviso e clique em Atualizar antes de remover.' -Type 'Warn' -Duration 4500
        return
    }
    $grid = $global:Inventario.Grid
    if (-not $grid -or $grid.SelectedRows.Count -eq 0) { Show-TIToast -Text 'Selecione um computador na lista.' -Type 'Warn'; return }
    $sel = $grid.SelectedRows[0].Tag
    $ok = Show-TIConfirm -Title 'Remover do inventário' -Style 'Danger' -Icon 'Warning' `
            -Message ("Remover '{0}' (patrimônio: {1}) da planilha?`n`nSó a linha do inventário é apagada; nada muda no computador." -f `
                      $sel['Computador'], $(if ([string]$sel['Patrimonio']) { $sel['Patrimonio'] } else { 'não informado' })) `
            -ConfirmText 'Remover'
    if (-not $ok) { return }
    try {
        $rows = @(Read-TIInventory)
    } catch {
        $msg = Get-InventarioErrorText $_.Exception
        Set-InventarioReadError $msg
        Show-TIToast -Text ('Nada foi removido: {0}.' -f $msg) -Type 'Error' -Duration 5000
        return
    }
    $idx = Find-TIInventoryRowIndex -Rows $rows -Row $sel
    if ($idx -lt 0) {
        Show-TIToast -Text 'Esse computador não está mais na planilha. A lista foi atualizada.' -Type 'Warn'
        Load-InventarioList
        return
    }
    $keep = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $rows.Count; $i++) { if ($i -ne $idx) { [void]$keep.Add($rows[$i]) } }
    try {
        Save-TIInventory -Rows $keep.ToArray()
    } catch {
        $msg = Get-InventarioErrorText $_.Exception
        Write-TILog -Level 'Error' -Message ('Falha ao atualizar o inventário: {0} ({1})' -f $msg, $_.Exception.Message)
        Show-TIToast -Text ('Não deu para salvar: {0}. Nada foi alterado.' -f $msg) -Type 'Error' -Duration 5000
        return
    }
    Write-TILog -Level 'Warn' -Message ('Inventário: {0} removido da planilha.' -f $sel['Computador'])
    Write-TIAudit -Action 'Inventário' -Result 'REMOVIDO' -Detail ('{0}; série {1}' -f $sel['Computador'], $sel['Serie'])
    Show-TIToast -Text 'Removido do inventário.' -Type 'Success'
    Load-InventarioList
}

function Open-InventarioFolder {
    $path = Get-TIInventoryPath
    $dir = Split-Path -Parent $path
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (Test-Path -LiteralPath $path) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $path) }
        else { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $dir) }
    } catch {
        Show-TIToast -Text 'Não foi possível abrir a pasta.' -Type 'Error'
    }
}

function Export-InventarioCopy {
    $path = Get-TIInventoryPath
    if (-not (Test-Path -LiteralPath $path)) { Show-TIToast -Text 'O inventário ainda está vazio.' -Type 'Warn'; return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = 'Salvar uma cópia do inventário'
    $dlg.Filter = 'Planilha CSV (*.csv)|*.csv'
    $dlg.FileName = ('inventario-{0}.csv' -f (Get-Date -Format 'yyyyMMdd'))
    if ($dlg.ShowDialog() -eq 'OK') {
        try {
            # lê com compartilhamento: funciona mesmo com a planilha aberta no Excel
            [System.IO.File]::WriteAllBytes($dlg.FileName, (Read-TIFileBytes -Path $path))
            Show-TIToast -Text 'Cópia salva.' -Type 'Success'
            Write-TILog -Level 'Success' -Message ('Cópia do inventário salva em: {0}' -f $dlg.FileName)
        } catch {
            Show-TIToast -Text 'Não foi possível salvar a cópia.' -Type 'Error'
        }
    }
    $dlg.Dispose()
}

$wsInventario = @{
    Id       = 'inventario'
    Title    = 'Inventário'
    Sub      = ('Registro dos computadores numa planilha única {0}' -f $(if ($global:TIPortable) { 'no pendrive' } else { 'neste computador' }))
    Icon     = 'CheckList'
    Keywords = 'inventario patrimonio serie numero mac planilha csv excel equipamento cadastro'

    OnActivate = {
        # sem leitura na última vez (Excel aberto?): tenta de novo ao voltar para a área
        if (-not $global:Inventario.Loaded -or $global:Inventario.ReadError) { $global:Inventario.Loaded = $true; Load-InventarioList }
        if (-not $global:Inventario.Data -and -not $global:Inventario.Collecting) { Invoke-InventarioCollect }
    }
    # Ctrl+R, F5 e o botão Atualizar passam por aqui (Invoke-TIRefreshActive)
    Refresh = { Load-InventarioList; Invoke-InventarioCollect }

    Actions = {
        param($Bar)
        $b1 = New-TIButton -Text 'Atualizar' -Style 'Outline' -Width 116 -Height 34 -Icon 'Refresh' -Tip 'Coletar de novo e reler a planilha (Ctrl+R)'
        $b1.Add_Click({ Invoke-TIRefreshActive })
        $Bar.Controls.Add($b1)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $where = $(if ($global:TIPortable) { 'no pendrive' } else { 'neste computador' })

        # --- Este computador ------------------------------------------------
        $b1 = New-TICard -Parent $flow -Title 'Este computador' -Desc 'Dados lidos do próprio equipamento (duplo clique copia o valor)' -Icon 'PC' -Half -Height 392
        $iw = Get-TIInnerWidth $b1
        foreach ($f in @(
            @{ K = 'Computador';    L = 'Computador' },
            @{ K = 'Modelo';        L = 'Fabricante e modelo' },
            @{ K = 'Serie';         L = 'Número de série' },
            @{ K = 'Processador';   L = 'Processador' },
            @{ K = 'Memoria';       L = 'Memória' },
            @{ K = 'Armazenamento'; L = 'Armazenamento' },
            @{ K = 'Sistema';       L = 'Sistema' },
            @{ K = 'MacCabo';       L = 'MAC (cabo)' },
            @{ K = 'MacWifi';       L = 'MAC (Wi-Fi)' },
            @{ K = 'Ip';            L = 'IP' }
        )) {
            $r = New-TIRow -Label $f.L -Value 'Lendo...' -Width $iw -LabelWidth 124
            $r.Value.ForeColor = $global:Pal.TextDim
            $b1.Controls.Add($r.Panel)
            $global:Inventario.Values[$f.K] = $r
        }

        # --- Identificação ----------------------------------------------------
        $b2 = New-TICard -Parent $flow -Title 'Identificação' -Desc 'Preenchida pelo técnico e salva junto com os dados' -Icon 'Tag' -Half -Height 392
        $global:Inventario.Fields['Patrimonio'] = New-TIField -Parent $b2 -Label 'Número de patrimônio' -Placeholder 'Número da plaqueta' -MaxLength 40
        $global:Inventario.Fields['Local'] = New-TIField -Parent $b2 -Label 'Local' -Placeholder 'Ex.: Laboratório 2, Secretaria' -MaxLength 60
        $global:Inventario.Fields['Observacao'] = New-TIField -Parent $b2 -Label 'Observação' -Placeholder 'Opcional' -MaxLength 200
        # Local sugere os nomes já usados (evita "Lab 2" e "Laboratório 2" para o mesmo lugar)
        $locBox = $global:Inventario.Fields['Local']
        $locBox.AutoCompleteMode = 'SuggestAppend'
        $locBox.AutoCompleteSource = 'CustomSource'
        foreach ($tb in $global:Inventario.Fields.Values) {
            $tb.Add_KeyDown({
                if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; Invoke-InventarioRegister }
            })
        }
        $global:Inventario.Status = New-TIHint -Parent $b2 -Text 'Coletando os dados deste computador...' -TopGap 4 -BottomGap 10
        $bar = New-TIButtonBar -Parent $b2
        $btnReg = New-TIButton -Text 'Registrar no inventário' -Style 'Primary' -Icon 'Save' -Width 214 -Height 38
        $btnReg.Enabled = $false
        $btnReg.Add_Click({ Invoke-InventarioRegister })
        $bar.Controls.Add($btnReg)
        $global:Inventario.RegisterBtn = $btnReg

        # --- Computadores registrados -------------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Computadores registrados' -Desc ('Planilha única {0}: abre no Excel ou no LibreOffice' -f $where) -Icon 'CheckList' -Width $global:Theme.CardWidth -Height 400 -Stretch
        $bar3 = New-TIButtonBar -Parent $b3
        $btnDel = New-TIButton -Text 'Remover do inventário' -Style 'Danger' -Icon 'Remove' -Width 200 -Height 36
        $btnDel.Enabled = $false
        $btnDel.Add_Click({ Invoke-InventarioRemove })
        $bar3.Controls.Add($btnDel)
        $global:Inventario.RemoveBtn = $btnDel
        $btnOpen = New-TIButton -Text 'Abrir pasta' -Style 'Outline' -Icon 'FolderOpen' -Width 130 -Height 36
        $btnOpen.Add_Click({ Open-InventarioFolder })
        $bar3.Controls.Add($btnOpen)
        $btnCopy = New-TIButton -Text 'Salvar cópia' -Style 'Ghost' -Icon 'Export' -Width 136 -Height 36
        $btnCopy.Add_Click({ Export-InventarioCopy })
        $bar3.Controls.Add($btnCopy)
        $global:Inventario.CountLabel = Add-TIBarLabel -Bar $bar3 -Text ''
        $null = New-TIHint -Parent $b3 -Size 8 -TopGap 0 -BottomGap 6 `
                    -Text ('Arquivo: {0}. Antes de cada gravação, uma cópia vai para {1} (10 últimas).' -f (Get-TIInventoryPath), (Get-TIInventoryBackupDir))

        $filterRow = New-Object System.Windows.Forms.Panel
        $filterRow.Tag = 'tirow'
        $filterRow.Size = New-Object System.Drawing.Size((Get-TIInnerWidth $b3), 36)
        $filterRow.BackColor = [System.Drawing.Color]::Transparent
        $filterRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
        $b3.Controls.Add($filterRow)
        $flt = New-Object System.Windows.Forms.TextBox
        $flt.Location = New-Object System.Drawing.Point(0, 3)
        $flt.Size = New-Object System.Drawing.Size(380, 28)
        $flt.BackColor = $global:Pal.Bg
        $flt.ForeColor = $global:Pal.TextMain
        $flt.BorderStyle = 'FixedSingle'
        $flt.Font = New-TIFont 9.5
        $flt.MaxLength = 80
        $flt.Add_TextChanged({ Fill-InventarioGrid })
        $flt.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $this.Text = ''; $_.SuppressKeyPress = $true } })
        $filterRow.Controls.Add($flt)
        $global:Inventario.FilterBox = $flt
        $null = Add-TIPlaceholder -TextBox $flt -Text 'Filtrar por nome, patrimônio, local, série ou modelo'

        $grid = New-TIGrid -Parent $b3 -Headers @('Computador', 'Patrimônio', 'Local', 'Modelo', 'Série', 'Memória', 'Armazenamento', 'Sistema', 'Atualizado em') `
                           -Widths @(130, 100, 130, 180, 120, 140, 150, 170, 120) `
                           -EmptyText 'Nenhum computador registrado ainda. Preencha a identificação e clique em Registrar.'
        $grid.Tag = 'tistretch'
        $grid.Height = 420
        $grid.Add_SelectionChanged({ Update-InventarioSelection })
        $global:Inventario.Grid = $grid
    }
}

Register-TIWorkspace @wsInventario
