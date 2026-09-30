# =====================================================================
# ÁREA: MANUTENÇÃO - perfis de alunos, limpeza profunda e manutenção em um passo
# =====================================================================

$global:Limpeza = @{
    Grid         = $null
    Rows         = @()
    ScanInfo     = $null
    RemoveBtn    = $null
    BulkBtn      = $null
    JunkGrid     = $null
    JunkRows     = @()
    JunkInfo     = $null
    JunkCleanBtn = $null
    Summary      = @{}
}

function Set-LimpezaSummary {
    param([string]$Key, [string]$Text, [string]$Tone = '')
    $r = $global:Limpeza.Summary[$Key]
    if ($r) { Set-TIRowValue $r $Text $Tone }
}

function Update-LimpezaScanInfo {
    param([string]$Text, [string]$Tone = 'muted')
    $l = $global:Limpeza.ScanInfo
    if ($l -and -not $l.IsDisposed) { $l.Text = $Text; $l.ForeColor = Get-TIToneColor $Tone }
}

function Update-LimpezaRemoveState {
    $grid = $global:Limpeza.Grid
    $sel = if ($grid) { $grid.SelectedRows.Count } else { 0 }
    if ($global:Limpeza.RemoveBtn) { $global:Limpeza.RemoveBtn.Enabled = (-not $global:TI.Busy -and $sel -gt 0) }
    if ($global:Limpeza.BulkBtn) { $global:Limpeza.BulkBtn.Enabled = (-not $global:TI.Busy -and @($global:Limpeza.Rows).Count -gt 0) }
    if ($global:Limpeza.JunkCleanBtn) { $global:Limpeza.JunkCleanBtn.Enabled = (-not $global:TI.Busy -and @($global:Limpeza.JunkRows).Count -gt 0) }
}

function Fill-LimpezaGrid {
    param($Rows)
    $grid = $global:Limpeza.Grid
    if (-not $grid) { return }
    $grid.Rows.Clear()
    $global:Limpeza.Rows = @($Rows)
    foreach ($r in @($Rows)) {
        if (-not $r) { continue }
        $row = Add-TIRow -Grid $grid -Cells @(
            $(if ($r.Loaded) { $r.Name + ' (em uso)' } else { $r.Name }),
            (Format-TIBytes $r.Size),
            (Format-TIDate $r.LastUse),
            $r.Path
        ) -Tag $r
        if ($r.Loaded) { $row.Cells[0].Style.ForeColor = $global:Pal.Warning }
    }
    Clear-TIGridSelection $grid
    Set-TIGridEmptyText $grid 'Nenhum perfil de aluno neste computador.'
    $count = @($Rows).Count
    $totalSize = ($Rows | Measure-Object -Property Size -Sum).Sum
    if ($count -eq 0) {
        Update-LimpezaScanInfo 'Nenhum perfil de aluno encontrado.' 'muted'
        Set-LimpezaSummary 'profiles' 'Nenhum encontrado' 'ok'
    } else {
        Update-LimpezaScanInfo ('{0} perfil(is), {1} no total. Selecione com Ctrl ou Shift para remover vários.' -f $count, (Format-TIBytes $totalSize)) 'primary'
        Set-LimpezaSummary 'profiles' ('{0} perfil(is), {1}' -f $count, (Format-TIBytes $totalSize))
    }
    Update-LimpezaRemoveState
}

function Invoke-LimpezaScan {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Verificação de perfis de alunos' -Quiet -Script {
        Get-StudentProfiles
    } -OnComplete {
        param($r)
        Fill-LimpezaGrid -Rows @($r | Where-Object { $_ -and $_.PSObject.Properties['Path'] })
    })
}

