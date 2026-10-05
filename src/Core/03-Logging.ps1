# =====================================================================
# 03-LOGGING.ps1 - Console com níveis, filtro, arquivo da sessão e auditoria
#
#   - O console mostra as últimas 3000 entradas; tudo (inclusive os detalhes)
#     vai também para logs\console-AAAA-MM-DD-<PC>.txt, gravado em segundo
#     plano a cada 2 s. O console nunca recebe senhas; o arquivo também não.
#   - Linha nova não mexe na leitura: se o técnico rolou para cima ou
#     selecionou um trecho, a vista e a seleção ficam onde estavam.
#   - Auditoria (logs\audit.csv) não se perde quando o arquivo está aberto no
#     Excel: a linha fica pendente e é gravada assim que der (ou ao fechar).
#   - No WinPE (modo recuperação) não há Explorer: o botão Logs abre o console
#     de hoje no Bloco de notas e Exportar grava direto em logs\ do pendrive.
# =====================================================================

$global:LogEntries = New-Object System.Collections.ArrayList
$global:LogBox = $null
$global:LogCounter = $null
$global:LogActions = $null
$global:LogFilter = @{ Debug = $false; Info = $true; Success = $true; Warn = $true; Error = $true }
$global:LogErrorCount = 0
# Entradas por nível: o contador "N eventos" conta só o que está visível
$global:LogLevelCount = @{ Debug = 0; Info = 0; Success = 0; Warn = 0; Error = 0 }

# Limite do console: passando de LogMax, saem as LogTrimBatch mais antigas de uma vez
$script:LogMax = 3000
$script:LogTrimBatch = 250
$script:LogTrimmed = $false
$script:LogTrimNotePending = $false
$script:LogScrollPending = $false

$script:LogLevelColor = @{
    Debug   = $global:Pal.TextDim
    Info    = $global:Pal.Primary
    Success = $global:Pal.Success
    Warn    = $global:Pal.Warning
    Error   = $global:Pal.Danger
}
# Etiquetas em português nas linhas do console e na exportação
$script:LogLevelTag = @{
    Debug   = 'DETALHE'
    Info    = 'INFO'
    Success = 'OK'
    Warn    = 'AVISO'
    Error   = 'ERRO'
}
$script:LogMessageColor = [System.Drawing.Color]::FromArgb(203, 213, 225)

# Chips de filtro da barra do console (ligado = preenchido; desligado = contorno)
$script:LogChips = @(
    @{ K = 'Info';    T = 'Info';     On = 'Mensagens informativas visíveis. Clique para ocultar.'; Off = 'Mensagens informativas ocultas. Clique para mostrar.' },
    @{ K = 'Success'; T = 'OK';       On = 'Mensagens de sucesso visíveis. Clique para ocultar.';   Off = 'Mensagens de sucesso ocultas. Clique para mostrar.' },
    @{ K = 'Warn';    T = 'Aviso';    On = 'Avisos visíveis. Clique para ocultar.';                 Off = 'Avisos ocultos. Clique para mostrar.' },
    @{ K = 'Error';   T = 'Erro';     On = 'Erros visíveis. Clique para ocultar.';                  Off = 'Erros ocultos. Clique para mostrar.' },
    @{ K = 'Debug';   T = 'Detalhes'; On = 'Detalhes técnicos visíveis (cada item analisado, cada área aberta). Clique para ocultar.'
                                      Off = 'Detalhes técnicos ocultos (cada item analisado, cada área aberta). Clique para mostrar.' }
)

function Format-TILogLine {
    param($Entry)
    return ('[{0}] {1,-7} {2}' -f $Entry.Time.ToString('HH:mm:ss'), $script:LogLevelTag[$Entry.Level], $Entry.Text)
}

# Modo de abertura em texto (cabeçalho do console salvo, exportação e Configurações)
function Get-TIModeText {
    if ($global:TIWinPE) { return 'Modo recuperação (WinPE)' }
    if ($global:TIRecovery) { return 'Modo recuperação' }
    if ($global:TIPortable) { return 'Modo portátil (USB)' }
    return 'Modo instalado'
}

# Quem roda o app, para o console salvo e a auditoria (no WinPE é sempre SYSTEM)
function Get-TILogOperator {
    $u = [string]$env:USERNAME
    if ($global:TIWinPE) { return ('{0} (WinPE)' -f $(if ($u) { $u } else { 'SYSTEM' })) }
    return $u
}

# Pasta dos logs (a mesma do exceptions.log e do audit.csv)
function Get-TILogDir {
    if (-not $global:TILogPath) { return $null }
    return (Split-Path -Parent $global:TILogPath)
}

# ---------------------------------------------------------------------
# Caixa do console (RichTextBox)
# ---------------------------------------------------------------------

# Texto da mensagem como vai para a caixa: quebras de linha uniformes
function Get-TILogBoxText {
    param($Entry)
    return ([string]$Entry.Text -replace "`r`n?", "`n")
}

# Quantas linhas a entrada ocupa na caixa (mensagens podem ter várias linhas)
function Get-TILogEntryLineCount {
    param($Entry)
    $t = Get-TILogBoxText $Entry
    return (1 + $t.Length - $t.Replace("`n", '').Length)
}

