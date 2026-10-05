# =====================================================================
# 01-THEME.ps1 - Design system: tokens, tipografia, ícones e componentes
# =====================================================================

# --- Tokens de cor (extraídos da paleta C# => fonte única de verdade) ---
$global:Pal = @{}
foreach ($f in ([TISuite.Pal].GetFields([System.Reflection.BindingFlags]'Public,Static'))) {
    $global:Pal[$f.Name] = $f.GetValue($null)
}

$global:Theme = @{
    SidebarWidth = 228
    HeaderHeight = 60
    StatusHeight = 28
    CardWidth    = 360
    CardGap      = 14
}

# --- Estado global da aplicação ------------------------------------------
if (-not $global:TI) {
    $global:TI = @{}
}
$global:TI.Version    = '1.5.0'
$global:TI.Elevated   = $false
$global:TI.Busy       = $false
$global:TI.ActiveId   = $null
$global:TI.Workspaces = New-Object System.Collections.ArrayList
# Portátil: definido em TI-Suite.ps1 (antes do carregamento deste módulo)

# Caminhos de config/log: o modo portátil usa a pasta do app
if ($global:TIPortable) {
    $global:TI.SettingsPath = Join-Path $global:TIRoot 'config.json'
    if (-not $global:TILogPath) { $global:TILogPath = Join-Path $global:TIRoot 'logs\exceptions.log' }
} else {
    if (-not $global:TI.SettingsPath) { $global:TI.SettingsPath = Join-Path $env:LOCALAPPDATA 'TI-Suite\config.json' }
    if (-not $global:TILogPath) { $global:TILogPath = Join-Path $env:LOCALAPPDATA 'TI-Suite\exceptions.log' }
}

# --- Tipografia ---
# Fontes compartilhadas (cache): ninguém descarta fonte de controle, então
# reaproveitar evita criar centenas de objetos GDI+ iguais. O .NET não falha
# com família inexistente (troca por Microsoft Sans Serif): confere o nome.
$global:TIFontCache = @{}
function New-TIFont {
    param([float]$Size = 9.5, [string]$Style = 'Regular', [string]$Family = 'Segoe UI')
    $key = '{0}|{1}|{2}' -f $Size, $Style, $Family
    if ($global:TIFontCache.ContainsKey($key)) { return $global:TIFontCache[$key] }
    $st = [System.Drawing.FontStyle]::$Style
    $fall = switch ($Family) {
        'Segoe MDL2 Assets' { @('Segoe MDL2 Assets', 'Segoe Fluent Icons', 'Segoe UI Symbol') }
        'Consolas'          { @('Consolas', 'Cascadia Mono', 'Courier New', 'Lucida Console') }
        default             { @($Family, 'Segoe UI', 'Tahoma', 'Arial') }
    }
    $font = $null
    foreach ($fam in $fall) {
        try {
            $f = New-Object System.Drawing.Font($fam, $Size, $st)
            if ($f.Name -eq $fam) { $font = $f; break }
            $f.Dispose()
        } catch { }
    }
    if (-not $font) { $font = New-Object System.Drawing.Font([System.Drawing.FontFamily]::GenericSansSerif, $Size, $st) }
    $global:TIFontCache[$key] = $font
    return $font
}

$global:Font = @{
    Small = New-TIFont 8.5
}

# --- Iconografia (Segoe MDL2 Assets; códigos conferidos na lista oficial) ---
$global:Icons = @{
    Home           = [char]0xE80F   # Home
    Clean          = [char]0xE74D   # Delete (lixeira)
    Erase          = [char]0xE75C   # EraseTool
    People         = [char]0xE716   # People
    Accounts       = [char]0xE910   # Accounts
    Globe          = [char]0xE774   # Globe
    Ethernet       = [char]0xE839   # Ethernet
    Wifi           = [char]0xE701   # Wifi
    Settings       = [char]0xE713   # Setting
    Search         = [char]0xE721   # Search
    Refresh        = [char]0xE72C   # Refresh
    Sync           = [char]0xE895   # Sync
    Close          = [char]0xE8BB   # ChromeClose
    Min            = [char]0xE921   # ChromeMinimize
    Max            = [char]0xE922   # ChromeMaximize
    Restore        = [char]0xE923   # ChromeRestore
    Check          = [char]0xE73E   # CheckMark
    Completed      = [char]0xE930   # Completed
    Error          = [char]0xE783   # Error
    Warning        = [char]0xE7BA   # Warning
    Info           = [char]0xE946   # Info
    Help           = [char]0xE897   # Help
    Shield         = [char]0xE83D   # DefenderApp (escudo)
    Terminal       = [char]0xE756   # CommandPrompt
    Copy           = [char]0xE8C8   # Copy
    Save           = [char]0xE74E   # Save
    Export         = [char]0xE792   # SaveAs
    Filter         = [char]0xE71C   # Filter
    Chevron        = [char]0xE76C   # ChevronRight
    ChevronDn      = [char]0xE70D   # ChevronDown
    Lock           = [char]0xE72E   # Lock
    Unlock         = [char]0xE785   # Unlock
    User           = [char]0xE77B   # Contact
    Admin          = [char]0xE7EF   # Admin
    UserOther      = [char]0xE7EE   # OtherUser
    Add            = [char]0xE710   # Add
    Remove         = [char]0xE738   # Remove
    Edit           = [char]0xE70F   # Edit
    Folder         = [char]0xE8B7   # Folder
    FolderOpen     = [char]0xE838   # FolderOpen
    Download       = [char]0xE896   # Download
    Monitor        = [char]0xE7F4   # TVMonitor
    PC             = [char]0xE977   # PC1
    Clock          = [char]0xE81C   # History
    Recent         = [char]0xE823   # Recent (relógio)
    TimeLanguage   = [char]0xE775   # TimeLanguage
    Power          = [char]0xE7E8   # PowerButton
    Usb            = [char]0xE88E   # USB
    Print          = [char]0xE749   # Print
    Package        = [char]0xE7B8   # Package
    Document       = [char]0xE8A5   # Document
    Report         = [char]0xE9F9   # ReportDocument
    Apps           = [char]0xE71D   # AllApps
    View           = [char]0xE890   # View
    Signal         = [char]0xE86D   # SignalBars2
    Stopwatch      = [char]0xE916   # Stopwatch
    Diagnostic     = [char]0xE9D9   # Diagnostic
    Health         = [char]0xE95E   # Health
    CheckList      = [char]0xE9D5   # CheckList
    Tag            = [char]0xE8EC   # Tag
    Update         = [char]0xE777   # UpdateRestore
    Repair         = [char]0xE90F   # Repair
    ArrowUp        = [char]0xE74A   # Up
    Battery        = [char]0xE83F   # Battery10 (cheia)
    Light          = [char]0xE793   # Light
    Undo           = [char]0xE7A7   # Undo
    Stop           = [char]0xE71A   # Stop
    Hamburger      = [char]0xE700   # GlobalNavigationButton
}

