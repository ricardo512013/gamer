# =====================================================================
# ÁREA: PROGRAMAS - lista e desinstalação em lote
# =====================================================================

$global:Programas = @{
    Grid         = $null
    Body         = $null
    Flow         = $null
    Rows         = @()
    FilterBox    = $null
    FilterTimer  = $null
    Info         = $null
    UninstBtn    = $null
    CountLabel   = $null
    MarkBtns     = @()
    SummaryCard  = $null
    SummaryLabel = $null
    RestartBtn   = $null
}

$global:ProgramasAdminMsg = 'Esta ação precisa do TI Suite aberto como administrador: clique no selo "Sem elevação" na barra lateral.'

# Coluna 0 da lista: caixa desenhada com glifo (marcado, desmarcado ou cadeado)
$global:ProgramasGlyph = @{
    On   = [string][char]0xE73A   # CheckboxComposite
    Off  = [string][char]0xE739   # Checkbox
    Lock = [string][char]0xE72E   # Lock
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

# Programas marcados em toda a lista — não só os visíveis
function Get-ProgramasMarked {
    return @($global:Programas.Rows | Where-Object { $_ -and $_.Marked })
}

function Set-ProgramasRowMark {
    param($Row, [bool]$On)
    if (-not $Row -or -not $Row.Tag) { return }
    $Row.Tag.Marked = $On
    $Row.Cells[0].Value = $(if ($On) { $global:ProgramasGlyph.On } else { $global:ProgramasGlyph.Off })
    $Row.Cells[0].Style.ForeColor = $(if ($On) { $global:Pal.Primary } else { $global:Pal.TextMuted })
    $Row.Cells[0].Style.SelectionForeColor = $Row.Cells[0].Style.ForeColor
}

# Clique na caixa, Espaço ou botão: se alguma estiver desmarcada, marca todas; senão desmarca
function Switch-ProgramasRows {
    param($Rows)
    $all = @($Rows | Where-Object { $_ -and $_.Tag })
    $rows = @($all)
    if ($rows.Count -eq 0) { return }
    $on = (@($rows | Where-Object { -not $_.Tag.Marked }).Count -gt 0)
    foreach ($r in $rows) { Set-ProgramasRowMark -Row $r -On $on }
    Update-ProgramasMarkInfo
}

# Marca/desmarca todos os programas visíveis
function Set-ProgramasMarkAll {
    param([bool]$On)
    $grid = $global:Programas.Grid
    if (-not $grid) { return }
    foreach ($r in $grid.Rows) {
        if (-not $r.Tag) { continue }
        Set-ProgramasRowMark -Row $r -On $On
    }
    Update-ProgramasMarkInfo
}

function Update-ProgramasMarkInfo {
    $rows = @($global:Programas.Rows | Where-Object { $_ })
    $total = $rows.Count
    $markable = $total
    $marked = @(Get-ProgramasMarked).Count
    $shown = @(Get-ProgramasFiltered).Count
    if ($global:Programas.CountLabel) {
        $base = if ($shown -eq $total) { Format-ProgramasCount $total } else { '{0} de {1}' -f $shown, (Format-ProgramasCount $total) }
        $global:Programas.CountLabel.Text = ('{0} — {1} marcado(s)' -f $base, $marked)
    }
    $info = $global:Programas.Info
    if ($info) {
        if ($markable -eq 0) {
            $info.Text = 'Nenhum programa carregado. Clique em Atualizar.'
            $info.ForeColor = $global:Pal.TextMuted
        } elseif ($marked -eq 0) {
            $info.Text = 'Marque os programas e clique em Desinstalar marcados. Clique na caixa ou use Espaço; duplo clique desinstala um só.'
            $info.ForeColor = $global:Pal.TextMuted
        } else {
            $info.Text = ('{0} programa(s) marcado(s) para desinstalar.' -f $marked)
            $info.ForeColor = $global:Pal.Primary
        }
    }
    if ($global:Programas.UninstBtn) {
        $global:Programas.UninstBtn.Enabled = ($marked -gt 0 -and -not $global:TI.Busy)
        $global:Programas.UninstBtn.Text = $(if ($marked -gt 0) { 'Desinstalar marcados ({0})' -f $marked } else { 'Desinstalar marcados' })
    }
    foreach ($b in @($global:Programas.MarkBtns)) { if ($b) { $b.Enabled = ($markable -gt 0 -and -not $global:TI.Busy) } }
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
        $row = Add-TIRow -Grid $grid -Cells @(
            '',
            $r.Name,
            $(if ($r.Version) { $r.Version } else { '-' }),
            $(if ($r.Publisher) { $r.Publisher } else { '-' }),
            $(if ($r.Size -gt 0) { Format-TIBytes $r.Size } else { '-' }),
            $(if ($date) { ([datetime]$date).ToString('dd/MM/yyyy') } else { '-' }),
            $(if ($r.Scope) { $r.Scope } else { '-' })
        ) -Tag $r -SortKeys @($null, $null, $null, $null, [double]$r.Size, $(if ($date) { [datetime]$date } else { [datetime]::MinValue }), $null)
        Set-ProgramasRowMark -Row $row -On ([bool]$r.Marked)
        # Nada fica travado: runtime/antivírus só ganha um aviso ao passar o mouse.
        if ($r.Sensitive) {
            $row.Cells[0].ToolTipText = 'Atenção: ' + $r.LockReason + '. Dá para desinstalar; faça com cuidado.'
            $row.Cells[1].ToolTipText = ('Runtime/antivírus: {0}. Dá para desinstalar no lote; pode afetar outros programas.' -f $r.LockReason)
        } else {
            $row.Cells[0].ToolTipText = 'Marcar ou desmarcar'
        }
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
    Update-ProgramasMarkInfo
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
        # Texto de busca pronto (sem acento, minúsculo): o filtro não recalcula a cada tecla.
        # Nada vem marcado: o técnico marca o que quiser.
        foreach ($x in $rows) {
            Add-Member -InputObject $x -NotePropertyName 'Search' -Force `
                       -NotePropertyValue (ConvertTo-TIPlain ('{0} {1} {2}' -f $x.Name, $x.Publisher, $x.Version))
            Add-Member -InputObject $x -NotePropertyName 'Marked' -NotePropertyValue $false -Force
        }
        $global:Programas.Rows = $rows
        Fill-ProgramasGrid
    })
}

# Resumo do lote no card (o console já recebeu as linhas durante a tarefa)
function Set-ProgramasBatchResult {
    param($Res)
    if (-not $Res) { return }
    $head = ('Resultado ({0}): {1} desinstalado(s), {2} não desinstalado(s), {3} cancelado(s).' -f `
            (Get-Date -Format 'HH:mm'), [int]$Res.Done, [int]$Res.Fail, [int]$Res.Cancelled)
    if ($global:Programas.SummaryLabel) {
        $global:Programas.SummaryLabel.Text = $head + "`n`n" + [string]$Res.Summary
        $tone = if ([int]$Res.Fail -gt 0) { 'crit' } elseif ([int]$Res.Cancelled -gt 0) { 'warn' } else { 'ok' }
        $global:Programas.SummaryLabel.ForeColor = Get-TIToneColor $tone
    }
    if ($global:Programas.RestartBtn) { $global:Programas.RestartBtn.Visible = [bool]$Res.Reboot }
    if ($global:Programas.SummaryCard) { try { Update-TICardHeight $global:Programas.SummaryCard } catch { } }
}

# Desinstalação em lote: uma confirmação, depois uma única tarefa que remove um a um
function Invoke-ProgramasUninstall {
    if ($global:TI.Busy) { return }
    $items = @(Get-ProgramasMarked)
    if ($items.Count -eq 0) { Show-TIToast -Text 'Marque ao menos um programa na lista.' -Type 'Warn'; return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text $global:ProgramasAdminMsg -Type 'Error'; return }
    $list = (($items | Select-Object -First 20 | ForEach-Object { '  ' + $_.Name }) -join "`n")
    if ($items.Count -gt 20) { $list += ("`n  e mais {0}" -f ($items.Count - 20)) }
    $msg = ("Estes {0} programa(s) serão desinstalados, um a um:`n`n{1}`n`nAntes de cada um, o TI Suite fecha as janelas e os processos dele e para os serviços dele (só dentro da pasta de instalação do programa), para os arquivos não ficarem presos. Usa o modo silencioso quando o fabricante permite; se não, abre a janela do desinstalador para você concluir. Não dá para desfazer." -f `
            $items.Count, $list)
    $sens = @($items | Where-Object { $_.Sensitive })
    if ($sens.Count -gt 0) {
        $sl = (@($sens | Select-Object -First 8 | ForEach-Object { '  ' + $_.Name }) -join "`n")
        if ($sens.Count -gt 8) { $sl += ("`n  e mais {0}" -f ($sens.Count - 8)) }
        $msg += ("`n`nATENÇÃO: a seleção inclui runtime(s)/antivírus. Desinstalar pode afetar outros programas ou a proteção do PC:`n{0}" -f $sl)
    }
    $res = Show-TIConfirm -Title 'Desinstalar marcados' -Message $msg `
            -ConfirmText ('Desinstalar {0}' -f $items.Count) -Style 'Danger' -Icon 'Warning'
    if (-not $res) { return }
    $names = (($items | Select-Object -First 25 | ForEach-Object { $_.Name }) -join ', ')
    if ($items.Count -gt 25) { $names += (' e mais {0}' -f ($items.Count - 25)) }
    if ($global:Programas.SummaryLabel) {
        $global:Programas.SummaryLabel.Text = 'Desinstalando...'
        $global:Programas.SummaryLabel.ForeColor = $global:Pal.TextMuted
    }
    if ($global:Programas.RestartBtn) { $global:Programas.RestartBtn.Visible = $false }
    [void](Invoke-TIAsync -Name ('Desinstalação de {0} programa(s)' -f $items.Count) -RequiresAdmin -Context @{ Apps = $items } `
            -AuditDetail ('Programas: ' + $names) -Script {
        Uninstall-TIAppBatch -Apps $Context.Apps
    } -OnComplete {
        param($r)
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'UninstallBatch' }) | Select-Object -First 1
        Set-ProgramasBatchResult $res
        if ($res -and [bool]$res.Reboot) {
            Show-TIToast -Text 'Um ou mais programas pedem reinício. Use "Reiniciar agora" para concluir.' -Type 'Warn' -Duration 7000
        }
        Refresh-ProgramasList
    })
}

