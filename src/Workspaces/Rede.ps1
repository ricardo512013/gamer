# =====================================================================
# ÁREA: REDE - adaptadores, Wi-Fi, diagnóstico e reparo
# =====================================================================

$global:Rede = @{
    GridAdapters = $null
    GridResults  = $null
    WifiBody     = $null
    WifiInfo     = $null
    SummaryLabel = $null
    RepairBtn    = $null
    Adapters     = @()
    Selected     = $null
}

function Update-RedeSelection {
    $btn = $global:Rede.RepairBtn
    if (-not $btn) { return }
    $grid = $global:Rede.GridAdapters
    $has = ($grid -and $grid.SelectedRows.Count -gt 0)
    $btn.Enabled = (-not $global:TI.Busy -and $has)
}

function Refresh-RedeAdapters {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Leitura dos adaptadores de rede' -Quiet -Script {
        Get-TIAdapters
    } -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Name'] })
        $global:Rede.Adapters = $rows
        $grid = $global:Rede.GridAdapters
        if ($grid) {
            $grid.Rows.Clear()
            foreach ($a in $rows) {
                $st = switch ($a.Status) { 'Up' { 'Conectado' } 'Disconnected' { 'Desconectado' } 'Disabled' { 'Desativado' } default { $a.Status } }
                $row = Add-TIRow -Grid $grid -Cells @(
                    $a.Name, $st,
                    $(if ($a.Ip) { $a.Ip } else { '-' }),
                    $(if ($a.Gateway) { $a.Gateway } else { '-' }),
                    $(if ($a.Dns) { $a.Dns } else { '-' }),
                    $(if ($a.Speed) { $a.Speed } else { '-' })
                ) -Tag $a
                if ($a.Status -eq 'Up') { $row.Cells[1].Style.ForeColor = $global:Pal.Success }
                else { $row.Cells[1].Style.ForeColor = $global:Pal.TextDim }
            }
            Clear-TIGridSelection $grid
        }
        $global:Rede.Selected = $null
        Update-RedeSelection
    })
}

function Select-RedeAdapterAtual {
    $grid = $global:Rede.GridAdapters
    if (-not $grid -or $grid.SelectedRows.Count -eq 0) { $global:Rede.Selected = $null }
    else { $global:Rede.Selected = $grid.SelectedRows[0].Tag }
    Update-RedeSelection
}

function Invoke-RedeRepair {
    Select-RedeAdapterAtual
    $sel = $global:Rede.Selected
    if (-not $sel) { Show-TIToast -Text 'Selecione um adaptador na lista.' -Type 'Warn'; return }
    $res = Show-TIConfirm -Title 'Reiniciar adaptador' -Style 'Danger' -Icon 'Warning' -Force `
            -Message ("O adaptador '{0}' será desativado e ativado de novo. A conexão cai por alguns segundos." -f $sel.Name) `
            -ConfirmText 'Reiniciar agora'
    if (-not $res) { return }
    $name = $sel.Name
    [void](Invoke-TIAsync -Name ('Reinício do adaptador ' + $name) -RequiresAdmin -Context @{ Name = $name } -Script {
        Repair-TIAdapter -Name $Context.Name
    } -OnComplete { param($r) Refresh-RedeAdapters })
}

function Invoke-RedeWifi {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Leitura do Wi-Fi' -Quiet -Script {
        Get-TIWifiInfo
    } -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Label'] })
        $body = $global:Rede.WifiBody
        if ($body) {
            $body.SuspendLayout()
            foreach ($c in @($body.Controls | Where-Object { $_.Tag -eq 'tirow' })) { $body.Controls.Remove($c); $c.Dispose() }
            foreach ($row in $rows) {
                $rr = New-TIRow -Label $row.Label -Width (Get-TIInnerWidth $body) -LabelWidth 124
                Set-TIRowValue $rr $row.Value $row.Tone
                $body.Controls.Add($rr.Panel)
            }
            $body.ResumeLayout()
        }
        if ($global:Rede.WifiInfo) { $global:Rede.WifiInfo.Text = ('Lido às {0}.' -f (Get-Date -Format 'HH:mm')) }
    })
}

function Invoke-RedeTest {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Teste de conexão' -Quiet -Script {
        Test-TINetwork
    } -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Target'] })
        $grid = $global:Rede.GridResults
        if ($grid) {
            $grid.Rows.Clear()
            foreach ($t in $rows) {
                $row = Add-TIRow -Grid $grid -Cells @(
                    $t.Target, $t.Addr,
                    $(if ($t.Ok) { 'OK' } else { 'Falha' }),
                    $(if ($t.Latency -ge 0) { '{0} ms' -f $t.Latency } else { '-' }),
                    $t.Detail
                ) -Tag $t
                $row.Cells[2].Style.ForeColor = $(if ($t.Ok) { $global:Pal.Success } else { $global:Pal.Danger })
            }
            Clear-TIGridSelection $grid
        }
        $up = @($rows | Where-Object { $_.Ok }).Count
        if ($global:Rede.SummaryLabel) {
            $l = $global:Rede.SummaryLabel
            if ($rows.Count -gt 0 -and $up -eq $rows.Count) {
                $l.Text = ('Tudo certo: {0} de {1} testes OK.' -f $up, $rows.Count); $l.ForeColor = $global:Pal.Success
            } else {
                $fail = @($rows | Where-Object { -not $_.Ok } | Select-Object -First 1)
                $l.Text = ('{0} de {1} testes OK. Primeira falha: {2}.' -f $up, $rows.Count, $(if ($fail) { $fail[0].Target } else { '-' }))
                $l.ForeColor = $global:Pal.Warning
            }
        }
    })
}

