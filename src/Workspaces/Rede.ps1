# =====================================================================
# ÁREA: REDE - adaptadores, Wi-Fi, diagnóstico e reparo
# =====================================================================

$global:Rede = @{
    GridAdapters = $null
    GridResults  = $null
    WifiBody     = $null
    WifiInfo     = $null
    WifiRows     = @()    # controles das linhas lidas (trocados a cada leitura)
    WifiTail     = @()    # controles que ficam depois das linhas
    WifiProfiles = @()    # redes salvas (para "Esquecer rede")
    WifiCurrent  = ''
    ForgetMenu   = $null
    SummaryLabel = $null
    RepairBtn    = $null
    RepairInfo   = $null
    RepairName   = ''
    WatchTimer   = $null
    Adapters     = @()
}

$global:RedeAdminMsg = 'Esta ação precisa do TI Suite aberto como administrador: clique no selo "Sem elevação" na barra lateral.'

# Estado do adaptador em português (o Windows devolve o texto em inglês)
function ConvertTo-RedeStatus {
    param([string]$Status)
    switch ($Status) {
        'Up'               { return 'Conectado' }
        'Disconnected'     { return 'Desconectado' }
        'Disabled'         { return 'Desativado' }
        'Not Present'      { return 'Ausente' }
        'NotPresent'       { return 'Ausente' }
        'Down'             { return 'Sem sinal' }
        'Lower Layer Down' { return 'Sem sinal' }
        'Dormant'          { return 'Em espera' }
        'Testing'          { return 'Em teste' }
        'Unknown'          { return 'Desconhecido' }
    }
    if ($Status) { return $Status }
    return '-'
}

function Get-RedeSelected {
    $grid = $global:Rede.GridAdapters
    if (-not $grid -or $grid.SelectedRows.Count -eq 0) { return $null }
    return $grid.SelectedRows[0].Tag
}

# Botão da lista: "Ativar adaptador" quando a placa está desativada
function Update-RedeSelection {
    $btn = $global:Rede.RepairBtn
    if (-not $btn -or $btn.IsDisposed) { return }
    $sel = Get-RedeSelected
    $btn.Enabled = (-not $global:TI.Busy -and $null -ne $sel)
    $info = $global:Rede.RepairInfo
    if ($sel -and $sel.Status -eq 'Disabled') {
        $btn.Text = 'Ativar adaptador'
        $btn.AccessibleName = $btn.Text
        $btn.Style = 'Primary'
        $btn.Glyph = Get-TIGlyph 'Power'
        if ($info) { $info.Text = ('{0} está desativado: ative para voltar a usar a rede.' -f $sel.Name) }
    } else {
        $btn.Text = 'Reiniciar adaptador'
        $btn.AccessibleName = $btn.Text
        $btn.Style = 'Danger'
        $btn.Glyph = Get-TIGlyph 'Undo'
        if ($info) {
            $info.Text = $(if ($sel) { 'Selecionado: {0}' -f $sel.Name } else { 'Selecione um adaptador para reiniciá-lo (desativar e ativar).' })
        }
    }
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
            $grid.SuspendLayout()
            $grid.Rows.Clear()
            $rank = @{ 'Up' = 0; 'Disconnected' = 1; 'Disabled' = 2 }
            foreach ($a in $rows) {
                $ipTxt = $(if ($a.Ip) { $a.Ip } else { '-' })
                if ($a.Apipa) { $ipTxt += ' (sem DHCP)' } elseif ($a.Conflict) { $ipTxt += ' (em conflito)' }
                $gwTxt = $(if ($a.Gateway) { $a.Gateway } elseif ($a.NoGateway) { 'Nenhum' } else { '-' })
                $st = [string]$a.Status
                $row = Add-TIRow -Grid $grid -Cells @(
                    $a.Name, (ConvertTo-RedeStatus $st), $ipTxt, $gwTxt,
                    $(if ($a.Dns) { $a.Dns } else { '-' }),
                    $(if ($a.Speed) { $a.Speed } else { '-' }),
                    $(if ($a.Mac) { $a.Mac } else { '-' }),
                    $(if ($a.Desc) { $a.Desc } else { '-' })
                ) -Tag $a -SortKeys @($null, $(if ($rank.ContainsKey($st)) { $rank[$st] } else { 3 }), $null, $null, $null, [double]$a.SpeedBps, $null, $null)
                $row.Cells[1].Style.ForeColor = $(if ($st -eq 'Up') { $global:Pal.Success } elseif ($st -eq 'Disabled') { $global:Pal.Warning } else { $global:Pal.TextDim })
                if ($a.Apipa -or $a.Conflict) { $row.Cells[2].Style.ForeColor = $global:Pal.Danger }
                if ($a.NoGateway) { $row.Cells[3].Style.ForeColor = $global:Pal.Warning }
            }
            Clear-TIGridSelection $grid
            $grid.ResumeLayout()
            Set-TIGridEmptyText $grid $(if ($rows.Count -eq 0) { 'Nenhum adaptador encontrado (veja o console).' } else { '' })
        }
        # Depois de um reinício interrompido: avisa se a placa ficou desativada
        $name = $global:Rede.RepairName
        $global:Rede.RepairName = ''
        if ($name) {
            $a = @($rows | Where-Object { $_.Name -eq $name }) | Select-Object -First 1
            if ($a -and $a.Status -eq 'Disabled') {
                Show-TIToast -Text ('{0} ficou desativado: selecione na lista e use Ativar adaptador.' -f $name) -Type 'Warn' -Duration 6000
            }
        }
        Update-RedeSelection
    })
}

