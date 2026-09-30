# =====================================================================
# 05-SHELL.ps1 - Janela principal, barra lateral, cabeçalho, status e navegação
# Código de nível superior. Os handlers de eventos usam $this, $this.Tag ou
# $global: (nunca variáveis locais): funcionam em qualquer escopo e não
# confundem variáveis de mesmo nome de outro diálogo aberto.
# =====================================================================

$global:NavItems = @{}
$global:WorkspacePanels = @{}
$global:DwmRounded = $false
$global:TIShown = $false
$global:TIOverlayHintDefault = 'Os detalhes aparecem no console (F12).'
$global:OverlayPercent = -1

# "Saúde" -> "saude": a busca funciona com ou sem acento
function ConvertTo-TIPlain {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $norm = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().ToLowerInvariant()
}

# ---------------------------------------------------------------------
# Janela principal: TISuite.TIForm (Controls.cs) = sem moldura, redimensiona
# pelas bordas (faixa de 6 px), maximiza dentro da área útil do monitor, tem
# sombra e minimiza pelo ícone da barra de tarefas. Tamanho e posição finais
# vêm de Set-TIInitialBounds, no fim do Start-TIApp.
# ---------------------------------------------------------------------
$global:Form = New-Object TISuite.TIForm
$global:Form.Text = 'TI Suite'
$global:Form.Size = New-Object System.Drawing.Size(1252, 792)
$global:Form.MinimumSize = New-Object System.Drawing.Size(1040, 640)
$global:Form.StartPosition = 'CenterScreen'
$global:Form.BackColor = $global:Pal.Bg
$global:Form.KeyPreview = $true
$global:Form.AutoScaleMode = 'None'

# Ícone da janela (quadrado arredondado com glifo de terminal)
try {
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'ClearTypeGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)
    $path = [TISuite.Gfx]::RoundRect(1, 1, 30, 30, 8)
    $g.FillPath((New-Object System.Drawing.SolidBrush($global:Pal.Primary)), $path)
    $g.DrawString(([char]0xE756), (New-Object System.Drawing.Font('Segoe MDL2 Assets', 14)),
                  (New-Object System.Drawing.SolidBrush($global:Pal.OnPrimary)),
                  (New-Object System.Drawing.RectangleF(1, 0, 30, 31)))
    $g.Dispose()
    $hIcon = $bmp.GetHicon()
    $global:Form.Icon = [System.Drawing.Icon]::FromHandle($hIcon)
} catch { }

$global:Root = New-Object System.Windows.Forms.Panel
$global:Root.Dock = 'Fill'
$global:Form.Controls.Add($global:Root)

