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
. (Get-SrcPath 'Core' '06-Windows.ps1')
. (Get-SrcPath 'Workspaces' 'Saude.ps1')
. (Get-SrcPath 'Workspaces' 'Inventario.ps1')
. (Get-SrcPath 'Workspaces' 'Limpeza.ps1')
. (Get-SrcPath 'Workspaces' 'Recuperacao.ps1')
. (Get-SrcPath 'Workspaces' 'Backup.ps1')
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


# ===== testes propostos para dev\Test-Logic.ps1 (seção Backup) =====
# --- Backup de usuários: nomes e pastas ----------------------------------------
Assert-Equal 'backup: nome sem caracteres proibidos' (ConvertTo-TIBackupName 'a\b/c:d*e?f"g<h>i|j') 'a_b_c_d_e_f_g_h_i_j'
Assert-Equal 'backup: nome sem ponto e espaço no fim' (ConvertTo-TIBackupName '  joao. . ') 'joao'
Assert-Equal 'backup: nome vazio' (ConvertTo-TIBackupName '' -Fallback 'usuario') 'usuario'
Assert-Equal 'backup: nome reservado do Windows' (ConvertTo-TIBackupName 'CON') '_CON'
Assert-Equal 'backup: nome reservado com extensão' (ConvertTo-TIBackupName 'com1.txt') '_com1.txt'
Assert-Equal 'backup: nome comum com "con" no meio fica' (ConvertTo-TIBackupName 'conta') 'conta'
Assert-Equal 'backup: nome longo cortado' (ConvertTo-TIBackupName ('x' * 80)).Length 60
Assert-Equal 'backup: pasta base' (Get-TIBackupBase -DestRoot 'E:\' -Computer 'PC01') 'E:\Backup-TI\PC01'
Assert-Equal 'backup: pasta base com letra só' (Get-TIBackupBase -DestRoot 'E' -Computer 'LAB:01') 'E:\Backup-TI\LAB_01'
$d = Get-Date -Year 2026 -Month 10 -Day 5 -Hour 14 -Minute 30 -Second 12
Assert-Equal 'backup: pasta do usuário' (Get-TIBackupFolder -DestRoot 'E:\' -Computer 'PC01' -User 'joao' -Date $d) 'E:\Backup-TI\PC01\joao-20261005-1430'
Assert-Equal 'backup: pasta do usuário, segunda no mesmo minuto' (Get-TIBackupFolder -DestRoot 'E:\' -Computer 'PC01' -User 'joao' -Date $d -Attempt 2) 'E:\Backup-TI\PC01\joao-20261005-1430-2'
Assert-Equal 'backup: pasta com nome sanitizado' (Get-TIBackupFolder -DestRoot 'E:\' -Computer 'PC 01' -User 'ana|maria' -Date $d) 'E:\Backup-TI\PC 01\ana_maria-20261005-1430'
Assert-Equal 'backup: auditoria' (Get-TIBackupAuditDetail -Names @('a', 'b') -Base 'E:\Backup-TI\PC01') 'Usuários: a, b -> E:\Backup-TI\PC01'
Assert-Equal 'backup: auditoria longa' (Get-TIBackupAuditDetail -Names @('a', 'b', 'c') -Base 'E:\X' -Max 2) 'Usuários: a, b e mais 1 -> E:\X'

# --- Backup: espaço e estimativa --------------------------------------------------
Assert-True  'backup: cabe com 5% de folga' (Test-TIBackupSpace -Needed 100GB -Free 105GB).Ok
Assert-True  'backup: não cabe sem a folga' (-not (Test-TIBackupSpace -Needed 100GB -Free 104GB).Ok)
Assert-Equal 'backup: quanto falta' ([Math]::Round((Test-TIBackupSpace -Needed 100GB -Free 104GB).Missing / 1GB, 2)) 1
Assert-True  'backup: livre desconhecido bloqueia' (-not (Test-TIBackupSpace -Needed 1MB -Free -1).Ok)
Assert-True  'backup: livre nulo é desconhecido' (-not (Test-TIBackupSpace -Needed 1MB -Free $null).Known)
Assert-True  'backup: nada para copiar cabe' (Test-TIBackupSpace -Needed 0 -Free 0).Ok
$us = @([pscustomobject]@{ Size = 10GB; CacheSize = 2GB }, [pscustomobject]@{ Size = 1GB; CacheSize = 0 }, [pscustomobject]@{ Size = -1 })
Assert-Equal 'backup: estimativa sem caches' ((Get-TIBackupEstimate -Items $us -SkipCache $true) / 1GB) 9
Assert-Equal 'backup: estimativa com caches' ((Get-TIBackupEstimate -Items $us -SkipCache $false) / 1GB) 11

# --- Backup: robocopy --------------------------------------------------------------
$ra = @(Get-TIBackupRobocopyArgs -Source 'C:\Users\joao' -Dest 'E:\Backup-TI\PC01\joao-20261005-1430' -LogPath 'E:\Backup-TI\PC01\joao-20261005-1430\_robocopy.log' -IsAdmin $true)
Assert-Equal 'backup: linha do robocopy (admin)' (Join-TIBackupArgs $ra) '"C:\Users\joao" "E:\Backup-TI\PC01\joao-20261005-1430" /E /COPY:DAT /DCOPY:DAT /XJ /R:1 /W:1 /MT:8 /NP /NFL /NDL /BYTES /ZB /UNILOG+:"E:\Backup-TI\PC01\joao-20261005-1430\_robocopy.log"'
$ra2 = @(Get-TIBackupRobocopyArgs -Source 'C:\Users\joao\' -Dest 'E:\B' -LogPath 'E:\B\_robocopy.log' -IsAdmin $false -ExcludeDirs @('C:\Users\joao\AppData\Local\Temp', 'C:\Users\joao\AppData\Local\Google\Chrome\User Data\Default\Code Cache') -ExcludeFiles @('NTUSER.DAT*', 'UsrClass.dat*'))
Assert-True  'backup: /XJ sempre' ($ra2 -contains '/XJ')
Assert-True  'backup: sem /ZB sem administrador' ($ra2 -notcontains '/ZB')
Assert-Equal 'backup: origem sem barra no fim' $ra2[0] 'C:\Users\joao'
Assert-Equal 'backup: /XD com caminho com espaço' (Join-TIBackupArgs $ra2) '"C:\Users\joao" "E:\B" /E /COPY:DAT /DCOPY:DAT /XJ /R:1 /W:1 /MT:8 /NP /NFL /NDL /BYTES /XD "C:\Users\joao\AppData\Local\Temp" "C:\Users\joao\AppData\Local\Google\Chrome\User Data\Default\Code Cache" /XF "NTUSER.DAT*" "UsrClass.dat*" /UNILOG+:"E:\B\_robocopy.log"'
Assert-Equal 'backup: aspas com barra no fim' (ConvertTo-TIBackupArg 'E:\' -Force) '"E:\\"'
Assert-Equal 'backup: argumento simples sem aspas' (ConvertTo-TIBackupArg '/MT:8') '/MT:8'
Assert-Equal 'backup: aspas internas' (ConvertTo-TIBackupArg 'a "b"') '"a \"b\""'
Assert-Equal 'backup: código sem o extra do próprio log' (Get-TIBackupEffectiveCode 3) 1
Assert-Equal 'backup: código 2 vira 0' (Get-TIBackupEffectiveCode 2) 0
Assert-Equal 'backup: falha continua falha' (Get-TIBackupEffectiveCode 11) 9
Assert-Equal 'backup: erro grave continua' (Get-TIBackupEffectiveCode 16) 16
Assert-Equal 'backup: situação com falhas' (Get-TIBackupStatus -Code 9).Level 'Error'
Assert-Equal 'backup: situação ok' (Get-TIBackupStatus -Code 1).Word 'Concluído'
Assert-Equal 'backup: situação interrompida' (Get-TIBackupStatus -Code -1 -Interrupted $true).Word 'Interrompido'
Assert-Equal 'backup: percentual' (Get-TIBackupPercent -Done 50 -Total 200) 25
Assert-Equal 'backup: percentual não chega a 100 antes do fim' (Get-TIBackupPercent -Done 500 -Total 200) 99
Assert-Equal 'backup: percentual sem total' (Get-TIBackupPercent -Done 5 -Total 0) 0
Assert-Equal 'backup: duração curta' (Format-TIBackupDuration 42) '42 s'
Assert-Equal 'backup: duração em minutos' (Format-TIBackupDuration 185) '3 min 05 s'
Assert-Equal 'backup: duração em horas' (Format-TIBackupDuration 3725) '1 h 02 min'

# --- Backup: temporários e caches (/XD) ----------------------------------------------
$cd = @(Get-TIBackupCacheDirs -UserPath 'C:\Users\joao\' -ChromeProfiles @('Default', 'Profile 1', 'Crashpad') -FirefoxProfiles @('ab12.default-release'))
Assert-True  'caches: Temp' ($cd -contains 'C:\Users\joao\AppData\Local\Temp')
Assert-True  'caches: INetCache' ($cd -contains 'C:\Users\joao\AppData\Local\Microsoft\Windows\INetCache')
Assert-True  'caches: Chrome Profile 1 Code Cache' ($cd -contains 'C:\Users\joao\AppData\Local\Google\Chrome\User Data\Profile 1\Code Cache')
Assert-True  'caches: Chrome GPUCache' ($cd -contains 'C:\Users\joao\AppData\Local\Google\Chrome\User Data\Default\GPUCache')
Assert-True  'caches: pasta que não é perfil fica de fora' (-not ($cd -like '*Crashpad*'))
Assert-True  'caches: Edge sem perfil, nada do Edge' (-not ($cd -like '*\Edge\*'))
Assert-True  'caches: Firefox cache2' ($cd -contains 'C:\Users\joao\AppData\Local\Mozilla\Firefox\Profiles\ab12.default-release\cache2')
Assert-True  'caches: nunca só o nome' (@($cd | Where-Object { $_ -notlike 'C:\Users\joao\*' }).Count -eq 0)
Assert-Equal 'caches: quantidade' $cd.Count 14

# --- Backup: resumo e erros do log do robocopy ---------------------------------------------
$logEn = @"
-------------------------------------------------------------------------------
   ROBOCOPY     ::     Robust File Copy for Windows
-------------------------------------------------------------------------------

  Started : Monday, October 5, 2026 2:30:01 PM
   Source : C:\Users\joao\
     Dest : E:\Backup-TI\PC01\joao-20261005-1430\

2026/10/05 14:31:02 ERROR 32 (0x00000020) Copying File C:\Users\joao\Documents\a.pst
The process cannot access the file because it is being used by another process.
Waiting 1 seconds... Retrying...
2026/10/05 14:31:03 ERROR 32 (0x00000020) Copying File C:\Users\joao\Documents\a.pst
The process cannot access the file because it is being used by another process.

ERROR: RETRY LIMIT EXCEEDED.

------------------------------------------------------------------------------

               Total    Copied   Skipped  Mismatch    FAILED    Extras
    Dirs :       120       119         1         0         0         0
   Files :      4521      4519         1         0         1         1
   Bytes : 987654321 987000000    654321         0         0       512
   Times :   0:02:01   0:01:58                       0:00:00   0:00:02
   Ended : Monday, October 5, 2026 2:32:02 PM
"@
$s1 = ConvertFrom-TIBackupRobocopySummary -Text $logEn
Assert-True  'log en: resumo achado' $s1.Found
Assert-Equal 'log en: arquivos copiados' $s1.FilesCopied 4519
Assert-Equal 'log en: arquivos com falha' $s1.FilesFailed 1
Assert-Equal 'log en: bytes copiados' $s1.BytesCopied 987000000
Assert-Equal 'log en: total de arquivos' $s1.FilesTotal 4521
$e1 = Get-TIBackupRobocopyErrors -Text $logEn
Assert-Equal 'log en: erro repetido conta uma vez' $e1.Count 1
Assert-True  'log en: erro com a mensagem' ($e1.Lines[0] -match '^ERROR 32 .*a\.pst - The process cannot')
$logPt = @"
  Iniciado : segunda-feira, 5 de outubro de 2026 14:30:01
     Origem : C:\Users\maria\

                Total   Copiado  Ignorado Incompatibilidade     FALHA    Extras
 Diretórios :        10        10         0         0         0         0
   Arquivos :       100        97         0         0         3         0
      Bytes :   5000000   4900000         0         0    100000         0
     Tempos :   0:00:10   0:00:09                       0:00:00   0:00:00
   Término : segunda-feira, 5 de outubro de 2026 14:30:11
"@
$s2 = ConvertFrom-TIBackupRobocopySummary -Text $logPt
Assert-Equal 'log pt: arquivos copiados' $s2.FilesCopied 97
Assert-Equal 'log pt: falhas' $s2.FilesFailed 3
Assert-Equal 'log pt: bytes' $s2.BytesCopied 4900000
Assert-True  'log sem resumo' (-not (ConvertFrom-TIBackupRobocopySummary -Text 'ERRO: parâmetro inválido').Found)
$s3 = ConvertFrom-TIBackupRobocopySummary -Text ($logPt -replace '   5000000   4900000         0         0    100000         0', '   4.7 m   4.6 m   0   0   97.6 k   0')
Assert-True  'log sem /BYTES: arquivos ainda lidos' ($s3.Found -and $s3.FilesCopied -eq 97)
Assert-Equal 'log sem /BYTES: bytes desconhecidos' $s3.BytesCopied -1

# --- Backup: destino --------------------------------------------------------------------
$v1 = ConvertTo-TIBackupVolume ([pscustomobject]@{ Drive = 'E:'; Label = 'BACKUP'; FileSystem = 'NTFS'; SizeBytes = 1TB; FreeBytes = 500GB; Type = 'USB'; IsTiSuite = $false })
Assert-Equal 'volume: raiz' $v1.Root 'E:\'
Assert-Equal 'volume: livre' ($v1.Free / 1GB) 500
Assert-Equal 'volume: disco desconhecido' $v1.DiskNumber -1
$v2 = ConvertTo-TIBackupVolume @{ Letter = 'f'; Free = 0; Size = 32GB; IsTiSuite = $true; DiskNumber = 0 }
Assert-Equal 'volume: letra sozinha' $v2.Drive 'F:'
Assert-Equal 'volume: livre zero é conhecido' $v2.Free 0
Assert-True  'volume: pendrive do TI Suite' $v2.IsTiSuite
Assert-Equal 'volume: disco 0' $v2.DiskNumber 0
Assert-Equal 'volume: livre desconhecido' (ConvertTo-TIBackupVolume ([pscustomobject]@{ Root = 'Z:\' })).Free -1
$n1 = @(Get-TIBackupDestNotes -Dest ([pscustomobject]@{ DiskNumber = 0; FileSystem = 'FAT32'; Type = 'Interno'; IsTiSuite = $false }) -SourceDisk 0)
Assert-Equal 'destino: mesmo disco e FAT32' (@($n1 | ForEach-Object { $_.Kind }) -join ',') 'samedisk,fat'
Assert-Equal 'destino: exFAT não avisa' @(Get-TIBackupDestNotes -Dest ([pscustomobject]@{ DiskNumber = 1; FileSystem = 'exFAT'; Type = 'USB' }) -SourceDisk 0).Count 0
Assert-Equal 'destino: disco desconhecido não avisa' @(Get-TIBackupDestNotes -Dest ([pscustomobject]@{ DiskNumber = -1; FileSystem = 'NTFS' }) -SourceDisk -1).Count 0

# --- Backup: LEIA-ME ------------------------------------------------------------------------
$rm = Get-TIBackupReadme -Info ([pscustomobject]@{
    Version = '1.5.0'; Status = 'COMPLETO'; Computer = 'PC01'; Windows = 'Windows 11 Pro 24H2 (26100.2033)'
    User = 'joao'; Account = 'ESCOLA\joao'; Source = 'C:\Users\joao'; Folder = 'E:\Backup-TI\PC01\joao-20261005-1430'
    Start = $d; End = $d.AddSeconds(185); Seconds = 185; Bytes = 1GB; Files = 4519; FilesTotal = 4521; Failed = 1
    Code = 9; CodeRaw = 11; CodeText = 'falhas'; CacheSkipped = $true; HivesSkipped = $true; Interrupted = $false })
Assert-True  'leia-me: usuário e conta' ($rm -match 'Usuário:\s+joao \(ESCOLA\\joao\)')
Assert-True  'leia-me: situação' ($rm -match 'Situação:\s+COMPLETO')
Assert-True  'leia-me: código e original' ($rm -match 'Robocopy:\s+código 9 - falhas \(no log, código 11')
Assert-True  'leia-me: arquivos' ($rm -match 'Arquivos copiados:\s+4519 de 4521')
Assert-True  'leia-me: hives avisados' ($rm -match 'NTUSER\.DAT')
Assert-True  'leia-me: caches avisados' ($rm -match 'Temporários e caches')
Assert-True  'leia-me: falhas apontam o log' ($rm -match '_robocopy\.log')
Assert-True  'leia-me: duração' ($rm -match '\(3 min 05 s\)')
Assert-True  'leia-me: CRLF' ($rm -match "`r`n" -and $rm -notmatch "[^`r]`n")
$rm2 = Get-TIBackupReadme -Info ([pscustomobject]@{ Version = '1.5.0'; Status = 'INCOMPLETO'; User = 'maria'; Start = $d; End = $d; Seconds = 3; Bytes = 10MB; Interrupted = $true })
Assert-True  'leia-me interrompido: aviso' ($rm2 -match 'interrompida' -and $rm2 -notmatch 'Arquivos com falha')
$rm3 = Get-TIBackupReadme -Info ([pscustomobject]@{ Version = '1.5.0'; Status = 'COMPLETO'; User = 'a'; Start = $d; End = $d; Seconds = 1; Bytes = 1; Files = 1; FilesTotal = 1; Failed = 0; Code = 1; CodeRaw = 3; CodeText = (Get-TIRobocopyResult -ExitCode 1).Text })
Assert-True  'leia-me: código do robocopy sem repetir' ($rm3 -match 'Robocopy:\s+Cópia concluída \(código 1\)' -and $rm3 -match 'no log, código 3')

# --- Windows no disco (06-Windows.ps1): rótulo, robocopy, caminhos offline --------
Assert-Equal 'win: 11 pelo build (registro diz 10)' (Get-TIWindowsLabel -ProductName 'Windows 10 Pro' -EditionId 'Professional' -Build 26100 -Ubr 2033 -DisplayVersion '24H2') 'Windows 11 Pro 24H2 (26100.2033)'
Assert-Equal 'win: 10 antigo usa ReleaseId' (Get-TIWindowsLabel -ProductName 'Windows 10 Home' -EditionId 'Core' -Build 18363 -Ubr 1556 -ReleaseId '1909') 'Windows 10 Home 1909 (18363.1556)'
Assert-Equal 'win: edição pelo nome do produto' (Get-TIWindowsLabel -ProductName 'Windows 10 Education' -Build 19045 -DisplayVersion '22H2') 'Windows 10 Education 22H2 (19045)'
Assert-Equal 'win: LTSC' (Get-TIWindowsLabel -ProductName 'Windows 10 Enterprise LTSC 2019' -EditionId 'EnterpriseS' -Build 17763 -Ubr 1 -ReleaseId '1809') 'Windows 10 Enterprise LTSC 1809 (17763.1)'
Assert-Equal 'win: servidor fica como está' (Get-TIWindowsLabel -ProductName 'Windows Server 2019 Standard' -EditionId 'ServerStandard' -Build 17763) 'Windows Server 2019 Standard (17763)'
Assert-Equal 'win: sem dados' (Get-TIWindowsLabel) 'Windows'
Assert-Equal 'robocopy 0: nada novo' (Get-TIRobocopyResult 0).Level 'Success'
Assert-Equal 'robocopy 3: extras no destino é sucesso' (Get-TIRobocopyResult 3).Ok $true
Assert-Equal 'robocopy 5: diferenças' (Get-TIRobocopyResult 5).Level 'Warn'
Assert-Equal 'robocopy 8: falha' (Get-TIRobocopyResult 8).Ok $false
Assert-Equal 'robocopy 16: erro grave' (Get-TIRobocopyResult 16).Level 'Error'
Assert-Equal 'robocopy -1: não terminou' (Get-TIRobocopyResult -1).Ok $false
Assert-Equal 'offline: %SystemDrive%' (Resolve-TIOfflinePath -Path '%SystemDrive%\Users\ana' -Drive 'D:') 'D:\Users\ana'
Assert-Equal 'offline: C: vira a letra da instalação' (Resolve-TIOfflinePath -Path 'C:\Users\ana' -Drive 'D:') 'D:\Users\ana'
Assert-Equal 'offline: %ProgramFiles(x86)%' (Resolve-TIOfflinePath -Path '"%ProgramFiles(x86)%\App"' -Drive 'E') 'E:\Program Files (x86)\App'
Assert-Equal 'firmware: PEFirmwareType 2' (ConvertTo-TIFirmwareType -PEFirmwareType 2) 'UEFI'
Assert-Equal 'firmware: %firmware_type% Legacy' (ConvertTo-TIFirmwareType -EnvFirmware 'Legacy') 'BIOS'
Assert-Equal 'firmware: winload.efi' (ConvertTo-TIFirmwareType -BcdText 'path  \WINDOWS\system32\winload.efi') 'UEFI'
Assert-Equal 'usuários: Público fica de fora' (Test-TIUserFolderExcluded -Name 'Public') $true
Assert-Equal 'usuários: defaultuser0 fica de fora' (Test-TIUserFolderExcluded -Name 'defaultuser0') $true
Assert-Equal 'usuários: SID do sistema fica de fora' (Test-TIUserFolderExcluded -Name 'x' -Sid 'S-1-5-18') $true
Assert-Equal 'usuários: conta comum entra' (Test-TIUserFolderExcluded -Name 'ana' -Sid 'S-1-5-21-1-2-3-1001') $false

# --- Programas offline (06-Windows.ps1) ---------------------------------------------
Assert-Equal 'prog: pasta pelo ícone' (Get-TIProgramFolder -DisplayIcon 'C:\Program Files\Notepad++\notepad++.exe' -Drive 'D:').Folder 'D:\Program Files\Notepad++'
Assert-Equal 'prog: msiexec não dá pasta' (Get-TIProgramFolder -UninstallString 'MsiExec.exe /X{ABC}' -DisplayIcon 'C:\Windows\Installer\{ABC}\i.exe' -Drive 'D:').Folder ''
Assert-Equal 'prog: comando com espaço sem aspas' (Get-TIExePathFromCommand 'C:\Program Files\App X\uninst.exe /S') 'C:\Program Files\App X\uninst.exe'
Assert-Equal 'prog: VC++ protegido' (Get-TIProgramProtection 'Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.38.33130') 'runtime essencial (Visual C++)'
Assert-Equal 'prog: .NET protegido' (Get-TIProgramProtection 'Microsoft .NET Runtime - 8.0.1 (x64)') 'runtime essencial (.NET)'
Assert-Equal 'prog: Paint.NET não é .NET' (Get-TIProgramProtection 'paint.net') ''
Assert-Equal 'prog: WebView2 protegido' (Get-TIProgramProtection 'Microsoft Edge WebView2 Runtime') 'runtime essencial (WebView2)'
Assert-True  'prog: antivírus pelo editor' ([bool](Get-TIProgramProtection 'Free Antivirus' 'Avast Software'))
Assert-Equal 'prog: "reset" não é ESET' (Get-TIProgramProtection 'Reset Tool' 'Acme') ''
$e = ConvertFrom-TIUninstallEntry -Values @{ DisplayName = 'VLC media player'; DisplayVersion = '3.0.20'; Publisher = 'VideoLAN'; InstallLocation = 'C:\Program Files\VideoLAN\VLC' } -KeyName 'VLC media player' -Drive 'D:'
Assert-Equal 'prog: entrada lida' ('{0}|{1}|{2}' -f $e.Name, $e.Version, $e.Folder) 'VLC media player|3.0.20|D:\Program Files\VideoLAN\VLC'
Assert-True  'prog: componente do sistema some' ($null -eq (ConvertFrom-TIUninstallEntry -Values @{ DisplayName = 'X'; SystemComponent = 1 }))
Assert-True  'prog: atualização some' ($null -eq (ConvertFrom-TIUninstallEntry -Values @{ DisplayName = 'Security Update for Microsoft Office (KB123456)' }))
Assert-Equal 'prog: código MSI' (ConvertFrom-TIUninstallEntry -Values @{ DisplayName = 'App'; WindowsInstaller = 1 } -KeyName '{12345678-90ab-CDEF-1234-567890ABCDEF}').ProductCode '{12345678-90AB-CDEF-1234-567890ABCDEF}'
Assert-Equal 'prog: GUID empacotado' (ConvertTo-TIPackedGuid '{12345678-90AB-CDEF-1234-567890ABCDEF}') '87654321BA09FEDC2143658709BADCFE'
Assert-Equal 'prog: pasta apagável' (Test-TIRemovableProgramFolder -Folder 'D:\Program Files\VideoLAN\VLC' -Root 'D:\') ''
Assert-Equal 'prog: raiz de Program Files nunca' (Test-TIRemovableProgramFolder -Folder 'D:\Program Files' -Root 'D:\') 'pasta raiz'
Assert-Equal 'prog: Common Files nunca' (Test-TIRemovableProgramFolder -Folder 'D:\Program Files\Common Files\Vendor' -Root 'D:\') 'pasta do Windows ou compartilhada'
Assert-Equal 'prog: ProgramData\Microsoft nunca' (Test-TIRemovableProgramFolder -Folder 'D:\ProgramData\Microsoft\Windows' -Root 'D:\') 'pasta do Windows ou compartilhada'
Assert-Equal 'prog: Windows nunca' (Test-TIRemovableProgramFolder -Folder 'D:\Windows\System32' -Root 'D:\') 'fora das pastas de programas'
Assert-Equal 'prog: ..\ no caminho' (Test-TIRemovableProgramFolder -Folder 'D:\Program Files\X\..\..\Windows' -Root 'D:\') 'caminho inválido'
Assert-Equal 'prog: AppData\Local\Programs do usuário' (Test-TIRemovableProgramFolder -Folder 'D:\Users\ana\AppData\Local\Programs\App' -Root 'D:\') ''
Assert-Equal 'prog: outra unidade' (Test-TIRemovableProgramFolder -Folder 'E:\Program Files\X' -Root 'D:\') 'pasta fora da unidade do Windows'
Assert-Equal 'prog: pasta compartilhada (contém)' (Test-TIFolderShared -Folder 'D:\Program Files\A' -Others @('D:\Program Files\A\B')) $true
Assert-Equal 'prog: pasta com prefixo parecido não é compartilhada' (Test-TIFolderShared -Folder 'D:\Program Files\A' -Others @('D:\Program Files\AB')) $false
$lnk = New-Object byte[] 200
$u = [Text.Encoding]::Unicode.GetBytes('C:\Program Files\VideoLAN\VLC\vlc.exe'); [Array]::Copy($u, 0, $lnk, 81, $u.Length)
Assert-Equal 'prog: atalho aponta para a pasta (outra letra)' (Test-TILnkPointsTo -Bytes $lnk -Folder 'D:\Program Files\VideoLAN\VLC') $true
Assert-Equal 'prog: atalho de outra pasta' (Test-TILnkPointsTo -Bytes $lnk -Folder 'D:\Program Files\VideoLAN\VL') $false

# --- Recuperação (Recuperacao.ps1) -----------------------------------------------------
$okKey = (@(11, 22, 720885, 11000, 55000, 135795, 440000, 77) | ForEach-Object { '{0:000000}' -f $_ }) -join '-'
Assert-Equal 'bitlocker: chave com hífens' (Get-TIRecoveryKeyError $okKey) ''
Assert-Equal 'bitlocker: chave sem hífens' (ConvertTo-TIRecoveryKey ($okKey -replace '-', '')) $okKey
Assert-Equal 'bitlocker: chave com espaços' (ConvertTo-TIRecoveryKey ($okKey -replace '-', ' ')) $okKey
Assert-Equal 'bitlocker: poucos números' (Get-TIRecoveryKeyError '123') 'A chave tem 48 números; foram digitados 3.'
Assert-Equal 'bitlocker: grupo que não é múltiplo de 11' (Get-TIRecoveryKeyError ('000012' + $okKey.Substring(6))) 'O grupo 1 não confere: confira a digitação.'
Assert-True  'bitlocker: letra na chave' ([bool](Get-TIRecoveryKeyError ($okKey -replace '1', 'a')))
Assert-Equal 'bitlocker: inválida não normaliza' (ConvertTo-TIRecoveryKey 'abc') ''
Assert-Equal 'laudo: nome' (Get-TIRecoveryLaudoName -Computer 'LAB-01' -When ([datetime]'2026-10-05 14:30')) 'recuperacao-LAB-01-20261005-1430.txt'
Assert-Equal 'laudo: nome do PC limpo' (Get-TIRecoveryLaudoName -Computer ' PC/2: x ' -When ([datetime]'2026-01-02 03:04')) 'recuperacao-PC_2_x-20260102-0304.txt'
Assert-Equal 'chkdsk 0' (Get-TIChkdskResult 0).Level 'Success'
Assert-Equal 'chkdsk 1: corrigido' (Get-TIChkdskResult 1).Ok $true
Assert-Equal 'chkdsk 3: para o reparo automático' (Get-TIChkdskResult 3).Stop $true
Assert-Equal 'chkdsk -1: não terminou' (Get-TIChkdskResult -1).Level 'Error'
Assert-Equal 'sfc: sem violações (pt)' (Get-TISfcResult 0 'A Proteção de Recursos do Windows não encontrou nenhuma violação de integridade.').Kind 'clean'
Assert-Equal 'sfc: não corrigiu alguns' (Get-TISfcResult 0 'A Proteção de Recursos do Windows encontrou arquivos corrompidos, mas não pôde corrigir alguns deles.').Kind 'partial'
Assert-Equal 'sfc: reparou (en)' (Get-TISfcResult 0 'Windows Resource Protection found corrupt files and successfully repaired them.').Kind 'repaired'
Assert-Equal 'sfc: reparo pendente' (Get-TISfcResult 0 'Há um reparo do sistema pendente que exige reinicialização para ser concluído.').Kind 'pending'
Assert-Equal 'dism: repositório reparável' (Get-TIDismResult 0 'The component store is repairable.').Kind 'repairable'
Assert-Equal 'dism: não reparável' (Get-TIDismResult 0 'The component store cannot be repaired.').Ok $false
Assert-True  'dism: 0x800f081f explicado' ((Get-TIDismCodeText -2146498529) -match 'mesma versão')
Assert-Equal 'dism: erro 87' (Get-TIDismCodeText 87) 'Falha do DISM (erro 87): opção não reconhecida para esta versão do Windows.'
Assert-Equal 'dism: 0x80070070 vira erro 112' (Get-TIDismCodeText -2147024784) 'Falha do DISM (erro 112): sem espaço em disco: libere espaço no disco do Windows.'
Assert-Equal 'bcdboot: GPT é UEFI' (Get-TIBcdbootTarget -Firmware 'BIOS' -PartitionStyle 'GPT') 'UEFI'
Assert-Equal 'bcdboot: MBR + BIOS' (Get-TIBcdbootTarget -Firmware 'BIOS' -PartitionStyle 'MBR') 'BIOS'
Assert-Equal 'bcdboot: MBR + UEFI = ALL' (Get-TIBcdbootTarget -Firmware 'UEFI' -PartitionStyle 'MBR') 'ALL'
Assert-Equal 'bcdboot: argumentos' (Get-TIBcdbootArgs -WinDir 'D:\Windows\' -Letter 's' -Target 'uefi' -Locale 'pt-BR') '"D:\Windows" /s S: /f UEFI /l pt-BR'
Assert-Equal 'bcd: caminhos do BCD (ALL)' ((Get-TIBcdStorePaths -Letter 'S' -Target 'ALL') -join '|') 'S:\EFI\Microsoft\Boot\BCD|S:\Boot\BCD'
$bcdTxt = "Windows Boot Loader`r`n-------------------`r`nidentificador           {11111111-2222-3333-4444-555555555555}`r`ndevice                  partition=C:`r`n`r`nWindows Boot Loader`r`n-------------------`r`nidentificador           {66666666-2222-3333-4444-555555555555}`r`ndevice                  partition=D:`r`nresumeobject            {bbbbbbbb-2222-3333-4444-555555555555}`r`nsafeboot                Minimal`r`n"
Assert-Equal 'bcd: entrada do Windows em D:' (Get-TIBcdLoaderInfo -Text $bcdTxt -Drive 'D:').Id '{66666666-2222-3333-4444-555555555555}'
Assert-Equal 'bcd: modo de segurança ligado' (Get-TIBcdLoaderInfo -Text $bcdTxt -Drive 'D:').SafeBoot 'Minimal'
Assert-Equal 'bcd: unidade sem entrada' (Get-TIBcdLoaderInfo -Text $bcdTxt -Drive 'E:').Id ''
Assert-Equal 'letra livre para a partição do sistema' (Select-TIFreeDriveLetter -Used @('C:', 'D:', 'S', 'X:')) 'R:'
$imgs = @([pscustomobject]@{ Path = 'E:\reparo\install.esd'; Index = 6; EditionId = 'Professional'; Build = 19045; Arch = 'x64' },
          [pscustomobject]@{ Path = 'E:\reparo\install.wim'; Index = 1; EditionId = 'Core'; Build = 19045; Arch = 'x64' },
          [pscustomobject]@{ Path = 'E:\reparo\w10b.wim'; Index = 3; EditionId = 'Professional'; Build = 19044; Arch = 'x64' })
Assert-Equal 'reparo: mesma versão e edição' (Select-TIRepairImage -Images $imgs -Build 19045 -EditionId 'Professional' -Arch 'x64').Path 'E:\reparo\install.esd'
Assert-Equal 'reparo: mesma base (19044 x 19045)' (Select-TIRepairImage -Images $imgs[1..2] -Build 19045 -EditionId 'Professional').Index 3
Assert-True  'reparo: outra edição não serve' ($null -eq (Select-TIRepairImage -Images $imgs -Build 19045 -EditionId 'Education'))
Assert-True  'reparo: outra versão não serve' ($null -eq (Select-TIRepairImage -Images $imgs -Build 22631 -EditionId 'Professional'))
Assert-Equal 'reparo: argumento /Source' (Get-TIDismSourceArg -Path 'E:\reparo\install.esd' -Index 6) '/Source:ESD:E:\reparo\install.esd:6'
Assert-Equal 'pacote: KB' (Get-TIPackageDisplayName 'Package_for_KB5034441~31bf3856ad364e35~amd64~~19041.3920.1.1') 'KB5034441'
Assert-Equal 'pacote: cumulativa' (Get-TIPackageDisplayName 'Package_for_RollupFix~31bf3856ad364e35~amd64~~19041.4046.1.6') 'Atualização cumulativa (19041.4046)'
Assert-Equal 'disco: erro de leitura é falha' (Get-TIRecoveryDiskVerdict -Health 'Healthy' -Uncorrected 3).Tone 'crit'
Assert-Equal 'disco: NVMe a 60 °C em ordem' (Get-TIRecoveryDiskVerdict -Health 'Healthy' -Temp 60 -Media 'SSD NVMe').Tone 'ok'
Assert-Equal 'saída: sfc em UTF-16' (Get-TIOutputEncodingKind ([Text.Encoding]::Unicode.GetBytes("`r`nVerifica"))) 'utf16'
Assert-Equal 'saída: chkdsk em OEM' (Get-TIOutputEncodingKind ([Text.Encoding]::ASCII.GetBytes('O tipo do sistema'))) 'oem'
$sg = Split-TIOutputSegments -Text "linha 1`r`n10%`r20%`rlinha 2`nresto"
Assert-Equal 'saída: \r sozinho é progresso' (($sg.Segments | ForEach-Object { '{0}:{1}' -f $_.Text, [int]$_.Cr }) -join '|') 'linha 1:0|10%:1|20%:1|linha 2:0'
Assert-Equal 'saída: resto espera o próximo pedaço' $sg.Rest 'resto'
Assert-Equal 'saída: percentual total do chkdsk' (Get-TIProgressPercent 'Progresso: 1234 de 5678 feitos; Estágio:  18%; Total:  12%; ETA:   0:00:10 ..') 12
Assert-Equal 'recuperação: em execução nunca' (Get-RecuperacaoInstallState ([pscustomobject]@{ Locked = $false; IsRunning = $true })).CanRepair $false
Assert-Equal 'recuperação: BitLocker bloqueado nunca' (Get-RecuperacaoInstallState ([pscustomobject]@{ Locked = $true; IsRunning = $false })).CanRepair $false
$rInst = [pscustomobject]@{ ComputerName = 'LAB-01'; Label = 'Windows 11 Pro 24H2 (26100.2033)'; Drive = 'D:'; WinDir = 'D:\Windows'; Arch = 'x64'; SizeBytes = 256GB; FreeBytes = 40GB }
$rRes = [pscustomobject]@{ Started = [datetime]'2026-10-05 14:31'; Title = 'Reparo automático'; Stopped = $false; StopReason = ''
                           Steps = @([pscustomobject]@{ Level = 'Success'; Name = 'Verificar disco (chkdsk /f)'; Text = 'Nenhum erro' }, [pscustomobject]@{ Level = 'Error'; Name = 'Reparar inicialização (bcdboot)'; Text = 'falhou' }) }
$rTxt = New-RecuperacaoLaudoText -Install $rInst -Actions @($rRes) -Firmware 'UEFI' -Version '1.5.0' -When ([datetime]'2026-10-05 15:00') -WinPE $true
Assert-True  'laudo recuperação: computador' ($rTxt -match 'Computador\s+: LAB-01')
Assert-True  'laudo recuperação: passo OK' ($rTxt -match '\[OK\] Verificar disco \(chkdsk /f\): Nenhum erro')
Assert-True  'laudo recuperação: passo com falha' ($rTxt -match '\[X\]  Reparar inicialização')

# --- Pendrive de recuperação (dev\Criar-Pendrive.ps1: com dot-source só define as funções) ---
. (Join-Path (Join-Path $root 'dev') 'Criar-Pendrive.ps1')
$pd = @(
    [pscustomobject]@{ Number = 0; FriendlyName = 'Samsung SSD 980'; Size = 500GB; BusType = 'NVMe'; IsBoot = $true; IsSystem = $true },
    [pscustomobject]@{ Number = 1; FriendlyName = 'SanDisk Ultra'; Size = 30752636928; BusType = 'USB' },
    [pscustomobject]@{ Number = 2; FriendlyName = 'Kingston 4GB'; Size = 3900000000; BusType = 7 },
    [pscustomobject]@{ Number = 3; FriendlyName = 'WD Elements'; Size = 1TB; BusType = 'USB'; HasRunningWindows = $true },
    [pscustomobject]@{ Number = 4; FriendlyName = 'Leitor SD'; Size = 0; BusType = 'SD' },
    [pscustomobject]@{ Number = 5; FriendlyName = 'Pendrive do projeto'; Size = 16GB; BusType = 'USB'; HasProject = $true },
    [pscustomobject]@{ Number = 6; FriendlyName = 'Cartão travado'; Size = 32GB; BusType = 'SD'; IsReadOnly = $true },
    [pscustomobject]@{ Number = 7; FriendlyName = 'Disco SATA'; Size = 1TB; BusType = 'SATA'; MediaType = 'Fixed hard disk media' },
    [pscustomobject]@{ Number = 8; FriendlyName = 'Pendrive 8 GB'; Size = 7743995904; BusType = 'SCSI'; MediaType = 'Removable Media' })
$pc = @(Get-TIPEDiskCandidates -Disks $pd)
Assert-Equal 'pendrive: elegíveis só USB/removível de 8 GB' (($pc | Where-Object { $_.Eligible } | ForEach-Object { $_.Number }) -join ',') '1,8'
Assert-Equal 'pendrive: disco do sistema (NVMe) não é removível' $pc[0].Code 'notremovable'
Assert-Equal 'pendrive: BusType numérico 7 = USB' $pc[2].BusType 'USB'
Assert-Equal 'pendrive: menor que 8 GB' $pc[2].Code 'small'
Assert-Equal 'pendrive: USB com o Windows em execução nunca' $pc[3].Code 'windows'
Assert-Equal 'pendrive: leitor vazio' $pc[4].Code 'nomedia'
Assert-Equal 'pendrive: disco da pasta do projeto' $pc[5].Code 'project'
Assert-Equal 'pendrive: protegido contra gravação' $pc[6].Code 'readonly'
Assert-Equal 'pendrive: SATA fixo fora' $pc[7].Code 'notremovable'
Assert-Equal 'pendrive: tamanho na tela' $pc[1].SizeText '28,6 GB'
Assert-True  'pendrive: APAGAR confirma' (Test-TIPEConfirmWord '  apagar ')
Assert-True  'pendrive: outra palavra cancela' (-not (Test-TIPEConfirmWord 'sim'))
Assert-Equal 'pendrive: letras livres' ((Get-TIPEFreeLetters -Used @('C', 'D:', 'E:\', 'f') -Count 2) -join ',') 'G,H'
Assert-Equal 'pendrive: sem X para o Windows PE' ((Get-TIPEFreeLetters -Used ([char[]]'CDEFGHIJKLMNOPQRSTUVW' | ForEach-Object { [string]$_ }) -Count 2) -join ',') 'Y,Z'
$dp = Get-TIPEDiskpartScript -DiskNumber 3 -BootLetter 'R' -DataLetter 'S' -FileSystem 'exFAT'
Assert-Equal 'diskpart: disco certo' $dp[0] 'select disk 3'
Assert-True  'diskpart: clean sem noerr' (($dp -contains 'clean') -and -not ($dp -match 'noerr'))
Assert-True  'diskpart: TI-BOOT FAT32 2 GB ativa' (($dp -contains 'create partition primary size=2048') -and ($dp -contains 'format fs=fat32 quick label="TI-BOOT"') -and ($dp -contains 'active'))
Assert-True  'diskpart: TI-SUITE exFAT' ($dp -contains 'format fs=exfat quick label="TI-SUITE"')
Assert-True  'diskpart: letra só depois de formatar' ([array]::IndexOf($dp, 'assign letter=R') -gt [array]::IndexOf($dp, 'format fs=fat32 quick label="TI-BOOT"'))
# robustez em pendrive lento: cria as duas partições e dá rescan ANTES de formatar, com seleção explícita
Assert-True  'diskpart: rescan antes do format' ([array]::IndexOf($dp, 'rescan') -gt [array]::IndexOf($dp, 'create partition primary') -and [array]::IndexOf($dp, 'rescan') -lt [array]::IndexOf($dp, 'format fs=fat32 quick label="TI-BOOT"'))
Assert-True  'diskpart: seleciona a partição antes de formatar' (($dp -contains 'select partition 1') -and ($dp -contains 'select partition 2'))
Assert-True  'diskpart: as duas partições criadas antes do rescan' ([array]::IndexOf($dp, 'rescan') -gt [array]::LastIndexOf($dp, 'create partition primary'))
$sn = New-TIPEStartnet
$snText = $sn -join "`n"
Assert-Equal 'startnet: wpeinit primeiro' (@($sn | Where-Object { $_ -and $_ -notmatch '^(@echo|rem )' })[0]) 'wpeinit'
Assert-True  'startnet: abre com -Recovery' ($snText -match [regex]::Escape('"%TIPS%" -NoProfile -STA -ExecutionPolicy Bypass -File "%TIDRV%\TI-Suite.ps1" -Recovery'))
Assert-True  'startnet: PowerShell do WinPE' ($snText -match [regex]::Escape('X:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'))
Assert-True  'startnet: exige portable.config' ($snText -match 'if exist "%%L:\\TI-Suite\.ps1" if exist "%%L:\\portable\.config"')
Assert-True  'startnet: menu reinicia e desliga' (($snText -match 'wpeutil reboot') -and ($snText -match 'wpeutil shutdown'))
Assert-True  'startnet: só ASCII' ($snText -match '^[\x00-\x7F]*$')
Assert-True  'startnet: não procura em X:' ($snText -notmatch '\bW X Y\b')
$ocs = @('WinPE-WMI.cab', 'WinPE-NetFx.cab', 'WinPE-Scripting.cab', 'WinPE-PowerShell.cab', 'WinPE-StorageWMI.cab', 'WinPE-DismCmdlets.cab',
         'WinPE-SecureStartup.cab', 'WinPE-EnhancedStorage.cab', 'WinPE-HTA.cab', 'pt-br\lp.cab', 'pt-br\WinPE-WMI_pt-br.cab', 'en-us\WinPE-WMI_en-us.cab',
         'pt-br\WinPE-PowerShell_pt-br.cab')
$pp = Get-TIPEPackagePlan -Available $ocs
Assert-Equal 'WinPE: lp.cab primeiro' $pp.Packages[0] 'pt-br\lp.cab'
Assert-Equal 'WinPE: componente seguido dos idiomas' (($pp.Packages[1..3]) -join ',') 'WinPE-WMI.cab,en-us\WinPE-WMI_en-us.cab,pt-br\WinPE-WMI_pt-br.cab'
Assert-Equal 'WinPE: 8 componentes + idiomas' $pp.Packages.Count 12
Assert-True  'WinPE: só os componentes do contrato' (-not ($pp.Packages -contains 'WinPE-HTA.cab'))
Assert-Equal 'WinPE: sem falta' $pp.Missing.Count 0
$pp2 = Get-TIPEPackagePlan -Available @('winpe-wmi.cab')
Assert-Equal 'WinPE: falta componente' $pp2.Missing.Count 7
Assert-Equal 'WinPE: sem pacote pt-br' $pp2.LanguagePack $false
$hf = @{ 'Segoe UI Bold (TrueType)' = 'segoeuib.ttf'; 'Consolas (TrueType)' = 'C:\Windows\Fonts\consola.ttf' }
Assert-Equal 'fonte: nome do Windows' (Get-TIPEFontValueName -FileName 'SEGOEUIB.TTF' -HostFonts $hf) 'Segoe UI Bold (TrueType)'
Assert-Equal 'fonte: caminho completo no registro' (Get-TIPEFontValueName -FileName 'consola.ttf' -HostFonts $hf) 'Consolas (TrueType)'
Assert-Equal 'fonte: sem registro' (Get-TIPEFontValueName -FileName 'segmdl2.ttf' -HostFonts @{}) 'segmdl2 (TrueType)'
Assert-True  'cópia: código vai' (-not (Test-TIPEAppExcluded 'src\Core\01-Theme.ps1'))
Assert-True  'cópia: TI-Suite.ps1 e portable.config vão' (-not (Test-TIPEAppExcluded 'TI-Suite.ps1') -and -not (Test-TIPEAppExcluded 'portable.config'))
foreach ($x in @('dev\Test-Logic.ps1', 'dist\TI-Suite-v1.5.0.zip', '.git\HEAD', '.gitignore', 'TI-Suite-v1.4.0-fonte.zip', 'Criar-Pendrive.cmd',
                 'logs\audit.csv', 'inventario\inventario.csv', 'wifi\ESCOLA.xml', 'Backup-TI\PC\x.txt', 'reparo\install.wim', 'config.json',
                 'manifest.sha256', 'bin\TISuite.Controls.dll', '.vscode\settings.json')) {
    Assert-True ('cópia: fica de fora ' + $x) (Test-TIPEAppExcluded $x)
}
Assert-True  'cópia: config.json só na raiz' (Test-TIPEAppExcluded 'config.json')
$rp = @(Get-TIPERestorePlan -Folders @('F:\Ferramentas\TI-Suite', 'E:\'))
Assert-Equal 'dados: a raiz volta para a raiz' $rp[0].Source 'E:\'
Assert-Equal 'dados: raiz sem subpasta' $rp[0].Target ''
Assert-Equal 'dados: outra pasta em dados-anteriores' $rp[1].Target 'dados-anteriores\F_Ferramentas_TI-Suite'
Assert-True  'dados: inclui backup, reparo e config.json' ((Get-TIPEFieldItems).Dirs -contains 'reparo' -and (Get-TIPEFieldItems).Dirs -contains 'backup' -and (Get-TIPEFieldItems).Files -contains 'config.json')
Assert-Equal 'trabalho: %TEMP% normal' (Get-TIPEWorkRoot -Temp 'C:\Users\ana\AppData\Local\Temp' -Id 'ab') 'C:\Users\ana\AppData\Local\Temp\TI-PE-ab'
Assert-Equal 'trabalho: %TEMP% com acento' (Get-TIPEWorkRoot -Temp 'C:\Users\João\AppData\Local\Temp' -SystemDrive 'C:' -Id 'ab') 'C:\TI-PE-ab'
Assert-Equal 'trabalho: %TEMP% com &' (Get-TIPEWorkRoot -Temp 'C:\Users\P&D\Temp' -SystemDrive 'D:' -Id 'ab') 'D:\TI-PE-ab'
$ra = Get-TIPERelaunchArgs -Bound @{ SomenteISO = [System.Management.Automation.SwitchParameter]$true; Disco = 2; Drivers = 'C:\Meus Drivers\'; Boot2023 = [System.Management.Automation.SwitchParameter]$false }
Assert-Equal 'reabrir: mesmas opções' ($ra -join '|') '-Disco|2|-Drivers|C:\Meus Drivers|-SomenteISO'
Assert-True  'DISM: barra de progresso' (Test-TIPEProgressLine '[==========================100.0%==========================]')
Assert-True  'DISM: linha normal' (-not (Test-TIPEProgressLine 'A operação foi concluída com êxito.'))
Assert-True  'robocopy: 3 ok, 8 falha' ((Test-TIPERobocopyOk 3) -and -not (Test-TIPERobocopyOk 8))
Assert-Equal 'aspas simples' (ConvertTo-TIPEQuoted "C:\D'Avila\x.cs") "'C:\D''Avila\x.cs'"
$adk = Get-TIPEAdkLayout -KitsRoot 'C:\Program Files (x86)\Windows Kits\10\'
Assert-Equal 'ADK: winpe.wim' $adk.WinpeWim 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us\winpe.wim'
Assert-Equal 'ADK: bootsect' $adk.Bootsect 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\BCDBoot\bootsect.exe'
$lm = New-TIPELeiaMe -StampLine 'Criado em 05/10/2026' -BootLine (Get-TIPEBootText -Boot2023 $false)
Assert-True  'LEIA-ME: reparo não reinstala' ($lm -match 'NÃO reinstala o Windows')
Assert-True  'LEIA-ME: teclas de boot' (($lm -match 'F12') -and ($lm -match 'Esc e depois F9'))
Assert-True  'LEIA-ME: CRLF' (($lm -split "`r`n").Count -gt 20 -and $lm -notmatch "[^`r]`n")
Assert-Equal 'LEIA-ME: linha do boot volta na atualização' (Get-TIPEBootLine $lm) (Get-TIPEBootText -Boot2023 $false)
Assert-Equal 'BusType desconhecido' (ConvertTo-TIPEBusType 99) 'Desconhecido'

# --- Desinstalação em lote: pastas, runtime/segurança e resumo -------------------
Assert-True  'inside: subpasta'        (Test-TIPathInside 'C:\Program Files\App\bin\x.exe' 'C:\Program Files\App')
Assert-True  'inside: a própria pasta' (Test-TIPathInside 'C:\Program Files\App' 'C:\Program Files\App')
Assert-True  'inside: maiúsc./barra'   (Test-TIPathInside 'c:/PROGRAM files/app/X.EXE' 'C:\Program Files\App')
Assert-Equal 'inside: não confunde App2' (Test-TIPathInside 'C:\Program Files\App2\x.exe' 'C:\Program Files\App') $false
Assert-Equal 'inside: vazio'           (Test-TIPathInside '' 'C:\App') $false
Assert-True  'kill: pasta de programa' (Test-TIKillableFolder 'C:\Program Files\App')
Assert-Equal 'kill: recusa raiz PF'    (Test-TIKillableFolder 'C:\Program Files') $false
Assert-Equal 'kill: recusa raiz drive' (Test-TIKillableFolder 'C:\') $false
Assert-Equal 'kill: recusa Windows'    (Test-TIKillableFolder 'C:\Windows\System32\x') $false
Assert-Equal 'kill: recusa WindowsApps' (Test-TIKillableFolder 'C:\Program Files\WindowsApps\Foo') $false
Assert-Equal 'pasta: InstallLocation'  (Get-TIAppFolder -InstallLocation 'C:\Program Files\App\') 'C:\Program Files\App'
Assert-Equal 'pasta: UninstallString'  (Get-TIAppFolder -Uninstall '"C:\Program Files\App\unins000.exe" /x') 'C:\Program Files\App'
Assert-Equal 'pasta: DisplayIcon'      (Get-TIAppFolder -Icon 'C:\Program Files\App\app.exe,0') 'C:\Program Files\App'
Assert-Equal 'pasta: MSI sem pasta'    (Get-TIAppFolder -Uninstall 'MsiExec.exe /X{G}') ''
Assert-True  'segurança: Kaspersky'    (Test-TISecurityProduct 'Kaspersky Free' 'AO Kaspersky Lab')
Assert-True  'segurança: ESET'         (Test-TISecurityProduct 'ESET NOD32 Antivirus' 'ESET')
Assert-True  'segurança: AVG'          (Test-TISecurityProduct 'AVG AntiVirus FREE' 'AVG Technologies')
Assert-Equal 'segurança: não trava Chrome' (Test-TISecurityProduct 'Google Chrome' 'Google LLC') $false
Assert-True  'runtime: VC++ Redist'    (Test-TIEssentialRuntime 'Microsoft Visual C++ 2015-2022 Redistributable (x64)' 'Microsoft')
Assert-True  'runtime: .NET Runtime'   (Test-TIEssentialRuntime 'Microsoft .NET Runtime - 8.0.4 (x64)' 'Microsoft')
Assert-True  'runtime: WebView2'       (Test-TIEssentialRuntime 'Microsoft Edge WebView2 Runtime' 'Microsoft')
Assert-True  'runtime: Windows App Runtime' (Test-TIEssentialRuntime 'Windows App Runtime 1.4' 'Microsoft')
Assert-Equal 'runtime: não trava 7-Zip' (Test-TIEssentialRuntime '7-Zip 23.01' 'Igor Pavlov') $false
Assert-Equal 'trava: motivo segurança' (Get-TIAppBatchLock 'Avast Free Antivirus' 'Avast').Reason 'use a ferramenta oficial do fabricante'
Assert-Equal 'trava: motivo runtime'   (Get-TIAppBatchLock '.NET Framework 4.8' 'Microsoft').Reason 'outros programas dependem dele'
Assert-Equal 'trava: programa comum livre' (Get-TIAppBatchLock 'Notepad++' 'Notepad++ Team').Locked $false
$sr = @(
    [pscustomobject]@{ Name = 'A'; Status = 'removed';   Reboot = $false; Message = '' },
    [pscustomobject]@{ Name = 'B'; Status = 'removed';   Reboot = $true;  Message = '' },
    [pscustomobject]@{ Name = 'C'; Status = 'failed';    Reboot = $false; Message = 'erro X' },
    [pscustomobject]@{ Name = 'D'; Status = 'cancelled'; Reboot = $false; Message = '' }
)
$st = Get-TIUninstallSummaryText -Results $sr
Assert-True 'resumo: desinstalados'      ($st -match 'Desinstalados: 2')
Assert-True 'resumo: reinício pendente'  ($st -match 'B \(reinício pendente\)')
Assert-True 'resumo: motivo da falha'    ($st -match 'C: erro X')
Assert-True 'resumo: cancelados'         ($st -match 'Cancelados: 1')

Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ('Regras: {0} testes aprovados.' -f $script:pass) -ForegroundColor Green
    exit 0
}
Write-Host ('Regras: {0} de {1} testes falharam.' -f $script:fail, ($script:pass + $script:fail)) -ForegroundColor Red
exit 1
