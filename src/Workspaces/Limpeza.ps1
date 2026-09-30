# =====================================================================
# ÁREA: MANUTENÇÃO - perfis de usuários, limpeza profunda e manutenção em um passo
# =====================================================================

# ---------------------------------------------------------------------
# Perfis de usuários (funções do worker)
# Lista todos os perfis do Windows e decide quais podem ser apagados.
# Nunca apagáveis: Público, Default e perfis do sistema; contas locais
# deste computador; administradores (diretos, por grupo do domínio ou
# porque todos os usuários são administradores); perfis em uso e o da conta
# que está rodando o TI Suite. Na dúvida (não deu para confirmar se a conta
# é administradora), o perfil fica protegido. O resto pode ser apagado.
# ---------------------------------------------------------------------
$global:TIWorkerLib += @'

function Get-TIMachineSid {
    try {
        $u = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID }) | Select-Object -First 1
        if ($u -and $u.SID.AccountDomainSid) { return [string]$u.SID.AccountDomainSid.Value }
    } catch { }
    try {
        $comp = [ADSI]('WinNT://{0},computer' -f $env:COMPUTERNAME)
        foreach ($c in $comp.Children) {
            if ($c.SchemaClassName -ne 'User') { continue }
            $sid = New-Object System.Security.Principal.SecurityIdentifier(([byte[]]$c.objectSid.Value), 0)
            if ($sid.AccountDomainSid) { return [string]$sid.AccountDomainSid.Value }
        }
    } catch { }
    return ''
}

function Test-TILocalSid {
    param([string]$Sid, [string]$MachineSid)
    if (-not $Sid -or -not $MachineSid) { return $false }
    return $Sid.StartsWith($MachineSid + '-', [System.StringComparison]::OrdinalIgnoreCase)
}

# Regra pura (sem acesso ao sistema): testada em dev\Test-Logic.ps1.
# IsAdmin: $true / $false / $null (não deu para confirmar = protegido).
function Get-TIProfileVerdict {
    param(
        [string]$Sid,
        [string]$Path,
        [bool]$Special = $false,
        [bool]$Loaded = $false,
        [string]$MachineSid = '',
        $AdminSids = $null,
        [string]$CurrentSid = '',
        $IsAdmin = $false
    )
    $leaf = ([string](Split-Path -Leaf ([string]$Path))).ToLowerInvariant()
    $kind = if ($Sid -like 'S-1-12-1-*') { 'Azure AD' } else { 'Rede' }
    $reason = ''
    if ($Special -or ($Sid -notlike 'S-1-5-21-*' -and $Sid -notlike 'S-1-12-1-*')) { $kind = 'Sistema'; $reason = 'perfil do sistema' }
    elseif (@('public', 'default', 'default user', 'all users') -contains $leaf) { $kind = 'Sistema'; $reason = 'pasta do sistema (Público/Default)' }
    elseif (-not $MachineSid) { $kind = '?'; $reason = 'não deu para identificar as contas locais' }
    elseif (Test-TILocalSid -Sid $Sid -MachineSid $MachineSid) { $kind = 'Local'; $reason = 'conta local deste computador' }
    elseif ($CurrentSid -and $Sid -eq $CurrentSid) { $reason = 'conta que está usando o TI Suite' }
    elseif ($Loaded) { $reason = 'em uso (usuário conectado)' }
    elseif ($null -eq $AdminSids) { $reason = 'não deu para ler o grupo Administradores' }
    elseif ($AdminSids.ContainsKey($Sid)) { $reason = 'administrador' }
    elseif ($IsAdmin -eq $true) { $reason = 'administrador (por grupo)' }
    elseif ($null -eq $IsAdmin) { $reason = 'não deu para confirmar se é administrador' }
    return [pscustomobject]@{ Kind = $kind; Protected = ($reason -ne ''); Reason = $reason }
}

# Quem é administrador neste PC: membros do grupo Administradores (S-1-5-32-544),
# grupos de fora do PC (domínio/Azure) e grupos que valem para todo mundo.
# AdminSids fica $null quando não dá para ler (falha fechada: nada apagável).
function Get-TIAdminContext {
    $ctx = [pscustomobject]@{
        AdminSids = $null; DomainGroups = @(); AzureGroups = $false; EveryoneAdmin = $false
        MachineSid = (Get-TIMachineSid); CurrentSid = ''
    }
    try { $ctx.CurrentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { }
    $members = Get-TIAdminMembers
    if ($null -eq $members) { return $ctx }
    $set = @{}
    $groups = New-Object System.Collections.ArrayList
    foreach ($m in @($members)) {
        if (-not $m.Sid) { return $ctx }   # membro sem SID lido: não dá para confiar na lista
        $sid = [string]$m.Sid
        $set[$sid] = $true
        # Todos, Interativo, Usuários autenticados, Rede: qualquer conta é administradora
        if (@('S-1-1-0', 'S-1-5-4', 'S-1-5-11', 'S-1-5-2') -contains $sid) { $ctx.EveryoneAdmin = $true; continue }
        if ($sid -like 'S-1-5-32-*' -or (Test-TILocalSid -Sid $sid -MachineSid $ctx.MachineSid)) { continue }
        if ($sid -like 'S-1-5-21-*') { [void]$groups.Add($sid) }
        elseif ($sid -like 'S-1-12-1-*') { $ctx.AzureGroups = $true }
    }
    $ctx.AdminSids = $set
    $ctx.DomainGroups = $groups.ToArray()
    return $ctx
}

# Grupos que o Windows guardou do último login do usuário (Política de Grupo).
# Inclui os aninhados e o próprio BUILTIN\Administradores quando ele era admin.
# $null = não há registro (o usuário nunca entrou com a política do domínio).
function Get-TIGroupCache {
    param([string]$Sid)
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\{0}\GroupMembership' -f $Sid
    try {
        if (-not (Test-Path -LiteralPath $key)) { return $null }
        $p = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        $n = [int]$p.Count
        if ($n -le 0) { return $null }
        $out = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $n; $i++) {
            $v = $p.('Group' + $i)
            if ($v) { [void]$out.Add([string]$v) }
        }
        return ,($out.ToArray())
    } catch { return $null }
}