function Invoke-RedeFlushDns {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Limpeza do cache de DNS' -Script { Clear-TIDnsCache } -OnComplete { param($r) })
}

function Invoke-RedeRenew {
    if ($global:TI.Busy) { return }
    $res = Show-TIConfirm -Title 'Renovar o endereço IP' -Style 'Danger' -Icon 'Warning' -Force `
            -Message 'Roda ipconfig /release e /renew. A conexão cai por alguns segundos.' `
            -ConfirmText 'Renovar IP'
    if (-not $res) { return }
    [void](Invoke-TIAsync -Name 'Renovação do endereço IP' -RequiresAdmin -Script {
        Reset-TINetwork
    } -OnComplete { param($r) Refresh-RedeAdapters })
}

$wsRede = @{
    Id       = 'rede'
    Title    = 'Rede'
    Sub      = 'Adaptadores, Wi-Fi, teste de conexão e reparo'
    Icon     = 'Globe'
    Keywords = 'rede internet wifi wi-fi adaptador ip dns ping proxy conexao'

    OnActivate = { if (@($global:Rede.Adapters).Count -eq 0) { Refresh-RedeAdapters } }
    Refresh    = { Refresh-RedeAdapters }

    Actions = {
        param($Bar)
        $b = New-TIButton -Text 'Atualizar' -Style 'Outline' -Width 116 -Height 34 -Icon 'Refresh' -Tip 'Ler os adaptadores de novo (Ctrl+R)'
        $b.Add_Click({ Refresh-RedeAdapters })
        $Bar.Controls.Add($b)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $w = $global:Theme.CardWidth

        # --- Adaptadores ---------------------------------------------------
        $b1 = New-TICard -Parent $flow -Title 'Adaptadores de rede' -Stretch -Icon 'Ethernet' -Desc 'Placas físicas e virtuais deste computador' -Width $w -Height 370
        $bar = New-TIButtonBar -Parent $b1
        $btnRepair = New-TIButton -Text 'Reiniciar adaptador' -Style 'Danger' -Width 186 -Height 36 -Icon 'Undo'
        $btnRepair.Enabled = $false
        $btnRepair.Add_Click({ Invoke-RedeRepair })
        $bar.Controls.Add($btnRepair)
        $global:Rede.RepairBtn = $btnRepair
        $null = Add-TIBarLabel -Bar $bar -Text 'Selecione um adaptador para reiniciá-lo (desativar e ativar).'

        $gridA = New-TIGrid -Parent $b1 -Headers @('Adaptador', 'Estado', 'IPv4', 'Gateway', 'DNS', 'Velocidade') `
                            -Widths @(170, 110, 140, 130, 190, 110) -EmptyText 'Carregando os adaptadores...'
        $gridA.Tag = 'tistretch'
        $gridA.Height = 246
        $gridA.Add_SelectionChanged({ Select-RedeAdapterAtual })
        $global:Rede.GridAdapters = $gridA

        # --- Wi-Fi ---------------------------------------------------------
        $b2 = New-TICard -Parent $flow -Title 'Wi-Fi' -Icon 'Wifi' -Desc 'Sinal e dados da conexão sem fio' -Width $w -Height 340
        $wBar = New-TIButtonBar -Parent $b2
        $btnWifi = New-TIButton -Text 'Verificar sinal' -Style 'Outline' -Width 160 -Height 36 -Icon 'Signal'
        $btnWifi.Add_Click({ Invoke-RedeWifi })
        $wBar.Controls.Add($btnWifi)
        $global:Rede.WifiInfo = Add-TIBarLabel -Bar $wBar -Text 'Ainda não lido.'
        $global:Rede.WifiBody = $b2

        # --- Diagnóstico ---------------------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Diagnóstico' -Icon 'Diagnostic' -Desc 'Testes e correções de conexão' -Width $w -Height 340
        $btnTest = New-TIButton -Text 'Testar conexão' -Style 'Primary' -Width 250 -Height 40 -Icon 'Check'
        $btnTest.Add_Click({ Invoke-RedeTest })
        $b3.Controls.Add($btnTest)
        $btnDns = New-TIButton -Text 'Limpar cache de DNS' -Style 'Soft' -Width 250 -Height 40 -Icon 'Erase'
        $btnDns.Add_Click({ Invoke-RedeFlushDns })
        $b3.Controls.Add($btnDns)
        $btnRenew = New-TIButton -Text 'Renovar endereço IP' -Style 'Outline' -Width 250 -Height 40 -Icon 'Sync'
        $btnRenew.Add_Click({ Invoke-RedeRenew })
        $b3.Controls.Add($btnRenew)
        $null = New-TIHint -Parent $b3 -Text 'O teste confere o roteador, servidores públicos, o DNS e o acesso à internet (detecta portal de login e proxy).' -TopGap 4

        # --- Resultados ----------------------------------------------------
        $b4 = New-TICard -Parent $flow -Title 'Resultado do teste' -Stretch -Icon 'Document' -Desc 'Resposta de cada etapa verificada' -Width $w -Height 330
        $sumLbl = New-TILabel -Text 'Nenhum teste feito ainda. Use Testar conexão.' -Size 9.5 -Bold -Color $global:Pal.TextDim
        $sumLbl.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
        $b4.Controls.Add($sumLbl)
        $global:Rede.SummaryLabel = $sumLbl

        $gridR = New-TIGrid -Parent $b4 -Headers @('Teste', 'Endereço', 'Resultado', 'Tempo', 'Detalhe') `
                            -Widths @(230, 170, 100, 90, 300) -EmptyText 'Clique em Testar conexão para ver cada etapa aqui.'
        $gridR.Tag = 'tistretch'
        $gridR.Height = 218
        $global:Rede.GridResults = $gridR
    }
}

Register-TIWorkspace @wsRede