# O pump não chama o OnComplete quando o operador cancela a tarefa: sem esta
# vigia, a lista ficaria com o estado antigo (ex.: placa desativada no meio).
function Start-RedeRefreshWatch {
    Stop-RedeRefreshWatch
    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = 600
    $t.Add_Tick({
        if ($global:TI.Busy) { return }
        Stop-RedeRefreshWatch
        Refresh-RedeAdapters
    })
    $global:Rede.WatchTimer = $t
    $t.Start()
}

function Stop-RedeRefreshWatch {
    $t = $global:Rede.WatchTimer
    $global:Rede.WatchTimer = $null
    if ($t) { try { $t.Stop(); $t.Dispose() } catch { } }
}

function Invoke-RedeRepair {
    if ($global:TI.Busy) { return }
    $sel = Get-RedeSelected
    if (-not $sel) { Show-TIToast -Text 'Selecione um adaptador na lista.' -Type 'Warn'; return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text $global:RedeAdminMsg -Type 'Error'; return }
    $name = $sel.Name
    $enableOnly = ($sel.Status -eq 'Disabled')
    if (-not $enableOnly) {
        $res = Show-TIConfirm -Title 'Reiniciar adaptador' -Style 'Danger' -Icon 'Warning' `
                -Message ("O adaptador '{0}' será desativado e ativado de novo. A conexão cai por alguns segundos." -f $name) `
                -ConfirmText 'Reiniciar agora'
        if (-not $res) { return }
    }
    $title = $(if ($enableOnly) { 'Ativação do adaptador ' + $name } else { 'Reinício do adaptador ' + $name })
    $started = @(Invoke-TIAsync -Name $title -RequiresAdmin -Context @{ Name = $name; EnableOnly = $enableOnly } -Script {
        Repair-TIAdapter -Name $Context.Name -EnableOnly:([bool]$Context.EnableOnly)
    } -OnComplete { param($r) Stop-RedeRefreshWatch; Refresh-RedeAdapters })
    if ($started.Count -gt 0 -and $started[-1] -eq $true) {
        $global:Rede.RepairName = $name
        Start-RedeRefreshWatch
    }
}