# Maximizar/restaurar (botão, duplo clique no cabeçalho e na marca)
function Switch-TIMaximize {
    $global:Form.WindowState = $(if ($global:Form.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' })
}

# ---------------------------------------------------------------------
# Barra lateral
# ---------------------------------------------------------------------
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Dock = 'Left'
$sidebar.Width = $global:Theme.SidebarWidth
$sidebar.BackColor = $global:Pal.Sidebar

$nav = New-Object System.Windows.Forms.FlowLayoutPanel
$nav.Dock = 'Fill'
$nav.FlowDirection = 'TopDown'
$nav.WrapContents = $false
$nav.AutoScroll = $true
$nav.BackColor = [System.Drawing.Color]::Transparent
$nav.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 8)
$sidebar.Controls.Add($nav)
$global:NavFlow = $nav
$nav.Add_Resize({
    $w = $this.ClientSize.Width - $this.Padding.Horizontal
    if ($w -gt 40) { foreach ($ctrl in $this.Controls) { $ctrl.Width = $w } }
})

# Marca
$brand = New-Object System.Windows.Forms.Panel
$brand.Dock = 'Top'
$brand.Height = 64
$brand.BackColor = [System.Drawing.Color]::Transparent
$sidebar.Controls.Add($brand)

$logo = New-Object TISuite.RoundPanel
$logo.Radius = 11
$logo.FillColor = $global:Pal.Primary
$logo.BorderWidth = 0
$logo.BackdropColor = $global:Pal.Sidebar
$logo.Size = New-Object System.Drawing.Size(38, 38)
$logo.Location = New-Object System.Drawing.Point(14, 13)
$brand.Controls.Add($logo)
$logoGlyph = New-TIGlyph -Icon 'Terminal' -Size 17 -Color $global:Pal.OnPrimary
$logoGlyph.Location = New-Object System.Drawing.Point(7, 7)
$logo.Controls.Add($logoGlyph)

$brandTitle = New-TILabel -Text 'TI Suite' -Size 13 -Bold
$brandTitle.Location = New-Object System.Drawing.Point(60, 13)
$brand.Controls.Add($brandTitle)

$brandSub = New-TILabel -Text $(if ($global:TIPortable) { 'Portátil (USB)' } else { 'Suporte escolar' }) -Size 7.5 -Muted
$brandSub.Location = New-Object System.Drawing.Point(61, 36)
$brand.Controls.Add($brandSub)

foreach ($c in @($brand, $brandTitle, $brandSub, $logoGlyph)) {
    $c.Add_MouseDown({ if ($_.Button -eq 'Left' -and $_.Clicks -eq 1) { [TISuite.Native]::DragWindow($global:Form) } })
}
$brand.Add_MouseDoubleClick({ if ($_.Button -eq 'Left') { Switch-TIMaximize } })

# Busca (ícone dentro da caixa; busca com ou sem acento)
$searchWrap = New-Object System.Windows.Forms.Panel
$searchWrap.Dock = 'Top'
$searchWrap.Height = 48
$searchWrap.BackColor = [System.Drawing.Color]::Transparent
$sidebar.Controls.Add($searchWrap)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = New-Object System.Drawing.Point(16, 10)
$searchBox.Size = New-Object System.Drawing.Size(($global:Theme.SidebarWidth - 32), 28)
$searchBox.Anchor = 'Top,Left,Right'
$searchBox.BackColor = $global:Pal.BgDeep
$searchBox.ForeColor = $global:Pal.TextMain
$searchBox.BorderStyle = 'FixedSingle'
$searchBox.Font = New-TIFont 9.5
$global:SearchBox = $searchBox
$searchWrap.Controls.Add($searchBox)
$null = Add-TIPlaceholder -TextBox $searchBox -Text 'Buscar ferramenta (Ctrl+F)'

$searchIcon = New-TIGlyph -Icon 'Search' -Size 10 -Color $global:Pal.TextDim
$searchIcon.BackColor = $global:Pal.BgDeep
$searchIcon.Cursor = [System.Windows.Forms.Cursors]::IBeam
$searchWrap.Controls.Add($searchIcon)
$searchIcon.Location = New-Object System.Drawing.Point(($searchBox.Right - 22), ($searchBox.Top + [int](($searchBox.Height - $searchIcon.PreferredHeight) / 2)))
$searchIcon.Anchor = 'Top,Right'
$searchIcon.BringToFront()
$searchIcon.Add_Click({ [void]$global:SearchBox.Focus() })

function Update-TINavFilter {
    $q = ConvertTo-TIPlain ($global:SearchBox.Text.Trim())
    foreach ($ws in $global:TI.Workspaces) {
        $item = $global:NavItems[$ws.Id]
        if (-not $item) { continue }
        $hay = ConvertTo-TIPlain ('{0} {1} {2}' -f $ws.Title, $ws.Sub, $ws.Keywords)
        $item.Visible = ($q -eq '' -or $hay.Contains($q))
    }
}
$searchBox.Add_TextChanged({ Update-TINavFilter })
$searchBox.Add_KeyDown({
    if ($_.KeyCode -eq 'Escape') {
        $global:SearchBox.Text = ''
        $_.SuppressKeyPress = $true
    } elseif ($_.KeyCode -eq 'Enter') {
        $_.SuppressKeyPress = $true
        $q = ConvertTo-TIPlain ($global:SearchBox.Text.Trim())
        $first = $global:TI.Workspaces | Where-Object {
            $q -eq '' -or (ConvertTo-TIPlain ('{0} {1} {2}' -f $_.Title, $_.Sub, $_.Keywords)).Contains($q)
        } | Select-Object -First 1
        if ($first -and -not $global:TI.Busy) { Switch-TIWorkspace -Id $first.Id }
    }
})

# Rodapé da barra lateral
$foot = New-Object System.Windows.Forms.Panel
$foot.Dock = 'Bottom'
$foot.Height = 68
$foot.BackColor = [System.Drawing.Color]::Transparent
$sidebar.Controls.Add($foot)

$footDiv = New-Object System.Windows.Forms.Panel
$footDiv.Dock = 'Top'
$footDiv.Height = 1
$footDiv.BackColor = $global:Pal.BorderSoft
$foot.Controls.Add($footDiv)

$badge = New-Object TISuite.RoundPanel
$badge.Radius = 9
$badge.FillColor = $global:Pal.BgDeep
$badge.BorderColor = $global:Pal.BorderSoft
$badge.BackdropColor = $global:Pal.Sidebar
$badge.Size = New-Object System.Drawing.Size(150, 30)
$badge.Location = New-Object System.Drawing.Point(14, 12)
$badge.Cursor = [System.Windows.Forms.Cursors]::Hand
$foot.Controls.Add($badge)
$global:AdminBadge = $badge

$badgeIcon = New-TIGlyph -Icon 'Shield' -Size 11 -Color $global:Pal.Warning
$badgeIcon.Location = New-Object System.Drawing.Point(10, 8)
$badgeIcon.Cursor = [System.Windows.Forms.Cursors]::Hand
$badge.Controls.Add($badgeIcon)
$global:AdminBadgeIcon = $badgeIcon
$badgeText = New-TILabel -Text 'Sem elevação' -Size 8 -Bold -Color $global:Pal.Warning
$badgeText.Location = New-Object System.Drawing.Point(29, 8)
$badgeText.Cursor = [System.Windows.Forms.Cursors]::Hand
$badge.Controls.Add($badgeText)
$global:AdminBadgeText = $badgeText
foreach ($c in @($badge, $badgeIcon, $badgeText)) { $c.Add_Click({ Invoke-TIBadgeClick }) }

$verLbl = New-TILabel -Text ('v{0}{1}' -f $global:TI.Version, $(if ($global:TIPortable) { ' (USB)' } else { '' })) -Size 7.5 -Dim
$verLbl.Location = New-Object System.Drawing.Point(16, 47)
$foot.Controls.Add($verLbl)

$btnSettings = New-TIGlyphButton -Icon 'Settings' -Tip 'Configurações' -Size 32
$btnSettings.Anchor = 'Top,Right'
$btnSettings.Location = New-Object System.Drawing.Point(($global:Theme.SidebarWidth - 46), 11)
$btnSettings.Add_Click({ Show-TISettings })
$foot.Controls.Add($btnSettings)

# Divisória direita da barra lateral
$sideEdge = New-Object System.Windows.Forms.Panel
$sideEdge.Dock = 'Right'
$sideEdge.Width = 1
$sideEdge.BackColor = $global:Pal.BorderSoft
$sidebar.Controls.Add($sideEdge)

# Ordem de encaixe explícita (o último da coleção encaixa primeiro):
# borda direita, marca no topo, busca logo abaixo, rodapé embaixo e o menu no meio.
$foot.SendToBack()
$searchWrap.SendToBack()
$brand.SendToBack()
$sideEdge.SendToBack()
$nav.BringToFront()

# ---------------------------------------------------------------------
# Coluna de conteúdo
# ---------------------------------------------------------------------
$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$global:Root.Controls.Add($content)
$global:Root.Controls.Add($sidebar)

# Divisão área de trabalho / console
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Horizontal'
$split.BackColor = $global:Pal.BorderSoft
$split.SplitterWidth = 6
$split.SplitterIncrement = 1
$split.Panel1MinSize = 200
$split.Panel2MinSize = 40
$global:ConsoleCollapsed = $false
$global:ConsoleSavedHeight = 0
$content.Controls.Add($split)
$global:Split = $split

$global:HostPanel = New-Object System.Windows.Forms.Panel
$global:HostPanel.Dock = 'Fill'
$global:HostPanel.BackColor = $global:Pal.Bg
$split.Panel1.Controls.Add($global:HostPanel)

# Sobreposição de "ocupado": nome da tarefa (com %) e a última mensagem dela
$overlay = New-Object System.Windows.Forms.Panel
$overlay.Dock = 'Fill'
$overlay.BackColor = $global:Pal.Bg
$overlay.Visible = $false
$global:HostPanel.Controls.Add($overlay)
$global:Overlay = $overlay

$spin = New-Object TISuite.ArcSpinner
$spin.Size = New-Object System.Drawing.Size(44, 44)
$overlay.Controls.Add($spin)
$global:OverlaySpinner = $spin

$ovTitle = New-TILabel -Text 'Processando...' -Size 11 -Bold
$ovTitle.AutoSize = $true
$overlay.Controls.Add($ovTitle)
$global:OverlayLabel = $ovTitle

$ovHint = New-TILabel -Text $global:TIOverlayHintDefault -Size 8.5 -Muted
$ovHint.AutoSize = $true
$ovHint.TextAlign = 'TopCenter'
$overlay.Controls.Add($ovHint)
$global:OverlayHint = $ovHint

$global:LayoutOverlay = {
    $ov = $global:Overlay
    $cx = [int]($ov.ClientSize.Width / 2)
    $cy = [int]($ov.ClientSize.Height / 2)
    $global:OverlayHint.MaximumSize = New-Object System.Drawing.Size(([Math]::Max(240, $ov.ClientSize.Width - 80)), 0)
    $global:OverlaySpinner.Location = New-Object System.Drawing.Point(($cx - 22), ($cy - 58))
    $global:OverlayLabel.Location = New-Object System.Drawing.Point(($cx - [int]($global:OverlayLabel.PreferredWidth / 2)), ($cy + 4))
    $global:OverlayHint.Location = New-Object System.Drawing.Point(($cx - [int]($global:OverlayHint.Width / 2)), ($cy + 30))
}
$overlay.Add_Resize({ & $global:LayoutOverlay })

# Console
$null = Initialize-TILogPanel -Parent $split.Panel2

# ---------------------------------------------------------------------
# Cabeçalho
# ---------------------------------------------------------------------
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = $global:Theme.HeaderHeight
$header.BackColor = [System.Drawing.Color]::Transparent
$content.Controls.Add($header)
$global:Header = $header

$headDiv = New-Object System.Windows.Forms.Panel
$headDiv.Dock = 'Bottom'
$headDiv.Height = 1
$headDiv.BackColor = $global:Pal.BorderSoft
$header.Controls.Add($headDiv)

$hTitle = New-TILabel -Text 'Início' -Size 15 -Bold
$hTitle.Location = New-Object System.Drawing.Point(24, 9)
$hTitle.Anchor = 'Top,Left'
$header.Controls.Add($hTitle)
$global:HeaderTitle = $hTitle

$hSub = New-TILabel -Text '' -Size 8.5 -Muted
$hSub.Location = New-Object System.Drawing.Point(26, 38)
$hSub.Anchor = 'Top,Left'
$header.Controls.Add($hSub)
$global:HeaderSub = $hSub

$hActions = New-Object System.Windows.Forms.FlowLayoutPanel
$hActions.Dock = 'Right'
$hActions.FlowDirection = 'LeftToRight'
$hActions.WrapContents = $false
$hActions.AutoSize = $true
$hActions.BackColor = [System.Drawing.Color]::Transparent
$hActions.Padding = New-Object System.Windows.Forms.Padding(0, 13, 8, 0)
$header.Controls.Add($hActions)
$global:HeaderActions = $hActions

# Botões da janela
$caption = New-Object System.Windows.Forms.FlowLayoutPanel
$caption.Dock = 'Right'
$caption.FlowDirection = 'LeftToRight'
$caption.WrapContents = $false
$caption.AutoSize = $true
$caption.BackColor = [System.Drawing.Color]::Transparent
$caption.Padding = New-Object System.Windows.Forms.Padding(0, 8, 10, 0)
$header.Controls.Add($caption)

# A divisória encaixa primeiro (fim da coleção) e passa por baixo dos botões
$headDiv.SendToBack()

$btnLog = New-TIGlyphButton -Icon 'Terminal' -Tip 'Mostrar ou ocultar o console (F12)' -Size 44
$btnLog.Radius = 7
$btnLog.Add_Click({ Toggle-TIConsole })

$btnMin = New-TIGlyphButton -Icon 'Min' -Tip 'Minimizar' -Size 44
$btnMin.Radius = 7
$btnMin.Add_Click({ $global:Form.WindowState = 'Minimized' })

$btnMax = New-TIGlyphButton -Icon 'Max' -Tip 'Maximizar' -Size 44
$btnMax.Radius = 7
$btnMax.Add_Click({ Switch-TIMaximize })
$global:BtnMax = $btnMax

$btnClose = New-TIGlyphButton -Icon 'Close' -Tip 'Fechar' -Size 44
$btnClose.Radius = 7
$btnClose.Add_MouseEnter({ $this.Style = 'Danger' })
$btnClose.Add_MouseLeave({ $this.Style = 'Ghost' })
$btnClose.Add_Click({ $global:Form.Close() })

[void]$caption.Controls.Add($btnLog)
[void]$caption.Controls.Add($btnMin)
[void]$caption.Controls.Add($btnMax)
[void]$caption.Controls.Add($btnClose)

foreach ($c in @($global:Header, $hTitle, $hSub)) {
    $c.Add_MouseDown({ if ($_.Button -eq 'Left' -and $_.Clicks -eq 1) { [TISuite.Native]::DragWindow($global:Form) } })
    $c.Add_MouseDoubleClick({ if ($_.Button -eq 'Left') { Switch-TIMaximize } })
}

# ---------------------------------------------------------------------
# Barra de status
# ---------------------------------------------------------------------
$status = New-Object System.Windows.Forms.Panel
$status.Dock = 'Bottom'
$status.Height = $global:Theme.StatusHeight
$status.BackColor = $global:Pal.BgDeep
$content.Controls.Add($status)
$global:StatusBar = $status

$statusDiv = New-Object System.Windows.Forms.Panel
$statusDiv.Dock = 'Top'
$statusDiv.Height = 1
$statusDiv.BackColor = $global:Pal.BorderSoft
$status.Controls.Add($statusDiv)

$stateDot = New-Object TISuite.RoundPanel
$stateDot.Radius = 99
$stateDot.BorderWidth = 0
$stateDot.FillColor = $global:Pal.Success
$stateDot.BackdropColor = $global:Pal.BgDeep
$stateDot.Size = New-Object System.Drawing.Size(9, 9)
$stateDot.Location = New-Object System.Drawing.Point(14, 10)
$status.Controls.Add($stateDot)
$global:StateDot = $stateDot

$stateLbl = New-TILabel -Text 'Pronto' -Size 8 -Bold -Color $global:Pal.TextMuted
$stateLbl.Location = New-Object System.Drawing.Point(30, 7)
$status.Controls.Add($stateLbl)
$global:StateLabel = $stateLbl

$barWrap = New-Object System.Windows.Forms.Panel
$barWrap.Location = New-Object System.Drawing.Point(110, 11)
$barWrap.Size = New-Object System.Drawing.Size(220, 6)
$barWrap.BackColor = $global:Pal.BgDeep
$barWrap.Visible = $false
$status.Controls.Add($barWrap)
$global:ProgressWrap = $barWrap

$bar = New-Object TISuite.FlatProgress
$bar.Dock = 'Fill'
$bar.Percent = -1
$barWrap.Controls.Add($bar)
$global:ProgressBar = $bar

$barLabel = New-TILabel -Text '' -Size 8 -Muted
$barLabel.AutoEllipsis = $true
$barLabel.Location = New-Object System.Drawing.Point(342, 7)
$status.Controls.Add($barLabel)
$global:StatusLabel = $barLabel

$btnCancel = New-TIButton -Text 'Cancelar' -Style 'Outline' -Width 82 -Height 22 -Tip 'Interromper a tarefa atual'
$btnCancel.Font = New-TIFont 8 Bold
$btnCancel.Visible = $false
$btnCancel.Add_Click({ Stop-TIAsync })
$status.Controls.Add($btnCancel)
$global:CancelBtn = $btnCancel

$helpLbl = New-TILabel -Text 'F1: atalhos' -Size 8 -Dim
$helpLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
$helpLbl.Add_Click({ Show-TIShortcuts })
$global:TITip.SetToolTip($helpLbl, 'Ver os atalhos do teclado')
$status.Controls.Add($helpLbl)
$global:HelpHint = $helpLbl

$clock = New-TILabel -Text (Get-Date -Format 'HH:mm') -Size 8 -Dim
$status.Controls.Add($clock)
$global:ClockLabel = $clock

$statVer = New-TILabel -Text ('{0}  |  v{1}' -f $env:COMPUTERNAME, $global:TI.Version) -Size 8 -Dim
$status.Controls.Add($statVer)
$global:StatusVersion = $statVer

$global:LayoutStatusBar = {
    $w = $global:StatusBar.ClientSize.Width
    if ($w -le 0) { return }
    $global:StatusVersion.Location = New-Object System.Drawing.Point(($w - $global:StatusVersion.PreferredWidth - 16), 7)
    $global:ClockLabel.Location = New-Object System.Drawing.Point(($global:StatusVersion.Left - $global:ClockLabel.PreferredWidth - 16), 7)
    $global:HelpHint.Location = New-Object System.Drawing.Point(($global:ClockLabel.Left - $global:HelpHint.PreferredWidth - 16), 7)
    $global:CancelBtn.Location = New-Object System.Drawing.Point(($global:HelpHint.Left - $global:CancelBtn.Width - 14), 3)
    $right = if ($global:CancelBtn.Visible) { $global:CancelBtn.Left - 12 } else { $global:HelpHint.Left - 12 }
    $left = if ($global:ProgressWrap.Visible) { 342 } else { 110 }
    $global:StatusLabel.AutoSize = $false
    $global:StatusLabel.Location = New-Object System.Drawing.Point($left, 7)
    $global:StatusLabel.Size = New-Object System.Drawing.Size(([Math]::Max(40, $right - $left)), 16)
}
$global:StatusBar.Add_Resize({ & $global:LayoutStatusBar })

# Relógio
$clockTimer = New-Object System.Windows.Forms.Timer
$clockTimer.Interval = 15000
$clockTimer.Add_Tick({ $global:ClockLabel.Text = Get-Date -Format 'HH:mm' })
$clockTimer.Start()

# ---------------------------------------------------------------------
# Botão da barra de tarefas: progresso da tarefa, vermelho por alguns
# segundos quando termina com erro e pisca se a janela estiver atrás.
# Melhor esforço (Windows 7+), só depois que a janela apareceu.
# ---------------------------------------------------------------------
$global:TaskbarTimer = New-Object System.Windows.Forms.Timer
$global:TaskbarTimer.Interval = 5000
$global:TaskbarTimer.Add_Tick({
    $this.Stop()
    try { [TISuite.Native]::ClearTaskbarProgress($global:Form) } catch { }
})

function Update-TITaskbar {
    param(
        [ValidateSet('Progress','Done','Error')][string]$State = 'Progress',
        [int]$Percent = -1,
        [switch]$Flash
    )
    if (-not $global:TIShown -or -not $global:Form -or $global:Form.IsDisposed) { return }
    try {
        $global:TaskbarTimer.Stop()
        switch ($State) {
            'Progress' { [TISuite.Native]::SetTaskbarProgress($global:Form, $Percent) }
            'Done'     { [TISuite.Native]::ClearTaskbarProgress($global:Form) }
            'Error'    { [TISuite.Native]::SetTaskbarError($global:Form); $global:TaskbarTimer.Start() }
        }
        # FlashTaskbar não faz nada se a janela (ou um diálogo dela) já está na frente
        if ($Flash -or $State -eq 'Error') { [TISuite.Native]::FlashTaskbar($global:Form) }
    } catch { }
}

# ---------------------------------------------------------------------
# Navegação
# ---------------------------------------------------------------------
function Register-TIWorkspace {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Title,
        [string]$Sub = '',
        [string]$Icon = 'Info',
        [string]$Keywords = '',
        [Parameter(Mandatory)][scriptblock]$Build,
        [scriptblock]$Actions,
        [scriptblock]$OnActivate,
        [scriptblock]$Refresh
    )
    $item = [pscustomobject]@{
        Id = $Id; Title = $Title; Sub = $Sub; Icon = $Icon; Keywords = $Keywords
        Build = $Build; Actions = $Actions; OnActivate = $OnActivate; Refresh = $Refresh
    }
    [void]$global:TI.Workspaces.Add($item)
}