# Membros (em qualquer nível) dos grupos do domínio que estão em Administradores.
# Uma consulta por grupo. Ok = $false quando não deu para perguntar ao domínio
# (sem rede, ou o app aberto com conta local, que não entra no domínio).
function Get-TINestedAdminMap {
    param([string[]]$GroupSids, [int]$TimeoutMs = 20000)
    $res = [pscustomobject]@{ Ok = $false; Admins = @{} }
    $GroupSids = @($GroupSids | Where-Object { $_ -like 'S-1-5-21-*' })
    if ($GroupSids.Count -eq 0) { $res.Ok = $true; return $res }
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($groups)
        $ErrorActionPreference = 'Stop'
        $admins = @{}
        try {
            foreach ($gs in $groups) {
                $g = New-Object System.DirectoryServices.DirectoryEntry(('LDAP://<SID={0}>' -f $gs))
                try {
                    $dn = $null
                    try { $dn = [string]$g.Properties['distinguishedName'].Value }
                    catch {
                        $code = 0
                        $ex = $_.Exception
                        while ($ex) { if ($ex -is [System.Runtime.InteropServices.COMException]) { $code = $ex.ErrorCode; break }; $ex = $ex.InnerException }
                        # 0x80072030: conta ou grupo que não existe mais no domínio (SID órfão): sem membros
                        if ($code -eq -2147016656) { continue }
                        throw
                    }
                    if (-not $dn) { throw ('O domínio não informou o grupo {0}.' -f $gs) }
                    $domDn = (@($dn -split '(?<!\\),' | Where-Object { $_ -like 'DC=*' })) -join ','
                    $esc = $dn.Replace('\', '\5c').Replace('*', '\2a').Replace('(', '\28').Replace(')', '\29')
                    $root = New-Object System.DirectoryServices.DirectoryEntry(('LDAP://{0}' -f $domDn))
                    $ds = New-Object System.DirectoryServices.DirectorySearcher($root)
                    # 1.2.840.113556.1.4.1941 = membro em qualquer nível de aninhamento
                    $ds.Filter = ('(memberOf:1.2.840.113556.1.4.1941:={0})' -f $esc)
                    $ds.PageSize = 500
                    [void]$ds.PropertiesToLoad.Add('objectSid')
                    $found = $ds.FindAll()
                    try {
                        foreach ($r in $found) {
                            $b = $r.Properties['objectsid']
                            if ($b -and $b.Count -gt 0) {
                                $admins[(New-Object System.Security.Principal.SecurityIdentifier(([byte[]]$b[0]), 0)).Value] = $true
                            }
                        }
                    } finally { $found.Dispose(); $ds.Dispose(); $root.Dispose() }
                } finally { $g.Dispose() }
            }
            [pscustomobject]@{ Ok = $true; Admins = $admins }
        } catch {
            [pscustomobject]@{ Ok = $false; Admins = @{} }
        }
    }).AddArgument($GroupSids)
    try {
        $h = $ps.BeginInvoke()
        if ($h.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            foreach ($x in @($ps.EndInvoke($h))) { if ($x -and $x.PSObject.Properties['Ok']) { $res = $x } }
            $ps.Dispose()
        } else {
            # sem resposta: não espera a consulta presa (Dispose bloquearia)
            try { [void]$ps.BeginStop($null, $null) } catch { }
        }
    } catch { }
    return $res
}

# $true / $false / $null para uma conta de rede (fora deste PC).
# -Cache: grupos do último login (padrão: lê do registro; os testes passam à mão).
function Get-TIProfileAdminState {
    param([string]$Sid, $Ctx, $Nested, $Cache = 'registro')
    if ($null -eq $Ctx.AdminSids) { return $null }
    if ($Ctx.AdminSids.ContainsKey($Sid) -or $Ctx.EveryoneAdmin) { return $true }
    if ($Cache -is [string] -and $Cache -eq 'registro') { $Cache = Get-TIGroupCache -Sid $Sid }
    foreach ($g in @($Cache)) { if ($g -and ($g -eq 'S-1-5-32-544' -or $Ctx.AdminSids.ContainsKey([string]$g))) { return $true } }
    $isDomain = ($Sid -like 'S-1-5-21-*')
    # grupos de fora do PC que poderiam conter esta conta
    $relevant = if ($isDomain) { ($Ctx.DomainGroups.Count -gt 0 -or $Ctx.AzureGroups) } else { $Ctx.AzureGroups }
    if (-not $relevant) { return $false }
    $asked = ($isDomain -and $Ctx.DomainGroups.Count -gt 0 -and $Nested -and $Nested.Ok)
    if ($asked -and $Nested.Admins.ContainsKey($Sid)) { return $true }
    # o domínio respondeu e não há grupos do Azure: resposta definitiva
    if ($asked -and -not $Ctx.AzureGroups) { return $false }
    # sem resposta: vale o que o Windows guardou do último login; sem isso, na dúvida protege
    if (@($Cache | Where-Object { $_ }).Count -gt 0) { return $false }
    return $null
}

