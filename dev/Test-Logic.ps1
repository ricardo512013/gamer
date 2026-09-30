# =====================================================================
# Test-Logic.ps1 - Testes das regras (funções puras) do TI Suite
# Não abre janela e não mexe no computador: roda em qualquer PowerShell
# (Windows PowerShell 5.1 ou pwsh 7).
# Uso:  powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\Test-Logic.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$global:TIRoot = $root
$global:TIPortable = $true
$script:pass = 0
$script:fail = 0

function Assert-Equal {
    param([string]$Name, $Got, $Want)
    if ([string]$Got -ceq [string]$Want) { $script:pass++ }
    else {
        $script:fail++
        Write-Host ('FALHA  {0}' -f $Name) -ForegroundColor Red
        Write-Host ('       esperado: [{0}]' -f $Want)
        Write-Host ('       obtido  : [{0}]' -f $Got)
    }
}
function Assert-True { param([string]$Name, $Cond) Assert-Equal $Name ([bool]$Cond) $true }

# A interface não é carregada: só as regras
function Register-TIWorkspace { }
function Emit { param([string]$Text, [string]$Level = 'Info', [int]$Progress = -1) }
function Get-SrcPath { param([string]$Dir, [string]$File) Join-Path (Join-Path (Join-Path $root 'src') $Dir) $File }

. (Get-SrcPath 'Core' '04-Async.ps1')
. (Get-SrcPath 'Workspaces' 'Saude.ps1')
. (Get-SrcPath 'Workspaces' 'Inventario.ps1')
. ([scriptblock]::Create($global:TIWorkerLib))

function Get-Row { param($Rows, [string]$Label) return (@($Rows | Where-Object { $_.Label -eq $Label }) | Select-Object -First 1) }

# --- Wi-Fi -------------------------------------------------------------------
$ptBr = @"
Há 1 interface no sistema:

    Nome                   : Wi-Fi
    Descrição              : Intel(R) Wireless-AC 9560
    Endereço físico        : 3c:6a:a7:12:34:56
    Estado                 : conectado
    SSID                   : ESCOLA-ALUNOS
    AP BSSID               : 7c:8b:ca:11:22:33
    Tipo de rede           : Infraestrutura
    Tipo de rádio          : 802.11ac
    Autenticação           : WPA2-Personal
    Codificação            : CCMP
    Banda                  : 5 GHz
    Canal                  : 44
    Taxa de recepção (Mbps)  : 866.7
    Taxa de transmissão (Mbps) : 780
    Sinal                  : 82%
    Perfil                 : ESCOLA-ALUNOS

    Estado da Rede Hospedada  : Não disponível
"@
$w = @(ConvertFrom-TIWifiText -Text $ptBr)
Assert-Equal 'wifi pt: SSID' (Get-Row $w 'Rede (SSID)').Value 'ESCOLA-ALUNOS'
Assert-Equal 'wifi pt: padrão (não confunde com "Tipo de rede")' (Get-Row $w 'Padrão').Value '802.11ac'
Assert-Equal 'wifi pt: segurança' (Get-Row $w 'Segurança').Value 'WPA2-Personal'
Assert-Equal 'wifi pt: sinal' (Get-Row $w 'Sinal').Value '82%'
Assert-Equal 'wifi pt: tom do sinal' (Get-Row $w 'Sinal').Tone 'ok'
Assert-Equal 'wifi pt: estado' (Get-Row $w 'Estado').Value 'conectado'
Assert-Equal 'wifi pt: estado não pega "Estado da Rede Hospedada"' @($w | Where-Object { $_.Label -eq 'Estado' }).Count 1
Assert-Equal 'wifi pt: recepção' (Get-Row $w 'Recepção (Mbps)').Value '866.7'
$moj = $ptBr.Replace('rádio', 'rÃ¡dio').Replace('Autenticação', 'AutenticaÃ§Ã£o').Replace('recepção', 'recepÃ§Ã£o').Replace('transmissão', 'transmissÃ£o')
$w2 = @(ConvertFrom-TIWifiText -Text $moj)
Assert-Equal 'wifi com acento quebrado: padrão' (Get-Row $w2 'Padrão').Value '802.11ac'
Assert-Equal 'wifi com acento quebrado: transmissão' (Get-Row $w2 'Transmissão (Mbps)').Value '780'
$en = "    Name                   : Wi-Fi`n    State                  : connected`n    SSID                   : LAB`n    BSSID                  : aa:bb:cc:dd:ee:ff`n    Network type           : Infrastructure`n    Radio type             : 802.11n`n    Authentication         : WPA2-Personal`n    Signal                 : 30%"
$w3 = @(ConvertFrom-TIWifiText -Text $en)
Assert-Equal 'wifi en: SSID (sem confundir com BSSID)' (Get-Row $w3 'Rede (SSID)').Value 'LAB'
Assert-Equal 'wifi en: padrão' (Get-Row $w3 'Padrão').Value '802.11n'
Assert-Equal 'wifi en: sinal fraco' (Get-Row $w3 'Sinal').Tone 'crit'
$w4 = @(ConvertFrom-TIWifiText -Text 'O serviço de configuração automática de rede sem fio (wlansvc) não está em execução.')
Assert-Equal 'wifi sem interface: 1 linha' $w4.Count 1
Assert-Equal 'wifi sem interface: rótulo' $w4[0].Label 'Wi-Fi'

