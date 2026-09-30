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

# Texto de apoio que some quando vazio
function Set-DashboardNote {
    param([string]$Key, [string]$Text, [string]$Tone = 'muted')
    $c = $global:Dashboard.Controls[$Key]
    if (-not $c -or $c.IsDisposed) { return }
    if ([string]::IsNullOrWhiteSpace($Text)) { $c.Visible = $false; return }
    $c.Text = $Text
    $c.ForeColor = Get-TIToneColor $Tone
    $c.Visible = $true
}

# --- Textos montados a partir do snapshot (tela, resumo e relatório) --------
function Get-DashboardOsText {
    param($Data)
    $t = ('{0} {1}' -f $Data.OsName, $Data.OsVersion).Trim()
    if ($Data.OsBuild -and $Data.OsBuild -ne '-') { $t += (' (build {0})' -f $Data.OsBuild) }
    return $t
}

function Get-DashboardUserText {
    param($Data)
    if (-not $Data.User) { return '' }
    if ($Data.UserDomain) { return ('{0} ({1})' -f $Data.User, $Data.UserDomain) }
    return [string]$Data.User
}

function Get-DashboardDiskText {
    param($Letter, [double]$Free, [double]$Total, [string]$Label = '')
    if ($Total -le 0) { return '' }
    $name = [string]$Letter
    if ($Label) { $name += (' ({0})' -f $Label) }
    return ('{0} {1} livres de {2} ({3}%)' -f $name, (Format-TIBytes $Free), (Format-TIBytes $Total), [int](100 * $Free / $Total))
}

function Get-DashboardMemText {
    param($Data)
    if ($Data.MemTotal -le 0) { return '' }
    $t = ('{0} utilizáveis' -f (Format-TIBytes $Data.MemTotal))
    if ($Data.MemInstalled -gt 0) { $t += (' ({0} instalados)' -f (Format-TIBytes $Data.MemInstalled)) }
    return $t
}

# Pares rótulo/valor usados por "Copiar resumo" e pelo relatório
function Get-DashboardFacts {
    param($Data)
    $f = New-Object System.Collections.ArrayList
    $add = { param($k, $v) [void]$f.Add(@($k, $(if ([string]::IsNullOrWhiteSpace([string]$v)) { '-' } else { [string]$v }))) }
    & $add 'Computador' $(if ($Data.Domain) { '{0} ({1})' -f $Data.Computer, $Data.Domain } else { $Data.Computer })
    & $add 'Modelo' $Data.Model
    & $add 'Nº de série' $(if ($Data.Serial) { $Data.Serial } else { 'não gravado pelo fabricante' })
    if ($Data.AssetTag) { & $add 'Etiqueta (patrimônio)' $Data.AssetTag }
    & $add 'Windows' (Get-DashboardOsText $Data)
    & $add 'Processador' $Data.Cpu
    & $add 'Memória' (Get-DashboardMemText $Data)
    & $add 'Disco' (Get-DashboardDiskText -Letter $Data.DiskLetter -Free $Data.DiskFree -Total $Data.DiskTotal)
    foreach ($d in @($Data.OtherDisks | Where-Object { $_ })) {
        & $add 'Outra unidade' (Get-DashboardDiskText -Letter $d.Letter -Free $d.Free -Total $d.Total -Label $d.Label)
    }
    & $add 'Usuário conectado' $(if ($Data.User) { Get-DashboardUserText $Data } else { 'ninguém conectado' })
    & $add 'Adaptador' $(if ($Data.Adapter) { '{0} - {1}' -f $Data.Adapter, $Data.AdapterDesc } else { 'nenhum conectado' })
    & $add 'IPv4' $(if ($Data.Apipa) { '{0} (automático: o DHCP não respondeu)' -f $Data.Ip } else { $Data.Ip })
    & $add 'Gateway' $(if ($Data.Adapter -and $Data.NoGateway) { 'nenhum' } else { $Data.Gateway })
    & $add 'MAC' $Data.Mac
    return $f
}