function Get-TIGlyph {
    param([string]$Name)
    if ($global:Icons.ContainsKey($Name)) { return $global:Icons[$Name] }
    return $global:Icons['Info']
}

# --- Dica flutuante (tooltip) no tema escuro -------------------------------
$global:TITip = New-Object System.Windows.Forms.ToolTip
$global:TITip.OwnerDraw = $true
$global:TITip.InitialDelay = 450
$global:TITip.ReshowDelay = 120
$global:TITip.AutoPopDelay = 9000
$global:TITip.Add_Popup({
    param($s, $e)
    try {
        $txt = $global:TITip.GetToolTip($e.AssociatedControl)
        $sz = [System.Windows.Forms.TextRenderer]::MeasureText($txt, $global:Font.Small)
        $e.ToolTipSize = New-Object System.Drawing.Size(($sz.Width + 18), ($sz.Height + 12))
    } catch { }
})
$global:TITip.Add_Draw({
    param($s, $e)
    try {
        $g = $e.Graphics
        $bg = New-Object System.Drawing.SolidBrush($global:Pal.CardAlt)
        $g.FillRectangle($bg, $e.Bounds)
        $bg.Dispose()
        $pen = New-Object System.Drawing.Pen($global:Pal.Border)
        $g.DrawRectangle($pen, 0, 0, ($e.Bounds.Width - 1), ($e.Bounds.Height - 1))
        $pen.Dispose()
        [System.Windows.Forms.TextRenderer]::DrawText($g, $e.ToolTipText, $global:Font.Small, $e.Bounds, $global:Pal.TextMain,
            ([System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter'))
    } catch { }
})

# --- Componentes básicos ---------------------------------------------------
function Get-TIToneColor {
    param([string]$Tone)
    switch ($Tone) {
        'ok'      { return $global:Pal.Success }
        'warn'    { return $global:Pal.Warning }
        'crit'    { return $global:Pal.Danger }
        'primary' { return $global:Pal.Primary }
        'muted'   { return $global:Pal.TextMuted }
        'dim'     { return $global:Pal.TextDim }
        'none'    { return $global:Pal.TextDim }
        default   { return $global:Pal.TextMain }
    }
}

function New-TIGlyph {
    param([string]$Icon, [float]$Size = 14, $Color = $null, [string]$Text = $null)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.AutoSize = $true
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.Font = New-TIFont $Size Regular 'Segoe MDL2 Assets'
    $lbl.ForeColor = if ($Color) { $Color } else { $global:Pal.TextMuted }
    $lbl.Text = if ($Text) { $Text } else { Get-TIGlyph $Icon }
    $lbl.Margin = New-Object System.Windows.Forms.Padding(0)
    return $lbl
}

function New-TILabel {
    param(
        [string]$Text,
        [float]$Size = 9.5,
        [switch]$Bold,
        [switch]$Muted,
        [switch]$Dim,
        $Color = $null
    )
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Font = New-TIFont $Size $(if ($Bold) { 'Bold' } else { 'Regular' })
    $lbl.ForeColor = if ($Color) { $Color }
                     elseif ($Muted) { $global:Pal.TextMuted }
                     elseif ($Dim) { $global:Pal.TextDim }
                     else { $global:Pal.TextMain }
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.AutoSize = $true
    $lbl.UseMnemonic = $false
    $lbl.Margin = New-Object System.Windows.Forms.Padding(0)
    return $lbl
}

function New-TIButton {
    param(
        [string]$Text,
        [ValidateSet('Primary','Danger','Success','Outline','Ghost','Soft')][string]$Style = 'Outline',
        [string]$Icon = '',
        [int]$Width = 150,
        [int]$Height = 36,
        [float]$GlyphSize = 12,
        [string]$Tip = ''
    )
    $btn = New-Object TISuite.PremiumButton
    $btn.Text = $Text
    $btn.Style = $Style
    if ($Icon) { $btn.Glyph = Get-TIGlyph $Icon }
    $btn.GlyphSize = $GlyphSize
    $btn.Width = $Width
    $btn.Height = $Height
    $btn.AccessibleName = $Text
    $btn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 8)
    # Nunca corta o próprio texto: cresce até caber (a largura pedida é o mínimo)
    try {
        $need = $btn.GetPreferredSize([System.Drawing.Size]::Empty).Width
        if ($need -gt $btn.Width) { $btn.Width = $need }
    } catch { }
    if ($Tip) {
        $global:TITip.SetToolTip($btn, $Tip)
        try { $btn.AutoTip = $false } catch { }
    }
    $btn.Add_Disposed({ try { $global:TITip.SetToolTip($this, $null) } catch { } })
    return $btn
}

function New-TIGlyphButton {
    param([string]$Icon, [string]$Tip, [int]$Size = 36)
    $btn = New-Object TISuite.PremiumButton
    $btn.Style = 'Ghost'
    $btn.Glyph = Get-TIGlyph $Icon
    $btn.GlyphSize = 13
    $btn.Width = $Size
    $btn.Height = $Size
    $btn.Radius = 8
    $btn.AccessibleName = $Tip
    $btn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
    if ($Tip) {
        $global:TITip.SetToolTip($btn, $Tip)
        try { $btn.AutoTip = $false } catch { }
    }
    $btn.Add_Disposed({ try { $global:TITip.SetToolTip($this, $null) } catch { } })
    return $btn
}

# --- Card -------------------------------------------------------------------
function New-TICard {
    <#
      Cria um card arredondado com cabeçalho (ícone + título + descrição curta de
      uma linha) e devolve o painel de conteúdo (FlowLayoutPanel vertical).
      -Height é a altura mínima: o card cresce para caber o conteúdo.
      -Stretch ocupa a largura toda da área; -Half ocupa meia largura (uma
      coluna só quando a janela é estreita).
      -WithStatus adiciona um selo de estado no canto (Set-TICardStatus).
    #>
    param(
        $Parent,
        [string]$Title = '',
        [string]$Desc = '',
        [string]$Icon = '',
        [int]$Width = 360,
        [int]$Height = 220,
        [switch]$Stretch,
        [switch]$Half,
        [switch]$WithStatus
    )
    $card = New-Object TISuite.RoundPanel
    $card.Radius = 14
    $card.FillColor = $global:Pal.Card
    $card.BorderColor = $global:Pal.BorderSoft
    $card.BorderWidth = 1
    $card.BackdropColor = $global:Pal.Bg
    $card.Size = New-Object System.Drawing.Size($Width, $Height)
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, $global:Theme.CardGap, $global:Theme.CardGap)
    if ($Stretch) { $card.Tag = 'tistretch' }
    elseif ($Half) { $card.Tag = 'tihalf' }

    $pill = $null
    $tx = 18
    if ($Icon) {
        $g = New-TIGlyph -Icon $Icon -Size 15 -Color $global:Pal.Primary
        $g.Location = New-Object System.Drawing.Point(18, 17)
        $card.Controls.Add($g)
        $tx = 46
    }
    $reserve = 18
    if ($WithStatus) {
        $pill = New-Object TISuite.StatusPill
        $pill.Anchor = 'Top,Right'
        $pill.Location = New-Object System.Drawing.Point(($Width - 18 - 60), 15)
        $card.Controls.Add($pill)
        $pill.Text = 'Aguardando'
        $pill.Tone = $global:Pal.TextDim
        $reserve = 132
    }
    if ($Title) {
        $t = New-TILabel -Text $Title -Size 10.5 -Bold
        $t.AutoSize = $false
        $t.AutoEllipsis = $true
        $t.Size = New-Object System.Drawing.Size(([Math]::Max(60, $Width - $tx - $reserve)), 22)
        $t.Location = New-Object System.Drawing.Point($tx, 14)
        $t.Anchor = 'Top,Left,Right'
        $card.Controls.Add($t)
    }
    if ($Desc) {
        $d = New-TILabel -Text $Desc -Size 8 -Muted
        $d.AutoSize = $false
        $d.AutoEllipsis = $true
        $d.Size = New-Object System.Drawing.Size(([Math]::Max(60, $Width - $tx - 18)), 16)
        $d.Location = New-Object System.Drawing.Point($tx, 37)
        $d.Anchor = 'Top,Left,Right'
        $card.Controls.Add($d)
        $topY = 64
    } else {
        $topY = 52
    }
    # Divisória ancorada dos dois lados: acompanha cards esticados
    $div = New-Object System.Windows.Forms.Panel
    $div.BackColor = $global:Pal.BorderSoft
    $div.Location = New-Object System.Drawing.Point(18, ($topY - 7))
    $div.Size = New-Object System.Drawing.Size(($Width - 36), 1)
    $div.Anchor = 'Top,Left,Right'
    $card.Controls.Add($div)

    $body = New-Object TISuite.TIScrollFlow
    $body.FlowDirection = 'TopDown'
    $body.WrapContents = $false
    $body.AutoScroll = $true
    $body.BackColor = [System.Drawing.Color]::Transparent
    $body.Location = New-Object System.Drawing.Point(14, $topY)
    $body.Size = New-Object System.Drawing.Size(($Width - 28), ($Height - $topY - 12))
    $body.Anchor = 'Top,Bottom,Left,Right'
    $body.Padding = New-Object System.Windows.Forms.Padding(4, 4, 4, 4)
    $body.Tag = $card
    Add-Member -InputObject $body -NotePropertyName 'MinCardHeight' -NotePropertyValue $Height -Force
    $body.Add_Resize({ Set-TIFitRows $this })
    $body.Add_Layout({ Update-TICardHeight $this })
    $card.Controls.Add($body)
    if ($pill) { Add-Member -InputObject $body -NotePropertyName 'Pill' -NotePropertyValue $pill -Force }

    if ($Parent) { $Parent.Controls.Add($card) }
    return $body
}

# O card cresce (nunca abaixo da altura pedida) para o conteúdo não ficar cortado
function Update-TICardHeight {
    param($Body)
    if (-not $Body -or $Body.IsDisposed -or -not $Body.PSObject.Properties['MinCardHeight']) { return }
    $card = $Body.Parent
    if (-not $card) { return }
    try {
        $need = $Body.GetPreferredSize((New-Object System.Drawing.Size($Body.ClientSize.Width, 0))).Height
        $h = [Math]::Max([int]$Body.MinCardHeight, $Body.Top + $need + 12)
        if ($card.Height -ne $h) { $card.Height = $h }
    } catch { }
}

function Set-TICardStatus {
    param($Body, [ValidateSet('ok','warn','crit','none','busy','info')][string]$Status = 'none', [string]$Text = '')
    if (-not $Body) { return }
    if (-not $Body.PSObject.Properties['Pill']) { return }
    $pill = $Body.Pill
    if (-not $pill -or $pill.IsDisposed) { return }
    $map = @{
        ok   = @('Em ordem',    $global:Pal.Success)
        warn = @('Atenção',     $global:Pal.Warning)
        crit = @('Crítico',     $global:Pal.Danger)
        none = @('Sem dados',   $global:Pal.TextDim)
        busy = @('Verificando', $global:Pal.Primary)
        info = @('Informativo', $global:Pal.Primary)
    }
    $pair = $map[$Status]
    $pill.Tone = $pair[1]
    $pill.Text = $(if ($Text) { $Text } else { $pair[0] })
}

function Get-TIInnerWidth {
    param($Body)
    return $Body.ClientSize.Width - $Body.Padding.Horizontal
}

# Linha rótulo/valor usada nos cards (valor com reticências quando não cabe;
# o próprio Label mostra o texto completo ao passar o mouse).
function New-TIRow {
    param(
        [Parameter(Mandatory)][string]$Label,
        [string]$Value = '',
        [int]$Width = 300,
        [int]$LabelWidth = 112
    )
    $row = New-Object System.Windows.Forms.Panel
    $row.Tag = 'tirow'
    $row.Size = New-Object System.Drawing.Size($Width, 24)
    $row.BackColor = [System.Drawing.Color]::Transparent
    $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)

    $l = New-TILabel -Text $Label -Size 8.5 -Muted
    $l.AutoSize = $false
    $l.AutoEllipsis = $true
    $l.TextAlign = 'MiddleLeft'
    $l.Size = New-Object System.Drawing.Size(([Math]::Max(30, $LabelWidth - 8)), 20)
    $l.Location = New-Object System.Drawing.Point(0, 2)
    $row.Controls.Add($l)

    $v = New-TILabel -Text $Value -Size 8.5 -Bold
    $v.AutoSize = $false
    $v.AutoEllipsis = $true
    $v.TextAlign = 'MiddleLeft'
    $v.Tag = 'tivalue'
    $v.Location = New-Object System.Drawing.Point($LabelWidth, 2)
    $v.Size = New-Object System.Drawing.Size(([Math]::Max(40, $Width - $LabelWidth)), 20)
    $v.Anchor = 'Top,Left,Right'
    # Duplo clique copia o valor (série, MAC, IP... direto para o chamado)
    $v.Add_DoubleClick({
        $t = [string]$this.Text
        if ($t -and $t -ne '-') {
            try { [System.Windows.Forms.Clipboard]::SetText($t); Show-TIToast -Text ('Copiado: {0}' -f $t) -Type 'Success' } catch { }
        }
    })
    $row.Controls.Add($v)

    return [pscustomobject]@{ Panel = $row; Value = $v; Label = $l }
}