# --- Desinstalação ---------------------------------------------------------------
$p = Get-TIUninstallPlan -Uninstall 'MsiExec.exe /I{12345678-1234-1234-1234-123456789ABC}' -Quiet ''
Assert-Equal 'msi: tipo' $p.Kind 'msi'
Assert-Equal 'msi: argumentos' $p.Args '/X{12345678-1234-1234-1234-123456789ABC} /qn /norestart'
$p = Get-TIUninstallPlan -Uninstall 'MsiExec.exe /X{12345678-1234-1234-1234-123456789ABC} /quiet' -Quiet ''
Assert-Equal 'msi já silencioso' $p.Args '/X{12345678-1234-1234-1234-123456789ABC} /quiet'
$p = Get-TIUninstallPlan -Uninstall '"C:\Program Files\App\unins000.exe"' -Quiet ''
Assert-Equal 'inno: tipo' $p.Kind 'inno'
Assert-Equal 'inno: executável' $p.Exe 'C:\Program Files\App\unins000.exe'
Assert-Equal 'inno: argumentos' $p.Args '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
$p = Get-TIUninstallPlan -Uninstall 'C:\Program Files\App X\uninst.exe' -Quiet '' -IsNsis $true
Assert-Equal 'nsis sem aspas: executável' $p.Exe 'C:\Program Files\App X\uninst.exe'
Assert-Equal 'nsis: argumentos' $p.Args '/S'
$p = Get-TIUninstallPlan -Uninstall '"C:\App\uninst.exe" /S' -Quiet '' -IsNsis $true
Assert-Equal 'nsis: não repete /S' $p.Args '/S'
$p = Get-TIUninstallPlan -Uninstall '"C:\App\remove.exe" --uninstall' -Quiet ''
Assert-Equal 'desconhecido: abre a janela' $p.Kind 'interactive'
Assert-Equal 'desconhecido: não inventa /S' $p.Args '--uninstall'
Assert-Equal 'desconhecido: não é silencioso' $p.Silent $false
$p = Get-TIUninstallPlan -Uninstall 'x' -Quiet '"C:\App\u.exe" /quiet'
Assert-Equal 'comando silencioso do fabricante' $p.Kind 'quiet'
Assert-Equal 'comando silencioso: argumentos' $p.Args '/quiet'
Assert-Equal 'rundll32' (Split-TICommandLine 'rundll32.exe dfshim.dll,ShArpMaintain app.application').Exe 'rundll32.exe'

# --- Perfis de aluno -----------------------------------------------------------------
foreach ($n in @('12345', '12345.000', '12345.ESCOLA', '9876543')) { Assert-True ('perfil de aluno: ' + $n) (Test-TIStudentProfileName $n) }
foreach ($n in @('professor', '12', '12345abc', 'admin.12345', 'TEMP', 'Public')) { Assert-True ('não é aluno: ' + $n) (-not (Test-TIStudentProfileName $n)) }

