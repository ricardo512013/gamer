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
. (Get-SrcPath 'Workspaces' 'Limpeza.ps1')
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

# --- Rede: Wi-Fi (24H2), redes salvas, conclusão do teste, placa principal, disco --------
Assert-Equal 'wifi pt: BSSID' (Get-Row $w 'Ponto de acesso').Value '7c:8b:ca:11:22:33'
Assert-Equal 'wifi pt: perfil' (Get-Row $w 'Perfil salvo').Value 'ESCOLA-ALUNOS'
Assert-Equal 'wifi en: BSSID não vira SSID' (Get-Row $w3 'Ponto de acesso').Value 'aa:bb:cc:dd:ee:ff'
$w5 = @(ConvertFrom-TIWifiText -Text "Network shell commands need location permission to access WLAN information.`nms-settings:privacy-location")
Assert-Equal 'wifi sem Localização: aviso' $w5[0].Label 'Localização'
Assert-Equal 'wifi sem Localização: tom' $w5[0].Tone 'warn'
$pf = @(ConvertFrom-TIWifiProfiles -Text "Perfis na interface Wi-Fi:`n`nPerfis de usuários`n-------------`n    Todos os Perfis de Usuários: ESCOLA`n    Todos os Perfis de Usuários: Rede: 5G")
Assert-Equal 'redes salvas: quantidade' $pf.Count 2
Assert-Equal 'redes salvas: nome com dois-pontos' $pf[1] 'Rede: 5G'
Assert-Equal 'rede: tudo certo' (Get-TINetVerdict -HasIp $true -HasGateway $true -GatewayOk $true -PublicOk $true -DnsTotal 1 -DnsOkCount 1 -Http 'ok').Tone 'ok'
Assert-True  'rede: ping bloqueado não é falha' ((Get-TINetVerdict -HasIp $true -HasGateway $true -GatewayOk $true -PublicOk $false -DnsTotal 1 -DnsOkCount 1 -Http 'ok').Text -match 'bloqueia o ping')
Assert-True  'rede: DNS ruim é citado' ((Get-TINetVerdict -HasIp $true -HasGateway $true -GatewayOk $true -PublicOk $true -DnsTotal 2 -DnsOkCount 1 -DnsFailed @('10.0.0.9') -Http 'ok').Text -match '10\.0\.0\.9')
Assert-Equal 'rede: IP 169.254' (Get-TINetVerdict -HasIp $true -Apipa $true).Tone 'crit'
Assert-True  'rede: ping ok e DNS falhou' ((Get-TINetVerdict -HasIp $true -HasGateway $true -GatewayOk $true -PublicOk $true -DnsTotal 1 -DnsOkCount 0 -Http 'fail').Text -match 'DNS não resolve')
Assert-True  'rede: proxy 407' ((Get-TINetVerdict -HasIp $true -HasGateway $true -Http 'proxyauth').Text -match 'proxy')
$nets = @([pscustomobject]@{ Index = 5; Name = 'vEthernet (WSL)'; Up = $true; Physical = $false; Ips = @('172.20.0.1'); Gateways = @(); Metric = [int64]::MaxValue },
          [pscustomobject]@{ Index = 9; Name = 'Wi-Fi'; Up = $true; Physical = $true; Ips = @('192.168.0.20'); Gateways = @('192.168.0.1'); Metric = 55 },
          [pscustomobject]@{ Index = 3; Name = 'Ethernet'; Up = $true; Physical = $true; Ips = @('10.0.0.20'); Gateways = @('10.0.0.1'); Metric = 25 })
Assert-Equal 'placa principal: menor métrica com gateway' (Select-TIPrimaryNet $nets).Name 'Ethernet'
Assert-Equal 'placa principal: física antes da virtual' (Select-TIPrimaryNet @($nets[0], [pscustomobject]@{ Index = 7; Name = 'Ethernet'; Up = $true; Physical = $true; Ips = @('169.254.1.2'); Gateways = @(); Metric = 0 })).Name 'Ethernet'
Assert-Equal 'disco: 7,6 GB de 64 GB é crítico' (Get-TIDiskLevel -Free 7.6GB -Total 64GB) 'crit'
Assert-Equal 'disco: 90 GB de 1 TB é atenção' (Get-TIDiskLevel -Free 90GB -Total 1TB) 'warn'
Assert-Equal 'disco: 120 GB de 465 GB em ordem' (Get-TIDiskLevel -Free 120GB -Total 465GB) 'ok'
Assert-Equal 'disco sem leitura' (Get-TIDiskLevel -Free 0 -Total 0) 'none'

