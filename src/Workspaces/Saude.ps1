# =====================================================================
# ÁREA: SAÚDE DO PC - Windows, discos, proteção, relógio e bateria
# =====================================================================

$global:TIWorkerLib += @'

# ---------------------------------------------------------------------
# SAÚDE DO PC (roda no worker)
# Cada verificação devolve uma "seção": Id, Status (ok|warn|crit|none),
# Rows (Label, Value, Tone) e Issues (Status, Text).
# ---------------------------------------------------------------------
function New-TIHealthSection {
    param([string]$Id)
    return [pscustomobject]@{
        Id     = $Id
        Status = 'ok'
        Rows   = (New-Object System.Collections.ArrayList)
        Issues = (New-Object System.Collections.ArrayList)
    }
}

function Get-TIWorseStatus {
    param([string]$A, [string]$B)
    $rank = @{ none = 0; ok = 1; warn = 2; crit = 3 }
    $ra = 0; $rb = 0
    if ($rank.ContainsKey($A)) { $ra = $rank[$A] }
    if ($rank.ContainsKey($B)) { $rb = $rank[$B] }
    if ($rb -gt $ra) { return $B }
    return $A
}

function Add-TIHealthRow {
    param($Sec, [string]$Label, [string]$Value, [string]$Tone = '')
    [void]$Sec.Rows.Add([pscustomobject]@{ Label = $Label; Value = $Value; Tone = $Tone })
}

function Add-TIHealthIssue {
    param($Sec, [string]$Status, [string]$Text)
    [void]$Sec.Issues.Add([pscustomobject]@{ Status = $Status; Text = $Text; Area = $Sec.Id })
    $Sec.Status = Get-TIWorseStatus $Sec.Status $Status
}

# --- Regras (funções puras, testadas em dev\Test-Logic.ps1) -------------
function Get-TIBatteryHealthPct {
    param([double]$Design, [double]$Full)
    if ($Design -le 0 -or $Full -le 0) { return $null }
    return [int][Math]::Min(100, [Math]::Round(100 * $Full / $Design))
}

function Get-TIBatteryVerdict {
    param([int]$Pct)
    if ($Pct -lt 50) { return 'crit' }
    if ($Pct -lt 70) { return 'warn' }
    return 'ok'
}

function Get-TIUpdateVerdict {
    param([int]$Days)
    if ($Days -gt 120) { return 'crit' }
    if ($Days -gt 60) { return 'warn' }
    return 'ok'
}

function Get-TIClockVerdict {
    param([double]$Seconds)
    $a = [Math]::Abs($Seconds)
    if ($a -gt 300) { return 'crit' }
    if ($a -gt 120) { return 'warn' }
    return 'ok'
}

# productState do Central de Segurança: 2o byte = ligado (0x10/0x11), 3o byte = definições (0x00 em dia)
function Get-TIAvState {
    param([int64]$ProductState)
    $hex = '{0:X6}' -f $ProductState
    $mid = $hex.Substring($hex.Length - 4, 2)
    $low = $hex.Substring($hex.Length - 2, 2)
    return [pscustomobject]@{ Enabled = ($mid -eq '10' -or $mid -eq '11'); UpToDate = ($low -eq '00') }
}

function Get-TIActivationInfo {
    param([int]$LicenseStatus, [string]$Description = '', [int]$GraceMinutes = 0)
    $ch = ''
    if ($Description -match '(?i)VOLUME_KMS') { $ch = 'volume, KMS' }
    elseif ($Description -match '(?i)VOLUME_MAK') { $ch = 'volume, MAK' }
    elseif ($Description -match '(?i)OEM') { $ch = 'OEM' }
    elseif ($Description -match '(?i)RETAIL') { $ch = 'varejo' }
    $suffix = if ($ch) { ' (' + $ch + ')' } else { '' }
    switch ($LicenseStatus) {
        1 {
            if ($ch -eq 'volume, KMS' -and $GraceMinutes -gt 0) {
                $days = [int][Math]::Floor($GraceMinutes / 1440)
                if ($days -lt 30) {
                    return [pscustomobject]@{ Text = ('Ativado{0}, renova em {1} dias' -f $suffix, $days); Tone = 'warn'
                        Issue = ('A ativação KMS vence em {0} dias: o PC precisa alcançar o servidor KMS da rede.' -f $days) }
                }
                return [pscustomobject]@{ Text = ('Ativado{0}, renova em {1} dias' -f $suffix, $days); Tone = 'ok'; Issue = '' }
            }
            return [pscustomobject]@{ Text = ('Ativado' + $suffix); Tone = 'ok'; Issue = '' }
        }
        0 { return [pscustomobject]@{ Text = ('Não ativado' + $suffix); Tone = 'warn'; Issue = 'O Windows não está ativado.' } }
        2 { return [pscustomobject]@{ Text = ('Em período de carência' + $suffix); Tone = 'warn'; Issue = 'O Windows está em período de carência: ative antes que expire.' } }
        3 { return [pscustomobject]@{ Text = ('Carência por troca de hardware' + $suffix); Tone = 'warn'; Issue = 'O Windows pede reativação depois de troca de hardware.' } }
        4 { return [pscustomobject]@{ Text = ('Cópia não genuína' + $suffix); Tone = 'crit'; Issue = 'O Windows acusa cópia não genuína.' } }
        5 { return [pscustomobject]@{ Text = ('Não ativado, em notificação' + $suffix); Tone = 'warn'; Issue = 'O Windows não está ativado (modo de notificação).' } }
        6 { return [pscustomobject]@{ Text = ('Carência estendida' + $suffix); Tone = 'warn'; Issue = 'O Windows está em carência estendida: ative em breve.' } }
    }
    return [pscustomobject]@{ Text = 'Situação desconhecida'; Tone = 'dim'; Issue = '' }
}

