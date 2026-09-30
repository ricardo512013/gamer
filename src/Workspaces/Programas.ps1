# =====================================================================
# ÁREA: PROGRAMAS - lista e desinstalação
# =====================================================================

$global:Programas = @{
    Grid        = $null
    Body        = $null
    Flow        = $null
    Rows        = @()
    FilterBox   = $null
    FilterTimer = $null
    Info        = $null
    UninstBtn   = $null
    CountLabel  = $null
}

$global:ProgramasAdminMsg = 'Esta ação precisa do TI Suite aberto como administrador: clique no selo "Sem elevação" na barra lateral.'

function Get-ProgramasSelected {
    $grid = $global:Programas.Grid
    if (-not $grid -or $grid.SelectedRows.Count -eq 0) { return $null }
    return $grid.SelectedRows[0].Tag
}

# Filtro literal e sem acento: "otimizacao" acha "Otimização"; "[", "*" e "?"
# são texto comum (antes "[" quebrava a lista com erro de curinga)
function Get-ProgramasFiltered {
    $q = ''
    if ($global:Programas.FilterBox) { $q = ConvertTo-TIPlain ($global:Programas.FilterBox.Text.Trim()) }
    $rows = @($global:Programas.Rows)
    if ($q) { $rows = @($rows | Where-Object { ([string]$_.Search).Contains($q) }) }
    return $rows
}

function Format-ProgramasCount {
    param([int]$N)
    if ($N -eq 1) { return '1 programa' }
    return ('{0} programas' -f $N)
}

function Fill-ProgramasGrid {
    $grid = $global:Programas.Grid
    if (-not $grid) { return }
    # @(): com 1 resultado o PowerShell 5.1 devolvia o objeto solto, sem .Count
    $rows = @(Get-ProgramasFiltered)
    $grid.SuspendLayout()
    $grid.Rows.Clear()
    foreach ($r in $rows) {
        $date = $r.InstallDate
        [void](Add-TIRow -Grid $grid -Cells @(
            $r.Name,
            $(if ($r.Version) { $r.Version } else { '-' }),
            $(if ($r.Publisher) { $r.Publisher } else { '-' }),
            $(if ($r.Size -gt 0) { Format-TIBytes $r.Size } else { '-' }),
            $(if ($date) { ([datetime]$date).ToString('dd/MM/yyyy') } else { '-' }),
            $(if ($r.Scope) { $r.Scope } else { '-' })
        ) -Tag $r -SortKeys @($null, $null, $null, [double]$r.Size, $(if ($date) { [datetime]$date } else { [datetime]::MinValue }), $null))
    }
    # Reaplica a ordenação escolhida pelo operador e não deixa nada pré-selecionado
    Clear-TIGridSelection $grid
    $grid.ResumeLayout()
    $total = @($global:Programas.Rows).Count
    $filtering = ($global:Programas.FilterBox -and $global:Programas.FilterBox.Text.Trim())
    if ($filtering -and $total -gt 0) {
        Set-TIGridEmptyText $grid 'Nenhum programa corresponde ao filtro.'
    } else {
        Set-TIGridEmptyText $grid 'Nenhum programa carregado. Clique em Atualizar.'
    }
    if ($global:Programas.CountLabel) {
        $global:Programas.CountLabel.Text = $(if ($rows.Count -eq $total) { Format-ProgramasCount $total } else { '{0} de {1}' -f $rows.Count, (Format-ProgramasCount $total) })
    }
    Update-ProgramasSelection
}

function Update-ProgramasSelection {
    $sel = Get-ProgramasSelected
    $has = ($null -ne $sel)
    if ($global:Programas.UninstBtn) { $global:Programas.UninstBtn.Enabled = ($has -and -not $global:TI.Busy) }
    $info = $global:Programas.Info
    if ($info) {
        if (-not $has) {
            $info.Text = 'Selecione um programa na lista para desinstalar (Enter no filtro seleciona o primeiro).'
            $info.ForeColor = $global:Pal.TextMuted
        } else {
            $info.Text = ('Selecionado: {0}' -f $sel.Name)
            $info.ForeColor = $global:Pal.Primary
        }
    }
}

# Enter no filtro: aplica na hora e leva o foco para o primeiro programa
function Select-ProgramasFirstRow {
    $t = $global:Programas.FilterTimer
    if ($t -and $t.Enabled) { $t.Stop(); Fill-ProgramasGrid }
    $grid = $global:Programas.Grid
    if (-not $grid -or $grid.Rows.Count -eq 0) { return }
    $grid.ClearSelection()
    try { $grid.CurrentCell = $grid.Rows[0].Cells[0] } catch { }
    $grid.Rows[0].Selected = $true
    [void]$grid.Focus()
}

