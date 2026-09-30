# =====================================================================
# ÁREA: CONTAS - contas locais, senhas, bloqueios e administradores
# =====================================================================

$global:Contas = @{
    Grid        = $null
    Selected    = $null
    Users       = @()
    PassBox     = $null
    PassInfo    = $null
    SelLabel    = $null
    Segments    = @()
    BtnApply    = $null
    BtnRemovePw = $null
    BtnEnable   = $null
    BtnDisable  = $null
    BtnAdmin    = $null
    BtnDeadmin  = $null
    Hint        = $null
    CountLabel  = $null
}

function Get-TIPasswordStrength {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $score = 0
    if ($Text.Length -ge 6) { $score = 1 }
    if ($Text.Length -ge 8) { $score = 2 }
    if ($Text.Length -ge 8 -and $Text -cmatch '[a-z]' -and $Text -cmatch '[A-Z]') { $score = 3 }
    if ($Text.Length -ge 10 -and $Text -match '\d' -and $Text -match '[^a-zA-Z0-9]') { $score = 4 }
    return $score
}

function Update-ContaPasswordMeter {
    $box = $global:Contas.PassBox
    if (-not $box) { return }
    $score = Get-TIPasswordStrength $box.Text
    $colors = @($global:Pal.Danger, $global:Pal.Danger, $global:Pal.Warning, $global:Pal.Primary, $global:Pal.Success)
    for ($i = 0; $i -lt $global:Contas.Segments.Count; $i++) {
        $seg = $global:Contas.Segments[$i]
        $seg.FillColor = $(if ($i -lt $score) { $colors[$score] } else { $global:Pal.BorderSoft })
        $seg.Invalidate()
    }
    $txt = switch ($score) { 0 { 'Digite a nova senha' } 1 { 'Muito fraca' } 2 { 'Fraca' } 3 { 'Razoável' } 4 { 'Forte' } }
    $col = switch ($score) { 0 { $global:Pal.TextDim } 1 { $global:Pal.Danger } 2 { $global:Pal.Danger } 3 { $global:Pal.Warning } 4 { $global:Pal.Success } }
    if ($global:Contas.PassInfo) {
        $global:Contas.PassInfo.Text = $txt
        $global:Contas.PassInfo.ForeColor = $col
    }
}

function Update-ContaSelectionUI {
    $sel = $global:Contas.Selected
    $hasSel = ($null -ne $sel)
    $isSelf = ($hasSel -and $sel.Name -eq $env:USERNAME)
    $busy = $global:TI.Busy

    if ($global:Contas.SelLabel) {
        $global:Contas.SelLabel.Text = if (-not $hasSel) { 'Nenhuma conta selecionada' }
            elseif ($isSelf) { $sel.Name + ' (conta em uso: senha protegida)' }
            else { 'Conta: ' + $sel.Name }
        $global:Contas.SelLabel.ForeColor = if (-not $hasSel) { $global:Pal.TextDim } elseif ($isSelf) { $global:Pal.Warning } else { $global:Pal.Primary }
    }

    $pwOk = ($hasSel -and -not $isSelf -and -not $busy)
    if ($global:Contas.BtnApply)    { $global:Contas.BtnApply.Enabled = $pwOk }
    if ($global:Contas.BtnRemovePw) { $global:Contas.BtnRemovePw.Enabled = $pwOk }
    if ($global:Contas.PassBox)     { $global:Contas.PassBox.Enabled = $pwOk }

    if ($global:Contas.BtnEnable)  { $global:Contas.BtnEnable.Enabled = ($hasSel -and -not $busy) }
    if ($global:Contas.BtnDisable) { $global:Contas.BtnDisable.Enabled = ($hasSel -and -not $isSelf -and -not $busy -and $sel.Enabled) }
    if ($global:Contas.BtnAdmin)   { $global:Contas.BtnAdmin.Enabled = ($hasSel -and -not $busy -and -not $sel.Admin) }
    if ($global:Contas.BtnDeadmin) { $global:Contas.BtnDeadmin.Enabled = ($hasSel -and -not $busy -and -not $isSelf -and $sel.Admin) }

    if ($global:Contas.Hint) {
        $h = $global:Contas.Hint
        if (-not $hasSel) { $h.Text = 'Selecione uma conta na lista.'; $h.ForeColor = $global:Pal.TextMuted }
        elseif (-not $global:TI.Elevated) { $h.Text = 'Estas ações precisam do TI Suite aberto como administrador (clique no selo da barra lateral).'; $h.ForeColor = $global:Pal.Warning }
        elseif ($sel.Locked) { $h.Text = ('"{0}" está bloqueada por tentativas de senha: use Ativar / desbloquear.' -f $sel.Name); $h.ForeColor = $global:Pal.Warning }
        elseif (-not $sel.Enabled) { $h.Text = ('"{0}" está desativada: use Ativar / desbloquear.' -f $sel.Name); $h.ForeColor = $global:Pal.TextMuted }
        else { $h.Text = ('Ações aplicadas a: {0}' -f $sel.Name); $h.ForeColor = $global:Pal.TextMuted }
    }
    Update-ContaPasswordMeter
}

