# =====================================================================
# ÁREA: SAÚDE DO PC - Windows, discos, estabilidade, proteção, relógio e bateria
# =====================================================================

$global:TIWorkerLib += @'

# ---------------------------------------------------------------------
# SAÚDE DO PC (roda no worker)
# Cada verificação devolve uma "seção": Id, Status (ok|warn|crit|none),
# Rows (Label, Value, Tone), Issues (Status, Text), Partial (o que ficou
# sem ler por falta de administrador; vazio = completa) e NotApplicable
# (a verificação não vale para este PC, ex.: computador de mesa sem bateria).
# ---------------------------------------------------------------------
function New-TIHealthSection {
    param([string]$Id)
    return [pscustomobject]@{
        Id            = $Id
        Status        = 'ok'
        Rows          = (New-Object System.Collections.ArrayList)
        Issues        = (New-Object System.Collections.ArrayList)
        Partial       = ''
        NotApplicable = $false
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
    [void]$Sec.Issues.Add([pscustomobject]@{ Status = $Status; Text = $Text })
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
                # GracePeriodRemaining = tempo até a ativação KMS expirar (o PC tenta renovar a cada 7 dias)
                $days = [int][Math]::Floor($GraceMinutes / 1440)
                $span = if ($days -lt 1) { 'menos de 1 dia' } elseif ($days -eq 1) { '1 dia' } else { '{0} dias' -f $days }
                $text = 'Ativado{0}, válido por {1}' -f $suffix, $(if ($days -lt 1) { $span } else { 'mais ' + $span })
                if ($days -lt 30) {
                    return [pscustomobject]@{ Text = $text; Tone = 'warn'
                        Issue = ('A ativação KMS vence em {0}: o PC precisa alcançar o servidor KMS da rede.' -f $span) }
                }
                return [pscustomobject]@{ Text = $text; Tone = 'ok'; Issue = '' }
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

# Datas do Win32_QuickFixEngineering (Windows 10/11 devolvem M/d/aaaa)
function ConvertFrom-TIQfeDate {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $fmts = [string[]]@('M/d/yyyy', 'MM/dd/yyyy', 'yyyyMMdd', 'yyyy-MM-dd', 'M/d/yyyy h:mm:ss tt', 'M/d/yyyy HH:mm:ss')
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact($Raw.Trim(), $fmts, $inv, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
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

# Data ISO 8601 do registro (ex.: pausa do Windows Update, '2026-10-20T13:12:05Z') -> hora local
function ConvertFrom-TIIsoDate {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $sty = [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal'
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($Text.Trim(), $inv, $sty, [ref]$d)) { return $d.ToLocalTime() }
    return $null
}

# Diferença do relógio (positivo = PC adiantado)
function Format-TIOffset {
    param([double]$Seconds)
    if ([Math]::Abs($Seconds) -lt 2) { return 'em dia (menos de 2 s)' }
    $dir = if ($Seconds -gt 0) { 'adiantado' } else { 'atrasado' }
    # arredonda antes de escolher a unidade: 59,6 s vira "1 min", e não "60 s"
    $abs = [Math]::Round([Math]::Abs($Seconds))
    if ($abs -lt 60) { return ('{0} s {1}' -f [int]$abs, $dir) }
    if ($abs -lt 3600) {
        $m = [int][Math]::Floor($abs / 60)
        $s = [int]($abs - ($m * 60))
        if ($s -eq 0) { return ('{0} min {1}' -f $m, $dir) }
        return ('{0} min {1} s {2}' -f $m, $s, $dir)
    }
    if ($abs -lt 172800) {
        $h = [int][Math]::Floor($abs / 3600)
        $m = [int][Math]::Round(($abs - ($h * 3600)) / 60)
        if ($m -ge 60) { $h++; $m = 0 }
        if ($m -eq 0) { return ('{0} h {1}' -f $h, $dir) }
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

# 'a' / 'a e b' / 'a, b e c'
function Join-TIWords {
    param([string[]]$Items)
    $list = @($Items | Where-Object { $_ })
    if ($list.Count -eq 0) { return '' }
    if ($list.Count -eq 1) { return [string]$list[0] }
    return ((@($list[0..($list.Count - 2)]) -join ', ') + ' e ' + $list[$list.Count - 1])
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

# Fusos do Windows usados no Brasil (Id não depende do idioma do Windows)
function Test-TIBrazilTimeZone {
    param([string]$Id)
    $br = @('E. South America Standard Time', 'SA Eastern Standard Time', 'Bahia Standard Time', 'Tocantins Standard Time',
            'Central Brazilian Standard Time', 'SA Western Standard Time', 'SA Pacific Standard Time', 'UTC-02')
    return ($br -contains $Id)
}

# De onde o Windows tira a hora (w32time: Type e NtpServer do registro)
function Format-TITimeSource {
    param([string]$Type, [string]$NtpServer = '', [string]$Domain = '')
    $srv = (@(($NtpServer -split '\s+') | Where-Object { $_ } | ForEach-Object { ($_ -split ',')[0] })) -join ', '
    switch ($Type) {
        'NT5DS'   { return [pscustomobject]@{ Text = $(if ($Domain) { 'Controlador do domínio ' + $Domain } else { 'Controlador de domínio' }); Tone = '' } }
        'NTP'     { return [pscustomobject]@{ Text = $(if ($srv) { 'Servidor NTP: ' + $srv } else { 'Servidor NTP' }); Tone = '' } }
        'AllSync' { return [pscustomobject]@{ Text = 'Domínio ou servidor NTP'; Tone = '' } }
        'NoSync'  { return [pscustomobject]@{ Text = 'Nenhuma: acerto automático desligado'; Tone = 'warn' } }
    }
    return [pscustomobject]@{ Text = 'Não informada'; Tone = 'dim' }
}

# Temperatura do disco: limite por tipo (HD esquenta menos; NVMe trabalha quente). Crítico = limite + 10 °C.
function Get-TIDiskTempVerdict {
    param([int]$Celsius, [string]$Media = '')
    if ($Celsius -le 0) { return 'ok' }
    $warn = 60
    if ($Media -match 'NVMe') { $warn = 75 }
    elseif ($Media -match '^SSD') { $warn = 70 }
    elseif ($Media -match '^HD') { $warn = 55 }
    if ($Celsius -ge ($warn + 10)) { return 'crit' }
    if ($Celsius -ge $warn) { return 'warn' }
    return 'ok'
}

function Get-TIDiskWearVerdict {
    param([int]$Wear)
    if ($Wear -ge 95) { return 'crit' }
    if ($Wear -ge 80) { return 'warn' }
    return 'ok'
}

# Tom da linha de um disco e o aviso com o motivo (e não só "pede atenção")
function Get-TIDiskAssessment {
    param([string]$Label, [string]$Name = '', [string]$HealthTone = 'ok', [string]$Media = '',
          [int]$Temp = 0, [int]$Wear = 0, [int64]$Uncorrected = 0)
    $tone = $HealthTone
    $why = New-Object System.Collections.ArrayList
    $fail = $false; $worn = $false; $hot = $false
    if ($HealthTone -eq 'crit') { $fail = $true; [void]$why.Add('o Windows sinaliza falha') }
    elseif ($HealthTone -eq 'warn') { [void]$why.Add('o Windows sinaliza alerta de saúde') }
    if ($Uncorrected -gt 0) {
        $fail = $true
        $tone = 'crit'
        [void]$why.Add($(if ($Uncorrected -eq 1) { '1 erro de leitura sem correção' } else { '{0} erros de leitura sem correção' -f $Uncorrected }))
    }
    $wv = Get-TIDiskWearVerdict $Wear
    if ($wv -ne 'ok') {
        if ($wv -eq 'crit') { $worn = $true }
        $tone = Get-TIWorseStatus $tone $wv
        [void]$why.Add(('desgaste de {0}%' -f $Wear))
    }
    $tv = Get-TIDiskTempVerdict -Celsius $Temp -Media $Media
    if ($tv -ne 'ok') {
        $hot = $true
        $tone = Get-TIWorseStatus $tone $tv
        [void]$why.Add(('temperatura {0} ({1} °C)' -f $(if ($tv -eq 'crit') { 'muito alta' } else { 'alta' }), $Temp))
    }
    $issue = ''
    if ($tone -eq 'crit' -or $tone -eq 'warn') {
        $who = if ($Name) { '{0} ({1})' -f $Label, $Name } else { $Label }
        $head = if ($fail) { 'com falha' } elseif ($worn) { 'perto do fim da vida útil' } elseif ($tone -eq 'crit' -and $hot) { 'muito quente' } else { 'pede atenção' }
        $act = if ($fail) { 'Faça backup e troque o disco.' }
               elseif ($worn) { 'Faça backup e programe a troca.' }
               elseif ($hot) { 'Confira a ventilação e a poeira dentro do gabinete.' }
               else { 'Faça backup e acompanhe nas próximas verificações.' }
        $issue = '{0} {1}: {2}. {3}' -f $who, $head, (@($why) -join ', '), $act
    }
    return [pscustomobject]@{ Tone = $tone; Issue = $issue }
}

# Espaço livre: no disco do sistema vale também o limite em GB (o Windows Update
# precisa de uns 10 GB); nas outras unidades fixas o aviso é só de "quase cheia".
function Get-TIFreeSpaceVerdict {
    param([double]$Free, [double]$Size, [bool]$System = $true)
    if ($Size -le 0) { return 'ok' }
    $pct = 100 * $Free / $Size
    if ($System) {
        if ($Free -lt 5GB -or $pct -lt 5) { return 'crit' }
        if ($Free -lt 10GB -or $pct -lt 10) { return 'warn' }
        return 'ok'
    }
    if ($pct -lt 5 -or ($pct -lt 10 -and $Free -lt 10GB)) { return 'warn' }
    return 'ok'
}

# Eventos do log do sistema -> contagem. Itens: Id (41 ou 1001), Code (BugcheckCode do 41),
# Button (desligado segurando o botão de energia) e Time. Uma tela azul gera 1001 e também
# um 41 com BugcheckCode: conta uma vez só.
function Get-TICrashSummary {
    param($Items)
    $shut = 0; $btn = 0; $bsod = 0; $bsod41 = 0
    $lastShut = $null; $lastBsod = $null; $lastBsod41 = $null
    foreach ($e in @($Items)) {
        if (-not $e) { continue }
        $t = $e.Time
        if ([int]$e.Id -eq 1001) {
            $bsod++
            if ($t -and (-not $lastBsod -or $t -gt $lastBsod)) { $lastBsod = $t }
        } elseif ([int]$e.Id -eq 41) {
            if ([int64]$e.Code -ne 0) {
                $bsod41++
                if ($t -and (-not $lastBsod41 -or $t -gt $lastBsod41)) { $lastBsod41 = $t }
            } else {
                $shut++
                if ($e.Button) { $btn++ }
                if ($t -and (-not $lastShut -or $t -gt $lastShut)) { $lastShut = $t }
            }
        }
    }
    if ($bsod -eq 0 -and $bsod41 -gt 0) { $bsod = $bsod41; $lastBsod = $lastBsod41 }
    return [pscustomobject]@{ Shutdowns = $shut; PowerButton = $btn; BlueScreens = $bsod; LastShutdown = $lastShut; LastBlueScreen = $lastBsod }
}

function Get-TICrashTones {
    param([int]$Shutdowns, [int]$BlueScreens)
    $s = if ($Shutdowns -ge 3) { 'warn' } elseif ($Shutdowns -eq 0) { 'ok' } else { '' }
    $b = if ($BlueScreens -ge 3) { 'crit' } elseif ($BlueScreens -ge 1) { 'warn' } else { 'ok' }
    return [pscustomobject]@{ Shutdown = $s; BlueScreen = $b }
}

# BitLocker pelo WMI (administrador): ProtectionStatus 0 desligada, 1 ligada;
# ConversionStatus 0 descriptografado, 1 criptografado, 2 criptografando, 3 descriptografando, 4/5 pausado
function Get-TIBitLockerInfo {
    param([int]$Protection, [int]$Conversion = -1)
    $conv = switch ($Conversion) {
        0 { 'Desligado' }
        1 { 'Criptografado, proteção suspensa' }
        2 { 'Criptografando' }
        3 { 'Descriptografando' }
        4 { 'Criptografia pausada' }
        5 { 'Descriptografia pausada' }
        default { '' }
    }
    if ($Protection -eq 1) {
        $t = 'Ligado'
        if ($Conversion -ge 2 -and $conv) { $t += ' (' + $conv.ToLower() + ')' }
        return [pscustomobject]@{ Text = $t; Tone = 'warn'; On = $true }
    }
    if ($conv) { return [pscustomobject]@{ Text = $conv; Tone = ''; On = $false } }
    return [pscustomobject]@{ Text = 'Estado desconhecido'; Tone = 'dim'; On = $false }
}

# BitLocker pelo Explorer (System.Volume.BitLockerProtection, lido sem administrador):
# 1 ligado, 2 desligado, 3 criptografando, 4 descriptografando, 5 suspenso, 6 ligado e bloqueado, 8 aguardando ativação
function Get-TIBitLockerShellInfo {
    param($Value)
    $v = -1
    if ($null -ne $Value -and ([string]$Value) -match '^\d+$') { $v = [int]([string]$Value) }
    switch ($v) {
        1 { return [pscustomobject]@{ Text = 'Ligado'; Tone = 'warn'; On = $true } }
        2 { return [pscustomobject]@{ Text = 'Desligado'; Tone = ''; On = $false } }
        3 { return [pscustomobject]@{ Text = 'Ligado (criptografando)'; Tone = 'warn'; On = $true } }
        4 { return [pscustomobject]@{ Text = 'Descriptografando'; Tone = ''; On = $false } }
        5 { return [pscustomobject]@{ Text = 'Criptografado, proteção suspensa'; Tone = ''; On = $false } }
        6 { return [pscustomobject]@{ Text = 'Ligado'; Tone = 'warn'; On = $true } }
        8 { return [pscustomobject]@{ Text = 'Criptografado, aguardando ativação'; Tone = ''; On = $false } }
    }
    return $null
}

# --- Coletas -------------------------------------------------------------
function Test-TIHealthElevated {
    try {
        $p = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-TIDomainName {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.PartOfDomain) { return [string]$cs.Domain }
    } catch { }
    return ''
}

# Fabricante, modelo, série e etiqueta de patrimônio gravada na BIOS (para o laudo)
function Get-TIHealthIdentity {
    $cs = $null; $bios = $null; $enc = $null
    try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { }
    try { $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop } catch { }
    try { $enc = @(Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop) | Select-Object -First 1 } catch { }
    $serial = ''
    if ($bios) { $serial = ([string]$bios.SerialNumber).Trim() }
    $asset = ''
    if ($enc) { $asset = ([string]$enc.SMBIOSAssetTag).Trim() }
    if (Get-Command Test-TIValidSerial -ErrorAction SilentlyContinue) {
        if (-not (Test-TIValidSerial $serial)) { $serial = '' }
        if (-not (Test-TIValidSerial $asset)) { $asset = '' }
    }
    return [pscustomobject]@{
        Fabricante = $(if ($cs) { ([string]$cs.Manufacturer).Trim() } else { '' })
        Modelo     = $(if ($cs) { ([string]$cs.Model).Trim() } else { '' })
        Serie      = $serial
        AssetTag   = $asset
        Dominio    = $(if ($cs -and $cs.PartOfDomain) { [string]$cs.Domain } else { '' })
    }
}

# Executa um programa com tempo limite (o w32tm pode demorar sem rede)
function Invoke-TIExeWait {
    param([string]$FilePath, [string]$Arguments = '', [int]$TimeoutSec = 20)
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = $FilePath
    $p.StartInfo.Arguments = $Arguments
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.CreateNoWindow = $true
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    try {
        [void]$p.Start()
        $o = $p.StandardOutput.ReadToEndAsync()
        $e = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch { }
            return [pscustomobject]@{ ExitCode = -1; Output = ''; TimedOut = $true }
        }
        $p.WaitForExit()
        $txt = ''
        try { $txt = ([string]$o.Result + "`n" + [string]$e.Result).Trim() } catch { }
        return [pscustomobject]@{ ExitCode = $p.ExitCode; Output = $txt; TimedOut = $false }
    } finally {
        $p.Dispose()
    }
}

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
                # definições do antivírus e a plataforma de Segurança (KB5007651) saem toda semana
                # e mascarariam o Windows Update parado
                if ($title -match 'KB2267602|KB4052623|KB915597|KB5007651|Defender|Intelig.ncia de Seguran|Security Intelligence|Antimalware') { continue }
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

# Windows Update desativado, pausado ou desligado por política (laboratório "congelado")
function Get-TIWindowsUpdateState {
    $st = [pscustomobject]@{ Disabled = $false; PausedUntil = $null; PolicyOff = $false }
    try {
        $svc = Get-Service -Name 'wuauserv' -ErrorAction Stop
        if ([string]$svc.StartType -eq 'Disabled') { $st.Disabled = $true }
    } catch { }
    try {
        $ux = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -ErrorAction Stop
        foreach ($n in @('PauseUpdatesExpiryTime', 'PauseQualityUpdatesEndTime')) {
            $d = ConvertFrom-TIIsoDate ([string]$ux.$n)
            if ($d -and $d -gt (Get-Date) -and (-not $st.PausedUntil -or $d -gt $st.PausedUntil)) { $st.PausedUntil = $d }
        }
    } catch { }
    try {
        $au = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction Stop
        if ([int]$au.NoAutoUpdate -eq 1) { $st.PolicyOff = $true }
    } catch { }
    return $st
}

function Get-TIHealthWindows {
    $sec = New-TIHealthSection 'windows'
    Emit 'Verificando o Windows: versão, ativação e atualizações...' 'Info' 8
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

    Emit 'Consultando a ativação (pode levar alguns segundos)...' 'Debug' 12
    $esu = $false
    try {
        $lic = @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction Stop)
        # Licenças complementares (ex.: ESU do Windows 10) têm o mesmo ApplicationID: não contam como a licença do Windows
        $base = @($lic | Where-Object { -not $_.LicenseIsAddon })
        $esu = (@($lic | Where-Object { $_.LicenseIsAddon -and [int]$_.LicenseStatus -eq 1 -and (('{0} {1}' -f $_.Name, $_.Description) -match 'ESU') }).Count -gt 0)
        $best = $null
        foreach ($l in $base) {
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

    # Só o Windows 10 de estação de trabalho (Windows Server e LTSC têm outro calendário de suporte)
    if ($os -and [int]$os.ProductType -eq 1 -and $build -gt 0 -and $build -lt 22000 -and $name -match 'Windows 10' -and $name -notmatch 'LTS[BC]') {
        if ($esu) {
            Add-TIHealthIssue $sec 'warn' 'O Windows 10 perdeu o suporte em 14/10/2025. Este PC tem o ESU (atualizações de segurança estendidas), que vale por tempo limitado: planeje a migração para o Windows 11.'
        } else {
            Add-TIHealthIssue $sec 'warn' 'O Windows 10 está sem suporte da Microsoft desde 14/10/2025: planeje a migração para o Windows 11.'
        }
    }

    Emit 'Lendo o histórico do Windows Update...' 'Debug' 18
    $wu = Get-TIWindowsUpdateState
    $wuShort = New-Object System.Collections.ArrayList
    $wuLong = New-Object System.Collections.ArrayList
    if ($wu.Disabled) {
        [void]$wuShort.Add('Serviço desativado')
        [void]$wuLong.Add('o serviço Windows Update está desativado')
    }
    if ($wu.PausedUntil) {
        $until = ([datetime]$wu.PausedUntil).ToString('dd/MM/yyyy')
        [void]$wuShort.Add(('Pausado até {0}' -f $until))
        [void]$wuLong.Add(('as atualizações estão pausadas até {0}' -f $until))
    }
    if ($wu.PolicyOff) {
        [void]$wuShort.Add('Automático desligado por política')
        [void]$wuLong.Add('a atualização automática está desligada por política de grupo')
    }
    $ageIssue = $false
    $last = Get-TILastUpdateInfo
    if ($last) {
        # dias do calendário (como o Format-TIAgo), não blocos de 24 h
        $days = [int]((Get-Date).Date - ([datetime]$last.Date).Date).TotalDays
        $tone = Get-TIUpdateVerdict $days
        Add-TIHealthRow $sec 'Última atualização' ('{0} ({1})' -f ([datetime]$last.Date).ToString('dd/MM/yyyy'), (Format-TIDaysText $days)) $tone
        if ($tone -ne 'ok') {
            $why = if ($wuLong.Count -gt 0) { ' (' + (Join-TIWords $wuLong.ToArray()) + ')' } else { '' }
            Add-TIHealthIssue $sec $tone ('Nenhuma atualização do Windows há {0} dias{1}: rode o Windows Update.' -f $days, $why)
            $ageIssue = $true
        }
    } else {
        Add-TIHealthRow $sec 'Última atualização' 'Histórico indisponível' 'dim'
    }
    if ($wuShort.Count -eq 0) {
        Add-TIHealthRow $sec 'Windows Update' 'Ativo' 'ok'
    } else {
        Add-TIHealthRow $sec 'Windows Update' ($wuShort.ToArray() -join '; ') 'warn'
        # com as atualizações já atrasadas, o motivo vai no mesmo aviso (um problema, um aviso)
        if (-not $ageIssue) { Add-TIHealthIssue $sec 'warn' ('O Windows pode ficar sem atualizações de segurança: ' + (Join-TIWords $wuLong.ToArray()) + '.') }
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
    return $sec
}

# Letras de unidades em discos USB (HD externo aparece como unidade fixa)
function Get-TIUsbDriveLetters {
    $set = @{}
    try {
        foreach ($dk in @(Get-Disk -ErrorAction Stop | Where-Object { -not (Test-TIInternalDisk $_) })) {
            foreach ($pt in @(Get-Partition -DiskNumber $dk.Number -ErrorAction SilentlyContinue)) {
                $l = [string]$pt.DriveLetter
                if ($l -match '^[A-Za-z]$') { $set[$l.ToUpper() + ':'] = $true }
            }
        }
    } catch { }
    return $set
}

function Get-TIHealthDisk {
    $sec = New-TIHealthSection 'disk'
    Emit 'Verificando os discos...' 'Info' 30
    $elev = Test-TIHealthElevated
    $ptBr = [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')
    $n = 0
    $relAny = $false
    $pd = @()
    try { $pd = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { Test-TIInternalDisk $_ } | Sort-Object DeviceId) } catch { }
    foreach ($d in $pd) {
        $n++
        $hw = ConvertTo-TIHealthWord $d.HealthStatus
        $media = ConvertTo-TIMediaWord $d.MediaType $d.BusType
        $label = ('{0} {1}' -f $media, (Format-TIDiskSize ([double]$d.Size)))
        $parts = New-Object System.Collections.ArrayList
        [void]$parts.Add($hw.Word)
        $t = 0; $w = 0; $hours = 0L; $unc = 0L
        $rel = $null
        try { $rel = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction Stop } catch { }
        if ($rel) {
            $relAny = $true
            try { $t = [int]$rel.Temperature } catch { }
            try { $w = [int]$rel.Wear } catch { }
            try { $hours = [int64]$rel.PowerOnHours } catch { }
            try { $unc = [int64]$rel.ReadErrorsUncorrected } catch { }
        }
        if ($t -gt 0) { [void]$parts.Add(('{0} °C' -f $t)) }
        if ($w -gt 0) { [void]$parts.Add(('{0}% de desgaste' -f $w)) }
        if ($unc -gt 0) { [void]$parts.Add($(if ($unc -eq 1) { '1 erro de leitura' } else { '{0} erros de leitura' -f $unc })) }
        if ($hours -gt 0) { [void]$parts.Add(('{0} h de uso' -f $hours.ToString('N0', $ptBr))) }
        $as = Get-TIDiskAssessment -Label $label -Name (([string]$d.FriendlyName).Trim()) -HealthTone $hw.Tone -Media $media -Temp $t -Wear $w -Uncorrected $unc
        Add-TIHealthRow $sec $label (@($parts) -join ', ') $as.Tone
        if ($as.Issue) { Add-TIHealthIssue $sec $as.Tone $as.Issue }
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
    # Sem administrador o Windows não entrega SMART, temperatura e desgaste: não afirmar "Em ordem" pleno
    if ($n -gt 0 -and -not $relAny -and -not $elev) {
        Add-TIHealthRow $sec 'SMART' 'Temperatura e desgaste precisam de administrador' 'dim'
        $sec.Partial = 'o SMART dos discos (temperatura e desgaste)'
    }

    $sys = if ($env:SystemDrive) { $env:SystemDrive.ToUpper() } else { 'C:' }
    $usb = Get-TIUsbDriveLetters
    try {
        $lds = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | Where-Object { [double]$_.Size -gt 0 })
        $lds = @($lds | Sort-Object @{ Expression = { if (([string]$_.DeviceID).ToUpper() -eq $sys) { 0 } else { 1 } } }, DeviceID)
        foreach ($ld in $lds) {
            $dev = ([string]$ld.DeviceID).ToUpper()
            $isSys = ($dev -eq $sys)
            if (-not $isSys -and $usb.ContainsKey($dev)) { continue }
            $free = [double]$ld.FreeSpace
            $size = [double]$ld.Size
            $pct = [int][Math]::Floor(100 * $free / $size)
            $tone = Get-TIFreeSpaceVerdict -Free $free -Size $size -System $isSys
            Add-TIHealthRow $sec ('Livre em ' + $dev) ('{0} de {1} ({2}%)' -f (Format-TIByte $free), (Format-TIByte $size), $pct) $tone
            if ($tone -eq 'ok') { continue }
            if (-not $isSys) {
                Add-TIHealthIssue $sec 'warn' ('A unidade {0} está quase cheia: {1} livres ({2}%).' -f $dev.TrimEnd(':'), (Format-TIByte $free), $pct)
            } elseif ($tone -eq 'crit') {
                Add-TIHealthIssue $sec 'crit' ('Pouco espaço livre no disco do sistema ({0}): {1} ({2}%). O Windows Update e os programas podem falhar: rode a Limpeza profunda em Manutenção.' -f $dev, (Format-TIByte $free), $pct)
            } else {
                Add-TIHealthIssue $sec 'warn' ('Pouco espaço livre no disco do sistema ({0}): {1} ({2}%). O Windows Update precisa de uns 10 GB livres: rode a Limpeza profunda em Manutenção.' -f $dev, (Format-TIByte $free), $pct)
            }
        }
    } catch { }
    if ($n -eq 0) { Add-TIHealthRow $sec 'Discos' 'O Windows não informou a saúde dos discos' 'dim' }
    return $sec
}

# BitLocker: WMI com administrador; sem ele, a mesma informação que o Explorer mostra
# (nunca o texto do manage-bde, que muda com o idioma do Windows)
function Get-TIBitLockerState {
    param([string]$Drive = 'C:')
    try {
        $vol = @(Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter ("DriveLetter='{0}'" -f $Drive) -ErrorAction Stop) | Select-Object -First 1
        if ($vol) {
            $conv = -1
            if ($null -ne $vol.ConversionStatus) { $conv = [int]$vol.ConversionStatus }
            else { try { $conv = [int](Invoke-CimMethod -InputObject $vol -MethodName 'GetConversionStatus' -ErrorAction Stop).ConversionStatus } catch { } }
            return (Get-TIBitLockerInfo -Protection ([int]$vol.ProtectionStatus) -Conversion $conv)
        }
    } catch { }
    try {
        $sh = New-Object -ComObject 'Shell.Application'
        try {
            $val = $sh.NameSpace($Drive + '\').Self.ExtendedProperty('System.Volume.BitLockerProtection')
            return (Get-TIBitLockerShellInfo $val)
        } finally {
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) } catch { }
        }
    } catch { }
    return $null
}

function Get-TIHealthSecurity {
    $sec = New-TIHealthSection 'security'
    Emit 'Verificando antivírus, firewall e BitLocker...' 'Info' 45
    $avs = @()
    try { $avs = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop) } catch { }
    $mp = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { }
    $defOn = $false
    if ($mp) { $defOn = ([bool]$mp.AntivirusEnabled -and [string]$mp.AMRunningMode -notmatch 'Passive') }
    $anyOn = $false
    foreach ($a in $avs) {
        $st = Get-TIAvState ([int64]$a.productState)
        $nm = [string]$a.displayName
        if ($st.Enabled) { $anyOn = $true }
        $txt = if (-not $st.Enabled) { 'desligado' } elseif ($st.UpToDate) { 'ativo e atualizado' } else { 'ativo, mas desatualizado' }
        $tone = if (-not $st.Enabled) { 'dim' } elseif ($st.UpToDate) { 'ok' } else { 'warn' }
        Add-TIHealthRow $sec 'Antivírus' ('{0}: {1}' -f $nm, $txt) $tone
        # Defender: o aviso das definições vem do Get-MpComputerStatus, que diz a idade (um problema, um aviso)
        if ($st.Enabled -and -not $st.UpToDate -and -not ($defOn -and $nm -match 'Defender')) {
            Add-TIHealthIssue $sec 'warn' ('{0} está com as definições desatualizadas.' -f $nm)
        }
    }
    if ($mp) {
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

    # Firewall: antivírus com firewall próprio desliga o do Windows (não é problema)
    $fw3 = New-Object System.Collections.ArrayList
    try {
        foreach ($f in @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName FirewallProduct -ErrorAction Stop)) {
            if ((Get-TIAvState ([int64]$f.productState)).Enabled) { [void]$fw3.Add([string]$f.displayName) }
        }
    } catch { }
    $third = Join-TIWords $fw3.ToArray()
    $svcRun = $null
    try { $svcRun = ((Get-Service -Name 'mpssvc' -ErrorAction Stop).Status -eq 'Running') } catch { }
    if ($svcRun -eq $false) {
        # perfil "ligado" com o serviço parado não protege
        if ($third) {
            Add-TIHealthRow $sec 'Firewall' 'Do Windows: serviço parado' 'dim'
        } else {
            Add-TIHealthRow $sec 'Firewall' 'Serviço parado' 'warn'
            Add-TIHealthIssue $sec 'warn' 'O serviço do Firewall do Windows (mpssvc) está parado: o firewall não protege este computador.'
        }
    } else {
        try {
            # ActiveStore = política efetiva (GPO do domínio + configuração local)
            $fw = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
            $off = @($fw | Where-Object { [string]$_.Enabled -eq 'False' } | ForEach-Object { ConvertTo-TIFirewallProfileName ([string]$_.Name) })
            if ($off.Count -eq 0) {
                Add-TIHealthRow $sec 'Firewall' ('Ligado nos {0} perfis' -f $fw.Count) 'ok'
            } else {
                $prof = Join-TIWords $off
                if ($third) {
                    Add-TIHealthRow $sec 'Firewall' ('Do Windows desligado: ' + $prof) 'dim'
                } else {
                    Add-TIHealthRow $sec 'Firewall' ('Desligado: ' + $prof) 'warn'
                    Add-TIHealthIssue $sec 'warn' ('Firewall do Windows desligado {0} {1}.' -f $(if ($off.Count -eq 1) { 'no perfil' } else { 'nos perfis' }), $prof)
                }
            }
        } catch {
            Add-TIHealthRow $sec 'Firewall' 'Não foi possível consultar' 'dim'
        }
    }
    if ($third) { Add-TIHealthRow $sec 'Outro firewall' ($third + ': ativo') 'ok' }

    # BitLocker no disco do sistema (só leitura)
    $sys = if ($env:SystemDrive) { $env:SystemDrive.ToUpper() } else { 'C:' }
    $bl = $null
    try { $bl = Get-TIBitLockerState -Drive $sys } catch { }
    if ($bl) {
        Add-TIHealthRow $sec ('BitLocker ({0})' -f $sys) $bl.Text $bl.Tone
        if ($bl.On) {
            Add-TIHealthIssue $sec 'warn' ('O BitLocker está ligado no disco do sistema ({0}). Antes de trocar peças, atualizar a BIOS ou restaurar o Windows, confirme onde está guardada a chave de recuperação.' -f $sys)
        }
    } elseif (-not (Test-TIHealthElevated)) {
        Add-TIHealthRow $sec 'BitLocker' 'Precisa de administrador' 'dim'
        $sec.Partial = 'o BitLocker'
    } else {
        Add-TIHealthRow $sec 'BitLocker' 'Não disponível neste Windows' 'dim'
    }
    return $sec
}

# Kernel-Power 41 (desligou sem encerrar) e BugCheck 1001 (tela azul) do log do sistema
function Get-TICrashEvents {
    param([int]$Days = 30)
    $fh = @{ LogName = 'System'; Id = @(41, 1001); StartTime = (Get-Date).AddDays(-1 * $Days) }
    $raw = @()
    try {
        $raw = @(Get-WinEvent -FilterHashtable $fh -MaxEvents 200 -ErrorAction Stop)
    } catch {
        # "nenhum evento encontrado" também chega como erro (texto traduzido; o Id não)
        if ([string]$_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound') { throw }
    }
    $out = New-Object System.Collections.ArrayList
    foreach ($ev in $raw) {
        $id = [int]$ev.Id
        $prov = [string]$ev.ProviderName
        if ($id -eq 41 -and $prov -ne 'Microsoft-Windows-Kernel-Power') { continue }
        if ($id -eq 1001 -and $prov -notmatch 'WER-SystemErrorReporting|BugCheck') { continue }
        $code = 0L
        $button = $false
        if ($id -eq 41) {
            try {
                $x = [xml]$ev.ToXml()
                foreach ($dt in @($x.Event.EventData.Data)) {
                    if ($null -eq $dt) { continue }
                    $nm = [string]$dt.GetAttribute('Name')
                    $val = ([string]$dt.InnerText).Trim()
                    if ($nm -eq 'BugcheckCode') { [void][int64]::TryParse($val, [ref]$code) }
                    elseif ($nm -eq 'PowerButtonTimestamp') { $button = ($val -and $val -notmatch '^0*$') }
                }
            } catch { }
        }
        [void]$out.Add([pscustomobject]@{ Id = $id; Code = $code; Button = $button; Time = $ev.TimeCreated })
    }
    return ,($out.ToArray())
}

function Get-TIHealthStability {
    $sec = New-TIHealthSection 'stability'
    Emit 'Procurando desligamentos inesperados e telas azuis dos últimos 30 dias...' 'Info' 58
    $items = $null
    try {
        $items = Get-TICrashEvents -Days 30
    } catch {
        $sec.Status = 'none'
        Add-TIHealthRow $sec 'Eventos' 'Não foi possível ler o log do sistema' 'dim'
        return $sec
    }
    $s = Get-TICrashSummary -Items $items
    $tones = Get-TICrashTones -Shutdowns $s.Shutdowns -BlueScreens $s.BlueScreens
    $day = { param($d) if ($d) { ([datetime]$d).ToString('dd/MM/yyyy') } else { '?' } }

    if ($s.Shutdowns -eq 0) {
        Add-TIHealthRow $sec 'Desligamentos' 'Nenhum inesperado' 'ok'
    } else {
        $txt = if ($s.Shutdowns -eq 1) { '1 inesperado, em {0}' -f (& $day $s.LastShutdown) } else { '{0} inesperados, o último em {1}' -f $s.Shutdowns, (& $day $s.LastShutdown) }
        if ($s.PowerButton -gt 0) { $txt += (' ({0} no botão de energia)' -f $s.PowerButton) }
        Add-TIHealthRow $sec 'Desligamentos' $txt $tones.Shutdown
        if ($tones.Shutdown -eq 'warn') {
            if ($s.PowerButton -ge $s.Shutdowns) {
                $msg = '{0} desligamentos inesperados nos últimos 30 dias, todos segurando o botão de energia: o computador pode estar travando.' -f $s.Shutdowns
            } else {
                $msg = '{0} desligamentos inesperados nos últimos 30 dias: confira a tomada e o estabilizador, a fonte e se o computador está esquentando.' -f $s.Shutdowns
            }
            Add-TIHealthIssue $sec 'warn' $msg
        }
    }

    if ($s.BlueScreens -eq 0) {
        Add-TIHealthRow $sec 'Telas azuis' 'Nenhuma' 'ok'
    } else {
        $when = & $day $s.LastBlueScreen
        $txt = if ($s.BlueScreens -eq 1) { '1, em {0}' -f $when } else { '{0}, a última em {1}' -f $s.BlueScreens, $when }
        Add-TIHealthRow $sec 'Telas azuis' $txt $tones.BlueScreen
        $msg = if ($s.BlueScreens -eq 1) { 'Houve 1 tela azul nos últimos 30 dias (em {0})' -f $when } else { 'Houve {0} telas azuis nos últimos 30 dias (a última em {1})' -f $s.BlueScreens, $when }
        Add-TIHealthIssue $sec $tones.BlueScreen ($msg + ': pode ser driver, memória RAM ou disco com defeito.')
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
    $dom = Get-TIDomainName
    # a interface usa estes dois campos: acerto só pelo domínio e botão "Usar fuso de Brasília"
    Add-Member -InputObject $sec -NotePropertyName 'Domain' -NotePropertyValue $dom -Force
    $tzOk = $true
    try { [System.TimeZoneInfo]::ClearCachedData() } catch { }
    Add-TIHealthRow $sec 'Hora do PC' ((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))
    try {
        $tz = Get-TimeZone
        $tzOk = Test-TIBrazilTimeZone ([string]$tz.Id)
        $auto = $false
        try { $auto = ([string](Get-Service -Name 'tzautoupdate' -ErrorAction Stop).StartType -ne 'Disabled') } catch { }
        $tzTxt = [string]$tz.DisplayName
        if ($auto) { $tzTxt += ' (automático)' }
        Add-TIHealthRow $sec 'Fuso horário' $tzTxt $(if ($tzOk) { '' } else { 'warn' })
        if (-not $tzOk) {
            Add-TIHealthIssue $sec 'warn' ('Fuso horário fora do Brasil: {0}. A hora aparece errada mesmo com o relógio certo: use "Usar fuso de Brasília" ou ajuste em Configurações > Hora e idioma.' -f $tz.DisplayName)
        }
    } catch { }
    Add-Member -InputObject $sec -NotePropertyName 'BrazilZone' -NotePropertyValue $tzOk -Force

    $type = ''; $ntp = ''
    try {
        $par = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -ErrorAction Stop
        $type = [string]$par.Type
        $ntp = [string]$par.NtpServer
    } catch { }
    $src = Format-TITimeSource -Type $type -NtpServer $ntp -Domain $dom
    Add-TIHealthRow $sec 'Fonte de horário' $src.Text $src.Tone

    $svcBad = $false
    try {
        $svc = Get-Service -Name 'w32time' -ErrorAction Stop
        if ($svc.Status -eq 'Running') { Add-TIHealthRow $sec 'Serviço de horário' 'Em execução' 'ok' }
        elseif ([string]$svc.StartType -eq 'Disabled') {
            $svcBad = $true
            Add-TIHealthRow $sec 'Serviço de horário' 'Desativado' 'warn'
            Add-TIHealthIssue $sec 'warn' 'O serviço de horário do Windows (w32time) está desativado: o relógio não se acerta sozinho.'
        }
        else { Add-TIHealthRow $sec 'Serviço de horário' 'Parado (liga quando precisa)' 'dim' }
    } catch {
        $svcBad = $true
        Add-TIHealthRow $sec 'Serviço de horário' 'Não encontrado' 'warn'
        Add-TIHealthIssue $sec 'warn' 'O serviço de horário do Windows (w32time) não foi encontrado: o relógio não se acerta sozinho.'
    }
    if ($type -eq 'NoSync' -and -not $svcBad) {
        Add-TIHealthIssue $sec 'warn' 'O acerto automático do relógio está desligado no Windows: o relógio não se acerta sozinho.'
    }

    $net = Get-TIInternetTime
    if ($null -eq $net.OffsetSeconds) {
        Add-TIHealthRow $sec 'Diferença' 'Sem internet para comparar' 'dim'
        if ($sec.Issues.Count -eq 0) { $sec.Status = 'none' }
    } else {
        $tone = Get-TIClockVerdict $net.OffsetSeconds
        $off = Format-TIOffset $net.OffsetSeconds
        Add-TIHealthRow $sec 'Diferença' $off $tone
        if ($tone -ne 'ok') {
            if ($dom) {
                # no domínio a hora vem do controlador (o login Kerberos depende dela)
                Add-TIHealthIssue $sec $tone ('Relógio {0} em relação à internet. Neste PC do domínio, use "Acertar relógio" para sincronizar com o controlador de domínio; se continuar errado, o horário do servidor precisa ser corrigido.' -f $off)
            } elseif ($tone -eq 'crit') {
                Add-TIHealthIssue $sec 'crit' ('Relógio {0}: sites seguros e o login na rede podem falhar. Use "Acertar relógio".' -f $off)
            } else {
                Add-TIHealthIssue $sec 'warn' ('Relógio {0}: vale acertar.' -f $off)
            }
        }
    }
    return $sec
}

# Acertar relógio: primeiro o Windows (w32tm). No domínio, fica só nisso (a hora certa
# é a do controlador de domínio). Fora do domínio, se continuar mais de 5 s errado e duas
# fontes da internet concordarem, ajusta pela diferença medida. O fuso não é alterado.
# Falhas vão para o Write-Error: a auditoria registra ERRO e o aviso final não fica verde.
function Sync-TIClock {
    $dom = Get-TIDomainName
    Emit $(if ($dom) { 'Pedindo ao Windows para sincronizar o relógio com o controlador de domínio...' } else { 'Pedindo ao Windows para sincronizar o relógio...' }) 'Info' 10
    $svcOk = $true
    try {
        $svc = Get-Service -Name 'w32time' -ErrorAction Stop
        if ([string]$svc.StartType -eq 'Disabled') {
            $svcOk = $false
            Emit 'O serviço de horário do Windows (w32time) está desativado.' 'Warn'
        } elseif ($svc.Status -ne 'Running') {
            $svc.Start()
            $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
            Start-Sleep -Seconds 2
        }
    } catch {
        $svcOk = $false
        Emit ('Serviço de horário indisponível: {0}' -f $_.Exception.Message) 'Warn'
    }
    $synced = $false
    if ($svcOk) {
        $exe = 'w32tm.exe'
        if ($env:SystemRoot -and (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\w32tm.exe'))) { $exe = Join-Path $env:SystemRoot 'System32\w32tm.exe' }
        try {
            $run = Invoke-TIExeWait -FilePath $exe -Arguments '/resync /rediscover' -TimeoutSec 25
            if ($run.TimedOut) {
                Emit 'O w32tm não respondeu em 25 s.' 'Warn'
            } elseif ($run.ExitCode -eq 0) {
                $synced = $true
                Emit 'O Windows sincronizou com o servidor de horário.' 'Success'
            } else {
                $lastLine = (@(($run.Output -split "`r?`n") | Where-Object { $_.Trim() }) | Select-Object -Last 1)
                Emit ('O w32tm não sincronizou: {0}' -f $lastLine) 'Warn'
            }
        } catch {
            Emit ('Não foi possível rodar o w32tm: {0}' -f $_.Exception.Message) 'Warn'
        }
        if ($synced) { Start-Sleep -Seconds 2 }
    }

    $result = 'failed'
    $toast = ''
    if ($dom) {
        if ($synced) {
            $net = Get-TIInternetTime
            if ($null -ne $net.OffsetSeconds -and [Math]::Abs($net.OffsetSeconds) -gt 120) {
                $result = 'domainoff'
                $toast = 'Sincronizado, mas o servidor do domínio está com a hora errada.'
                Emit ('Sincronizado com o domínio, mas o relógio continua {0} em relação à internet: corrija o horário do controlador de domínio.' -f (Format-TIOffset $net.OffsetSeconds)) 'Warn'
            } else {
                $result = 'synced'
                $toast = 'Relógio sincronizado com o domínio.'
                Emit 'Relógio sincronizado com o controlador de domínio.' 'Success'
            }
        } else {
            $toast = 'Não foi possível sincronizar com o domínio.'
            Write-Error 'Não foi possível sincronizar com o controlador de domínio. Neste PC do domínio o TI Suite não ajusta pela internet: confira a rede e o horário do servidor.'
        }
    } else {
        Emit 'Conferindo com o horário da internet...' 'Info' 60
        $net = Get-TIInternetTime
        if ($null -eq $net.OffsetSeconds) {
            if ($synced) {
                $result = 'synced'
                $toast = 'Relógio sincronizado pelo Windows.'
                Emit 'Sem internet para conferir, mas o Windows informou que sincronizou.' 'Warn'
            } else {
                $toast = 'Sem internet: nada foi alterado.'
                Write-Error 'Sem internet para conferir o horário e o Windows não sincronizou: nada foi alterado.'
            }
        } else {
            $abs = [Math]::Abs($net.OffsetSeconds)
            $off = Format-TIOffset $net.OffsetSeconds
            if ($abs -lt 2) {
                $result = 'ok'
                $toast = 'O relógio está certo.'
                Emit 'Relógio certo: diferença menor que 2 s.' 'Success'
            } elseif ($abs -le 5) {
                $result = 'ok'
                $toast = 'O relógio está certo.'
                Emit ('Relógio dentro da tolerância ({0}).' -f $off) 'Success'
            } elseif ($net.Agree -lt 2) {
                $result = 'disagree'
                $toast = 'As fontes da internet não concordaram: nada foi alterado.'
                Write-Error ('Relógio {0}, mas as fontes de horário da internet não concordaram entre si: nada foi alterado.' -f $off)
            } else {
                try {
                    Set-Date -Adjust ([TimeSpan]::FromSeconds(-1 * $net.OffsetSeconds)) -ErrorAction Stop | Out-Null
                    $result = 'adjusted'
                    $toast = 'Relógio ajustado pelo horário da internet.'
                    Emit ('Relógio ajustado pelo horário da internet (estava {0}).' -f $off) 'Success'
                } catch {
                    $toast = 'Não foi possível ajustar o relógio.'
                    Write-Error ('Não foi possível ajustar o relógio: {0}' -f $_.Exception.Message)
                }
            }
        }
    }
    return [pscustomobject]@{ Result = $result; Toast = $toast; Section = (Get-TIHealthClock) }
}

# "Usar fuso de Brasília"
function Set-TIBrasiliaTimeZone {
    Emit 'Trocando o fuso horário para Brasília (UTC-03:00)...' 'Info' 20
    $result = 'failed'
    $toast = 'Não foi possível trocar o fuso horário.'
    try {
        Set-TimeZone -Id 'E. South America Standard Time' -ErrorAction Stop
        try { [System.TimeZoneInfo]::ClearCachedData() } catch { }
        $result = 'ok'
        $toast = 'Fuso horário trocado para Brasília.'
        Emit 'Fuso horário trocado para Brasília (UTC-03:00).' 'Success'
    } catch {
        Write-Error ('Não foi possível trocar o fuso horário: {0}' -f $_.Exception.Message)
    }
    return [pscustomobject]@{ Result = $result; Toast = $toast; Section = (Get-TIHealthClock) }
}

function Get-TIHealthBattery {
    $sec = New-TIHealthSection 'battery'
    Emit 'Verificando a bateria...' 'Info' 88
    # -ErrorAction Stop: falha na consulta vira erro da etapa, e não "computador de mesa"
    $bat = @(Get-CimInstance Win32_Battery -ErrorAction Stop)
    if ($bat.Count -eq 0) {
        $sec.Status = 'none'
        $sec.NotApplicable = $true
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
    } elseif (-not (Test-TIHealthElevated)) {
        # sem administrador o Windows não entrega a capacidade: não culpar o fabricante
        Add-TIHealthRow $sec 'Capacidade' 'Precisa de administrador' 'dim'
        $sec.Partial = 'a capacidade da bateria'
    } else {
        Add-TIHealthRow $sec 'Capacidade' 'Não informada pelo fabricante' 'dim'
    }
    if ($cycles -gt 0) { Add-TIHealthRow $sec 'Ciclos de carga' ([string]$cycles) }
    return $sec
}

function Invoke-TIHealthStep {
    param([string]$Id, [string]$Name, [scriptblock]$Body)
    try {
        return (& $Body)
    } catch {
        Emit ('Falha ao verificar {0}: {1}' -f $Name, $_.Exception.Message) 'Warn'
        $s = New-TIHealthSection $Id
        $s.Status = 'none'
        Add-TIHealthRow $s 'Erro' $_.Exception.Message 'dim'
        return $s
    }
}

function Get-TIHealthReport {
    $elev = Test-TIHealthElevated
    if (-not $elev) { Emit 'Sem administrador: SMART dos discos, capacidade da bateria e BitLocker podem ficar de fora.' 'Info' 2 }
    $ident = $null
    try { $ident = Get-TIHealthIdentity } catch { }
    $sections = [ordered]@{}
    $sections['windows']   = Invoke-TIHealthStep 'windows'   'o Windows'        { Get-TIHealthWindows }
    $sections['disk']      = Invoke-TIHealthStep 'disk'      'os discos'        { Get-TIHealthDisk }
    $sections['security']  = Invoke-TIHealthStep 'security'  'a proteção'       { Get-TIHealthSecurity }
    $sections['stability'] = Invoke-TIHealthStep 'stability' 'a estabilidade'   { Get-TIHealthStability }
    $sections['clock']     = Invoke-TIHealthStep 'clock'     'o relógio'        { Get-TIHealthClock }
    $sections['battery']   = Invoke-TIHealthStep 'battery'   'a bateria'        { Get-TIHealthBattery }
    $n = 0
    $miss = New-Object System.Collections.ArrayList
    foreach ($s in $sections.Values) {
        $n += @($s.Issues).Count
        if ($s.Partial) { [void]$miss.Add([string]$s.Partial) }
    }
    $note = ''
    if ($miss.Count -gt 0) {
        $note = 'Verificação parcial: sem administrador, não foi possível ler {0}. Clique no selo da barra lateral para reabrir como administrador.' -f (Join-TIWords $miss.ToArray())
    }
    Emit ('Verificação concluída: {0} ponto(s) para revisar.' -f $n) $(if ($n -gt 0) { 'Warn' } else { 'Success' }) 100
    return [pscustomobject]@{
        Sections    = $sections
        CheckedAt   = (Get-Date)
        Computer    = $env:COMPUTERNAME
        Elevated    = $elev
        Identity    = $ident
        PartialNote = $note
    }
}
'@

# ---------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------
$global:Saude = @{
    Report      = $null
    Cards       = @{}
    StatusText  = @{}
    Order       = @('windows', 'disk', 'stability', 'security', 'clock', 'battery')
    Meta        = @{
        windows   = @{ Title = 'Windows';      Desc = 'Versão, ativação, atualizações e reinício pendente';  Icon = 'Update' }
        disk      = @{ Title = 'Discos';       Desc = 'Saúde, temperatura, desgaste e espaço livre';         Icon = 'Diagnostic' }
        stability = @{ Title = 'Estabilidade'; Desc = 'Desligamentos inesperados e telas azuis em 30 dias';  Icon = 'Power' }
        security  = @{ Title = 'Proteção';     Desc = 'Antivírus, firewall e BitLocker';                     Icon = 'Shield' }
        clock     = @{ Title = 'Data e hora';  Desc = 'Relógio e fuso comparados com a internet';            Icon = 'Recent' }
        battery   = @{ Title = 'Bateria';      Desc = 'Carga e capacidade em relação à original';            Icon = 'Battery' }
    }
    SummaryBody = $null
    Verdict     = $null
    VerdictSub  = $null
}

# Problemas do relatório na ordem das áreas (funções puras: testáveis sem janela)
function Get-SaudeIssues {
    param($Report)
    $all = New-Object System.Collections.ArrayList
    foreach ($id in $global:Saude.Order) {
        $sec = $Report.Sections[$id]
        if (-not $sec) { continue }
        foreach ($i in @($sec.Issues)) { if ($i) { [void]$all.Add($i) } }
    }
    return [pscustomobject]@{
        Crit = @($all | Where-Object { $_.Status -eq 'crit' })
        Warn = @($all | Where-Object { $_.Status -eq 'warn' })
    }
}

function Get-SaudeVerdict {
    param([int]$Crit, [int]$Warn, [bool]$Partial = $false)
    if ($Crit -gt 0) {
        $t = if ($Crit -eq 1) { '1 problema crítico' } else { '{0} problemas críticos' -f $Crit }
        if ($Warn -gt 0) { $t += $(if ($Warn -eq 1) { ' e 1 ponto de atenção' } else { ' e {0} pontos de atenção' -f $Warn }) }
        return [pscustomobject]@{ Text = $t; Tone = 'crit' }
    }
    if ($Warn -gt 0) {
        return [pscustomobject]@{ Text = $(if ($Warn -eq 1) { '1 ponto de atenção' } else { '{0} pontos de atenção' -f $Warn }); Tone = 'warn' }
    }
    # sem administrador parte dos dados não foi lida: não afirmar "Tudo em ordem"
    if ($Partial) { return [pscustomobject]@{ Text = 'Nenhum problema encontrado (verificação parcial)'; Tone = 'primary' } }
    return [pscustomobject]@{ Text = 'Tudo em ordem'; Tone = 'ok' }
}

# Texto do laudo (.txt): identificação do equipamento, pontos encontrados e cada área,
# com [X] nas linhas críticas e [!] nas de atenção
function New-SaudeLaudoText {
    param($Report, $StatusText = $null, $Inventory = $null, [string]$Technician = '', [string]$Version = '')
    $sb = New-Object System.Text.StringBuilder
    $line = '=' * 69
    $when = [datetime]$Report.CheckedAt
    $idn = $Report.Identity
    $val = { param($o, [string]$k) if ($o -and $o.PSObject.Properties[$k]) { ([string]$o.$k).Trim() } else { '' } }
    $dash = { param([string]$s) if ([string]::IsNullOrWhiteSpace($s)) { '-' } else { $s } }
    $maker = ((& $val $idn 'Fabricante') + ' ' + (& $val $idn 'Modelo')).Trim()
    $asset = ''; $local = ''
    if ($Inventory) { $asset = ([string]$Inventory['Patrimonio']).Trim(); $local = ([string]$Inventory['Local']).Trim() }
    if (-not $asset) { $asset = & $val $idn 'AssetTag' }
    $dom = & $val $idn 'Dominio'
    $iss = Get-SaudeIssues -Report $Report
    $note = [string]$Report.PartialNote
    $verdict = Get-SaudeVerdict -Crit $iss.Crit.Count -Warn $iss.Warn.Count -Partial ([bool]$note)

    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine(' TI Suite - laudo de saúde do computador')
    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine((' {0,-16}: {1}' -f 'Computador', (& $dash ([string]$Report.Computer))))
    [void]$sb.AppendLine((' {0,-16}: {1}' -f 'Equipamento', (& $dash $maker)))
    [void]$sb.AppendLine((' {0,-16}: {1}' -f 'Número de série', (& $dash (& $val $idn 'Serie'))))
    [void]$sb.AppendLine((' {0,-16}: {1}' -f 'Patrimônio', (& $dash $asset)))
    if ($local) { [void]$sb.AppendLine((' {0,-16}: {1}' -f 'Local', $local)) }
    if ($dom) { [void]$sb.AppendLine((' {0,-16}: {1}' -f 'Domínio', $dom)) }
    [void]$sb.AppendLine((' {0,-16}: {1}' -f 'Verificado em', $when.ToString('dd/MM/yyyy HH:mm')))
    [void]$sb.AppendLine((' {0,-16}: {1}' -f 'Técnico', (& $dash $Technician)))
    [void]$sb.AppendLine((' {0,-16}: {1}' -f 'Resultado', $verdict.Text))
    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(' Pontos encontrados ([X] crítico, [!] atenção)')
    if ($iss.Crit.Count + $iss.Warn.Count -eq 0) { [void]$sb.AppendLine('   Nenhum problema encontrado.') }
    foreach ($i in $iss.Crit) { [void]$sb.AppendLine(('   [X] {0}' -f $i.Text)) }
    foreach ($i in $iss.Warn) { [void]$sb.AppendLine(('   [!] {0}' -f $i.Text)) }
    if ($note) { [void]$sb.AppendLine(('   (i) {0}' -f $note)) }
    foreach ($id in $global:Saude.Order) {
        $sec = $Report.Sections[$id]
        if (-not $sec) { continue }
        $st = [string]$sec.Status
        if ($StatusText -and $StatusText[$id]) { $st = [string]$StatusText[$id] }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine((' {0} ({1})' -f $global:Saude.Meta[$id].Title, $st))
        foreach ($r in @($sec.Rows)) {
            $mark = if ($r.Tone -eq 'crit') { '[X]' } elseif ($r.Tone -eq 'warn') { '[!]' } else { '   ' }
            [void]$sb.AppendLine(('   {0} {1,-22} {2}' -f $mark, $r.Label, $r.Value))
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($line)
    [void]$sb.AppendLine((' Gerado pelo TI Suite v{0}' -f $Version))
    return $sb.ToString()
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
    $glyph = switch ($Status) { 'crit' { 'Error' } 'warn' { 'Warning' } 'ok' { 'Completed' } default { 'Info' } }
    $icon = New-TIGlyph -Icon $glyph -Size 10.5 -Color (Get-TIToneColor $Status)
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
        $tip = if ($Section.Domain) { 'Pede ao Windows para sincronizar com o controlador de domínio (precisa de administrador)' }
               else { 'Sincroniza o horário do Windows (precisa de administrador)' }
        $btn = New-TIButton -Text 'Acertar relógio' -Style 'Outline' -Icon 'Sync' -Width 150 -Height 36 -Tip $tip
        $btn.Add_Click({ Invoke-SaudeClockSync })
        $bar.Controls.Add($btn)
        if ($Section.PSObject.Properties['BrazilZone'] -and -not $Section.BrazilZone) {
            $btz = New-TIButton -Text 'Usar fuso de Brasília' -Style 'Outline' -Icon 'TimeLanguage' -Width 150 -Height 36 -Tip 'Troca o fuso horário para (UTC-03:00) Brasília'
            $btz.Add_Click({ Invoke-SaudeSetTimeZone })
            $bar.Controls.Add($btz)
        }
    }
    $b.ResumeLayout()
    if ($Section.NotApplicable) { Set-TICardStatus $b 'none' 'Não se aplica' }
    elseif ($Section.Status -eq 'ok' -and $Section.Partial) { Set-TICardStatus $b 'info' 'Parcial' }
    else { Set-TICardStatus $b $Section.Status }
    # o laudo repete exatamente o selo da tela
    $global:Saude.StatusText[$Id] = $(if ($b.PSObject.Properties['Pill'] -and $b.Pill) { [string]$b.Pill.Text } else { [string]$Section.Status })
}

function Update-SaudeUI {
    param($Report)
    if (-not $Report) { return }
    $global:Saude.Report = $Report
    foreach ($id in $global:Saude.Order) {
        $sec = $Report.Sections[$id]
        if ($sec) { Fill-SaudeCard -Id $id -Section $sec }
    }
    $iss = Get-SaudeIssues -Report $Report
    $note = [string]$Report.PartialNote
    $verdict = Get-SaudeVerdict -Crit $iss.Crit.Count -Warn $iss.Warn.Count -Partial ([bool]$note)
    $v = $global:Saude.Verdict
    $v.Text = $verdict.Text
    $v.ForeColor = Get-TIToneColor $verdict.Tone
    $when = [datetime]$Report.CheckedAt
    $global:Saude.VerdictSub.Text = ('Verificado em {0} às {1}.' -f $when.ToString('dd/MM/yyyy'), $when.ToString('HH:mm'))

    # O card cresce sozinho para caber as linhas (New-TICard: -Height é o mínimo)
    $b0 = $global:Saude.SummaryBody
    $b0.SuspendLayout()
    foreach ($c in @($b0.Controls | Where-Object { $_.Name -eq 'tiissue' })) { $b0.Controls.Remove($c); $c.Dispose() }
    if ($iss.Crit.Count + $iss.Warn.Count -eq 0) {
        Add-SaudeIssueLine -Body $b0 -Status 'ok' -Text 'Nenhum problema encontrado nas verificações.'
    } else {
        foreach ($i in $iss.Crit) { Add-SaudeIssueLine -Body $b0 -Status 'crit' -Text $i.Text }
        foreach ($i in $iss.Warn) { Add-SaudeIssueLine -Body $b0 -Status 'warn' -Text $i.Text }
    }
    if ($note) { Add-SaudeIssueLine -Body $b0 -Status 'none' -Text $note }
    $b0.ResumeLayout()
    $lvl = if ($verdict.Tone -eq 'crit' -or $verdict.Tone -eq 'warn') { 'Warn' } else { 'Success' }
    Write-TILog -Level $lvl -Message ('Saúde do PC: {0}.' -f $verdict.Text.ToLower())
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

function Show-SaudeNeedsAdmin {
    param([string]$Action)
    Show-TIToast -Text ('{0} precisa do TI Suite aberto como administrador.' -f $Action) -Type 'Warn'
    Write-TILog -Level 'Warn' -Message ('{0}: precisa de administrador. Clique no selo da barra lateral para reabrir como administrador.' -f $Action)
}

# Resultado de "Acertar relógio" e "Usar fuso de Brasília": atualiza o card e dá o aviso certo
function Complete-SaudeClockAction {
    param($Result)
    $res = @($Result | Where-Object { $_ -and $_.PSObject.Properties['Section'] }) | Select-Object -First 1
    if (-not $res) { return }
    try { [System.TimeZoneInfo]::ClearCachedData() } catch { }
    if ($res.Section -and $global:Saude.Report) {
        $global:Saude.Report.Sections['clock'] = $res.Section
        Update-SaudeUI -Report $global:Saude.Report
    }
    if ($res.Toast) {
        $type = switch ([string]$res.Result) {
            'ok'       { 'Success' }
            'synced'   { 'Success' }
            'adjusted' { 'Success' }
            'failed'   { 'Error' }
            default    { 'Warn' }
        }
        Show-TIToast -Text $res.Toast -Type $type
    }
}

function Invoke-SaudeClockSync {
    if ($global:TI.Busy) { return }
    # sem administrador, avisa antes da confirmação (e não depois de "Acertar agora")
    if (-not $global:TI.Elevated) { Show-SaudeNeedsAdmin -Action 'Acertar o relógio'; return }
    $dom = ''
    $rep = $global:Saude.Report
    if ($rep -and $rep.Sections['clock'] -and $rep.Sections['clock'].PSObject.Properties['Domain']) { $dom = [string]$rep.Sections['clock'].Domain }
    $msg = if ($dom) {
        ("Este computador está no domínio {0}. O TI Suite pede ao Windows para sincronizar com o controlador de domínio " +
         "e não ajusta pela internet: o login na rede segue a hora do servidor.`n`nO fuso horário não é alterado.") -f $dom
    } else {
        ("O TI Suite pede ao Windows para sincronizar o horário. Se o relógio continuar errado " +
         "e duas fontes da internet concordarem entre si, ajusta pela diferença medida.`n`nO fuso horário não é alterado.")
    }
    $ok = Show-TIConfirm -Title 'Acertar relógio' -Icon 'Recent' -Style 'Primary' -Message $msg -ConfirmText 'Acertar agora'
    if (-not $ok) { return }
    [void](Invoke-TIAsync -Name 'Acerto do relógio' -RequiresAdmin -Quiet -Script {
        Sync-TIClock
    } -OnComplete {
        param($r)
        Complete-SaudeClockAction -Result $r
    })
}

function Invoke-SaudeSetTimeZone {
    if ($global:TI.Busy) { return }
    $ok = Show-TIConfirm -Title 'Usar fuso de Brasília' -Icon 'Recent' -Style 'Primary' `
            -Message ("Troca o fuso horário deste computador para (UTC-03:00) Brasília.`n`n" +
                      "Se a escola fica em outro fuso do Brasil (Amazonas, Acre, Mato Grosso...), ajuste em Configurações > Hora e idioma.") `
            -ConfirmText 'Trocar o fuso'
    if (-not $ok) { return }
    [void](Invoke-TIAsync -Name 'Troca do fuso horário' -Audit -Quiet -Script {
        Set-TIBrasiliaTimeZone
    } -OnComplete {
        param($r)
        Complete-SaudeClockAction -Result $r
    })
}

# Modo portátil: pasta "laudos" ao lado do app (no pendrive); instalado: Documentos
function Get-SaudeLaudoDir {
    if ($global:TIPortable -and $global:TIRoot) {
        $d = Join-Path $global:TIRoot 'laudos'
        try {
            if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null }
            return $d
        } catch { }
    }
    return [Environment]::GetFolderPath('MyDocuments')
}

# Linha do inventário deste PC (patrimônio e local), se já registrado
function Get-SaudeInventoryRow {
    param($Identity, [string]$Computer)
    if (-not (Get-Command Read-TIInventory -ErrorAction SilentlyContinue)) { return $null }
    try {
        $rows = @(Read-TIInventory)
        $serie = ''
        if ($Identity -and $Identity.PSObject.Properties['Serie']) { $serie = [string]$Identity.Serie }
        $idx = Find-TIInventoryIndex -Rows $rows -Serie $serie -Computador $Computer
        if ($idx -ge 0) { return $rows[$idx] }
    } catch { }
    return $null
}

function Export-SaudeLaudo {
    $rep = $global:Saude.Report
    if (-not $rep) { Show-TIToast -Text 'Rode a verificação antes de salvar o laudo.' -Type 'Warn'; return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = 'Salvar laudo de saúde'
    $dlg.Filter = 'Texto (*.txt)|*.txt|Todos os arquivos (*.*)|*.*'
    $dlg.FileName = ('Laudo-saude-{0}-{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm'))
    $dir = Get-SaudeLaudoDir
    if ($dir) { $dlg.InitialDirectory = $dir }
    try {
        if ($dlg.ShowDialog($global:Form) -ne 'OK') { return }
        $inv = Get-SaudeInventoryRow -Identity $rep.Identity -Computer ([string]$rep.Computer)
        $txt = New-SaudeLaudoText -Report $rep -StatusText $global:Saude.StatusText -Inventory $inv -Technician $env:USERNAME -Version $global:TI.Version
        [System.IO.File]::WriteAllText($dlg.FileName, $txt, (New-Object System.Text.UTF8Encoding($true)))
        Write-TILog -Level 'Success' -Message ('Laudo salvo: {0}' -f $dlg.FileName)
        Show-TIToast -Text ('Laudo salvo: {0}' -f (Split-Path -Leaf $dlg.FileName)) -Type 'Success'
    } catch {
        Write-TILog -Level 'Error' -Message ('Falha ao salvar o laudo: {0}' -f $_.Exception.Message)
        Show-TIToast -Text 'Não foi possível salvar o laudo.' -Type 'Error'
    } finally {
        $dlg.Dispose()
    }
}

$wsSaude = @{
    Id       = 'saude'
    Title    = 'Saúde do PC'
    Sub      = 'Windows, discos, estabilidade, proteção, relógio e bateria em uma verificação'
    Icon     = 'Health'
    Keywords = 'saude disco smart ssd hd bateria ativacao licenca windows update atualizacao antivirus defender firewall relogio hora data laudo temperatura fuso reinicio desgaste espaco bitlocker tela azul desligamento'

    OnActivate = { if (-not $global:Saude.Report) { Invoke-SaudeCheck } }
    Refresh    = { Invoke-SaudeCheck }

    Actions = {
        param($Bar)
        $b1 = New-TIButton -Text 'Verificar agora' -Style 'Outline' -Width 146 -Height 34 -Icon 'Refresh' -Tip 'Rodar todas as verificações de novo (Ctrl+R)'
        $b1.Add_Click({ Invoke-SaudeCheck })
        $Bar.Controls.Add($b1)
        $b2 = New-TIButton -Text 'Salvar laudo' -Style 'Ghost' -Width 130 -Height 34 -Icon 'Report' -Tip 'Salva o resultado em .txt para anexar ao chamado'
        $b2.Add_Click({ Export-SaudeLaudo })
        $Bar.Controls.Add($b2)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel

        # --- Resumo (os botões ficam só na barra do cabeçalho) ------------------
        $b0 = New-TICard -Parent $flow -Title 'Resumo' -Desc 'O que pede atenção neste computador' -Icon 'Health' -Height 150 -Stretch
        $v = New-TILabel -Text 'Ainda não verificado' -Size 12 -Bold -Color $global:Pal.TextDim
        $v.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
        $b0.Controls.Add($v)
        $global:Saude.Verdict = $v
        $global:Saude.VerdictSub = New-TIHint -Parent $b0 -Text 'A verificação examina Windows, discos, estabilidade, proteção, relógio e bateria. Leva de 10 a 30 segundos.' -BottomGap 8
        $global:Saude.SummaryBody = $b0

        # --- Um card por verificação (duas colunas quando a janela permite) ------
        foreach ($key in $global:Saude.Order) {
            $m = $global:Saude.Meta[$key]
            $b = New-TICard -Parent $flow -Title $m.Title -Desc $m.Desc -Icon $m.Icon -Height 230 -Half -WithStatus
            $null = New-TIHint -Parent $b -Text 'Aguardando a verificação.'
            $global:Saude.Cards[$key] = $b
        }
    }
}

Register-TIWorkspace @wsSaude