# --- Programas: data de instalação e códigos do desinstalador ----------------------------
Assert-Equal 'data aaaammdd' ((ConvertFrom-TIInstallDate '20240315').ToString('yyyy-MM-dd')) '2024-03-15'
Assert-Equal 'data m/d/aaaa' ((ConvertFrom-TIInstallDate '3/15/2024').ToString('yyyy-MM-dd')) '2024-03-15'
Assert-True  'data inválida' ($null -eq (ConvertFrom-TIInstallDate 'abc'))
Assert-Equal 'código 3010 pede reinício' (Get-TIUninstallCodeInfo 3010).Reboot $true
Assert-Equal 'código 1618 é falha' (Get-TIUninstallCodeInfo 1618).Ok $false
Assert-True  'código 1618 explicado' ((Get-TIUninstallCodeInfo 1618).Text -match 'Outra instalação')
Assert-Equal 'código 1614 não é falha' (Get-TIUninstallCodeInfo 1614).Ok $true

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

# --- Perfis de usuários: o que pode ser apagado ----------------------------------------
$mach = 'S-1-5-21-1111-2222-3333'
$dom  = 'S-1-5-21-7777-8888-9999'
$adm  = @{ ($mach + '-500') = $true; ($dom + '-512') = $true; ($dom + '-1500') = $true }
$cur  = $dom + '-1600'
function Get-V {
    param([string]$Sid, [string]$Path = 'C:\Users\x', [bool]$Special = $false, [bool]$Loaded = $false, $IsAdmin = $false,
          $Admins = $adm, [string]$Machine = $mach)
    $v = Get-TIProfileVerdict -Sid $Sid -Path $Path -Special $Special -Loaded $Loaded -MachineSid $Machine -AdminSids $Admins `
                              -CurrentSid $cur -IsAdmin $IsAdmin
    return ('{0}|{1}' -f $v.Kind, $v.Protected)
}
Assert-Equal 'perfil do sistema'            (Get-V 'S-1-5-18' 'C:\Windows\system32\config\systemprofile' -Special $true) 'Sistema|True'
Assert-Equal 'perfil de serviço'            (Get-V 'S-1-5-80-1-2-3' 'C:\Windows\ServiceProfiles\x') 'Sistema|True'
Assert-Equal 'Público nunca'                (Get-V ($dom + '-2000') 'C:\Users\Public') 'Sistema|True'
Assert-Equal 'Default nunca'                (Get-V ($dom + '-2001') 'C:\Users\Default') 'Sistema|True'
Assert-Equal 'conta local protegida'        (Get-V ($mach + '-1001') 'C:\Users\Professor') 'Local|True'
Assert-Equal 'SID local em minúsculas'      (Get-V ($mach.ToLower() + '-1002') 'C:\Users\aluno01') 'Local|True'
Assert-Equal 'prefixo parecido não é local' (Get-V ($mach + '1-1002') 'C:\Users\outro') 'Rede|False'
Assert-Equal 'administrador direto'         (Get-V ($dom + '-1500') 'C:\Users\ti.suporte') 'Rede|True'
Assert-Equal 'administrador por grupo'      (Get-V ($dom + '-1700') 'C:\Users\prof.maria' -IsAdmin $true) 'Rede|True'
Assert-Equal 'admin não confirmado protege' (Get-V ($dom + '-1701') 'C:\Users\prof.joao' -IsAdmin $null) 'Rede|True'
Assert-Equal 'aluno do domínio'             (Get-V ($dom + '-1800') 'C:\Users\12345.ESCOLA') 'Rede|False'
Assert-Equal 'perfil em uso'                (Get-V ($dom + '-1803') 'C:\Users\12348' -Loaded $true) 'Rede|True'
Assert-Equal 'conta que roda o app'         (Get-V $cur 'C:\Users\tecnico') 'Rede|True'
Assert-Equal 'Administradores ilegível'     (Get-V ($dom + '-1804') 'C:\Users\12349' -Admins $null) 'Rede|True'
Assert-Equal 'sem SID do computador'        (Get-V ($dom + '-1805') 'C:\Users\12350' -Machine '') '?|True'
Assert-Equal 'Azure AD'                     (Get-V 'S-1-12-1-11-22-33-44' 'C:\Users\aluno') 'Azure AD|False'

# Quem é administrador: domínio, último login guardado e grupos de fora do PC
$ctxDom = [pscustomobject]@{ AdminSids = $adm; DomainGroups = @($dom + '-512'); AzureGroups = $false; EveryoneAdmin = $false }
$ctxLoc = [pscustomobject]@{ AdminSids = @{ ($mach + '-500') = $true }; DomainGroups = @(); AzureGroups = $false; EveryoneAdmin = $false }
$ctxAll = [pscustomobject]@{ AdminSids = $adm; DomainGroups = @(); AzureGroups = $false; EveryoneAdmin = $true }
$ctxNul = [pscustomobject]@{ AdminSids = $null; DomainGroups = @(); AzureGroups = $false; EveryoneAdmin = $false }
$ctxAz  = [pscustomobject]@{ AdminSids = $adm; DomainGroups = @($dom + '-512'); AzureGroups = $true; EveryoneAdmin = $false }
$okMap  = [pscustomobject]@{ Ok = $true; Admins = @{ ($dom + '-1700') = $true } }
$noMap  = [pscustomobject]@{ Ok = $false; Admins = @{} }
function Get-A { param([string]$Sid, $Ctx, $Nested = $null, $Cache = @()) $r = Get-TIProfileAdminState -Sid $Sid -Ctx $Ctx -Nested $Nested -Cache $Cache; if ($null -eq $r) { 'nulo' } else { [string]$r } }
Assert-Equal 'admin: direto'                      (Get-A ($dom + '-1500') $ctxDom) 'True'
Assert-Equal 'admin: domínio confirmou'           (Get-A ($dom + '-1700') $ctxDom $okMap) 'True'
Assert-Equal 'admin: domínio negou'               (Get-A ($dom + '-1800') $ctxDom $okMap) 'False'
Assert-Equal 'admin: sem domínio, sem registro'   (Get-A ($dom + '-1800') $ctxDom $noMap) 'nulo'
Assert-Equal 'admin: sem domínio, login comum'    (Get-A ($dom + '-1800') $ctxDom $noMap @(($dom + '-513'), 'S-1-5-32-545')) 'False'
Assert-Equal 'admin: login guardou Administradores' (Get-A ($dom + '-1800') $ctxDom $noMap @(($dom + '-513'), 'S-1-5-32-544')) 'True'
Assert-Equal 'admin: login guardou Domain Admins' (Get-A ($dom + '-1801') $ctxDom $okMap @(($dom + '-512'))) 'True'
Assert-Equal 'admin: sem grupos de fora'          (Get-A ($dom + '-1800') $ctxLoc) 'False'
Assert-Equal 'admin: todos são administradores'   (Get-A ($dom + '-1800') $ctxAll) 'True'
Assert-Equal 'admin: grupo ilegível'              (Get-A ($dom + '-1800') $ctxNul) 'nulo'
Assert-Equal 'admin: Azure sem registro'          (Get-A 'S-1-12-1-1-2-3-4' $ctxAz $okMap) 'nulo'
Assert-Equal 'admin: Azure sem grupos do Azure'   (Get-A 'S-1-12-1-1-2-3-4' $ctxDom $okMap) 'False'
Assert-Equal 'admin: domínio negou, mas há Azure' (Get-A ($dom + '-1800') $ctxAz $okMap) 'nulo'

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
Assert-Equal 'mesmo PC pela série' (Find-TIInventoryIndex -Rows @($m2.Rows[0]) -Row $r1) 0
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

# --- Inventário: leitura robusta, identificação e gravação segura --------------------------
Assert-True  'série inválida (123456789)' (-not (Test-TIValidSerial '123456789'))
Assert-True  'série inválida (Default_string)' (-not (Test-TIValidSerial 'Default_string'))
Assert-True  'série inválida (Base Board Serial Number)' (-not (Test-TIValidSerial 'Base Board Serial Number'))
Assert-True  'UUID genérico' (-not (Test-TIValidUuid '03000200-0400-0500-0006-000700080009'))
Assert-True  'UUID zerado' (-not (Test-TIValidUuid '00000000-0000-0000-0000-000000000000'))
Assert-True  'UUID válido' (Test-TIValidUuid '{4C4C4544-0042-3510-8052-B3C04F4B4E32}')
$nics = @(
    [pscustomobject]@{ ifIndex = 3; MacAddress = '11-11-11-11-11-11'; PhysicalMediaType = 'BlueTooth'; NdisPhysicalMedium = 10; InterfaceDescription = 'Bluetooth Device (Personal Area Network)'; PnPDeviceID = 'BTH\MS_BTHPAN\1' },
    [pscustomobject]@{ ifIndex = 5; MacAddress = '22-22-22-22-22-22'; PhysicalMediaType = '802.3'; NdisPhysicalMedium = 14; InterfaceDescription = 'ASIX AX88179 USB 3.0 to Gigabit Ethernet Adapter'; PnPDeviceID = 'USB\VID_0B95&PID_1790\1' },
    [pscustomobject]@{ ifIndex = 7; MacAddress = '33-33-33-33-33-33'; PhysicalMediaType = 'Native 802.11'; NdisPhysicalMedium = 9; InterfaceDescription = 'Intel(R) Wi-Fi 6 AX201 160MHz'; PnPDeviceID = 'PCI\VEN_8086&DEV_A0F0\1' },
    [pscustomobject]@{ ifIndex = 9; MacAddress = '44-44-44-44-44-44'; PhysicalMediaType = '802.3'; NdisPhysicalMedium = 14; InterfaceDescription = 'Realtek PCIe GbE Family Controller'; PnPDeviceID = 'PCI\VEN_10EC&DEV_8168\1' }
)
$mac = Select-TIInventoryMacs -Adapters $nics
Assert-Equal 'MAC (cabo): pula Bluetooth e adaptador USB' $mac.Cabo '44-44-44-44-44-44'
Assert-Equal 'MAC (Wi-Fi)' $mac.WiFi '33-33-33-33-33-33'
Assert-Equal 'notebook sem porta de rede: cabo vazio' (Select-TIInventoryMacs -Adapters @($nics[0], $nics[2])).Cabo ''
$cfgs = @(
    [pscustomobject]@{ InterfaceAlias = 'Ethernet 2'; InterfaceDescription = 'VirtualBox Host-Only Ethernet Adapter'; IPv4Address = @([pscustomobject]@{ IPAddress = '192.168.56.1' }); IPv4DefaultGateway = $null },
    [pscustomobject]@{ InterfaceAlias = 'Ethernet'; InterfaceDescription = 'Realtek PCIe GbE Family Controller'; IPv4Address = @([pscustomobject]@{ IPAddress = '10.1.2.30' }); IPv4DefaultGateway = @([pscustomobject]@{ NextHop = '10.1.2.1' }) }
)
Assert-Equal 'IP principal: placa com gateway, não a do VirtualBox' (Select-TIInventoryIp -Configs $cfgs) '10.1.2.30'
$tt = "sep=;`r`nInventário - E.E. Fulano`r`nComputador;Patrimônio;Situação;Nº de série`r`nPC1;000123;Emprestado;AAA111`r`nPC2;000124;;BBB222"
$rt = @(ConvertFrom-TIInventoryText -Text $tt)
Assert-Equal 'planilha com "sep=" e título: linhas' $rt.Count 2
Assert-Equal 'planilha com "Nº de série" no cabeçalho' $rt[0]['Serie'] 'AAA111'
$tx = ConvertTo-TIInventoryText -Rows $rt
Assert-True  'coluna extra continua na planilha' ($tx -match '"Situação"' -and $tx -match '"Emprestado"')
$threw = $false
try { [void](ConvertFrom-TIInventoryText -Text "Inventário da escola`r`nPC1;123`r`nPC2;456") } catch { $threw = $true }
Assert-True  'cabeçalho não reconhecido dá erro (não lista vazia)' $threw
$mx = Merge-TIInventoryRow -Rows $rt -New (New-TIInventoryRecord -Data ([pscustomobject]@{ Computador = 'PC1'; Serie = 'AAA111' }) -Patrimonio '000123')
Assert-Equal 'coluna extra acompanha a linha atualizada' $mx.Rows[0]['_extra']['Situação'] 'Emprestado'
$px = ConvertTo-TIInventoryText -Rows @(New-TIInventoryRecord -Data ([pscustomobject]@{ Computador = 'PC9'; Serie = '123456789012345678'; Ip = '10.0.0.5' }) -Patrimonio '000123')
Assert-True  'Excel: patrimônio gravado como ="000123"' ($px -match '"=""000123"""')
$pb = @(ConvertFrom-TIInventoryText -Text $px)[0]
Assert-Equal 'Excel: patrimônio relido' $pb['Patrimonio'] '000123'
Assert-Equal 'Excel: série longa relida' $pb['Serie'] '123456789012345678'
Assert-Equal 'Excel: IP relido' $pb['Ip'] '10.0.0.5'
$rowsX = @(New-TIInventoryRecord -Data ([pscustomobject]@{ Computador = 'LAB-PC01'; Serie = '1,23457E+17' }))
Assert-Equal 'série estragada pelo Excel: casa pelo nome' (Find-TIInventoryIndex -Rows $rowsX -Row @{ Computador = 'LAB-PC01'; Serie = '123456789012345678' }) 0
$rowsM = @(New-TIInventoryRecord -Data ([pscustomobject]@{ Computador = 'PC-VELHO'; MacCabo = 'AA-BB-CC-00-11-22' }))
$mm = Find-TIInventoryMatch -Rows $rowsM -Row ([pscustomobject]@{ Computador = 'PC-NOVO'; Serie = ''; MacCabo = 'aa:bb:cc:00:11:22' })
Assert-Equal 'PC montado renomeado: casa pelo MAC' ('{0}|{1}' -f $mm.Index, $mm.By) '0|mac'
$rowsU = @(New-TIInventoryRecord -Data ([pscustomobject]@{ Computador = 'PC'; Uuid = '11111111-2222-3333-4444-555555555555' }))
Assert-Equal 'mesmo nome e UUID diferente: outro PC' (Find-TIInventoryIndex -Rows $rowsU -Row ([pscustomobject]@{ Computador = 'PC'; Uuid = '99999999-2222-3333-4444-555555555555' })) -1
Assert-Equal 'patrimônio repetido (mesmo sem os zeros à esquerda)' (Find-TIInventoryPatrimonio -Rows $m5.Rows -Patrimonio '123' -ExceptIndex 1)['Computador'] 'LAB2-PC05'
$chg = @(Get-TIInventoryChanges -Old $m2.Rows[0] -New ([pscustomobject]@{ Processador = 'Intel Core i5-10500'; Memoria = '4 GB (1 módulo)'; Armazenamento = 'SSD 256 GB'; MacCabo = 'aa:bb:cc:dd:ee:ff'; MacWifi = '' }))
Assert-Equal 'hardware que mudou: só a memória' $chg.Count 1
Assert-Equal 'hardware que mudou: texto' $chg[0] 'Memória 8 GB (2 x 4 GB) → 4 GB (1 módulo)'
Assert-Equal 'ordenação por data' (ConvertTo-TIInventoryDate '01/10/2026 08:05').ToString('yyyy-MM-dd HH:mm') '2026-10-01 08:05'
Assert-True  'ordenação por memória: 16 GB depois de 4 GB' ((ConvertTo-TIInventoryBytes '16 GB (2 x 8 GB)' -First) -gt (ConvertTo-TIInventoryBytes '4 GB (1 módulo)' -First))
$dirT = Join-Path ([System.IO.Path]::GetTempPath()) ('ti-inv-' + [guid]::NewGuid().ToString('N'))
try {
    $csvT = Join-Path $dirT 'inventario.csv'
    Save-TIInventory -Rows $m5.Rows -Path $csvT
    Save-TIInventory -Rows @($m5.Rows[0]) -Path $csvT
    $bkT = Join-Path $dirT 'backup'
    Assert-Equal 'gravação: relê o que gravou' @(Read-TIInventory -Path $csvT).Count 1
    Assert-Equal 'gravação: cópia de segurança antes de sobrescrever' @(Get-ChildItem -LiteralPath $bkT -Filter 'inventario-*.csv').Count 1
    Assert-Equal 'gravação: sem .tmp nem .old para trás' @(Get-ChildItem -LiteralPath $dirT -File | Where-Object { $_.Name -ne 'inventario.csv' }).Count 0
    1..12 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $bkT ('inventario-20260101-0000{0:00}.csv' -f $_)), 'x') }
    Remove-TIOldBackups -Dir $bkT -Keep 10
    Assert-Equal 'cópias de segurança: só as 10 últimas' @(Get-ChildItem -LiteralPath $bkT -Filter 'inventario-*.csv').Count 10
} finally {
    Remove-Item -LiteralPath $dirT -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Saúde do PC: regras novas ------------------------------------------------------------
Assert-Equal 'diferença 59,6 s vira 1 min' (Format-TIOffset 59.6) '1 min adiantado'
Assert-Equal 'diferença 3599,7 s vira 1 h' (Format-TIOffset 3599.7) '1 h adiantado'
Assert-Equal 'KMS: válido por mais N dias' (Get-TIActivationInfo -LicenseStatus 1 -Description 'VOLUME_KMSCLIENT channel' -GraceMinutes (179 * 1440)).Text 'Ativado (volume, KMS), válido por mais 179 dias'
Assert-Equal 'lista com "e"' (Join-TIWords @('Domínio', 'Privado', 'Público')) 'Domínio, Privado e Público'
Assert-Equal 'lista de 1' (Join-TIWords @('Privado')) 'Privado'
Assert-Equal 'temperatura HD 58 °C' (Get-TIDiskTempVerdict 58 'HD') 'warn'
Assert-Equal 'temperatura NVMe 68 °C' (Get-TIDiskTempVerdict 68 'SSD NVMe') 'ok'
Assert-Equal 'temperatura SSD 81 °C' (Get-TIDiskTempVerdict 81 'SSD') 'crit'
$da = Get-TIDiskAssessment -Label 'SSD 256 GB' -Name 'KINGSTON' -HealthTone 'ok' -Media 'SSD' -Temp 40 -Wear 96
Assert-Equal 'desgaste 96%: crítico' $da.Tone 'crit'
Assert-True  'desgaste 96%: fim da vida útil, não "com falha"' ($da.Issue -match 'fim da vida útil' -and $da.Issue -notmatch 'com falha')
Assert-True  'HD quente: aviso diz o motivo' ((Get-TIDiskAssessment -Label 'HD 1 TB' -Media 'HD' -Temp 62).Issue -match 'temperatura alta \(62 °C\)')
Assert-Equal 'estado desconhecido + desgaste 85%' (Get-TIDiskAssessment -Label 'SSD' -HealthTone 'dim' -Wear 85).Tone 'warn'
Assert-Equal 'erro de leitura sem correção' (Get-TIDiskAssessment -Label 'HD' -Uncorrected 3).Tone 'crit'
Assert-Equal 'espaço: 7 GB de 64 GB no sistema' (Get-TIFreeSpaceVerdict -Free 7GB -Size 64GB -System $true) 'warn'
Assert-Equal 'espaço: 4 GB no sistema' (Get-TIFreeSpaceVerdict -Free 4GB -Size 500GB -System $true) 'crit'
Assert-Equal 'espaço: unidade de dados só avisa' (Get-TIFreeSpaceVerdict -Free 1GB -Size 1000GB -System $false) 'warn'
Assert-True  'fuso de Brasília' (Test-TIBrazilTimeZone 'E. South America Standard Time')
Assert-True  'fuso do Pacífico não é do Brasil' (-not (Test-TIBrazilTimeZone 'Pacific Standard Time'))
Assert-Equal 'pausa do Windows Update (UTC)' ((ConvertFrom-TIIsoDate '2026-10-20T13:12:05Z').ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) '2026-10-20 13:12'
$cs = Get-TICrashSummary -Items @(
    [pscustomobject]@{ Id = 41; Code = 0; Button = $true; Time = [datetime]'2026-09-20' },
    [pscustomobject]@{ Id = 41; Code = 80; Button = $false; Time = [datetime]'2026-09-25' },
    [pscustomobject]@{ Id = 1001; Code = 0; Button = $false; Time = [datetime]'2026-09-25' })
Assert-Equal 'tela azul (41 + 1001) conta uma vez' $cs.BlueScreens 1
Assert-Equal 'desligamento inesperado' $cs.Shutdowns 1
Assert-Equal 'desligamento no botão de energia' $cs.PowerButton 1
Assert-Equal 'tela azul só pelo evento 41' (Get-TICrashSummary -Items @([pscustomobject]@{ Id = 41; Code = 80; Time = [datetime]'2026-09-25' })).BlueScreens 1
Assert-Equal '3 telas azuis: crítico' (Get-TICrashTones -Shutdowns 0 -BlueScreens 3).BlueScreen 'crit'
Assert-Equal '2 desligamentos: sem aviso' (Get-TICrashTones -Shutdowns 2 -BlueScreens 0).Shutdown ''
Assert-Equal 'BitLocker ligado (WMI)' (Get-TIBitLockerInfo -Protection 1 -Conversion 1).On $true
Assert-Equal 'BitLocker suspenso (WMI)' (Get-TIBitLockerInfo -Protection 0 -Conversion 1).Text 'Criptografado, proteção suspensa'
Assert-Equal 'BitLocker desligado (Explorer)' (Get-TIBitLockerShellInfo 2).Text 'Desligado'
Assert-True  'BitLocker sem valor (Explorer)' ($null -eq (Get-TIBitLockerShellInfo $null))
Assert-Equal 'fonte de horário no domínio' (Format-TITimeSource -Type 'NT5DS' -Domain 'ESCOLA').Text 'Controlador do domínio ESCOLA'
Assert-Equal 'fonte de horário NTP' (Format-TITimeSource -Type 'NTP' -NtpServer 'a.st1.ntp.br,0x9 b.st1.ntp.br,0x9').Text 'Servidor NTP: a.st1.ntp.br, b.st1.ntp.br'
Assert-Equal 'veredito sem administrador' (Get-SaudeVerdict -Crit 0 -Warn 0 -Partial $true).Text 'Nenhum problema encontrado (verificação parcial)'
Assert-Equal 'veredito 2 + 1' (Get-SaudeVerdict -Crit 2 -Warn 1).Text '2 problemas críticos e 1 ponto de atenção'
$secW = New-TIHealthSection 'windows'
Add-TIHealthRow $secW 'Última atualização' '10/05/2026 (há 143 dias)' 'crit'
Add-TIHealthIssue $secW 'crit' 'Sem atualização.'
$secB = New-TIHealthSection 'battery'
$secB.Status = 'none'; $secB.NotApplicable = $true
Add-TIHealthRow $secB 'Bateria' 'Não há bateria (computador de mesa)' 'dim'
$fakeRep = [pscustomobject]@{ Sections = [ordered]@{ windows = $secW; battery = $secB }; CheckedAt = [datetime]'2026-09-30 09:15'; Computer = 'LAB2-PC05'
                              Identity = [pscustomobject]@{ Fabricante = 'Dell Inc.'; Modelo = 'OptiPlex 3080'; Serie = 'ABC1234'; AssetTag = ''; Dominio = '' }; PartialNote = '' }
$laudo = New-SaudeLaudoText -Report $fakeRep -StatusText @{ windows = 'Crítico'; battery = 'Não se aplica' } -Inventory ([ordered]@{ Patrimonio = '000123'; Local = 'Lab 2' }) -Technician 'ti' -Version '1.4.0'
Assert-True  'laudo: patrimônio do inventário' ($laudo -match 'Patrimônio\s+: 000123')
Assert-True  'laudo: linha crítica marcada' ($laudo -match '\[X\] Última atualização')
Assert-True  'laudo: desktop "Não se aplica"' ($laudo -match 'Bateria \(Não se aplica\)')

Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ('Regras: {0} testes aprovados.' -f $script:pass) -ForegroundColor Green
    exit 0
}
Write-Host ('Regras: {0} de {1} testes falharam.' -f $script:fail, ($script:pass + $script:fail)) -ForegroundColor Red
exit 1
