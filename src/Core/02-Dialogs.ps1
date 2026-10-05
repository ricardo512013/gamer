# =====================================================================
# 02-DIALOGS.ps1 - Janelas modais: confirmação, entrada de texto, aviso (toast)
#                  e arquivos (onde salvar e como mostrar, também no WinPE)
# Os handlers dos diálogos rodam enquanto ShowDialog mantém o escopo da função
# ativo, por isso podem referenciar variáveis locais diretamente. O aviso
# (toast) não é modal: os handlers dele usam só $global: e $this.
# =====================================================================

# Dono dos diálogos: a janela principal, quando já está visível
function Get-TIOwner {
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

# Anel de foco visível desde a abertura. Quando o diálogo abre por um clique, o
# Windows esconde o foco até a primeira tecla, e nas confirmações perigosas o
# técnico não via que o Enter aciona "Cancelar".
# WM_CHANGEUISTATE (0x127): UIS_CLEAR (2) na palavra baixa, UISF_HIDEFOCUS (1) na alta.
function Enable-TIFocusCues {
    param($Form)
    try { [void][TISuite.Native]::SendMessage($Form.Handle, 0x127, [IntPtr]0x10002, [IntPtr]::Zero) } catch { }
}

# Moldura comum dos diálogos: ícone, título, botão fechar (Esc), arrastar e borda
function New-TIDialogForm {
    param(
        [string]$Title,
        [string]$Icon = 'Info',
        $IconColor = $null,
        [int]$Width = 470
    )
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = 'None'
    $f.StartPosition = 'CenterParent'
    $f.BackColor = $global:Pal.CardAlt
    $f.ShowInTaskbar = $false
    $f.KeyPreview = $true
    $f.AutoScaleMode = 'None'
    $f.Text = $Title
    $f.Width = $Width

    $ico = New-TIGlyph -Icon $Icon -Size 17 -Color $(if ($IconColor) { $IconColor } else { $global:Pal.Primary })
    $ico.Location = New-Object System.Drawing.Point(22, 19)
    $f.Controls.Add($ico)

    $lblTitle = New-TILabel -Text $Title -Size 11.5 -Bold
    $lblTitle.AutoSize = $false
    $lblTitle.AutoEllipsis = $true
    $lblTitle.Size = New-Object System.Drawing.Size(($Width - 50 - 56), 24)
    $lblTitle.Location = New-Object System.Drawing.Point(50, 18)
    $f.Controls.Add($lblTitle)

    $btnClose = New-TIGlyphButton -Icon 'Close' -Tip 'Fechar (Esc)' -Size 34
    $btnClose.Location = New-Object System.Drawing.Point(($Width - 46), 12)
    $btnClose.Anchor = 'Top,Right'
    $btnClose.TabStop = $false
    $btnClose.Add_Click({
        $d = $this.FindForm()
        if ($d) { $d.DialogResult = 'Cancel'; $d.Close() }
    })
    $f.Controls.Add($btnClose)

    $f.Add_MouseDown({ if ($_.Button -eq 'Left') { [TISuite.Native]::DragWindow($this) } })
    Add-TIDialogFrame $f
    return $f
}

# Janela de mensagem com um ou dois botões: base de Show-TIConfirm e Show-TIMessage.
# Sem -CancelText, só o botão principal (aviso informativo). Devolve $true/$false.
function Invoke-TIMessageDialog {
    param(
        [string]$Title,
        [string]$Message = '',
        [string]$ConfirmText = 'OK',
        [string]$CancelText = '',
        [string]$Style = 'Primary',
        [string]$Icon = 'Info',
        $IconColor = $null
    )

    $padX = 22
    # Botões com largura pelo texto (New-TIButton cresce até caber); a janela
    # também cresce se eles não couberem na largura padrão.
    $btnCancel = $null
    if ($CancelText) { $btnCancel = New-TIButton -Text $CancelText -Style 'Outline' -Width 110 -Height 38 }
    $btnConfirm = New-TIButton -Text $ConfirmText -Style $Style -Width $(if ($btnCancel) { 150 } else { 120 }) -Height 38
    $cancelW = if ($btnCancel) { $btnCancel.Width + 10 } else { 0 }
    $w = [Math]::Max(470, ($padX + $cancelW + $btnConfirm.Width + 18))

    $f = New-TIDialogForm -Title $Title -Icon $Icon -IconColor $IconColor -Width $w

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
        # Mede de novo descontando a barra vertical: sem isso surgia barra
        # horizontal e o fim das linhas ficava embaixo da barra de rolagem.
        $inner = $msgHost.Width - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth - 4
        $lblMsg.MaximumSize = New-Object System.Drawing.Size($inner, 0)
        $lblMsg.Location = New-Object System.Drawing.Point(0, 0)
        $msgHost.Controls.Add($lblMsg)
        $f.Controls.Add($msgHost)
        $msgHost.Add_HandleCreated({ Set-TIDarkScroll $this })
        $msgBottom = 62 + 340
    }

    $y = $msgBottom + 18
    $div = New-Object System.Windows.Forms.Panel
    $div.BackColor = $global:Pal.BorderSoft
    $div.Location = New-Object System.Drawing.Point(0, $y)
    $div.Size = New-Object System.Drawing.Size($w, 1)
    $div.Anchor = 'Top,Left,Right'
    $f.Controls.Add($div)

    $y += 1
    $btnConfirm.Anchor = 'Top,Right'
    $btnConfirm.Location = New-Object System.Drawing.Point(($w - $btnConfirm.Width - 18), ($y + 16))
    $btnConfirm.Add_Click({ $f.DialogResult = 'OK'; $f.Close() })
    if ($btnCancel) {
        $btnCancel.Anchor = 'Top,Right'
        $btnCancel.Location = New-Object System.Drawing.Point(($btnConfirm.Location.X - $btnCancel.Width - 10), ($y + 16))
        $btnCancel.Add_Click({ $f.DialogResult = 'Cancel'; $f.Close() })
        if ($Style -eq 'Danger') {
            $btnCancel.TabIndex = 0; $btnConfirm.TabIndex = 1
        } else {
            $btnConfirm.TabIndex = 0; $btnCancel.TabIndex = 1
        }
        $f.Controls.Add($btnCancel)
    } else {
        $btnConfirm.TabIndex = 0
    }
    $f.Controls.Add($btnConfirm)

    # Altura exata do conteúdo (sem altura mínima: ela deixava um vão abaixo dos botões)
    $f.ClientSize = New-Object System.Drawing.Size($w, ($btnConfirm.Bottom + 18))

    $f.Add_Shown({
        Enable-TIFocusCues $f
        if ($btnCancel -and $Style -eq 'Danger') { [void]$btnCancel.Focus() } else { [void]$btnConfirm.Focus() }
    })
    $f.Add_KeyDown({
        if ($_.KeyCode -eq 'Escape') { $f.DialogResult = 'Cancel'; $f.Close(); return }
        if ($_.KeyCode -eq 'Enter') {
            $_.SuppressKeyPress = $true
            if ($btnCancel -and $f.ActiveControl -eq $btnCancel) { $f.DialogResult = 'Cancel'; $f.Close() }
            elseif ($f.ActiveControl -eq $btnConfirm -or $Style -ne 'Danger') { $f.DialogResult = 'OK'; $f.Close() }
        }
    })

    [void][TISuite.Native]::RoundWindow($f)

    $result = $f.ShowDialog((Get-TIOwner))
    $f.Dispose()
    return ($result -eq 'OK')
}