function Add-TILogEntryToBox {
    param($Entry)
    $box = $global:LogBox
    if (-not $box) { return }
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor = $script:LogLevelColor.Debug
    $box.AppendText(('[{0}] ' -f $Entry.Time.ToString('HH:mm:ss')))

    $box.SelectionColor = $script:LogLevelColor[$Entry.Level]
    $box.AppendText(('{0,-7} ' -f $script:LogLevelTag[$Entry.Level]))

    $box.SelectionColor = switch ($Entry.Level) {
        'Error'  { $script:LogLevelColor.Error }
        'Warn'   { $script:LogLevelColor.Warn }
        'Debug'  { $global:Pal.TextMuted }
        default  { $script:LogMessageColor }
    }
    $box.AppendText((Get-TILogBoxText $Entry) + "`n")
}

# Liga/desliga a pintura da caixa (WM_SETREDRAW): sem piscar nas mudanças em lote
function Set-TILogRedraw {
    param([bool]$On)
    $box = $global:LogBox
    if (-not $box -or -not $box.IsHandleCreated) { return }
    try {
        [void][TISuite.Native]::SendMessage($box.Handle, 0x000B, [IntPtr]$(if ($On) { 1 } else { 0 }), [IntPtr]::Zero)
        if ($On) {
            $box.Invalidate()
            # Barras de rolagem (área não cliente) também: WM_NCPAINT
            [void][TISuite.Native]::SendMessage($box.Handle, 0x0085, [IntPtr]1, [IntPtr]::Zero)
        }
    } catch { }
}

# Posição de rolagem em pixels (EM_GETSCROLLPOS / EM_SETSCROLLPOS)
function Get-TILogScrollPos {
    param($Box)
    $p = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(8)
    try {
        [System.Runtime.InteropServices.Marshal]::WriteInt64($p, 0)
        [void][TISuite.Native]::SendMessage($Box.Handle, 0x04DD, [IntPtr]::Zero, $p)
        $x = [System.Runtime.InteropServices.Marshal]::ReadInt32($p, 0)
        $y = [System.Runtime.InteropServices.Marshal]::ReadInt32($p, 4)
    } finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($p)
    }
    return @{ X = $x; Y = $y }
}

function Set-TILogScrollPos {
    param($Box, [int]$X, [int]$Y)
    $p = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(8)
    try {
        [System.Runtime.InteropServices.Marshal]::WriteInt32($p, 0, $X)
        [System.Runtime.InteropServices.Marshal]::WriteInt32($p, 4, [Math]::Max(0, $Y))
        [void][TISuite.Native]::SendMessage($Box.Handle, 0x04DE, [IntPtr]::Zero, $p)
    } finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($p)
    }
}

# Onde o técnico está lendo. $null = acompanhando o fim sem seleção (a vista
# segue as linhas novas); senão, a seleção e a rolagem a restaurar.
function Get-TILogView {
    $box = $global:LogBox
    if (-not $box -or -not $box.IsHandleCreated -or -not $box.Visible) { return $null }
    try {
        $selLen = $box.SelectionLength
        if ($script:LogScrollPending -and $selLen -eq 0) { return $null }
        $last = $box.GetLineFromCharIndex($box.TextLength)
        $pt = New-Object System.Drawing.Point(2, [Math]::Max(0, ($box.ClientSize.Height - 4)))
        $bottom = $box.GetLineFromCharIndex($box.GetCharIndexFromPosition($pt))
        if ($bottom -ge ($last - 1) -and $selLen -eq 0) { return $null }
        return @{ Start = $box.SelectionStart; Length = $selLen; Scroll = (Get-TILogScrollPos $box) }
    } catch {
        return $null
    }
}

function Restore-TILogView {
    param($View, $Cut)
    $box = $global:LogBox
    $start = $View.Start - $Cut.Chars
    $len = $View.Length
    if ($start -lt 0) { $len = [Math]::Max(0, $len + $start); $start = 0 }
    $start = [Math]::Min($start, $box.TextLength)
    $len = [Math]::Min($len, ($box.TextLength - $start))
    $box.Select($start, $len)
    Set-TILogScrollPos $box $View.Scroll.X ($View.Scroll.Y - $Cut.Pixels)
}

# Rola até o fim uma vez só, depois da rajada de linhas (ScrollToCaret custa
# caro com o console cheio)
function Request-TILogScroll {
    $script:LogScrollPending = $true
    if (-not $global:LogScrollTimer) {
        $t = New-Object System.Windows.Forms.Timer
        $t.Interval = 40
        $t.Add_Tick({ param($s, $e) $s.Stop(); Complete-TILogScroll })
        $global:LogScrollTimer = $t
    }
    if (-not $global:LogScrollTimer.Enabled) { $global:LogScrollTimer.Start() }
}

function Complete-TILogScroll {
    $script:LogScrollPending = $false
    $box = $global:LogBox
    if (-not $box -or -not $box.IsHandleCreated) { return }
    # O técnico começou a selecionar nesse meio tempo: não mexe
    if ($box.SelectionLength -gt 0) { return }
    try {
        $box.Select($box.TextLength, 0)
        $box.ScrollToCaret()
    } catch { }
}