# --- Wi-Fi ---------------------------------------------------------------------
function Show-RedeWifiRows {
    param($Rows)
    $body = $global:Rede.WifiBody
    if (-not $body -or $body.IsDisposed) { return }
    $body.SuspendLayout()
    foreach ($c in @($global:Rede.WifiRows)) {
        if ($c -and -not $c.IsDisposed) { $body.Controls.Remove($c); $c.Dispose() }
    }
    $added = New-Object System.Collections.ArrayList
    $iw = Get-TIInnerWidth $body
    foreach ($row in @($Rows)) {
        if ($row.PSObject.Properties['Note'] -and $row.Note) {
            # Aviso (Localização, serviço parado): parágrafo que quebra linha
            $h = New-TIHint -Parent $body -Text ([string]$row.Value) -Color (Get-TIToneColor $row.Tone) -TopGap 2 -BottomGap 8
            [void]$added.Add($h)
        } else {
            $rr = New-TIRow -Label $row.Label -Width $iw -LabelWidth 124
            Set-TIRowValue $rr $row.Value $row.Tone
            $body.Controls.Add($rr.Panel)
            [void]$added.Add($rr.Panel)
        }
    }
    # Faixa de perfis e dica continuam depois das linhas
    foreach ($t in @($global:Rede.WifiTail)) {
        if ($t -and -not $t.IsDisposed) { $body.Controls.SetChildIndex($t, $body.Controls.Count - 1) }
    }
    $global:Rede.WifiRows = @($added)
    $body.ResumeLayout()
}

function Invoke-RedeWifi {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Leitura do Wi-Fi' -Quiet -Script {
        Get-TIWifiInfo
    } -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Label'] })
        $global:Rede.WifiProfiles = @($r | Where-Object { $_ -and $_.PSObject.Properties['Profile'] } | ForEach-Object { [string]$_.Profile })
        $cur = @($rows | Where-Object { $_.Label -eq 'Perfil salvo' }) | Select-Object -First 1
        if (-not $cur) { $cur = @($rows | Where-Object { $_.Label -eq 'Rede (SSID)' }) | Select-Object -First 1 }
        $global:Rede.WifiCurrent = $(if ($cur) { [string]$cur.Value } else { '' })
        Show-RedeWifiRows $rows
        if ($global:Rede.WifiInfo) {
            $n = @($global:Rede.WifiProfiles).Count
            $global:Rede.WifiInfo.Text = ('Lido às {0}. {1}' -f (Get-Date -Format 'HH:mm'), $(if ($n -eq 1) { '1 rede salva.' } else { '{0} redes salvas.' -f $n }))
        }
    })
}

# "Esquecer rede": menu com as redes salvas (lidas em Verificar sinal)
function Show-RedeForgetMenu {
    param($Button)
    if ($global:TI.Busy) { return }
    $names = @($global:Rede.WifiProfiles | Where-Object { $_ })
    if ($names.Count -eq 0) {
        Show-TIToast -Text 'Nenhuma rede salva na lista: use Verificar sinal para ler as redes deste computador.' -Type 'Warn'
        return
    }
    if ($global:Rede.ForgetMenu) { try { $global:Rede.ForgetMenu.Dispose() } catch { } }
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.ShowImageMargin = $false
    $menu.Renderer = New-Object TISuite.DarkMenuRenderer
    $menu.BackColor = $global:Pal.CardAlt
    $menu.ForeColor = $global:Pal.TextMain
    $menu.Font = New-TIFont 9
    foreach ($n in $names) {
        $txt = $n
        if ($n -eq $global:Rede.WifiCurrent) { $txt += '   (conectada agora)' }
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($txt)
        $mi.ForeColor = $global:Pal.TextMain
        $mi.Tag = $n
        $mi.Add_Click({ Invoke-RedeForget -Name ([string]$this.Tag) })
        [void]$menu.Items.Add($mi)
    }
    $global:Rede.ForgetMenu = $menu
    $menu.Show($Button, (New-Object System.Drawing.Point(0, $Button.Height)))
}