# Datas do Win32_QuickFixEngineering vêm em formatos variados
function ConvertFrom-TIQfeDate {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $fmts = [string[]]@('M/d/yyyy', 'MM/dd/yyyy', 'yyyyMMdd', 'yyyy-MM-dd', 'M/d/yyyy h:mm:ss tt', 'M/d/yyyy HH:mm:ss')
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact($Raw.Trim(), $fmts, $inv, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    if ($Raw.Trim() -match '^[0-9A-Fa-f]{15,16}$') {
        try { return [datetime]::FromFileTime([Convert]::ToInt64($Raw.Trim(), 16)) } catch { }
    }
    return $null
}

# Cabeçalho HTTP "Date" (RFC 1123) -> DateTime em UTC
function ConvertFrom-TIHttpDate {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $sty = [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal'
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact($Text.Trim(), 'r', $inv, $sty, [ref]$d)) { return $d }
    if ([datetime]::TryParse($Text.Trim(), $inv, $sty, [ref]$d)) { return $d }
    return $null
}

# Diferença do relógio (positivo = PC adiantado)
function Format-TIOffset {
    param([double]$Seconds)
    $abs = [Math]::Abs($Seconds)
    if ($abs -lt 2) { return 'em dia (menos de 2 s)' }
    $dir = if ($Seconds -gt 0) { 'adiantado' } else { 'atrasado' }
    if ($abs -lt 60) { return ('{0} s {1}' -f [int][Math]::Round($abs), $dir) }
    if ($abs -lt 3600) {
        $m = [int][Math]::Floor($abs / 60)
        $s = [int][Math]::Round($abs - ($m * 60))
        if ($s -ge 60) { $m++; $s = 0 }
        return ('{0} min {1} s {2}' -f $m, $s, $dir)
    }
    if ($abs -lt 172800) {
        $h = [int][Math]::Floor($abs / 3600)
        $m = [int][Math]::Round(($abs - ($h * 3600)) / 60)
        if ($m -ge 60) { $h++; $m = 0 }
        return ('{0} h {1} min {2}' -f $h, $m, $dir)
    }
    return ('{0} dias {1}' -f [int][Math]::Round($abs / 86400), $dir)
}

# Mediana das fontes + quantas concordam (até 10 s da mediana)
function Get-TIOffsetConsensus {
    param([double[]]$Offsets)
    $vals = @($Offsets | Sort-Object)
    if ($vals.Count -eq 0) { return [pscustomobject]@{ OffsetSeconds = $null; Sources = 0; Agree = 0 } }
    $mid = [int][Math]::Floor($vals.Count / 2)
    $med = if ($vals.Count % 2 -eq 1) { [double]$vals[$mid] } else { ([double]$vals[$mid - 1] + [double]$vals[$mid]) / 2 }
    $agree = @($vals | Where-Object { [Math]::Abs($_ - $med) -le 10 }).Count
    return [pscustomobject]@{ OffsetSeconds = [Math]::Round($med, 1); Sources = $vals.Count; Agree = $agree }
}

function Format-TIDaysText {
    param([int]$Days)
    if ($Days -le 0) { return 'hoje' }
    if ($Days -eq 1) { return 'ontem' }
    return ('há {0} dias' -f $Days)
}

function ConvertTo-TIFirewallProfileName {
    param([string]$Name)
    switch ($Name) {
        'Domain'  { return 'Domínio' }
        'Private' { return 'Privado' }
        'Public'  { return 'Público' }
    }
    return $Name
}

# --- Coletas -------------------------------------------------------------
function Get-TILastUpdateInfo {
    try {
        $session = New-Object -ComObject 'Microsoft.Update.Session'
        $searcher = $session.CreateUpdateSearcher()
        $count = [int]$searcher.GetTotalHistoryCount()
        if ($count -gt 0) {
            $best = $null
            foreach ($e in $searcher.QueryHistory(0, [Math]::Min($count, 300))) {
                if ([int]$e.Operation -ne 1 -or [int]$e.ResultCode -ne 2) { continue }
                $title = [string]$e.Title
                # definições do antivírus saem todo dia e mascarariam o Windows Update parado
                if ($title -match 'KB2267602|KB4052623|KB915597|Defender|Intelig.ncia de Seguran|Security Intelligence|Antimalware') { continue }
                $d = ([datetime]$e.Date).ToLocalTime()
                if (-not $best -or $d -gt $best.Date) { $best = [pscustomobject]@{ Date = $d; Title = $title } }
            }
            if ($best) { return $best }
        }
    } catch { }
    try {
        $bestD = $null
        foreach ($q in @(Get-CimInstance Win32_QuickFixEngineering -ErrorAction Stop)) {
            $d = ConvertFrom-TIQfeDate ([string]$q.InstalledOn)
            if ($d -and (-not $bestD -or $d -gt $bestD)) { $bestD = $d }
        }
        if ($bestD) { return [pscustomobject]@{ Date = $bestD; Title = '' } }
    } catch { }
    return $null
}

function Get-TIHealthWindows {
    $sec = New-TIHealthSection 'windows'
    Emit 'Verificando o Windows: versão, ativação e atualizações...' 'Info' 10
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cv = $null
    try { $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop } catch { }
    $build = 0
    if ($os) { [void][int]::TryParse([string]$os.BuildNumber, [ref]$build) }
    $name = 'Windows'
    if ($os -and $os.Caption) { $name = ([string]$os.Caption) -replace '^Microsoft\s+', '' }
    $disp = ''
    if ($cv) { $disp = [string]$cv.DisplayVersion; if (-not $disp) { $disp = [string]$cv.ReleaseId } }
    $ubr = ''
    if ($cv -and $null -ne $cv.UBR) { $ubr = '.' + [string]$cv.UBR }
    Add-TIHealthRow $sec 'Sistema' ((('{0} {1}' -f $name, $disp).Trim()) + (' (build {0}{1})' -f $build, $ubr))
    if ($build -gt 0 -and $build -lt 22000 -and $name -notmatch 'LTS[BC]') {
        Add-TIHealthIssue $sec 'warn' 'O Windows 10 está sem suporte da Microsoft desde 14/10/2025: planeje a migração para o Windows 11.'
    }

    Emit 'Consultando a ativação (pode levar alguns segundos)...' 'Debug' 15
    try {
        $lic = @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction Stop)
        $best = $null
        foreach ($l in $lic) {
            if (-not $best -or ([int]$l.LicenseStatus -eq 1 -and [int]$best.LicenseStatus -ne 1)) { $best = $l }
        }
        if ($best) {
            $act = Get-TIActivationInfo -LicenseStatus ([int]$best.LicenseStatus) -Description ([string]$best.Description) -GraceMinutes ([int]$best.GracePeriodRemaining)
            Add-TIHealthRow $sec 'Ativação' $act.Text $act.Tone
            if ($act.Issue) { Add-TIHealthIssue $sec $act.Tone $act.Issue }
        } else {
            Add-TIHealthRow $sec 'Ativação' 'Sem chave de produto' 'warn'
            Add-TIHealthIssue $sec 'warn' 'O Windows está sem chave de produto: não está ativado.'
        }
    } catch {
        Add-TIHealthRow $sec 'Ativação' 'Não foi possível consultar' 'dim'
    }

    Emit 'Lendo o histórico do Windows Update...' 'Debug' 20
    $last = Get-TILastUpdateInfo
    if ($last) {
        $days = [int][Math]::Floor(((Get-Date) - $last.Date).TotalDays)
        $tone = Get-TIUpdateVerdict $days
        Add-TIHealthRow $sec 'Última atualização' ('{0} ({1})' -f $last.Date.ToString('dd/MM/yyyy'), (Format-TIDaysText $days)) $tone
        if ($tone -ne 'ok') { Add-TIHealthIssue $sec $tone ('Nenhuma atualização do Windows há {0} dias: rode o Windows Update.' -f $days) }
    } else {
        Add-TIHealthRow $sec 'Última atualização' 'Histórico indisponível' 'dim'
    }

    $pend = @()
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pend += 'componentes' }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pend += 'Windows Update' }
    if ($pend.Count -gt 0) {
        Add-TIHealthRow $sec 'Reinício pendente' ('Sim (' + ($pend -join ', ') + ')') 'warn'
        Add-TIHealthIssue $sec 'warn' 'Há atualização esperando reinício: reinicie o computador quando a sala estiver livre.'
    } else {
        Add-TIHealthRow $sec 'Reinício pendente' 'Não' 'ok'
    }

    # Só informativo: com a Inicialização rápida, "desligar" não zera este contador
    if ($os -and $os.LastBootUpTime) {
        $up = (Get-Date) - $os.LastBootUpTime
        $d = [int][Math]::Floor($up.TotalDays)
        $txt = if ($d -gt 0) { '{0}d {1}h' -f $d, $up.Hours } else { '{0}h {1}min' -f $up.Hours, $up.Minutes }
        Add-TIHealthRow $sec 'Ligado há' $txt
    }
    return $sec
}

