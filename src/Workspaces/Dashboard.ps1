# =====================================================================
# ÁREA: INÍCIO - visão geral do equipamento
# =====================================================================

$global:Dashboard = @{
    Data     = $null
    LastRun  = $null
    Controls = @{}
}

function Set-DashboardValue {
    param([string]$Key, [string]$Value, [string]$Tone = '')
    $c = $global:Dashboard.Controls[$Key]
    if ($c -and -not $c.IsDisposed) {
        $c.Text = $(if ([string]::IsNullOrEmpty($Value)) { '-' } else { $Value })
        $c.ForeColor = Get-TIToneColor $Tone
    }
}

function Set-DashboardBar {
    param([string]$Key, [int]$Percent, $Color = $null)
    $c = $global:Dashboard.Controls[$Key]
    if ($c -and -not $c.IsDisposed) {
        $c.FillColor = $(if ($Color) { $Color } else { [System.Drawing.Color]::Empty })
        $c.Percent = [Math]::Max(0, [Math]::Min(100, $Percent))
    }
}

function Update-DashboardUI {
    param($Data)
    if (-not $Data) { return }
    $global:Dashboard.Data = $Data

    # Disco: a barra mostra o espaço LIVRE; fica amarela/vermelha quando falta espaço
    $pct = [int]$Data.DiskFreePct
    Set-DashboardValue 'disk' ('{0} livres de {1} ({2}%)' -f (Format-TIBytes $Data.DiskFree), (Format-TIBytes $Data.DiskTotal), $pct)
    if ($pct -lt 10) {
        Set-DashboardBar 'diskBar' $pct $global:Pal.Danger
        Set-DashboardValue 'diskHint' 'Pouco espaço: rode a Limpeza profunda em Manutenção.' 'crit'
    } elseif ($pct -lt 20) {
        Set-DashboardBar 'diskBar' $pct $global:Pal.Warning
        Set-DashboardValue 'diskHint' 'O espaço está ficando curto: vale uma limpeza.' 'warn'
    } else {
        Set-DashboardBar 'diskBar' $pct $null
        Set-DashboardValue 'diskHint' 'Espaço suficiente no disco do sistema.' 'muted'
    }

    if ($Data.MemTotal -gt 0) {
        $memFree = $Data.MemTotal - $Data.MemUsed
        $mp = [int](100 * $memFree / $Data.MemTotal)
        Set-DashboardValue 'mem' ('{0} livres de {1} ({2}%)' -f (Format-TIBytes $memFree), (Format-TIBytes $Data.MemTotal), $mp)
        if ($mp -lt 10) {
            Set-DashboardBar 'memBar' $mp $global:Pal.Warning
            Set-DashboardValue 'memHint' 'Pouca memória livre: feche programas pesados ou reinicie.' 'warn'
        } else {
            Set-DashboardBar 'memBar' $mp $null
            Set-DashboardValue 'memHint' 'Memória livre agora, em relação ao total instalado.' 'muted'
        }
    }

    Set-DashboardValue 'model'    $Data.Model
    Set-DashboardValue 'serial'   $Data.Serial
    Set-DashboardValue 'os'       ('{0} (build {1})' -f $Data.OsName, $Data.OsBuild)
    Set-DashboardValue 'cpu'      $Data.Cpu
    Set-DashboardValue 'operator' $(if ($Data.Domain -and $Data.Domain -ne '-') { '{0} ({1})' -f $Data.User, $Data.Domain } else { $Data.User })
    Set-DashboardValue 'uptime'   (Format-TIDuration $Data.Uptime)
    if ($Data.Adapter) { Set-DashboardValue 'adapter' $Data.Adapter } else { Set-DashboardValue 'adapter' 'Nenhum adaptador conectado' 'warn' }
    Set-DashboardValue 'ip'       $Data.Ip
    Set-DashboardValue 'gateway'  $Data.Gateway
}

function Refresh-Dashboard {
    param([switch]$Force)
    if ($global:TI.Busy) { return }
    if (-not $Force -and $global:Dashboard.LastRun -and
        ((Get-Date) - $global:Dashboard.LastRun).TotalSeconds -lt 20) { return }
    $global:Dashboard.LastRun = Get-Date
    [void](Invoke-TIAsync -Name 'Leitura dos dados do sistema' -Quiet -Script {
        Get-TISystemSnapshot
    } -OnComplete {
        param($r)
        Update-DashboardUI -Data (@($r | Where-Object { $_ -and $_.PSObject.Properties['Computer'] }) | Select-Object -First 1)
    })
}