# --- Saúde do PC -----------------------------------------------------------------------
Assert-Equal 'antivírus ligado' (Get-TIAvState 397568).Enabled $true
Assert-Equal 'antivírus em dia' (Get-TIAvState 397568).UpToDate $true
Assert-Equal 'antivírus desligado' (Get-TIAvState 393472).Enabled $false
Assert-Equal 'antivírus desatualizado' (Get-TIAvState 397584).UpToDate $false
Assert-Equal 'antivírus 0x41000 ligado' (Get-TIAvState 266240).Enabled $true
Assert-Equal 'bateria 45%' (Get-TIBatteryVerdict 45) 'crit'
Assert-Equal 'bateria 65%' (Get-TIBatteryVerdict 65) 'warn'
Assert-Equal 'bateria 90%' (Get-TIBatteryVerdict 90) 'ok'
Assert-Equal 'capacidade da bateria' (Get-TIBatteryHealthPct -Design 50000 -Full 36000) 72
Assert-True  'capacidade sem dado' ($null -eq (Get-TIBatteryHealthPct -Design 0 -Full 100))
Assert-Equal 'atualização 30 dias' (Get-TIUpdateVerdict 30) 'ok'
Assert-Equal 'atualização 70 dias' (Get-TIUpdateVerdict 70) 'warn'
Assert-Equal 'atualização 130 dias' (Get-TIUpdateVerdict 130) 'crit'
Assert-Equal 'relógio 100 s' (Get-TIClockVerdict 100) 'ok'
Assert-Equal 'relógio -200 s' (Get-TIClockVerdict -200) 'warn'
Assert-Equal 'relógio 400 s' (Get-TIClockVerdict 400) 'crit'
Assert-Equal 'diferença 0,5 s' (Format-TIOffset 0.5) 'em dia (menos de 2 s)'
Assert-Equal 'diferença 45 s' (Format-TIOffset 45) '45 s adiantado'
Assert-Equal 'diferença -200 s' (Format-TIOffset -200) '3 min 20 s atrasado'
Assert-Equal 'diferença 2 h' (Format-TIOffset 7300) '2 h 2 min adiantado'
Assert-Equal 'diferença 3 dias' (Format-TIOffset -259200) '3 dias atrasado'
$c = Get-TIOffsetConsensus -Offsets @(3.1, 2.8, 400)
Assert-Equal 'consenso: mediana' $c.OffsetSeconds 3.1
Assert-Equal 'consenso: fontes que concordam' $c.Agree 2
Assert-True  'consenso sem fontes' ($null -eq (Get-TIOffsetConsensus -Offsets @()).OffsetSeconds)
$d = ConvertFrom-TIHttpDate 'Tue, 29 Sep 2026 17:32:10 GMT'
Assert-Equal 'data HTTP' ($d.ToString('yyyy-MM-dd HH:mm:ss')) '2026-09-29 17:32:10'
Assert-Equal 'data HTTP em UTC' $d.Kind 'Utc'
Assert-Equal 'data QFE m/d/aaaa' ((ConvertFrom-TIQfeDate '9/15/2026').ToString('yyyy-MM-dd')) '2026-09-15'
Assert-Equal 'data QFE aaaammdd' ((ConvertFrom-TIQfeDate '20260915').ToString('yyyy-MM-dd')) '2026-09-15'
Assert-Equal 'ativação OEM' (Get-TIActivationInfo -LicenseStatus 1 -Description 'Windows(R) Operating System, OEM_DM channel').Text 'Ativado (OEM)'
Assert-Equal 'ativação KMS vencendo' (Get-TIActivationInfo -LicenseStatus 1 -Description 'VOLUME_KMSCLIENT channel' -GraceMinutes (20 * 1440)).Tone 'warn'
Assert-Equal 'não ativado' (Get-TIActivationInfo -LicenseStatus 0).Tone 'warn'
Assert-Equal 'pior estado' (Get-TIWorseStatus 'ok' 'crit') 'crit'
Assert-Equal 'pior estado a partir de "sem dados"' (Get-TIWorseStatus 'none' 'warn') 'warn'
$sec = New-TIHealthSection 'teste'
Add-TIHealthIssue $sec 'warn' 'a'
Add-TIHealthIssue $sec 'crit' 'b'
Add-TIHealthIssue $sec 'warn' 'c'
Assert-Equal 'seção fica no pior estado' $sec.Status 'crit'
Assert-Equal 'seção guarda os problemas' $sec.Issues.Count 3