# Último uso real: último login/logoff guardado no ProfileList. O LastUseTime do
# WMI muda quando antivírus e backup leem a pasta e engana o "sem uso há X dias".
function Get-TIProfileLastUse {
    param([string]$Sid, $Fallback)
    $best = $null
    try {
        $p = Get-ItemProperty -LiteralPath ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\{0}' -f $Sid) -ErrorAction Stop
        foreach ($pair in @(@('LocalProfileLoadTimeHigh', 'LocalProfileLoadTimeLow'), @('LocalProfileUnloadTimeHigh', 'LocalProfileUnloadTimeLow'))) {
            $hi = $p.($pair[0]); $lo = $p.($pair[1])
            if ($null -eq $hi -or $null -eq $lo) { continue }
            $h = [int64][BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$hi), 0)
            $l = [int64][BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$lo), 0)
            $ft = $h * 4294967296 + $l
            if ($ft -le 0) { continue }
            $dt = [datetime]::FromFileTime($ft)
            if (-not $best -or $dt -gt $best) { $best = $dt }
        }
    } catch { }
    if ($best) { return $best }
    return $Fallback
}

function Get-TIUserProfiles {
    Emit 'Lendo os perfis de usuário do computador...' 'Info'
    $ctx = Get-TIAdminContext
    if ($null -eq $ctx.AdminSids) { Emit 'Não foi possível ler o grupo Administradores: nenhum perfil pode ser apagado agora.' 'Warn' }
    if (-not $ctx.MachineSid) { Emit 'Não foi possível identificar as contas locais: nenhum perfil pode ser apagado agora.' 'Warn' }
    if ($ctx.EveryoneAdmin) { Emit 'O grupo Administradores inclui todos os usuários: nenhum perfil de rede pode ser apagado.' 'Warn' }

    $all = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object { $_.LocalPath } | Sort-Object LocalPath)

    # 1ª passada: regras locais. Só as contas de rede que sobraram precisam do domínio.
    $pending = @{}
    foreach ($p in $all) {
        $v0 = Get-TIProfileVerdict -Sid $p.SID -Path $p.LocalPath -Special ([bool]$p.Special) -Loaded ([bool]$p.Loaded) `
                                   -MachineSid $ctx.MachineSid -AdminSids $ctx.AdminSids -CurrentSid $ctx.CurrentSid
        if (-not $v0.Protected) { $pending[[string]$p.SID] = $true }
    }
    $nested = $null
    if ($ctx.DomainGroups.Count -gt 0 -and @($pending.Keys | Where-Object { $_ -like 'S-1-5-21-*' }).Count -gt 0) {
        Emit 'Conferindo no servidor do domínio quem é administrador...' 'Info'
        $nested = Get-TINestedAdminMap -GroupSids $ctx.DomainGroups
        if (-not $nested.Ok) {
            $why = if (Test-TILocalSid -Sid $ctx.CurrentSid -MachineSid $ctx.MachineSid) {
                'o TI Suite está aberto com uma conta local, que não consulta o domínio'
            } else { 'sem resposta do servidor do domínio' }
            Emit ('Não deu para consultar o domínio ({0}): vale o que o Windows guardou do último login de cada usuário.' -f $why) 'Warn'
        }
    }

    $rows = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($p in $all) {
        $i++
        $isAdmin = $false
        if ($pending.ContainsKey([string]$p.SID)) { $isAdmin = Get-TIProfileAdminState -Sid $p.SID -Ctx $ctx -Nested $nested }
        $v = Get-TIProfileVerdict -Sid $p.SID -Path $p.LocalPath -Special ([bool]$p.Special) -Loaded ([bool]$p.Loaded) `
                                  -MachineSid $ctx.MachineSid -AdminSids $ctx.AdminSids -CurrentSid $ctx.CurrentSid -IsAdmin $isAdmin
        if ($v.Kind -eq 'Sistema') { continue }
        $name = Split-Path -Leaf $p.LocalPath
        $account = ''
        try { $account = (New-Object System.Security.Principal.SecurityIdentifier($p.SID)).Translate([System.Security.Principal.NTAccount]).Value } catch { }
        $size = -1.0
        if (-not $v.Protected) {
            Emit ('Medindo o perfil {0} ({1}/{2})...' -f $name, $i, $all.Count) 'Debug' ([int](100 * $i / [Math]::Max(1, $all.Count)))
            # não segue pontos de junção/links (tamanho inflado ou de fora do perfil)
            $size = Get-TISafeSize -Path $p.LocalPath
        }
        [void]$rows.Add([pscustomobject]@{
            Name      = $name
            Account   = $account
            Path      = $p.LocalPath
            Sid       = [string]$p.SID
            Size      = $size
            LastUse   = (Get-TIProfileLastUse -Sid $p.SID -Fallback $p.LastUseTime)
            Loaded    = [bool]$p.Loaded
            Kind      = $v.Kind
            Protected = [bool]$v.Protected
            Reason    = $v.Reason
        })
    }
    $free = @($rows | Where-Object { -not $_.Protected }).Count
    Emit ('{0} perfil(is) encontrado(s): {1} pode(m) ser apagado(s), {2} protegido(s).' -f $rows.Count, $free, ($rows.Count - $free)) 'Success'
    return ,($rows.ToArray())
}