function Build-TISidebar {
    $n = 0
    foreach ($ws in $global:TI.Workspaces) {
        $n++
        if ($global:NavItems.ContainsKey($ws.Id)) { continue }
        $item = New-Object TISuite.SidebarItem
        $item.Glyph = Get-TIGlyph $ws.Icon
        $item.ItemText = $ws.Title
        $item.AccessibleName = $ws.Title
        if ($n -le 9) { $item.HintText = ('Ctrl+{0}' -f $n) }
        $w = $global:NavFlow.ClientSize.Width - $global:NavFlow.Padding.Horizontal
        if ($w -lt 60) { $w = $global:Theme.SidebarWidth - 17 }
        $item.Width = $w
        $item.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
        # Id no Tag (sem closure): funciona mesmo com o script fora do escopo global
        $item.Tag = $ws.Id
        $item.Add_Click({ Switch-TIWorkspace -Id ([string]$this.Tag) })
        $global:NavFlow.Controls.Add($item)
        $global:NavItems[$ws.Id] = $item
    }
}

function Switch-TIWorkspace {
    param([string]$Id, [switch]$Force)
    $ws = $global:TI.Workspaces | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $ws) { return }
    if ($global:TI.ActiveId -eq $Id -and -not $Force) { return }

    foreach ($key in @($global:WorkspacePanels.Keys)) {
        $global:WorkspacePanels[$key].Visible = $false
    }

    if (-not $global:WorkspacePanels.ContainsKey($Id)) {
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = 'Fill'
        $panel.BackColor = $global:Pal.Bg
        $global:HostPanel.Controls.Add($panel)
        $global:WorkspacePanels[$Id] = $panel
        $panel.SuspendLayout()
        & $ws.Build $panel $Id
        $panel.ResumeLayout()
    }

    $panel = $global:WorkspacePanels[$Id]
    $panel.Visible = $true
    $panel.BringToFront()
    $global:Overlay.BringToFront()

    $global:HeaderTitle.Text = $ws.Title
    $global:HeaderSub.Text = $ws.Sub

    # Os botões da área anterior são descartados (o Dispose também libera a dica)
    foreach ($c in @($global:HeaderActions.Controls)) { try { $c.Dispose() } catch { } }
    $global:HeaderActions.Controls.Clear()
    if ($ws.Actions) { & $ws.Actions $global:HeaderActions }
    foreach ($c in $global:HeaderActions.Controls) { $c.Enabled = -not $global:TI.Busy }

    foreach ($key in @($global:NavItems.Keys)) {
        $global:NavItems[$key].Active = ($key -eq $Id)
    }

    $global:TI.ActiveId = $Id
    Write-TILog -Level 'Debug' -Message ("Área aberta: {0}" -f $ws.Title)

    if ($ws.OnActivate -and -not $global:TI.SuppressOnActivate) { & $ws.OnActivate }
}