function Get-TIHealthDisk {
    $sec = New-TIHealthSection 'disk'
    Emit 'Verificando os discos...' 'Info' 30
    $n = 0
    $pd = @()
    try { $pd = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { Test-TIInternalDisk $_ } | Sort-Object DeviceId) } catch { }
    foreach ($d in $pd) {
        $n++
        $hw = ConvertTo-TIHealthWord $d.HealthStatus
        $media = ConvertTo-TIMediaWord $d.MediaType $d.BusType
        $label = ('{0} {1}' -f $media, (Format-TIDiskSize ([double]$d.Size)))
        $parts = New-Object System.Collections.ArrayList
        [void]$parts.Add($hw.Word)
        $tone = $hw.Tone
        $rel = $null
        try { $rel = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction Stop } catch { }
        if ($rel) {
            $t = 0; try { $t = [int]$rel.Temperature } catch { }
            if ($t -gt 0) {
                [void]$parts.Add(('{0} °C' -f $t))
                if ($t -ge 60 -and $tone -eq 'ok') { $tone = 'warn' }
            }
            $w = 0; try { $w = [int]$rel.Wear } catch { }
            if ($w -gt 0) {
                [void]$parts.Add(('{0}% de desgaste' -f $w))
                if ($w -ge 95) { $tone = 'crit' } elseif ($w -ge 80 -and $tone -eq 'ok') { $tone = 'warn' }
            }
        }
        $txt = ($parts -join ', ')
        Add-TIHealthRow $sec $label $txt $tone
        if ($tone -eq 'crit') { Add-TIHealthIssue $sec 'crit' ('{0} ({1}) com falha: faça backup e troque o disco.' -f $label, ([string]$d.FriendlyName).Trim()) }
        elseif ($tone -eq 'warn') { Add-TIHealthIssue $sec 'warn' ('{0} pede atenção: {1}.' -f $label, $txt) }
    }
    if ($n -eq 0) {
        foreach ($dd in @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceType -ne 'USB' })) {
            $n++
            $st = [string]$dd.Status
            $tone = if ($st -eq 'OK') { 'ok' } elseif ($st -match 'Pred Fail') { 'crit' } else { 'warn' }
            $label = ('Disco {0}' -f (Format-TIDiskSize ([double]$dd.Size)))
            Add-TIHealthRow $sec $label $(if ($tone -eq 'ok') { 'Saudável' } elseif ($tone -eq 'crit') { 'Falha prevista' } else { $st }) $tone
            if ($tone -ne 'ok') { Add-TIHealthIssue $sec $tone ('{0}: o Windows informa "{1}". Faça backup.' -f $label, $st) }
        }
    }
    try {
        $smart = @(Get-CimInstance -Namespace 'root/wmi' -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop | Where-Object { $_.PredictFailure })
        if ($smart.Count -gt 0) {
            Add-TIHealthRow $sec 'SMART' 'Falha prevista' 'crit'
            Add-TIHealthIssue $sec 'crit' 'O SMART de um disco prevê falha: faça backup e programe a troca.'
        }
    } catch { }

    $sys = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
    try {
        $ld = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $sys) -ErrorAction Stop
        if ($ld -and [double]$ld.Size -gt 0) {
            $pct = [int](100 * [double]$ld.FreeSpace / [double]$ld.Size)
            $tone = if ($pct -lt 5) { 'crit' } elseif ($pct -lt 10) { 'warn' } else { 'ok' }
            Add-TIHealthRow $sec ('Livre em ' + $sys) ('{0} de {1} ({2}%)' -f (Format-TIByte ([double]$ld.FreeSpace)), (Format-TIByte ([double]$ld.Size)), $pct) $tone
            if ($tone -ne 'ok') { Add-TIHealthIssue $sec $tone ('Pouco espaço livre em {0} ({1}%): rode a Limpeza profunda em Manutenção.' -f $sys, $pct) }
        }
    } catch { }
    if ($n -eq 0) { Add-TIHealthRow $sec 'Discos' 'O Windows não informou a saúde dos discos' 'dim' }
    return $sec
}

