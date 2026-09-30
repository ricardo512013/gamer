# =====================================================================
# 02-DIALOGS.ps1 - Janelas modais: confirmação, entrada de texto e aviso (toast)
# Os handlers abaixo rodam enquanto ShowDialog mantém o escopo da função
# ativo, por isso podem referenciar variáveis locais diretamente.
# =====================================================================

function Get-TIOwner {
    param($Owner)
    if ($Owner) { return $Owner }
    if ($global:Form -and $global:Form.Visible) { return $global:Form }
    return $null
}

# Borda de 1 px nas janelas sem moldura (no Windows 10 elas se misturavam ao fundo)
function Add-TIDialogFrame {
    param($Form)
    $Form.Add_Paint({
        param($s, $e)
        try {
            $pen = New-Object System.Drawing.Pen($global:Pal.Border)
            $e.Graphics.DrawRectangle($pen, 0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
            $pen.Dispose()
        } catch { }
    })
}

function Show-TIConfirm {
    <#
      Retorna $true/$false. Se -CheckText for informado, retorna
      [pscustomobject] @{ OK = bool; Checked = bool }.
      Estilo Danger: o foco começa em "Cancelar" e o Enter NÃO confirma sozinho
      (só aciona o botão que estiver com foco).
    #>
    param(
        [string]$Title = 'Confirmar operação',
        [string]$Message = '',
        [string]$ConfirmText = 'Confirmar',
        [string]$CancelText = 'Cancelar',
        [ValidateSet('Primary','Danger','Success')][string]$Style = 'Primary',
        [string]$Icon = 'Warning',
        [string]$CheckText = '',
        [switch]$Force,
        $Owner = $null
    )

    if (-not $Force -and $global:TI.Settings.SuppressConfirm -and -not $CheckText) {
        Write-TILog -Level 'Warn' -Message ("Confirmação dispensada pela configuração: {0}" -f $Title)
        return $true
    }

    $ownerWnd = Get-TIOwner $Owner

    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition = 'CenterParent'
    $f.BackColor = $global:Pal.CardAlt
    $f.ShowInTaskbar = $false
    $f.KeyPreview = $true
    $f.MinimumSize = New-Object System.Drawing.Size(420, 200)
    $f.AutoScaleMode = 'None'
    $f.Text = $Title

    $w = 470
    $f.Width = $w
    $padX = 22

    $icoColor = switch ($Style) {
        'Danger'  { $global:Pal.Danger }
        'Success' { $global:Pal.Success }
        default   { if ($Icon -eq 'Warning') { $global:Pal.Warning } else { $global:Pal.Primary } }
    }
    $ico = New-TIGlyph -Icon $Icon -Size 17 -Color $icoColor
    $ico.Location = New-Object System.Drawing.Point($padX, 19)
    $f.Controls.Add($ico)

    $lblTitle = New-TILabel -Text $Title -Size 11.5 -Bold
    $lblTitle.AutoSize = $false
    $lblTitle.AutoEllipsis = $true
    $lblTitle.Size = New-Object System.Drawing.Size(($w - 50 - 56), 24)
    $lblTitle.Location = New-Object System.Drawing.Point(50, 18)
    $f.Controls.Add($lblTitle)

    $btnClose = New-TIGlyphButton -Icon 'Close' -Tip 'Fechar (Esc)' -Size 34
    $btnClose.Location = New-Object System.Drawing.Point(($w - 46), 12)
    $btnClose.Anchor = 'Top,Right'
    $btnClose.TabStop = $false
    $btnClose.Add_Click({ $f.DialogResult = 'Cancel'; $f.Close() })
    $f.Controls.Add($btnClose)

    $lblMsg = New-TILabel -Text $Message -Size 9.5
    $lblMsg.MaximumSize = New-Object System.Drawing.Size(($w - $padX * 2 - 6), 0)
    $lblMsg.AutoSize = $true
    $f.Controls.Add($lblMsg)
    $lblMsg.Location = New-Object System.Drawing.Point($padX, 62)
    $msgBottom = 62 + $lblMsg.Height

    # Mensagens longas (listas de contas, por exemplo) rolam dentro da janela
    if ($lblMsg.Height -gt 340) {
        $f.Controls.Remove($lblMsg)
        $msgHost = New-Object System.Windows.Forms.Panel
        $msgHost.AutoScroll = $true
        $msgHost.BackColor = $global:Pal.CardAlt
        $msgHost.Location = New-Object System.Drawing.Point($padX, 62)
        $msgHost.Size = New-Object System.Drawing.Size(($w - $padX * 2), 340)
        $lblMsg.Location = New-Object System.Drawing.Point(0, 0)
        $msgHost.Controls.Add($lblMsg)
        $f.Controls.Add($msgHost)
        $msgHost.Add_HandleCreated({ Set-TIDarkScroll $this })
        $msgBottom = 62 + 340
    }

    $y = $msgBottom
    $chk = $null
    if ($CheckText) {
        $y += 14
        $chk = New-Object TISuite.ToggleSwitch
        $chk.Location = New-Object System.Drawing.Point($padX, ($y + 1))
        $f.Controls.Add($chk)
        $chkLbl = New-TILabel -Text $CheckText -Size 8.5 -Muted
        $chkLbl.Location = New-Object System.Drawing.Point(($padX + 50), ($y + 3))
        $chkLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
        $chkLbl.Add_Click({ $chk.Checked = -not $chk.Checked })
        $f.Controls.Add($chkLbl)
        $y += 30
    }

    $y += 18
    $div = New-Object System.Windows.Forms.Panel
    $div.BackColor = $global:Pal.BorderSoft
    $div.Location = New-Object System.Drawing.Point(0, $y)
    $div.Size = New-Object System.Drawing.Size($w, 1)
    $div.Anchor = 'Top,Left,Right'
    $f.Controls.Add($div)

    $y += 1
    $btnCancel = New-TIButton -Text $CancelText -Style 'Outline' -Width 110 -Height 38
    $btnConfirm = New-TIButton -Text $ConfirmText -Style $Style -Width 150 -Height 38
    $btnCancel.Anchor = 'Top,Right'
    $btnConfirm.Anchor = 'Top,Right'
    $btnConfirm.Location = New-Object System.Drawing.Point(($w - $btnConfirm.Width - 18), ($y + 16))
    $btnCancel.Location = New-Object System.Drawing.Point(($btnConfirm.Location.X - $btnCancel.Width - 10), ($y + 16))
    $btnCancel.Add_Click({ $f.DialogResult = 'Cancel'; $f.Close() })
    $btnConfirm.Add_Click({ $f.DialogResult = 'OK'; $f.Close() })
    if ($Style -eq 'Danger') {
        $btnCancel.TabIndex = 0; $btnConfirm.TabIndex = 1
    } else {
        $btnConfirm.TabIndex = 0; $btnCancel.TabIndex = 1
    }
    $f.Controls.Add($btnCancel)
    $f.Controls.Add($btnConfirm)

    $h = $btnConfirm.Bottom + 18
    $f.ClientSize = New-Object System.Drawing.Size($w, $h)

    $f.Add_Shown({
        if ($Style -eq 'Danger') { [void]$btnCancel.Focus() } else { [void]$btnConfirm.Focus() }
    })
    $f.Add_KeyDown({
        if ($_.KeyCode -eq 'Escape') { $f.DialogResult = 'Cancel'; $f.Close(); return }
        if ($_.KeyCode -eq 'Enter') {
            $_.SuppressKeyPress = $true
            if ($f.ActiveControl -eq $btnCancel) { $f.DialogResult = 'Cancel'; $f.Close() }
            elseif ($f.ActiveControl -eq $btnConfirm -or $Style -ne 'Danger') { $f.DialogResult = 'OK'; $f.Close() }
        }
    })
    $f.Add_MouseDown({ if ($_.Button -eq 'Left') { [TISuite.Native]::DragWindow($f) } })
    Add-TIDialogFrame $f

    [void][TISuite.Native]::RoundWindow($f)

    $result = $f.ShowDialog($ownerWnd)
    $ok = ($result -eq 'OK')
    $checked = ($null -ne $chk -and $chk.Checked)
    $f.Dispose()

    # "Não pedir de novo" só vale quando o operador confirmou
    if ($checked -and $ok) {
        $global:TI.Settings.SuppressConfirm = $true
        Save-TISettings
    }

    if ($CheckText) { return [pscustomobject]@{ OK = $ok; Checked = ($checked -and $ok) } }
    return $ok
}

function Show-TIInput {
    param(
        [string]$Title = 'Entrada',
        [string]$Message = '',
        [string]$Label = 'Valor',
        [string]$Value = '',
        [switch]$Password,
        [switch]$Required,
        [string]$OkText = 'Aplicar',
        [ValidateSet('Primary','Danger','Success')][string]$Style = 'Primary',
        $Owner = $null
    )
    $ownerWnd = Get-TIOwner $Owner

    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition = 'CenterParent'
    $f.BackColor = $global:Pal.CardAlt
    $f.ShowInTaskbar = $false
    $f.KeyPreview = $true
    $f.AutoScaleMode = 'None'
    $f.Text = $Title

    $w = 430
    $f.Width = $w
    $padX = 22

    $ico = New-TIGlyph -Icon $(if ($Password) { 'Lock' } else { 'Edit' }) -Size 17 -Color $global:Pal.Primary
    $ico.Location = New-Object System.Drawing.Point($padX, 19)
    $f.Controls.Add($ico)

    $lblTitle = New-TILabel -Text $Title -Size 11.5 -Bold
    $lblTitle.AutoSize = $false
    $lblTitle.AutoEllipsis = $true
    $lblTitle.Size = New-Object System.Drawing.Size(($w - 50 - 56), 24)
    $lblTitle.Location = New-Object System.Drawing.Point(50, 18)
    $f.Controls.Add($lblTitle)

    $btnClose = New-TIGlyphButton -Icon 'Close' -Tip 'Fechar (Esc)' -Size 34
    $btnClose.Location = New-Object System.Drawing.Point(($w - 46), 12)
    $btnClose.Anchor = 'Top,Right'
    $btnClose.TabStop = $false
    $btnClose.Add_Click({ $f.DialogResult = 'Cancel'; $f.Close() })
    $f.Controls.Add($btnClose)

    $y = 60
    if ($Message) {
        $lblMsg = New-TILabel -Text $Message -Size 9 -Muted
        $lblMsg.Location = New-Object System.Drawing.Point($padX, $y)
        $lblMsg.MaximumSize = New-Object System.Drawing.Size(($w - $padX * 2), 0)
        $lblMsg.AutoSize = $true
        $f.Controls.Add($lblMsg)
        $y += $lblMsg.Height + 12
    }

    $lblField = New-TILabel -Text $Label -Size 8.5 -Muted
    $lblField.Location = New-Object System.Drawing.Point($padX, $y)
    $f.Controls.Add($lblField)
    $y += 19

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point($padX, $y)
    $txt.Size = New-Object System.Drawing.Size(($w - $padX * 2), 30)
    $txt.Anchor = 'Top,Left,Right'
    $txt.BackColor = $global:Pal.Bg
    $txt.ForeColor = $global:Pal.TextMain
    $txt.Font = New-TIFont 10
    $txt.BorderStyle = 'FixedSingle'
    $txt.UseSystemPasswordChar = $Password.IsPresent
    $txt.Text = $Value
    $txt.TabIndex = 0
    $f.Controls.Add($txt)
    $y += 34

    if ($Password) {
        $sw = New-Object TISuite.ToggleSwitch
        $sw.Location = New-Object System.Drawing.Point($padX, $y)
        $sw.TabIndex = 1
        $sw.Add_CheckedChanged({ $txt.UseSystemPasswordChar = -not $sw.Checked })
        $f.Controls.Add($sw)
        $swLbl = New-TILabel -Text 'Mostrar senha' -Size 8.5 -Muted
        $swLbl.Location = New-Object System.Drawing.Point(($padX + 50), ($y + 3))
        $swLbl.AutoSize = $true
        $swLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
        $swLbl.Add_Click({ $sw.Checked = -not $sw.Checked })
        $f.Controls.Add($swLbl)
        $y += 32
    }

    $lblErr = New-TILabel -Text '' -Size 8.5 -Color $global:Pal.Danger
    $lblErr.Location = New-Object System.Drawing.Point($padX, $y)
    $f.Controls.Add($lblErr)

    $div = New-Object System.Windows.Forms.Panel
    $div.BackColor = $global:Pal.BorderSoft
    $div.Location = New-Object System.Drawing.Point(0, ($y + 22))
    $div.Size = New-Object System.Drawing.Size($w, 1)
    $div.Anchor = 'Top,Left,Right'
    $f.Controls.Add($div)

    $btnCancel = New-TIButton -Text 'Cancelar' -Style 'Outline' -Width 110 -Height 38
    $btnOk = New-TIButton -Text $OkText -Style $Style -Width 150 -Height 38
    $btnOk.Anchor = 'Top,Right'
    $btnCancel.Anchor = 'Top,Right'
    $btnOk.TabIndex = 2
    $btnCancel.TabIndex = 3
    $btnOk.Location = New-Object System.Drawing.Point(($w - $btnOk.Width - 18), ($y + 38))
    $btnCancel.Location = New-Object System.Drawing.Point(($btnOk.Location.X - $btnCancel.Width - 10), ($y + 38))
    $btnCancel.Add_Click({ $f.DialogResult = 'Cancel'; $f.Close() })
    $btnOk.Add_Click({
        if ($Required.IsPresent -and $txt.Text.Trim() -eq '') {
            $lblErr.Text = 'Preencha este campo para continuar.'
            [void]$txt.Focus()
            return
        }
        $f.DialogResult = 'OK'
        $f.Close()
    })
    $txt.Add_TextChanged({ if ($lblErr.Text) { $lblErr.Text = '' } })
    $f.Controls.Add($btnCancel)
    $f.Controls.Add($btnOk)

    $f.ClientSize = New-Object System.Drawing.Size($w, ($btnOk.Bottom + 18))

    $f.Add_Shown({ [void]$txt.Focus(); $txt.SelectAll() })
    $f.Add_KeyDown({
        if ($_.KeyCode -eq 'Escape') { $f.DialogResult = 'Cancel'; $f.Close(); return }
        if ($_.KeyCode -eq 'Enter') {
            $_.SuppressKeyPress = $true
            if ($f.ActiveControl -eq $btnCancel) { $f.DialogResult = 'Cancel'; $f.Close() }
            else { $btnOk.PerformClick() }
        }
    })
    $f.Add_MouseDown({ if ($_.Button -eq 'Left') { [TISuite.Native]::DragWindow($f) } })
    Add-TIDialogFrame $f

    [void][TISuite.Native]::RoundWindow($f)

    $ok = ($f.ShowDialog($ownerWnd) -eq 'OK')
    $val = $txt.Text
    $f.Dispose()
    if ($ok) { return $val }
    return $null
}

function Show-TIToast {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('Success','Error','Warn','Info')][string]$Type = 'Info',
        [int]$Duration = 2800
    )
    if (-not $global:Form) { return }

    if ($global:ActiveToast) {
        try { if ($global:ActiveToastTimer) { $global:ActiveToastTimer.Stop(); $global:ActiveToastTimer.Dispose() } } catch { }
        try { $global:ActiveToast.Close(); $global:ActiveToast.Dispose() } catch { }
        $global:ActiveToast = $null
        $global:ActiveToastTimer = $null
    }

    $pair = switch ($Type) {
        'Success' { @{ Icon = 'Completed'; Color = $global:Pal.Success } }
        'Error'   { @{ Icon = 'Error'; Color = $global:Pal.Danger } }
        'Warn'    { @{ Icon = 'Warning'; Color = $global:Pal.Warning } }
        default   { @{ Icon = 'Info'; Color = $global:Pal.Primary } }
    }

    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.ShowInTaskbar = $false
    $f.TopMost = $true
    $f.StartPosition = 'Manual'
    $f.BackColor = $global:Pal.CardAlt
    $f.Opacity = 0
    $f.AutoScaleMode = 'None'

    # Faixa de cor à esquerda indica o tipo do aviso
    $accent = New-Object System.Windows.Forms.Panel
    $accent.BackColor = $pair.Color
    $accent.Dock = 'Left'
    $accent.Width = 3
    $f.Controls.Add($accent)

    $g = New-TIGlyph -Icon $pair.Icon -Size 14 -Color $pair.Color
    $g.Location = New-Object System.Drawing.Point(18, 17)
    $f.Controls.Add($g)

    $lbl = New-TILabel -Text $Text -Size 9.5
    $lbl.Location = New-Object System.Drawing.Point(44, 17)
    $lbl.AutoSize = $true
    $lbl.MaximumSize = New-Object System.Drawing.Size(360, 0)
    $f.Controls.Add($lbl)

    $f.PerformLayout()
    $w = [Math]::Min(430, (44 + $lbl.Width + 22))
    $h = [Math]::Max(52, $lbl.Height + 34)
    $f.ClientSize = New-Object System.Drawing.Size($w, $h)
    Add-TIDialogFrame $f

    $area = [System.Windows.Forms.Screen]::FromControl($global:Form).WorkingArea
    $f.Location = New-Object System.Drawing.Point(($area.Right - $w - 22), ($area.Bottom - $h - 22))

    [void][TISuite.Native]::RoundWindow($f)

    $global:ActiveToast = $f
    [TISuite.Native]::ShowNoActivate($f)

    $state = @{ Phase = 'In'; Steps = 0; Hold = [int]($Duration / 16) }
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 16
    $timer.Add_Tick({
        if ($f.IsDisposed) { try { $timer.Stop(); $timer.Dispose() } catch { }; return }
        $state.Steps++
        switch ($state.Phase) {
            'In' {
                $f.Opacity = [Math]::Min(1.0, $f.Opacity + 0.14)
                if ($f.Opacity -ge 1.0) { $state.Phase = 'Hold' }
            }
            'Hold' {
                if ($state.Steps -ge $state.Hold) { $state.Phase = 'Out' }
            }
            'Out' {
                $f.Opacity = [Math]::Max(0.0, $f.Opacity - 0.10)
                if ($f.Opacity -le 0.0) {
                    $timer.Stop()
                    $timer.Dispose()
                    try { $f.Dispose() } catch { }
                    if ($global:ActiveToast -eq $f) { $global:ActiveToast = $null; $global:ActiveToastTimer = $null }
                }
            }
        }
    }.GetNewClosure())
    $global:ActiveToastTimer = $timer
    $timer.Start()
}

function Show-TIMessage {
    param(
        [string]$Title = 'TI Suite',
        [string]$Message = '',
        [string]$Icon = 'Info',
        [ValidateSet('Primary','Danger','Success')][string]$Style = 'Primary',
        $Owner = $null
    )
    return Show-TIConfirm -Title $Title -Message $Message -ConfirmText 'Entendi' -CancelText 'Fechar' `
                           -Style $Style -Icon $Icon -Force -Owner $Owner
}