function Set-TIRowValue {
    param($Row, [string]$Text, [string]$Tone = '')
    if (-not $Row) { return }
    $v = $Row
    if ($Row.PSObject.Properties['Value'] -and $Row.Value -is [System.Windows.Forms.Control]) { $v = $Row.Value }
    if (-not ($v -is [System.Windows.Forms.Control]) -or $v.IsDisposed) { return }
    $v.Text = $(if ([string]::IsNullOrEmpty($Text)) { '-' } else { $Text })
    $v.ForeColor = $(if ($Tone) { Get-TIToneColor $Tone } else { $global:Pal.TextMain })
}

# Parágrafo que quebra linha e cresce na altura (acompanha a largura do card)
function New-TIHint {
    param($Parent, [string]$Text, [float]$Size = 8.5, $Color = $null, [int]$TopGap = 2, [int]$BottomGap = 8)
    $l = New-TILabel -Text $Text -Size $Size -Muted -Color $Color
    $l.AutoSize = $true
    $l.Tag = 'tiwrap'
    $w = if ($Parent) { Get-TIInnerWidth $Parent } else { 300 }
    $l.MaximumSize = New-Object System.Drawing.Size(([Math]::Max(80, $w)), 0)
    $l.Margin = New-Object System.Windows.Forms.Padding(0, $TopGap, 0, $BottomGap)
    if ($Parent) { $Parent.Controls.Add($l) }
    return $l
}