function Update-DashboardUI {
    param($Data)
    if (-not $Data) {
        # Falha na leitura: se já havia dados, mantém; senão, sai do "Lendo..."
        if ($global:Dashboard.Data) {
            Show-TIToast -Text 'Não foi possível atualizar os dados do Início (veja o console).' -Type 'Warn'
            return
        }
        foreach ($k in @('disk', 'mem')) { Set-DashboardValue $k 'Não foi possível ler (veja o console)' 'warn' }
        foreach ($k in @('diskBar', 'memBar')) { Set-DashboardBar $k 0 $null }
        foreach ($k in @('diskHint', 'memHint')) { Set-DashboardValue $k 'Use Atualizar para tentar de novo.' 'muted' }
        foreach ($k in @('computer', 'model', 'serial', 'os', 'cpu', 'user', 'operator', 'uptime', 'adapter', 'ip', 'gateway', 'mac')) {
            Set-DashboardValue $k '-' 'dim'
        }
        foreach ($k in @('diskOther', 'uptimeHint', 'netHint')) { Set-DashboardNote $k '' }
        return
    }
    $global:Dashboard.Data = $Data

    # --- Disco: a barra mostra o espaço LIVRE; nível por GB e por percentual ---
    if ($Data.DiskTotal -le 0) {
        Set-DashboardValue 'disk' 'Não foi possível ler o disco do sistema' 'warn'
        Set-DashboardBar 'diskBar' 0 $null
        Set-DashboardValue 'diskHint' 'O Windows não informou o espaço livre. Use Atualizar; se continuar, veja a Saúde do PC.' 'muted'
    } else {
        $pct = [int]$Data.DiskFreePct
        Set-DashboardValue 'disk' (Get-DashboardDiskText -Letter $Data.DiskLetter -Free $Data.DiskFree -Total $Data.DiskTotal)
        switch ([string]$Data.DiskLevel) {
            'crit' {
                Set-DashboardBar 'diskBar' $pct $global:Pal.Danger
                Set-DashboardValue 'diskHint' 'Pouco espaço (menos de 10 GB livres): rode a Limpeza profunda em Manutenção.' 'crit'
            }
            'warn' {
                Set-DashboardBar 'diskBar' $pct $global:Pal.Warning
                Set-DashboardValue 'diskHint' 'O espaço está ficando curto: vale uma limpeza (o Windows Update precisa de uns 20 GB livres).' 'warn'
            }
            default {
                Set-DashboardBar 'diskBar' $pct $null
                Set-DashboardValue 'diskHint' 'Espaço suficiente no disco do sistema.' 'muted'
            }
        }
    }
    $others = @($Data.OtherDisks | Where-Object { $_ })
    if ($others.Count -gt 0) {
        $lines = @($others | ForEach-Object { Get-DashboardDiskText -Letter $_.Letter -Free $_.Free -Total $_.Total -Label $_.Label })
        $low = @($others | Where-Object { $_.Level -eq 'crit' }).Count -gt 0
        Set-DashboardNote 'diskOther' ("Outras unidades:`n" + ($lines -join "`n")) $(if ($low) { 'warn' } else { 'muted' })
    } else {
        Set-DashboardNote 'diskOther' ''
    }

    # --- Memória (livre, em relação à memória utilizável pelo Windows) ---------
    if ($Data.MemTotal -gt 0) {
        $memFree = $Data.MemTotal - $Data.MemUsed
        $mp = [int](100 * $memFree / $Data.MemTotal)
        Set-DashboardValue 'mem' ('{0} livres de {1} ({2}%)' -f (Format-TIBytes $memFree), (Format-TIBytes $Data.MemTotal), $mp)
        if ($mp -lt 10) {
            Set-DashboardBar 'memBar' $mp $global:Pal.Warning
            Set-DashboardValue 'memHint' 'Pouca memória livre: feche programas pesados ou reinicie.' 'warn'
        } else {
            Set-DashboardBar 'memBar' $mp $null
            $inst = ''
            if ($Data.MemInstalled -gt 0) { $inst = (' ({0} instalados)' -f (Format-TIBytes $Data.MemInstalled)) }
            Set-DashboardValue 'memHint' ('Em relação à memória utilizável pelo Windows{0}.' -f $inst) 'muted'
        }
    } else {
        Set-DashboardValue 'mem' 'Não foi possível ler a memória' 'warn'
        Set-DashboardBar 'memBar' 0 $null
        Set-DashboardValue 'memHint' 'O Windows não informou a memória. Use Atualizar para tentar de novo.' 'muted'
    }

    # --- Sistema ----------------------------------------------------------------
    Set-DashboardValue 'computer' $(if ($Data.Domain) { '{0} ({1})' -f $Data.Computer, $Data.Domain } else { $Data.Computer })
    Set-DashboardValue 'model' $Data.Model
    if ($Data.Serial) { Set-DashboardValue 'serial' $Data.Serial }
    else { Set-DashboardValue 'serial' 'Não gravado pelo fabricante' 'warn' }
    Set-DashboardValue 'os' (Get-DashboardOsText $Data)
    Set-DashboardValue 'cpu' $Data.Cpu
    if ($Data.User) { Set-DashboardValue 'user' (Get-DashboardUserText $Data) }
    else { Set-DashboardValue 'user' 'Ninguém conectado' 'dim' }
    Set-DashboardValue 'operator' ('{0} ({1})' -f $Data.Operator, $(if ($global:TI.Elevated) { 'administrador' } else { 'sem elevação' })) 'muted'
    $days = 0
    if ($Data.Uptime) { $days = $Data.Uptime.TotalDays }
    Set-DashboardValue 'uptime' (Format-TIDuration $Data.Uptime) $(if ($days -ge 7) { 'warn' } else { '' })
    if ($Data.FastStartup) {
        Set-DashboardNote 'uptimeHint' 'A Inicialização rápida está ligada: "Desligar" não zera o tempo ligado. Para limpar a memória e concluir atualizações, use Reiniciar.' $(if ($days -ge 7) { 'warn' } else { 'muted' })
    } elseif ($days -ge 7) {
        Set-DashboardNote 'uptimeHint' 'Ligado há mais de uma semana: reiniciar costuma resolver lentidão e conclui atualizações.' 'warn'
    } else {
        Set-DashboardNote 'uptimeHint' ''
    }

    # --- Rede: alerta de IP automático (169.254) e de falta de gateway ----------
    if ($Data.Adapter) {
        Set-DashboardValue 'adapter' $Data.Adapter
        if ($Data.Apipa) { Set-DashboardValue 'ip' ('{0} (automático)' -f $Data.Ip) 'crit' }
        elseif ($Data.IpConflict) { Set-DashboardValue 'ip' ('{0} (em conflito)' -f $Data.Ip) 'crit' }
        else { Set-DashboardValue 'ip' $Data.Ip }
        if ($Data.NoGateway) { Set-DashboardValue 'gateway' 'Nenhum' 'warn' } else { Set-DashboardValue 'gateway' $Data.Gateway }
        Set-DashboardValue 'mac' $Data.Mac
    } else {
        Set-DashboardValue 'adapter' 'Nenhum adaptador conectado' 'warn'
        foreach ($k in @('ip', 'gateway', 'mac')) { Set-DashboardValue $k '-' 'dim' }
    }
    if (-not $Data.Adapter) {
        Set-DashboardNote 'netHint' 'Nenhuma placa conectada: confira o cabo ou o Wi-Fi.' 'warn'
    } elseif ($Data.Apipa) {
        Set-DashboardNote 'netHint' 'O servidor DHCP não respondeu (IP automático 169.254): confira o cabo, o Wi-Fi e o switch; depois use Renovar endereço IP na área Rede.' 'crit'
    } elseif ($Data.IpConflict) {
        Set-DashboardNote 'netHint' 'Outro equipamento da rede está usando o mesmo IP: use Renovar endereço IP na área Rede ou corrija o IP fixo.' 'crit'
    } elseif ($Data.NoGateway) {
        Set-DashboardNote 'netHint' 'A placa não tem gateway: este PC não tem rota para a internet (confira a configuração de IP).' 'warn'
    } else {
        Set-DashboardNote 'netHint' ''
    }
}

