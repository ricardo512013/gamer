# =====================================================================
# ÁREA: CONTAS - contas locais, senhas, bloqueios e administradores
# =====================================================================

$global:Contas = @{
    Grid        = $null
    Selected    = $null
    Users       = @()
    Loaded      = $false
    MySid       = $null
    PassBox     = $null
    PassBox2    = $null
    PassInfo    = $null
    MatchInfo   = $null
    PwHint      = $null
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

# "Conta em uso" é comparada pelo SID, não pelo nome (uma conta do domínio pode ter
# o mesmo nome de uma conta local): vale a de quem abriu o TI Suite e também a de
# quem está conectado ao Windows (elevando com a senha de outro administrador).
function Get-ContaMySid {
    if ($null -eq $global:Contas.MySid) {
        $s = ''
        try { $s = [string][System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { }
        $global:Contas.MySid = $s
    }
    return [string]$global:Contas.MySid
}

function Test-ContaIsSelf {
    param($Account)
    if (-not $Account) { return $false }
    if ($Account.Sid -and $global:TI.SessionUserSid -and [string]$Account.Sid -eq [string]$global:TI.SessionUserSid) { return $true }
    $me = Get-ContaMySid
    if ($me -and $Account.Sid) { return ([string]$Account.Sid -eq $me) }
    return ([string]$Account.Name -eq $env:USERNAME)
}

# "Remover senha" só em conta confirmada como NÃO administradora
# (o worker confere de novo pelo SID antes de aplicar)
function Test-ContaCanRemovePassword {
    param($Account)
    return [bool]($Account -and $Account.AdminKnown -and -not $Account.Admin)
}

# As duas caixas ("Nova senha" e "Repita a senha") preenchidas e iguais
function Test-ContaPasswordsMatch {
    $a = $global:Contas.PassBox
    $b = $global:Contas.PassBox2
    if (-not $a -or $a.Text.Length -eq 0) { return $false }
    if (-not $b) { return $true }
    return ($a.Text -ceq $b.Text)
}

function Update-ContaApplyButton {
    $sel = $global:Contas.Selected
    $pwOk = ($null -ne $sel -and -not (Test-ContaIsSelf $sel) -and -not $global:TI.Busy)
    if ($global:Contas.BtnApply) { $global:Contas.BtnApply.Enabled = ($pwOk -and (Test-ContaPasswordsMatch)) }
}

function Update-ContaMatchState {
    $a = $global:Contas.PassBox
    $b = $global:Contas.PassBox2
    $lbl = $global:Contas.MatchInfo
    if ($lbl -and $a -and $b) {
        if ($a.Text.Length -eq 0 -and $b.Text.Length -eq 0) {
            $lbl.Text = 'Digite a mesma senha nas duas caixas.'
            $lbl.ForeColor = $global:Pal.TextDim
        } elseif ($b.Text.Length -eq 0) {
            $lbl.Text = 'Repita a senha para liberar "Aplicar senha".'
            $lbl.ForeColor = $global:Pal.TextDim
        } elseif ($a.Text -cne $b.Text) {
            $lbl.Text = 'As senhas não conferem.'
            $lbl.ForeColor = $global:Pal.Danger
        } else {
            $lbl.Text = 'As senhas conferem.'
            $lbl.ForeColor = $global:Pal.Success
        }
    }
    Update-ContaApplyButton
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
    Update-ContaMatchState
}

function Clear-ContaPasswordBoxes {
    if ($global:Contas.PassBox) { $global:Contas.PassBox.Text = '' }
    if ($global:Contas.PassBox2) { $global:Contas.PassBox2.Text = '' }
    Update-ContaPasswordMeter
}

function Update-ContaSelectionUI {
    $sel = $global:Contas.Selected
    $hasSel = ($null -ne $sel)
    $isSelf = ($hasSel -and (Test-ContaIsSelf $sel))
    $busy = $global:TI.Busy
    $canBlank = ($hasSel -and (Test-ContaCanRemovePassword $sel))

    if ($global:Contas.SelLabel) {
        $global:Contas.SelLabel.Text = if (-not $hasSel) { 'Nenhuma conta selecionada' }
            elseif ($isSelf) { $sel.Name + ' (conta em uso: senha protegida)' }
            elseif ($sel.Admin) { 'Conta: ' + $sel.Name + ' (administradora)' }
            else { 'Conta: ' + $sel.Name }
        $global:Contas.SelLabel.ForeColor = if (-not $hasSel) { $global:Pal.TextDim } elseif ($isSelf) { $global:Pal.Warning } else { $global:Pal.Primary }
    }

    $pwOk = ($hasSel -and -not $isSelf -and -not $busy)
    if ($global:Contas.BtnRemovePw) { $global:Contas.BtnRemovePw.Enabled = ($pwOk -and $canBlank) }
    if ($global:Contas.PassBox)     { $global:Contas.PassBox.Enabled = $pwOk }
    if ($global:Contas.PassBox2)    { $global:Contas.PassBox2.Enabled = $pwOk }

    if ($global:Contas.PwHint) {
        $ph = $global:Contas.PwHint
        if (-not $hasSel) { $ph.Text = 'Selecione uma conta na lista.'; $ph.ForeColor = $global:Pal.TextMuted }
        elseif ($isSelf) { $ph.Text = 'A senha da conta em uso não é alterada por aqui.'; $ph.ForeColor = $global:Pal.Warning }
        elseif (-not $sel.AdminKnown) { $ph.Text = '"Remover senha" está bloqueado: não deu para confirmar se esta conta é administradora.'; $ph.ForeColor = $global:Pal.Warning }
        elseif ($sel.Admin) { $ph.Text = '"Remover senha" está bloqueado: conta administradora sem senha daria controle total do computador a quem sentar no teclado.'; $ph.ForeColor = $global:Pal.TextMuted }
        else { $ph.Text = '"Remover senha" deixa a conta entrar sem senha, só no teclado deste computador. Use em laboratório ou almoxarifado.'; $ph.ForeColor = $global:Pal.TextMuted }
    }

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

# Resultado da leitura: contas + marcador AccountsRead do worker. Sem o marcador,
# a leitura falhou (não é o mesmo que "nenhuma conta").
function Show-ContasResult {
    param($Result)
    $all = @($Result | Where-Object { $_ })
    $readOk = (@($all | Where-Object { $_.PSObject.Properties['AccountsRead'] }).Count -gt 0)
    $rows = @($all | Where-Object { $_.PSObject.Properties['Name'] -and $_.PSObject.Properties['Sid'] })
    $grid = $global:Contas.Grid
    $global:Contas.Selected = $null

    if (-not $readOk) {
        $global:Contas.Users = @()
        $global:Contas.Loaded = $false
        if ($grid) {
            $grid.Rows.Clear()
            Set-TIGridEmptyText $grid 'Não foi possível ler as contas locais (veja o console). Clique em Atualizar para tentar de novo.'
        }
        if ($global:Contas.CountLabel) {
            $global:Contas.CountLabel.Text = 'Leitura das contas falhou'
            $global:Contas.CountLabel.ForeColor = $global:Pal.Danger
        }
        Update-ContaSelectionUI
        return
    }

    $global:Contas.Users = $rows
    $global:Contas.Loaded = $true
    if ($grid) {
        $grid.Rows.Clear()
        foreach ($u in $rows) {
            $state = if ($u.Locked) { 'Bloqueada' } elseif (-not $u.Enabled) { 'Desativada' } else { 'Ativa' }
            $adm = if (-not $u.AdminKnown) { '?' } elseif ($u.Admin) { 'Sim' } else { 'Não' }
            # "Nunca" ordena antes de qualquer data
            $lastKey = if ($u.LastLogon) { [datetime]$u.LastLogon } else { [datetime]::MinValue }
            $row = Add-TIRow -Grid $grid -Cells @($u.Name, $state, $adm, $u.Description, (Format-TIDate $u.LastLogon -Relative -Empty 'Nunca')) `
                             -SortKeys @($null, $null, $null, $null, $lastKey) -Tag $u
            if ($u.Locked) { $row.Cells[1].Style.ForeColor = $global:Pal.Warning }
            elseif (-not $u.Enabled) { $row.Cells[1].Style.ForeColor = $global:Pal.TextDim }
        }
        Set-TIGridEmptyText $grid 'Nenhuma conta local encontrada neste computador.'
        Clear-TIGridSelection $grid
    }
    Update-ContaSelectionUI
    if ($global:Contas.CountLabel) {
        $locked = @($rows | Where-Object { $_.Locked }).Count
        $global:Contas.CountLabel.Text = ('{0} conta(s) local(is){1}' -f $rows.Count, $(if ($locked -gt 0) { ', ' + $locked + ' bloqueada(s)' } else { '' }))
        $global:Contas.CountLabel.ForeColor = $global:Pal.TextMuted
    }
}

function Refresh-ContasList {
    $grid = $global:Contas.Grid
    if ($global:TI.Busy) {
        if ($grid -and $grid.Rows.Count -eq 0) { Set-TIGridEmptyText $grid 'Há uma tarefa em andamento. Quando ela terminar, clique em Atualizar.' }
        return
    }
    if ($grid -and $grid.Rows.Count -eq 0) { Set-TIGridEmptyText $grid 'Carregando as contas...' }
    $res = @(Invoke-TIAsync -Name 'Leitura das contas locais' -Quiet -Script {
        Get-TIAccounts
    } -OnComplete {
        param($r)
        Show-ContasResult $r
    })
    $started = ($res.Count -gt 0 -and $res[-1] -eq $true)
    if (-not $started -and $grid -and $grid.Rows.Count -eq 0) {
        Set-TIGridEmptyText $grid 'As contas não foram lidas. Clique em Atualizar.'
    }
}

function Select-ContaAtual {
    $grid = $global:Contas.Grid
    if (-not $grid -or $grid.SelectedRows.Count -eq 0) { $global:Contas.Selected = $null }
    else { $global:Contas.Selected = $grid.SelectedRows[0].Tag }
    Update-ContaSelectionUI
}

# Texto da auditoria (coluna de detalhe do audit.csv): QUAL conta. Nunca a senha.
function Get-ContaAuditText {
    param($Account)
    if ($Account.Sid) { return ('Conta: {0} ({1})' -f $Account.Name, $Account.Sid) }
    return ('Conta: {0}' -f $Account.Name)
}

function Invoke-ContaApplyPassword {
    Select-ContaAtual
    $sel = $global:Contas.Selected
    if (-not $sel) { Show-TIToast -Text 'Selecione uma conta.' -Type 'Warn'; return }
    if (Test-ContaIsSelf $sel) { Show-TIToast -Text 'A senha da conta em uso não é alterada por aqui.' -Type 'Error'; return }

    $pw = $global:Contas.PassBox.Text
    if ($pw.Length -eq 0) { Show-TIToast -Text 'Digite a nova senha.' -Type 'Warn'; return }
    if ($global:Contas.PassBox2 -and $global:Contas.PassBox2.Text -cne $pw) {
        Show-TIToast -Text 'As duas senhas não conferem: digite a mesma senha nas duas caixas.' -Type 'Warn'
        try { [void]$global:Contas.PassBox2.Focus() } catch { }
        return
    }
    if ($pw.Length -lt 6) {
        $ok = Show-TIConfirm -Title 'Senha muito curta' -Style 'Danger' -Icon 'Warning' `
                -Message ("A senha tem só {0} caractere(s) e pode ser recusada pela política da rede.`nAplicar assim mesmo?" -f $pw.Length) `
                -ConfirmText 'Aplicar mesmo assim'
        if (-not $ok) { return }
    }
    [void](Invoke-TIAsync -Name ('Nova senha para ' + $sel.Name) -RequiresAdmin -AuditDetail (Get-ContaAuditText $sel) `
            -Context @{ User = $sel.Name; Sid = [string]$sel.Sid; Password = $pw } -Script {
        Set-TIAccountPassword -User $Context.User -Sid $Context.Sid -Password $Context.Password
    } -OnComplete {
        param($r)
        Clear-ContaPasswordBoxes
        Refresh-ContasList
    })
}

function Invoke-ContaRemovePassword {
    Select-ContaAtual
    $sel = $global:Contas.Selected
    if (-not $sel) { Show-TIToast -Text 'Selecione uma conta.' -Type 'Warn'; return }
    if (Test-ContaIsSelf $sel) { Show-TIToast -Text 'A senha da conta em uso não é alterada por aqui.' -Type 'Error'; return }
    if (-not (Test-ContaCanRemovePassword $sel)) {
        $why = if (-not $sel.AdminKnown) { 'Não deu para confirmar se esta conta é administradora: a senha foi mantida.' }
               else { 'Contas administradoras não podem ficar sem senha: qualquer pessoa no teclado teria controle total do computador.' }
        Show-TIToast -Text $why -Type 'Error'
        return
    }
    $res = Show-TIConfirm -Title 'Remover a senha da conta' -Style 'Danger' -Icon 'Lock' `
            -Message ("A conta '{0}' vai entrar sem pedir senha, no teclado deste computador (o Windows não aceita conta sem senha pela rede).`nUse só em computador de laboratório ou almoxarifado." -f $sel.Name) `
            -ConfirmText 'Remover senha'
    if (-not $res) { return }
    [void](Invoke-TIAsync -Name ('Remoção da senha de ' + $sel.Name) -RequiresAdmin -AuditDetail (Get-ContaAuditText $sel) `
            -Context @{ User = $sel.Name; Sid = [string]$sel.Sid } -Script {
        Set-TIAccountPassword -User $Context.User -Sid $Context.Sid -Remove
    } -OnComplete { param($r) Refresh-ContasList })
}

function Invoke-ContaToggleEnable {
    param([switch]$Disable)
    Select-ContaAtual
    $sel = $global:Contas.Selected
    if (-not $sel) { Show-TIToast -Text 'Selecione uma conta.' -Type 'Warn'; return }
    if ($Disable) {
        if (Test-ContaIsSelf $sel) { Show-TIToast -Text 'A conta em uso não pode ser desativada.' -Type 'Error'; return }
        $res = Show-TIConfirm -Title 'Desativar conta' -Style 'Danger' -Icon 'Warning' `
                -Message ("'{0}' não vai conseguir entrar até ser reativada." -f $sel.Name) `
                -ConfirmText 'Desativar'
        if (-not $res) { return }
    }
    $name = $sel.Name
    [void](Invoke-TIAsync -Name $(if ($Disable) { 'Desativação de ' + $name } else { 'Ativação de ' + $name }) -RequiresAdmin `
            -AuditDetail (Get-ContaAuditText $sel) `
            -Context @{ User = $name; Sid = [string]$sel.Sid; Disable = [bool]$Disable } -Script {
        Enable-TIAccount -User $Context.User -Sid $Context.Sid -Disable:$Context.Disable
    } -OnComplete { param($r) Refresh-ContasList })
}

function Invoke-ContaToggleAdmin {
    param([switch]$Remove)
    Select-ContaAtual
    $sel = $global:Contas.Selected
    if (-not $sel) { Show-TIToast -Text 'Selecione uma conta.' -Type 'Warn'; return }
    if ($Remove -and (Test-ContaIsSelf $sel)) { Show-TIToast -Text 'A conta em uso não perde o acesso de administrador por aqui.' -Type 'Error'; return }
    $res = Show-TIConfirm -Title $(if ($Remove) { 'Remover administrador' } else { 'Tornar administrador' }) `
            -Style $(if ($Remove) { 'Danger' } else { 'Primary' }) -Icon 'Admin' `
            -Message $(if ($Remove) { ("'{0}' deixa de ter acesso de administrador neste computador." -f $sel.Name) }
                       else { ("'{0}' passa a ter controle total do computador, inclusive senhas e programas." -f $sel.Name) }) `
            -ConfirmText $(if ($Remove) { 'Remover administrador' } else { 'Tornar administrador' })
    if (-not $res) { return }
    $name = $sel.Name
    [void](Invoke-TIAsync -Name $(if ($Remove) { 'Remoção de administrador: ' + $name } else { 'Promoção a administrador: ' + $name }) -RequiresAdmin `
            -AuditDetail (Get-ContaAuditText $sel) `
            -Context @{ User = $name; Sid = [string]$sel.Sid; Remove = [bool]$Remove } -Script {
        Set-TIAccountAdmin -User $Context.User -Sid $Context.Sid -Remove:$Context.Remove
    } -OnComplete { param($r) Refresh-ContasList })
}

# Senha padrão em lote: só contas numéricas (RM) ativas, nunca administrador nem a conta em uso
function Invoke-ContaSchoolPassword {
    if ($global:TI.Busy) { return }
    $users = @($global:Contas.Users)
    if (-not $global:Contas.Loaded) {
        Show-TIToast -Text 'A lista de contas ainda não foi lida: tente de novo em seguida.' -Type 'Info'
        Refresh-ContasList
        return
    }
    if (@($users | Where-Object { -not $_.AdminKnown }).Count -gt 0) {
        Show-TIToast -Text 'Não deu para identificar os administradores: a senha em lote ficou bloqueada por segurança.' -Type 'Error'
        return
    }
    $targets = @($users | Where-Object { $_.Name -match '^[0-9]{3,}$' -and $_.Enabled -and -not $_.Admin -and -not (Test-ContaIsSelf $_) } | ForEach-Object { $_.Name })
    $keptAdmins = @($users | Where-Object { $_.Name -match '^[0-9]{3,}$' -and $_.Enabled -and $_.Admin } | ForEach-Object { $_.Name })
    if ($targets.Count -eq 0) {
        Show-TIToast -Text 'Nenhuma conta de aluno (RM) ativa para alterar.' -Type 'Warn'
        return
    }

    $pw = [string]$global:TI.Settings['SchoolPassword']
    if ([string]::IsNullOrWhiteSpace($pw)) {
        $pw = Show-TIInput -Title 'Senha padrão da escola' -Label 'Senha' -Password -Confirm -Required `
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
    $res = Show-TIConfirm -Title 'Aplicar senha padrão' -Style 'Danger' -Icon 'Lock' `
            -Message $msg -ConfirmText ('Aplicar em {0} conta(s)' -f $targets.Count)
    if (-not $res) { return }
    $maxAudit = 60
    $auditNames = (@($targets | Select-Object -First $maxAudit) -join ', ')
    if ($targets.Count -gt $maxAudit) { $auditNames += (' e mais {0}' -f ($targets.Count - $maxAudit)) }
    $audit = ('Contas: {0}; troca no próximo login: {1}' -f $auditNames, $(if ($force) { 'sim' } else { 'não' }))
    [void](Invoke-TIAsync -Name ('Senha padrão em lote ({0} contas)' -f $targets.Count) -RequiresAdmin -AuditDetail $audit `
            -Context @{ Password = $pw; ForceChange = $force } -Script {
        Set-TISchoolPasswords -Password $Context.Password -ForceChange:([bool]$Context.ForceChange)
    } -OnComplete { param($r) Refresh-ContasList })
}

function Invoke-ContaCreate {
    if ($global:TI.Busy) { return }
    # O Windows aceita até 20 caracteres no nome de login; o erro aparece no próprio diálogo
    $name = Show-TIInput -Title 'Nova conta local' -Label 'Nome da conta (login)' -Required -MaxLength 20 `
            -Message 'Use o RM ou o padrão de nomes da escola (até 20 caracteres).' -OkText 'Continuar' -Validate {
        param($t)
        $n = ([string]$t).Trim()
        if ($n -match '[\\/\[\]:;|=,+*?<>"@]') { return 'O nome não pode ter \ / [ ] : ; | = , + * ? < > " @' }
        if ($n -match '^[\. ]+$') { return 'O nome não pode ser só pontos ou espaços.' }
        if (@($global:Contas.Users | Where-Object { [string]$_.Name -eq $n }).Count -gt 0) { return ('Já existe uma conta local chamada "{0}".' -f $n) }
        return ''
    }
    if (-not $name) { return }
    $name = $name.Trim()
    $force = [bool]$global:TI.Settings['ForceChangeOnLogon']
    $msg = ("Para '{0}'. Recomendado: 8 caracteres ou mais, com letras e números." -f $name)
    if ($force) { $msg += "`nNo primeiro login, a pessoa vai trocar esta senha por uma própria." }
    $pw = Show-TIInput -Title 'Senha inicial' -Label 'Senha' -Password -Confirm -Required -OkText 'Criar conta' -Message $msg
    if ($null -eq $pw) { return }
    [void](Invoke-TIAsync -Name ('Criação da conta ' + $name) -RequiresAdmin `
            -AuditDetail ('Conta: {0}; troca de senha no primeiro login: {1}' -f $name, $(if ($force) { 'sim' } else { 'não' })) `
            -Context @{ User = $name; Password = $pw; MustChange = $force } -Script {
        New-TIAccount -User $Context.User -Password $Context.Password -Description 'Conta criada pelo TI Suite' `
                      -MustChange:([bool]$Context.MustChange)
    } -OnComplete { param($r) Refresh-ContasList })
}

$wsContas = @{
    Id       = 'contas'
    Title    = 'Contas'
    Sub      = 'Contas locais, senhas, bloqueios e administradores'
    Icon     = 'People'
    Keywords = 'contas usuarios senha bloqueio desbloquear administrador admin rm aluno'

    OnActivate = { if (-not $global:Contas.Loaded) { Refresh-ContasList } }
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
                           -Widths @(150, 100, 70, 230, 210) -EmptyText 'Carregando as contas...'
        $grid.Tag = 'tistretch'
        $grid.Height = 250
        $grid.Add_SelectionChanged({ Select-ContaAtual })
        $global:Contas.Grid = $grid

        # --- Redefinir senha ----------------------------------------------
        $b2 = New-TICard -Parent $flow -Title 'Redefinir senha' -Icon 'Lock' -Desc 'Nova senha para a conta selecionada' -Half -Width $w -Height 380
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
        $pwBox.AccessibleName = 'Nova senha'
        $pwBox.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
        $pwBox.Add_TextChanged({ Update-ContaPasswordMeter })
        # Enter na primeira caixa vai para "Repita a senha"; na segunda, aplica
        $pwBox.Add_KeyDown({
            if ($_.KeyCode -ne 'Enter') { return }
            $_.SuppressKeyPress = $true
            $b = $global:Contas.PassBox2
            if ($b -and $b.Text.Length -eq 0) { [void]$b.Focus() } else { Invoke-ContaApplyPassword }
        })
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

        $pw2Label = New-TILabel -Text 'Repita a senha' -Size 8.5 -Muted
        $pw2Label.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
        $b2.Controls.Add($pw2Label)

        $pwBox2 = New-Object System.Windows.Forms.TextBox
        $pwBox2.Tag = 'tirow'
        $pwBox2.Size = New-Object System.Drawing.Size((Get-TIInnerWidth $b2), 28)
        $pwBox2.BackColor = $global:Pal.Bg
        $pwBox2.ForeColor = $global:Pal.TextMain
        $pwBox2.BorderStyle = 'FixedSingle'
        $pwBox2.Font = New-TIFont 10
        $pwBox2.UseSystemPasswordChar = $true
        $pwBox2.Enabled = $false
        $pwBox2.AccessibleName = 'Repita a senha'
        $pwBox2.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
        $pwBox2.Add_TextChanged({ Update-ContaMatchState })
        $pwBox2.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; Invoke-ContaApplyPassword } })
        $b2.Controls.Add($pwBox2)
        $global:Contas.PassBox2 = $pwBox2

        $matchInfo = New-TILabel -Text 'Digite a mesma senha nas duas caixas.' -Size 8 -Color $global:Pal.TextDim
        $matchInfo.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
        $b2.Controls.Add($matchInfo)
        $global:Contas.MatchInfo = $matchInfo

        $showRow = New-Object System.Windows.Forms.Panel
        $showRow.Tag = 'tirow'
        $showRow.Size = New-Object System.Drawing.Size((Get-TIInnerWidth $b2), 30)
        $showRow.BackColor = [System.Drawing.Color]::Transparent
        $b2.Controls.Add($showRow)
        $showSw = New-Object TISuite.ToggleSwitch
        $showSw.Location = New-Object System.Drawing.Point(0, 3)
        $showSw.AccessibleName = 'Mostrar senha'
        $showSw.Add_CheckedChanged({
            $hide = -not $this.Checked
            if ($global:Contas.PassBox) { $global:Contas.PassBox.UseSystemPasswordChar = $hide }
            if ($global:Contas.PassBox2) { $global:Contas.PassBox2.UseSystemPasswordChar = $hide }
        })
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

        $global:Contas.PwHint = New-TIHint -Parent $b2 -Text 'Selecione uma conta na lista.' -TopGap 2

        # --- Estado e privilégios -----------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Estado e privilégios' -Icon 'Shield' -Desc 'Ativar, desbloquear, desativar e administradores' -Half -Width $w -Height 380
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