# Faixa de botões que quebra linha sozinha (nada de posição fixa sobreposta)
function New-TIButtonBar {
    param($Parent, [int]$BottomGap = 4)
    $bar = New-Object System.Windows.Forms.FlowLayoutPanel
    $bar.Tag = 'tibar'
    $bar.FlowDirection = 'LeftToRight'
    $bar.WrapContents = $true
    $bar.AutoSize = $true
    $bar.AutoSizeMode = 'GrowAndShrink'
    $bar.BackColor = [System.Drawing.Color]::Transparent
    $bar.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, $BottomGap)
    $bar.Padding = New-Object System.Windows.Forms.Padding(0)
    $w = if ($Parent) { [Math]::Max(80, (Get-TIInnerWidth $Parent)) } else { 300 }
    $bar.MinimumSize = New-Object System.Drawing.Size($w, 0)
    $bar.MaximumSize = New-Object System.Drawing.Size($w, 0)
    if ($Parent) { $Parent.Controls.Add($bar) }
    return $bar
}

# Texto de apoio alinhado ao meio dos botões de 36 px de uma faixa
function Add-TIBarLabel {
    param($Bar, [string]$Text = '', [switch]$Bold)
    $l = New-TILabel -Text $Text -Size 8.5 -Muted -Bold:$Bold
    $l.AutoSize = $true
    $l.Margin = New-Object System.Windows.Forms.Padding(4, 10, 0, 8)
    $Bar.Controls.Add($l)
    return $l
}