function Export-TIReport {
    $data = $global:Dashboard.Data
    if (-not $data) {
        Show-TIToast -Text 'Espere os dados carregarem e tente de novo.' -Type 'Warn'
        return
    }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = 'Exportar relatório do equipamento'
    $dlg.Filter = 'Texto (*.txt)|*.txt|Todos os arquivos (*.*)|*.*'
    $dlg.FileName = ('Relatorio-{0}-{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm'))
    if ($dlg.ShowDialog() -ne 'OK') { $dlg.Dispose(); return }

    $lines = @(
        '====================================================================='
        ' TI Suite - relatório do equipamento'
        '====================================================================='
        (' Data         : {0}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'))
        (' Computador   : {0}' -f $data.Computer)
        (' Modelo       : {0}' -f $data.Model)
        (' Nº de série  : {0}' -f $data.Serial)
        (' Sistema      : {0} (build {1})' -f $data.OsName, $data.OsBuild)
        (' Processador  : {0}' -f $data.Cpu)
        (' Usuário      : {0} ({1})' -f $data.User, $data.Domain)
        (' Ligado há    : {0}' -f (Format-TIDuration $data.Uptime))
        (' Disco        : {0} livres de {1} ({2}%)' -f (Format-TIBytes $data.DiskFree), (Format-TIBytes $data.DiskTotal), $data.DiskFreePct)
        (' Memória      : {0} em uso de {1}' -f (Format-TIBytes $data.MemUsed), (Format-TIBytes $data.MemTotal))
        (' Adaptador    : {0}' -f $data.Adapter)
        (' IPv4         : {0}' -f $data.Ip)
        (' Gateway      : {0}' -f $data.Gateway)
        (' Elevação     : {0}' -f $(if ($global:TI.Elevated) { 'administrador' } else { 'sem elevação' }))
        (' Versão       : TI Suite v{0}' -f $global:TI.Version)
        '====================================================================='
    )
    try {
        [System.IO.File]::WriteAllLines($dlg.FileName, $lines, (New-Object System.Text.UTF8Encoding($true)))
        Write-TILog -Level 'Success' -Message ('Relatório exportado: {0}' -f $dlg.FileName)
        Show-TIToast -Text 'Relatório exportado.' -Type 'Success'
    } catch {
        Write-TILog -Level 'Error' -Message ('Falha ao exportar o relatório: {0}' -f $_.Exception.Message)
        Show-TIToast -Text 'Não foi possível salvar o relatório.' -Type 'Error'
    }
    $dlg.Dispose()
}