# Tira as entradas mais antigas da lista e da caixa quando passa do limite.
# Devolve o que saiu da caixa (caracteres e pixels) para corrigir a vista.
function Remove-TILogOldest {
    $cut = @{ Chars = 0; Pixels = 0; Redraw = $false }
    $n = $global:LogEntries.Count - ($script:LogMax - $script:LogTrimBatch)
    if ($n -le 0) { return $cut }
    $n = [Math]::Min($n, $global:LogEntries.Count)
    $lines = 0
    for ($i = 0; $i -lt $n; $i++) {
        $e = $global:LogEntries[$i]
        $global:LogLevelCount[$e.Level] = [Math]::Max(0, ([int]$global:LogLevelCount[$e.Level] - 1))
        if ($global:LogFilter[$e.Level]) { $lines += (Get-TILogEntryLineCount $e) }
    }
    $global:LogEntries.RemoveRange(0, $n)
    $global:LogErrorCount = [int]$global:LogLevelCount.Error
    if (-not $script:LogTrimmed) { $script:LogTrimmed = $true; $script:LogTrimNotePending = $true }

    $box = $global:LogBox
    if ($box -and $lines -gt 0) {
        try {
            $idx = $box.GetFirstCharIndexFromLine($lines)
            if ($idx -lt 0) { $idx = $box.TextLength }
            if ($box.IsHandleCreated) {
                $cut.Pixels = [Math]::Max(0, ($box.GetPositionFromCharIndex($idx).Y - $box.GetPositionFromCharIndex(0).Y))
            }
            $before = $box.TextLength
            # Caixa somente leitura não aceita apagar (WM_CLEAR): libera só neste instante
            $ro = $box.ReadOnly
            $box.ReadOnly = $false
            try {
                $box.Select(0, $idx)
                $box.SelectedText = ''
            } finally {
                $box.ReadOnly = $ro
            }
            $cut.Chars = $idx
            if ($box.TextLength -gt ($before - $idx)) { $cut.Redraw = $true }
        } catch {
            $cut.Redraw = $true
        }
    }
    return $cut
}

# Linha nova na caixa sem tirar o técnico de onde ele está lendo
function Add-TILogEntryToView {
    param($Entry)
    $trim = ($global:LogEntries.Count -gt $script:LogMax)
    $box = $global:LogBox
    if (-not $box) {
        if ($trim) { [void](Remove-TILogOldest) }
        return
    }
    $show = [bool]$global:LogFilter[$Entry.Level]
    if (-not $show -and -not $trim) { return }

    $view = Get-TILogView
    $cut = @{ Chars = 0; Pixels = 0; Redraw = $false }
    $frozen = ($null -ne $view -or $trim)
    if ($frozen) { Set-TILogRedraw $false }
    try {
        if ($show) { Add-TILogEntryToBox $Entry }
        if ($trim) { $cut = Remove-TILogOldest }
        if ($view -and -not $cut.Redraw) { Restore-TILogView $view $cut }
    } finally {
        if ($frozen) { Set-TILogRedraw $true }
    }
    if ($cut.Redraw) { Redraw-TILog; return }
    if (-not $view) {
        # Depois de cortar o início, rola já (senão a vista pularia por um instante)
        if ($trim) { Complete-TILogScroll } else { Request-TILogScroll }
    }
}

# ---------------------------------------------------------------------
# Contador "N eventos" (só o que está visível; "N de M" quando há filtro)
# ---------------------------------------------------------------------
function Update-TILogCounts {
    $c = @{ Debug = 0; Info = 0; Success = 0; Warn = 0; Error = 0 }
    foreach ($e in $global:LogEntries) { $c[$e.Level] = [int]$c[$e.Level] + 1 }
    $global:LogLevelCount = $c
    $global:LogErrorCount = [int]$c.Error
}

function Update-TILogCounter {
    $lbl = $global:LogCounter
    if (-not $lbl) { return }
    $shown = 0
    $total = 0
    foreach ($k in @('Info', 'Success', 'Warn', 'Error', 'Debug')) {
        $n = [int]$global:LogLevelCount[$k]
        if ($global:LogFilter[$k]) { $shown += $n }
        # Detalhes desligados (o padrão) não entram no total
        if ($k -ne 'Debug' -or $global:LogFilter.Debug) { $total += $n }
    }
    $errs = [int]$global:LogErrorCount
    $ev = if ($total -eq 1) { 'evento' } else { 'eventos' }
    $txt = if ($shown -ne $total) { '{0} de {1} {2}' -f $shown, $total, $ev } else { '{0} {1}' -f $total, $ev }
    if ($errs -gt 0) { $txt += (', {0} com erro' -f $errs) }
    if ($lbl.Text -ne $txt) { $lbl.Text = $txt }
    $lbl.ForeColor = if ($errs -gt 0) { $global:Pal.Danger } else { $global:Pal.TextDim }
}

# O contador ocupa o espaço entre os chips e os botões (corta com reticências)
function Update-TILogCounterWidth {
    $c = $global:LogCounter
    $a = $global:LogActions
    if (-not $c -or -not $a) { return }
    $c.Width = [Math]::Max(24, ($a.Left - $c.Left - 10))
}

# ---------------------------------------------------------------------
# Registro
# ---------------------------------------------------------------------
function Write-TILog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Debug','Info','Success','Warn','Error')][string]$Level = 'Info'
    )
    $entry = [pscustomobject]@{ Time = Get-Date; Level = $Level; Text = $Message }
    [void]$global:LogEntries.Add($entry)
    $global:LogLevelCount[$Level] = [int]$global:LogLevelCount[$Level] + 1
    if ($Level -eq 'Error') { $global:LogErrorCount++ }
    Add-TILogFileLine $entry
    Add-TILogEntryToView $entry
    Update-TILogCounter
    if ($script:LogTrimNotePending) {
        $script:LogTrimNotePending = $false
        $file = Get-TILogFilePath
        $note = if ($file -and -not $global:TILogFile.Failed) { 'as mais antigas continuam em {0}.' -f $file } else { 'as mais antigas saíram da tela.' }
        Write-TILog -Level 'Info' -Message ('O console mostra as últimas {0} linhas; {1}' -f $script:LogMax, $note)
    }
}