function Invoke-RedeForget {
    param([string]$Name)
    if ($global:TI.Busy -or -not $Name) { return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text $global:RedeAdminMsg -Type 'Error'; return }
    $extra = $(if ($Name -eq $global:Rede.WifiCurrent) { "`n`nEste computador está conectado nela agora: a conexão cai." } else { '' })
    $ok = Show-TIConfirm -Title 'Esquecer rede Wi-Fi' -Style 'Danger' -Icon 'Warning' `
            -Message ("A rede ""{0}"" e a senha salva serão apagadas deste computador, para todos os usuários. Para conectar de novo, será preciso digitar a senha.{1}" -f $Name, $extra) `
            -ConfirmText 'Esquecer rede'
    if (-not $ok) { return }
    [void](Invoke-TIAsync -Name ('Esquecer a rede Wi-Fi ' + $Name) -RequiresAdmin -Context @{ Name = $Name } -Script {
        Remove-TIWifiProfile -Name $Context.Name
    } -OnComplete { param($r) Invoke-RedeWifi })
}

# Perfis .xml na pasta "wifi" ao lado do app (configura notebooks sem digitar senha)
function Invoke-RedeWifiImport {
    if ($global:TI.Busy) { return }
    $dir = Join-Path $global:TIRoot 'wifi'
    $files = @()
    if (Test-Path -LiteralPath $dir) { $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File -ErrorAction SilentlyContinue | Sort-Object Name) }
    if ($files.Count -eq 0) {
        [void](Show-TIMessage -Title 'Importar redes Wi-Fi' -Icon 'Info' `
            -Message ("Nenhum arquivo .xml na pasta:`n{0}`n`nCrie a pasta ""wifi"" ao lado do TI Suite e coloque nela os perfis de rede exportados de um computador já configurado. Cada arquivo vira uma rede salva para todos os usuários." -f $dir))
        return
    }
    if (-not $global:TI.Elevated) { Show-TIToast -Text $global:RedeAdminMsg -Type 'Error'; return }
    $names = (@($files | Select-Object -First 8 | ForEach-Object { $_.BaseName }) -join ', ')
    if ($files.Count -gt 8) { $names += ', ...' }
    $ok = Show-TIConfirm -Title 'Importar redes Wi-Fi' -Style 'Primary' -Icon 'Wifi' `
            -Message ("Importar {0} rede(s) da pasta wifi para todos os usuários deste computador?`n`n{1}`n`nO computador passa a conectar sozinho nessas redes." -f $files.Count, $names) `
            -ConfirmText 'Importar'
    if (-not $ok) { return }
    [void](Invoke-TIAsync -Name 'Importação de redes Wi-Fi' -RequiresAdmin -Context @{ Folder = $dir } -Script {
        Import-TIWifiProfiles -Folder $Context.Folder
    } -OnComplete { param($r) Invoke-RedeWifi })
}

