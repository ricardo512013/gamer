# =====================================================================
# 03-LOGGING.ps1 - Console com níveis, filtro, exportação e auditoria
# =====================================================================

$global:LogEntries = New-Object System.Collections.ArrayList
$global:LogBox = $null
$global:LogFilter = @{ Debug = $false; Info = $true; Success = $true; Warn = $true; Error = $true }
$global:LogFilterChips = @{}
$global:LogErrorCount = 0

# Caminho do log: respeita o modo portátil (definido em TI-Suite.ps1)
if (-not $global:TILogPath) {
    if ($global:TIPortable) {
        $global:TILogPath = Join-Path $global:TIRoot 'logs\exceptions.log'
    } else {
        $global:TILogPath = Join-Path $env:LOCALAPPDATA 'TI-Suite\exceptions.log'
    }
}

$script:LogLevelColor = @{
    Debug   = $global:Pal.TextDim
    Info    = $global:Pal.Primary
    Success = $global:Pal.Success
    Warn    = $global:Pal.Warning
    Error   = $global:Pal.Danger
}
# Etiquetas em português nas linhas do console e na exportação
$script:LogLevelTag = @{
    Debug   = 'DEBUG'
    Info    = 'INFO'
    Success = 'OK'
    Warn    = 'AVISO'
    Error   = 'ERRO'
}
$script:LogMessageColor = [System.Drawing.Color]::FromArgb(203, 213, 225)

function Get-TILogErrorCount {
    return $global:LogErrorCount
}

function Format-TILogLine {
    param($Entry)
    return ('[{0}] {1,-6} {2}' -f $Entry.Time.ToString('HH:mm:ss'), $script:LogLevelTag[$Entry.Level], $Entry.Text)
}

function Add-TILogEntryToBox {
    param($Entry, [switch]$Scroll)
    $box = $global:LogBox
    if (-not $box) { return }
    if (-not $global:LogFilter[$Entry.Level]) { return }

    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor = $script:LogLevelColor.Debug
    $box.AppendText(('[{0}] ' -f $Entry.Time.ToString('HH:mm:ss')))

    $box.SelectionColor = $script:LogLevelColor[$Entry.Level]
    $box.AppendText(('{0,-6} ' -f $script:LogLevelTag[$Entry.Level]))

    $box.SelectionColor = if ($Entry.Level -eq 'Error' -or $Entry.Level -eq 'Warn') {
        $script:LogLevelColor[$Entry.Level]
    } else {
        $script:LogMessageColor
    }
    $box.AppendText($Entry.Text + "`n")
    if ($Scroll) { $box.ScrollToCaret() }
}

function Update-TILogCounter {
    if ($global:LogCounter) {
        $total = $global:LogEntries.Count
        $errs = $global:LogErrorCount
        $ev = if ($total -eq 1) { 'evento' } else { 'eventos' }
        $txt = if ($errs -gt 0) { ('{0} {1}, {2} com erro' -f $total, $ev, $errs) } else { ('{0} {1}' -f $total, $ev) }
        $global:LogCounter.Text = $txt
        $global:LogCounter.ForeColor = if ($errs -gt 0) { $global:Pal.Danger } else { $global:Pal.TextDim }
    }
}

function Write-TILog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Debug','Info','Success','Warn','Error')][string]$Level = 'Info'
    )
    $entry = [pscustomobject]@{ Time = Get-Date; Level = $Level; Text = $Message }
    [void]$global:LogEntries.Add($entry)
    if ($Level -eq 'Error') { $global:LogErrorCount++ }
    Add-TILogEntryToBox $entry -Scroll
    Update-TILogCounter
}

function Write-TIAudit {
    # Trilha de auditoria (CSV) das ações administrativas: quando, PC, operador, ação, resultado.
    # Nunca recebe senhas: só o nome da tarefa e um detalhe curto.
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$Result = 'OK',
        [string]$Detail = ''
    )
    try {
        $dir = Split-Path -Parent $global:TILogPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $file = Join-Path $dir 'audit.csv'
        $q = { param($t) '"' + ([string]$t -replace '"', '""') + '"' }
        $line = (@(
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME, $env:USERNAME, $Action, $Result, $Detail
        ) | ForEach-Object { & $q $_ }) -join ';'
        if (-not (Test-Path -LiteralPath $file)) {
            Set-Content -LiteralPath $file -Value '"data";"pc";"operador";"acao";"resultado";"detalhe"' -Encoding UTF8
        }
        Add-Content -LiteralPath $file -Value $line -Encoding UTF8
    } catch { }
}

function Reset-TILog {
    $global:LogEntries.Clear()
    $global:LogErrorCount = 0
    if ($global:LogBox) { $global:LogBox.Clear() }
    Update-TILogCounter
    Write-TILog -Level 'Info' -Message 'Console limpo. Sistema pronto.'
}

function Redraw-TILog {
    if (-not $global:LogBox) { return }
    $global:LogBox.SuspendLayout()
    $global:LogBox.Clear()
    foreach ($e in $global:LogEntries) { Add-TILogEntryToBox $e }
    $global:LogBox.ResumeLayout()
    $global:LogBox.ScrollToCaret()
    Update-TILogCounter
}