function Reset-TILog {
    $global:LogEntries.Clear()
    Update-TILogCounts
    if ($global:LogBox) { $global:LogBox.Clear() }
    Update-TILogCounter
    # O arquivo da sessão em logs\ continua com tudo o que saiu da tela
    $msg = 'Console limpo. Sistema pronto.'
    if ($global:TI.Busy) {
        $name = if ($global:TIAsync -and $global:TIAsync.Name) { [string]$global:TIAsync.Name } else { '' }
        $msg = if ($name) { 'Console limpo. Tarefa em andamento: {0}.' -f $name } else { 'Console limpo. Há uma tarefa em andamento.' }
    }
    Write-TILog -Level 'Info' -Message $msg
}

# ---------------------------------------------------------------------
# Redesenho completo (troca de filtro): RTF montado de uma vez, com a pintura
# suspensa. Se o RTF falhar, cai no caminho linha a linha.
# ---------------------------------------------------------------------
$script:LogRtfEscape = [System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    $c = [int][char]$m.Value
    if ($c -gt 32767) { $c -= 65536 }
    '\u' + $c + '?'
}

function ConvertTo-TIRtfText {
    param([string]$Text)
    $t = $Text.Replace('\', '\\').Replace('{', '\{').Replace('}', '\}')
    $t = ($t -replace "`r`n?", "`n").Replace("`n", '\par ').Replace("`t", '\tab ')
    if ($t -match '[^\x00-\x7F]') { $t = [regex]::Replace($t, '[^\x00-\x7F]', $script:LogRtfEscape) }
    return $t
}

function Get-TILogRtf {
    param($Box)
    # Cores: 1 hora/etiqueta de detalhe, 2-5 níveis, 6 mensagem, 7 mensagem de detalhe
    $colors = @($script:LogLevelColor.Debug, $script:LogLevelColor.Info, $script:LogLevelColor.Success,
                $script:LogLevelColor.Warn, $script:LogLevelColor.Error, $script:LogMessageColor, $global:Pal.TextMuted)
    $tagColor = @{ Debug = 1; Info = 2; Success = 3; Warn = 4; Error = 5 }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('{\rtf1\ansi\deff0{\fonttbl{\f0\fmodern\fcharset0 ').Append($Box.Font.Name).Append(';}}{\colortbl ;')
    foreach ($c in $colors) { [void]$sb.Append(('\red{0}\green{1}\blue{2};' -f $c.R, $c.G, $c.B)) }
    [void]$sb.Append('}\f0\fs').Append([int][Math]::Round($Box.Font.SizeInPoints * 2)).Append(' ')
    foreach ($e in $global:LogEntries) {
        if (-not $global:LogFilter[$e.Level]) { continue }
        $tc = $tagColor[$e.Level]
        $mc = switch ($e.Level) { 'Error' { 5 } 'Warn' { 4 } 'Debug' { 7 } default { 6 } }
        [void]$sb.Append('\cf1 [').Append($e.Time.ToString('HH:mm:ss')).Append('] \cf').Append($tc).Append(' ')
        [void]$sb.Append(('{0,-7} ' -f $script:LogLevelTag[$e.Level])).Append('\cf').Append($mc).Append(' ')
        [void]$sb.Append((ConvertTo-TIRtfText ([string]$e.Text))).Append("\par`r`n")
    }
    [void]$sb.Append('}')
    return $sb.ToString()
}

function Redraw-TILog {
    Update-TILogCounts
    $box = $global:LogBox
    if ($box) {
        $lines = 0
        foreach ($e in $global:LogEntries) { if ($global:LogFilter[$e.Level]) { $lines += (Get-TILogEntryLineCount $e) } }
        Set-TILogRedraw $false
        try {
            $viaRtf = $false
            if ($lines -gt 0) {
                try { $box.Rtf = Get-TILogRtf $box; $viaRtf = $true } catch { $viaRtf = $false }
            }
            if (-not $viaRtf) {
                $box.Clear()
                foreach ($e in $global:LogEntries) { if ($global:LogFilter[$e.Level]) { Add-TILogEntryToBox $e } }
            } elseif ($box.GetLineFromCharIndex($box.TextLength) -lt $lines) {
                # O RichEdit pode absorver o último \par: a próxima linha não pode colar nesta
                $box.Select($box.TextLength, 0)
                $box.AppendText("`n")
            }
            $box.Select($box.TextLength, 0)
            $script:LogScrollPending = $false
            $box.ScrollToCaret()
        } finally {
            Set-TILogRedraw $true
        }
        # Garantia: se a rolagem com a pintura suspensa não pegou, acerta logo depois
        Request-TILogScroll
    }
    Update-TILogCounter
}

# ---------------------------------------------------------------------
# Console salvo em arquivo: logs\console-AAAA-MM-DD-<PC>.txt (anexa; um por
# dia e por computador). Gravação assíncrona (FileStream.WriteAsync) a cada
# 2 s; no fechamento do app, síncrona.
# ---------------------------------------------------------------------
$global:TILogFile = @{
    Buffer  = New-Object System.Text.StringBuilder
    Path    = $null
    Stream  = $null
    Task    = $null
    Timer   = $null
    Started = $false
    Failed  = $false
    Closed  = $false
    Hooked  = $false
}

function Get-TILogFilePath {
    $dir = Get-TILogDir
    if (-not $dir) { return $null }
    return (Join-Path $dir ('console-{0}-{1}.txt' -f (Get-Date -Format 'yyyy-MM-dd'), $env:COMPUTERNAME))
}

function Add-TILogFileLine {
    param($Entry)
    $lf = $global:TILogFile
    if ($lf.Failed -or $lf.Closed) { return }
    if (-not $lf.Started) {
        $lf.Started = $true
        $sep = '=' * 69
        [void]$lf.Buffer.AppendLine($sep)
        [void]$lf.Buffer.AppendLine((' Sessão iniciada em {0}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss')))
        [void]$lf.Buffer.AppendLine((' Computador: {0} | Operador: {1} | TI Suite v{2}' -f $env:COMPUTERNAME, (Get-TILogOperator), $global:TI.Version))
        if ($global:TIRecovery) { [void]$lf.Buffer.AppendLine((' {0}' -f (Get-TIModeText))) }
        [void]$lf.Buffer.AppendLine($sep)
        Start-TILogFileTimer
    }
    [void]$lf.Buffer.AppendLine((Format-TILogLine $Entry))
}