function Get-TIHealthSecurity {
    $sec = New-TIHealthSection 'security'
    Emit 'Verificando antivírus e firewall...' 'Info' 50
    $avs = @()
    try { $avs = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop) } catch { }
    $anyOn = $false
    foreach ($a in $avs) {
        $st = Get-TIAvState ([int64]$a.productState)
        $nm = [string]$a.displayName
        if ($st.Enabled) { $anyOn = $true }
        $txt = if (-not $st.Enabled) { 'desligado' } elseif ($st.UpToDate) { 'ativo e atualizado' } else { 'ativo, mas desatualizado' }
        $tone = if (-not $st.Enabled) { 'dim' } elseif ($st.UpToDate) { 'ok' } else { 'warn' }
        Add-TIHealthRow $sec 'Antivírus' ('{0}: {1}' -f $nm, $txt) $tone
        if ($st.Enabled -and -not $st.UpToDate) { Add-TIHealthIssue $sec 'warn' ('{0} está com as definições desatualizadas.' -f $nm) }
    }
    $mp = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { }
    if ($mp) {
        $mode = [string]$mp.AMRunningMode
        $defOn = ([bool]$mp.AntivirusEnabled -and $mode -notmatch 'Passive')
        if ($avs.Count -eq 0) {
            if ($defOn -and [bool]$mp.RealTimeProtectionEnabled) { $anyOn = $true }
            Add-TIHealthRow $sec 'Antivírus' $(if ($defOn) { 'Microsoft Defender: ativo' } else { 'Microsoft Defender: desligado' }) $(if ($defOn) { 'ok' } else { 'crit' })
        }
        if ($defOn) {
            $age = [int]$mp.AntivirusSignatureAge
            if ($age -ge 65000) {
                Add-TIHealthRow $sec 'Definições' 'Nunca atualizadas' 'crit'
                Add-TIHealthIssue $sec 'crit' 'As definições do Microsoft Defender nunca foram atualizadas.'
            } else {
                $tone = if ($age -gt 7) { 'warn' } else { 'ok' }
                Add-TIHealthRow $sec 'Definições' ('Atualizadas ' + (Format-TIDaysText $age)) $tone
                if ($age -gt 7) { Add-TIHealthIssue $sec 'warn' ('Definições do Microsoft Defender com {0} dias: rode o Windows Update.' -f $age) }
            }
            $rt = [bool]$mp.RealTimeProtectionEnabled
            Add-TIHealthRow $sec 'Tempo real' $(if ($rt) { 'Ligada' } else { 'Desligada' }) $(if ($rt) { 'ok' } else { 'crit' })
            if (-not $rt) { Add-TIHealthIssue $sec 'crit' 'A proteção em tempo real do Microsoft Defender está desligada.' }
        }
    }
    if (-not $anyOn) {
        if ($avs.Count -eq 0 -and -not $mp) { Add-TIHealthRow $sec 'Antivírus' 'Nenhum encontrado' 'crit' }
        Add-TIHealthIssue $sec 'crit' 'Nenhum antivírus ativo neste computador.'
    }
    try {
        $fw = @(Get-NetFirewallProfile -ErrorAction Stop)
        $off = @($fw | Where-Object { [string]$_.Enabled -eq 'False' } | ForEach-Object { ConvertTo-TIFirewallProfileName ([string]$_.Name) })
        if ($off.Count -eq 0) {
            Add-TIHealthRow $sec 'Firewall' ('Ligado nos {0} perfis' -f $fw.Count) 'ok'
        } else {
            Add-TIHealthRow $sec 'Firewall' ('Desligado: ' + ($off -join ', ')) 'warn'
            Add-TIHealthIssue $sec 'warn' ('Firewall do Windows desligado no perfil ' + ($off -join ', ') + '.')
        }
    } catch {
        Add-TIHealthRow $sec 'Firewall' 'Não foi possível consultar' 'dim'
    }
    return $sec
}