function Refresh-ContasList {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Leitura das contas locais' -Quiet -Script {
        Get-TIAccounts
    } -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Name'] })
        $global:Contas.Users = $rows
        $grid = $global:Contas.Grid
        if ($grid) {
            $grid.Rows.Clear()
            foreach ($u in $rows) {
                $state = if ($u.Locked) { 'Bloqueada' } elseif (-not $u.Enabled) { 'Desativada' } else { 'Ativa' }
                $adm = if (-not $u.AdminKnown) { '?' } elseif ($u.Admin) { 'Sim' } else { 'Não' }
                $row = Add-TIRow -Grid $grid -Cells @($u.Name, $state, $adm, $u.Description, (Format-TIDate $u.LastLogon)) -Tag $u
                if ($u.Locked) { $row.Cells[1].Style.ForeColor = $global:Pal.Warning }
                elseif (-not $u.Enabled) { $row.Cells[1].Style.ForeColor = $global:Pal.TextDim }
            }
            Clear-TIGridSelection $grid
        }
        $global:Contas.Selected = $null
        Update-ContaSelectionUI
        if ($global:Contas.CountLabel) {
            $locked = @($rows | Where-Object { $_.Locked }).Count
            $global:Contas.CountLabel.Text = ('{0} conta(s) local(is){1}' -f $rows.Count, $(if ($locked -gt 0) { ', ' + $locked + ' bloqueada(s)' } else { '' }))
        }
    })
}

function Select-ContaAtual {
    $grid = $global:Contas.Grid
    if (-not $grid -or $grid.SelectedRows.Count -eq 0) { $global:Contas.Selected = $null }
    else { $global:Contas.Selected = $grid.SelectedRows[0].Tag }
    Update-ContaSelectionUI
}

