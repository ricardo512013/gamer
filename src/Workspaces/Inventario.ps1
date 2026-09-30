# =====================================================================
# ÁREA: INVENTÁRIO - registro dos computadores numa planilha no pendrive
#   Arquivo: <pasta do app>\inventario\inventario.csv (modo portátil)
#            %LOCALAPPDATA%\TI-Suite\inventario.csv   (modo instalado)
#   CSV com ";" e UTF-8 com BOM: abre certo no Excel em português.
#   Um PC nunca é duplicado: casa pelo número de série (ou pelo nome,
#   quando o fabricante não gravou série).
# =====================================================================

$global:TIWorkerLib += @'

# ---------------------------------------------------------------------
# INVENTÁRIO (roda no worker)
# ---------------------------------------------------------------------
function Test-TIValidSerial {
    param([string]$Value)
    $v = ([string]$Value).Trim()
    if ($v.Length -lt 3) { return $false }
    $bad = @('to be filled by o.e.m.', 'to be filled by oem', 'default string', 'system serial number', 'not specified',
             'not applicable', 'none', 'n/a', 'invalid', '0123456789', '1234567890', 'chassis serial number',
             'serial number', 'no asset tag', 'no asset information', 'asset-1234567890', 'unknown', 'oem', 'o.e.m.',
             'empty', 'xxxxxxxxxx', 'default', 'sn12345678')
    if ($bad -contains $v.ToLowerInvariant()) { return $false }
    if ($v -match '^0+$' -or $v -match '^(.)\1+$') { return $false }
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

function Get-TIInventoryData {
    Emit 'Coletando os dados do equipamento...' 'Info' 10
    $cs   = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $enc  = @(Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue) | Select-Object -First 1
    $os   = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu  = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue) | Select-Object -First 1
    $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $cv   = $null
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

    $macWired = ''; $macWifi = ''
    try {
        foreach ($n in @(Get-NetAdapter -Physical -ErrorAction Stop | Sort-Object ifIndex)) {
            $isWifi = ([string]$n.PhysicalMediaType -match '802\.11' -or [string]$n.MediaType -match '802\.11' -or
                       [string]$n.InterfaceDescription -match '(?i)wi-?fi|wireless|wlan|802\.11')
            if ($isWifi) { if (-not $macWifi) { $macWifi = [string]$n.MacAddress } }
            elseif (-not $macWired) { $macWired = [string]$n.MacAddress }
        }
    } catch { }
    $ip = ''
    try {
        $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
               Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } | Select-Object -First 1
        if ($cfg) { $ip = [string](@($cfg.IPv4Address)[0].IPAddress) }
    } catch { }

    $serial = ''
    if ($bios) { $serial = ([string]$bios.SerialNumber).Trim() }
    if (-not (Test-TIValidSerial $serial)) { $serial = '' }
    $asset = ''
    if ($enc) { $asset = ([string]$enc.SMBIOSAssetTag).Trim() }
    if (-not (Test-TIValidSerial $asset)) { $asset = '' }

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
        AssetTag      = $asset
        Processador   = $(if ($cpu) { (((([string]$cpu.Name) -split '@')[0]).Trim() -replace '\s{2,}', ' ') } else { '' })
        Memoria       = $memTxt
        Armazenamento = ($stor -join ' + ')
        Sistema       = ('{0} {1}' -f $osName, $disp).Trim()
        Build         = $build
        MacCabo       = $macWired
        MacWifi       = $macWifi
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
    @{ K = 'Observacao';    H = 'Observação' },
    @{ K = 'RegistradoEm';  H = 'Registrado em' },
    @{ K = 'AtualizadoEm';  H = 'Atualizado em' },
    @{ K = 'Tecnico';       H = 'Técnico' }
)