# Campo de texto com rótulo e dica de preenchimento
function New-TIField {
    param($Parent, [string]$Label, [string]$Placeholder = '', [int]$MaxLength = 80, [string]$Value = '')
    $w = if ($Parent) { [Math]::Max(80, (Get-TIInnerWidth $Parent)) } else { 300 }
    $wrap = New-Object System.Windows.Forms.Panel
    $wrap.Tag = 'tirow'
    $wrap.Size = New-Object System.Drawing.Size($w, 52)
    $wrap.BackColor = [System.Drawing.Color]::Transparent
    $wrap.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)

    $lbl = New-TILabel -Text $Label -Size 8.5 -Muted
    $lbl.Location = New-Object System.Drawing.Point(0, 0)
    $wrap.Controls.Add($lbl)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(0, 21)
    $tb.Size = New-Object System.Drawing.Size($w, 28)
    $tb.Anchor = 'Top,Left,Right'
    $tb.BackColor = $global:Pal.Bg
    $tb.ForeColor = $global:Pal.TextMain
    $tb.BorderStyle = 'FixedSingle'
    $tb.Font = New-TIFont 10
    $tb.MaxLength = $MaxLength
    $tb.Text = $Value
    $wrap.Controls.Add($tb)
    if ($Parent) { $Parent.Controls.Add($wrap) }
    if ($Placeholder) { $null = Add-TIPlaceholder -TextBox $tb -Text $Placeholder }
    return $tb
}

# Ajusta larguras dos elementos esticáveis dentro de um FlowLayoutPanel
function Set-TIFitRows {
    param($Flow)
    if (-not $Flow -or $Flow.IsDisposed) { return }
    $w = $Flow.ClientSize.Width - $Flow.Padding.Horizontal
    if ($w -lt 80) { return }
    foreach ($c in $Flow.Controls) {
        switch ([string]$c.Tag) {
            'tistretch' {
                $cw = $w - $c.Margin.Horizontal
                if ($cw -gt 80 -and $c.Width -ne $cw) { $c.Width = $cw }
            }
            'tihalf' {
                # duas colunas quando cada uma tem pelo menos 400 px; senão, largura toda
                $cols = if ((($w / 2) - $c.Margin.Horizontal) -ge 400) { 2 } else { 1 }
                $cw = [int][Math]::Floor($w / $cols) - $c.Margin.Horizontal
                if ($cw -gt 80 -and $c.Width -ne $cw) { $c.Width = $cw }
            }
            'tirow' {
                if ($c.Width -ne $w) { $c.Width = $w }
            }
            'tiwrap' {
                if ($c.MaximumSize.Width -ne $w) { $c.MaximumSize = New-Object System.Drawing.Size($w, 0) }
            }
            'tibar' {
                if ($c.MaximumSize.Width -ne $w) {
                    $c.MinimumSize = New-Object System.Drawing.Size(0, 0)
                    $c.MaximumSize = New-Object System.Drawing.Size($w, 0)
                    $c.MinimumSize = New-Object System.Drawing.Size($w, 0)
                }
            }
        }
    }
}

# Container de área de trabalho padrão (grade fluida de cards)
function New-TIWorkspaceLayout {
    param($Panel)
    $flow = New-Object TISuite.TIScrollFlow
    $flow.Dock = 'Fill'
    $flow.FlowDirection = 'LeftToRight'
    $flow.WrapContents = $true
    $flow.AutoScroll = $true
    $flow.BackColor = $global:Pal.Bg
    # direita menor: os cards já têm a margem do espaçamento (CardGap) à direita
    $flow.Padding = New-Object System.Windows.Forms.Padding(24, 20, (24 - $global:Theme.CardGap), 24)
    $flow.Add_Resize({ Set-TIFitRows $this })
    $Panel.Controls.Add($flow)
    return $flow
}

# --- Barras de rolagem escuras (uxtheme) -------------------------------------
function Set-TIDarkScroll {
    # Melhor esforço: tema escuro do Windows 10/11 na janela e nas barras filhas.
    param($Control)
    try {
        [void][TISuite.Native]::SetWindowTheme($Control.Handle, 'DarkMode_Explorer', $null)
        foreach ($child in $Control.Controls) {
            if ($child -is [System.Windows.Forms.ScrollBar]) {
                [void][TISuite.Native]::SetWindowTheme($child.Handle, 'DarkMode_Explorer', $null)
            }
        }
    } catch { }
}