function Show-TIConfirm {
    <#
      Pede confirmação e devolve $true (confirmou) ou $false.
      Estilo Danger: o foco começa em "Cancelar" e o Enter NÃO confirma sozinho
      (só aciona o botão que estiver com foco). A confirmação é sempre pedida.
    #>
    param(
        [string]$Title = 'Confirmar operação',
        [string]$Message = '',
        [string]$ConfirmText = 'Confirmar',
        [string]$CancelText = 'Cancelar',
        [ValidateSet('Primary','Danger','Success')][string]$Style = 'Primary',
        [string]$Icon = 'Warning'
    )
    $icoColor = switch ($Style) {
        'Danger'  { $global:Pal.Danger }
        'Success' { $global:Pal.Success }
        default   { if ($Icon -eq 'Warning') { $global:Pal.Warning } else { $global:Pal.Primary } }
    }
    return (Invoke-TIMessageDialog -Title $Title -Message $Message -ConfirmText $ConfirmText `
                -CancelText $(if ($CancelText) { $CancelText } else { 'Cancelar' }) -Style $Style -Icon $Icon -IconColor $icoColor)
}

# Aviso informativo com um único botão ("Entendi"). Não devolve nada.
function Show-TIMessage {
    param(
        [string]$Title = 'TI Suite',
        [string]$Message = '',
        [string]$Icon = 'Info',
        [string]$OkText = 'Entendi'
    )
    $icoColor = switch ($Icon) {
        'Warning' { $global:Pal.Warning }
        'Error'   { $global:Pal.Danger }
        default   { $global:Pal.Primary }
    }
    [void](Invoke-TIMessageDialog -Title $Title -Message $Message -ConfirmText $OkText -Style 'Primary' -Icon $Icon -IconColor $icoColor)
}

function Show-TIInput {
    <#
      Caixa de entrada de texto. Devolve o texto digitado ou $null (cancelou).
        -Password   oculta o texto (com "Mostrar senha")
        -Confirm    segunda caixa "Repita a senha" (ou "Repita o valor"); só
                    confirma quando as duas são iguais
        -Required   não aceita vazio
        -Numeric    só dígitos de 0 a 9
        -MaxLength  limite de caracteres (0 = sem limite)
        -Validate   { param($t) ... } devolve '' (ou $null) quando o valor serve,
                    ou a mensagem de erro, que aparece no próprio diálogo sem fechá-lo
      Os erros aparecem dentro do diálogo; o foco volta para a caixa com problema.
    #>
    param(
        [string]$Title = 'Entrada',
        [string]$Message = '',
        [string]$Label = 'Valor',
        [string]$Value = '',
        [switch]$Password,
        [switch]$Confirm,
        [switch]$Required,
        [switch]$Numeric,
        [int]$MaxLength = 0,
        [scriptblock]$Validate = $null,
        [string]$OkText = 'Aplicar'
    )

    $padX = 22
    $btnCancel = New-TIButton -Text 'Cancelar' -Style 'Outline' -Width 110 -Height 38
    $btnOk = New-TIButton -Text $OkText -Style 'Primary' -Width 150 -Height 38
    $w = [Math]::Max(430, ($padX + $btnCancel.Width + 10 + $btnOk.Width + 18))
    $fieldW = $w - $padX * 2

    $f = New-TIDialogForm -Title $Title -Icon $(if ($Password) { 'Lock' } else { 'Edit' }) -IconColor $global:Pal.Primary -Width $w

    $y = 60
    if ($Message) {
        $lblMsg = New-TILabel -Text $Message -Size 9 -Muted
        $lblMsg.Location = New-Object System.Drawing.Point($padX, $y)
        $lblMsg.MaximumSize = New-Object System.Drawing.Size($fieldW, 0)
        $lblMsg.AutoSize = $true
        $f.Controls.Add($lblMsg)
        $y += $lblMsg.Height + 12
    }

    $lblField = New-TILabel -Text $Label -Size 8.5 -Muted
    $lblField.Location = New-Object System.Drawing.Point($padX, $y)
    $f.Controls.Add($lblField)
    $y += 19

    $boxes = New-Object System.Collections.ArrayList
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point($padX, $y)
    $txt.Text = $Value
    [void]$boxes.Add($txt)
    $y += 34

    $txt2 = $null
    if ($Confirm) {
        $lblField2 = New-TILabel -Text $(if ($Password) { 'Repita a senha' } else { 'Repita o valor' }) -Size 8.5 -Muted
        $lblField2.Location = New-Object System.Drawing.Point($padX, $y)
        $f.Controls.Add($lblField2)
        $y += 19
        $txt2 = New-Object System.Windows.Forms.TextBox
        $txt2.Location = New-Object System.Drawing.Point($padX, $y)
        [void]$boxes.Add($txt2)
        $y += 34
    }

    $tab = 0
    foreach ($b in $boxes) {
        $b.Size = New-Object System.Drawing.Size($fieldW, 30)
        $b.Anchor = 'Top,Left,Right'
        $b.BackColor = $global:Pal.Bg
        $b.ForeColor = $global:Pal.TextMain
        $b.Font = New-TIFont 10
        $b.BorderStyle = 'FixedSingle'
        $b.UseSystemPasswordChar = $Password.IsPresent
        if ($MaxLength -gt 0) { $b.MaxLength = $MaxLength }
        $b.TabIndex = $tab
        $tab++
        $f.Controls.Add($b)
    }

    if ($Password) {
        $sw = New-Object TISuite.ToggleSwitch
        $sw.Location = New-Object System.Drawing.Point($padX, $y)
        $sw.TabIndex = $tab
        $tab++
        $sw.Add_CheckedChanged({
            foreach ($b in $boxes) { $b.UseSystemPasswordChar = -not $sw.Checked }
        })
        $f.Controls.Add($sw)
        $swLbl = New-TILabel -Text 'Mostrar senha' -Size 8.5 -Muted
        $swLbl.Location = New-Object System.Drawing.Point(($padX + 50), ($y + 3))
        $swLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
        $swLbl.Add_Click({ $sw.Checked = -not $sw.Checked })
        $f.Controls.Add($swLbl)
        $y += 32
    }

    # Aviso de erro dentro do diálogo (quebra em até duas linhas; a janela acompanha)
    $lblErr = New-TILabel -Text '' -Size 8.5 -Color $global:Pal.Danger
    $lblErr.MaximumSize = New-Object System.Drawing.Size($fieldW, 0)
    $lblErr.Location = New-Object System.Drawing.Point($padX, $y)
    $f.Controls.Add($lblErr)
    $errTop = $y

    $div = New-Object System.Windows.Forms.Panel
    $div.BackColor = $global:Pal.BorderSoft
    $div.Size = New-Object System.Drawing.Size($w, 1)
    $div.Anchor = 'Top,Left,Right'
    $f.Controls.Add($div)

    $btnOk.Anchor = 'Top,Right'
    $btnCancel.Anchor = 'Top,Right'
    $btnOk.TabIndex = $tab
    $btnCancel.TabIndex = $tab + 1
    $btnOk.Left = $w - $btnOk.Width - 18
    $btnCancel.Left = $btnOk.Left - $btnCancel.Width - 10
    $f.Controls.Add($btnCancel)
    $f.Controls.Add($btnOk)

    $layoutBottom = {
        $gap = [Math]::Max(22, ($lblErr.Height + 6))
        $div.Top = $errTop + $gap
        $btnOk.Top = $div.Top + 16
        $btnCancel.Top = $div.Top + 16
        $f.ClientSize = New-Object System.Drawing.Size($w, ($btnOk.Bottom + 18))
        $f.Invalidate()
    }
    $showError = {
        param([string]$Text, $Focus)
        $lblErr.Text = $Text
        & $layoutBottom
        if ($Focus) { [void]$Focus.Focus(); $Focus.SelectAll() }
    }
    & $layoutBottom

    if ($Numeric) {
        foreach ($b in $boxes) {
            $b.Add_KeyPress({
                # Teclas de controle (apagar, Ctrl+V, Ctrl+C...) passam; o colado é conferido no OK
                $n = [int]$_.KeyChar
                if ($n -ge 32 -and $n -ne 127 -and ($n -lt 48 -or $n -gt 57)) {
                    $_.Handled = $true
                    & $showError 'Digite só números (0 a 9).' $null
                }
            })
        }
    }
    foreach ($b in $boxes) {
        $b.Add_TextChanged({ if ($lblErr.Text) { $lblErr.Text = ''; & $layoutBottom } })
    }

    $btnCancel.Add_Click({ $f.DialogResult = 'Cancel'; $f.Close() })
    $btnOk.Add_Click({
        $v = $txt.Text
        $t = $v.Trim()
        $err = ''
        $bad = $txt
        if ($Required -and $t -eq '') {
            $err = 'Preencha este campo para continuar.'
        } elseif ($Numeric -and $t -ne '' -and $t -notmatch '^[0-9]+$') {
            $err = 'Digite só números (0 a 9).'
        } elseif ($Validate) {
            try {
                $r = @(& $Validate $v) | Select-Object -Last 1
                if ($r -is [bool]) { $err = $(if ($r) { '' } else { 'Valor inválido.' }) }
                elseif ($null -ne $r) { $err = [string]$r }
            } catch {
                $err = ('Valor inválido: {0}' -f $_.Exception.Message)
            }
        }
        if (-not $err -and $txt2 -and $txt2.Text -cne $v) {
            $err = 'Os valores não conferem. Digite o mesmo valor nas duas caixas.'
            if ($Password) { $err = 'As senhas não conferem. Digite a mesma senha nas duas caixas.' }
            $bad = $txt2
        }
        if ($err) {
            & $showError $err $bad
            return
        }
        $f.DialogResult = 'OK'
        $f.Close()
    })

    $f.Add_Shown({
        Enable-TIFocusCues $f
        [void]$txt.Focus()
        $txt.SelectAll()
    })
    $f.Add_KeyDown({
        if ($_.KeyCode -eq 'Escape') { $f.DialogResult = 'Cancel'; $f.Close(); return }
        if ($_.KeyCode -eq 'Enter') {
            $_.SuppressKeyPress = $true
            if ($f.ActiveControl -eq $btnCancel) { $f.DialogResult = 'Cancel'; $f.Close() }
            elseif ($txt2 -and $f.ActiveControl -eq $txt -and $txt2.Text -eq '') { [void]$txt2.Focus() }
            else { $btnOk.PerformClick() }
        }
    })

    [void][TISuite.Native]::RoundWindow($f)

    $ok = ($f.ShowDialog((Get-TIOwner)) -eq 'OK')
    $val = $txt.Text
    $f.Dispose()
    if ($ok) { return $val }
    return $null
}

# ---------------------------------------------------------------------
# Arquivos: onde salvar e como mostrar. O WinPE do pendrive de recuperação
# não tem Explorer, e o diálogo "Salvar como" não é confiável nele: lá o
# arquivo vai direto para uma pasta do app (logs\, laudos\...) na partição
# TI-SUITE, e quem chama mostra o caminho num aviso.
# ---------------------------------------------------------------------

# Bloco de notas do Windows (existe também no WinPE)
function Get-TINotepadPath {
    try {
        $p = Join-Path $env:SystemRoot 'System32\notepad.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    } catch { }
    return 'notepad.exe'
}

# Caminho livre na pasta: 'laudo.txt' vira 'laudo (2).txt' quando já existe
function Get-TIUniquePath {
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$FileName)
    $path = Join-Path $Dir $FileName
    if (-not (Test-Path -LiteralPath $path)) { return $path }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext = [System.IO.Path]::GetExtension($FileName)
    for ($i = 2; $i -lt 1000; $i++) {
        $p = Join-Path $Dir ('{0} ({1}){2}' -f $base, $i, $ext)
        if (-not (Test-Path -LiteralPath $p)) { return $p }
    }
    return $path
}

function Select-TISaveFile {
    <#
      Caminho para salvar um arquivo; $null = cancelou (ou não há onde gravar).
        -FileName  nome sugerido
        -Folder    subpasta do app (logs, laudos, relatorios...): pasta inicial do
                   diálogo no modo portátil e destino direto no WinPE
      Fora do WinPE: diálogo "Salvar como". No WinPE: <app>\<Folder>\<FileName>
      (cria a pasta e não sobrescreve); avise o caminho com Show-TIToast.
    #>
    param(
        [string]$Title = 'Salvar',
        [string]$Filter = 'Todos os arquivos (*.*)|*.*',
        [string]$FileName = '',
        [string]$Folder = 'logs'
    )
    $dir = $null
    $base = if (Get-Command Get-TIAppDataDir -ErrorAction SilentlyContinue) { Get-TIAppDataDir } else { $global:TIRoot }
    if ($base) { $dir = $(if ($Folder) { Join-Path $base $Folder } else { $base }) }

    if ($global:TIWinPE) {
        if (-not $dir) { return $null }
        try {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
        } catch {
            Show-TIToast -Text ('Não deu para criar a pasta {0} (pendrive protegido contra gravação ou cheio?).' -f $dir) -Type 'Error'
            return $null
        }
        $name = if ($FileName) { $FileName } else { 'TI-Suite-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmm') }
        return (Get-TIUniquePath -Dir $dir -FileName $name)
    }

    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    try {
        $dlg.Title = $Title
        $dlg.Filter = $Filter
        if ($FileName) { $dlg.FileName = $FileName }
        # Modo portátil: abre na pasta do pendrive, não nos Documentos do PC atendido
        if ($global:TIPortable -and $dir -and (Test-Path -LiteralPath $dir)) { $dlg.InitialDirectory = $dir }
        $owner = Get-TIOwner
        $res = if ($owner) { $dlg.ShowDialog($owner) } else { $dlg.ShowDialog() }
        if ($res -ne 'OK') { return $null }
        return $dlg.FileName
    } finally {
        $dlg.Dispose()
    }
}

function Open-TIFile {
    <#
      Mostra um arquivo ou pasta gravado pelo app. Devolve $true se abriu algo.
      Fora do WinPE: Explorer (arquivo selecionado na pasta dele; pasta aberta).
      No WinPE (sem Explorer): arquivos de texto abrem no Bloco de notas (o
      Arquivo > Abrir dele serve para navegar nas pastas); o resto (pastas,
      outros tipos) mostra o caminho num aviso.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Show-TIToast -Text ('Não encontrado: {0}' -f $Path) -Type 'Warn'
        return $false
    }
    try {
        if ($global:TIWinPE) {
            $isText = (Test-Path -LiteralPath $Path -PathType Leaf) -and
                      ([System.IO.Path]::GetExtension($Path) -match '^\.(txt|log|csv|xml|json|ini|cfg|md)$')
            if ($isText) {
                Start-Process -FilePath (Get-TINotepadPath) -ArgumentList ('"{0}"' -f $Path) -ErrorAction Stop
                return $true
            }
            Show-TIToast -Text ('Caminho: {0}' -f $Path) -Type 'Info' -Duration 8000
            return $false
        }
        if (Test-Path -LiteralPath $Path -PathType Container) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $Path) -ErrorAction Stop
        } else {
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $Path) -ErrorAction Stop
        }
        return $true
    } catch {
        Show-TIToast -Text ('Não deu para abrir {0}: {1}' -f $Path, $_.Exception.Message) -Type 'Error'
        return $false
    }
}

# ---------------------------------------------------------------------
# Avisos (toasts)
#   - um por vez, no canto inferior direito da janela principal, acima da
#     barra de status (no canto da tela se a janela estiver minimizada);
#   - tempo pelo tamanho do texto: 60 ms por caractere (mínimo 2,8 s),
#     1,5x para aviso e 2x para erro (máximo 16 s); -Duration só aumenta;
#   - mouse em cima pausa a contagem; clique fecha;
#   - um aviso de erro visível não é trocado por outro: os seguintes esperam
#     na fila até ele sair (o mesmo vale para Info/OK sobre um aviso);
#   - no WinPE (sem DWM) aparece e some sem esmaecer: nada de janela em camadas.
# ---------------------------------------------------------------------
$global:ActiveToast = $null
$global:TIToastQueue = New-Object System.Collections.ArrayList

function Get-TIToastRank {
    param([string]$Type)
    if ($Type -eq 'Error') { return 2 }
    if ($Type -eq 'Warn') { return 1 }
    return 0
}

function Get-TIToastDuration {
    param([string]$Text, [string]$Type = 'Info')
    $ms = [Math]::Max(2800, 60 * $Text.Length)
    if ($Type -eq 'Error') { $ms = $ms * 2 }
    elseif ($Type -eq 'Warn') { $ms = [int]($ms * 1.5) }
    return [int][Math]::Min(16000, $ms)
}

function Show-TIToast {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('Success','Error','Warn','Info')][string]$Type = 'Info',
        # Tempo mínimo em ms; vale o maior entre ele e o automático (pelo tamanho do texto)
        [int]$Duration = 0
    )
    if (-not $global:Form) { return }
    $req = @{ Text = $Text; Type = $Type; Duration = $Duration }

    $cur = $global:ActiveToast
    if ($cur -and -not $cur.Form.IsDisposed -and $cur.Phase -ne 'Out') {
        # Mesmo aviso de novo: só reinicia o tempo
        if ($cur.Text -ceq $Text -and $cur.Type -eq $Type) { $cur.Held = 0; return }
        $rc = Get-TIToastRank $cur.Type
        $rn = Get-TIToastRank $Type
        if ($rc -eq 2 -or $rn -lt $rc -or ($global:TIToastQueue.Count -gt 0 -and $rn -le $rc)) {
            Add-TIToastToQueue $req
            return
        }
    }
    Close-TIToast
    Open-TIToast $req
}

function Add-TIToastToQueue {
    param($Req)
    foreach ($q in $global:TIToastQueue) {
        if ($q.Text -ceq $Req.Text -and $q.Type -eq $Req.Type) { return }
    }
    if ($global:TIToastQueue.Count -ge 4) {
        # Fila cheia: sai o mais antigo de menor importância (ou o novo, se for o menor)
        $drop = 0; $low = 9
        for ($i = 0; $i -lt $global:TIToastQueue.Count; $i++) {
            $r = Get-TIToastRank $global:TIToastQueue[$i].Type
            if ($r -lt $low) { $low = $r; $drop = $i }
        }
        if ((Get-TIToastRank $Req.Type) -lt $low) { return }
        $global:TIToastQueue.RemoveAt($drop)
    }
    [void]$global:TIToastQueue.Add($Req)
}

# Próximo da fila: o mais importante primeiro (erro, aviso, o resto); empate, o mais antigo
function Show-TIToastNext {
    if ($global:ActiveToast -or $global:TIToastQueue.Count -eq 0) { return }
    $pick = 0; $best = -1
    for ($i = 0; $i -lt $global:TIToastQueue.Count; $i++) {
        $r = Get-TIToastRank $global:TIToastQueue[$i].Type
        if ($r -gt $best) { $best = $r; $pick = $i }
    }
    $req = $global:TIToastQueue[$pick]
    $global:TIToastQueue.RemoveAt($pick)
    Open-TIToast $req
}

# Fecha na hora o aviso visível (sem puxar a fila)
function Close-TIToast {
    $st = $global:ActiveToast
    $global:ActiveToast = $null
    if (-not $st) { return }
    try { $st.Timer.Stop(); $st.Timer.Dispose() } catch { }
    try { $st.Form.Close(); $st.Form.Dispose() } catch { }
}

# Clique no aviso: some rápido e dá lugar ao próximo da fila
function Hide-TIToast {
    $st = $global:ActiveToast
    if ($st -and $st.Phase -ne 'Out') { $st.Phase = 'Out'; $st.Fade = 0.25 }
}

function Get-TIToastLocation {
    param([int]$Width, [int]$Height)
    $main = $global:Form
    $area = [System.Windows.Forms.Screen]::FromControl($main).WorkingArea
    $x = $area.Right - $Width - 22
    $y = $area.Bottom - $Height - 22
    try {
        if ($main.Visible -and $main.WindowState -ne 'Minimized') {
            $b = $main.Bounds
            $status = if ($global:StatusBar -and $global:StatusBar.Visible) { $global:StatusBar.Height } else { 0 }
            $x = $b.Right - $Width - 18
            $y = $b.Bottom - $status - $Height - 14
        }
    } catch { }
    $x = [Math]::Max(($area.Left + 8), [Math]::Min($x, ($area.Right - $Width - 8)))
    $y = [Math]::Max(($area.Top + 8), [Math]::Min($y, ($area.Bottom - $Height - 8)))
    return (New-Object System.Drawing.Point($x, $y))
}

function Open-TIToast {
    param($Req)
    $pair = switch ($Req.Type) {
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
    $fade = -not $global:TIWinPE
    if ($fade) { $f.Opacity = 0 }
    $f.AutoScaleMode = 'None'
    $f.Cursor = [System.Windows.Forms.Cursors]::Hand

    # Faixa de cor à esquerda indica o tipo do aviso
    $accent = New-Object System.Windows.Forms.Panel
    $accent.BackColor = $pair.Color
    $accent.Dock = 'Left'
    $accent.Width = 3
    $f.Controls.Add($accent)

    $g = New-TIGlyph -Icon $pair.Icon -Size 14 -Color $pair.Color
    $g.Location = New-Object System.Drawing.Point(18, 17)
    $f.Controls.Add($g)

    $lbl = New-TILabel -Text $Req.Text -Size 9.5
    $lbl.Location = New-Object System.Drawing.Point(44, 17)
    $lbl.AutoSize = $true
    $lbl.MaximumSize = New-Object System.Drawing.Size(360, 0)
    $f.Controls.Add($lbl)

    $f.PerformLayout()
    $w = [Math]::Min(430, (44 + $lbl.Width + 22))
    $h = [Math]::Max(52, $lbl.Height + 34)
    $f.ClientSize = New-Object System.Drawing.Size($w, $h)
    Add-TIDialogFrame $f
    $f.Location = Get-TIToastLocation -Width $w -Height $h

    [void][TISuite.Native]::RoundWindow($f)

    $ms = [Math]::Max($Req.Duration, (Get-TIToastDuration -Text $Req.Text -Type $Req.Type))
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 16
    $global:ActiveToast = @{
        Form = $f; Timer = $timer; Text = $Req.Text; Type = $Req.Type
        Phase = $(if ($fade) { 'In' } else { 'Hold' }); Held = 0; Hold = [int][Math]::Ceiling($ms / 16); Fade = 0.10
        NoFade = (-not $fade)
    }

    foreach ($c in @($f, $accent, $g, $lbl)) { $c.Add_Click({ Hide-TIToast }) }
    $timer.Add_Tick({ param($s, $e) Step-TIToast -Timer $s })

    [TISuite.Native]::ShowNoActivate($f)
    $timer.Start()
}

function Step-TIToast {
    param($Timer)
    $st = $global:ActiveToast
    if (-not $st -or -not [object]::ReferenceEquals($st.Timer, $Timer)) {
        # Temporizador de um aviso que já saiu
        try { $Timer.Stop(); $Timer.Dispose() } catch { }
        return
    }
    $f = $st.Form
    if ($f.IsDisposed) { Close-TIToast; Show-TIToastNext; return }
    switch ($st.Phase) {
        'In' {
            $f.Opacity = [Math]::Min(1.0, $f.Opacity + 0.14)
            if ($f.Opacity -ge 1.0) { $st.Phase = 'Hold' }
        }
        'Hold' {
            # Mouse em cima pausa a contagem (dá tempo de ler)
            $over = $false
            try { $over = $f.Bounds.Contains([System.Windows.Forms.Control]::MousePosition) } catch { }
            if (-not $over) { $st.Held++ }
            if ($st.Held -ge $st.Hold) { $st.Phase = 'Out' }
        }
        'Out' {
            if (-not $st.NoFade) { $f.Opacity = [Math]::Max(0.0, $f.Opacity - $st.Fade) }
            if ($st.NoFade -or $f.Opacity -le 0.0) {
                Close-TIToast
                Show-TIToastNext
            }
        }
    }
}