function Get-TIInventoryPath {
    if ($global:TIPortable) { return (Join-Path (Join-Path $global:TIRoot 'inventario') 'inventario.csv') }
    return (Join-Path (Join-Path $env:LOCALAPPDATA 'TI-Suite') 'inventario.csv')
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

function New-TIInventoryRecord {
    param($Data, [string]$Patrimonio = '', [string]$Local = '', [string]$Observacao = '', [string]$Tecnico = '', $When = $null)
    if (-not $When) { $When = Get-Date }
    $now = ([datetime]$When).ToString('dd/MM/yyyy HH:mm')
    $r = [ordered]@{}
    foreach ($c in $global:TIInventoryColumns) { $r[$c.K] = '' }
    foreach ($k in @('Computador', 'Fabricante', 'Modelo', 'Serie', 'Processador', 'Memoria', 'Armazenamento', 'Sistema', 'Build', 'MacCabo', 'MacWifi', 'Ip', 'Dominio', 'Bios')) {
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

function Find-TIInventoryIndex {
    param($Rows, [string]$Serie, [string]$Computador)
    $list = @($Rows)
    if ($Serie) {
        for ($i = 0; $i -lt $list.Count; $i++) { if ([string]$list[$i]['Serie'] -eq $Serie) { return $i } }
    }
    if ($Computador) {
        for ($i = 0; $i -lt $list.Count; $i++) {
            $rs = [string]$list[$i]['Serie']
            if ([string]$list[$i]['Computador'] -eq $Computador -and (-not $rs -or -not $Serie -or $rs -eq $Serie)) { return $i }
        }
    }
    return -1
}

function Merge-TIInventoryRow {
    param($Rows, $New)
    $list = New-Object System.Collections.ArrayList
    foreach ($r in @($Rows)) { if ($r) { [void]$list.Add($r) } }
    $idx = Find-TIInventoryIndex -Rows $list.ToArray() -Serie ([string]$New['Serie']) -Computador ([string]$New['Computador'])
    if ($idx -ge 0) {
        $old = $list[$idx]
        if ([string]$old['RegistradoEm']) { $New['RegistradoEm'] = [string]$old['RegistradoEm'] }
        $list[$idx] = $New
        return [pscustomobject]@{ Rows = $list.ToArray(); Updated = $true }
    }
    [void]$list.Add($New)
    return [pscustomobject]@{ Rows = $list.ToArray(); Updated = $false }
}

function Test-TIInventorySame {
    param($A, $B)
    $sa = [string]$A['Serie']; $sb = [string]$B['Serie']
    if ($sa -and $sb) { return ($sa -eq $sb) }
    return ([string]$A['Computador'] -eq [string]$B['Computador'] -and [string]$A['RegistradoEm'] -eq [string]$B['RegistradoEm'])
}

function ConvertTo-TIInventoryText {
    param($Rows)
    $objs = New-Object System.Collections.ArrayList
    foreach ($r in @($Rows)) {
        if (-not $r) { continue }
        $o = [ordered]@{}
        foreach ($c in $global:TIInventoryColumns) { $o[$c.H] = Protect-TICsvValue ([string]$r[$c.K]) }
        [void]$objs.Add([pscustomobject]$o)
    }
    if ($objs.Count -eq 0) {
        return ((@($global:TIInventoryColumns | ForEach-Object { '"' + $_.H + '"' })) -join ';')
    }
    return ((@($objs.ToArray() | ConvertTo-Csv -NoTypeInformation -Delimiter ';')) -join "`r`n")
}

function ConvertFrom-TIInventoryText {
    param([string]$Text)
    $rows = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($Text)) { return $rows.ToArray() }
    $first = ($Text.TrimStart() -split "`r?`n", 2)[0]
    $delim = ';'
    if ($first.Split(',').Count -gt $first.Split(';').Count) { $delim = ',' }
    $map = @{}
    foreach ($c in $global:TIInventoryColumns) {
        $map[(ConvertTo-TIInventoryKey $c.H)] = $c.K
        $map[(ConvertTo-TIInventoryKey $c.K)] = $c.K
    }
    foreach ($o in @($Text | ConvertFrom-Csv -Delimiter $delim)) {
        $r = [ordered]@{}
        foreach ($c in $global:TIInventoryColumns) { $r[$c.K] = '' }
        $any = $false
        foreach ($p in $o.PSObject.Properties) {
            $k = $map[(ConvertTo-TIInventoryKey $p.Name)]
            if ($k) {
                $v = Unprotect-TICsvValue ([string]$p.Value)
                $r[$k] = $v
                if ($v) { $any = $true }
            }
        }
        if ($any) { [void]$rows.Add($r) }
    }
    return $rows.ToArray()
}

# Lê UTF-8 (com ou sem BOM), UTF-16 ou ANSI (Excel às vezes salva assim)
function Read-TITextAuto {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
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
    $path = Get-TIInventoryPath
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return (ConvertFrom-TIInventoryText -Text (Read-TITextAuto -Path $path))
}

# Grava num temporário e depois copia por cima: se o pendrive sair no meio, a planilha antiga fica inteira
function Save-TIInventory {
    param($Rows)
    $path = Get-TIInventoryPath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $txt = ConvertTo-TIInventoryText -Rows $Rows
    $tmp = $path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, ($txt + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    try {
        [System.IO.File]::Copy($tmp, $path, $true)
    } finally {
        try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch { }
    }
}

# ---------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------
$global:Inventario = @{
    Data        = $null
    Rows        = @()
    Loaded      = $false
    Grid        = $null
    Values      = @{}
    Fields      = @{}
    Status      = $null
    RegisterBtn = $null
    RemoveBtn   = $null
    CountLabel  = $null
}

function Update-InventarioSelection {
    $g = $global:Inventario.Grid
    $has = ($g -and $g.SelectedRows.Count -gt 0)
    if ($global:Inventario.RemoveBtn) { $global:Inventario.RemoveBtn.Enabled = ($has -and -not $global:TI.Busy) }
}

function Update-InventarioThisPcStatus {
    $d = $global:Inventario.Data
    $st = $global:Inventario.Status
    $btn = $global:Inventario.RegisterBtn
    if (-not $st) { return }
    if (-not $d) {
        $st.Text = 'Coletando os dados deste computador...'
        $st.ForeColor = $global:Pal.TextMuted
        if ($btn) { $btn.Enabled = $false }
        return
    }
    $idx = Find-TIInventoryIndex -Rows $global:Inventario.Rows -Serie ([string]$d.Serie) -Computador ([string]$d.Computador)
    if ($idx -ge 0) {
        $r = @($global:Inventario.Rows)[$idx]
        $st.Text = ('Já está no inventário (registrado em {0}, atualizado em {1}). Salvar de novo atualiza a mesma linha.' -f $r['RegistradoEm'], $r['AtualizadoEm'])
        $st.ForeColor = $global:Pal.Success
        if ($btn) { $btn.Text = 'Atualizar registro' }
        foreach ($k in @('Patrimonio', 'Local', 'Observacao')) {
            $tb = $global:Inventario.Fields[$k]
            if ($tb -and -not $tb.Text -and [string]$r[$k]) { $tb.Text = [string]$r[$k] }
        }
    } else {
        $st.Text = 'Este computador ainda não está no inventário.'
        $st.ForeColor = $global:Pal.TextMuted
        if ($btn) { $btn.Text = 'Registrar no inventário' }
        $tb = $global:Inventario.Fields['Patrimonio']
        if ($tb -and -not $tb.Text -and $d.AssetTag) { $tb.Text = [string]$d.AssetTag }
    }
    if ($btn) { $btn.Enabled = -not $global:TI.Busy }
}

function Load-InventarioList {
    $rows = @()
    try {
        $rows = @(Read-TIInventory)
    } catch {
        Write-TILog -Level 'Error' -Message ('Não foi possível ler o inventário: {0}' -f $_.Exception.Message)
        Show-TIToast -Text 'Não foi possível ler a planilha do inventário.' -Type 'Error'
    }
    $global:Inventario.Rows = $rows
    $grid = $global:Inventario.Grid
    if ($grid) {
        $grid.Rows.Clear()
        foreach ($r in $rows) {
            [void](Add-TIRow -Grid $grid -Cells @(
                [string]$r['Computador'], [string]$r['Patrimonio'], [string]$r['Local'],
                (('{0} {1}' -f $r['Fabricante'], $r['Modelo']).Trim()), [string]$r['Serie'],
                [string]$r['Memoria'], [string]$r['Armazenamento'], [string]$r['Sistema'], [string]$r['AtualizadoEm']
            ) -Tag $r)
        }
        Clear-TIGridSelection $grid
    }
    if ($global:Inventario.CountLabel) {
        $n = $rows.Count
        $global:Inventario.CountLabel.Text = $(if ($n -eq 1) { '1 computador registrado' } else { '{0} computadores registrados' -f $n })
    }
    Update-InventarioSelection
    Update-InventarioThisPcStatus
}

function Invoke-InventarioCollect {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Coleta dos dados do equipamento' -Quiet -Script {
        Get-TIInventoryData
    } -OnComplete {
        param($r)
        $d = @($r | Where-Object { $_ -and $_.PSObject.Properties['Computador'] }) | Select-Object -First 1
        if (-not $d) { return }
        $global:Inventario.Data = $d
        foreach ($k in @($global:Inventario.Values.Keys)) {
            $row = $global:Inventario.Values[$k]
            switch ($k) {
                'Modelo' { Set-TIRowValue $row (('{0} {1}' -f $d.Fabricante, $d.Modelo).Trim()) }
                'Serie'  { if ($d.Serie) { Set-TIRowValue $row $d.Serie } else { Set-TIRowValue $row 'Não gravado pelo fabricante' 'warn' } }
                default  { Set-TIRowValue $row ([string]$d.$k) }
            }
        }
        Update-InventarioThisPcStatus
    })
}

function Invoke-InventarioRegister {
    $d = $global:Inventario.Data
    if (-not $d) { Show-TIToast -Text 'Espere a coleta dos dados terminar.' -Type 'Warn'; return }
    $pat = $global:Inventario.Fields['Patrimonio'].Text.Trim()
    $loc = $global:Inventario.Fields['Local'].Text.Trim()
    $obs = $global:Inventario.Fields['Observacao'].Text.Trim()
    if (-not $pat) {
        $ok = Show-TIConfirm -Title 'Registrar sem patrimônio?' -Icon 'Tag' -Style 'Primary' -Force `
                -Message 'O número de patrimônio está vazio. Sem ele, o computador fica identificado só pelo número de série e pelo nome.' `
                -ConfirmText 'Registrar assim mesmo'
        if (-not $ok) { [void]$global:Inventario.Fields['Patrimonio'].Focus(); return }
    }
    try {
        $rows = @(Read-TIInventory)
    } catch {
        Write-TILog -Level 'Error' -Message ('Não foi possível ler o inventário: {0}' -f $_.Exception.Message)
        Show-TIToast -Text 'Não foi possível ler a planilha do inventário.' -Type 'Error'
        return
    }
    $rec = New-TIInventoryRecord -Data $d -Patrimonio $pat -Local $loc -Observacao $obs -Tecnico $env:USERNAME
    $m = Merge-TIInventoryRow -Rows $rows -New $rec
    try {
        Save-TIInventory -Rows $m.Rows
    } catch {
        Write-TILog -Level 'Error' -Message ('Falha ao salvar o inventário: {0}' -f $_.Exception.Message)
        Show-TIToast -Text 'Não deu para salvar: feche o inventario.csv no Excel e tente de novo.' -Type 'Error'
        return
    }
    $what = if ($m.Updated) { 'Registro atualizado' } else { 'Computador registrado' }
    Write-TILog -Level 'Success' -Message ('Inventário: {0} ({1}{2}).' -f $what.ToLower(), $d.Computador, $(if ($pat) { ', patrimônio ' + $pat } else { '' }))
    Write-TIAudit -Action 'Inventário' -Result $(if ($m.Updated) { 'ATUALIZADO' } else { 'REGISTRADO' }) -Detail ('patrimônio {0}; série {1}' -f $pat, $d.Serie)
    Show-TIToast -Text ($what + ' no inventário.') -Type 'Success'
    Load-InventarioList
}

function Invoke-InventarioRemove {
    $grid = $global:Inventario.Grid
    if (-not $grid -or $grid.SelectedRows.Count -eq 0) { Show-TIToast -Text 'Selecione um computador na lista.' -Type 'Warn'; return }
    $sel = $grid.SelectedRows[0].Tag
    $ok = Show-TIConfirm -Title 'Remover do inventário' -Style 'Danger' -Icon 'Warning' -Force `
            -Message ("Remover '{0}' (patrimônio: {1}) da planilha?`n`nSó a linha do inventário é apagada; nada muda no computador." -f `
                      $sel['Computador'], $(if ([string]$sel['Patrimonio']) { $sel['Patrimonio'] } else { 'não informado' })) `
            -ConfirmText 'Remover'
    if (-not $ok) { return }
    try {
        $rows = @(Read-TIInventory)
        $keep = @($rows | Where-Object { -not (Test-TIInventorySame $_ $sel) })
        Save-TIInventory -Rows $keep
    } catch {
        Write-TILog -Level 'Error' -Message ('Falha ao atualizar o inventário: {0}' -f $_.Exception.Message)
        Show-TIToast -Text 'Não deu para salvar: feche o inventario.csv no Excel e tente de novo.' -Type 'Error'
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
            Copy-Item -LiteralPath $path -Destination $dlg.FileName -Force
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
    Sub      = 'Registro dos computadores numa planilha única no pendrive'
    Icon     = 'CheckList'
    Keywords = 'inventario patrimonio serie numero mac planilha csv excel equipamento cadastro'

    OnActivate = {
        if (-not $global:Inventario.Loaded) { $global:Inventario.Loaded = $true; Load-InventarioList }
        if (-not $global:Inventario.Data) { Invoke-InventarioCollect }
    }
    Refresh = { Load-InventarioList; Invoke-InventarioCollect }

    Actions = {
        param($Bar)
        $b1 = New-TIButton -Text 'Atualizar' -Style 'Outline' -Width 116 -Height 34 -Icon 'Refresh' -Tip 'Coletar de novo e reler a planilha (Ctrl+R)'
        $b1.Add_Click({ Load-InventarioList; Invoke-InventarioCollect })
        $Bar.Controls.Add($b1)
        $b2 = New-TIButton -Text 'Abrir pasta' -Style 'Ghost' -Width 124 -Height 34 -Icon 'FolderOpen'
        $b2.Add_Click({ Open-InventarioFolder })
        $Bar.Controls.Add($b2)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $cw = 466

        # --- Este computador ------------------------------------------------
        $b1 = New-TICard -Parent $flow -Title 'Este computador' -Desc 'Dados lidos do próprio equipamento' -Icon 'PC' -Width $cw -Height 392
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
        $b2 = New-TICard -Parent $flow -Title 'Identificação' -Desc 'Preenchida pelo técnico e salva junto com os dados' -Icon 'Tag' -Width $cw -Height 392
        $global:Inventario.Fields['Patrimonio'] = New-TIField -Parent $b2 -Label 'Número de patrimônio' -Placeholder 'Número da plaqueta' -MaxLength 40
        $global:Inventario.Fields['Local'] = New-TIField -Parent $b2 -Label 'Local' -Placeholder 'Ex.: Laboratório 2, Secretaria' -MaxLength 60
        $global:Inventario.Fields['Observacao'] = New-TIField -Parent $b2 -Label 'Observação' -Placeholder 'Opcional' -MaxLength 200
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
        $b3 = New-TICard -Parent $flow -Title 'Computadores registrados' -Desc 'Planilha única no pendrive: abre no Excel ou no LibreOffice' -Icon 'CheckList' -Width $cw -Height 400 -Stretch
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
        $null = New-TIHint -Parent $b3 -Text ('Arquivo: ' + (Get-TIInventoryPath)) -Size 8 -TopGap 0 -BottomGap 6

        $grid = New-TIGrid -Parent $b3 -Headers @('Computador', 'Patrimônio', 'Local', 'Modelo', 'Série', 'Memória', 'Armazenamento', 'Sistema', 'Atualizado em') `
                           -Widths @(130, 100, 130, 180, 120, 140, 150, 170, 120) `
                           -EmptyText 'Nenhum computador registrado ainda. Preencha a identificação e clique em Registrar.'
        $grid.Tag = 'tistretch'
        $grid.Height = 230
        $grid.Add_SelectionChanged({ Update-InventarioSelection })
        $global:Inventario.Grid = $grid
    }
}

Register-TIWorkspace @wsInventario