# --- Tabela estilizada ---------------------------------------------------------
function New-TIGrid {
    param($Parent, [string[]]$Headers, [int[]]$Widths, [switch]$Multi, [string]$EmptyText = 'Nenhum item para exibir.')
    $g = New-Object System.Windows.Forms.DataGridView
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.AllowUserToResizeRows = $false
    $g.AutoSizeRowsMode = 'None'
    $g.BorderStyle = 'None'
    $g.CellBorderStyle = 'SingleHorizontal'
    $g.GridColor = $global:Pal.BorderSoft
    $g.BackgroundColor = $global:Pal.Card
    $g.RowHeadersVisible = $false
    $g.ReadOnly = $true
    $g.SelectionMode = 'FullRowSelect'
    $g.MultiSelect = $Multi.IsPresent
    $g.StandardTab = $true
    $g.EnableHeadersVisualStyles = $false
    $g.ColumnHeadersHeightSizeMode = 'DisableResizing'
    $g.ColumnHeadersHeight = 34
    $g.RowHeadersWidthSizeMode = 'DisableResizing'
    $g.RowTemplate.Height = 30
    $g.Font = New-TIFont 9.5
    $g.ForeColor = $global:Pal.TextMain
    $g.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    # Buffer duplo (propriedade protegida): rolagem sem cintilação em PC fraco
    try {
        [System.Windows.Forms.DataGridView].GetProperty('DoubleBuffered',
            [System.Reflection.BindingFlags]'Instance, NonPublic').SetValue($g, $true, $null)
    } catch { }

    $hdr = $g.ColumnHeadersDefaultCellStyle
    $hdr.BackColor = $global:Pal.CardAlt
    $hdr.ForeColor = $global:Pal.TextMuted
    $hdr.Font = New-TIFont 8.5 Bold
    $hdr.SelectionBackColor = $global:Pal.CardAlt
    $hdr.SelectionForeColor = $global:Pal.TextMuted
    $hdr.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)

    $cell = $g.DefaultCellStyle
    $cell.BackColor = $global:Pal.Card
    $cell.ForeColor = $global:Pal.TextMain
    $cell.SelectionBackColor = $global:Pal.ActiveRow
    $cell.SelectionForeColor = $global:Pal.TextMain
    $cell.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
    $cell.Font = New-TIFont 9.5

    $g.ColumnHeadersBorderStyle = 'None'
    $alt = $g.AlternatingRowsDefaultCellStyle
    $alt.BackColor = [TISuite.Gfx]::Lerp($global:Pal.Card, $global:Pal.Bg, 0.22)
    $alt.ForeColor = $global:Pal.TextMain
    $alt.SelectionBackColor = $global:Pal.ActiveRow
    $alt.SelectionForeColor = $global:Pal.TextMain

    # Colunas proporcionais à largura do card (a largura pedida vira o peso):
    # nada fica fora de alcance em tela pequena, nem sobra faixa vazia em tela grande.
    for ($i = 0; $i -lt $Headers.Count; $i++) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.HeaderText = $Headers[$i]
        $cw = if ($Widths -and $i -lt $Widths.Count) { $Widths[$i] } else { 120 }
        $col.MinimumWidth = [Math]::Min(60, $cw)
        $col.FillWeight = $cw
        $col.AutoSizeMode = 'Fill'
        [void]$g.Columns.Add($col)
    }

    # Estado vazio: orienta em vez de mostrar uma área escura em branco
    $empty = New-Object System.Windows.Forms.Label
    $empty.Text = $EmptyText
    $empty.AutoSize = $true
    $empty.Font = New-TIFont 9.5
    $empty.ForeColor = $global:Pal.TextDim
    $empty.BackColor = $global:Pal.Card
    $empty.UseMnemonic = $false
    $g.Controls.Add($empty)
    $place = {
        try {
            $empty.Visible = ($g.Rows.Count -eq 0)
            $empty.Location = New-Object System.Drawing.Point(
                [Math]::Max(8, [int](($g.ClientSize.Width - $empty.Width) / 2)),
                [int]($g.ColumnHeadersHeight + 28))
        } catch { }
    }.GetNewClosure()
    $g.Add_RowsAdded($place)
    $g.Add_RowsRemoved($place)
    $g.Add_Resize($place)
    # SizeChanged (não TextChanged): o AutoSize só recalcula a largura depois do texto
    $empty.Add_SizeChanged($place)
    $g.Add_HandleCreated({ Set-TIDarkScroll $this })
    # Ordenação pelo valor real (bytes, datas, ms) quando Add-TIRow recebe -SortKeys;
    # sem chave, ordena pelo texto como antes
    $g.Add_SortCompare({
        param($s, $e)
        try {
            $a = $s.Rows[$e.RowIndex1].Cells[$e.Column.Index].Tag
            $b = $s.Rows[$e.RowIndex2].Cells[$e.Column.Index].Tag
            if ($null -ne $a -and $null -ne $b) {
                $e.SortResult = [System.Collections.Comparer]::Default.Compare($a, $b)
                $e.Handled = $true
            }
        } catch { }
    })
    & $place
    Add-Member -InputObject $g -NotePropertyName 'EmptyLabel' -NotePropertyValue $empty -Force
    Add-TIGridMenu $g

    if ($Parent) { $Parent.Controls.Add($g) }
    return $g
}

# Botão direito nas tabelas: copiar linhas e exportar a lista para o Excel
function Add-TIGridMenu {
    param($Grid)
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.ShowImageMargin = $false
    $menu.Renderer = New-Object TISuite.DarkMenuRenderer
    $menu.BackColor = $global:Pal.CardAlt
    $menu.ForeColor = $global:Pal.TextMain
    $menu.Font = New-TIFont 9
    $miCopy = New-Object System.Windows.Forms.ToolStripMenuItem('Copiar linha(s) selecionada(s)')
    $miCopy.Add_Click({ Copy-TIGridRows -Grid $Grid }.GetNewClosure())
    $miAll = New-Object System.Windows.Forms.ToolStripMenuItem('Copiar a lista inteira')
    $miAll.Add_Click({ Copy-TIGridRows -Grid $Grid -All }.GetNewClosure())
    $miCsv = New-Object System.Windows.Forms.ToolStripMenuItem('Exportar a lista (.csv para o Excel)...')
    $miCsv.Add_Click({ Export-TIGridCsv -Grid $Grid }.GetNewClosure())
    foreach ($mi in @($miCopy, $miAll, $miCsv)) { $mi.ForeColor = $global:Pal.TextMain; [void]$menu.Items.Add($mi) }
    $menu.Add_Opening({
        $miCopy.Enabled = ($Grid.SelectedRows.Count -gt 0)
        $miAll.Enabled = ($Grid.Rows.Count -gt 0)
        $miCsv.Enabled = ($Grid.Rows.Count -gt 0)
    }.GetNewClosure())
    # Clique direito numa linha não selecionada passa a selecioná-la (como no Explorer)
    $Grid.Add_CellMouseDown({
        param($s, $e)
        if ($e.Button -ne 'Right' -or $e.RowIndex -lt 0) { return }
        $row = $s.Rows[$e.RowIndex]
        if (-not $row.Selected) { $s.ClearSelection(); $row.Selected = $true }
    })
    $Grid.ContextMenuStrip = $menu
}