function Invoke-LimpezaRemoveItems {
    param($Items)
    $Items = @($Items | Where-Object { $_ })
    if ($Items.Count -eq 0) { Show-TIToast -Text 'Selecione ao menos um perfil na lista.' -Type 'Warn'; return }
    $totalSize = ($Items | Measure-Object -Property Size -Sum).Sum
    $maxShow = 15
    $listTxt = (($Items | Select-Object -First $maxShow | ForEach-Object {
        '  ' + $_.Name + $(if ($_.LastUse) { '  (último uso: ' + (Format-TIDate $_.LastUse) + ')' } else { '' })
    }) -join "`n")
    if ($Items.Count -gt $maxShow) { $listTxt += ("`n  e mais {0}" -f ($Items.Count - $maxShow)) }
    $msg = ("Estes {0} perfil(is) serão apagados do disco e do registro do Windows:`n`n{1}`n`nEspaço liberado: {2}. Perfis em uso ficam de fora.`nNão dá para desfazer." -f `
            $Items.Count, $listTxt, (Format-TIBytes $totalSize))
    $res = Show-TIConfirm -Title 'Remover perfis de alunos' -Message $msg `
            -ConfirmText 'Remover perfis' -Style 'Danger' -Icon 'Warning' -Force
    if (-not $res) { return }

    [void](Invoke-TIAsync -Name 'Remoção de perfis' -RequiresAdmin -Context @{ Items = $Items } -Script {
        Remove-StudentProfiles -Items $Context.Items
    } -OnComplete {
        param($r)
        $info = @($r | Where-Object { $_ -and $_.PSObject.Properties['Freed'] }) | Select-Object -First 1
        if ($info) {
            Set-LimpezaSummary 'last' ('{0} perfil(is) removido(s), {1} liberados' -f $info.Removed, (Format-TIBytes $info.Freed)) 'ok'
        }
        Invoke-LimpezaScan
    })
}

function Invoke-LimpezaRemoveSelected {
    $grid = $global:Limpeza.Grid
    if (-not $grid -or $grid.SelectedRows.Count -eq 0) { Show-TIToast -Text 'Selecione ao menos um perfil na lista.' -Type 'Warn'; return }
    $items = @()
    foreach ($row in $grid.SelectedRows) { if ($row.Tag) { $items += $row.Tag } }
    Invoke-LimpezaRemoveItems -Items $items
}

function Invoke-LimpezaRemoveAll {
    $items = @($global:Limpeza.Rows)
    if ($items.Count -eq 0) { Show-TIToast -Text 'Nenhum perfil para remover.' -Type 'Warn'; return }
    Invoke-LimpezaRemoveItems -Items $items
}

function Invoke-LimpezaRemoveInactive {
    if ($global:TI.Busy) { return }
    $daysText = Show-TIInput -Title 'Perfis sem uso' -Label 'Dias sem uso' -Value '90' `
            -Message 'Lista os perfis de alunos sem uso há mais de X dias para você confirmar a remoção.' -OkText 'Procurar'
    if (-not $daysText) { return }
    $days = 0
    if (-not [int]::TryParse($daysText.Trim(), [ref]$days) -or $days -lt 1) {
        Show-TIToast -Text 'Digite um número de dias válido (1 ou mais).' -Type 'Error'
        return
    }
    [void](Invoke-TIAsync -Name ('Perfis sem uso há mais de {0} dias' -f $days) -Quiet -Context @{ Days = $days } -Script {
        $all = Get-StudentProfiles
        $cutoff = (Get-Date).AddDays(-[int]$Context.Days)
        [pscustomobject]@{ Inactive = @($all | Where-Object { $_.LastUse -and $_.LastUse -lt $cutoff -and -not $_.Loaded }); Days = $Context.Days; All = @($all) }
    } -OnComplete {
        param($r)
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Inactive'] }) | Select-Object -First 1
        if (-not $res) { return }
        Fill-LimpezaGrid -Rows @($res.All)
        if (@($res.Inactive).Count -eq 0) {
            Show-TIToast -Text ('Nenhum perfil sem uso há mais de {0} dias.' -f $res.Days) -Type 'Info'
            return
        }
        Invoke-LimpezaRemoveItems -Items @($res.Inactive)
    })
}

function Fill-LimpezaJunkGrid {
    param($Rows)
    $grid = $global:Limpeza.JunkGrid
    if (-not $grid) { return }
    $grid.Rows.Clear()
    $global:Limpeza.JunkRows = @($Rows)
    foreach ($r in @($Rows)) {
        if (-not $r) { continue }
        [void](Add-TIRow -Grid $grid -Cells @($r.Group, $r.Label, (Format-TIBytes $r.Size), $r.Path) -Tag $r)
    }
    Clear-TIGridSelection $grid
    Set-TIGridEmptyText $grid 'Nada para limpar neste computador.'
    $count = @($Rows).Count
    $totalSize = ($Rows | Measure-Object -Property Size -Sum).Sum
    if ($global:Limpeza.JunkInfo) {
        if ($count -eq 0) {
            $global:Limpeza.JunkInfo.Text = 'Nada para limpar neste computador.'
            $global:Limpeza.JunkInfo.ForeColor = $global:Pal.TextMuted
            Set-LimpezaSummary 'junk' 'Nada para limpar' 'ok'
        } else {
            $global:Limpeza.JunkInfo.Text = ('{0} item(ns), {1} recuperáveis. Sem seleção, "Limpar" leva todos.' -f $count, (Format-TIBytes $totalSize))
            $global:Limpeza.JunkInfo.ForeColor = $global:Pal.Primary
            Set-LimpezaSummary 'junk' ('{0} recuperáveis' -f (Format-TIBytes $totalSize))
        }
    }
    Update-LimpezaRemoveState
}

function Invoke-LimpezaJunkScan {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Análise de limpeza' -Quiet -Script {
        Get-TIJunkScan
    } -OnComplete {
        param($r)
        Fill-LimpezaJunkGrid -Rows @($r | Where-Object { $_ -and $_.PSObject.Properties['Path'] })
    })
}

function Invoke-LimpezaClearCache {
    if ($global:TI.Busy) { return }
    $grid = $global:Limpeza.JunkGrid
    $items = @()
    if ($grid -and $grid.SelectedRows.Count -gt 0) {
        foreach ($row in $grid.SelectedRows) { if ($row.Tag) { $items += $row.Tag } }
    } else {
        $items = @($global:Limpeza.JunkRows)
    }
    if ($items.Count -eq 0) {
        Show-TIToast -Text 'Clique em Analisar para medir o que pode ser limpo.' -Type 'Warn'
        return
    }
    $totalSize = ($items | Measure-Object -Property Size -Sum).Sum
    $binNote = if (@($items | Where-Object { $_.Special -eq 'recycle' }).Count -gt 0) { "`nA Lixeira será esvaziada." } else { '' }
    $res = Show-TIConfirm -Title 'Limpar arquivos' -Style 'Primary' -Icon 'Erase' `
            -Message ("Remove {0} item(ns), {1} no total. Documentos e programas não são afetados.{2}" -f $items.Count, (Format-TIBytes $totalSize), $binNote) `
            -ConfirmText 'Limpar agora'
    if (-not $res) { return }
    [void](Invoke-TIAsync -Name 'Limpeza de temporários e caches' -Audit -Context @{ Items = $items } -Script {
        Clear-TIJunkItems -Items $Context.Items
    } -OnComplete {
        param($r)
        $info = @($r | Where-Object { $_ -and $_.PSObject.Properties['Freed'] }) | Select-Object -First 1
        if ($info) { Set-LimpezaSummary 'last' ('{0} liberados às {1}' -f (Format-TIBytes $info.Freed), (Get-Date -Format 'HH:mm')) 'ok' }
        Invoke-LimpezaJunkScan
    })
}

function Invoke-LimpezaFull {
    if ($global:TI.Busy) { return }
    # Apaga perfis: sempre pede confirmação (não obedece a "não pedir de novo")
    $res = Show-TIConfirm -Title 'Manutenção completa' -Icon 'Clean' -Style 'Danger' -Force `
        -Message ("Em um passo só:`n  1. Remove todos os perfis de alunos (os perfis em uso ficam de fora)`n  2. Limpa temporários, caches, Windows Update e a Lixeira`n`nIndicado para a troca de turma. Não dá para desfazer.") `
        -ConfirmText 'Executar manutenção'
    if (-not $res) { return }

    Write-TILog -Level 'Warn' -Message 'Manutenção completa solicitada pelo operador.'
    [void](Invoke-TIAsync -Name 'Manutenção completa' -RequiresAdmin -Script {
        $rows = Get-StudentProfiles
        $prof = $null
        if ($rows -and @($rows).Count -gt 0) {
            $prof = Remove-StudentProfiles -Items $rows
        } else {
            Emit 'Nenhum perfil de aluno para remover.' 'Info'
        }
        $junk = Clear-TISystemCache
        [pscustomobject]@{ Profiles = $prof; Junk = $junk }
    } -OnComplete {
        param($r)
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Junk'] }) | Select-Object -First 1
        if ($res) {
            $freed = 0.0
            if ($res.Profiles) { $freed += [double]$res.Profiles.Freed }
            if ($res.Junk) { $freed += [double]$res.Junk.Freed }
            Set-LimpezaSummary 'last' ('Manutenção completa: {0} liberados às {1}' -f (Format-TIBytes $freed), (Get-Date -Format 'HH:mm')) 'ok'
        }
        Invoke-LimpezaScan
    })
}

$wsLimpeza = @{
    Id       = 'limpeza'
    Title    = 'Manutenção'
    Sub      = 'Perfis de alunos, limpeza profunda e manutenção em um passo'
    Icon     = 'Clean'
    Keywords = 'manutencao limpeza perfil perfis aluno rm temporarios cache lixeira espaco disco'

    OnActivate = { if ($global:Limpeza.Grid -and $global:Limpeza.Grid.Rows.Count -eq 0) { Invoke-LimpezaScan } }
    Refresh    = { Invoke-LimpezaScan }

    Actions = {
        param($Bar)
        $b = New-TIButton -Text 'Atualizar' -Style 'Outline' -Width 116 -Height 34 -Icon 'Refresh' -Tip 'Verificar os perfis de novo (Ctrl+R)'
        $b.Add_Click({ Invoke-LimpezaScan })
        $Bar.Controls.Add($b)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $w = $global:Theme.CardWidth

        # --- Resumo -------------------------------------------------------
        $bSum = New-TICard -Parent $flow -Title 'Resumo' -Desc 'Perfis de alunos e espaço recuperável' -Icon 'Document' -Width $w -Height 196
        $iw = Get-TIInnerWidth $bSum
        foreach ($p in @(
            @{ K = 'profiles'; L = 'Perfis de alunos'; V = 'Verificando...' },
            @{ K = 'junk';     L = 'Limpeza profunda'; V = 'Clique em Analisar' },
            @{ K = 'last';     L = 'Última limpeza';   V = 'Nenhuma nesta sessão' }
        )) {
            $r = New-TIRow -Label $p.L -Value $p.V -Width $iw -LabelWidth 124
            $r.Value.ForeColor = $global:Pal.TextMuted
            $bSum.Controls.Add($r.Panel)
            $global:Limpeza.Summary[$p.K] = $r
        }

        # --- Manutenção completa -------------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Manutenção completa' -Desc 'Perfis de alunos, caches e Lixeira de uma vez' -Icon 'Power' -Width $w -Height 196
        $null = New-TIHint -Parent $b3 -Text 'Indicado para a troca de turma. Precisa do TI Suite aberto como administrador.' -BottomGap 10
        $btnFull = New-TIButton -Text 'Executar manutenção completa' -Style 'Primary' -Width 270 -Height 42 -Icon 'Power' -GlyphSize 13
        $btnFull.Add_Click({ Invoke-LimpezaFull })
        $b3.Controls.Add($btnFull)

        # --- Perfis de alunos ------------------------------------------------
        $b1 = New-TICard -Parent $flow -Title 'Perfis de alunos (RM)' -Stretch `
                -Desc 'Perfis numéricos criados pelo login dos alunos, inclusive os com sufixo (.000, .DOMÍNIO)' -Icon 'People' -Width $w -Height 452
        $bar1 = New-TIButtonBar -Parent $b1
        $btnScan = New-TIButton -Text 'Verificar perfis' -Style 'Outline' -Width 156 -Height 36 -Icon 'Search'
        $btnScan.Add_Click({ Invoke-LimpezaScan })
        $bar1.Controls.Add($btnScan)
        $btnRemove = New-TIButton -Text 'Remover selecionados' -Style 'Danger' -Width 190 -Height 36 -Icon 'Remove'
        $btnRemove.Enabled = $false
        $btnRemove.Add_Click({ Invoke-LimpezaRemoveSelected })
        $bar1.Controls.Add($btnRemove)
        $global:Limpeza.RemoveBtn = $btnRemove
        $btnBulk = New-TIButton -Text 'Remover todos' -Style 'Danger' -Width 146 -Height 36 -Icon 'Stop'
        $btnBulk.Enabled = $false
        $btnBulk.Add_Click({ Invoke-LimpezaRemoveAll })
        $bar1.Controls.Add($btnBulk)
        $global:Limpeza.BulkBtn = $btnBulk
        $btnInactive = New-TIButton -Text 'Sem uso há...' -Style 'Soft' -Width 136 -Height 36 -Icon 'Clock' -Tip 'Remover só os perfis sem uso há X dias'
        $btnInactive.Add_Click({ Invoke-LimpezaRemoveInactive })
        $bar1.Controls.Add($btnInactive)

        $global:Limpeza.ScanInfo = New-TIHint -Parent $b1 -Text 'Verificando os perfis...' -TopGap 0 -BottomGap 6

        $grid1 = New-TIGrid -Parent $b1 -Headers @('Usuário (RM)', 'Tamanho', 'Último uso', 'Pasta') `
                            -Widths @(150, 100, 140, 320) -Multi -EmptyText 'Clique em Verificar perfis para listar os perfis de alunos.'
        $grid1.Tag = 'tistretch'
        $grid1.Height = 250
        $grid1.Add_SelectionChanged({ Update-LimpezaRemoveState })
        $global:Limpeza.Grid = $grid1

        # --- Limpeza profunda --------------------------------------------------
        $b2 = New-TICard -Parent $flow -Title 'Limpeza profunda' -Stretch `
                -Desc 'Temporários, navegadores, Windows Update, logs, despejos de memória e Lixeira' -Icon 'Erase' -Width $w -Height 372
        $bar2 = New-TIButtonBar -Parent $b2
        $btnScanJ = New-TIButton -Text 'Analisar' -Style 'Outline' -Width 124 -Height 36 -Icon 'Search'
        $btnScanJ.Add_Click({ Invoke-LimpezaJunkScan })
        $bar2.Controls.Add($btnScanJ)
        $btnCache = New-TIButton -Text 'Limpar' -Style 'Primary' -Width 120 -Height 36 -Icon 'Clean' -Tip 'Limpa os itens selecionados (ou todos, sem seleção)'
        $btnCache.Enabled = $false
        $btnCache.Add_Click({ Invoke-LimpezaClearCache })
        $bar2.Controls.Add($btnCache)
        $global:Limpeza.JunkCleanBtn = $btnCache

        $global:Limpeza.JunkInfo = New-TIHint -Parent $b2 -Text 'Clique em Analisar para medir o que pode ser limpo.' -TopGap 0 -BottomGap 6

        $gridJ = New-TIGrid -Parent $b2 -Headers @('Grupo', 'Item', 'Tamanho', 'Pasta') `
                            -Widths @(120, 240, 100, 300) -Multi -EmptyText 'Clique em Analisar para medir o que pode ser limpo.'
        $gridJ.Tag = 'tistretch'
        $gridJ.Height = 200
        $gridJ.Add_SelectionChanged({ Update-LimpezaRemoveState })
        $global:Limpeza.JunkGrid = $gridJ
    }
}

Register-TIWorkspace @wsLimpeza