# Confere tudo de novo na hora de apagar (a lista pode ter ficado velha)
function Remove-TIUserProfiles {
    param($Items)
    $removed = 0; $freed = 0.0; $skipped = 0; $failed = 0
    $names = New-Object System.Collections.ArrayList
    $Items = @($Items | Where-Object { $_ -and $_.Sid })
    $total = $Items.Count
    if ($total -eq 0) { Emit 'Nenhum perfil marcado.' 'Warn'; return }

    $ctx = Get-TIAdminContext
    if ($null -eq $ctx.AdminSids) { throw 'Não foi possível ler o grupo Administradores: nenhum perfil foi apagado.' }
    if (-not $ctx.MachineSid) { throw 'Não foi possível identificar as contas locais: nenhum perfil foi apagado.' }
    $nested = $null
    if ($ctx.DomainGroups.Count -gt 0) {
        Emit 'Conferindo de novo no domínio quem é administrador...' 'Debug'
        $nested = Get-TINestedAdminMap -GroupSids $ctx.DomainGroups
    }

    $live = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop)
    $i = 0
    foreach ($item in $Items) {
        $i++
        if ($item.Protected) { Emit ('O perfil {0} é protegido: mantido.' -f $item.Name) 'Warn'; $skipped++; continue }
        $match = $live | Where-Object { $_.SID -eq $item.Sid } | Select-Object -First 1
        if (-not $match) {
            Emit ('O perfil {0} não está mais registrado no Windows.' -f $item.Name) 'Warn'
            $skipped++
            continue
        }
        $isAdmin = Get-TIProfileAdminState -Sid $match.SID -Ctx $ctx -Nested $nested
        $v = Get-TIProfileVerdict -Sid $match.SID -Path $match.LocalPath -Special ([bool]$match.Special) -Loaded ([bool]$match.Loaded) `
                                  -MachineSid $ctx.MachineSid -AdminSids $ctx.AdminSids -CurrentSid $ctx.CurrentSid -IsAdmin $isAdmin
        if ($v.Protected) {
            Emit ('O perfil {0} ficou protegido ({1}): mantido.' -f $item.Name, $v.Reason) 'Warn'
            $skipped++
            continue
        }
        Emit ('Apagando o perfil {0} ({1}/{2})...' -f $item.Name, $i, $total) 'Info' ([int](100 * $i / $total))
        try {
            Remove-CimInstance -InputObject $match -ErrorAction Stop
            $removed++
            [void]$names.Add([string]$item.Name)
            if ($item.Size -gt 0) { $freed += [double]$item.Size }
            Emit ('Perfil {0} apagado do disco e do registro.' -f $item.Name) 'Success'
        } catch {
            $failed++
            Emit ('Falha ao apagar {0}: {1}' -f $item.Name, $_.Exception.Message) 'Error'
        }
    }
    Emit ('Concluído: {0} apagado(s), {1} mantido(s), {2} com falha, {3} liberados.' -f $removed, $skipped, $failed, (Format-TIByte $freed)) $(if ($failed -gt 0) { 'Warn' } else { 'Success' })
    return ([pscustomobject]@{ Removed = $removed; Skipped = $skipped; Failed = $failed; Freed = $freed; Names = $names.ToArray() })
}
'@

$global:Limpeza = @{
    Grid         = $null
    Rows         = @()
    Scanned      = $false
    ScanInfo     = $null
    RemoveBtn    = $null
    MarkBtns     = @()
    JunkGrid     = $null
    JunkRows     = @()
    JunkInfo     = $null
    JunkCleanBtn = $null
    Summary      = @{}
}

# Coluna 0 da lista de perfis: caixa desenhada com glifo (marcado, desmarcado ou cadeado)
$global:LimpezaGlyph = @{
    On   = [string][char]0xE73A   # CheckboxComposite
    Off  = [string][char]0xE739   # Checkbox
    Lock = [string][char]0xE72E   # Lock
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

function Get-LimpezaMarked {
    return @($global:Limpeza.Rows | Where-Object { $_ -and -not $_.Protected -and $_.Marked })
}

function Update-LimpezaRemoveState {
    $busy = $global:TI.Busy
    $free = @($global:Limpeza.Rows | Where-Object { $_ -and -not $_.Protected }).Count
    if ($global:Limpeza.RemoveBtn) { $global:Limpeza.RemoveBtn.Enabled = (-not $busy -and @(Get-LimpezaMarked).Count -gt 0) }
    foreach ($b in @($global:Limpeza.MarkBtns)) { if ($b) { $b.Enabled = (-not $busy -and $free -gt 0) } }
    if ($global:Limpeza.JunkCleanBtn) { $global:Limpeza.JunkCleanBtn.Enabled = (-not $busy -and @($global:Limpeza.JunkRows).Count -gt 0) }
}

function Set-LimpezaRowMark {
    param($Row, [bool]$On)
    if (-not $Row -or -not $Row.Tag -or $Row.Tag.Protected) { return }
    $Row.Tag.Marked = $On
    $Row.Cells[0].Value = $(if ($On) { $global:LimpezaGlyph.On } else { $global:LimpezaGlyph.Off })
    $Row.Cells[0].Style.ForeColor = $(if ($On) { $global:Pal.Primary } else { $global:Pal.TextMuted })
    $Row.Cells[0].Style.SelectionForeColor = $Row.Cells[0].Style.ForeColor
}

function Update-LimpezaMarkInfo {
    $rows = @($global:Limpeza.Rows | Where-Object { $_ })
    $free = @($rows | Where-Object { -not $_.Protected })
    $marked = @(Get-LimpezaMarked)
    $prot = $rows.Count - $free.Count
    $size = [double](($marked | Where-Object { $_.Size -gt 0 } | Measure-Object -Property Size -Sum).Sum)
    if ($rows.Count -eq 0) {
        Update-LimpezaScanInfo 'Nenhum perfil de usuário neste computador.' 'muted'
        Set-LimpezaSummary 'profiles' 'Nenhum encontrado' 'ok'
    } elseif ($free.Count -eq 0) {
        Update-LimpezaScanInfo ('{0} perfil(is), todos protegidos (contas locais, administradores ou em uso).' -f $rows.Count) 'muted'
        Set-LimpezaSummary 'profiles' 'Nada para apagar' 'ok'
    } else {
        $txt = '{0} de {1} perfil(is) marcado(s) para apagar ({2}).' -f $marked.Count, $free.Count, (Format-TIBytes $size)
        if ($prot -gt 0) { $txt += (' {0} protegido(s).' -f $prot) }
        $txt += ' Clique na caixa ou use Espaço para marcar e desmarcar.'
        Update-LimpezaScanInfo $txt $(if ($marked.Count -gt 0) { 'primary' } else { 'muted' })
        Set-LimpezaSummary 'profiles' ('{0} de {1} marcado(s), {2}' -f $marked.Count, $free.Count, (Format-TIBytes $size))
    }
    if ($global:Limpeza.RemoveBtn) {
        $global:Limpeza.RemoveBtn.Text = $(if ($marked.Count -gt 0) { 'Apagar marcados ({0})' -f $marked.Count } else { 'Apagar marcados' })
    }
    Update-LimpezaRemoveState
}

# Clique na caixa, Espaço ou duplo clique: se alguma das linhas estiver desmarcada, marca todas; senão desmarca
function Switch-LimpezaRows {
    param($Rows)
    $all = @($Rows | Where-Object { $_ -and $_.Tag })
    $rows = @($all | Where-Object { -not $_.Tag.Protected })
    if ($rows.Count -eq 0) {
        $p = $all | Select-Object -First 1
        if ($p) { Show-TIToast -Text ('{0} é protegido: {1}.' -f $p.Tag.Name, $p.Tag.Reason) -Type 'Info' }
        return
    }
    $on = (@($rows | Where-Object { -not $_.Tag.Marked }).Count -gt 0)
    foreach ($r in $rows) { Set-LimpezaRowMark -Row $r -On $on }
    Update-LimpezaMarkInfo
}

function Set-LimpezaMarkAll {
    param([bool]$On)
    $grid = $global:Limpeza.Grid
    if (-not $grid) { return }
    foreach ($r in $grid.Rows) {
        if (-not $r.Tag -or $r.Tag.Protected) { continue }
        Set-LimpezaRowMark -Row $r -On $On
    }
    Update-LimpezaMarkInfo
}

function Fill-LimpezaGrid {
    param($Rows)
    $grid = $global:Limpeza.Grid
    if (-not $grid) { return }
    $grid.Rows.Clear()
    # apagáveis primeiro (sem uso há mais tempo no topo), protegidos no fim
    $list = @($Rows | Where-Object { $_ } | Sort-Object @{ Expression = { [bool]$_.Protected } },
                                                      @{ Expression = { if ($_.LastUse) { [datetime]$_.LastUse } else { [datetime]::MinValue } } },
                                                      Name)
    $global:Limpeza.Rows = $list
    $global:Limpeza.Scanned = $true
    foreach ($r in $list) {
        # vêm todos marcados, menos os protegidos (o técnico desmarca o que quiser manter)
        Add-Member -InputObject $r -NotePropertyName 'Marked' -NotePropertyValue (-not $r.Protected) -Force
        $situ = if ($r.Protected) { 'Protegido: ' + $r.Reason } else { 'Pode ser apagado' }
        $sizeTxt = if ($r.Size -ge 0) { Format-TIBytes $r.Size } else { '-' }
        $row = Add-TIRow -Grid $grid -Tag $r `
                -Cells @('', $r.Name, $r.Kind, $sizeTxt, (Format-TIDate $r.LastUse -Relative), $situ) `
                -SortKeys @($null, $r.Name, $r.Kind, [double]$r.Size, $(if ($r.LastUse) { [datetime]$r.LastUse } else { [datetime]::MinValue }), $situ)
        $row.Cells[1].ToolTipText = ('{0}{1}' -f $r.Path, $(if ($r.Account) { "`nConta: " + $r.Account } else { '' }))
        if ($r.Protected) {
            $row.Cells[0].Value = $global:LimpezaGlyph.Lock
            $row.DefaultCellStyle.ForeColor = $global:Pal.TextDim
            $row.DefaultCellStyle.SelectionForeColor = $global:Pal.TextMuted
            $row.Cells[0].ToolTipText = 'Protegido: não pode ser apagado'
        } else {
            Set-LimpezaRowMark -Row $row -On ([bool]$r.Marked)
            $row.Cells[0].ToolTipText = 'Marcar ou desmarcar'
        }
    }
    Clear-TIGridSelection $grid
    Set-TIGridEmptyText $grid 'Nenhum perfil de usuário neste computador.'
    Update-LimpezaMarkInfo
}