# Hora da internet por HTTP simples (sem TLS: funciona mesmo com o relógio muito errado)
function Get-TIInternetTime {
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $sources = @(
        @{ Url = 'http://www.msftconnecttest.com/connecttest.txt'; Kind = 'date' },
        @{ Url = 'http://www.google.com/generate_204';              Kind = 'date' },
        @{ Url = 'http://1.1.1.1/cdn-cgi/trace';                    Kind = 'trace' }
    )
    $offs = New-Object System.Collections.ArrayList
    foreach ($s in $sources) {
        $resp = $null
        try {
            $req = [System.Net.HttpWebRequest]::Create($s.Url + '?nocache=' + [DateTime]::UtcNow.Ticks)
            $req.Timeout = 5000
            $req.ReadWriteTimeout = 5000
            $req.AllowAutoRedirect = $false
            $req.Headers.Add('Cache-Control', 'no-cache')
            $req.Headers.Add('Pragma', 'no-cache')
            if ($req.Proxy) { $req.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials }
            $t0 = [DateTime]::UtcNow
            try { $resp = $req.GetResponse() } catch [System.Net.WebException] { $resp = $_.Exception.Response }
            $t1 = [DateTime]::UtcNow
            if (-not $resp) { continue }
            $server = $null
            if ($s.Kind -eq 'trace') {
                $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $body = $sr.ReadToEnd()
                $sr.Close()
                if ($body -match '(?m)^ts=(\d+(?:\.\d+)?)') {
                    $server = (New-Object DateTime(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).AddSeconds([double]::Parse($Matches[1], $inv))
                }
            } else {
                $server = ConvertFrom-TIHttpDate ([string]$resp.Headers['Date'])
                if ($server) {
                    $server = $server.AddMilliseconds(500)   # o cabeçalho corta os milissegundos
                    $age = [string]$resp.Headers['Age']
                    if ($age -match '^\d+$') { $server = $server.AddSeconds([int]$age) }
                }
            }
            if ($server) {
                $midT = $t0.AddTicks([long](($t1 - $t0).Ticks / 2))
                [void]$offs.Add([double]($midT - $server).TotalSeconds)
            }
        } catch {
        } finally {
            if ($resp) { try { $resp.Close() } catch { } }
        }
    }
    return (Get-TIOffsetConsensus -Offsets ([double[]]$offs.ToArray()))
}

function Get-TIHealthClock {
    $sec = New-TIHealthSection 'clock'
    Emit 'Comparando o relógio com a internet...' 'Info' 70
    Add-TIHealthRow $sec 'Hora do PC' ((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))
    try { Add-TIHealthRow $sec 'Fuso horário' ([string](Get-TimeZone).DisplayName) } catch { }
    try {
        $svc = Get-Service -Name 'w32time' -ErrorAction Stop
        if ($svc.Status -eq 'Running') { Add-TIHealthRow $sec 'Serviço de horário' 'Em execução' 'ok' }
        elseif ([string]$svc.StartType -eq 'Disabled') { Add-TIHealthRow $sec 'Serviço de horário' 'Desativado' 'warn' }
        else { Add-TIHealthRow $sec 'Serviço de horário' 'Parado (liga quando precisa)' 'dim' }
    } catch { Add-TIHealthRow $sec 'Serviço de horário' 'Não encontrado' 'warn' }
    $net = Get-TIInternetTime
    if ($null -eq $net.OffsetSeconds) {
        Add-TIHealthRow $sec 'Diferença' 'Sem internet para comparar' 'dim'
        $sec.Status = 'none'
    } else {
        $tone = Get-TIClockVerdict $net.OffsetSeconds
        Add-TIHealthRow $sec 'Diferença' (Format-TIOffset $net.OffsetSeconds) $tone
        if ($tone -eq 'crit') { Add-TIHealthIssue $sec 'crit' ('Relógio {0}: sites seguros e o login na rede podem falhar. Use "Acertar relógio".' -f (Format-TIOffset $net.OffsetSeconds)) }
        elseif ($tone -eq 'warn') { Add-TIHealthIssue $sec 'warn' ('Relógio {0}: vale acertar.' -f (Format-TIOffset $net.OffsetSeconds)) }
    }
    Add-Member -InputObject $sec -NotePropertyName 'Offset' -NotePropertyValue $net.OffsetSeconds -Force
    Add-Member -InputObject $sec -NotePropertyName 'Agree' -NotePropertyValue $net.Agree -Force
    return $sec
}

# Acertar relógio: primeiro o Windows (w32tm); se continuar errado e 2 fontes da
# internet concordarem, ajusta pela diferença medida. O fuso não é alterado.
function Sync-TIClock {
    Emit 'Pedindo ao Windows para sincronizar o relógio...' 'Info' 10
    $svcOk = $true
    try {
        $svc = Get-Service -Name 'w32time' -ErrorAction Stop
        if ([string]$svc.StartType -eq 'Disabled') {
            $svcOk = $false
            Emit 'O serviço de horário do Windows está desativado: vou usar o horário da internet.' 'Warn'
        } elseif ($svc.Status -ne 'Running') {
            Start-Service -Name 'w32time' -ErrorAction Stop
            Start-Sleep -Seconds 2
        }
    } catch {
        $svcOk = $false
        Emit ('Serviço de horário indisponível: {0}' -f $_.Exception.Message) 'Warn'
    }
    if ($svcOk) {
        $out = (& w32tm.exe /resync /force 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0) { Emit 'O Windows sincronizou com o servidor de horário.' 'Success' }
        else { Emit ('O w32tm não sincronizou: {0}' -f ((($out -split "`r?`n") | Where-Object { $_.Trim() }) | Select-Object -Last 1)) 'Warn' }
        Start-Sleep -Seconds 2
    }
    Emit 'Conferindo com o horário da internet...' 'Info' 60
    $net = Get-TIInternetTime
    if ($null -eq $net.OffsetSeconds) {
        Emit 'Sem internet para conferir o horário.' 'Warn'
    } elseif ([Math]::Abs($net.OffsetSeconds) -le 120) {
        Emit ('Relógio certo ({0}).' -f (Format-TIOffset $net.OffsetSeconds)) 'Success'
    } elseif ($net.Agree -lt 2) {
        Emit 'As fontes de horário da internet não concordaram entre si: nada foi alterado.' 'Warn'
    } else {
        try {
            Set-Date -Adjust ([TimeSpan]::FromSeconds(-1 * $net.OffsetSeconds)) -ErrorAction Stop | Out-Null
            Emit ('Relógio ajustado pelo horário da internet (estava {0}).' -f (Format-TIOffset $net.OffsetSeconds)) 'Success'
        } catch {
            Emit ('Não foi possível ajustar o relógio: {0}' -f $_.Exception.Message) 'Error'
        }
    }
    return (Get-TIHealthClock)
}

function Get-TIHealthBattery {
    $sec = New-TIHealthSection 'battery'
    Emit 'Verificando a bateria...' 'Info' 85
    $bat = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if ($bat.Count -eq 0) {
        $sec.Status = 'none'
        Add-TIHealthRow $sec 'Bateria' 'Não há bateria (computador de mesa)' 'dim'
        return $sec
    }
    $b = $bat[0]
    $charge = [int]$b.EstimatedChargeRemaining
    $stTxt = switch ([int]$b.BatteryStatus) {
        1 { 'na bateria' }
        2 { 'na tomada' }
        3 { 'carga completa' }
        4 { 'carga baixa' }
        5 { 'carga crítica' }
        6 { 'carregando' }
        7 { 'carregando' }
        8 { 'carregando' }
        9 { 'carregando' }
        11 { 'carga parcial' }
        default { '' }
    }
    Add-TIHealthRow $sec 'Carga' $(if ($stTxt) { '{0}% ({1})' -f $charge, $stTxt } else { '{0}%' -f $charge })
    $design = 0.0; $full = 0.0; $cycles = 0
    try { foreach ($x in @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryStaticData -ErrorAction Stop)) { $design += [double]$x.DesignedCapacity } } catch { }
    try { foreach ($x in @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryFullChargedCapacity -ErrorAction Stop)) { $full += [double]$x.FullChargedCapacity } } catch { }
    try { foreach ($x in @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryCycleCount -ErrorAction Stop)) { $cycles = [Math]::Max($cycles, [int]$x.CycleCount) } } catch { }
    $health = Get-TIBatteryHealthPct -Design $design -Full $full
    if ($null -ne $health) {
        $v = Get-TIBatteryVerdict $health
        Add-TIHealthRow $sec 'Capacidade' ('{0}% da original' -f $health) $v
        if ($v -eq 'crit') { Add-TIHealthIssue $sec 'crit' ('Bateria com {0}% da capacidade original: troca recomendada.' -f $health) }
        elseif ($v -eq 'warn') { Add-TIHealthIssue $sec 'warn' ('Bateria gasta ({0}% da capacidade original): a autonomia já caiu.' -f $health) }
    } else {
        Add-TIHealthRow $sec 'Capacidade' 'Não informada pelo fabricante' 'dim'
    }
    if ($cycles -gt 0) { Add-TIHealthRow $sec 'Ciclos de carga' ([string]$cycles) }
    return $sec
}