# Texto de uma linha: células separadas por tabulação (cola certo no Excel)
function Get-TIGridLines {
    param($Grid, $Rows)
    $cols = @($Grid.Columns | Where-Object { $_.Visible -and $_.HeaderText } | Sort-Object DisplayIndex)
    $out = New-Object System.Collections.ArrayList
    [void]$out.Add((@($cols | ForEach-Object { $_.HeaderText }) -join "`t"))
    foreach ($r in $Rows) {
        [void]$out.Add((@($cols | ForEach-Object { [string]$r.Cells[$_.Index].FormattedValue }) -join "`t"))
    }
    return $out
}

function Copy-TIGridRows {
    param($Grid, [switch]$All)
    $rows = if ($All) { @($Grid.Rows) } else { @($Grid.SelectedRows | Sort-Object Index) }
    if ($rows.Count -eq 0) { return }
    try {
        [System.Windows.Forms.Clipboard]::SetText(((Get-TIGridLines -Grid $Grid -Rows $rows) -join "`r`n"))
        Show-TIToast -Text ('{0} linha(s) copiada(s).' -f $rows.Count) -Type 'Success'
    } catch {
        Show-TIToast -Text 'Não foi possível usar a área de transferência.' -Type 'Error'
    }
}

function Export-TIGridCsv {
    param($Grid)
    $rows = @($Grid.Rows)
    if ($rows.Count -eq 0) { return }
    # Select-TISaveFile funciona no Windows aberto (diálogo) e no WinPE (grava em relatorios\)
    $path = Select-TISaveFile -Title 'Exportar a lista' -Filter 'Planilha CSV (*.csv)|*.csv' `
            -FileName ('{0}-{1}.csv' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm')) -Folder 'relatorios'
    if (-not $path) { return }
    try {
        $cols = @($Grid.Columns | Where-Object { $_.Visible -and $_.HeaderText } | Sort-Object DisplayIndex)
        $lines = New-Object System.Collections.ArrayList
        $fmt = { param($v) '"' + ([string]$v).Replace('"', '""') + '"' }
        [void]$lines.Add((@($cols | ForEach-Object { & $fmt $_.HeaderText }) -join ';'))
        foreach ($r in $rows) {
            [void]$lines.Add((@($cols | ForEach-Object {
                $v = [string]$r.Cells[$_.Index].FormattedValue
                # texto que começa com = + - @ vira fórmula no Excel: neutraliza
                if ($v -match '^[=+\-@]') { $v = "'" + $v }
                & $fmt $v
            }) -join ';'))
        }
        # ; e UTF-8 com BOM: abre certo no Excel em português
        [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
        Show-TIToast -Text ('Lista exportada: {0}' -f (Split-Path -Leaf $path)) -Type 'Success'
    } catch {
        Show-TIToast -Text ('Não foi possível exportar: {0}' -f $_.Exception.Message) -Type 'Error'
    }
}

function Set-TIGridEmptyText {
    param($Grid, [string]$Text)
    if ($Grid -and $Grid.PSObject.Properties['EmptyLabel']) { $Grid.EmptyLabel.Text = $Text }
}

# -SortKeys: valor bruto por coluna (tamanho em bytes, data...) usado ao ordenar
function Add-TIRow {
    param($Grid, [object[]]$Cells, [object]$Tag = $null, [object[]]$SortKeys = $null)
    $row = New-Object System.Windows.Forms.DataGridViewRow
    for ($i = 0; $i -lt $Cells.Count; $i++) {
        $cell = New-Object System.Windows.Forms.DataGridViewTextBoxCell
        $cell.Value = $Cells[$i]
        if ($SortKeys -and $i -lt $SortKeys.Count -and $null -ne $SortKeys[$i]) { $cell.Tag = $SortKeys[$i] }
        [void]$row.Cells.Add($cell)
    }
    if ($null -ne $Tag) { $row.Tag = $Tag }
    [void]$Grid.Rows.Add($row)
    return $row
}

# Depois de preencher: mantém a ordenação que o operador escolheu (a seta do
# cabeçalho continuava, mas as linhas voltavam na ordem original) e deixa
# nada pré-selecionado (botões só liberam com clique do operador)
function Clear-TIGridSelection {
    param($Grid)
    if (-not $Grid) { return }
    try {
        if ($Grid.SortedColumn -and $Grid.Rows.Count -gt 1) {
            $dir = if ($Grid.SortOrder -eq 'Descending') { 'Descending' } else { 'Ascending' }
            $Grid.Sort($Grid.SortedColumn, [System.ComponentModel.ListSortDirection]$dir)
        }
    } catch { }
    try { $Grid.ClearSelection() } catch { }
    try { $Grid.CurrentCell = $null } catch { }
}

# --- Texto de exemplo dentro da caixa (placeholder) ----------------------------
# 1.3.0: posição relativa à caixa (antes nascia fora dela na busca da barra
# lateral), fundo igual ao da caixa e clique no texto foca o campo.
function Add-TIPlaceholder {
    param($TextBox, [string]$Text, $Color = $null)
    $holder = New-TILabel -Text $Text -Size 9 -Muted -Color $Color
    $holder.AutoSize = $true
    $holder.BackColor = $TextBox.BackColor
    $holder.Cursor = [System.Windows.Forms.Cursors]::IBeam
    $holder.Anchor = 'Top,Left'
    $TextBox.Parent.Controls.Add($holder)

    $place = {
        $holder.Location = New-Object System.Drawing.Point(($TextBox.Left + 4), ($TextBox.Top + [int](($TextBox.Height - $holder.Height) / 2)))
    }.GetNewClosure()
    & $place
    $TextBox.Add_LocationChanged($place)
    $TextBox.Add_SizeChanged($place)
    $holder.BringToFront()
    $holder.Add_Click({ $TextBox.Focus() }.GetNewClosure())

    $sync = {
        $holder.Visible = ($TextBox.Text.Length -eq 0 -and -not $TextBox.Focused)
    }.GetNewClosure()
    $TextBox.Add_TextChanged($sync)
    # GotFocus/LostFocus (não Enter/Leave): no Enter o foco nativo ainda não chegou
    # e o texto de exemplo ficava por cima do cursor ao entrar com Tab
    $TextBox.Add_GotFocus($sync)
    $TextBox.Add_LostFocus($sync)
    & $sync
    return $holder
}

# --- Formatação ---------------------------------------------------------------
function Format-TIBytes {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:0.##} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:0.##} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:0.##} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:0.##} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

# -Relative acrescenta a idade: '05/01/2026 10:30 (há 268 dias)'. -Empty: texto quando não há data.
function Format-TIDate {
    param($Dt, [switch]$Relative, [string]$Empty = '-')
    if (-not $Dt) { return $Empty }
    if ($Dt -is [string]) { return $Dt }
    if ($Dt -eq [datetime]::MinValue) { return $Empty }
    $txt = $Dt.ToString('dd/MM/yyyy HH:mm')
    if ($Relative) { $txt += ' (' + (Format-TIAgo $Dt) + ')' }
    return $txt
}

function Format-TIDuration {
    param($Span)
    if (-not $Span) { return '-' }
    $d = [int][Math]::Floor($Span.TotalDays)
    $h = $Span.Hours
    $m = $Span.Minutes
    if ($d -gt 0) { return ('{0}d {1}h {2}min' -f $d, $h, $m) }
    if ($h -gt 0) { return ('{0}h {1}min' -f $h, $m) }
    return ('{0} min' -f $m)
}

function Format-TIAgo {
    param($Date)
    if (-not $Date) { return '' }
    $days = [int][Math]::Floor(((Get-Date).Date - ([datetime]$Date).Date).TotalDays)
    if ($days -le 0) { return 'hoje' }
    if ($days -eq 1) { return 'ontem' }
    return ('há {0} dias' -f $days)
}

# --- Persistência de configurações ---------------------------------------------
$global:TI.Settings = @{
    CompactConsole     = $true
    ForceChangeOnLogon = $false
    CrispText          = $false
    # Lembrados ao fechar a janela (05-Shell): maximizada e altura do console
    # em pixels (0 = automática, 30% da área)
    WindowMaximized    = $false
    ConsoleHeight      = 0
    # SchoolPassword vive SOMENTE em memória (nunca vai para o config.json)
    SchoolPassword     = ''
}

function Read-TISettings {
    try {
        if (Test-Path -LiteralPath $global:TI.SettingsPath) {
            $j = Get-Content -LiteralPath $global:TI.SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @('CompactConsole','ForceChangeOnLogon','CrispText','WindowMaximized')) {
                $v = $j.$k
                if ($null -eq $v) { continue }
                # "false" entre aspas (editado à mão) não pode virar verdadeiro
                if ($v -is [string]) { $v = ($v -match '^(?i:true|1|sim)$') }
                $global:TI.Settings[$k] = [bool]$v
            }
            # Número inteiro de 0 a 4000; valor estranho (editado à mão) é ignorado
            $n = 0
            if ($null -ne $j.ConsoleHeight -and [int]::TryParse(([string]$j.ConsoleHeight).Trim(), [ref]$n) -and $n -ge 0 -and $n -le 4000) {
                $global:TI.Settings['ConsoleHeight'] = $n
            }
            # Migração: config antigo guardava a senha em texto puro. Não carrega e apaga do disco.
            if ($null -ne $j.SchoolPassword -and [string]$j.SchoolPassword -ne '') { $script:TILegacyPwScrub = $true }
        }
    } catch { }
}

# Devolve $false quando não consegue gravar (pendrive protegido, arquivo somente leitura)
function Save-TISettings {
    try {
        $dir = Split-Path -Parent $global:TI.SettingsPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        # Nunca grava a senha nem opções que saíram do app (config.json antigo fica limpo)
        $skip = @('SchoolPassword', 'SuppressConfirm', 'ClearLogStart', 'KeepGridSort')
        $persist = [ordered]@{}
        foreach ($k in @($global:TI.Settings.Keys | Sort-Object)) { if ($skip -notcontains $k) { $persist[$k] = $global:TI.Settings[$k] } }
        ConvertTo-Json -InputObject $persist | Set-Content -LiteralPath $global:TI.SettingsPath -Encoding UTF8 -ErrorAction Stop
        return $true
    } catch {
        $msg = 'Não foi possível gravar o config.json (pendrive protegido contra gravação?). As preferências valem só nesta sessão.'
        if (Get-Command Write-TILog -ErrorAction SilentlyContinue) { Write-TILog -Level 'Warn' -Message $msg }
        if ($global:Form -and (Get-Command Show-TIToast -ErrorAction SilentlyContinue)) { Show-TIToast -Text $msg -Type 'Warn' }
        return $false
    }
}

Read-TISettings
if ($script:TILegacyPwScrub) { [void](Save-TISettings) }