function Invoke-ContaApplyPassword {
    Select-ContaAtual
    $sel = $global:Contas.Selected
    if (-not $sel) { Show-TIToast -Text 'Selecione uma conta.' -Type 'Warn'; return }
    if ($sel.Name -eq $env:USERNAME) { Show-TIToast -Text 'A senha da conta em uso não é alterada por aqui.' -Type 'Error'; return }

    $pw = $global:Contas.PassBox.Text
    if ($pw.Length -eq 0) { Show-TIToast -Text 'Digite a nova senha.' -Type 'Warn'; return }
    if ($pw.Length -lt 6) {
        $ok = Show-TIConfirm -Title 'Senha muito curta' -Style 'Danger' -Icon 'Warning' -Force `
                -Message ("A senha tem só {0} caractere(s) e pode ser recusada pela política da rede.`nAplicar assim mesmo?" -f $pw.Length) `
                -ConfirmText 'Aplicar mesmo assim'
        if (-not $ok) { return }
    }
    [void](Invoke-TIAsync -Name ('Nova senha para ' + $sel.Name) -RequiresAdmin `
            -Context @{ User = $sel.Name; Password = $pw } -Script {
        Set-TIAccountPassword -User $Context.User -Password $Context.Password
    } -OnComplete {
        param($r)
        if ($global:Contas.PassBox) { $global:Contas.PassBox.Text = '' }
        Update-ContaPasswordMeter
        Refresh-ContasList
    })
}

function Invoke-ContaRemovePassword {
    Select-ContaAtual
    $sel = $global:Contas.Selected
    if (-not $sel) { Show-TIToast -Text 'Selecione uma conta.' -Type 'Warn'; return }
    $res = Show-TIConfirm -Title 'Remover a senha da conta' -Style 'Danger' -Icon 'Lock' -Force `
            -Message ("A conta '{0}' vai entrar sem pedir senha. Use só em computador de laboratório ou almoxarifado." -f $sel.Name) `
            -ConfirmText 'Remover senha'
    if (-not $res) { return }
    [void](Invoke-TIAsync -Name ('Remoção da senha de ' + $sel.Name) -RequiresAdmin -Context @{ User = $sel.Name } -Script {
        Set-TIAccountPassword -User $Context.User -Remove
    } -OnComplete { param($r) Refresh-ContasList })
}

function Invoke-ContaToggleEnable {
    param([switch]$Disable)
    Select-ContaAtual
    $sel = $global:Contas.Selected
    if (-not $sel) { Show-TIToast -Text 'Selecione uma conta.' -Type 'Warn'; return }
    if ($Disable) {
        if ($sel.Name -eq $env:USERNAME) { Show-TIToast -Text 'A conta em uso não pode ser desativada.' -Type 'Error'; return }
        $res = Show-TIConfirm -Title 'Desativar conta' -Style 'Danger' -Icon 'Warning' -Force `
                -Message ("'{0}' não vai conseguir entrar até ser reativada." -f $sel.Name) `
                -ConfirmText 'Desativar'
        if (-not $res) { return }
    }
    $name = $sel.Name
    [void](Invoke-TIAsync -Name $(if ($Disable) { 'Desativação de ' + $name } else { 'Ativação de ' + $name }) -RequiresAdmin `
            -Context @{ User = $name; Disable = [bool]$Disable } -Script {
        Enable-TIAccount -User $Context.User -Disable:$Context.Disable
    } -OnComplete { param($r) Refresh-ContasList })
}

function Invoke-ContaToggleAdmin {
    param([switch]$Remove)
    Select-ContaAtual
    $sel = $global:Contas.Selected
    if (-not $sel) { Show-TIToast -Text 'Selecione uma conta.' -Type 'Warn'; return }
    $res = Show-TIConfirm -Title $(if ($Remove) { 'Remover administrador' } else { 'Tornar administrador' }) `
            -Style $(if ($Remove) { 'Danger' } else { 'Primary' }) -Icon 'Admin' -Force `
            -Message $(if ($Remove) { ("'{0}' deixa de ter acesso de administrador neste computador." -f $sel.Name) }
                       else { ("'{0}' passa a ter controle total do computador, inclusive senhas e programas." -f $sel.Name) }) `
            -ConfirmText $(if ($Remove) { 'Remover administrador' } else { 'Tornar administrador' })
    if (-not $res) { return }
    $name = $sel.Name
    [void](Invoke-TIAsync -Name $(if ($Remove) { 'Remoção de administrador' } else { 'Promoção a administrador' }) -RequiresAdmin `
            -Context @{ User = $name; Remove = [bool]$Remove } -Script {
        Set-TIAccountAdmin -User $Context.User -Remove:$Context.Remove
    } -OnComplete { param($r) Refresh-ContasList })
}