# A lista ocupa a altura da janela (no mínimo ~8 linhas)
function Update-ProgramasHeight {
    $grid = $global:Programas.Grid
    $flow = $global:Programas.Flow
    $body = $global:Programas.Body
    if (-not $grid -or -not $flow -or -not $body -or $grid.IsDisposed -or $flow.IsDisposed) { return }
    $card = $body.Parent
    if (-not $card) { return }
    try {
        $avail = $flow.ClientSize.Height - $flow.Padding.Vertical - $card.Margin.Vertical
        # Tudo o que não é a tabela: cabeçalho do card, botões, filtro e dica
        $need = $body.GetPreferredSize((New-Object System.Drawing.Size($body.ClientSize.Width, 0))).Height
        $overhead = ($body.Top + $need + 12) - $grid.Height
        $h = [int][Math]::Max(290, $avail - $overhead)
        if ([Math]::Abs($grid.Height - $h) -gt 4) { $grid.Height = $h }
    } catch { }
}

function Refresh-ProgramasList {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Leitura dos programas instalados' -Quiet -Script {
        Get-TIInstalledApps
    } -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Name'] })
        # Texto de busca pronto (sem acento, minúsculo): o filtro não recalcula a cada tecla
        foreach ($x in $rows) {
            Add-Member -InputObject $x -NotePropertyName 'Search' -Force `
                       -NotePropertyValue (ConvertTo-TIPlain ('{0} {1} {2}' -f $x.Name, $x.Publisher, $x.Version))
        }
        $global:Programas.Rows = $rows
        Fill-ProgramasGrid
    })
}

function Invoke-ProgramasUninstall {
    if ($global:TI.Busy) { return }
    $sel = Get-ProgramasSelected
    if (-not $sel) { Show-TIToast -Text 'Selecione um programa na lista.' -Type 'Warn'; return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text $global:ProgramasAdminMsg -Type 'Error'; return }
    $when = $(if ($sel.InstallDate) { ([datetime]$sel.InstallDate).ToString('dd/MM/yyyy') } else { '-' })
    $msg = ("Desinstalar '{0}'?`n`nVersão: {1}`nFabricante: {2}`nInstalado em: {3}`nPara: {4}`n`nO TI Suite usa o modo silencioso quando o fabricante permite; se não, abre a janela do desinstalador para você concluir. Não dá para desfazer." -f `
        $sel.Name, $(if ($sel.Version) { $sel.Version } else { '-' }), $(if ($sel.Publisher) { $sel.Publisher } else { '-' }),
        $when, $(if ($sel.Scope) { $sel.Scope } else { '-' }))
    $res = Show-TIConfirm -Title 'Desinstalar programa' -Message $msg `
            -ConfirmText 'Desinstalar' -Style 'Danger' -Icon 'Warning'
    if (-not $res) { return }
    $appName = [string]$sel.Name
    [void](Invoke-TIAsync -Name ('Desinstalação de ' + $appName) -RequiresAdmin -Context @{ App = $sel } -Script {
        Uninstall-TIApp -App $Context.App
    } -OnComplete ({
        param($r)
        # O pump já avisou "concluída" ou "com erros"; aqui vai o motivo em linguagem simples
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Removed'] }) | Select-Object -First 1
        if ($res -and -not $res.Removed) {
            if ($res.Reboot) { Show-TIToast -Text ('{0}: reinicie o PC para concluir a remoção.' -f $appName) -Type 'Warn' -Duration 6000 }
            else { Show-TIToast -Text ('{0} continua instalado (veja o motivo no console).' -f $appName) -Type 'Error' -Duration 6000 }
        } elseif ($res -and $res.Reboot) {
            Show-TIToast -Text ('{0} removido. Reinicie o PC para concluir.' -f $appName) -Type 'Warn' -Duration 6000
        }
        Refresh-ProgramasList
    }.GetNewClosure()))
}

$wsProgramas = @{
    Id       = 'programas'
    Title    = 'Programas'
    Sub      = 'Programas instalados e desinstalação sem janelas quando possível'
    Icon     = 'Apps'
    Keywords = 'programas aplicativos software desinstalar remover instalados data instalacao'

    OnActivate = {
        Update-ProgramasHeight
        if (@($global:Programas.Rows).Count -eq 0) { Refresh-ProgramasList }
    }
    Refresh    = { Refresh-ProgramasList }

    Actions = {
        param($Bar)
        $b = New-TIButton -Text 'Atualizar' -Style 'Outline' -Width 116 -Height 34 -Icon 'Refresh' -Tip 'Ler a lista de novo (Ctrl+R)'
        $b.Add_Click({ Refresh-ProgramasList })
        $Bar.Controls.Add($b)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $w = $global:Theme.CardWidth
        $global:Programas.Flow = $flow

        $b1 = New-TICard -Parent $flow -Title 'Programas instalados' -Stretch `
                -Desc 'Máquina e usuário, 32 e 64 bits; componentes do sistema e atualizações ficam ocultos' `
                -Icon 'Package' -Width $w -Height 480
        $global:Programas.Body = $b1

        $bar = New-TIButtonBar -Parent $b1
        $btnUn = New-TIButton -Text 'Desinstalar' -Style 'Danger' -Width 150 -Height 36 -Icon 'Remove'
        $btnUn.Enabled = $false
        $btnUn.Add_Click({ Invoke-ProgramasUninstall })
        $bar.Controls.Add($btnUn)
        $global:Programas.UninstBtn = $btnUn
        $global:Programas.CountLabel = Add-TIBarLabel -Bar $bar -Text ''

        $filterRow = New-Object System.Windows.Forms.Panel
        $filterRow.Tag = 'tirow'
        $filterRow.Size = New-Object System.Drawing.Size((Get-TIInnerWidth $b1), 36)
        $filterRow.BackColor = [System.Drawing.Color]::Transparent
        $filterRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
        $b1.Controls.Add($filterRow)

        # Atraso curto: recriar centenas de linhas a cada tecla pesa em PC fraco
        $ft = New-Object System.Windows.Forms.Timer
        $ft.Interval = 250
        $ft.Add_Tick({ $this.Stop(); Fill-ProgramasGrid })
        $global:Programas.FilterTimer = $ft

        $flt = New-Object System.Windows.Forms.TextBox
        $flt.Location = New-Object System.Drawing.Point(0, 3)
        $flt.Size = New-Object System.Drawing.Size(340, 28)
        $flt.BackColor = $global:Pal.Bg
        $flt.ForeColor = $global:Pal.TextMain
        $flt.BorderStyle = 'FixedSingle'
        $flt.Font = New-TIFont 9.5
        $flt.Add_TextChanged({
            $t = $global:Programas.FilterTimer
            if ($t) { $t.Stop(); $t.Start() } else { Fill-ProgramasGrid }
        })
        $flt.Add_KeyDown({
            if ($_.KeyCode -eq 'Escape') { $this.Text = ''; $_.SuppressKeyPress = $true }
            elseif ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; Select-ProgramasFirstRow }
        })
        $filterRow.Controls.Add($flt)
        $global:Programas.FilterBox = $flt
        $null = Add-TIPlaceholder -TextBox $flt -Text 'Filtrar por nome, fabricante ou versão'

        $global:Programas.Info = New-TIHint -Parent $b1 -Text 'Selecione um programa na lista para desinstalar (Enter no filtro seleciona o primeiro).' -TopGap 0 -BottomGap 6

        $grid = New-TIGrid -Parent $b1 -Headers @('Programa', 'Versão', 'Fabricante', 'Tamanho', 'Instalado em', 'Para') `
                           -Widths @(280, 110, 200, 90, 100, 80) -EmptyText 'Carregando a lista de programas...'
        $grid.Tag = 'tistretch'
        $grid.Height = 290
        $grid.Columns[4].ToolTipText = 'Data gravada pelo instalador (nem todo programa informa)'
        $grid.Columns[5].ToolTipText = 'Máquina: para todos os usuários. Usuário: só para a conta que abriu o TI Suite.'
        $grid.Add_SelectionChanged({ Update-ProgramasSelection })
        $grid.Add_CellDoubleClick({ if ($_.RowIndex -ge 0) { Invoke-ProgramasUninstall } })
        $global:Programas.Grid = $grid
        $flow.Add_Resize({ Update-ProgramasHeight })

        $b2 = New-TICard -Parent $flow -Title 'Como funciona' -Desc 'O que acontece ao desinstalar' -Icon 'Info' -Width $w -Height 300
        foreach ($t in @(
            'Usa o modo silencioso quando o programa é MSI, Inno Setup ou NSIS, ou quando o fabricante informa um comando próprio.',
            'Se o tipo for desconhecido, abre a janela do desinstalador para você concluir.',
            'No fim, confere se o programa saiu mesmo da lista do Windows; se não saiu, avisa em vermelho e explica o motivo.',
            'Apps da Microsoft Store não aparecem aqui.',
            'Não há como desfazer: confira o nome antes de confirmar.'
        )) {
            $null = New-TIHint -Parent $b2 -Text $t -TopGap 0 -BottomGap 8
        }
    }
}

Register-TIWorkspace @wsProgramas
