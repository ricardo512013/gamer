# =====================================================================
# ÁREA: PROGRAMAS - lista e desinstalação
# =====================================================================

$global:Programas = @{
    Grid       = $null
    Rows       = @()
    FilterBox  = $null
    Info       = $null
    UninstBtn  = $null
    CountLabel = $null
    Selected   = $null
}

function Get-ProgramasFiltered {
    $q = ''
    if ($global:Programas.FilterBox) { $q = $global:Programas.FilterBox.Text.Trim() }
    $rows = @($global:Programas.Rows)
    if ($q) {
        $rows = @($rows | Where-Object {
            $_.Name -like "*$q*" -or $_.Publisher -like "*$q*" -or $_.Version -like "*$q*"
        })
    }
    return $rows
}

function Fill-ProgramasGrid {
    $grid = $global:Programas.Grid
    if (-not $grid) { return }
    $grid.Rows.Clear()
    $rows = Get-ProgramasFiltered
    foreach ($r in $rows) {
        [void](Add-TIRow -Grid $grid -Cells @(
            $r.Name,
            $(if ($r.Version) { $r.Version } else { '-' }),
            $(if ($r.Publisher) { $r.Publisher } else { '-' }),
            $(if ($r.Size -gt 0) { Format-TIBytes $r.Size } else { '-' })
        ) -Tag $r)
    }
    Clear-TIGridSelection $grid
    $total = @($global:Programas.Rows).Count
    if ($global:Programas.FilterBox -and $global:Programas.FilterBox.Text.Trim() -and $total -gt 0) {
        Set-TIGridEmptyText $grid 'Nenhum programa corresponde ao filtro.'
    } else {
        Set-TIGridEmptyText $grid 'Nenhum programa carregado. Clique em Atualizar.'
    }
    if ($global:Programas.CountLabel) {
        $global:Programas.CountLabel.Text = $(if ($rows.Count -eq $total) { '{0} programas' -f $total } else { '{0} de {1} programas' -f $rows.Count, $total })
    }
    $global:Programas.Selected = $null
    Update-ProgramasSelection
}

function Update-ProgramasSelection {
    $grid = $global:Programas.Grid
    if (-not $grid -or $grid.SelectedRows.Count -eq 0) { $global:Programas.Selected = $null }
    else { $global:Programas.Selected = $grid.SelectedRows[0].Tag }
    $has = ($null -ne $global:Programas.Selected)
    if ($global:Programas.UninstBtn) { $global:Programas.UninstBtn.Enabled = ($has -and -not $global:TI.Busy) }
    $info = $global:Programas.Info
    if ($info) {
        if (-not $has) {
            $info.Text = 'Selecione um programa na lista para desinstalar.'
            $info.ForeColor = $global:Pal.TextMuted
        } else {
            $info.Text = ('Selecionado: {0}' -f $global:Programas.Selected.Name)
            $info.ForeColor = $global:Pal.Primary
        }
    }
}

function Refresh-ProgramasList {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Leitura dos programas instalados' -Quiet -Script {
        Get-TIInstalledApps
    } -OnComplete {
        param($r)
        $global:Programas.Rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Name'] })
        Fill-ProgramasGrid
    })
}

function Invoke-ProgramasUninstall {
    Update-ProgramasSelection
    $sel = $global:Programas.Selected
    if (-not $sel) { Show-TIToast -Text 'Selecione um programa na lista.' -Type 'Warn'; return }
    $msg = ("Desinstalar '{0}'?`n`nVersão: {1}`nFabricante: {2}`n`nO TI Suite usa o modo silencioso quando o fabricante permite; se não, abre a janela do desinstalador para você concluir. Não dá para desfazer." -f `
        $sel.Name, $(if ($sel.Version) { $sel.Version } else { '-' }), $(if ($sel.Publisher) { $sel.Publisher } else { '-' }))
    $res = Show-TIConfirm -Title 'Desinstalar programa' -Message $msg `
            -ConfirmText 'Desinstalar' -Style 'Danger' -Icon 'Warning' -Force
    if (-not $res) { return }
    [void](Invoke-TIAsync -Name ('Desinstalação de ' + $sel.Name) -RequiresAdmin -Context @{ App = $sel } -Script {
        Uninstall-TIApp -App $Context.App
    } -OnComplete { param($r) Refresh-ProgramasList })
}

$wsProgramas = @{
    Id       = 'programas'
    Title    = 'Programas'
    Sub      = 'Programas instalados e desinstalação sem janelas quando possível'
    Icon     = 'Apps'
    Keywords = 'programas aplicativos software desinstalar remover instalados'

    OnActivate = { if (@($global:Programas.Rows).Count -eq 0) { Refresh-ProgramasList } }
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

        $b1 = New-TICard -Parent $flow -Title 'Programas instalados' -Stretch `
                -Desc 'Máquina e usuário, 32 e 64 bits; componentes do sistema e atualizações ficam ocultos' `
                -Icon 'Package' -Width $w -Height 480

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

        $flt = New-Object System.Windows.Forms.TextBox
        $flt.Location = New-Object System.Drawing.Point(0, 3)
        $flt.Size = New-Object System.Drawing.Size(340, 28)
        $flt.BackColor = $global:Pal.Bg
        $flt.ForeColor = $global:Pal.TextMain
        $flt.BorderStyle = 'FixedSingle'
        $flt.Font = New-TIFont 9.5
        $flt.Add_TextChanged({ Fill-ProgramasGrid })
        $flt.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $this.Text = ''; $_.SuppressKeyPress = $true } })
        $filterRow.Controls.Add($flt)
        $global:Programas.FilterBox = $flt
        $null = Add-TIPlaceholder -TextBox $flt -Text 'Filtrar por nome, fabricante ou versão'

        $global:Programas.Info = New-TIHint -Parent $b1 -Text 'Selecione um programa na lista para desinstalar.' -TopGap 0 -BottomGap 6

        $grid = New-TIGrid -Parent $b1 -Headers @('Programa', 'Versão', 'Fabricante', 'Tamanho') `
                           -Widths @(300, 120, 230, 100) -EmptyText 'Carregando a lista de programas...'
        $grid.Tag = 'tistretch'
        $grid.Height = 290
        $grid.Add_SelectionChanged({ Update-ProgramasSelection })
        $grid.Add_CellDoubleClick({ if ($_.RowIndex -ge 0) { Invoke-ProgramasUninstall } })
        $global:Programas.Grid = $grid

        $b2 = New-TICard -Parent $flow -Title 'Como funciona' -Desc 'O que acontece ao desinstalar' -Icon 'Info' -Width $w -Height 300
        foreach ($t in @(
            'Usa o modo silencioso quando o programa é MSI, Inno Setup ou NSIS, ou quando o fabricante informa um comando próprio.',
            'Se o tipo for desconhecido, abre a janela do desinstalador para você concluir.',
            'No fim, confere se o programa saiu mesmo da lista do Windows.',
            'Apps da Microsoft Store não aparecem aqui.',
            'Não há como desfazer: confira o nome antes de confirmar.'
        )) {
            $null = New-TIHint -Parent $b2 -Text $t -TopGap 0 -BottomGap 8
        }
    }
}

Register-TIWorkspace @wsProgramas
