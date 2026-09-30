# =====================================================================
# 99-SELFTEST.ps1 - Verificação estrutural do aplicativo (-SelfTest)
# =====================================================================

function Invoke-TISelfTest {
    $global:SelfTestChecks = New-Object System.Collections.ArrayList
    $global:SelfTestFailed = 0

    function Add-Check {
        param([string]$Name, [bool]$Ok, [string]$Detail = '')
        $status = if ($Ok) { 'OK  ' } else { 'FALHA' }
        $color = if ($Ok) { 'Green' } else { 'Red' }
        $line = '[{0}] {1}{2}' -f $status, $Name, $(if ($Detail) { ' - ' + $Detail } else { '' })
        Write-Host $line -ForegroundColor $color
        [void]$global:SelfTestChecks.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail })
        if (-not $Ok) { $global:SelfTestFailed++ }
    }

    function Wait-TIIdle {
        param([int]$Seconds = 20)
        $deadline = (Get-Date).AddSeconds($Seconds)
        while ($global:TI.Busy -and (Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 40
        }
        return -not $global:TI.Busy
    }

    # Deixa a janela processar eventos por um tempo (sem bloquear)
    function Invoke-TIUiWait {
        param([int]$Milliseconds = 300)
        $deadline = (Get-Date).AddMilliseconds($Milliseconds)
        while ((Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 30
        }
    }

    Write-Host ''
    Write-Host '==== TI Suite - autoverificação ====' -ForegroundColor Cyan
    Write-Host ''

    # 1. Sintaxe de todos os arquivos
    $all = @(Get-ChildItem -Path (Join-Path $global:TIRoot 'src') -Filter '*.ps1' -Recurse)
    $all += Get-Item -Path (Join-Path $global:TIRoot 'TI-Suite.ps1')
    $parseErrors = 0
    foreach ($f in $all) {
        $tok = $null; $err = $null
        [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$err) | Out-Null
        if ($err -and $err.Count -gt 0) {
            $parseErrors += $err.Count
            Write-Host ('    {0}: {1}' -f $f.Name, $err[0].Message) -ForegroundColor Red
        }
    }
    Add-Check 'Sintaxe dos arquivos PowerShell' ($parseErrors -eq 0) ("{0} arquivo(s), {1} erro(s)" -f @($all).Count, $parseErrors)

    # 2. Controles C#
    $typesOk = $true
    foreach ($t in @('TISuite.PremiumButton','TISuite.RoundPanel','TISuite.SidebarItem','TISuite.FlatProgress',
                     'TISuite.ArcSpinner','TISuite.ToggleSwitch','TISuite.StatusPill','TISuite.TIScrollFlow',
                     'TISuite.TIForm','TISuite.Native')) {
        if (-not ($t -as [type])) { $typesOk = $false; Write-Host "    tipo ausente: $t" -ForegroundColor Red }
    }
    # "compilados na hora", "DLL pré-compilada"... e o motivo, quando a DLL não foi usada
    $ctlDetail = [string]$global:TIControlsSource
    if ($global:TIControlsError) { $ctlDetail += ('; motivo: {0}' -f $global:TIControlsError) }
    Add-Check 'Controles visuais carregados' $typesOk $ctlDetail
    Add-Check 'Botão aceita Enter (PerformClick)' ($null -ne ([TISuite.PremiumButton].GetMethod('PerformClick')))

    # 3. Fontes de ícones e interface
    $famNames = [System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name }
    Add-Check 'Fonte Segoe MDL2 Assets (ícones)' ($famNames -contains 'Segoe MDL2 Assets')
    Add-Check 'Fonte Segoe UI' ($famNames -contains 'Segoe UI')

    # 4. Tema e tokens
    Add-Check 'Paleta de cores do tema' ($global:Pal.Count -ge 15 -and $null -ne $global:Pal.Primary)
    Add-Check 'Iconografia mapeada' (@($global:Icons.Keys).Count -ge 60) ("{0} ícones" -f $global:Icons.Keys.Count)

    # 5. Janela montada
    Add-Check 'Janela principal criada' ($null -ne $global:Form)
    Add-Check 'Barra lateral e navegação' ($null -ne $global:NavFlow -and $null -ne $global:HeaderTitle)
    Add-Check 'Console de log' ($null -ne $global:LogBox)
    Add-Check 'Barra de status' ($null -ne $global:StateLabel -and $null -ne $global:ProgressBar)

    # 6. Áreas de trabalho
    $ids = @($global:TI.Workspaces | ForEach-Object { $_.Id })
    Add-Check 'Áreas de trabalho registradas' (@($ids).Count -ge 7) ($ids -join ', ')
    Add-Check 'IDs sem duplicidade' ((@($ids | Select-Object -Unique)).Count -eq $ids.Count)
    Add-Check 'Itens da barra lateral' ($global:NavItems.Count -eq $ids.Count) ("{0} de {1}" -f $global:NavItems.Count, $ids.Count)
    Add-Check 'Todas as áreas sabem se atualizar (Ctrl+R)' (@($global:TI.Workspaces | Where-Object { -not $_.Refresh }).Count -eq 0)

    # 7. Construção de cada área (sem disparar recargas automáticas)
    $global:TI.SuppressOnActivate = $true
    foreach ($id in $ids) {
        try {
            Switch-TIWorkspace -Id $id -Force
            $panel = $global:WorkspacePanels[$id]
            $ok = ($null -ne $panel -and $panel.Controls.Count -gt 0)
            Add-Check ("Construção da área '{0}'" -f $id) $ok ("{0} controle(s) de nível superior" -f $(if ($panel) { $panel.Controls.Count } else { 0 }))
        } catch {
            Add-Check ("Construção da área '{0}'" -f $id) $false $_.ToString()
        }
    }
    $global:TI.SuppressOnActivate = $false

    # 8. Exibição breve da janela (layout, DWM, maximizar/restaurar, redimensionamento)
    try {
        $global:Form.Show()
        Invoke-TIUiWait 2000
        $wa = [System.Windows.Forms.Screen]::FromControl($global:Form).WorkingArea

        $global:Form.WindowState = 'Maximized'
        Invoke-TIUiWait 400
        $b = $global:Form.Bounds
        $okMax = ($global:BtnMax.Glyph -eq (Get-TIGlyph 'Restore')) -and ($null -eq $global:Form.Region) -and
                 ($global:Form.Padding.All -eq 0) -and ($b.Width -le $wa.Width) -and ($b.Height -le $wa.Height)
        Add-Check 'Maximizar dentro da área útil (sem cobrir a barra de tarefas)' $okMax ('{0}x{1} de {2}x{3}' -f $b.Width, $b.Height, $wa.Width, $wa.Height)

        $global:Form.WindowState = 'Normal'
        Invoke-TIUiWait 400
        $b = $global:Form.Bounds
        $okNorm = ($global:BtnMax.Glyph -eq (Get-TIGlyph 'Max')) -and ($global:Form.Padding.All -eq $global:Form.ResizeBorder) -and
                  ($b.Width -le $wa.Width) -and ($b.Height -le $wa.Height)
        Add-Check 'Restaurar: cabe na área útil e tem borda para redimensionar' $okNorm ('{0}x{1}' -f $b.Width, $b.Height)

        $global:Form.Width = 1280
        [System.Windows.Forms.Application]::DoEvents()
        Add-Check 'Exibição e redimensionamento da janela' ($global:Form.Width -eq 1280 -and $global:NavFlow.Width -gt 100)
    } catch {
        Add-Check 'Exibição e redimensionamento da janela' $false $_.ToString()
    }

    # 8b. Atalhos (teclas simuladas na própria janela) e ajuda F1 (montada, sem abrir)
    try {
        $onKey = [System.Windows.Forms.Control].GetMethod('OnKeyDown', [System.Reflection.BindingFlags]'Instance,NonPublic')
        $sendKey = {
            param([int]$Keys)
            $ev = New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]$Keys)
            [void]$onKey.Invoke($global:Form, [object[]]@(, $ev))
        }
        $wsIds = @($global:TI.Workspaces | ForEach-Object { $_.Id })
        $global:TI.SuppressOnActivate = $true
        Switch-TIWorkspace -Id $wsIds[0]
        & $sendKey ([int][System.Windows.Forms.Keys]::Control -bor [int][System.Windows.Forms.Keys]::D2)
        $okCtrl2 = ($global:TI.ActiveId -eq $wsIds[1])
        Switch-TIWorkspace -Id $wsIds[0]
        $global:TI.SuppressOnActivate = $false
        Add-Check 'Atalho Ctrl+2 troca de área' $okCtrl2

        $c0 = $global:ConsoleCollapsed
        & $sendKey ([int][System.Windows.Forms.Keys]::F12)
        $c1 = $global:ConsoleCollapsed
        & $sendKey ([int][System.Windows.Forms.Keys]::F12)
        Add-Check 'F12 mostra e oculta o console' (($c1 -ne $c0) -and ($global:ConsoleCollapsed -eq $c0))

        $sf = New-TIShortcutsForm
        $okHelp = ($sf.Controls.Count -ge 18)
        $sf.Dispose()
        Add-Check 'Ajuda de atalhos (F1)' $okHelp
    } catch {
        Add-Check 'Atalhos do teclado' $false $_.ToString()
    } finally {
        $global:TI.SuppressOnActivate = $false
    }

    # 9. Interruptor: vai e volta (bug do 2o clique corrigido na 1.3.0)
    try {
        $sw = New-Object TISuite.ToggleSwitch
        $sw.Checked = $true; $sw.Checked = $false; $sw.Checked = $true
        Add-Check 'Interruptor alterna corretamente' ($sw.Checked -eq $true)
        $sw.Dispose()
    } catch { Add-Check 'Interruptor alterna corretamente' $false $_.ToString() }

    # 10. Filtros e renderização do console
    $before = $global:LogEntries.Count
    Write-TILog -Level 'Info' -Message 'Autoteste: nível Info'
    Write-TILog -Level 'Success' -Message 'Autoteste: nível OK'
    Write-TILog -Level 'Warn' -Message 'Autoteste: nível Aviso'
    Write-TILog -Level 'Error' -Message 'Autoteste: nível Erro'
    Add-Check 'Registro de log com níveis' ($global:LogEntries.Count -eq ($before + 4))
    $global:LogFilter['Debug'] = $true
    Redraw-TILog
    Add-Check 'Redesenho do console com filtro' ($global:LogBox.TextLength -gt 0)
    while ($global:LogEntries.Count -gt $before) { $global:LogEntries.RemoveAt($global:LogEntries.Count - 1) }
    $global:LogErrorCount = 0
    $global:LogFilter['Debug'] = $false
    Redraw-TILog

    # 11. Execução assíncrona (fila + timer + resultado)
    [void](Wait-TIIdle -Seconds 60)
    $global:SelfTestAsync = @{ Done = $false; Result = $null }
    $okAsync = Invoke-TIAsync -Name 'Autoteste assíncrono' -Quiet -Script {
        Emit 'Etapa 1 de 2' 'Info' 50
        Emit 'Etapa 2 de 2' 'Success' 100
        Start-Sleep -Milliseconds 300
        [pscustomobject]@{ Value = 42 }
    } -OnComplete {
        param($r)
        $global:SelfTestAsync.Result = @($r | Where-Object { $_ }) | Select-Object -First 1
        $global:SelfTestAsync.Done = $true
    }
    Add-Check 'Início da tarefa assíncrona' $okAsync
    if ($okAsync) {
        $overlaySeen = $false
        $detailSeen = $false
        $deadline = (Get-Date).AddSeconds(15)
        while (-not $global:SelfTestAsync.Done -and (Get-Date) -lt $deadline) {
            [System.Windows.Forms.Application]::DoEvents()
            if ($global:Overlay.Visible) { $overlaySeen = $true }
            if ($global:OverlayHint.Text -like 'Etapa*' -and $global:OverlayLabel.Text -like '*%)') { $detailSeen = $true }
            Start-Sleep -Milliseconds 30
        }
        $idle = Wait-TIIdle -Seconds 5
        Add-Check 'Conclusão da tarefa assíncrona' $global:SelfTestAsync.Done
        Add-Check 'Resultado capturado da tarefa' ($global:SelfTestAsync.Result -and $global:SelfTestAsync.Result.Value -eq 42)
        Add-Check 'Estado liberado após a tarefa' $idle
        Add-Check 'Aviso de ocupado exibido' $overlaySeen
        Add-Check 'Aviso de ocupado mostra a última mensagem e o percentual' $detailSeen
    } else {
        Add-Check 'Conclusão da tarefa assíncrona' $false 'não iniciada'
    }

    # 11b. Falha relatada pela tarefa (Emit ... 'Error') conta como erro dela
    [void](Wait-TIIdle -Seconds 30)
    $okFail = Invoke-TIAsync -Name 'Autoteste de falha' -Quiet -Script { Emit 'Falha simulada do autoteste' 'Error' } -OnComplete { }
    if ($okFail) { [void](Wait-TIIdle -Seconds 15) }
    $failHit = @($global:LogEntries | Where-Object { $_.Text -eq 'Autoteste de falha: terminou com 1 erro(s).' }).Count -gt 0
    Add-Check "Emit 'Error' conta como erro da tarefa" ($okFail -and $failHit)

    # 11c. Fechar com tarefa em andamento: interrompe sem travar e libera o estado
    [void](Wait-TIIdle -Seconds 30)
    $global:SelfTestCloseDone = $false
    $okBusy = Invoke-TIAsync -Name 'Autoteste: fechar com tarefa' -Quiet -Script {
        for ($i = 0; $i -lt 300; $i++) { Start-Sleep -Milliseconds 100 }
    } -OnComplete { $global:SelfTestCloseDone = $true }
    if ($okBusy) {
        Invoke-TIUiWait 500
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        # Windows desligando: fecha sem perguntar (nenhum diálogo modal no autoteste)
        $allowed = Test-TICanClose -Reason ([System.Windows.Forms.CloseReason]::WindowsShutDown)
        $sw.Stop()
        Invoke-TIUiWait 300
        $okClose = ($allowed -and -not $global:TI.Busy -and -not $global:Overlay.Visible -and
                    -not $global:SelfTestCloseDone -and $sw.Elapsed.TotalSeconds -lt 8)
        Add-Check 'Fechar com tarefa: interrompe sem travar' $okClose ('{0:N1} s' -f $sw.Elapsed.TotalSeconds)
    } else {
        Add-Check 'Fechar com tarefa: interrompe sem travar' $false 'tarefa não iniciada'
    }

    # 12. Proteção de elevação
    if ($global:TI.Elevated) {
        Add-Check 'Execução elevada detectada' $true 'administrador'
    } else {
        $blocked = Invoke-TIAsync -Name 'Deve ser bloqueada' -RequiresAdmin -Script { 1 } -OnComplete { }
        Add-Check 'Bloqueio de ações sem elevação' (-not $blocked)
    }

    # 13. Regras das ferramentas (funções puras do worker, num escopo isolado)
    try {
        $logic = & {
            function Emit { param([string]$Text, [string]$Level = 'Info', [int]$Progress = -1) }
            . ([scriptblock]::Create($global:TIWorkerLib))
            $wifi = ConvertFrom-TIWifiText -Text ("    Estado : conectado`n    SSID : LAB`n    Tipo de rede : Infraestrutura`n    Tipo de rádio : 802.11ac`n    Sinal : 80%")
            $msi = Get-TIUninstallPlan -Uninstall 'MsiExec.exe /I{12345678-1234-1234-1234-123456789ABC}' -Quiet ''
            $unk = Get-TIUninstallPlan -Uninstall 'C:\App\remove.exe' -Quiet '' -IsNsis $false
            [pscustomobject]@{
                Wifi    = ((@($wifi | Where-Object { $_.Label -eq 'Padrão' }) | Select-Object -First 1).Value -eq '802.11ac')
                Msi     = ($msi.Kind -eq 'msi' -and $msi.Args -like '/X{*} /qn /norestart')
                Unknown = ($unk.Kind -eq 'interactive' -and -not $unk.Silent)
                Profile = ((Get-TIProfileVerdict -Sid 'S-1-5-21-1-2-3-1001' -Path 'C:\Users\Professor' -MachineSid 'S-1-5-21-1-2-3' -AdminSids @{}).Protected -and
                           (Get-TIProfileVerdict -Sid 'S-1-5-21-7-8-9-1801' -Path 'C:\Users\prof' -MachineSid 'S-1-5-21-1-2-3' -AdminSids @{} -IsAdmin $null).Protected -and
                           -not (Get-TIProfileVerdict -Sid 'S-1-5-21-7-8-9-1800' -Path 'C:\Users\12345.ESCOLA' -MachineSid 'S-1-5-21-1-2-3' -AdminSids @{}).Protected)
                Av      = ((Get-TIAvState 397568).Enabled -and -not (Get-TIAvState 393472).Enabled)
                Clock   = ((Get-TIClockVerdict 30) -eq 'ok' -and (Get-TIClockVerdict 400) -eq 'crit')
                Battery = ((Get-TIBatteryVerdict 45) -eq 'crit' -and (Get-TIBatteryVerdict 90) -eq 'ok')
            }
        }
        Add-Check 'Leitura do Wi-Fi (português e inglês)' ([bool]$logic.Wifi)
        Add-Check 'Desinstalação MSI silenciosa' ([bool]$logic.Msi)
        Add-Check 'Desinstalador desconhecido abre a janela' ([bool]$logic.Unknown)
        Add-Check 'Perfis: contas locais e admins protegidos' ([bool]$logic.Profile)
        Add-Check 'Leitura do estado do antivírus' ([bool]$logic.Av)
        Add-Check 'Regras de relógio e bateria' ([bool]($logic.Clock -and $logic.Battery))
    } catch {
        Add-Check 'Regras das ferramentas' $false $_.Exception.Message
    }

    # 14. Inventário: atualiza sem duplicar e relê a planilha (em memória)
    try {
        $fake = [pscustomobject]@{ Computador = 'LAB01-PC05'; Fabricante = 'Dell'; Modelo = 'OptiPlex 3080'; Serie = 'ABC1234'
                                   Processador = 'Intel Core i5'; Memoria = '8 GB (2 x 4 GB)'; Armazenamento = 'SSD 256 GB'
                                   Sistema = 'Windows 11 Pro 23H2'; Build = '22631.1'; MacCabo = 'AA-BB-CC-DD-EE-FF'; MacWifi = ''
                                   Ip = '10.0.0.5'; Dominio = 'ESCOLA'; Bios = '1.2' }
        $r1 = New-TIInventoryRecord -Data $fake -Patrimonio '000123' -Local 'Laboratório 2' -Observacao '=teste; "aspas"' -Tecnico 'ti'
        $m1 = Merge-TIInventoryRow -Rows @() -New $r1
        $r2 = New-TIInventoryRecord -Data $fake -Patrimonio '000123' -Local 'Sala 5' -Tecnico 'ti'
        $m2 = Merge-TIInventoryRow -Rows $m1.Rows -New $r2
        $back = @(ConvertFrom-TIInventoryText -Text (ConvertTo-TIInventoryText -Rows $m2.Rows))
        $ok = ($m2.Updated -and $back.Count -eq 1 -and $back[0]['Local'] -eq 'Sala 5' -and $back[0]['Patrimonio'] -eq '000123')
        Add-Check 'Inventário atualiza sem duplicar' $ok
    } catch {
        Add-Check 'Inventário atualiza sem duplicar' $false $_.Exception.Message
    }

    # 15. Persistência de configurações
    try {
        [void](Save-TISettings)
        Add-Check 'Gravação das configurações' (Test-Path -LiteralPath $global:TI.SettingsPath)
    } catch {
        Add-Check 'Gravação das configurações' $false $_.ToString()
    }
    $keys = $global:TI.Settings
    Add-Check 'Configurações: chaves atuais (janela e console lembrados)' (
        -not $keys.ContainsKey('SuppressConfirm') -and -not $keys.ContainsKey('ClearLogStart') -and
        $keys.ContainsKey('WindowMaximized') -and $keys.ContainsKey('ConsoleHeight'))
    Add-Check 'Usuário conectado ao Windows identificado' ([bool]$global:TI.SessionUser) ('{0} {1}' -f $global:TI.SessionUser, $global:TI.SessionUserSid)

    # 16. Folha de ícones (amostra visual para conferência manual)
    try {
        $names = @($global:Icons.Keys | Sort-Object)
        $rowsN = [Math]::Ceiling($names.Count / 12)
        $sheet = New-Object System.Drawing.Bitmap(640, [int](24 + $rowsN * 52))
        $g = [System.Drawing.Graphics]::FromImage($sheet)
        $g.Clear($global:Pal.Card)
        $g.TextRenderingHint = 'ClearTypeGridFit'
        $font = New-Object System.Drawing.Font('Segoe MDL2 Assets', 22)
        $small = New-Object System.Drawing.Font('Segoe UI', 6)
        $brush = New-Object System.Drawing.SolidBrush($global:Pal.Primary)
        $muted = New-Object System.Drawing.SolidBrush($global:Pal.TextMuted)
        $x = 8; $y = 12
        foreach ($name in $names) {
            if ($x -gt 610) { $x = 8; $y += 52 }
            $g.DrawString([string]$global:Icons[$name], $font, $brush, $x, $y)
            $g.DrawString($name, $small, $muted, $x, ($y + 32))
            $x += 52
        }
        $g.Dispose()
        $path = Join-Path $env:TEMP 'TI-Suite-icones.png'
        $sheet.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $sheet.Dispose()
        Add-Check 'Amostra de ícones exportada' (Test-Path -LiteralPath $path) $path
    } catch {
        Add-Check 'Amostra de ícones exportada' $false $_.ToString()
    }

    # 17. Oculta a janela
    try {
        $global:Form.Hide()
        Add-Check 'Ocultação da janela ao final' (-not $global:Form.Visible)
    } catch {
        Add-Check 'Ocultação da janela ao final' $false $_.ToString()
    }

    Write-Host ''
    $total = $global:SelfTestChecks.Count
    if ($global:SelfTestFailed -eq 0) {
        Write-Host ("==== RESULTADO: {0}/{0} verificações aprovadas ====" -f $total) -ForegroundColor Green
    } else {
        Write-Host ("==== RESULTADO: {0} de {1} verificações falharam ====" -f $global:SelfTestFailed, $total) -ForegroundColor Red
    }
    Write-Host ''
    return $(if ($global:SelfTestFailed -eq 0) { 0 } else { 1 })
}