# --- Hardware (inventário e saúde) ------------------------------------------------------
Assert-Equal 'disco 256 GB' (Format-TIDiskSize 256060514304) '256 GB'
Assert-Equal 'disco 500 GB' (Format-TIDiskSize 500107862016) '500 GB'
Assert-Equal 'disco 240 GB' (Format-TIDiskSize 240057409536) '240 GB'
Assert-Equal 'disco 1 TB' (Format-TIDiskSize 1000204886016) '1 TB'
Assert-Equal 'disco 2 TB' (Format-TIDiskSize 2000398934016) '2 TB'
Assert-Equal 'eMMC 64 GB' (Format-TIDiskSize 62.5e9) '64 GB'
Assert-True  'disco 1,5 TB' ((Format-TIDiskSize 1.5e12) -match '^1[.,]5 TB$')
Assert-Equal 'mídia NVMe' (ConvertTo-TIMediaWord 'SSD' 'NVMe') 'SSD NVMe'
Assert-Equal 'mídia HD (numérica)' (ConvertTo-TIMediaWord 3 11) 'HD'
Assert-Equal 'saúde numérica' (ConvertTo-TIHealthWord 2).Tone 'crit'
Assert-True  'disco USB fica de fora' (-not (Test-TIInternalDisk ([pscustomobject]@{ BusType = 'USB' })))
Assert-Equal 'memória 2 x 4' (Format-TIMemoryText -Modules @(4GB, 4GB)) '8 GB (2 x 4 GB)'
Assert-Equal 'memória 1 módulo' (Format-TIMemoryText -Modules @(8GB)) '8 GB (1 módulo)'
Assert-Equal 'memória mista' (Format-TIMemoryText -Modules @(4GB, 8GB)) '12 GB (4 GB + 8 GB)'
Assert-True  'série inválida (O.E.M.)' (-not (Test-TIValidSerial 'To be filled by O.E.M.'))
Assert-True  'série inválida (Default string)' (-not (Test-TIValidSerial 'Default string'))
Assert-True  'série inválida (zeros)' (-not (Test-TIValidSerial '0000000'))
Assert-True  'série válida' (Test-TIValidSerial 'PF2ABCDE')

# --- Planilha do inventário ---------------------------------------------------------------
Assert-Equal 'chave do cabeçalho' (ConvertTo-TIInventoryKey 'Número de série') 'numerodeserie'
Assert-True  'caminho do inventário' ((Get-TIInventoryPath) -like '*inventario*inventario.csv')
$fake = [pscustomobject]@{ Computador = 'LAB2-PC05'; Fabricante = 'Dell Inc.'; Modelo = 'OptiPlex 3080'; Serie = 'ABC1234'; AssetTag = ''
                           Processador = 'Intel Core i5-10500'; Memoria = '8 GB (2 x 4 GB)'; Armazenamento = 'SSD 256 GB'
                           Sistema = 'Windows 11 Pro 23H2'; Build = '22631.4169'; MacCabo = 'AA-BB-CC-DD-EE-FF'; MacWifi = ''
                           Ip = '10.1.2.3'; Dominio = 'ESCOLA'; Bios = '1.20.0' }