$wsDashboard = @{
    Id       = 'dashboard'
    Title    = 'Início'
    Sub      = 'Visão geral do equipamento e atalhos para as tarefas do dia a dia'
    Icon     = 'Home'
    Keywords = 'inicio painel resumo relatorio disco memoria'

    OnActivate = { Refresh-Dashboard }
    Refresh    = { Refresh-Dashboard -Force }

    Actions = {
        param($Bar)
        $b1 = New-TIButton -Text 'Atualizar' -Style 'Outline' -Width 116 -Height 34 -Icon 'Refresh' -Tip 'Ler os dados de novo (Ctrl+R)'
        $b1.Add_Click({ Refresh-Dashboard -Force })
        $Bar.Controls.Add($b1)
        $b2 = New-TIButton -Text 'Exportar relatório' -Style 'Ghost' -Width 156 -Height 34 -Icon 'Export'
        $b2.Add_Click({ Export-TIReport })
        $Bar.Controls.Add($b2)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $w = $global:Theme.CardWidth
        $c = $global:Dashboard.Controls

        # --- Armazenamento -------------------------------------------------
        $b1 = New-TICard -Parent $flow -Title 'Armazenamento' -Desc 'Espaço livre no disco do sistema' -Icon 'Monitor' -Width $w -Height 160
        $diskLbl = New-TILabel -Text 'Lendo...' -Size 9.5 -Bold -Color $global:Pal.TextDim
        $diskLbl.AutoSize = $false
        $diskLbl.AutoEllipsis = $true
        $diskLbl.Height = 20
        $diskLbl.Tag = 'tirow'
        $diskLbl.Width = Get-TIInnerWidth $b1
        $b1.Controls.Add($diskLbl)
        $diskBar = New-Object TISuite.FlatProgress
        $diskBar.Percent = -1
        $diskBar.Height = 8
        $diskBar.Tag = 'tirow'
        $diskBar.Width = Get-TIInnerWidth $b1
        $diskBar.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 8)
        $b1.Controls.Add($diskBar)
        $c['diskHint'] = New-TIHint -Parent $b1 -Text ' ' -TopGap 0
        $c['disk'] = $diskLbl
        $c['diskBar'] = $diskBar

        # --- Memória -------------------------------------------------------
        $b2 = New-TICard -Parent $flow -Title 'Memória RAM' -Desc 'Uso atual da memória física' -Icon 'Package' -Width $w -Height 160
        $memLbl = New-TILabel -Text 'Lendo...' -Size 9.5 -Bold -Color $global:Pal.TextDim
        $memLbl.AutoSize = $false
        $memLbl.AutoEllipsis = $true
        $memLbl.Height = 20
        $memLbl.Tag = 'tirow'
        $memLbl.Width = Get-TIInnerWidth $b2
        $b2.Controls.Add($memLbl)
        $memBar = New-Object TISuite.FlatProgress
        $memBar.Percent = -1
        $memBar.Height = 8
        $memBar.Tag = 'tirow'
        $memBar.Width = Get-TIInnerWidth $b2
        $memBar.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 8)
        $b2.Controls.Add($memBar)
        $c['memHint'] = New-TIHint -Parent $b2 -Text ' ' -TopGap 0
        $c['mem'] = $memLbl
        $c['memBar'] = $memBar

        # --- Sistema -------------------------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Sistema' -Desc 'Identificação do equipamento' -Icon 'PC' -Width $w -Height 266
        $iw = Get-TIInnerWidth $b3
        foreach ($p in @(
            @{ K = 'model';    L = 'Modelo' },
            @{ K = 'serial';   L = 'Número de série' },
            @{ K = 'os';       L = 'Sistema' },
            @{ K = 'cpu';      L = 'Processador' },
            @{ K = 'operator'; L = 'Usuário' },
            @{ K = 'uptime';   L = 'Ligado há' }
        )) {
            $r = New-TIRow -Label $p.L -Width $iw
            $b3.Controls.Add($r.Panel)
            $c[$p.K] = $r.Value
        }

        # --- Rede ----------------------------------------------------------
        $b4 = New-TICard -Parent $flow -Title 'Rede' -Desc 'Conexão ativa deste computador' -Icon 'Ethernet' -Width $w -Height 266
        $iw = Get-TIInnerWidth $b4
        foreach ($p in @(
            @{ K = 'adapter'; L = 'Adaptador' },
            @{ K = 'ip';      L = 'IPv4' },
            @{ K = 'gateway'; L = 'Gateway' }
        )) {
            $r = New-TIRow -Label $p.L -Width $iw
            $b4.Controls.Add($r.Panel)
            $c[$p.K] = $r.Value
        }
        $netBtn = New-TIButton -Text 'Diagnóstico de rede' -Style 'Outline' -Width 186 -Height 36 -Icon 'Globe'
        $netBtn.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
        $netBtn.Add_Click({ Switch-TIWorkspace -Id 'rede' })
        $b4.Controls.Add($netBtn)

        # --- Ações rápidas ---------------------------------------------------
        $b5 = New-TICard -Parent $flow -Title 'Ações rápidas' -Desc 'Ir direto para as tarefas mais comuns' -Icon 'Power' -Width $w -Height 232
        $qa = New-TIButtonBar -Parent $b5
        foreach ($a in @(
            @{ T = 'Manutenção';  I = 'Clean';     S = 'Primary'; Go = 'limpeza' },
            @{ T = 'Saúde do PC'; I = 'Health';    S = 'Soft';    Go = 'saude' },
            @{ T = 'Programas';   I = 'Apps';      S = 'Soft';    Go = 'programas' },
            @{ T = 'Contas';      I = 'People';    S = 'Soft';    Go = 'contas' },
            @{ T = 'Inventário';  I = 'CheckList'; S = 'Soft';    Go = 'inventario' },
            @{ T = 'Relatório';   I = 'Export';    S = 'Outline'; Go = '' }
        )) {
            $btn = New-TIButton -Text $a.T -Style $a.S -Width 152 -Height 38 -Icon $a.I
            $go = $a.Go
            if ($go) { $btn.Add_Click({ Switch-TIWorkspace -Id $go }.GetNewClosure()) }
            else { $btn.Add_Click({ Export-TIReport }) }
            $qa.Controls.Add($btn)
        }

        # --- Atalhos -------------------------------------------------------
        $b6 = New-TICard -Parent $flow -Title 'Atalhos' -Desc 'Teclas para trabalhar mais rápido' -Icon 'Terminal' -Width $w -Height 232
        $iw = Get-TIInnerWidth $b6
        foreach ($k in @(
            @{ K = 'Ctrl + 1 a 7';   V = 'Trocar de área' },
            @{ K = 'Ctrl + R ou F5'; V = 'Atualizar a área aberta' },
            @{ K = 'Ctrl + F';       V = 'Buscar ferramenta' },
            @{ K = 'Ctrl + L';       V = 'Limpar o console' },
            @{ K = 'F12';            V = 'Mostrar ou ocultar o console' }
        )) {
            $rr = New-TIRow -Label $k.K -Value $k.V -Width $iw -LabelWidth 116
            $rr.Label.ForeColor = $global:Pal.TextMain
            $rr.Label.Font = New-TIFont 8.5 Bold
            $rr.Value.ForeColor = $global:Pal.TextMuted
            $rr.Value.Font = New-TIFont 8.5
            $b6.Controls.Add($rr.Panel)
        }
    }
}

Register-TIWorkspace @wsDashboard