# Ctrl+R / F5 / botão Atualizar: recarrega de verdade a área atual
function Invoke-TIRefreshActive {
    $ws = $global:TI.Workspaces | Where-Object { $_.Id -eq $global:TI.ActiveId } | Select-Object -First 1
    if (-not $ws) { return }
    if ($global:TI.Busy) { Show-TIToast -Text 'Espere a tarefa atual terminar.' -Type 'Warn'; return }
    if ($ws.Refresh) { & $ws.Refresh }
    elseif ($ws.OnActivate) { & $ws.OnActivate }
}

# -NoCancel: tarefa curta e crítica, sem o botão Cancelar
function Set-TIBusy {
    param([bool]$Busy, [string]$Name = '', [switch]$NoCancel)
    if ($Busy) {
        $global:OverlayPercent = -1
        $global:OverlayLabel.Text = $Name
        $global:OverlayHint.Text = $global:TIOverlayHintDefault
        $global:Overlay.Visible = $true
        $global:Overlay.BringToFront()
        & $global:LayoutOverlay
        $global:CancelBtn.Enabled = -not $NoCancel
        $global:CancelBtn.Visible = -not $NoCancel
        $global:ProgressWrap.Visible = $true
        $global:StateDot.FillColor = $global:Pal.Warning
        $global:StateDot.Invalidate()
        $global:StateLabel.Text = 'Executando'
        $global:StateLabel.ForeColor = $global:Pal.Warning
        $global:ProgressBar.Percent = -1
        $global:StatusLabel.Text = $Name
        foreach ($k in @($global:NavItems.Keys)) { $global:NavItems[$k].Enabled = $false }
        foreach ($c in $global:HeaderActions.Controls) { $c.Enabled = $false }
        Update-TITaskbar -State 'Progress' -Percent -1
    } else {
        $global:OverlayPercent = -1
        $global:Overlay.Visible = $false
        $global:CancelBtn.Visible = $false
        $global:ProgressWrap.Visible = $false
        $global:StateDot.FillColor = $global:Pal.Success
        $global:StateDot.Invalidate()
        $global:StateLabel.Text = 'Pronto'
        $global:StateLabel.ForeColor = $global:Pal.TextMuted
        $global:ProgressBar.Percent = -1
        $global:StatusLabel.Text = ''
        foreach ($k in @($global:NavItems.Keys)) { $global:NavItems[$k].Enabled = $true }
        foreach ($c in $global:HeaderActions.Controls) { $c.Enabled = $true }
    }
    & $global:LayoutStatusBar
}

# Sobreposição: percentual no título e a última mensagem da tarefa (chamado pelo pump)
function Set-TIBusyDetail {
    param([string]$Text = '', [int]$Percent = -1)
    if (-not $global:TI.Busy -or -not $global:Overlay) { return }
    try {
        if ($Percent -ge 0) { $global:OverlayPercent = [Math]::Min(100, $Percent) }
        if (-not $global:TIAsync.Cancelled) {
            $title = [string]$global:TIAsync.Name
            if ($global:OverlayPercent -ge 0) { $title = '{0} ({1}%)' -f $title, $global:OverlayPercent }
            $global:OverlayLabel.Text = $title
        }
        if ($Text) {
            $t = ($Text -replace '\s+', ' ').Trim()
            if ($t.Length -gt 140) { $t = $t.Substring(0, 137) + '...' }
            if ($t) { $global:OverlayHint.Text = $t }
        }
        & $global:LayoutOverlay
    } catch { }
}

# ---------------------------------------------------------------------
# Console recolhível (F12 ou Ctrl+'). A altura é lembrada entre sessões
# (ConsoleHeight no config.json; 0 = 30% da área).
# ---------------------------------------------------------------------
function Get-TIConsoleHeight {
    if (-not $global:Split) { return 0 }
    if ($global:ConsoleCollapsed) { return [int]$global:ConsoleSavedHeight }
    $h = $global:Split.Height - $global:Split.SplitterDistance - $global:Split.SplitterWidth
    return [int][Math]::Max(0, $h)
}