# -ThenFull: leitura pedida pela manutenção completa, que continua quando ela terminar
# (o pedido vai junto da tarefa: se for cancelada, nada fica pendente)
function Invoke-LimpezaScan {
    param([switch]$ThenFull)
    if ($global:TI.Busy) { return }
    [void](Invoke-TIAsync -Name 'Leitura dos perfis de usuário' -Quiet -Context @{ ThenFull = [bool]$ThenFull } -Script {
        $ok = $true
        $rows = @()
        try { $rows = Get-TIUserProfiles }
        catch { $ok = $false; Emit ('Não foi possível ler os perfis: {0}' -f $_.Exception.Message) 'Error' }
        [pscustomobject]@{ Kind = 'ProfileScan'; Ok = $ok; Rows = @($rows); ThenFull = [bool]$Context.ThenFull }
    } -OnComplete {
        param($r)
        $res = @($r | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'ProfileScan' }) | Select-Object -First 1
        if (-not $res -or -not $res.Ok) {
            # leitura falhou: não finge que não há perfis e não deixa a manutenção seguir
            $global:Limpeza.Scanned = $false
            $global:Limpeza.Rows = @()
            if ($global:Limpeza.Grid) { $global:Limpeza.Grid.Rows.Clear(); Set-TIGridEmptyText $global:Limpeza.Grid 'Não foi possível ler os perfis. Veja o console (F12) e clique em Verificar perfis.' }
            Update-LimpezaScanInfo 'Não foi possível ler os perfis deste computador (detalhes no console).' 'crit'
            Set-LimpezaSummary 'profiles' 'Falha na leitura' 'crit'
            Update-LimpezaRemoveState
            return
        }
        Fill-LimpezaGrid -Rows @($res.Rows | Where-Object { $_ -and $_.PSObject.Properties['Sid'] })
        if ($res.ThenFull) { Invoke-LimpezaFull }
    })
}