function Refresh-Dashboard {
    param([switch]$Force)
    if ($global:TI.Busy) { return }
    if (-not $Force -and $global:Dashboard.LastRun -and
        ((Get-Date) - $global:Dashboard.LastRun).TotalSeconds -lt 20) { return }
    [void](Invoke-TIAsync -Name 'Leitura dos dados do sistema' -Quiet -Script {
        Get-TISystemSnapshot
    } -OnComplete {
        param($r)
        # Marcado só aqui: leitura cancelada tenta de novo na próxima visita
        $global:Dashboard.LastRun = Get-Date
        Update-DashboardUI -Data (@($r | Where-Object { $_ -and $_.PSObject.Properties['Computer'] }) | Select-Object -First 1)
    })
}

# I1: bloco pronto para colar no chamado ou na planilha
function Copy-TIDashboardSummary {
    $data = $global:Dashboard.Data
    if (-not $data) {
        Show-TIToast -Text 'Espere os dados carregarem e tente de novo.' -Type 'Warn'
        return
    }
    $lines = @(Get-DashboardFacts $data | ForEach-Object { '{0}: {1}' -f $_[0], $_[1] })
    try {
        [System.Windows.Forms.Clipboard]::SetText(($lines -join "`r`n"))
        Show-TIToast -Text 'Resumo copiado: cole no chamado ou na planilha (Ctrl+V).' -Type 'Success'
    } catch {
        Show-TIToast -Text 'Não foi possível usar a área de transferência.' -Type 'Error'
    }
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
    # Modo portátil: sugere a pasta "relatorios" do pendrive, não os Documentos do PC atendido
    if ($global:TIPortable -and $global:TIRoot) {
        $dir = Join-Path $global:TIRoot 'relatorios'
        try {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $dlg.InitialDirectory = $dir
        } catch { }
    }
    if ($dlg.ShowDialog($global:Form) -ne 'OK') { $dlg.Dispose(); return }

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('=====================================================================')
    [void]$lines.Add(' TI Suite - relatório do equipamento')
    [void]$lines.Add('=====================================================================')
    $fmt = ' {0,-22}: {1}'
    [void]$lines.Add(($fmt -f 'Data', (Get-Date -Format 'dd/MM/yyyy HH:mm:ss')))
    foreach ($p in (Get-DashboardFacts $data)) { [void]$lines.Add(($fmt -f $p[0], $p[1])) }
    [void]$lines.Add(($fmt -f 'DNS', $(if ($data.Dns) { $data.Dns } else { '-' })))
    [void]$lines.Add(($fmt -f 'Ligado há', (Format-TIDuration $data.Uptime)))
    [void]$lines.Add(($fmt -f 'Inicialização rápida', $(if ($data.FastStartup) { 'ligada' } else { 'desligada' })))
    [void]$lines.Add(($fmt -f 'Operador (TI Suite)', ('{0} ({1})' -f $data.Operator, $(if ($global:TI.Elevated) { 'administrador' } else { 'sem elevação' }))))
    [void]$lines.Add(($fmt -f 'Versão', ('TI Suite v{0}' -f $global:TI.Version)))
    [void]$lines.Add('=====================================================================')
    try {
        [System.IO.File]::WriteAllLines($dlg.FileName, [string[]]$lines.ToArray(), (New-Object System.Text.UTF8Encoding($true)))
        Write-TILog -Level 'Success' -Message ('Relatório exportado: {0}' -f $dlg.FileName)
        Show-TIToast -Text 'Relatório exportado.' -Type 'Success'
    } catch {
        Write-TILog -Level 'Error' -Message ('Falha ao exportar o relatório: {0}' -f $_.Exception.Message)
        Show-TIToast -Text 'Não foi possível salvar o relatório.' -Type 'Error'
    }
    $dlg.Dispose()
}