function Start-TILogFileTimer {
    $lf = $global:TILogFile
    if ($lf.Timer) { return }
    try {
        $t = New-Object System.Windows.Forms.Timer
        $t.Interval = 2000
        $t.Add_Tick({ Sync-TILogFile })
        $t.Start()
        $lf.Timer = $t
    } catch { }
}

# Fechar o app grava o que falta (console e auditoria pendente)
function Register-TILogShutdown {
    $lf = $global:TILogFile
    if ($lf.Hooked -or -not $global:Form) { return }
    $lf.Hooked = $true
    $global:Form.Add_FormClosed({ Close-TILogFile })
}

function Close-TILogStream {
    $lf = $global:TILogFile
    if ($lf.Task) { try { [void]$lf.Task.Wait(3000) } catch { }; $lf.Task = $null }
    if ($lf.Stream) { try { $lf.Stream.Dispose() } catch { }; $lf.Stream = $null }
}

function Set-TILogFileFailed {
    param([string]$Why)
    $lf = $global:TILogFile
    if ($lf.Failed) { return }
    $lf.Failed = $true
    [void]$lf.Buffer.Clear()
    Close-TILogStream
    $where = if ($lf.Path) { $lf.Path } else { Get-TILogFilePath }
    Write-TILog -Level 'Warn' -Message ('Não deu para salvar o console em {0} ({1}). Nesta sessão ele fica só na tela: use Exportar para guardar.' -f $where, $Why)
}

function Sync-TILogFile {
    param([switch]$Final)
    Register-TILogShutdown
    if (-not $Final -and $global:TIAuditPending.Count -gt 0 -and (Get-Date) -ge $script:TIAuditRetryAt) {
        $script:TIAuditRetryAt = (Get-Date).AddSeconds(15)
        [void](Save-TIAuditPending -Quiet)
    }

    $lf = $global:TILogFile
    if ($lf.Closed) { return }
    if ($lf.Failed) { [void]$lf.Buffer.Clear(); return }

    # Gravação anterior ainda em curso: espera a próxima rodada (no fechamento, até 3 s)
    if ($lf.Task) {
        if (-not $lf.Task.IsCompleted) {
            if (-not $Final) { return }
            try { [void]$lf.Task.Wait(3000) } catch { }
        }
        $done = $lf.Task
        $lf.Task = $null
        if ($done.IsFaulted) {
            $why = 'falha de gravação'
            try { $why = $done.Exception.GetBaseException().Message } catch { }
            Set-TILogFileFailed $why
            return
        }
    }
    if ($lf.Buffer.Length -eq 0) { return }

    try {
        $path = Get-TILogFilePath
        if (-not $path) { throw 'pasta de logs não definida' }
        # Virou o dia: passa para o arquivo novo
        if ($lf.Stream -and $lf.Path -ne $path) { Close-TILogStream }
        if (-not $lf.Stream) {
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            # Tamanho de buffer 1 = sem buffer interno: cada gravação vai direto ao disco
            $lf.Stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 1, [System.IO.FileOptions]::Asynchronous)
            $lf.Path = $path
        }
        $text = $lf.Buffer.ToString()
        [void]$lf.Buffer.Clear()
        # Sempre no fim: outro TI Suite (reaberto como administrador) pode ter escrito
        $pos = $lf.Stream.Seek(0, [System.IO.SeekOrigin]::End)
        if ($pos -eq 0) { $text = [string][char]0xFEFF + $text }
        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
        if ($Final) {
            $lf.Stream.Write($bytes, 0, $bytes.Length)
            $lf.Stream.Flush()
        } else {
            $lf.Task = $lf.Stream.WriteAsync($bytes, 0, $bytes.Length)
        }
    } catch {
        Set-TILogFileFailed $_.Exception.Message
    }
}

function Close-TILogFile {
    [void](Save-TIAuditPending -Final)
    $lf = $global:TILogFile
    if ($lf.Closed) { return }
    if ($lf.Started -and -not $lf.Failed) {
        [void]$lf.Buffer.AppendLine((' Sessão encerrada em {0}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss')))
        [void]$lf.Buffer.AppendLine('')
    }
    Sync-TILogFile -Final
    if ($lf.Timer) { try { $lf.Timer.Stop(); $lf.Timer.Dispose() } catch { }; $lf.Timer = $null }
    Close-TILogStream
    $lf.Closed = $true
}