function Get-LimpezaListText {
    param($Items, [int]$Max = 15)
    $txt = (($Items | Select-Object -First $Max | ForEach-Object {
        $extra = @()
        if ($_.LastUse) { $extra += ('último uso ' + (Format-TIDate $_.LastUse)) }
        '  ' + $_.Name + $(if ($extra.Count -gt 0) { '  (' + ($extra -join '; ') + ')' } else { '' })
    }) -join "`n")
    if (@($Items).Count -gt $Max) { $txt += ("`n  e mais {0}" -f (@($Items).Count - $Max)) }
    return $txt
}

# Nomes para a auditoria (sem inflar a linha do audit.csv)
function Get-LimpezaAuditNames {
    param($Items, [int]$Max = 25)
    $n = @($Items | ForEach-Object { $_.Name })
    $txt = ($n | Select-Object -First $Max) -join ', '
    if ($n.Count -gt $Max) { $txt += (' e mais {0}' -f ($n.Count - $Max)) }
    return $txt
}

function Set-LimpezaRemoveResult {
    param($Info, [string]$Prefix = '')
    if (-not $Info) { return }
    $txt = '{0}{1} perfil(is) apagado(s), {2} liberados às {3}' -f $Prefix, $Info.Removed, (Format-TIBytes $Info.Freed), (Get-Date -Format 'HH:mm')
    if ($Info.Failed -gt 0) { $txt += (' ({0} com falha)' -f $Info.Failed) }
    Set-LimpezaSummary 'last' $txt $(if ($Info.Failed -gt 0) { 'warn' } else { 'ok' })
}