function Invoke-TIHealthStep {
    param([string]$Id, [scriptblock]$Body)
    try {
        return (& $Body)
    } catch {
        Emit ('Falha ao verificar {0}: {1}' -f $Id, $_.Exception.Message) 'Warn'
        $s = New-TIHealthSection $Id
        $s.Status = 'none'
        Add-TIHealthRow $s 'Erro' $_.Exception.Message 'dim'
        return $s
    }
}

function Get-TIHealthReport {
    $sections = [ordered]@{}
    $sections['windows']  = Invoke-TIHealthStep 'windows'  { Get-TIHealthWindows }
    $sections['disk']     = Invoke-TIHealthStep 'disk'     { Get-TIHealthDisk }
    $sections['security'] = Invoke-TIHealthStep 'security' { Get-TIHealthSecurity }
    $sections['clock']    = Invoke-TIHealthStep 'clock'    { Get-TIHealthClock }
    $sections['battery']  = Invoke-TIHealthStep 'battery'  { Get-TIHealthBattery }
    $n = 0
    foreach ($s in $sections.Values) { $n += @($s.Issues).Count }
    Emit ('Verificação concluída: {0} ponto(s) para revisar.' -f $n) $(if ($n -gt 0) { 'Warn' } else { 'Success' }) 100
    return [pscustomobject]@{ Sections = $sections; CheckedAt = (Get-Date); Computer = $env:COMPUTERNAME }
}
'@

# ---------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------
$global:Saude = @{
    Report      = $null
    Cards       = @{}
    Order       = @('windows', 'disk', 'security', 'clock', 'battery')
    Meta        = @{
        windows  = @{ Title = 'Windows';     Desc = 'Versão, ativação, atualizações e reinício pendente'; Icon = 'Update' }
        disk     = @{ Title = 'Discos';      Desc = 'Saúde, temperatura, desgaste e espaço livre';          Icon = 'Diagnostic' }
        security = @{ Title = 'Proteção';    Desc = 'Antivírus, definições e firewall';                     Icon = 'Shield' }
        clock    = @{ Title = 'Data e hora'; Desc = 'Relógio do PC comparado com a internet';               Icon = 'Recent' }
        battery  = @{ Title = 'Bateria';     Desc = 'Carga e capacidade em relação à original';             Icon = 'Battery' }
    }
    SummaryBody = $null
    Verdict     = $null
    VerdictSub  = $null
}

function Get-TIStatusWord {
    param([string]$Status)
    switch ($Status) {
        'ok'   { return 'Em ordem' }
        'warn' { return 'Atenção' }
        'crit' { return 'Crítico' }
    }
    return 'Sem dados'
}

# Linha do resumo: ícone colorido + texto que quebra linha e ajusta a altura
function Add-SaudeIssueLine {
    param($Body, [string]$Status, [string]$Text)
    $row = New-Object System.Windows.Forms.Panel
    $row.Tag = 'tirow'
    $row.Name = 'tiissue'
    $row.BackColor = [System.Drawing.Color]::Transparent
    $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $row.Width = Get-TIInnerWidth $Body
    $row.Height = 22
    $icon = New-TIGlyph -Icon $(if ($Status -eq 'crit') { 'Error' } elseif ($Status -eq 'warn') { 'Warning' } else { 'Completed' }) -Size 10.5 -Color (Get-TIToneColor $Status)
    $icon.Location = New-Object System.Drawing.Point(0, 2)
    $row.Controls.Add($icon)
    $lbl = New-TILabel -Text $Text -Size 9
    $lbl.AutoSize = $false
    $lbl.Location = New-Object System.Drawing.Point(24, 0)
    $row.Controls.Add($lbl)
    $fit = {
        $lw = [Math]::Max(60, $row.Width - 24)
        $sz = [System.Windows.Forms.TextRenderer]::MeasureText($lbl.Text, $lbl.Font, (New-Object System.Drawing.Size($lw, 2000)), [System.Windows.Forms.TextFormatFlags]'WordBreak')
        $lbl.Size = New-Object System.Drawing.Size($lw, ($sz.Height + 2))
        $h = [Math]::Max(20, $sz.Height + 4)
        if ($row.Height -ne $h) { $row.Height = $h }
    }.GetNewClosure()
    & $fit
    $row.Add_Resize($fit)
    $Body.Controls.Add($row)
}