# ---------------------------------------------------------------------
# Auditoria (logs\audit.csv)
# ---------------------------------------------------------------------
$global:TIAuditPending = New-Object System.Collections.ArrayList
$script:TIAuditWarned = $false
$script:TIAuditNoticeDue = $false
$script:TIAuditRetryAt = Get-Date

function Write-TIAudit {
    # Trilha de auditoria (CSV) das ações administrativas: quando, PC, operador, ação, resultado.
    # Nunca recebe senhas: só o nome da tarefa e um detalhe curto.
    # Com o audit.csv bloqueado (aberto no Excel, pendrive protegido), a linha fica
    # pendente e é gravada na próxima ação, a cada 15 s e ao fechar o app.
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$Result = 'OK',
        [string]$Detail = ''
    )
    $q = { param($t) '"' + ([string]$t -replace '"', '""') + '"' }
    $line = (@(
        (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME, (Get-TILogOperator), $Action, $Result, $Detail
    ) | ForEach-Object { & $q $_ }) -join ';'
    [void]$global:TIAuditPending.Add($line)
    [void](Save-TIAuditPending)
}

function Add-TIAuditLines {
    param([string]$Path, [string[]]$Lines)
    $sb = New-Object System.Text.StringBuilder
    if (-not (Test-Path -LiteralPath $Path)) {
        [void]$sb.Append('"data";"pc";"operador";"acao";"resultado";"detalhe"').Append("`r`n")
    }
    foreach ($l in $Lines) { [void]$sb.Append($l).Append("`r`n") }
    # UTF-8 com BOM no arquivo novo (o Excel reconhece os acentos); anexando, sem BOM
    [System.IO.File]::AppendAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
}

# Grava as linhas pendentes. Devolve $true quando não sobrou nada.
#   -Quiet  tentativa automática: não avisa de novo se falhar
#   -Final  fechamento do app: se o audit.csv seguir bloqueado, grava ao lado
#           em audit-pendente-AAAAMMDD-HHMMSS.csv
function Save-TIAuditPending {
    param([switch]$Quiet, [switch]$Final)
    $n = $global:TIAuditPending.Count
    if ($n -eq 0) { return $true }
    $dir = Get-TILogDir
    try {
        if (-not $dir) { throw 'pasta de logs não definida' }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-TIAuditLines -Path (Join-Path $dir 'audit.csv') -Lines @($global:TIAuditPending)
        $global:TIAuditPending.Clear()
        if ($script:TIAuditNoticeDue) {
            $script:TIAuditNoticeDue = $false
            Write-TILog -Level 'Success' -Message ('Auditoria em dia: {0} linha(s) pendente(s) gravada(s) no audit.csv.' -f $n)
        }
        return $true
    } catch {
        $why = $_.Exception.Message
    }

    if ($Final -and $dir) {
        $alt = Join-Path $dir ('audit-pendente-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        try {
            Add-TIAuditLines -Path $alt -Lines @($global:TIAuditPending)
            $global:TIAuditPending.Clear()
            Write-TILog -Level 'Warn' -Message ('O audit.csv continuou bloqueado: {0} linha(s) de auditoria foram gravadas em {1}. Junte ao audit.csv depois.' -f $n, $alt)
            return $true
        } catch { }
    }

    $script:TIAuditNoticeDue = $true
    if (-not $script:TIAuditWarned) {
        $script:TIAuditWarned = $true
        Write-TILog -Level 'Warn' -Message ('Auditoria não gravada: o audit.csv está aberto em outro programa (Excel?) ou o pendrive está protegido contra gravação ({0}). {1} linha(s) aguardando; o TI Suite tenta de novo sozinho e ao fechar.' -f $why, $n)
        Show-TIToast -Text 'Auditoria não gravada: feche o audit.csv no Excel (ou libere o pendrive). O TI Suite tenta de novo sozinho.' -Type 'Warn'
    } elseif (-not $Quiet) {
        Write-TILog -Level 'Warn' -Message ('Auditoria ainda pendente ({0} linha(s)): o audit.csv continua bloqueado.' -f $n)
    }
    return $false
}

# ---------------------------------------------------------------------
# Ações da barra do console
# ---------------------------------------------------------------------
function Copy-TILog {
    $box = $global:LogBox
    $what = 'Console copiado.'
    $text = ''
    if ($box -and $box.SelectionLength -gt 0) {
        $text = ($box.SelectedText -replace "`r`n|`r|`n", "`r`n")
        $what = 'Trecho copiado.'
    } else {
        $lines = New-Object System.Collections.ArrayList
        foreach ($e in $global:LogEntries) {
            if ($global:LogFilter[$e.Level]) { [void]$lines.Add((Format-TILogLine $e)) }
        }
        $text = $lines -join "`r`n"
    }
    if (-not $text) {
        Show-TIToast -Text 'Nada para copiar: não há linhas visíveis no console.' -Type 'Info'
        return
    }
    try {
        [System.Windows.Forms.Clipboard]::SetText($text)
        Show-TIToast -Text $what -Type 'Success'
    } catch {
        Show-TIToast -Text 'Não deu para usar a área de transferência. Tente de novo.' -Type 'Error'
    }
}