function Invoke-LimpezaRemoveMarked {
    if ($global:TI.Busy) { return }
    $items = @(Get-LimpezaMarked)
    if ($items.Count -eq 0) { Show-TIToast -Text 'Marque ao menos um perfil na lista.' -Type 'Warn'; return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text 'Apagar perfis precisa do TI Suite aberto como administrador (clique no selo da barra lateral).' -Type 'Error'; return }
    $totalSize = [double](($items | Where-Object { $_.Size -gt 0 } | Measure-Object -Property Size -Sum).Sum)
    $msg = ("Estes {0} perfil(is) serão apagados do disco e do registro do Windows:`n`n{1}`n`nEspaço liberado: {2}.`nContas locais, administradores e perfis em uso nunca são apagados. Não dá para desfazer." -f `
            $items.Count, (Get-LimpezaListText $items), (Format-TIBytes $totalSize))
    $res = Show-TIConfirm -Title 'Apagar perfis de usuário' -Message $msg `
            -ConfirmText ('Apagar {0} perfil(is)' -f $items.Count) -Style 'Danger' -Icon 'Warning'
    if (-not $res) { return }

    [void](Invoke-TIAsync -Name ('Remoção de {0} perfil(is)' -f $items.Count) -RequiresAdmin -Context @{ Items = $items } `
            -AuditDetail ('Perfis: ' + (Get-LimpezaAuditNames $items)) -Script {
        Remove-TIUserProfiles -Items $Context.Items
    } -OnComplete {
        param($r)
        Set-LimpezaRemoveResult (@($r | Where-Object { $_ -and $_.PSObject.Properties['Freed'] }) | Select-Object -First 1)
        Invoke-LimpezaScan
    })
}

function Invoke-LimpezaMarkInactive {
    if ($global:TI.Busy) { return }
    if (@($global:Limpeza.Rows | Where-Object { $_ -and -not $_.Protected }).Count -eq 0) {
        Show-TIToast -Text 'Nenhum perfil que possa ser apagado. Clique em Verificar perfis para ler de novo.' -Type 'Info'
        return
    }
    $daysText = Show-TIInput -Title 'Perfis sem uso' -Label 'Dias sem uso' -Value '90' -Numeric -MaxLength 5 `
            -Validate { param($t) if ([int]$t.Trim() -lt 1) { 'Digite 1 ou mais.' } else { '' } } `
            -Message 'Marca só os perfis sem uso há mais de X dias; os outros ficam desmarcados. Nada é apagado antes da sua confirmação.' -OkText 'Marcar'
    if (-not $daysText) { return }
    $days = [int]$daysText.Trim()
    $cutoff = (Get-Date).AddDays(-$days)
    $n = 0
    foreach ($r in $global:Limpeza.Grid.Rows) {
        if (-not $r.Tag -or $r.Tag.Protected) { continue }
        $old = ($r.Tag.LastUse -and ([datetime]$r.Tag.LastUse) -lt $cutoff)
        Set-LimpezaRowMark -Row $r -On $old
        if ($old) { $n++ }
    }
    Update-LimpezaMarkInfo
    if ($n -eq 0) { Show-TIToast -Text ('Nenhum perfil sem uso há mais de {0} dias.' -f $days) -Type 'Info' }
    else { Show-TIToast -Text ('{0} perfil(is) sem uso há mais de {1} dias marcado(s). Confira e clique em Apagar marcados.' -f $n, $days) -Type 'Success' }
}

function Fill-LimpezaJunkGrid {
    param($Rows)
    $grid = $global:Limpeza.JunkGrid
    if (-not $grid) { return }
    $grid.Rows.Clear()
    $global:Limpeza.JunkRows = @($Rows)
    foreach ($r in @($Rows)) {
        if (-not $r) { continue }
        [void](Add-TIRow -Grid $grid -Cells @($r.Group, $r.Label, (Format-TIBytes $r.Size), $r.Path) `
                         -SortKeys @($r.Group, $r.Label, [double]$r.Size, $r.Path) -Tag $r)
    }
    Clear-TIGridSelection $grid
    Set-TIGridEmptyText $grid 'Nada para limpar neste computador.'
    $count = @($Rows).Count
    $totalSize = [double]((@($Rows) | Measure-Object -Property Size -Sum).Sum)
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
    $totalSize = [double](($items | Measure-Object -Property Size -Sum).Sum)
    $binNote = if (@($items | Where-Object { $_.Special -eq 'recycle' }).Count -gt 0) { "`nA Lixeira de todas as contas será esvaziada." } else { '' }
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

# Manutenção completa: apaga os perfis MARCADOS na lista (respeita o que o técnico
# desmarcou) e faz a limpeza profunda. Sem lista lida ainda, lê primeiro.
function Invoke-LimpezaFull {
    if ($global:TI.Busy) { return }
    if (-not $global:TI.Elevated) { Show-TIToast -Text 'A manutenção completa precisa do TI Suite aberto como administrador (clique no selo da barra lateral).' -Type 'Error'; return }
    if (-not $global:Limpeza.Scanned) {
        Show-TIToast -Text 'Lendo os perfis antes da manutenção completa...' -Type 'Info'
        Invoke-LimpezaScan -ThenFull
        return
    }
    $items = @(Get-LimpezaMarked)
    $profTxt = if ($items.Count -gt 0) {
        $sz = [double](($items | Where-Object { $_.Size -gt 0 } | Measure-Object -Property Size -Sum).Sum)
        ("  1. Apaga {0} perfil(is) marcado(s) na lista ({1}):`n{2}" -f $items.Count, (Format-TIBytes $sz), (Get-LimpezaListText $items 10))
    } else {
        '  1. Nenhum perfil marcado na lista: nenhum perfil será apagado'
    }
    # Apaga perfis: sempre pede confirmação (não obedece a "não pedir de novo")
    $res = Show-TIConfirm -Title 'Manutenção completa' -Icon 'Clean' -Style 'Danger' `
        -Message ("Em um passo só:`n{0}`n  2. Limpa temporários, caches, Windows Update e a Lixeira`n`nContas locais, administradores e quem está conectado nunca são apagados. Indicado para a troca de turma. Não dá para desfazer." -f $profTxt) `
        -ConfirmText 'Executar manutenção'
    if (-not $res) { return }

    Write-TILog -Level 'Warn' -Message 'Manutenção completa solicitada pelo operador.'
    [void](Invoke-TIAsync -Name 'Manutenção completa' -RequiresAdmin -Context @{ Items = $items } `
            -AuditDetail $(if ($items.Count -gt 0) { 'Perfis: ' + (Get-LimpezaAuditNames $items) } else { 'Sem perfis marcados' }) -Script {
        $prof = $null
        if (@($Context.Items).Count -gt 0) {
            $prof = Remove-TIUserProfiles -Items $Context.Items
        } else {
            Emit 'Nenhum perfil marcado para apagar.' 'Info'
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
            $fail = if ($res.Profiles) { [int]$res.Profiles.Failed } else { 0 }
            Set-LimpezaSummary 'last' ('Manutenção completa: {0} liberados às {1}{2}' -f (Format-TIBytes $freed), (Get-Date -Format 'HH:mm'),
                $(if ($fail -gt 0) { " ($fail perfil(is) com falha)" } else { '' })) $(if ($fail -gt 0) { 'warn' } else { 'ok' })
        }
        # a análise da limpeza profunda ficou velha: pede uma nova
        Fill-LimpezaJunkGrid -Rows @()
        Set-TIGridEmptyText $global:Limpeza.JunkGrid 'Clique em Analisar para medir o que pode ser limpo.'
        if ($global:Limpeza.JunkInfo) { $global:Limpeza.JunkInfo.Text = 'Clique em Analisar para medir o que pode ser limpo.'; $global:Limpeza.JunkInfo.ForeColor = $global:Pal.TextMuted }
        Set-LimpezaSummary 'junk' 'Clique em Analisar'
        Invoke-LimpezaScan
    })
}

$wsLimpeza = @{
    Id       = 'limpeza'
    Title    = 'Manutenção'
    Sub      = 'Perfis de usuários, limpeza profunda e manutenção em um passo'
    Icon     = 'Clean'
    Keywords = 'manutencao limpeza perfil perfis usuario usuarios apagar aluno rm temporarios cache lixeira espaco disco'

    OnActivate = { if (-not $global:Limpeza.Scanned) { Invoke-LimpezaScan } }
    Refresh    = { Invoke-LimpezaScan }

    Actions = {
        param($Bar)
        $b = New-TIButton -Text 'Atualizar' -Style 'Outline' -Width 116 -Height 34 -Icon 'Refresh' -Tip 'Ler os perfis de novo (Ctrl+R)'
        $b.Add_Click({ Invoke-LimpezaScan })
        $Bar.Controls.Add($b)
    }

    Build = {
        param($Panel, $Id)
        $flow = New-TIWorkspaceLayout -Panel $Panel
        $w = $global:Theme.CardWidth

        # --- Resumo -------------------------------------------------------
        $bSum = New-TICard -Parent $flow -Title 'Resumo' -Desc 'Perfis de usuários e espaço recuperável' -Icon 'Document' -Width $w -Height 196
        $iw = Get-TIInnerWidth $bSum
        foreach ($p in @(
            @{ K = 'profiles'; L = 'Perfis';           V = 'Verificando...' },
            @{ K = 'junk';     L = 'Limpeza profunda'; V = 'Clique em Analisar' },
            @{ K = 'last';     L = 'Última limpeza';   V = 'Nenhuma nesta sessão' }
        )) {
            $r = New-TIRow -Label $p.L -Value $p.V -Width $iw -LabelWidth 124
            $r.Value.ForeColor = $global:Pal.TextMuted
            $bSum.Controls.Add($r.Panel)
            $global:Limpeza.Summary[$p.K] = $r
        }

        # --- Manutenção completa -------------------------------------------
        $b3 = New-TICard -Parent $flow -Title 'Manutenção completa' -Desc 'Perfis marcados, caches e Lixeira de uma vez' -Icon 'Power' -Width $w -Height 196
        $null = New-TIHint -Parent $b3 -Text 'Indicado para a troca de turma: apaga os perfis marcados na lista abaixo e faz a limpeza profunda. Precisa do TI Suite aberto como administrador.' -BottomGap 10
        $btnFull = New-TIButton -Text 'Executar manutenção completa' -Style 'Primary' -Width 270 -Height 42 -Icon 'Power' -GlyphSize 13
        $btnFull.Add_Click({ Invoke-LimpezaFull })
        $b3.Controls.Add($btnFull)

        # --- Perfis de usuários ----------------------------------------------
        $b1 = New-TICard -Parent $flow -Title 'Perfis de usuários' -Stretch `
                -Desc 'Perfis de rede e do domínio. Público, contas locais, administradores e quem está conectado ficam protegidos' -Icon 'People' -Width $w -Height 472
        $bar1 = New-TIButtonBar -Parent $b1
        $btnScan = New-TIButton -Text 'Verificar perfis' -Style 'Outline' -Width 156 -Height 36 -Icon 'Search'
        $btnScan.Add_Click({ Invoke-LimpezaScan })
        $bar1.Controls.Add($btnScan)
        $btnRemove = New-TIButton -Text 'Apagar marcados' -Style 'Danger' -Width 196 -Height 36 -Icon 'Remove'
        $btnRemove.Enabled = $false
        $btnRemove.Add_Click({ Invoke-LimpezaRemoveMarked })
        $bar1.Controls.Add($btnRemove)
        $global:Limpeza.RemoveBtn = $btnRemove
        $btnAll = New-TIButton -Text 'Marcar todos' -Style 'Ghost' -Width 132 -Height 36 -Icon 'CheckList' -Tip 'Marca todos os perfis que podem ser apagados'
        $btnAll.Enabled = $false
        $btnAll.Add_Click({ Set-LimpezaMarkAll -On $true })
        $bar1.Controls.Add($btnAll)
        $btnNone = New-TIButton -Text 'Desmarcar todos' -Style 'Ghost' -Width 150 -Height 36 -Icon 'Undo'
        $btnNone.Enabled = $false
        $btnNone.Add_Click({ Set-LimpezaMarkAll -On $false })
        $bar1.Controls.Add($btnNone)
        $btnInactive = New-TIButton -Text 'Sem uso há...' -Style 'Soft' -Width 136 -Height 36 -Icon 'Clock' -Tip 'Marca só os perfis sem uso há mais de X dias'
        $btnInactive.Enabled = $false
        $btnInactive.Add_Click({ Invoke-LimpezaMarkInactive })
        $bar1.Controls.Add($btnInactive)
        $global:Limpeza.MarkBtns = @($btnAll, $btnNone, $btnInactive)

        $global:Limpeza.ScanInfo = New-TIHint -Parent $b1 -Text 'Verificando os perfis...' -TopGap 0 -BottomGap 6

        $grid1 = New-TIGrid -Parent $b1 -Headers @('', 'Usuário', 'Tipo', 'Tamanho', 'Último uso', 'Situação') `
                            -Widths @(40, 170, 80, 96, 190, 260) -Multi -EmptyText 'Clique em Verificar perfis para listar os perfis de usuário.'
        $grid1.Tag = 'tistretch'
        $grid1.Height = 260
        $chk = $grid1.Columns[0]
        $chk.AutoSizeMode = 'None'
        $chk.Width = 40
        $chk.SortMode = 'NotSortable'
        $chk.Resizable = 'False'
        $chk.DefaultCellStyle.Font = New-TIFont 12 Regular 'Segoe MDL2 Assets'
        $chk.DefaultCellStyle.Alignment = 'MiddleCenter'
        $chk.ToolTipText = 'Clique para marcar ou desmarcar todos'
        # Clique na caixa (MouseUp conta os dois cliques de um duplo clique rápido)
        $grid1.Add_CellMouseUp({
            param($s, $e)
            if ($e.Button -ne 'Left' -or $e.RowIndex -lt 0 -or $e.ColumnIndex -ne 0 -or $global:TI.Busy) { return }
            Switch-LimpezaRows @($s.Rows[$e.RowIndex])
        })
        $grid1.Add_CellMouseDoubleClick({
            param($s, $e)
            if ($e.Button -ne 'Left' -or $e.RowIndex -lt 0 -or $e.ColumnIndex -le 0 -or $global:TI.Busy) { return }
            Switch-LimpezaRows @($s.Rows[$e.RowIndex])
        })
        $grid1.Add_ColumnHeaderMouseClick({
            param($s, $e)
            if ($e.ColumnIndex -ne 0 -or $global:TI.Busy) { return }
            $free = @($global:Limpeza.Rows | Where-Object { $_ -and -not $_.Protected })
            $allOn = ($free.Count -gt 0 -and @($free | Where-Object { -not $_.Marked }).Count -eq 0)
            Set-LimpezaMarkAll -On (-not $allOn)
        })
        $grid1.Add_KeyDown({
            param($s, $e)
            if ($e.KeyCode -eq 'Space' -and -not $global:TI.Busy) {
                $e.Handled = $true
                $e.SuppressKeyPress = $true
                Switch-LimpezaRows @($s.SelectedRows)
            }
        })
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