# Desinstalação individual (como hoje): pelo duplo clique, vale para qualquer
# programa. Não encerra processos nem serviços (usa o desinstalador do fabricante).
function Invoke-ProgramasUninstallOne {
    param($App)
    if ($global:TI.Busy -or -not $App) { return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text $global:ProgramasAdminMsg -Type 'Error'; return }
    $sel = $App
    $when = $(if ($sel.InstallDate) { ([datetime]$sel.InstallDate).ToString('dd/MM/yyyy') } else { '-' })
    $lockNote = $(if ($sel.Sensitive) { ("`n`nAtenção: {0}. Dá para desinstalar, mas pode afetar outros programas ou a proteção do PC." -f $sel.LockReason) } else { '' })
    $msg = ("Desinstalar '{0}'?`n`nVersão: {1}`nFabricante: {2}`nInstalado em: {3}`nPara: {4}{5}`n`nO TI Suite usa o modo silencioso quando o fabricante permite; se não, abre a janela do desinstalador para você concluir. Não dá para desfazer." -f `
        $sel.Name, $(if ($sel.Version) { $sel.Version } else { '-' }), $(if ($sel.Publisher) { $sel.Publisher } else { '-' }),
        $when, $(if ($sel.Scope) { $sel.Scope } else { '-' }), $lockNote)
    $res = Show-TIConfirm -Title 'Desinstalar programa' -Message $msg `
            -ConfirmText 'Desinstalar' -Style 'Danger' -Icon 'Warning'
    if (-not $res) { return }
    $appName = [string]$sel.Name
    [void](Invoke-TIAsync -Name ('Desinstalação de ' + $appName) -RequiresAdmin -Context @{ App = $sel } `
            -AuditDetail ('Programa: ' + $appName) -Script {
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

# "Reiniciar agora": só por clique e com confirmação (nunca reinicia sozinho)
function Invoke-ProgramasRestart {
    if ($global:TI.Busy) { return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text $global:ProgramasAdminMsg -Type 'Error'; return }
    $res = Show-TIConfirm -Title 'Reiniciar o computador' -Style 'Danger' -Icon 'Warning' `
            -Message "O computador vai reiniciar em 15 segundos para concluir a remoção dos programas.`n`nSalve o que estiver aberto nas outras janelas. Para cancelar depois, abra o Prompt de Comando e rode: shutdown /a" `
            -ConfirmText 'Reiniciar agora'
    if (-not $res) { return }
    try {
        Start-Process -FilePath 'shutdown.exe' -ArgumentList @('/r', '/t', '15') -WindowStyle Hidden -ErrorAction Stop
        Write-TILog -Level 'Warn' -Message 'Reinício agendado (shutdown /r /t 15) pelo operador.'
        Show-TIToast -Text 'O computador vai reiniciar em 15 segundos. Para cancelar: shutdown /a no Prompt.' -Type 'Warn' -Duration 8000
    } catch {
        Show-TIToast -Text ('Não foi possível agendar o reinício: {0}' -f $_.Exception.Message) -Type 'Error'
    }
}

$wsProgramas = @{
    Id       = 'programas'
    Title    = 'Programas'
    Sub      = 'Programas instalados e desinstalação em lote, sem janelas quando possível'
    Icon     = 'Apps'
    Keywords = 'programas aplicativos software desinstalar remover instalados data instalacao lote marcados'

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
        $btnUn = New-TIButton -Text 'Desinstalar marcados' -Style 'Danger' -Width 220 -Height 36 -Icon 'Remove'
        $btnUn.Enabled = $false
        $btnUn.Add_Click({ Invoke-ProgramasUninstall })
        $bar.Controls.Add($btnUn)
        $global:Programas.UninstBtn = $btnUn
        $btnAll = New-TIButton -Text 'Marcar todos' -Style 'Ghost' -Width 132 -Height 36 -Icon 'CheckList' -Tip 'Marca todos os programas que podem entrar no lote'
        $btnAll.Enabled = $false
        $btnAll.Add_Click({ Set-ProgramasMarkAll -On $true })
        $bar.Controls.Add($btnAll)
        $btnNone = New-TIButton -Text 'Desmarcar todos' -Style 'Ghost' -Width 150 -Height 36 -Icon 'Undo'
        $btnNone.Enabled = $false
        $btnNone.Add_Click({ Set-ProgramasMarkAll -On $false })
        $bar.Controls.Add($btnNone)
        $global:Programas.MarkBtns = @($btnAll, $btnNone)
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
            elseif ($_.KeyCode -eq 'Enter') {
                $_.SuppressKeyPress = $true
                $t = $global:Programas.FilterTimer
                if ($t) { $t.Stop() }
                Fill-ProgramasGrid
            }
        })
        $filterRow.Controls.Add($flt)
        $global:Programas.FilterBox = $flt
        $null = Add-TIPlaceholder -TextBox $flt -Text 'Filtrar por nome, fabricante ou versão'

        $global:Programas.Info = New-TIHint -Parent $b1 -Text 'Marque os programas e clique em Desinstalar marcados. Clique na caixa ou use Espaço; duplo clique desinstala um só.' -TopGap 0 -BottomGap 6

        $grid = New-TIGrid -Parent $b1 -Headers @('', 'Programa', 'Versão', 'Fabricante', 'Tamanho', 'Instalado em', 'Para') `
                           -Widths @(40, 250, 100, 180, 90, 100, 76) -Multi -EmptyText 'Carregando a lista de programas...'
        $grid.Tag = 'tistretch'
        $grid.Height = 290
        $chk = $grid.Columns[0]
        $chk.AutoSizeMode = 'None'
        $chk.Width = 40
        $chk.SortMode = 'NotSortable'
        $chk.Resizable = 'False'
        $chk.DefaultCellStyle.Font = New-TIFont 12 Regular 'Segoe MDL2 Assets'
        $chk.DefaultCellStyle.Alignment = 'MiddleCenter'
        $chk.ToolTipText = 'Clique para marcar ou desmarcar todos'
        $grid.Columns[5].ToolTipText = 'Data gravada pelo instalador (nem todo programa informa)'
        $grid.Columns[6].ToolTipText = 'Máquina: para todos os usuários. Usuário: só para a conta que abriu o TI Suite.'
        # Clique na caixa (MouseUp conta os dois cliques de um duplo clique rápido)
        $grid.Add_CellMouseUp({
            param($s, $e)
            if ($e.Button -ne 'Left' -or $e.RowIndex -lt 0 -or $e.ColumnIndex -ne 0 -or $global:TI.Busy) { return }
            Switch-ProgramasRows @($s.Rows[$e.RowIndex])
        })
        # Duplo clique numa célula de dados: desinstala só aquele programa (como hoje)
        $grid.Add_CellMouseDoubleClick({
            param($s, $e)
            if ($e.Button -ne 'Left' -or $e.RowIndex -lt 0 -or $e.ColumnIndex -le 0 -or $global:TI.Busy) { return }
            $row = $s.Rows[$e.RowIndex]
            if ($row.Tag) { Invoke-ProgramasUninstallOne -App $row.Tag }
        })
        $grid.Add_ColumnHeaderMouseClick({
            param($s, $e)
            if ($e.ColumnIndex -ne 0 -or $global:TI.Busy) { return }
            $gridRows = @($s.Rows | Where-Object { $_.Tag })
            $allOn = ($gridRows.Count -gt 0 -and @($gridRows | Where-Object { -not $_.Tag.Marked }).Count -eq 0)
            Set-ProgramasMarkAll -On (-not $allOn)
        })
        $grid.Add_KeyDown({
            param($s, $e)
            if ($e.KeyCode -eq 'Space' -and -not $global:TI.Busy) {
                $e.Handled = $true
                $e.SuppressKeyPress = $true
                Switch-ProgramasRows @($s.SelectedRows)
            }
        })
        $global:Programas.Grid = $grid
        $flow.Add_Resize({ Update-ProgramasHeight })

        # --- Resultado da desinstalação ------------------------------------
        $b2 = New-TICard -Parent $flow -Title 'Resultado da desinstalação' -Desc 'Resumo da última desinstalação em lote' -Icon 'Report' -Width $w -Height 200
        $global:Programas.SummaryCard = $b2
        $global:Programas.SummaryLabel = New-TIHint -Parent $b2 -Text 'Nenhuma desinstalação nesta sessão.' -TopGap 0 -BottomGap 10
        $btnRestart = New-TIButton -Text 'Reiniciar agora' -Style 'Danger' -Width 170 -Height 38 -Icon 'Power' -Tip 'Reinicia o computador em 15 segundos para concluir a remoção'
        $btnRestart.Visible = $false
        $btnRestart.Add_Click({ Invoke-ProgramasRestart })
        $b2.Controls.Add($btnRestart)
        $global:Programas.RestartBtn = $btnRestart

        # --- Como funciona -------------------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Como funciona' -Desc 'O que acontece ao desinstalar' -Icon 'Info' -Width $w -Height 300
        foreach ($t in @(
            'Marque os programas e use "Desinstalar marcados" para removê-los um a um numa única tarefa.',
            'Antes de cada programa, o TI Suite fecha as janelas e os processos dele e para os serviços dele — só dentro da pasta de instalação do programa — para evitar o aviso de "aplicativo aberto".',
            'Usa o modo silencioso quando o programa é MSI, Inno Setup ou NSIS, ou quando o fabricante informa um comando próprio; se não, abre a janela do desinstalador.',
            'Ficam de fora do lote (com cadeado): runtimes essenciais (Visual C++, .NET, Windows App Runtime, WebView2) e antivírus/segurança. Use o duplo clique para desinstalá-los pelo desinstalador do fabricante.',
            'No fim, mostra o resumo por programa; se algum pedir reinício, aparece "Reiniciar agora".',
            'Apps da Microsoft Store não aparecem aqui. Não há como desfazer: confira antes de confirmar.'
        )) {
            $null = New-TIHint -Parent $b3 -Text $t -TopGap 0 -BottomGap 8
        }
    }
}

Register-TIWorkspace @wsProgramas
