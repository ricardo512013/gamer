# =====================================================================
# 05-SHELL.ps1 - Janela principal, barra lateral, cabeçalho, status e navegação
# Código de nível superior: os handlers usam variáveis de escopo de
# script, que permanecem vivas durante toda a sessão.
# =====================================================================

$global:NavItems = @{}
$global:WorkspacePanels = @{}
$global:DwmRounded = $false

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
# Janela principal
# ---------------------------------------------------------------------
$global:Form = New-Object System.Windows.Forms.Form
$global:Form.Text = 'TI Suite'
$global:Form.ClientSize = New-Object System.Drawing.Size(1240, 780)
$global:Form.MinimumSize = New-Object System.Drawing.Size(1040, 640)
$global:Form.StartPosition = 'CenterScreen'
$global:Form.FormBorderStyle = 'None'
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
$global:Root.Add_Paint({
    $evt = $_
    if ($null -eq $evt -or $null -eq $evt.Graphics) { return }
    $top = $global:Pal.Bg
    $bottom = $global:Pal.Sidebar
    $rect = New-Object System.Drawing.Rectangle(0, 0, $global:Root.Width, $global:Root.Height)
    if ($rect.Width -le 0 -or $rect.Height -le 0) { return }
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bottom, 90)
    try { $evt.Graphics.FillRectangle($brush, $rect) } finally { $brush.Dispose() }
})

# ---------------------------------------------------------------------
# Barra lateral
# ---------------------------------------------------------------------
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Dock = 'Left'
$sidebar.Width = $global:Theme.SidebarWidth
$sidebar.BackColor = $global:Pal.Sidebar
$global:Sidebar = $sidebar

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
    $w = $nav.ClientSize.Width - $nav.Padding.Horizontal
    if ($w -gt 40) { foreach ($ctrl in $nav.Controls) { $ctrl.Width = $w } }
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
$brand.Add_MouseDoubleClick({ if ($_.Button -eq 'Left') { $global:Form.WindowState = $(if ($global:Form.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }) } })

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
$global:ConsoleSavedDistance = 0
$content.Controls.Add($split)
$global:Split = $split

$global:HostPanel = New-Object System.Windows.Forms.Panel
$global:HostPanel.Dock = 'Fill'
$global:HostPanel.BackColor = $global:Pal.Bg
$split.Panel1.Controls.Add($global:HostPanel)

# Sobreposição de "ocupado"
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

$ovHint = New-TILabel -Text 'Os detalhes aparecem no console (F12).' -Size 8.5 -Muted
$ovHint.AutoSize = $true
$overlay.Controls.Add($ovHint)

$global:LayoutOverlay = {
    $cx = [int]($overlay.ClientSize.Width / 2)
    $cy = [int]($overlay.ClientSize.Height / 2)
    $spin.Location = New-Object System.Drawing.Point(($cx - 22), ($cy - 58))
    $ovTitle.Location = New-Object System.Drawing.Point(($cx - [int]($ovTitle.PreferredWidth / 2)), ($cy + 4))
    $ovHint.Location = New-Object System.Drawing.Point(($cx - [int]($ovHint.PreferredWidth / 2)), ($cy + 30))
}
$overlay.Add_Resize({ & $global:LayoutOverlay })

# Console
$logRoot = Initialize-TILogPanel -Parent $split.Panel2

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

$btnLog = New-TIGlyphButton -Icon 'Terminal' -Tip 'Mostrar ou ocultar o console (F12)' -Size 44
$btnLog.Radius = 7
$btnLog.Add_Click({ Toggle-TIConsole })
$global:BtnConsole = $btnLog

$btnMin = New-TIGlyphButton -Icon 'Min' -Tip 'Minimizar' -Size 44
$btnMin.Radius = 7
$btnMin.Add_Click({ $global:Form.WindowState = 'Minimized' })