function Export-TILog {
    if ($global:LogEntries.Count -eq 0) {
        Show-TIToast -Text 'O console está vazio: nada para exportar.' -Type 'Warn'
        return
    }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = 'Exportar console'
    $dlg.Filter = 'Texto (*.txt)|*.txt|Todos os arquivos (*.*)|*.*'
    $dlg.FileName = ('TI-Suite-console-{0}-{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm'))
    if ($dlg.ShowDialog() -ne 'OK') { $dlg.Dispose(); return }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('=====================================================================')
    [void]$sb.AppendLine(' TI Suite - registro do console')
    [void]$sb.AppendLine('=====================================================================')
    [void]$sb.AppendLine((' Data       : {0}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss')))
    [void]$sb.AppendLine((' Computador : {0}' -f $env:COMPUTERNAME))
    [void]$sb.AppendLine((' Operador   : {0}{1}' -f $env:USERNAME, $(if ($global:TI.Elevated) { ' (administrador)' } else { '' })))
    [void]$sb.AppendLine((' Versão     : {0}' -f $global:TI.Version))
    [void]$sb.AppendLine('=====================================================================')
    foreach ($e in $global:LogEntries) {
        [void]$sb.AppendLine((Format-TILogLine $e))
    }
    [void]$sb.AppendLine('=====================================================================')

    try {
        [System.IO.File]::WriteAllText($dlg.FileName, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
        Write-TILog -Level 'Success' -Message ("Console exportado para: {0}" -f $dlg.FileName)
        Show-TIToast -Text 'Console exportado.' -Type 'Success'
    } catch {
        Write-TILog -Level 'Error' -Message ("Falha ao exportar o console: {0}" -f $_.Exception.Message)
        Show-TIToast -Text 'Não foi possível salvar o arquivo.' -Type 'Error'
    }
    $dlg.Dispose()
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
    $box.DetectUrls = $true
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

    $div = New-Object System.Windows.Forms.Panel
    $div.Dock = 'Bottom'
    $div.Height = 1
    $div.BackColor = $global:Pal.BorderSoft
    $root.Controls.Add($div)

    $title = New-TILabel -Text 'Console' -Size 8.5 -Bold -Color $global:Pal.TextMuted
    $title.Location = New-Object System.Drawing.Point(16, 12)
    $bar.Controls.Add($title)

    $counter = New-TILabel -Text '0 eventos' -Size 8 -Dim
    $counter.Location = New-Object System.Drawing.Point(76, 13)
    $bar.Controls.Add($counter)
    $global:LogCounter = $counter

    # Filtros por nível (desligado = contorno; ligado = preenchido)
    $levels = @(
        @{ K = 'Info';    T = 'Info';  Tip = 'Mostrar mensagens informativas' },
        @{ K = 'Success'; T = 'OK';    Tip = 'Mostrar mensagens de sucesso' },
        @{ K = 'Warn';    T = 'Aviso'; Tip = 'Mostrar avisos' },
        @{ K = 'Error';   T = 'Erro';  Tip = 'Mostrar erros' }
    )
    $x = 240
    foreach ($lv in $levels) {
        $chip = New-Object TISuite.PremiumButton
        $chip.Text = $lv.T
        $chip.GlyphSize = 0
        $chip.Width = 56
        $chip.Height = 24
        $chip.Radius = 99
        $chip.Font = New-TIFont 7.5 Bold
        $chip.Style = if ($global:LogFilter[$lv.K]) { 'Primary' } else { 'Ghost' }
        $chip.Location = New-Object System.Drawing.Point($x, 7)
        $chip.AccessibleName = $lv.Tip
        $global:TITip.SetToolTip($chip, $lv.Tip)
        $k = $lv.K
        $chip.Add_Click({
            $global:LogFilter[$k] = -not $global:LogFilter[$k]
            $chip.Style = if ($global:LogFilter[$k]) { 'Primary' } else { 'Ghost' }
            Redraw-TILog
        }.GetNewClosure())
        $bar.Controls.Add($chip)
        $global:LogFilterChips[$lv.K] = $chip
        $x += 62
    }

    # Ações
    $acts = New-Object System.Windows.Forms.FlowLayoutPanel
    $acts.Dock = 'Right'
    $acts.FlowDirection = 'LeftToRight'
    $acts.WrapContents = $false
    $acts.AutoSize = $true
    $acts.BackColor = [System.Drawing.Color]::Transparent
    $acts.Padding = New-Object System.Windows.Forms.Padding(0, 6, 10, 0)
    $bar.Controls.Add($acts)

    $btnCopy = New-TIButton -Text 'Copiar' -Style 'Ghost' -Width 74 -Height 26 -Tip 'Copiar todo o console'
    $btnCopy.Add_Click({
        if ($global:LogEntries.Count -eq 0) { return }
        $lines = ($global:LogEntries | ForEach-Object { Format-TILogLine $_ }) -join "`r`n"
        try { [System.Windows.Forms.Clipboard]::SetText($lines); Show-TIToast -Text 'Console copiado.' -Type 'Success' } catch { }
    })
    $btnExp = New-TIButton -Text 'Exportar' -Style 'Ghost' -Width 84 -Height 26 -Tip 'Salvar o console em .txt (Ctrl+E)'
    $btnExp.Add_Click({ Export-TILog })
    $btnClr = New-TIButton -Text 'Limpar' -Style 'Ghost' -Width 74 -Height 26 -Tip 'Limpar o console (Ctrl+L)'
    $btnClr.Add_Click({ Reset-TILog })

    [void]$acts.Controls.Add($btnCopy)
    [void]$acts.Controls.Add($btnExp)
    [void]$acts.Controls.Add($btnClr)

    $Parent.Controls.Add($root)
    return $root
}