# --- Diagnóstico ---------------------------------------------------------------
function Invoke-RedeTest {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Teste de conexão' -Quiet -Script {
        Test-TINetwork
    } -OnComplete {
        param($r)
        $rows = @($r | Where-Object { $_ -and $_.PSObject.Properties['Target'] })
        $verdict = @($r | Where-Object { $_ -and $_.PSObject.Properties['Verdict'] }) | Select-Object -First 1
        $grid = $global:Rede.GridResults
        if ($grid) {
            $grid.Rows.Clear()
            foreach ($t in $rows) {
                $row = Add-TIRow -Grid $grid -Cells @(
                    $t.Target, $t.Addr,
                    $(if ($t.Ok) { 'OK' } else { 'Falha' }),
                    $(if ($t.Latency -ge 0) { '{0} ms' -f $t.Latency } else { '-' }),
                    $t.Detail
                ) -Tag $t -SortKeys @($null, $null, $(if ($t.Ok) { 0 } else { 1 }), $(if ($t.Latency -ge 0) { [double]$t.Latency } else { [double]::MaxValue }), $null)
                $row.Cells[2].Style.ForeColor = $(if ($t.Ok) { $global:Pal.Success } else { $global:Pal.Danger })
            }
            Clear-TIGridSelection $grid
        }
        $l = $global:Rede.SummaryLabel
        if ($l -and -not $l.IsDisposed) {
            $up = @($rows | Where-Object { $_.Ok }).Count
            if ($rows.Count -eq 0) {
                $l.Text = 'O teste não chegou ao fim (veja o console).'
                $l.ForeColor = $global:Pal.Danger
            } else {
                $txt = $(if ($verdict) { [string]$verdict.Verdict } elseif ($up -eq $rows.Count) { 'Tudo certo.' } else { 'Há falhas: veja o detalhe de cada etapa.' })
                $l.Text = ('{0}  ({1} de {2} etapas OK)' -f $txt, $up, $rows.Count)
                $tone = $(if ($verdict) { [string]$verdict.Tone } elseif ($up -eq $rows.Count) { 'ok' } elseif ($up -eq 0) { 'crit' } else { 'warn' })
                $l.ForeColor = Get-TIToneColor $tone
            }
        }
    })
}

function Invoke-RedeFlushDns {
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Limpeza do cache de DNS' -Script { Clear-TIDnsCache })
}

function Invoke-RedeRenew {
    if ($global:TI.Busy) { return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text $global:RedeAdminMsg -Type 'Error'; return }
    $res = Show-TIConfirm -Title 'Renovar o endereço IP' -Style 'Danger' -Icon 'Warning' `
            -Message 'Roda ipconfig /release e /renew em todas as placas. A conexão cai por alguns segundos (até 1 minuto se o servidor DHCP demorar).' `
            -ConfirmText 'Renovar IP'
    if (-not $res) { return }
    [void](Invoke-TIAsync -Name 'Renovação do endereço IP' -RequiresAdmin -Script {
        Reset-TINetwork
    } -OnComplete {
        param($r)
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Reason'] }) | Select-Object -First 1
        if ($res) {
            switch ([string]$res.Reason) {
                'apipa' { Show-TIToast -Text 'O servidor DHCP não respondeu: a placa ficou com IP automático (169.254).' -Type 'Error' -Duration 6000 }
                'noip'  { Show-TIToast -Text 'Nenhuma placa recebeu endereço: confira o cabo ou o Wi-Fi.' -Type 'Error' -Duration 6000 }
                'nogw'  { Show-TIToast -Text ('Novo IP {0}, mas sem gateway: não há rota para a internet.' -f $res.Ip) -Type 'Warn' -Duration 6000 }
                default { Show-TIToast -Text ('Novo endereço: {0} ({1}).' -f $res.Ip, $res.Adapter) -Type 'Success' }
            }
        }
        Refresh-RedeAdapters
    })
}