# Barra de uso com rótulo acima (disco e memória)
function New-DashboardMeter {
    param($Body, [string]$Key)
    $c = $global:Dashboard.Controls
    $lbl = New-TILabel -Text 'Lendo...' -Size 9.5 -Bold -Color $global:Pal.TextDim
    $lbl.AutoSize = $false
    $lbl.AutoEllipsis = $true
    $lbl.Height = 20
    $lbl.Tag = 'tirow'
    $lbl.Width = Get-TIInnerWidth $Body
    $Body.Controls.Add($lbl)
    $bar = New-Object TISuite.FlatProgress
    $bar.Percent = -1
    $bar.Height = 8
    $bar.Tag = 'tirow'
    $bar.Width = Get-TIInnerWidth $Body
    $bar.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 8)
    $Body.Controls.Add($bar)
    $c[$Key] = $lbl
    $c[$Key + 'Bar'] = $bar
    $c[$Key + 'Hint'] = New-TIHint -Parent $Body -Text ' ' -TopGap 0
}

$wsDashboard = @{
    Id       = 'dashboard'
    Title    = 'Início'
    Sub      = 'Visão geral do equipamento: identificação, disco, memória e rede'
    Icon     = 'Home'
    Keywords = 'inicio painel resumo relatorio disco memoria serie usuario ip mac copiar'

    OnActivate = { Refresh-Dashboard }
    Refresh    = { Refresh-Dashboard -Force }

    Actions = {
        param($Bar)
        $b1 = New-TIButton -Text 'Atualizar' -Style 'Outline' -Width 116 -Height 34 -Icon 'Refresh' -Tip 'Ler os dados de novo (Ctrl+R)'
        $b1.Add_Click({ Refresh-Dashboard -Force })
        $Bar.Controls.Add($b1)
        $b2 = New-TIButton -Text 'Exportar relatório' -Style 'Ghost' -Width 156 -Height 34 -Icon 'Export' -Tip 'Salva os dados do equipamento em .txt'
        $b2.Add_Click({ Export-TIReport })
        $Bar.Controls.Add($b2)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $c = $global:Dashboard.Controls

        # --- Armazenamento -------------------------------------------------
        $b1 = New-TICard -Parent $flow -Title 'Armazenamento' -Desc 'Espaço livre no disco do sistema e nas outras unidades' -Icon 'Monitor' -Half -Height 160
        New-DashboardMeter -Body $b1 -Key 'disk'
        $c['diskOther'] = New-TIHint -Parent $b1 -Text ' ' -TopGap 0
        $c['diskOther'].Visible = $false

        # --- Memória -------------------------------------------------------
        $b2 = New-TICard -Parent $flow -Title 'Memória RAM' -Desc 'Memória livre agora' -Icon 'Package' -Half -Height 160
        New-DashboardMeter -Body $b2 -Key 'mem'

        # --- Sistema -------------------------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Sistema' -Desc 'Identificação do equipamento (duplo clique copia o valor)' -Icon 'PC' -Half -Height 266
        $iw = Get-TIInnerWidth $b3
        foreach ($p in @(
            @{ K = 'computer'; L = 'Computador' },
            @{ K = 'model';    L = 'Modelo' },
            @{ K = 'serial';   L = 'Número de série' },
            @{ K = 'os';       L = 'Windows' },
            @{ K = 'cpu';      L = 'Processador' },
            @{ K = 'user';     L = 'Usuário conectado' },
            @{ K = 'operator'; L = 'Operador' },
            @{ K = 'uptime';   L = 'Ligado há' }
        )) {
            $r = New-TIRow -Label $p.L -Width $iw -LabelWidth 122
            $b3.Controls.Add($r.Panel)
            $c[$p.K] = $r.Value
        }
        $c['uptimeHint'] = New-TIHint -Parent $b3 -Text ' ' -TopGap 0
        $c['uptimeHint'].Visible = $false
        $sBar = New-TIButtonBar -Parent $b3
        $btnCopy = New-TIButton -Text 'Copiar resumo' -Style 'Outline' -Width 150 -Height 36 -Icon 'Copy' `
                    -Tip 'Nome, série, modelo, Windows, IP, MAC e usuário, prontos para colar no chamado'
        $btnCopy.Add_Click({ Copy-TIDashboardSummary })
        $sBar.Controls.Add($btnCopy)
        $null = Add-TIBarLabel -Bar $sBar -Text 'Para colar no chamado ou na planilha.'

        # --- Rede ----------------------------------------------------------
        $b4 = New-TICard -Parent $flow -Title 'Rede' -Desc 'Conexão principal deste computador' -Icon 'Ethernet' -Half -Height 266
        $iw = Get-TIInnerWidth $b4
        foreach ($p in @(
            @{ K = 'adapter'; L = 'Adaptador' },
            @{ K = 'ip';      L = 'IPv4' },
            @{ K = 'gateway'; L = 'Gateway' },
            @{ K = 'mac';     L = 'MAC' }
        )) {
            $r = New-TIRow -Label $p.L -Width $iw
            $b4.Controls.Add($r.Panel)
            $c[$p.K] = $r.Value
        }
        $c['netHint'] = New-TIHint -Parent $b4 -Text ' ' -TopGap 0
        $c['netHint'].Visible = $false
        $netBtn = New-TIButton -Text 'Diagnóstico de rede' -Style 'Outline' -Width 186 -Height 36 -Icon 'Globe'
        $netBtn.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
        $netBtn.Add_Click({ if (-not $global:TI.Busy) { Switch-TIWorkspace -Id 'rede' } })
        $b4.Controls.Add($netBtn)

        # --- Atalhos -------------------------------------------------------
        $b6 = New-TICard -Parent $flow -Title 'Atalhos' -Desc 'Teclas para trabalhar mais rápido' -Icon 'Terminal' -Half -Height 232
        $iw = Get-TIInnerWidth $b6
        foreach ($k in @(
            @{ K = 'Ctrl + 1 a 7';   V = 'Trocar de área' },
            @{ K = 'Ctrl + R ou F5'; V = 'Atualizar a área aberta' },
            @{ K = 'Ctrl + F';       V = 'Buscar ferramenta' },
            @{ K = 'Ctrl + L';       V = 'Limpar o console' },
            @{ K = 'Ctrl + E';       V = 'Exportar o console' },
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