function Fill-SaudeCard {
    param([string]$Id, $Section)
    $b = $global:Saude.Cards[$Id]
    if (-not $b -or $b.IsDisposed -or -not $Section) { return }
    $b.SuspendLayout()
    foreach ($c in @($b.Controls)) { $b.Controls.Remove($c); $c.Dispose() }
    $iw = Get-TIInnerWidth $b
    foreach ($r in @($Section.Rows)) {
        $row = New-TIRow -Label $r.Label -Width $iw -LabelWidth 124
        Set-TIRowValue $row $r.Value $r.Tone
        $b.Controls.Add($row.Panel)
    }
    if ($Id -eq 'clock') {
        $bar = New-TIButtonBar -Parent $b
        $bar.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
        $btn = New-TIButton -Text 'Acertar relógio' -Style 'Outline' -Icon 'Sync' -Width 164 -Height 36 -Tip 'Sincroniza o horário do Windows (precisa de administrador)'
        $btn.Add_Click({ Invoke-SaudeClockSync })
        $bar.Controls.Add($btn)
    }
    $b.ResumeLayout()
    if ($Id -eq 'battery' -and $Section.Status -eq 'none') { Set-TICardStatus $b 'none' 'Não se aplica' }
    else { Set-TICardStatus $b $Section.Status }
}

function Update-SaudeUI {
    param($Report)
    if (-not $Report) { return }
    $global:Saude.Report = $Report
    $all = New-Object System.Collections.ArrayList
    foreach ($id in $global:Saude.Order) {
        $sec = $Report.Sections[$id]
        if (-not $sec) { continue }
        Fill-SaudeCard -Id $id -Section $sec
        foreach ($i in @($sec.Issues)) { [void]$all.Add($i) }
    }
    $crit = @($all | Where-Object { $_.Status -eq 'crit' })
    $warn = @($all | Where-Object { $_.Status -eq 'warn' })

    $v = $global:Saude.Verdict
    if ($crit.Count -gt 0) {
        $txt = if ($crit.Count -eq 1) { '1 problema crítico' } else { '{0} problemas críticos' -f $crit.Count }
        if ($warn.Count -gt 0) { $txt += $(if ($warn.Count -eq 1) { ' e 1 ponto de atenção' } else { ' e {0} pontos de atenção' -f $warn.Count }) }
        $v.Text = $txt
        $v.ForeColor = $global:Pal.Danger
    } elseif ($warn.Count -gt 0) {
        $v.Text = $(if ($warn.Count -eq 1) { '1 ponto de atenção' } else { '{0} pontos de atenção' -f $warn.Count })
        $v.ForeColor = $global:Pal.Warning
    } else {
        $v.Text = 'Tudo em ordem'
        $v.ForeColor = $global:Pal.Success
    }
    $when = [datetime]$Report.CheckedAt
    $global:Saude.VerdictSub.Text = ('Verificado em {0} às {1}.' -f $when.ToString('dd/MM/yyyy'), $when.ToString('HH:mm'))

    $b0 = $global:Saude.SummaryBody
    $b0.SuspendLayout()
    foreach ($c in @($b0.Controls | Where-Object { $_.Name -eq 'tiissue' })) { $b0.Controls.Remove($c); $c.Dispose() }
    $list = @($crit) + @($warn)
    if ($list.Count -eq 0) {
        Add-SaudeIssueLine -Body $b0 -Status 'ok' -Text 'Nenhum problema encontrado nas verificações.'
    } else {
        foreach ($i in $list) { Add-SaudeIssueLine -Body $b0 -Status $i.Status -Text $i.Text }
    }
    $b0.ResumeLayout()
    $card = $b0.Parent
    if ($card) {
        $n = [Math]::Max(1, $list.Count)
        $card.Height = [Math]::Max(214, 64 + 4 + 104 + ($n * 30) + 14)
    }
    $lvl = if ($crit.Count -gt 0 -or $warn.Count -gt 0) { 'Warn' } else { 'Success' }
    Write-TILog -Level $lvl -Message ('Saúde do PC: {0}.' -f $v.Text.ToLower())
}

function Invoke-SaudeCheck {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Verificação de saúde do PC' -Quiet -Script {
        Get-TIHealthReport
    } -OnComplete {
        param($r)
        $rep = @($r | Where-Object { $_ -and $_.PSObject.Properties['Sections'] }) | Select-Object -First 1
        if ($rep) { Update-SaudeUI -Report $rep }
    })
}

function Invoke-SaudeClockSync {
    if ($global:TI.Busy) { return }
    $ok = Show-TIConfirm -Title 'Acertar relógio' -Icon 'Recent' -Style 'Primary' -Force `
            -Message ("O TI Suite pede ao Windows para sincronizar o horário. Se o relógio continuar errado " +
                      "e duas fontes da internet concordarem entre si, ajusta pela diferença medida.`n`nO fuso horário não é alterado.") `
            -ConfirmText 'Acertar agora'
    if (-not $ok) { return }
    [void](Invoke-TIAsync -Name 'Acerto do relógio' -RequiresAdmin -Script {
        Sync-TIClock
    } -OnComplete {
        param($r)
        $sec = @($r | Where-Object { $_ -and $_.PSObject.Properties['Rows'] }) | Select-Object -First 1
        if (-not $sec) { return }
        if ($global:Saude.Report) {
            $global:Saude.Report.Sections['clock'] = $sec
            Update-SaudeUI -Report $global:Saude.Report
        } else {
            Fill-SaudeCard -Id 'clock' -Section $sec
        }
    })
}