# Botão Logs (console) e Configurações. Fora do WinPE: Explorer na pasta de logs com
# o audit.csv (ou o console de hoje) selecionado. No WinPE não há Explorer: abre o
# console de hoje no Bloco de notas (o Arquivo > Abrir dele mostra os outros registros).
function Open-TILogFolder {
    $dir = Get-TILogDir
    if (-not $dir) {
        Show-TIToast -Text 'A pasta de logs não está definida.' -Type 'Warn'
        return
    }
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $audit = Join-Path $dir 'audit.csv'
        $session = Get-TILogFilePath
        if ($global:TIWinPE) {
            # Grava já o que está na fila: o Bloco de notas mostra o console até agora
            Sync-TILogFile -Final
            $pick = if ($session -and (Test-Path -LiteralPath $session)) { $session } elseif (Test-Path -LiteralPath $audit) { $audit } else { $null }
            if ($pick) {
                Start-Process -FilePath (Get-TINotepadPath) -ArgumentList ('"{0}"' -f $pick) -ErrorAction Stop
                Show-TIToast -Text ('Aberto no Bloco de notas. Auditoria e consoles anteriores: {0} (Arquivo > Abrir).' -f $dir) -Type 'Info'
            } else {
                Show-TIToast -Text ('Ainda não há registros salvos em {0}.' -f $dir) -Type 'Info'
            }
            return
        }
        Sync-TILogFile
        $pick = if (Test-Path -LiteralPath $audit) { $audit } elseif ($session -and (Test-Path -LiteralPath $session)) { $session } else { $null }
        if ($pick) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $pick)
        } else {
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $dir)
        }
    } catch {
        Write-TILog -Level 'Error' -Message ('Não deu para abrir a pasta de logs ({0}): {1}' -f $dir, $_.Exception.Message)
        Show-TIToast -Text 'Não deu para abrir a pasta de logs.' -Type 'Error'
    }
}