function Set-TIConsoleHeight {
    param([int]$Height = 0)
    $sp = $global:Split
    if (-not $sp -or $sp.Panel2Collapsed) { return }
    $total = $sp.Height
    if ($total -le ($sp.Panel1MinSize + $sp.Panel2MinSize + $sp.SplitterWidth)) { return }
    if ($Height -le 0) { $Height = [int]($total * 0.30) }
    $max = $total - $sp.Panel1MinSize - $sp.SplitterWidth
    $Height = [int][Math]::Max($sp.Panel2MinSize, [Math]::Min($Height, $max))
    try { $sp.SplitterDistance = $total - $Height - $sp.SplitterWidth } catch { }
}

function Toggle-TIConsole {
    if (-not $global:Split) { return }
    if ($global:ConsoleCollapsed) {
        $global:Split.Panel2Collapsed = $false
        $global:ConsoleCollapsed = $false
        Set-TIConsoleHeight $global:ConsoleSavedHeight
        if ($global:LogBox) { $global:LogBox.ScrollToCaret() }
    } else {
        $global:ConsoleSavedHeight = Get-TIConsoleHeight
        $global:Split.Panel2Collapsed = $true
        $global:ConsoleCollapsed = $true
    }
}

# Antes do Shown: recolhe se pedido; a altura salva vale no Shown ou no primeiro F12
function Apply-TIConsolePreference {
    $saved = 0
    try { $saved = [int]$global:TI.Settings.ConsoleHeight } catch { }
    $global:ConsoleSavedHeight = [Math]::Max(0, $saved)
    if ($global:TI.Settings.CompactConsole -and -not $global:ConsoleCollapsed) {
        $global:Split.Panel2Collapsed = $true
        $global:ConsoleCollapsed = $true
    }
}

# ---------------------------------------------------------------------
# Elevação: o selo "Sem elevação" reabre o app como administrador
# ---------------------------------------------------------------------
function Restart-TIElevated {
    if ($global:TI.Busy) { Show-TIToast -Text 'Espere a tarefa atual terminar.' -Type 'Warn'; return }
    $ok = Show-TIConfirm -Title 'Reabrir como administrador' -Icon 'Shield' -Style 'Primary' `
            -Message "O TI Suite vai fechar e abrir de novo com permissão de administrador. O Windows mostra a confirmação (UAC) antes." `
            -ConfirmText 'Reabrir'
    if (-not $ok) { return }
    $proc = $null
    try {
        # Get-TIElevatedArgs (TI-Suite.ps1): caminho UNC se a pasta estiver numa unidade mapeada;
        # -Reopen faz a nova janela esperar esta fechar (instância única)
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList (Get-TIElevatedArgs -Reopen) -PassThru -ErrorAction Stop
    } catch {
        Show-TIToast -Text 'A elevação foi cancelada no Windows (UAC).' -Type 'Warn'
        return
    }
    # Se a cópia elevada cair logo (ex.: pasta que o administrador não enxerga), esta continua aberta
    $oldCursor = $global:Form.Cursor
    $global:Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $global:StatusLabel.Text = 'Reabrindo como administrador...'
    $global:StatusLabel.Refresh()
    $started = Test-TIElevatedStart $proc -TimeoutMs 2500
    $global:Form.Cursor = $oldCursor
    $global:StatusLabel.Text = ''
    if (-not $started) {
        Show-TIToast -Text ('O TI Suite não abriu como administrador (código {0}). Copie a pasta para este computador ou para o pendrive.' -f $proc.ExitCode) -Type 'Error' -Duration 7000
        return
    }
    $global:Form.Close()
}

function Invoke-TIBadgeClick {
    if ($global:TI.Elevated) {
        Show-TIToast -Text 'Aberto como administrador: todas as ações estão liberadas.' -Type 'Success'
    } else {
        Restart-TIElevated
    }
}

# ---------------------------------------------------------------------
# Quem roda o app (operador) e quem está conectado ao Windows (sessão).
# Com a senha de outro administrador no UAC, são contas diferentes: as áreas
# usam $global:TI.SessionUser / SessionUserSid para proteger a conta conectada.
# ---------------------------------------------------------------------
function Get-TIOperatorName {
    try { return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name } catch { return $env:USERNAME }
}

function Get-TISessionUser {
    $name = ''
    $sid = ''
    $sess = -1
    try { $sess = [System.Diagnostics.Process]::GetCurrentProcess().SessionId } catch { }
    # 1. Dono do explorer.exe desta sessão (vale também para área de trabalho remota)
    if ($sess -ge 0) {
        try {
            $ex = @(Get-CimInstance -ClassName Win32_Process -Filter ("Name='explorer.exe' AND SessionId={0}" -f $sess) -ErrorAction Stop |
                    Sort-Object CreationDate) | Select-Object -First 1
            if ($ex) {
                $o = Invoke-CimMethod -InputObject $ex -MethodName GetOwner -ErrorAction Stop
                if ($o.ReturnValue -eq 0 -and $o.User) {
                    $name = if ($o.Domain) { '{0}\{1}' -f $o.Domain, $o.User } else { [string]$o.User }
                }
                $s = Invoke-CimMethod -InputObject $ex -MethodName GetOwnerSid -ErrorAction Stop
                if ($s.ReturnValue -eq 0 -and $s.Sid) { $sid = [string]$s.Sid }
            }
        } catch { }
    }
    # 2. Usuário do console (Win32_ComputerSystem)
    if (-not $name) {
        try {
            $u = [string](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
            if ($u) { $name = $u }
        } catch { }
    }
    if ($name -and -not $sid) {
        try { $sid = (New-Object System.Security.Principal.NTAccount($name)).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { }
    }
    # 3. Sem explorer (ex.: sessão sem área de trabalho): o próprio processo
    if (-not $name) {
        try {
            $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $name = $id.Name
            $sid = $id.User.Value
        } catch { $name = $env:USERNAME }
    }
    return [pscustomobject]@{ Name = $name; Sid = $sid }
}

# ---------------------------------------------------------------------
# Pasta de dados (pendrive): somente leitura ou quase cheia -> aviso na abertura
# ---------------------------------------------------------------------
function Test-TIDataFolder {
    $global:TIDataReadOnly = $false
    $global:TIStartupWarning = $null
    $dir = Split-Path -Parent $global:TILogPath
    $where = if ($global:TIPortable) { 'A pasta do TI Suite (pendrive)' } else { 'A pasta de dados do TI Suite' }
    $msg = $null
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
        $probe = Join-Path $dir ('.gravacao-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText($probe, 'ok')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    } catch {
        $global:TIDataReadOnly = $true
        $msg = ('{0} não aceita gravação (protegida contra gravação ou cheia): configurações, auditoria e inventário não serão gravados.' -f $where)
    }
    if (-not $msg) {
        try {
            $rootPath = [System.IO.Path]::GetPathRoot($dir)
            if ($rootPath -match '^[A-Za-z]:\\?$') {
                $free = (New-Object System.IO.DriveInfo($rootPath)).AvailableFreeSpace
                if ($free -lt 50MB) {
                    $disk = if ($global:TIPortable) { 'O pendrive do TI Suite' } else { ('O disco {0}' -f $rootPath.Substring(0, 2)) }
                    $msg = ('{0} está quase cheio ({1} livres): a auditoria e o inventário podem deixar de ser gravados.' -f $disk, (Format-TIBytes $free))
                }
            }
        } catch { }
    }
    if ($msg) {
        Write-TILog -Level 'Warn' -Message $msg
        $global:TIStartupWarning = $msg
    }
}

# ---------------------------------------------------------------------
# Configurações. Tudo é aplicado só no "Salvar" (Enter também salva);
# Esc ou X descartam as mudanças.
# ---------------------------------------------------------------------
function Open-TILogFolder {
    $dir = Split-Path -Parent $global:TILogPath
    try { if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } } catch { }
    if (Test-Path -LiteralPath $dir) {
        try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $dir) }
        catch { Show-TIToast -Text ('Não foi possível abrir a pasta: {0}' -f $dir) -Type 'Error' }
    } else {
        Show-TIToast -Text 'A pasta de logs não existe e não pôde ser criada (pasta somente leitura?).' -Type 'Warn'
    }
}