$btnMax = New-TIGlyphButton -Icon 'Max' -Tip 'Maximizar' -Size 44
$btnMax.Radius = 7
$btnMax.Add_Click({
    $global:Form.WindowState = $(if ($global:Form.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' })
})
$global:BtnMax = $btnMax

$btnClose = New-TIGlyphButton -Icon 'Close' -Tip 'Fechar' -Size 44
$btnClose.Radius = 7
$btnClose.Add_MouseEnter({ $btnClose.Style = 'Danger' })
$btnClose.Add_MouseLeave({ $btnClose.Style = 'Ghost' })
$btnClose.Add_Click({ $global:Form.Close() })

[void]$caption.Controls.Add($btnLog)
[void]$caption.Controls.Add($btnMin)
[void]$caption.Controls.Add($btnMax)
[void]$caption.Controls.Add($btnClose)

foreach ($c in @($global:Header, $hTitle, $hSub)) {
    $c.Add_MouseDown({ if ($_.Button -eq 'Left' -and $_.Clicks -eq 1) { [TISuite.Native]::DragWindow($global:Form) } })
    $c.Add_MouseDoubleClick({
        if ($_.Button -eq 'Left') {
            $global:Form.WindowState = $(if ($global:Form.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' })
        }
    })
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
    $global:CancelBtn.Location = New-Object System.Drawing.Point(($global:ClockLabel.Left - $global:CancelBtn.Width - 14), 3)
    $right = if ($global:CancelBtn.Visible) { $global:CancelBtn.Left - 12 } else { $global:ClockLabel.Left - 12 }
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
        $id = $ws.Id
        $item.Add_Click({ Switch-TIWorkspace -Id $id }.GetNewClosure())
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

function Set-TIBusy {
    param([bool]$Busy, [string]$Name = '')
    if ($Busy) {
        $global:OverlayLabel.Text = $Name
        $global:Overlay.Visible = $true
        $global:Overlay.BringToFront()
        & $global:LayoutOverlay
        $global:CancelBtn.Enabled = $true
        $global:CancelBtn.Visible = $true
        $global:ProgressWrap.Visible = $true
        $global:StateDot.FillColor = $global:Pal.Warning
        $global:StateDot.Invalidate()
        $global:StateLabel.Text = 'Executando'
        $global:StateLabel.ForeColor = $global:Pal.Warning
        $global:ProgressBar.Percent = -1
        $global:StatusLabel.Text = $Name
        foreach ($k in @($global:NavItems.Keys)) { $global:NavItems[$k].Enabled = $false }
        foreach ($c in $global:HeaderActions.Controls) { $c.Enabled = $false }
    } else {
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

# ---------------------------------------------------------------------
# Console recolhível (F12 ou Ctrl+')
# ---------------------------------------------------------------------
function Toggle-TIConsole {
    if (-not $global:Split) { return }
    if ($global:ConsoleCollapsed) {
        $global:Split.Panel2Collapsed = $false
        if ($global:ConsoleSavedDistance -gt 80) {
            try { $global:Split.SplitterDistance = $global:ConsoleSavedDistance } catch { }
        }
        $global:ConsoleCollapsed = $false
        if ($global:LogBox) { $global:LogBox.ScrollToCaret() }
    } else {
        $global:ConsoleSavedDistance = $global:Split.SplitterDistance
        $global:Split.Panel2Collapsed = $true
        $global:ConsoleCollapsed = $true
    }
}

function Apply-TIConsolePreference {
    if ($global:TI.Settings.CompactConsole -and -not $global:ConsoleCollapsed) {
        Toggle-TIConsole
    }
}

# ---------------------------------------------------------------------
# Elevação: o selo "Sem elevação" reabre o app como administrador
# ---------------------------------------------------------------------
function Restart-TIElevated {
    if ($global:TI.Busy) { Show-TIToast -Text 'Espere a tarefa atual terminar.' -Type 'Warn'; return }
    $ok = Show-TIConfirm -Title 'Reabrir como administrador' -Icon 'Shield' -Style 'Primary' -Force `
            -Message "O TI Suite vai fechar e abrir de novo com permissão de administrador. O Windows mostra a confirmação (UAC) antes." `
            -ConfirmText 'Reabrir'
    if (-not $ok) { return }
    $argLine = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $global:TIEntryPoint
    if ($global:TISkipIntegrity) { $argLine += ' -SkipIntegrity' }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argLine -ErrorAction Stop | Out-Null
        $global:TIRestarting = $true
        $global:Form.Close()
    } catch {
        Show-TIToast -Text 'A elevação foi cancelada no Windows (UAC).' -Type 'Warn'
    }
}

function Invoke-TIBadgeClick {
    if ($global:TI.Elevated) {
        Show-TIToast -Text 'Aberto como administrador: todas as ações estão liberadas.' -Type 'Success'
    } else {
        Restart-TIElevated
    }
}

# ---------------------------------------------------------------------
# Configurações
# ---------------------------------------------------------------------
function Show-TISettings {
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition = 'CenterParent'
    $f.BackColor = $global:Pal.CardAlt
    $f.ShowInTaskbar = $false
    $f.KeyPreview = $true
    $f.AutoScaleMode = 'None'
    $f.Text = 'Configurações'

    $w = 520
    $f.Width = $w
    $padX = 22

    $ico = New-TIGlyph -Icon 'Settings' -Size 17 -Color $global:Pal.Primary
    $ico.Location = New-Object System.Drawing.Point($padX, 19)
    $f.Controls.Add($ico)

    $t = New-TILabel -Text 'Configurações' -Size 12 -Bold
    $t.Location = New-Object System.Drawing.Point(50, 17)
    $f.Controls.Add($t)

    $btnClose = New-TIGlyphButton -Icon 'Close' -Tip 'Fechar (Esc)' -Size 34
    $btnClose.Location = New-Object System.Drawing.Point(($w - 46), 12)
    $btnClose.TabStop = $false
    $btnClose.Add_Click({ $f.DialogResult = 'Cancel'; $f.Close() })
    $f.Controls.Add($btnClose)
    $btnClose.BringToFront()

    $y = 64
    $rows = @(
        @{ Key = 'SuppressConfirm'; Title = 'Não pedir confirmação em ações repetidas'
           Desc = 'Ações que apagam dados (perfis, programas, senhas) sempre pedem confirmação.' },
        @{ Key = 'ClearLogStart'; Title = 'Limpar o console ao iniciar'
           Desc = 'Começa cada sessão com o console vazio.' },
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
        $key = $r.Key
        $sw.Checked = [bool]$global:TI.Settings[$key]
        $sw.Add_CheckedChanged({
            $global:TI.Settings[$key] = $sw.Checked
            Save-TISettings
        }.GetNewClosure())
        $f.Controls.Add($sw)

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

    $y = $pwBox.Bottom + 18

    $modeLine = if ($global:TIPortable) { 'Modo portátil (USB)' } else { 'Modo instalado' }
    $info = New-TILabel -Text ('{0}   |   PC: {1}   |   Operador: {2}' -f $modeLine, $env:COMPUTERNAME, $env:USERNAME) -Size 8 -Dim
    $info.Location = New-Object System.Drawing.Point($padX, $y)
    $info.MaximumSize = New-Object System.Drawing.Size(($w - $padX * 2), 0)
    $info.AutoSize = $true
    $f.Controls.Add($info)
    $info2 = New-TILabel -Text ('Configuração: {0}' -f $global:TI.SettingsPath) -Size 8 -Dim
    $info2.Location = New-Object System.Drawing.Point($padX, ($y + 17))
    $info2.MaximumSize = New-Object System.Drawing.Size(($w - $padX * 2), 0)
    $info2.AutoSize = $true
    $f.Controls.Add($info2)
    $y += 17 + $info2.PreferredHeight + 16

    $div = New-Object System.Windows.Forms.Panel
    $div.BackColor = $global:Pal.BorderSoft
    $div.Location = New-Object System.Drawing.Point(0, $y)
    $div.Size = New-Object System.Drawing.Size($w, 1)
    $f.Controls.Add($div)

    $btnReset = New-TIButton -Text 'Restaurar padrões' -Style 'Ghost' -Width 160 -Height 38
    $btnReset.Location = New-Object System.Drawing.Point($padX, ($y + 14))
    $btnReset.Add_Click({
        $global:TI.Settings.SuppressConfirm = $false
        $global:TI.Settings.ClearLogStart = $false
        $global:TI.Settings.CompactConsole = $true
        $global:TI.Settings.ForceChangeOnLogon = $false
        $global:TI.Settings.CrispText = $false
        $global:TI.Settings.SchoolPassword = ''
        Save-TISettings
        Show-TIToast -Text 'Configurações restauradas.' -Type 'Success'
        $f.DialogResult = 'OK'; $f.Close()
    })

    $btnOk = New-TIButton -Text 'Salvar' -Style 'Primary' -Width 140 -Height 38
    $btnOk.Location = New-Object System.Drawing.Point(($w - $btnOk.Width - $padX), ($y + 14))
    $btnOk.Add_Click({
        $global:TI.Settings['SchoolPassword'] = $pwBox.Text
        Save-TISettings
        $f.DialogResult = 'OK'
        $f.Close()
    })
    $f.Controls.Add($btnReset)
    $f.Controls.Add($btnOk)

    $f.ClientSize = New-Object System.Drawing.Size($w, ($btnOk.Bottom + 16))
    $f.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $f.DialogResult = 'Cancel'; $f.Close() } })
    $f.Add_MouseDown({ if ($_.Button -eq 'Left') { [TISuite.Native]::DragWindow($f) } })
    Add-TIDialogFrame $f
    [void][TISuite.Native]::RoundWindow($f)
    [void]$f.ShowDialog($global:Form)
    $f.Dispose()
}

# ---------------------------------------------------------------------
# Atalhos de teclado e comportamento da janela
# ---------------------------------------------------------------------
$global:Form.Add_KeyDown({
    $k = $_
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
    }
})

$global:Form.Add_Resize({
    try {
        if ($null -eq $global:Form) { return }
        if ($global:Form.WindowState -eq 'Maximized') {
            $scr = [System.Windows.Forms.Screen]::FromControl($global:Form)
            if ($scr) { $global:Form.MaximizedBounds = $scr.WorkingArea }
            $global:Form.Region = $null
        } else {
            if (-not $global:DwmRounded) { [TISuite.Native]::ApplyRegion($global:Form, 10) }
        }
        if ($global:BtnMax) {
            $isMax = ($global:Form.WindowState -eq 'Maximized')
            $global:BtnMax.Glyph = Get-TIGlyph $(if ($isMax) { 'Restore' } else { 'Max' })
            $global:TITip.SetToolTip($global:BtnMax, $(if ($isMax) { 'Restaurar' } else { 'Maximizar' }))
        }
    } catch { }
})

$global:Form.Add_Shown({
    $global:DwmRounded = [TISuite.Native]::RoundWindow($global:Form)
    if (-not $global:DwmRounded) { [TISuite.Native]::ApplyRegion($global:Form, 10) }
    & $global:LayoutStatusBar
    & $global:LayoutOverlay
    try {
        $h = $global:Split.Height
        if ($h -gt 400 -and -not $global:ConsoleCollapsed) {
            $global:Split.SplitterDistance = [int]($h * 0.70)
        }
    } catch { }
})

$global:Form.Add_FormClosing({
    if ($global:TI.Busy) {
        $ok = Show-TIConfirm -Title 'Tarefa em andamento' `
                              -Message 'Há uma tarefa em andamento. Fechar agora interrompe a tarefa no meio.' `
                              -ConfirmText 'Fechar mesmo assim' -Style 'Danger' -Icon 'Warning' -Force
        if (-not $ok) { $_.Cancel = $true }
        else { try { Stop-TIAsync } catch { } }
    }
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
    Update-TIElevationBadge
    Build-TISidebar

    if ($global:TI.Settings.ClearLogStart) { $global:LogEntries.Clear(); $global:LogErrorCount = 0 }

    Write-TILog -Level 'Info' -Message ("TI Suite v{0} aberto em {1}." -f $global:TI.Version, $env:COMPUTERNAME)
    if ($global:TI.Elevated) {
        Write-TILog -Level 'Success' -Message 'Aberto como administrador: todas as ações liberadas.'
    } else {
        Write-TILog -Level 'Warn' -Message 'Sem elevação: as ações administrativas ficam bloqueadas. Clique no selo "Sem elevação" para reabrir como administrador.'
    }
    Write-TILog -Level 'Debug' -Message ("Controles visuais: {0}." -f $global:TIControlsSource)
    if ($global:TIPortable) {
        Write-TILog -Level 'Info' -Message 'Modo portátil (USB): configuração, logs e inventário ficam na pasta do aplicativo.'
    }

    if ($global:TI.Workspaces.Count -gt 0) {
        Switch-TIWorkspace -Id $global:TI.Workspaces[0].Id
    }
    Apply-TIConsolePreference
}