function Export-TILog {
    if ($global:LogEntries.Count -eq 0) {
        Show-TIToast -Text 'O console está vazio: nada para exportar.' -Type 'Warn'
        return
    }
    # "Salvar como" (no modo portátil abre em logs\ do pendrive); no WinPE grava direto em logs\
    $path = Select-TISaveFile -Title 'Exportar console' -Filter 'Texto (*.txt)|*.txt|Todos os arquivos (*.*)|*.*' `
                -FileName ('TI-Suite-console-{0}-{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm')) -Folder 'logs'
    if (-not $path) { return }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('=====================================================================')
    [void]$sb.AppendLine(' TI Suite - registro do console')
    [void]$sb.AppendLine('=====================================================================')
    [void]$sb.AppendLine((' Data       : {0}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss')))
    [void]$sb.AppendLine((' Computador : {0}' -f $env:COMPUTERNAME))
    [void]$sb.AppendLine((' Operador   : {0}{1}' -f (Get-TILogOperator), $(if ($global:TI.Elevated -and -not $global:TIWinPE) { ' (administrador)' } else { '' })))
    [void]$sb.AppendLine((' Versão     : {0}' -f $global:TI.Version))
    [void]$sb.AppendLine((' Modo       : {0}' -f (Get-TIModeText)))
    [void]$sb.AppendLine((' Linhas     : {0} (todas, inclusive os detalhes)' -f $global:LogEntries.Count))
    if ($script:LogTrimmed) {
        $file = Get-TILogFilePath
        [void]$sb.AppendLine((' Observação : as linhas mais antigas saíram do console; o registro completo está em {0}' -f $file))
    }
    [void]$sb.AppendLine('=====================================================================')
    foreach ($e in $global:LogEntries) {
        [void]$sb.AppendLine((Format-TILogLine $e))
    }
    [void]$sb.AppendLine('=====================================================================')

    try {
        [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
        Write-TILog -Level 'Success' -Message ("Console exportado para: {0}" -f $path)
        if ($global:TIWinPE) { Show-TIToast -Text ('Console salvo em {0}' -f $path) -Type 'Success' -Duration 8000 }
        else { Show-TIToast -Text 'Console exportado.' -Type 'Success' }
    } catch {
        Write-TILog -Level 'Error' -Message ("Falha ao exportar o console: {0}" -f $_.Exception.Message)
        Show-TIToast -Text 'Não foi possível salvar o arquivo.' -Type 'Error'
    }
}

# ---------------------------------------------------------------------
# Painel do console
# ---------------------------------------------------------------------
function Set-TILogChipState {
    param($Chip)
    $k = [string]$Chip.Tag
    $on = [bool]$global:LogFilter[$k]
    $Chip.Style = if ($on) { 'Primary' } else { 'Outline' }
    foreach ($d in $script:LogChips) {
        if ($d.K -eq $k) { $global:TITip.SetToolTip($Chip, $(if ($on) { $d.On } else { $d.Off })) }
    }
}

function Switch-TILogFilter {
    param($Chip)
    $k = [string]$Chip.Tag
    $global:LogFilter[$k] = -not $global:LogFilter[$k]
    Set-TILogChipState $Chip
    Redraw-TILog
}

function Initialize-TILogPanel {
    param($Parent)

    $root = New-Object System.Windows.Forms.Panel
    $root.Dock = 'Fill'
    $root.BackColor = $global:Pal.ConsoleBg

    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Dock = 'Fill'
    $box.ReadOnly = $true
    $box.BackColor = $global:Pal.ConsoleBg
    $box.ForeColor = $script:LogMessageColor
    $box.BorderStyle = 'None'
    $box.Font = New-TIFont 9.5 Regular 'Consolas'
    # Sem links: não há o que abrir, e o sublinhado azul cobria a cor do nível
    $box.DetectUrls = $false
    $box.WordWrap = $false
    $box.HideSelection = $false
    $box.Add_HandleCreated({ Set-TIDarkScroll $this })
    $root.Controls.Add($box)
    $global:LogBox = $box

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock = 'Top'
    $bar.Height = 38
    $bar.BackColor = $global:Pal.BgDeep
    $root.Controls.Add($bar)

    $title = New-TILabel -Text 'Console' -Size 8.5 -Bold -Color $global:Pal.TextMuted
    $title.Location = New-Object System.Drawing.Point(16, 12)
    $bar.Controls.Add($title)

    # Filtros por nível (ligado = preenchido; desligado = contorno). "Detalhes"
    # mostra as mensagens de depuração e começa desligado.
    $x = 86
    foreach ($lv in $script:LogChips) {
        $chip = New-Object TISuite.PremiumButton
        $chip.Text = $lv.T
        $chip.GlyphSize = 0
        $chip.Height = 24
        $chip.Radius = 99
        $chip.Font = New-TIFont 7.5 Bold
        # A dica é a nossa (estado do filtro), não a automática de texto cortado
        $chip.AutoTip = $false
        $chip.Width = [Math]::Max(44, ($chip.GetPreferredSize([System.Drawing.Size]::Empty).Width - 10))
        $chip.Tag = $lv.K
        $chip.AccessibleName = ('Filtro: {0}' -f $lv.T)
        $chip.Location = New-Object System.Drawing.Point($x, 7)
        Set-TILogChipState $chip
        $chip.Add_Click({ Switch-TILogFilter -Chip $this })
        $chip.Add_Disposed({ try { $global:TITip.SetToolTip($this, $null) } catch { } })
        $bar.Controls.Add($chip)
        $x += $chip.Width + 6
    }

    $counter = New-TILabel -Text '0 eventos' -Size 8 -Dim
    $counter.AutoSize = $false
    $counter.AutoEllipsis = $true
    $counter.Location = New-Object System.Drawing.Point(($x + 8), 13)
    $counter.Size = New-Object System.Drawing.Size(160, 16)
    $bar.Controls.Add($counter)
    $global:LogCounter = $counter

    # Ações
    $acts = New-Object System.Windows.Forms.FlowLayoutPanel
    $acts.Dock = 'Right'
    $acts.FlowDirection = 'LeftToRight'
    $acts.WrapContents = $false
    $acts.AutoSize = $true
    $acts.BackColor = [System.Drawing.Color]::Transparent
    $acts.Padding = New-Object System.Windows.Forms.Padding(0, 6, 8, 0)
    $bar.Controls.Add($acts)
    $global:LogActions = $acts

    $btnCopy = New-TIButton -Text 'Copiar' -Style 'Ghost' -Width 70 -Height 26 -Tip 'Copiar as linhas visíveis (ou só o trecho selecionado)'
    $btnCopy.Add_Click({ Copy-TILog })
    # No WinPE: sem Explorer nem "Salvar como" (veja Open-TILogFolder e Export-TILog)
    $expTip = if ($global:TIWinPE) { 'Salvar o console completo, com os detalhes, na pasta logs do pendrive (Ctrl+E)' }
              else { 'Salvar o console completo, com os detalhes, em .txt (Ctrl+E)' }
    $dirTip = if ($global:TIWinPE) { 'Abrir o console salvo de hoje no Bloco de notas (auditoria e dias anteriores ficam na pasta logs do pendrive)' }
              else { 'Abrir a pasta de logs: auditoria (audit.csv) e o console salvo de cada dia' }
    $btnExp = New-TIButton -Text 'Exportar' -Style 'Ghost' -Width 80 -Height 26 -Tip $expTip
    $btnExp.Add_Click({ Export-TILog })
    $btnDir = New-TIButton -Text 'Logs' -Icon $(if ($global:TIWinPE) { 'Document' } else { 'FolderOpen' }) -Style 'Ghost' -Width 70 -Height 26 -Tip $dirTip
    $btnDir.Add_Click({ Open-TILogFolder })
    $btnClr = New-TIButton -Text 'Limpar' -Style 'Ghost' -Width 70 -Height 26 -Tip 'Limpar a tela do console (Ctrl+L). O arquivo da sessão em logs continua completo.'
    $btnClr.Add_Click({ Reset-TILog })
    foreach ($b in @($btnCopy, $btnExp, $btnDir, $btnClr)) {
        $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
        [void]$acts.Controls.Add($b)
    }

    # Divisória entre a barra e o texto: dentro da barra, embaixo. Adicionada por
    # último, encaixa primeiro e ocupa a largura toda.
    $div = New-Object System.Windows.Forms.Panel
    $div.Dock = 'Bottom'
    $div.Height = 1
    $div.BackColor = $global:Pal.BorderSoft
    $bar.Controls.Add($div)

    $bar.Add_Resize({ Update-TILogCounterWidth })
    $acts.Add_LocationChanged({ Update-TILogCounterWidth })
    $acts.Add_SizeChanged({ Update-TILogCounterWidth })

    $Parent.Controls.Add($root)
    Register-TILogShutdown
    # Linhas registradas antes do painel existir
    if ($global:LogEntries.Count -gt 0) { Redraw-TILog } else { Update-TILogCounter }
    return $root
}