# Senha padrão em lote: só contas numéricas (RM) ativas, nunca administrador nem a conta em uso
function Invoke-ContaSchoolPassword {
    if ($global:TI.Busy) { return }
    $users = @($global:Contas.Users)
    if ($users.Count -eq 0) {
        Show-TIToast -Text 'Carregando a lista de contas: tente de novo em seguida.' -Type 'Info'
        Refresh-ContasList
        return
    }
    if (@($users | Where-Object { -not $_.AdminKnown }).Count -gt 0) {
        Show-TIToast -Text 'Não deu para identificar os administradores: a senha em lote ficou bloqueada por segurança.' -Type 'Error'
        return
    }
    $targets = @($users | Where-Object { $_.Name -match '^[0-9]{3,}$' -and $_.Enabled -and -not $_.Admin -and $_.Name -ne $env:USERNAME } | ForEach-Object { $_.Name })
    $keptAdmins = @($users | Where-Object { $_.Name -match '^[0-9]{3,}$' -and $_.Enabled -and $_.Admin } | ForEach-Object { $_.Name })
    if ($targets.Count -eq 0) {
        Show-TIToast -Text 'Nenhuma conta de aluno (RM) ativa para alterar.' -Type 'Warn'
        return
    }

    $pw = [string]$global:TI.Settings['SchoolPassword']
    if ([string]::IsNullOrWhiteSpace($pw)) {
        $pw = Show-TIInput -Title 'Senha padrão da escola' -Label 'Senha' -Password -Required `
                -Message 'Ela fica só na memória durante esta sessão; não é gravada no pendrive.' `
                -OkText 'Continuar'
        if ([string]::IsNullOrWhiteSpace($pw)) { return }
        $global:TI.Settings['SchoolPassword'] = $pw
    }

    $maxShow = 15
    $listTxt = (($targets | Select-Object -First $maxShow | ForEach-Object { '  ' + $_ }) -join "`n")
    if ($targets.Count -gt $maxShow) { $listTxt += ("`n  e mais {0} conta(s)" -f ($targets.Count - $maxShow)) }
    $force = [bool]$global:TI.Settings['ForceChangeOnLogon']
    $extra = ''
    if ($keptAdmins.Count -gt 0) { $extra += ("Ficam de fora por serem administradoras: {0}.`n" -f ($keptAdmins -join ', ')) }
    if ($force) { $extra += "Cada aluno vai definir a própria senha no próximo login.`n" }
    $msg = ("A senha padrão será aplicada em {0} conta(s) de aluno (RM):`n`n{1}`n`n{2}Contas de administrador e a conta em uso nunca são alteradas." -f `
            $targets.Count, $listTxt, $extra)
    $res = Show-TIConfirm -Title 'Aplicar senha padrão' -Style 'Danger' -Icon 'Lock' -Force `
            -Message $msg -ConfirmText ('Aplicar em {0} conta(s)' -f $targets.Count)
    if (-not $res) { return }
    [void](Invoke-TIAsync -Name ('Senha padrão em lote ({0} contas)' -f $targets.Count) -RequiresAdmin `
            -Context @{ Password = $pw; ForceChange = $force } -Script {
        Set-TISchoolPasswords -Password $Context.Password -ForceChange:([bool]$Context.ForceChange)
    } -OnComplete { param($r) Refresh-ContasList })
}

function Invoke-ContaCreate {
    if ($global:TI.Busy) { return }
    $name = Show-TIInput -Title 'Nova conta local' -Label 'Nome da conta (login)' -Required `
            -Message 'Use o RM ou o padrão de nomes da escola.' -OkText 'Continuar'
    if (-not $name) { return }
    $name = $name.Trim()
    if ($name -match '[\\/\[\]:;|=,+*?<>"@]') {
        Show-TIToast -Text 'O nome não pode ter \ / [ ] : ; | = , + * ? < > " @' -Type 'Error'
        return
    }
    $pw = Show-TIInput -Title 'Senha inicial' -Label 'Senha' -Password -Required -OkText 'Criar conta' `
            -Message ("Para '{0}'. Recomendado: 8 caracteres ou mais, com letras e números." -f $name)
    if ($null -eq $pw) { return }
    [void](Invoke-TIAsync -Name ('Criação da conta ' + $name) -RequiresAdmin -Context @{ User = $name; Password = $pw } -Script {
        New-TIAccount -User $Context.User -Password $Context.Password -Description 'Conta criada pelo TI Suite'
    } -OnComplete { param($r) Refresh-ContasList })
}

$wsContas = @{
    Id       = 'contas'
    Title    = 'Contas'
    Sub      = 'Contas locais, senhas, bloqueios e administradores'
    Icon     = 'People'
    Keywords = 'contas usuarios senha bloqueio desbloquear administrador admin rm aluno'

    OnActivate = { if (@($global:Contas.Users).Count -eq 0) { Refresh-ContasList } }
    Refresh    = { Refresh-ContasList }

    Actions = {
        param($Bar)
        $b = New-TIButton -Text 'Atualizar' -Style 'Outline' -Width 116 -Height 34 -Icon 'Refresh' -Tip 'Ler as contas de novo (Ctrl+R)'
        $b.Add_Click({ Refresh-ContasList })
        $Bar.Controls.Add($b)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $w = $global:Theme.CardWidth

        # --- Lista de contas ----------------------------------------------
        $b1 = New-TICard -Parent $flow -Title 'Contas locais' -Stretch -Icon 'Accounts' -Desc 'Usuários cadastrados neste computador' -Width $w -Height 380
        $bar = New-TIButtonBar -Parent $b1
        $btnNew = New-TIButton -Text 'Nova conta' -Style 'Primary' -Width 140 -Height 36 -Icon 'Add'
        $btnNew.Add_Click({ Invoke-ContaCreate })
        $bar.Controls.Add($btnNew)
        $btnSchool = New-TIButton -Text 'Senha padrão (lote)' -Style 'Soft' -Width 186 -Height 36 -Icon 'Lock' -Tip 'Aplica a senha padrão da escola em todas as contas de aluno (RM)'
        $btnSchool.Add_Click({ Invoke-ContaSchoolPassword })
        $bar.Controls.Add($btnSchool)
        $global:Contas.CountLabel = Add-TIBarLabel -Bar $bar -Text ''

        $grid = New-TIGrid -Parent $b1 -Headers @('Conta', 'Estado', 'Admin', 'Descrição', 'Último logon') `
                           -Widths @(170, 110, 76, 260, 140) -EmptyText 'Carregando as contas...'
        $grid.Tag = 'tistretch'
        $grid.Height = 250
        $grid.Add_SelectionChanged({ Select-ContaAtual })
        $global:Contas.Grid = $grid

        # --- Redefinir senha ----------------------------------------------
        $b2 = New-TICard -Parent $flow -Title 'Redefinir senha' -Icon 'Lock' -Desc 'Nova senha para a conta selecionada' -Width $w -Height 330
        $selLbl = New-TILabel -Text 'Nenhuma conta selecionada' -Size 9.5 -Bold -Color $global:Pal.TextDim
        $selLbl.AutoSize = $false
        $selLbl.AutoEllipsis = $true
        $selLbl.Tag = 'tirow'
        $selLbl.Height = 20
        $selLbl.Width = Get-TIInnerWidth $b2
        $selLbl.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
        $b2.Controls.Add($selLbl)
        $global:Contas.SelLabel = $selLbl

        $pwLabel = New-TILabel -Text 'Nova senha' -Size 8.5 -Muted
        $pwLabel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
        $b2.Controls.Add($pwLabel)

        $pwBox = New-Object System.Windows.Forms.TextBox
        $pwBox.Tag = 'tirow'
        $pwBox.Size = New-Object System.Drawing.Size((Get-TIInnerWidth $b2), 28)
        $pwBox.BackColor = $global:Pal.Bg
        $pwBox.ForeColor = $global:Pal.TextMain
        $pwBox.BorderStyle = 'FixedSingle'
        $pwBox.Font = New-TIFont 10
        $pwBox.UseSystemPasswordChar = $true
        $pwBox.Enabled = $false
        $pwBox.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
        $pwBox.Add_TextChanged({ Update-ContaPasswordMeter })
        $pwBox.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; Invoke-ContaApplyPassword } })
        $b2.Controls.Add($pwBox)
        $global:Contas.PassBox = $pwBox

        $segRow = New-Object System.Windows.Forms.Panel
        $segRow.Tag = 'tirow'
        $segRow.Size = New-Object System.Drawing.Size((Get-TIInnerWidth $b2), 30)
        $segRow.BackColor = [System.Drawing.Color]::Transparent
        $b2.Controls.Add($segRow)
        $segX = 0
        for ($i = 0; $i -lt 4; $i++) {
            $seg = New-Object TISuite.RoundPanel
            $seg.Radius = 99
            $seg.BorderWidth = 0
            $seg.FillColor = $global:Pal.BorderSoft
            $seg.BackdropColor = $global:Pal.Card
            $seg.Size = New-Object System.Drawing.Size(64, 6)
            $seg.Location = New-Object System.Drawing.Point($segX, 2)
            $segRow.Controls.Add($seg)
            $global:Contas.Segments += $seg
            $segX += 70
        }
        $segInfo = New-TILabel -Text 'Digite a nova senha' -Size 8 -Color $global:Pal.TextDim
        $segInfo.Location = New-Object System.Drawing.Point(0, 12)
        $segRow.Controls.Add($segInfo)
        $global:Contas.PassInfo = $segInfo

        $showRow = New-Object System.Windows.Forms.Panel
        $showRow.Tag = 'tirow'
        $showRow.Size = New-Object System.Drawing.Size((Get-TIInnerWidth $b2), 30)
        $showRow.BackColor = [System.Drawing.Color]::Transparent
        $b2.Controls.Add($showRow)
        $showSw = New-Object TISuite.ToggleSwitch
        $showSw.Location = New-Object System.Drawing.Point(0, 3)
        $showSw.AccessibleName = 'Mostrar senha'
        $showSw.Add_CheckedChanged({ $global:Contas.PassBox.UseSystemPasswordChar = -not $this.Checked })
        $showRow.Controls.Add($showSw)
        $showLbl = New-TILabel -Text 'Mostrar senha' -Size 8.5 -Muted
        $showLbl.Location = New-Object System.Drawing.Point(50, 6)
        $showLbl.Cursor = [System.Windows.Forms.Cursors]::Hand
        $showLbl.Add_Click({ $showSw.Checked = -not $showSw.Checked }.GetNewClosure())
        $showRow.Controls.Add($showLbl)

        $pwBar = New-TIButtonBar -Parent $b2
        $btnApply = New-TIButton -Text 'Aplicar senha' -Style 'Primary' -Width 150 -Height 38 -Icon 'Check'
        $btnApply.Enabled = $false
        $btnApply.Add_Click({ Invoke-ContaApplyPassword })
        $pwBar.Controls.Add($btnApply)
        $global:Contas.BtnApply = $btnApply
        $btnRemovePw = New-TIButton -Text 'Remover senha' -Style 'Outline' -Width 148 -Height 38 -Icon 'Unlock'
        $btnRemovePw.Enabled = $false
        $btnRemovePw.Add_Click({ Invoke-ContaRemovePassword })
        $pwBar.Controls.Add($btnRemovePw)
        $global:Contas.BtnRemovePw = $btnRemovePw

        # --- Estado e privilégios -----------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Estado e privilégios' -Icon 'Shield' -Desc 'Ativar, desbloquear, desativar e administradores' -Width $w -Height 330
        $sBar = New-TIButtonBar -Parent $b3
        $btnEnable = New-TIButton -Text 'Ativar / desbloquear' -Style 'Outline' -Width 190 -Height 38 -Icon 'Unlock' -Tip 'Reativa a conta e libera o bloqueio por senhas erradas'
        $btnEnable.Add_Click({ Invoke-ContaToggleEnable })
        $sBar.Controls.Add($btnEnable)
        $global:Contas.BtnEnable = $btnEnable
        $btnDisable = New-TIButton -Text 'Desativar' -Style 'Danger' -Width 120 -Height 38 -Icon 'Stop'
        $btnDisable.Add_Click({ Invoke-ContaToggleEnable -Disable })
        $sBar.Controls.Add($btnDisable)
        $global:Contas.BtnDisable = $btnDisable
        $btnAdmin = New-TIButton -Text 'Tornar administrador' -Style 'Soft' -Width 190 -Height 38 -Icon 'Admin'
        $btnAdmin.Add_Click({ Invoke-ContaToggleAdmin })
        $sBar.Controls.Add($btnAdmin)
        $global:Contas.BtnAdmin = $btnAdmin
        $btnDeadmin = New-TIButton -Text 'Remover administrador' -Style 'Outline' -Width 196 -Height 38 -Icon 'Remove'
        $btnDeadmin.Add_Click({ Invoke-ContaToggleAdmin -Remove })
        $sBar.Controls.Add($btnDeadmin)
        $global:Contas.BtnDeadmin = $btnDeadmin

        $global:Contas.Hint = New-TIHint -Parent $b3 -Text 'Selecione uma conta na lista.' -TopGap 4

        Update-ContaSelectionUI
    }
}

Register-TIWorkspace @wsContas