$r1 = New-TIInventoryRecord -Data $fake -Patrimonio '000123' -Local 'Laboratório 2' -Observacao '=CMD(); tela "trincada"' -Tecnico 'tecnico' -When ([datetime]'2026-09-01 10:00')
$m1 = Merge-TIInventoryRow -Rows @() -New $r1
Assert-Equal 'inventário: primeira gravação' $m1.Updated $false
Assert-Equal 'inventário: 1 linha' @($m1.Rows).Count 1
$r2 = New-TIInventoryRecord -Data $fake -Patrimonio '000123' -Local 'Sala 5' -Tecnico 'tecnico' -When ([datetime]'2026-09-20 15:30')
$m2 = Merge-TIInventoryRow -Rows $m1.Rows -New $r2
Assert-Equal 'inventário: mesmo PC atualiza' $m2.Updated $true
Assert-Equal 'inventário: sem duplicar' @($m2.Rows).Count 1
Assert-Equal 'inventário: mantém a data do 1o registro' $m2.Rows[0]['RegistradoEm'] '01/09/2026 10:00'
Assert-Equal 'inventário: data da atualização' $m2.Rows[0]['AtualizadoEm'] '20/09/2026 15:30'
$fake2 = $fake.PSObject.Copy()
$fake2.Computador = 'LAB2-PC06'
$fake2.Serie = ''
$m3 = Merge-TIInventoryRow -Rows $m2.Rows -New (New-TIInventoryRecord -Data $fake2 -Patrimonio '000124')
Assert-Equal 'inventário: outro PC entra' @($m3.Rows).Count 2
$m4 = Merge-TIInventoryRow -Rows $m3.Rows -New (New-TIInventoryRecord -Data $fake2 -Patrimonio '000125')
Assert-Equal 'inventário: sem série casa pelo nome' @($m4.Rows).Count 2
$m5 = Merge-TIInventoryRow -Rows $m4.Rows -New $r1
$txt = ConvertTo-TIInventoryText -Rows $m5.Rows
Assert-True  'planilha: cabeçalho com acento' ($txt -match '"Patrimônio";"Local"')
Assert-True  'planilha: fórmula neutralizada' ($txt -match '"''=CMD')
$back = @(ConvertFrom-TIInventoryText -Text $txt)
Assert-Equal 'planilha: linhas relidas' $back.Count 2
$b1 = @($back | Where-Object { $_['Serie'] -eq 'ABC1234' })[0]
Assert-Equal 'planilha: local com acento' $b1['Local'] 'Laboratório 2'
Assert-Equal 'planilha: observação com ; e aspas' $b1['Observacao'] '=CMD(); tela "trincada"'
Assert-True  'mesmo PC pela série' (Test-TIInventorySame $m2.Rows[0] $r1)
Assert-Equal 'planilha vazia só com cabeçalho' @((ConvertTo-TIInventoryText -Rows @()) -split "`r`n").Count 1
$bc = @(ConvertFrom-TIInventoryText -Text "Computador,Patrimonio,Local,Numero de serie`r`nPC-X,999,Sala 1,XYZ9")
Assert-Equal 'planilha com vírgula: série' $bc[0]['Serie'] 'XYZ9'
Assert-Equal 'planilha com vírgula: patrimônio' $bc[0]['Patrimonio'] '999'
$tmp = [System.IO.Path]::GetTempFileName()
try {
    $ansi = [System.Text.Encoding]::GetEncoding(1252)
    [System.IO.File]::WriteAllBytes($tmp, $ansi.GetBytes("Computador;Patrimônio;Local`r`nPC-A;77;Laboratório"))
    $ba = @(ConvertFrom-TIInventoryText -Text (Read-TITextAuto -Path $tmp))
    Assert-Equal 'planilha ANSI (Excel): local' $ba[0]['Local'] 'Laboratório'
    Assert-Equal 'planilha ANSI (Excel): patrimônio' $ba[0]['Patrimonio'] '77'
    [System.IO.File]::WriteAllText($tmp, "Computador;Local`r`nPC-B;Informática", (New-Object System.Text.UTF8Encoding($true)))
    Assert-Equal 'planilha UTF-8 com BOM' (@(ConvertFrom-TIInventoryText -Text (Read-TITextAuto -Path $tmp)))[0]['Local'] 'Informática'
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ('Regras: {0} testes aprovados.' -f $script:pass) -ForegroundColor Green
    exit 0
}
Write-Host ('Regras: {0} de {1} testes falharam.' -f $script:fail, ($script:pass + $script:fail)) -ForegroundColor Red
exit 1