function Invoke-RedeStackReset {
    if ($global:TI.Busy) { return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text $global:RedeAdminMsg -Type 'Error'; return }
    $res = Show-TIConfirm -Title 'Redefinir a pilha de rede' -Style 'Danger' -Icon 'Warning' `
            -Message ("Roda netsh winsock reset e netsh int ip reset. Resolve ""conectado, sem internet"" depois de vírus, VPN ou proxy quebrado.`n`nO computador PRECISA ser reiniciado depois. IP fixo configurado à mão volta para automático (DHCP): anote antes, se houver.") `
            -ConfirmText 'Redefinir'
    if (-not $res) { return }
    [void](Invoke-TIAsync -Name 'Redefinição da pilha de rede' -RequiresAdmin -Script {
        Reset-TINetStack
    } -OnComplete {
        param($r)
        [void](Show-TIMessage -Title 'Reinicie o computador' -Icon 'Warning' `
            -Message 'A redefinição da rede só vale depois de reiniciar o Windows. Salve o que estiver aberto e reinicie assim que puder.')
        Refresh-RedeAdapters
    })
}

$wsRede = @{
    Id       = 'rede'
    Title    = 'Rede'
    Sub      = 'Adaptadores, Wi-Fi, teste de conexão e reparo'
    Icon     = 'Globe'
    Keywords = 'rede internet wifi wi-fi adaptador ip dns ping proxy conexao mac winsock dhcp'

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
        $b1 = New-TICard -Parent $flow -Title 'Adaptadores de rede' -Stretch -Icon 'Ethernet' -Desc 'Placas físicas e virtuais deste computador (botão direito copia o MAC)' -Width $w -Height 370
        $bar = New-TIButtonBar -Parent $b1
        $btnRepair = New-TIButton -Text 'Reiniciar adaptador' -Style 'Danger' -Width 186 -Height 36 -Icon 'Undo'
        $btnRepair.Enabled = $false
        $btnRepair.Add_Click({ Invoke-RedeRepair })
        $bar.Controls.Add($btnRepair)
        $global:Rede.RepairBtn = $btnRepair
        $global:Rede.RepairInfo = Add-TIBarLabel -Bar $bar -Text 'Selecione um adaptador para reiniciá-lo (desativar e ativar).'

        $gridA = New-TIGrid -Parent $b1 -Headers @('Adaptador', 'Estado', 'IPv4', 'Gateway', 'DNS', 'Velocidade', 'MAC', 'Placa') `
                            -Widths @(150, 100, 140, 120, 150, 90, 140, 200) -EmptyText 'Carregando os adaptadores...'
        $gridA.Tag = 'tistretch'
        $gridA.Height = 246
        $gridA.Add_SelectionChanged({ Update-RedeSelection })
        # Menu do botão direito: "Copiar o MAC" antes das opções padrão da tabela
        $miMac = New-Object System.Windows.Forms.ToolStripMenuItem('Copiar o MAC')
        $miMac.ForeColor = $global:Pal.TextMain
        $miMac.Add_Click({
            $sel = Get-RedeSelected
            if ($sel -and $sel.Mac) {
                try {
                    [System.Windows.Forms.Clipboard]::SetText([string]$sel.Mac)
                    Show-TIToast -Text ('MAC copiado: {0}' -f $sel.Mac) -Type 'Success'
                } catch { Show-TIToast -Text 'Não foi possível usar a área de transferência.' -Type 'Error' }
            }
        })
        if ($gridA.ContextMenuStrip) {
            $gridA.ContextMenuStrip.Items.Insert(0, $miMac)
            $gridA.ContextMenuStrip.Items.Insert(1, (New-Object System.Windows.Forms.ToolStripSeparator))
            $gridA.ContextMenuStrip.Add_Opening({
                $sel = Get-RedeSelected
                $this.Items[0].Enabled = ($null -ne $sel -and [bool]$sel.Mac)
            })
        }
        $global:Rede.GridAdapters = $gridA

        # --- Wi-Fi ---------------------------------------------------------
        $b2 = New-TICard -Parent $flow -Title 'Wi-Fi' -Icon 'Wifi' -Desc 'Sinal, ponto de acesso e redes salvas' -Half -Height 340
        $wBar = New-TIButtonBar -Parent $b2
        $btnWifi = New-TIButton -Text 'Verificar sinal' -Style 'Outline' -Width 160 -Height 36 -Icon 'Signal'
        $btnWifi.Add_Click({ Invoke-RedeWifi })
        $wBar.Controls.Add($btnWifi)
        $global:Rede.WifiInfo = Add-TIBarLabel -Bar $wBar -Text 'Ainda não lido.'
        $global:Rede.WifiBody = $b2

        $pBar = New-TIButtonBar -Parent $b2
        $pBar.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 4)
        $btnImport = New-TIButton -Text 'Importar da pasta wifi' -Style 'Soft' -Width 180 -Height 36 -Icon 'Download' `
                      -Tip 'Adiciona as redes dos arquivos .xml da pasta "wifi" ao lado do TI Suite'
        $btnImport.Add_Click({ Invoke-RedeWifiImport })
        $pBar.Controls.Add($btnImport)
        $btnForget = New-TIButton -Text 'Esquecer rede...' -Style 'Outline' -Width 150 -Height 36 -Icon 'Remove' `
                      -Tip 'Apaga uma rede salva e a senha (útil quando a senha mudou)'
        $btnForget.Add_Click({ Show-RedeForgetMenu -Button $this })
        $pBar.Controls.Add($btnForget)
        $wHint = New-TIHint -Parent $b2 -Text 'Esquecer rede resolve senha antiga salva no notebook. Importar usa os perfis .xml da pasta "wifi" ao lado do TI Suite e vale para todos os usuários.' -TopGap 0
        $global:Rede.WifiTail = @($pBar, $wHint)

        # --- Diagnóstico ---------------------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Diagnóstico' -Icon 'Diagnostic' -Desc 'Testes e correções de conexão' -Half -Height 340
        $btnTest = New-TIButton -Text 'Testar conexão' -Style 'Primary' -Width 250 -Height 40 -Icon 'Check'
        $btnTest.Add_Click({ Invoke-RedeTest })
        $b3.Controls.Add($btnTest)
        $btnDns = New-TIButton -Text 'Limpar cache de DNS' -Style 'Soft' -Width 250 -Height 40 -Icon 'Erase'
        $btnDns.Add_Click({ Invoke-RedeFlushDns })
        $b3.Controls.Add($btnDns)
        $btnRenew = New-TIButton -Text 'Renovar endereço IP' -Style 'Outline' -Width 250 -Height 40 -Icon 'Sync'
        $btnRenew.Add_Click({ Invoke-RedeRenew })
        $b3.Controls.Add($btnRenew)
        $btnStack = New-TIButton -Text 'Redefinir pilha de rede' -Style 'Outline' -Width 250 -Height 40 -Icon 'Repair' `
                     -Tip 'netsh winsock reset e netsh int ip reset (exige reiniciar o PC)'
        $btnStack.Add_Click({ Invoke-RedeStackReset })
        $b3.Controls.Add($btnStack)
        $null = New-TIHint -Parent $b3 -Text 'O teste confere o roteador, servidores públicos, cada servidor DNS da placa e o acesso à internet (detecta portal de login e proxy). Redefinir a pilha de rede exige reiniciar o PC.' -TopGap 4

        # --- Resultados ----------------------------------------------------
        $b4 = New-TICard -Parent $flow -Title 'Resultado do teste' -Stretch -Icon 'Document' -Desc 'Conclusão e resposta de cada etapa verificada' -Width $w -Height 330
        $sumLbl = New-TIHint -Parent $b4 -Text 'Nenhum teste feito ainda. Use Testar conexão.' -Size 9.5 -Color $global:Pal.TextDim -TopGap 0 -BottomGap 8
        $sumLbl.Font = New-TIFont 9.5 Bold
        $global:Rede.SummaryLabel = $sumLbl

        $gridR = New-TIGrid -Parent $b4 -Headers @('Teste', 'Endereço', 'Resultado', 'Tempo', 'Detalhe') `
                            -Widths @(210, 150, 90, 80, 340) -EmptyText 'Clique em Testar conexão para ver cada etapa aqui.'
        $gridR.Tag = 'tistretch'
        $gridR.Height = 218
        $global:Rede.GridResults = $gridR
    }
}

Register-TIWorkspace @wsRede