function Show-TISettings {
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition = 'CenterParent'
    $f.BackColor = $global:Pal.CardAlt
    $f.ShowInTaskbar = $false
    $f.KeyPreview = $true
    $f.AutoScaleMode = 'None'
    $f.Text = 'Configurações'

    $w = 540
    $f.Width = $w
    $padX = 22
    # Estado do diálogo no Tag: os handlers usam $this.FindForm().Tag
    $state = @{ Switches = @{}; Pw = $null; Ok = $null }
    $f.Tag = $state

    $ico = New-TIGlyph -Icon 'Settings' -Size 17 -Color $global:Pal.Primary
    $ico.Location = New-Object System.Drawing.Point($padX, 19)
    $f.Controls.Add($ico)

    $t = New-TILabel -Text 'Configurações' -Size 12 -Bold
    $t.Location = New-Object System.Drawing.Point(50, 17)
    $f.Controls.Add($t)

    $btnX = New-TIGlyphButton -Icon 'Close' -Tip 'Fechar sem salvar (Esc)' -Size 34
    $btnX.Location = New-Object System.Drawing.Point(($w - 46), 12)
    $btnX.TabStop = $false
    $btnX.Add_Click({ $fm = $this.FindForm(); $fm.DialogResult = 'Cancel'; $fm.Close() })
    $f.Controls.Add($btnX)
    $btnX.BringToFront()

    $y = 64
    $rows = @(
        @{ Key = 'CompactConsole'; Title = 'Iniciar com o console recolhido'
           Desc = 'Mais espaço para as ferramentas. Mostre ou oculte com F12.' },
        @{ Key = 'ForceChangeOnLogon'; Title = 'Exigir troca de senha no próximo login'
           Desc = 'Na senha padrão em lote, cada aluno define a própria senha ao entrar.' },
        @{ Key = 'CrispText'; Title = 'Texto nítido em telas com zoom (125% ou mais)'
           Desc = 'Pode desalinhar o layout em notebooks com escala. Vale a partir da próxima abertura.' }
    )
    foreach ($r in $rows) {
        $lbl = New-TILabel -Text $r.Title -Size 9.5 -Bold
        $lbl.Location = New-Object System.Drawing.Point($padX, $y)
        $f.Controls.Add($lbl)

        $d = New-TILabel -Text $r.Desc -Size 8 -Muted
        $d.Location = New-Object System.Drawing.Point($padX, ($y + 20))
        $d.MaximumSize = New-Object System.Drawing.Size(($w - 110), 0)
        $d.AutoSize = $true
        $f.Controls.Add($d)

        $sw = New-Object TISuite.ToggleSwitch
        $sw.Location = New-Object System.Drawing.Point(($w - 62), ($y + 4))
        $sw.AccessibleName = $r.Title
        $sw.Checked = [bool]$global:TI.Settings[$r.Key]
        $f.Controls.Add($sw)
        $state.Switches[$r.Key] = $sw

        $hRow = [Math]::Max(46, ($d.PreferredHeight + 24))
        $y += $hRow + 8
    }

    $pwLbl = New-TILabel -Text 'Senha padrão da escola (só nesta sessão)' -Size 9.5 -Bold
    $pwLbl.Location = New-Object System.Drawing.Point($padX, $y)
    $f.Controls.Add($pwLbl)

    $pwDesc = New-TILabel -Text 'Usada na senha padrão em lote das contas de aluno. Fica só na memória: nunca é gravada no pendrive.' -Size 8 -Muted
    $pwDesc.Location = New-Object System.Drawing.Point($padX, ($y + 20))
    $pwDesc.MaximumSize = New-Object System.Drawing.Size(($w - $padX * 2), 0)
    $pwDesc.AutoSize = $true
    $f.Controls.Add($pwDesc)

    $pwBox = New-Object System.Windows.Forms.TextBox
    $pwBox.Location = New-Object System.Drawing.Point($padX, ($y + $pwDesc.PreferredHeight + 28))
    $pwBox.Size = New-Object System.Drawing.Size(($w - $padX * 2), 28)
    $pwBox.BackColor = $global:Pal.Bg
    $pwBox.ForeColor = $global:Pal.TextMain
    $pwBox.BorderStyle = 'FixedSingle'
    $pwBox.Font = New-TIFont 10
    $pwBox.UseSystemPasswordChar = $true
    $pwBox.Text = [string]$global:TI.Settings['SchoolPassword']
    $f.Controls.Add($pwBox)
    $state.Pw = $pwBox

    $y = $pwBox.Bottom + 18

    # Onde fica cada coisa e quem está usando
    $modeLine = if ($global:TIPortable) { 'Modo portátil (USB)' } else { 'Modo instalado' }
    $session = if ($global:TI.SessionUser) { [string]$global:TI.SessionUser } else { 'não identificada' }
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add(('{0}   |   PC: {1}' -f $modeLine, $env:COMPUTERNAME))
    [void]$lines.Add(('Operador (rodando o TI Suite): {0}' -f (Get-TIOperatorName)))
    [void]$lines.Add(('Sessão (conectado ao Windows): {0}' -f $session))
    [void]$lines.Add(('Configuração: {0}' -f $global:TI.SettingsPath))
    [void]$lines.Add(('Logs e auditoria: {0}' -f (Split-Path -Parent $global:TILogPath)))
    if (Get-Command Get-TIInventoryPath -ErrorAction SilentlyContinue) {
        try { [void]$lines.Add(('Inventário: {0}' -f (Get-TIInventoryPath))) } catch { }
    }
    $info = New-TILabel -Text ($lines -join "`n") -Size 8 -Dim
    $info.Location = New-Object System.Drawing.Point($padX, $y)
    $info.MaximumSize = New-Object System.Drawing.Size(($w - $padX * 2), 0)
    $info.AutoSize = $true
    $f.Controls.Add($info)
    $y += $info.PreferredHeight + 10

    $btnLogs = New-TIButton -Text 'Abrir pasta de logs' -Style 'Outline' -Icon 'FolderOpen' -Width 170 -Height 32 `
                            -Tip 'audit.csv, exceptions.log e os registros do console'
    $btnLogs.Location = New-Object System.Drawing.Point($padX, $y)
    $btnLogs.Add_Click({ Open-TILogFolder })
    $f.Controls.Add($btnLogs)
    $y = $btnLogs.Bottom + 16

    $div = New-Object System.Windows.Forms.Panel
    $div.BackColor = $global:Pal.BorderSoft
    $div.Location = New-Object System.Drawing.Point(0, $y)
    $div.Size = New-Object System.Drawing.Size($w, 1)
    $f.Controls.Add($div)

    $btnReset = New-TIButton -Text 'Restaurar padrões' -Style 'Ghost' -Width 160 -Height 38
    $btnReset.Location = New-Object System.Drawing.Point($padX, ($y + 14))
    $btnReset.Add_Click({
        $global:TI.Settings.CompactConsole = $true
        $global:TI.Settings.ForceChangeOnLogon = $false
        $global:TI.Settings.CrispText = $false
        $global:TI.Settings.SchoolPassword = ''
        if (Save-TISettings) { Show-TIToast -Text 'Configurações restauradas.' -Type 'Success' }
        $fm = $this.FindForm(); $fm.DialogResult = 'OK'; $fm.Close()
    })

    $btnOk = New-TIButton -Text 'Salvar' -Style 'Primary' -Width 140 -Height 38
    $btnOk.Location = New-Object System.Drawing.Point(($w - $btnOk.Width - $padX), ($y + 14))
    $btnOk.Add_Click({
        $fm = $this.FindForm()
        $st = $fm.Tag
        foreach ($k in @($st.Switches.Keys)) { $global:TI.Settings[$k] = [bool]$st.Switches[$k].Checked }
        $global:TI.Settings['SchoolPassword'] = $st.Pw.Text
        if (Save-TISettings) { Show-TIToast -Text 'Configurações salvas.' -Type 'Success' }
        $fm.DialogResult = 'OK'
        $fm.Close()
    })
    $state.Ok = $btnOk
    $f.Controls.Add($btnReset)
    $f.Controls.Add($btnOk)

    $f.ClientSize = New-Object System.Drawing.Size($w, ($btnOk.Bottom + 16))
    $f.Add_KeyDown({
        if ($_.KeyCode -eq 'Escape') {
            $this.DialogResult = 'Cancel'; $this.Close()
        } elseif ($_.KeyCode -eq 'Enter' -and -not ($this.ActiveControl -is [TISuite.PremiumButton])) {
            # Enter na senha (ou num interruptor) salva; num botão, vale o botão com foco
            $_.SuppressKeyPress = $true
            $this.Tag.Ok.PerformClick()
        }
    })
    $f.Add_MouseDown({ if ($_.Button -eq 'Left') { [TISuite.Native]::DragWindow($this) } })
    Add-TIDialogFrame $f
    [void][TISuite.Native]::RoundWindow($f)
    [void]$f.ShowDialog($global:Form)
    $f.Dispose()
}

# ---------------------------------------------------------------------
# Atalhos do teclado (F1)
# ---------------------------------------------------------------------
function New-TIShortcutsForm {
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition = 'CenterParent'
    $f.BackColor = $global:Pal.CardAlt
    $f.ShowInTaskbar = $false
    $f.KeyPreview = $true
    $f.AutoScaleMode = 'None'
    $f.Text = 'Atalhos do teclado'

    $w = 500
    $f.Width = $w
    $padX = 22

    $ico = New-TIGlyph -Icon 'Help' -Size 17 -Color $global:Pal.Primary
    $ico.Location = New-Object System.Drawing.Point($padX, 19)
    $f.Controls.Add($ico)

    $t = New-TILabel -Text 'Atalhos do teclado' -Size 12 -Bold
    $t.Location = New-Object System.Drawing.Point(50, 17)
    $f.Controls.Add($t)

    $btnX = New-TIGlyphButton -Icon 'Close' -Tip 'Fechar (Esc)' -Size 34
    $btnX.Location = New-Object System.Drawing.Point(($w - 46), 12)
    $btnX.TabStop = $false
    $btnX.Add_Click({ $this.FindForm().Close() })
    $f.Controls.Add($btnX)

    $nAreas = [Math]::Max(1, [Math]::Min(9, @($global:TI.Workspaces).Count))
    $rows = @(
        @(('Ctrl+1 a Ctrl+{0}' -f $nAreas), 'Abrir as áreas, na ordem da barra lateral'),
        @('Ctrl+F', 'Buscar ferramenta (com ou sem acento); Enter abre a primeira encontrada'),
        @('Ctrl+R ou F5', 'Atualizar a área aberta'),
        @("F12 ou Ctrl+'", 'Mostrar ou ocultar o console'),
        @('Ctrl+L', 'Limpar o console'),
        @('Ctrl+E', 'Exportar o console'),
        @('Setas', 'Andar pela barra lateral (Enter abre a área)'),
        @('Esc', 'Fechar a janela aberta ou limpar a busca'),
        @('F1', 'Mostrar esta lista')
    )
    $y = 64
    foreach ($r in $rows) {
        $k = New-TILabel -Text $r[0] -Size 9 -Bold -Color $global:Pal.Primary
        $k.Location = New-Object System.Drawing.Point($padX, $y)
        $f.Controls.Add($k)
        $d = New-TILabel -Text $r[1] -Size 9
        $d.MaximumSize = New-Object System.Drawing.Size(($w - $padX - 150 - $padX), 0)
        $d.AutoSize = $true
        $d.Location = New-Object System.Drawing.Point(($padX + 150), $y)
        $f.Controls.Add($d)
        $y += [Math]::Max(26, $d.PreferredHeight + 10)
    }

    $y += 6
    $div = New-Object System.Windows.Forms.Panel
    $div.BackColor = $global:Pal.BorderSoft
    $div.Location = New-Object System.Drawing.Point(0, $y)
    $div.Size = New-Object System.Drawing.Size($w, 1)
    $f.Controls.Add($div)

    $btnOk = New-TIButton -Text 'Fechar' -Style 'Primary' -Width 120 -Height 38
    $btnOk.Location = New-Object System.Drawing.Point(($w - $btnOk.Width - $padX), ($y + 14))
    $btnOk.Add_Click({ $this.FindForm().Close() })
    $f.Controls.Add($btnOk)

    $f.ClientSize = New-Object System.Drawing.Size($w, ($btnOk.Bottom + 16))
    $f.Add_KeyDown({
        if ($_.KeyCode -in @('Escape', 'Enter', 'F1')) { $_.SuppressKeyPress = $true; $this.Close() }
    })
    $f.Add_MouseDown({ if ($_.Button -eq 'Left') { [TISuite.Native]::DragWindow($this) } })
    Add-TIDialogFrame $f
    return $f
}

function Show-TIShortcuts {
    $f = New-TIShortcutsForm
    [void][TISuite.Native]::RoundWindow($f)
    [void]$f.ShowDialog($global:Form)
    $f.Dispose()
}

# ---------------------------------------------------------------------
# Atalhos de teclado e comportamento da janela
# ---------------------------------------------------------------------
function Invoke-TIShortcutKey {
    param([System.Windows.Forms.KeyEventArgs]$Key)
    $k = $Key
    if ($k.Control -and -not $k.Alt) {
        $done = $true
        switch ($k.KeyCode) {
            'L'        { Reset-TILog }
            'F'        { [void]$global:SearchBox.Focus(); $global:SearchBox.SelectAll() }
            'E'        { Export-TILog }
            'R'        { Invoke-TIRefreshActive }
            'Oemtilde' { Toggle-TIConsole }
            default    { $done = $false }
        }
        $code = [int]$k.KeyCode
        if (($code -ge 49 -and $code -le 57) -or ($code -ge 97 -and $code -le 105)) {
            $n = if ($code -le 57) { $code - 48 } else { $code - 96 }
            if ($n -le $global:TI.Workspaces.Count -and -not $global:TI.Busy) {
                Switch-TIWorkspace -Id $global:TI.Workspaces[$n - 1].Id
            }
            $done = $true
        }
        if ($done) { $k.Handled = $true; $k.SuppressKeyPress = $true }
    } elseif (-not $k.Control -and -not $k.Alt -and -not $k.Shift) {
        if ($k.KeyCode -eq 'F12') { Toggle-TIConsole; $k.Handled = $true }
        elseif ($k.KeyCode -eq 'F5') { Invoke-TIRefreshActive; $k.Handled = $true }
        elseif ($k.KeyCode -eq 'F1') { $k.Handled = $true; $k.SuppressKeyPress = $true; Show-TIShortcuts }
    }
}
$global:Form.Add_KeyDown({ Invoke-TIShortcutKey -Key $_ })

# Botão Maximizar/Restaurar acompanha o estado da janela
function Update-TIMaxButton {
    if (-not $global:BtnMax) { return }
    try {
        $isMax = ($global:Form.WindowState -eq 'Maximized')
        $tip = if ($isMax) { 'Restaurar' } else { 'Maximizar' }
        $global:BtnMax.Glyph = Get-TIGlyph $(if ($isMax) { 'Restore' } else { 'Max' })
        $global:BtnMax.AccessibleName = $tip
        $global:TITip.SetToolTip($global:BtnMax, $tip)
    } catch { }
}

# Tamanho inicial dentro da área útil do monitor do mouse (1366x768 cabe inteiro);
# tela pequena demais ou "WindowMaximized" salvo: abre maximizada.
function Set-TIInitialBounds {
    $fm = $global:Form
    try {
        $wa = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
        $minW = [Math]::Min(1040, $wa.Width)
        $minH = [Math]::Min(640, $wa.Height)
        $fm.MinimumSize = New-Object System.Drawing.Size($minW, $minH)
        $w = [Math]::Min(1252, $wa.Width - 24)
        $h = [Math]::Min(792, $wa.Height - 24)
        $small = ($w -lt 1040 -or $h -lt 640)
        $w = [Math]::Max($minW, $w)
        $h = [Math]::Max($minH, $h)
        $fm.StartPosition = 'Manual'
        $fm.Bounds = New-Object System.Drawing.Rectangle(($wa.X + [int](($wa.Width - $w) / 2)), ($wa.Y + [int](($wa.Height - $h) / 2)), $w, $h)
        if ($small -or $global:TI.Settings.WindowMaximized) { $fm.WindowState = 'Maximized' }
    } catch { }
}

# Lembra janela maximizada e altura do console (só grava se mudou)
function Save-TIWindowState {
    try {
        if ($global:Form.WindowState -eq 'Minimized') { return }
        $changed = $false
        $isMax = ($global:Form.WindowState -eq 'Maximized')
        if ([bool]$global:TI.Settings.WindowMaximized -ne $isMax) { $global:TI.Settings.WindowMaximized = $isMax; $changed = $true }
        $ch = Get-TIConsoleHeight
        if ($ch -gt 0 -and [int]$global:TI.Settings.ConsoleHeight -ne $ch) { $global:TI.Settings.ConsoleHeight = $ch; $changed = $true }
        if ($changed -and -not $global:TIDataReadOnly) { [void](Save-TISettings) }
    } catch { }
}

# Pode fechar? Com tarefa rodando pergunta (menos quando o Windows está desligando),
# interrompe e espera a tarefa parar, gravando 'INTERROMPIDA' na auditoria.
function Test-TICanClose {
    param([System.Windows.Forms.CloseReason]$Reason = [System.Windows.Forms.CloseReason]::UserClosing)
    if (-not $global:TI.Busy) { return $true }
    $shutdown = ($Reason -eq [System.Windows.Forms.CloseReason]::WindowsShutDown -or
                 $Reason -eq [System.Windows.Forms.CloseReason]::TaskManagerClosing)
    if (-not $shutdown) {
        $ok = Show-TIConfirm -Title 'Tarefa em andamento' `
                             -Message 'Há uma tarefa em andamento. Fechar agora interrompe a tarefa no meio.' `
                             -ConfirmText 'Fechar mesmo assim' -Style 'Danger' -Icon 'Warning'
        if (-not $ok) { return $false }
        if (-not $global:TI.Busy) { return $true }   # terminou enquanto a pergunta estava aberta
    }
    $why = if ($Reason -eq [System.Windows.Forms.CloseReason]::WindowsShutDown) { 'Windows desligando' } else { 'app fechado durante a tarefa' }
    try { Stop-TIAsync -ForExit -Reason $why -TimeoutSeconds $(if ($shutdown) { 4 } else { 10 }) } catch { }
    return $true
}

$global:Form.Add_Resize({
    $fm = $global:Form
    if ($null -eq $fm) { return }
    try {
        # Maximizada: sem recorte. Minimizada: não mexe (o recorte do tamanho
        # minimizado deixava a janela invisível ao restaurar).
        if ($fm.WindowState -eq 'Maximized') { $fm.Region = $null }
        elseif ($fm.WindowState -eq 'Normal' -and $global:TIShown -and -not $global:DwmRounded) { [TISuite.Native]::ApplyRegion($fm, 10) }
    } catch { }
    Update-TIMaxButton
})

$global:Form.Add_Shown({
    $fm = $global:Form
    try { $global:DwmRounded = [TISuite.Native]::RoundWindow($fm) } catch { $global:DwmRounded = $false }
    try { if (-not $global:DwmRounded -and $fm.WindowState -eq 'Normal') { [TISuite.Native]::ApplyRegion($fm, 10) } } catch { }
    $global:TIShown = $true
    & $global:LayoutStatusBar
    & $global:LayoutOverlay
    if (-not $global:ConsoleCollapsed) { Set-TIConsoleHeight $global:ConsoleSavedHeight }
    Update-TIMaxButton
    if ($global:TIStartupWarning) {
        Show-TIToast -Text $global:TIStartupWarning -Type 'Warn' -Duration 7000
        $global:TIStartupWarning = $null
    }
})

$global:Form.Add_FormClosing({
    if (-not (Test-TICanClose -Reason $_.CloseReason)) { $_.Cancel = $true; return }
    Save-TIWindowState
    try { [TISuite.Native]::ClearTaskbarProgress($global:Form) } catch { }
})

# ---------------------------------------------------------------------
# Inicialização chamada após o registro das áreas de trabalho
# ---------------------------------------------------------------------
function Update-TIElevationBadge {
    $col = if ($global:TI.Elevated) { $global:Pal.Success } else { $global:Pal.Warning }
    $txt = if ($global:TI.Elevated) { 'Administrador' } else { 'Sem elevação' }
    $tip = if ($global:TI.Elevated) { 'Aberto como administrador: todas as ações liberadas' } else { 'Clique para reabrir como administrador' }
    $global:AdminBadgeIcon.ForeColor = $col
    $global:AdminBadgeText.ForeColor = $col
    $global:AdminBadgeText.Text = $txt
    foreach ($c in @($global:AdminBadge, $global:AdminBadgeIcon, $global:AdminBadgeText)) { $global:TITip.SetToolTip($c, $tip) }
}

function Start-TIApp {
    $global:TI.Elevated = Test-TIIsAdmin
    $su = Get-TISessionUser
    $global:TI.SessionUser = [string]$su.Name
    $global:TI.SessionUserSid = [string]$su.Sid
    Update-TIElevationBadge
    Build-TISidebar

    Write-TILog -Level 'Info' -Message ("TI Suite v{0} aberto em {1}." -f $global:TI.Version, $env:COMPUTERNAME)
    if ($global:TI.Elevated) {
        Write-TILog -Level 'Success' -Message 'Aberto como administrador: todas as ações liberadas.'
    } else {
        Write-TILog -Level 'Warn' -Message 'Sem elevação: as ações administrativas ficam bloqueadas. Clique no selo "Sem elevação" para reabrir como administrador.'
    }
    $op = Get-TIOperatorName
    if ($global:TI.SessionUser -and $global:TI.SessionUser -ne $op) {
        Write-TILog -Level 'Info' -Message ("Conectado ao Windows: {0} (o TI Suite roda como {1})." -f $global:TI.SessionUser, $op)
    } else {
        Write-TILog -Level 'Debug' -Message ("Sessão do Windows: {0} ({1})." -f $global:TI.SessionUser, $global:TI.SessionUserSid)
    }
    Write-TILog -Level 'Debug' -Message ("Controles visuais: {0}." -f $global:TIControlsSource)
    if ($global:TIControlsError) {
        Write-TILog -Level 'Debug' -Message ("A DLL dos controles não foi usada: {0}" -f $global:TIControlsError)
    }
    if ($global:TIPortable) {
        Write-TILog -Level 'Info' -Message 'Modo portátil (USB): configuração, logs e inventário ficam na pasta do aplicativo.'
    }
    Test-TIDataFolder

    if ($global:TI.Workspaces.Count -gt 0) {
        Switch-TIWorkspace -Id $global:TI.Workspaces[0].Id
    }
    Apply-TIConsolePreference
    Set-TIInitialBounds
}