function Export-SaudeLaudo {
    $rep = $global:Saude.Report
    if (-not $rep) { Show-TIToast -Text 'Rode a verificação antes de salvar o laudo.' -Type 'Warn'; return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = 'Salvar laudo de saúde'
    $dlg.Filter = 'Texto (*.txt)|*.txt|Todos os arquivos (*.*)|*.*'
    $dlg.FileName = ('Laudo-saude-{0}-{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm'))
    if ($dlg.ShowDialog() -ne 'OK') { $dlg.Dispose(); return }

    $sb = New-Object System.Text.StringBuilder
    $line = '====================================================================='
    $when = [datetime]$rep.CheckedAt
    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine(' TI Suite - laudo de saúde do computador')
    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine((' Computador : {0}' -f $rep.Computer))
    [void]$sb.AppendLine((' Verificado : {0}' -f $when.ToString('dd/MM/yyyy HH:mm')))
    [void]$sb.AppendLine((' Técnico    : {0}' -f $env:USERNAME))
    [void]$sb.AppendLine((' Resultado  : {0}' -f $global:Saude.Verdict.Text))
    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(' Pontos encontrados')
    $issues = New-Object System.Collections.ArrayList
    foreach ($id in $global:Saude.Order) {
        $sec = $rep.Sections[$id]
        if ($sec) { foreach ($i in @($sec.Issues)) { [void]$issues.Add($i) } }
    }
    $sorted = @($issues | Where-Object { $_.Status -eq 'crit' }) + @($issues | Where-Object { $_.Status -eq 'warn' })
    if ($sorted.Count -eq 0) { [void]$sb.AppendLine('   Nenhum problema encontrado.') }
    foreach ($i in $sorted) {
        [void]$sb.AppendLine(('   [{0}] {1}' -f $(if ($i.Status -eq 'crit') { 'CRÍTICO' } else { 'ATENÇÃO' }), $i.Text))
    }
    foreach ($id in $global:Saude.Order) {
        $sec = $rep.Sections[$id]
        if (-not $sec) { continue }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine((' {0} ({1})' -f $global:Saude.Meta[$id].Title, (Get-TIStatusWord $sec.Status)))
        foreach ($r in @($sec.Rows)) {
            [void]$sb.AppendLine(('   {0,-20} {1}' -f $r.Label, $r.Value))
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine((' Gerado pelo TI Suite v{0}' -f $global:TI.Version))
    try {
        [System.IO.File]::WriteAllText($dlg.FileName, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
        Write-TILog -Level 'Success' -Message ('Laudo salvo: {0}' -f $dlg.FileName)
        Show-TIToast -Text 'Laudo salvo.' -Type 'Success'
    } catch {
        Write-TILog -Level 'Error' -Message ('Falha ao salvar o laudo: {0}' -f $_.Exception.Message)
        Show-TIToast -Text 'Não foi possível salvar o laudo.' -Type 'Error'
    }
    $dlg.Dispose()
}

$wsSaude = @{
    Id       = 'saude'
    Title    = 'Saúde do PC'
    Sub      = 'Windows, discos, antivírus, relógio e bateria em uma verificação'
    Icon     = 'Health'
    Keywords = 'saude disco smart ssd hd bateria ativacao licenca windows update atualizacao antivirus defender firewall relogio hora data laudo'

    OnActivate = { if (-not $global:Saude.Report) { Invoke-SaudeCheck } }
    Refresh    = { Invoke-SaudeCheck }

    Actions = {
        param($Bar)
        $b1 = New-TIButton -Text 'Verificar agora' -Style 'Outline' -Width 146 -Height 34 -Icon 'Refresh' -Tip 'Rodar todas as verificações de novo (Ctrl+R)'
        $b1.Add_Click({ Invoke-SaudeCheck })
        $Bar.Controls.Add($b1)
        $b2 = New-TIButton -Text 'Salvar laudo' -Style 'Ghost' -Width 130 -Height 34 -Icon 'Report'
        $b2.Add_Click({ Export-SaudeLaudo })
        $Bar.Controls.Add($b2)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $cw = 466

        # --- Resumo ---------------------------------------------------------
        $b0 = New-TICard -Parent $flow -Title 'Resumo' -Desc 'O que pede atenção neste computador' -Icon 'Health' -Width $cw -Height 214 -Stretch
        $v = New-TILabel -Text 'Ainda não verificado' -Size 12 -Bold -Color $global:Pal.TextDim
        $v.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
        $b0.Controls.Add($v)
        $global:Saude.Verdict = $v
        $global:Saude.VerdictSub = New-TIHint -Parent $b0 -Text 'A verificação examina Windows, discos, proteção, relógio e bateria. Leva de 10 a 30 segundos.' -BottomGap 8
        $bar = New-TIButtonBar -Parent $b0
        $btnGo = New-TIButton -Text 'Verificar agora' -Style 'Primary' -Icon 'Health' -Width 170 -Height 38
        $btnGo.Add_Click({ Invoke-SaudeCheck })
        $bar.Controls.Add($btnGo)
        $btnLaudo = New-TIButton -Text 'Salvar laudo' -Style 'Outline' -Icon 'Report' -Width 150 -Height 38 -Tip 'Salva o resultado em .txt para anexar ao chamado'
        $btnLaudo.Add_Click({ Export-SaudeLaudo })
        $bar.Controls.Add($btnLaudo)
        $global:Saude.SummaryBody = $b0

        # --- Um card por verificação ------------------------------------------
        foreach ($key in $global:Saude.Order) {
            $m = $global:Saude.Meta[$key]
            $b = New-TICard -Parent $flow -Title $m.Title -Desc $m.Desc -Icon $m.Icon -Width $cw -Height 262 -WithStatus
            $null = New-TIHint -Parent $b -Text 'Aguardando a verificação.'
            $global:Saude.Cards[$key] = $b
        }
    }
}

Register-TIWorkspace @wsSaude
