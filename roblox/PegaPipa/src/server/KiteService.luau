--!strict
--[[
	KiteService — a mecânica central (GDD §2): uma pipa no ar por jogador, faixas 0-4, o botão PUXAR
	(remote Pull "Down"/"Up": toque < TAP_MAX sobe ou rabeia, segurar desce 1 faixa a cada
	HOLD_DESCEND_EVERY), deriva no anel compartilhado (§2.4), selvagens (§2.8), rabeio/duelo (§2.3),
	queda e pega pública (§2.5), Árvore do Campinho (§2.6), escudo de novato e Pipa de Jornal (§2.7),
	anti-AFK "linha frouxa" (§3.3), tutorial da Pipa de Treino aos TUTORIAL_AT s e passos do funil
	1/2/4/5 (§5.8).

	Servidor-autoritativo: nenhuma pipa tem física. As posições são calculadas aqui e escritas como
	Attributes (GDD §7.4) em workspace/KiteStates/<id> (Configuration com tag Kite) a SYNC_HZ; o cliente
	só interpola. Tempos replicados usam workspace:GetServerTimeNow(); os tempos do dedo (toque/segurar)
	usam os.clock().

	Dono de profile.Data.Selected: no load escolhe a pipa de maior base×(dourada ? 5 : 1) e a sobe;
	quando Selected == 0 (corte, venda, renascer) escolhe outra. Pipa cortada sai do perfil NA HORA
	(DataService.removeKite) e volta por DataService.addKite na pega ou quando a árvore expira.
	Escreve VaralCodes na laje do dono: "model:rarity:color:golden,…" (golden = "true"/"false") das pipas
	fora do ar.

	Requer: Config, Remotes, DataService, MapGen, Leaderboard. NUNCA requer ShopService/EventService/
	MonetizationService: eles assinam onDuelEnd/onCatch; o Festival é lido de workspace.World (atributo
	Festival) e o Carretel Automático de DataService.hooks.hasAutoReel(p).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local AnalyticsService = game:GetService("AnalyticsService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local DataService = require(script.Parent.DataService)
local MapGen = require(script.Parent.MapGen)
local Leaderboard = require(script.Parent.Leaderboard)

export type KiteState = {
	id: number, -- id único no servidor (nome da Configuration)
	owner: number, -- userId; 0 = selvagem
	model: string,
	rarity: number,
	color: number,
	golden: boolean,
	faixa: number,
	theta: number, -- ângulo no anel (rad)
	pos: Vector3,
	status: string, -- Flying | Dueling | Falling | Ground | Tree
	statusUntil: number, -- fim do estado atual (GetServerTimeNow); 0 em Flying
	duelWith: number?, -- id da pipa adversária
	immuneUntil: number, -- não pode ser rabeada até aqui
	wild: boolean,
	tutorialFor: Player?, -- Pipa de Treino deste novato
	landPos: Vector3?, -- ponto de pouso (Falling/Ground) ou TREE_TOP (Tree)
	conf: Configuration,
	-- internos (não fazem parte do contrato §7.2)
	profileId: number?, -- id da pipa no perfil do dono (KiteData.id)
	laje: number?, -- laje do dono
	ownerName: string?, -- nome exibido do dono (sobrevive à saída dele)
	points: number?, -- pontos fixos (Pipa de Treino = 0); nil = WILD_POINTS[raridade]
	wildPhase: string?, -- Enter | Orbit | Exit | Tutorial
	wildTarget: Vector3?, -- destino nas fases Enter/Exit
	orbitLeft: number?, -- radianos que faltam da volta contra o vento
	diveTarget: Vector3?, -- destino do mergulho de quem rabeou
	rain: boolean?, -- Chuva de Pipas: some se ninguém pegar (não vai à árvore)
}

export type WildOpts = { tutorialFor: Player?, points: number? }
export type DuelEndCallback = (winner: Player?, loser: Player?, wild: boolean) -> ()
export type CatchCallback = (p: Player, k: KiteState) -> ()

type ProfileData = Config.ProfileData
type KiteData = Config.KiteData
type Duel = { a: KiteState, b: KiteState, endsAt: number }
type WildBoost = { intervalMin: number, intervalMax: number, maxInAir: number, weights: { number }, untilTime: number }
type Sample = { pos: Vector3, t: number }

local STATUS_FLYING = "Flying"
local STATUS_DUELING = "Dueling"
local STATUS_FALLING = "Falling"
local STATUS_GROUND = "Ground"
local STATUS_TREE = "Tree"
local STARTER_MODEL = "Jornal" -- só a starter usa este modelo (GDD §3.2)
local WILD_TUTORIAL_RARITY = 1 -- Pipa de Treino é Comum

local KiteService = {}

local rng = Random.new()

-- Estado -----------------------------------------------------------------------------------------

local kites: { [number]: KiteState } = {} -- por id do servidor
local flying: { [Player]: KiteState } = {} -- a pipa no ar de cada jogador
local duels: { Duel } = {}
local nextId = 1
local windSign = 1

-- botão PUXAR (os.clock)
local holdStart: { [Player]: number } = {}
local holding: { [Player]: boolean } = {}
local holdSeq: { [Player]: number } = {} -- invalida o laço de descida anterior num Down→Up→Down rápido
local lastHoldEnd: { [Player]: number } = {}
local tapCooldown: { [Player]: number } = {}

-- anti-AFK e anti-teleport
local lastPull: { [Player]: number } = {}
local afkNextDrop: { [Player]: number } = {}
local moveSample: { [Player]: Sample } = {}
local catchBanUntil: { [Player]: number } = {}
local tutorialGiven: { [Player]: boolean } = {}

-- selvagens
local wildBoost: WildBoost? = nil
local nextWildAt = 0

local duelEndCallbacks: { DuelEndCallback } = {}
local catchCallbacks: { CatchCallback } = {}

local pullLimiter = Remotes.limiter(Config.RATE.Pull[1], Config.RATE.Pull[2])
local selectLimiter = Remotes.limiter(Config.RATE.SelectKite[1], Config.RATE.SelectKite[2])
local emoteLimiter = Remotes.limiter(Config.RATE.Emote[1], Config.RATE.Emote[2])

-- Ajudantes --------------------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- workspace/World (Configuration criada pelo MapGen; criada aqui se faltar).
local function world(): Configuration
	local found = Workspace:FindFirstChild("World")
	if found and found:IsA("Configuration") then
		return found
	end
	local conf = Instance.new("Configuration")
	conf.Name = "World"
	conf:SetAttribute("WindSign", 1)
	conf.Parent = Workspace
	return conf
end

-- workspace/KiteStates (Folder criada pelo MapGen; criada aqui se faltar).
local function statesFolder(): Folder
	local found = Workspace:FindFirstChild("KiteStates")
	if found and found:IsA("Folder") then
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = "KiteStates"
	folder.Parent = Workspace
	return folder
end

local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

local function rootOf(p: Player): BasePart?
	local character = p.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function dataOf(p: Player): ProfileData?
	local profile = DataService.get(p)
	return if profile then profile.Data else nil
end

local function ownerPlayer(k: KiteState): Player?
	if k.owner == 0 then
		return nil
	end
	return Players:GetPlayerByUserId(k.owner)
end

local function isFestival(): boolean
	return world():GetAttribute("Festival") == true
end

local function ringPos(r: number, h: number, theta: number): Vector3
	return Vector3.new(r * math.cos(theta), h, r * math.sin(theta))
end

-- Anda de `from` para `to` no máximo `maxStep` studs.
local function moveToward(from: Vector3, to: Vector3, maxStep: number): Vector3
	local delta = to - from
	local dist = delta.Magnitude
	if dist <= maxStep then
		return to
	end
	return from + delta * (maxStep / dist)
end

local function toast(p: Player?, kind: string, args: { [string]: any })
	DataService.toast(p, kind, args)
end

-- Passo do funil de onboarding (§5.8): só avança; loga no AnalyticsService.
local function onboarding(p: Player, step: number)
	local data = dataOf(p)
	if not data or data.Onboarding >= step then
		return
	end
	data.Onboarding = step
	DataService.pushState(p, { Onboarding = step })
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(p, step, Config.ONBOARDING_STEPS[step])
	end)
end

-- Ponto aleatório do campinho (x ∈ [-landX, landX], z ∈ [-landZ, landZ], y = LAND_Y).
function KiteService.randomLandPos(): Vector3
	local c = Config.CAMPINHO
	return Vector3.new(rng:NextNumber(-c.landX, c.landX), Config.LAND_Y, rng:NextNumber(-c.landZ, c.landZ))
end

-- Sorteia uma raridade (1..6) por uma tabela de pesos (WILD_TABLE, WILD_TABLE_RAJADA…).
function KiteService.rollRarity(weights: { number }): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber() * total
	for i, w in weights do
		if w > 0 and roll < w then
			return i
		end
		roll -= w
	end
	return 1
end

-- Pipa de maior base×(dourada ? 5 : 1) do varal (seleção padrão, §2.1).
local function bestKite(data: ProfileData): KiteData?
	local best: KiteData? = nil
	local bestRate = -1
	for _, k in data.Kites do
		local rate = Config.baseRate(k)
		if rate > bestRate then
			best, bestRate = k, rate
		end
	end
	return best
end

-- Posição-alvo de uma pipa de jogador pela faixa (§2.2).
local function lajeGoal(k: KiteState): Vector3
	local laje = k.laje or 1
	if k.faixa >= 3 then
		local ring = Config.RING[k.faixa]
		return ringPos(ring.r, ring.h, k.theta)
	elseif k.faixa >= 1 then
		return MapGen.lajeFloor(laje) + Vector3.new(0, Config.FAIXA_HEIGHT_ABOVE_LAJE[k.faixa], 0)
	end
	local c = MapGen.carretelPos(laje)
	return Vector3.new(c.X, Config.LAJE_FLOOR_Y, c.Z)
end

local function linhaOf(k: KiteState): number
	if k.wild then
		return k.points or Config.WILD_POINTS[k.rarity]
	end
	local p = ownerPlayer(k)
	local data = if p then dataOf(p) else nil
	return if data then data.Linha else 1
end

-- Configuration ---------------------------------------------------------------------------------

local function syncConf(k: KiteState)
	local conf = k.conf
	setAttr(conf, "Faixa", k.faixa)
	setAttr(conf, "Pos", k.pos)
	setAttr(conf, "Status", k.status)
	setAttr(conf, "StatusUntil", k.statusUntil)
	setAttr(conf, "DuelWith", k.duelWith or 0)
	setAttr(conf, "DuelEndsAt", if k.status == STATUS_DUELING then k.statusUntil else 0)
	setAttr(conf, "LandPos", k.landPos or Vector3.zero)
	setAttr(conf, "Golden", k.golden)
	setAttr(conf, "Linha", linhaOf(k))
end

-- Cria o estado + a Configuration (tag Kite) em workspace/KiteStates/<id>.
local function newState(owner: number, ownerName: string, model: string, rarity: number, color: number, golden: boolean, wild: boolean): KiteState
	local id = nextId
	nextId += 1
	local conf = Instance.new("Configuration")
	conf.Name = tostring(id)
	conf:SetAttribute("Id", id)
	conf:SetAttribute("Owner", owner)
	conf:SetAttribute("OwnerName", ownerName)
	conf:SetAttribute("Model", model)
	conf:SetAttribute("Rarity", rarity)
	conf:SetAttribute("Color", color)
	conf:SetAttribute("Wild", wild)
	conf:AddTag("Kite")
	local k: KiteState = {
		id = id,
		owner = owner,
		model = model,
		rarity = rarity,
		color = color,
		golden = golden,
		faixa = 0,
		theta = 0,
		pos = Vector3.zero,
		status = STATUS_FLYING,
		statusUntil = 0,
		immuneUntil = 0,
		wild = wild,
		conf = conf,
		ownerName = ownerName,
	}
	kites[id] = k
	syncConf(k)
	conf.Parent = statesFolder()
	return k
end

local function destroyKite(k: KiteState)
	kites[k.id] = nil
	local p = ownerPlayer(k)
	if p and flying[p] == k then
		flying[p] = nil
	end
	k.conf:Destroy()
end

-- Varal ------------------------------------------------------------------------------------------

-- VaralCodes da laje do dono: pipas fora do ar, "model:rarity:color:golden,…".
local function updateVaral(p: Player, data: ProfileData)
	local laje = DataService.lajeOf(p)
	if laje == 0 then
		return
	end
	local k = flying[p]
	local inAir = if k then k.profileId else nil
	local codes = {}
	for _, kd in data.Kites do
		if kd.id ~= inAir then
			table.insert(codes, `{kd.model}:{kd.rarity}:{kd.color}:{tostring(kd.golden)}`)
		end
	end
	setAttr(MapGen.lajeModel(laje), "VaralCodes", table.concat(codes, ","))
end

-- Pipa do jogador ---------------------------------------------------------------------------------

local function setFaixa(k: KiteState, faixa: number)
	local old = k.faixa
	k.faixa = math.clamp(faixa, 0, 4)
	if k.faixa >= 3 and old < 3 then
		k.theta = MapGen.lajeAngle(k.laje or 1) -- entra no anel no ângulo da própria laje
	end
end

-- Sobe a pipa `profileId` do perfil de p na faixa 0.
local function putUp(p: Player, profileId: number)
	local kd = DataService.findKite(p, profileId)
	local laje = DataService.lajeOf(p)
	if not kd or laje == 0 then
		return
	end
	local k = newState(p.UserId, p.DisplayName, kd.model, kd.rarity, kd.color, kd.golden, false)
	k.profileId = kd.id
	k.laje = laje
	k.theta = MapGen.lajeAngle(laje)
	k.pos = lajeGoal(k)
	flying[p] = k
	syncConf(k)
end

-- Garante que a pipa no ar é a Selected do perfil (e que Selected aponta para uma pipa que existe).
local function watchSelection(p: Player, data: ProfileData)
	local k: KiteState? = flying[p]
	if k and k.status ~= STATUS_FLYING then
		return -- em duelo: espera resolver
	end
	if k and DataService.findKite(p, k.profileId or 0) == nil then
		destroyKite(k) -- a pipa sumiu do perfil (renascer, venda)
		k = nil
	end
	if data.Selected ~= 0 and DataService.findKite(p, data.Selected) == nil then
		data.Selected = 0
	end
	if data.Selected == 0 then
		local best = bestKite(data)
		if not best then
			return
		end
		data.Selected = best.id
		DataService.pushState(p, { Selected = best.id })
	end
	if k == nil or k.profileId ~= data.Selected then
		if k then
			destroyKite(k)
		end
		putUp(p, data.Selected)
	end
end

-- Queda, chão, árvore e pega (§2.5 / §2.6) ----------------------------------------------------------

local function startFall(k: KiteState, t: number, landPos: Vector3?)
	k.status = STATUS_FALLING
	k.faixa = 0
	k.duelWith = nil
	k.diveTarget = nil
	k.landPos = landPos or KiteService.randomLandPos()
	k.statusUntil = t + Config.FALL_TIME
	toast(nil, "Voada", {
		name = k.ownerName or "",
		kite = k.model,
		rarity = k.rarity,
		landPos = k.landPos,
		untilTime = t + Config.FALL_TIME + Config.GROUND_TIME,
		wild = k.wild,
	})
end

local function toTree(k: KiteState, t: number)
	k.status = STATUS_TREE
	k.pos = Config.TREE_TOP
	k.landPos = Config.TREE_TOP
	k.statusUntil = t + Config.TREE_TIME
	local p = ownerPlayer(k)
	if p then
		toast(p, "Arvore", { time = Config.TREE_TIME })
	end
end

-- Árvore expirou: dono online → volta ao varal; senão a pipa é destruída.
local function treeExpire(k: KiteState)
	local p = ownerPlayer(k)
	if p and dataOf(p) then
		DataService.addKite(p, k.model, k.rarity, k.color, k.golden)
	end
	destroyKite(k)
end

local function catchKite(p: Player, k: KiteState)
	local data = dataOf(p)
	if not data then
		return
	end
	local color = if isFestival() then Config.FESTIVAL.color else k.color
	DataService.addKite(p, k.model, k.rarity, color, k.golden)
	data.Stats.Pegas += 1
	toast(p, "Pegou", { kite = k.model, rarity = k.rarity })
	if k.owner ~= 0 and k.owner ~= p.UserId then
		local ex = ownerPlayer(k)
		if ex then
			toast(ex, "PegaramSua", { name = p.DisplayName, kite = k.model })
		end
	end
	onboarding(p, 5)
	destroyKite(k)
	for _, cb in catchCallbacks do
		task.spawn(cb, p, k)
	end
end

-- Anti-teleport: salto > TELEPORT_JUMP studs em TELEPORT_WINDOW s → TELEPORT_PENALTY s fora da pega.
local function sampleMovement(p: Player, t: number)
	local root = rootOf(p)
	if not root then
		moveSample[p] = nil
		return
	end
	local sample = moveSample[p]
	if not sample then
		moveSample[p] = { pos = root.Position, t = t }
		return
	end
	if t - sample.t >= Config.TELEPORT_WINDOW then
		if (root.Position - sample.pos).Magnitude > Config.TELEPORT_JUMP then
			catchBanUntil[p] = t + Config.TELEPORT_PENALTY
		end
		moveSample[p] = { pos = root.Position, t = t }
	end
end

-- HumanoidRootPart mais próximo a ≤ radius da pipa (qualquer jogador, inclusive o dono).
local function nearestCatcher(k: KiteState, radius: number, t: number): Player?
	local best: Player? = nil
	local bestDist = radius
	for _, p in Players:GetPlayers() do
		if (catchBanUntil[p] or 0) > t or not DataService.get(p) then
			continue
		end
		local root = rootOf(p)
		if not root then
			continue
		end
		local d = (root.Position - k.pos).Magnitude
		if d <= bestDist then
			best, bestDist = p, d
		end
	end
	return best
end

-- Duelo (§2.3 passos 3-6) ---------------------------------------------------------------------------

local function isHolding(p: Player): boolean
	return holding[p] == true or (os.clock() - (lastHoldEnd[p] or -math.huge)) <= Config.HOLD_GRACE
end

local function duelPoints(k: KiteState): number
	if k.wild then
		return k.points or Config.WILD_POINTS[k.rarity]
	end
	local p = ownerPlayer(k)
	local data = if p then dataOf(p) else nil
	local linha = if data then data.Linha else 1
	local bonus = if p and isHolding(p) then Config.HOLD_BONUS else 0
	return linha + bonus + rng:NextInteger(0, Config.DUEL_RANDOM)
end

-- Alvo do rabeio: pipa Flying de outro dono (ou selvagem) sem imunidade a ≤ RABEIO_RANGE; precisa da
-- própria faixa ≥ 3, salvo a Pipa de Treino deste jogador (vale em qualquer faixa ≥ 1).
local function findRabeioTarget(p: Player, k: KiteState, t: number): KiteState?
	local best: KiteState? = nil
	local bestDist = Config.RABEIO_RANGE
	for _, o in kites do
		if o == k or o.status ~= STATUS_FLYING or o.owner == k.owner or o.immuneUntil > t then
			continue
		end
		local tutorial = o.tutorialFor == p
		if not o.wild and o.faixa < 3 then
			continue
		end
		if tutorial and k.faixa < 1 then
			continue
		end
		if not tutorial and k.faixa < 3 then
			continue
		end
		local d = (o.pos - k.pos).Magnitude
		if d <= bestDist then
			best, bestDist = o, d
		end
	end
	return best
end

local function duelToast(k: KiteState, opponent: KiteState, endsAt: number)
	local p = ownerPlayer(k)
	if not p then
		return
	end
	local name = if opponent.wild then Config.str("wild", "pt-BR") else (opponent.ownerName or "")
	toast(p, "Duelo", { opponent = name, linha = linhaOf(opponent), endsAt = endsAt, wild = opponent.wild })
end

local function startRabeio(a: KiteState, b: KiteState, t: number)
	local endsAt = t + Config.RABEIO_TIME + Config.DUEL_TIME
	a.status, b.status = STATUS_DUELING, STATUS_DUELING
	a.duelWith, b.duelWith = b.id, a.id
	a.statusUntil, b.statusUntil = endsAt, endsAt
	local dir = b.pos - a.pos
	if dir.Magnitude > 0 then
		a.diveTarget = a.pos + dir.Unit * Config.RABEIO_DIVE
	end
	table.insert(duels, { a = a, b = b, endsAt = endsAt })
	duelToast(a, b, endsAt)
	duelToast(b, a, endsAt)
end

local function backToFlying(k: KiteState)
	k.status = STATUS_FLYING
	k.statusUntil = 0
	k.duelWith = nil
	k.diveTarget = nil
end

-- Perdedor: selvagem cai; novato/Jornal/Carretel Automático volta à laje; senão sai do perfil e cai.
local function loseKite(k: KiteState, lp: Player?, t: number)
	if k.wild or not lp then
		backToFlying(k)
		startFall(k, t, nil)
		return
	end
	local shield = DataService.isNovato(lp) or k.model == STARTER_MODEL or DataService.hooks.hasAutoReel(lp)
	if shield then
		backToFlying(k)
		setFaixa(k, 0)
		k.pos = lajeGoal(k)
		k.immuneUntil = t + Config.POST_DUEL_IMMUNITY
		toast(lp, "Voou", { shield = true })
		return
	end
	DataService.removeKite(lp, k.profileId or 0) -- Selected vira 0; watchSelection sobe outra
	flying[lp] = nil
	toast(lp, "Voou", { shield = false })
	backToFlying(k)
	startFall(k, t, nil)
	local data = dataOf(lp)
	if data then
		updateVaral(lp, data)
	end
end

local function resolveDuel(d: Duel, t: number)
	local a, b = d.a, d.b
	if kites[a.id] ~= a or kites[b.id] ~= b then
		-- um lado sumiu (jogador saiu): o outro volta a voar sem vencedor
		for _, k in { a, b } do
			if kites[k.id] == k then
				backToFlying(k)
			end
		end
		return
	end
	local pa, pb = duelPoints(a), duelPoints(b)
	local tie = pa == pb
	local aWins = if tie then rng:NextInteger(0, 1) == 0 else pa > pb
	local winner = if aWins then a else b
	local loser = if aWins then b else a
	local wp, lp = ownerPlayer(winner), ownerPlayer(loser)
	if tie then
		for _, p in { wp, lp } do
			if p then
				toast(p, "Sorte", {})
			end
		end
	end
	backToFlying(winner)
	winner.immuneUntil = t + Config.POST_DUEL_IMMUNITY
	if wp then
		toast(wp, "Cortou", {})
		local data = dataOf(wp)
		if data then
			data.Stats.Cortes += 1
			if not loser.wild then
				data.Stats.CortesPvP += 1
				Leaderboard.addWeekly(wp, "CortesPvP", 1)
			end
		end
		onboarding(wp, 4)
	end
	loseKite(loser, lp, t)
	for _, cb in duelEndCallbacks do
		task.spawn(cb, wp, lp, a.wild or b.wild)
	end
end

-- Botão PUXAR (§2.3 passos 2-3) -----------------------------------------------------------------------

local function onTap(p: Player)
	local clock = os.clock()
	if (tapCooldown[p] or 0) > clock then
		return
	end
	local k = flying[p]
	if not k or k.status ~= STATUS_FLYING then
		return
	end
	local t = now()
	local target = findRabeioTarget(p, k, t)
	if target then
		startRabeio(k, target, t)
	elseif k.faixa < 4 then
		setFaixa(k, k.faixa + 1)
	end
	tapCooldown[p] = clock + Config.TAP_COOLDOWN
end

-- Segurar: desce 1 faixa agora e a cada HOLD_DESCEND_EVERY enquanto o dedo estiver no botão.
local function beginHold(p: Player)
	local seq = (holdSeq[p] or 0) + 1
	holdSeq[p] = seq
	holding[p] = true
	task.spawn(function()
		while holding[p] and holdSeq[p] == seq do
			local k = flying[p]
			if k and k.status == STATUS_FLYING and k.faixa > 0 then
				setFaixa(k, k.faixa - 1)
			end
			task.wait(Config.HOLD_DESCEND_EVERY)
		end
	end)
end

local function endHold(p: Player)
	holding[p] = nil
end

local function onPull(p: Player, phase: unknown)
	if not pullLimiter:allow(p) then
		return
	end
	if phase ~= "Down" and phase ~= "Up" then
		return
	end
	lastPull[p] = os.clock()
	afkNextDrop[p] = nil
	onboarding(p, 2)
	if phase == "Down" then
		if holdStart[p] then
			return -- já pressionado
		end
		local t0 = os.clock()
		holdStart[p] = t0
		task.delay(Config.TAP_MAX, function()
			if holdStart[p] == t0 then
				beginHold(p)
			end
		end)
	else
		local t0 = holdStart[p]
		if not t0 then
			return
		end
		holdStart[p] = nil
		if os.clock() - t0 < Config.TAP_MAX then
			onTap(p)
		else
			endHold(p)
		end
		lastHoldEnd[p] = os.clock()
	end
end

-- Anti-AFK (§3.3): AFK_SECONDS sem Pull → desce 1 faixa a cada AFK_DROP_EVERY.
local function antiAfk(p: Player)
	local k = flying[p]
	local clock = os.clock()
	if not k or k.status ~= STATUS_FLYING or k.faixa == 0 then
		return
	end
	if clock - (lastPull[p] or clock) < Config.AFK_SECONDS then
		return
	end
	if clock >= (afkNextDrop[p] or 0) then
		setFaixa(k, k.faixa - 1)
		afkNextDrop[p] = clock + Config.AFK_DROP_EVERY
	end
end

-- Selvagens (§2.8) -----------------------------------------------------------------------------------

local function countWilds(): number
	local n = 0
	for _, k in kites do
		if k.wild and k.tutorialFor == nil and (k.status == STATUS_FLYING or k.status == STATUS_DUELING) then
			n += 1
		end
	end
	return n
end

local function activeBoost(t: number): WildBoost?
	local boost = wildBoost
	if boost and boost.untilTime > t then
		return boost
	end
	return nil
end

local function wildInterval(t: number): number
	local boost = activeBoost(t)
	if boost then
		return rng:NextNumber(boost.intervalMin, boost.intervalMax)
	end
	return rng:NextNumber(Config.WILD_INTERVAL[1], Config.WILD_INTERVAL[2])
end

-- Ponto onde a Pipa de Treino paira: ao lado da pipa do novato (ou da laje dele), rumo ao centro.
local function tutorialHover(k: KiteState): Vector3
	local p = k.tutorialFor
	local mine = if p then flying[p] else nil
	local base: Vector3
	if mine and mine.faixa >= 1 then
		base = mine.pos
	else
		base = MapGen.lajeFloor(k.laje or 1) + Vector3.new(0, Config.FAIXA_HEIGHT_ABOVE_LAJE[1], 0)
	end
	local flat = Vector3.new(base.X, 0, base.Z)
	local dir = if flat.Magnitude > 0 then -flat.Unit else Vector3.xAxis
	return base + dir * (Config.RABEIO_RANGE / 2)
end

local function wildStep(k: KiteState, dt: number)
	if k.status ~= STATUS_FLYING then
		return
	end
	local phase = k.wildPhase
	local h = Config.RING[math.max(3, k.faixa)].h
	if phase == "Tutorial" then
		k.pos = moveToward(k.pos, tutorialHover(k), Config.WILD_SPEED * dt)
	elseif phase == "Enter" then
		local target = k.wildTarget or k.pos
		k.pos = moveToward(k.pos, target, Config.WILD_SPEED * dt)
		if k.pos == target then
			k.wildPhase = "Orbit"
			k.orbitLeft = 2 * math.pi
		end
	elseif phase == "Orbit" then
		k.theta -= windSign * Config.WILD_OMEGA * dt -- contra o vento
		k.orbitLeft = (k.orbitLeft or 0) - Config.WILD_OMEGA * dt
		k.pos = ringPos(Config.WILD_RING_R, h, k.theta)
		if (k.orbitLeft or 0) <= 0 then
			k.wildPhase = "Exit"
			k.wildTarget = ringPos(Config.MAP_RADIUS, h, k.theta)
		end
	elseif phase == "Exit" then
		local target = k.wildTarget or k.pos
		k.pos = moveToward(k.pos, target, Config.WILD_SPEED * dt)
		if k.pos == target then
			destroyKite(k)
		end
	end
end

-- Tick (SYNC_HZ) ---------------------------------------------------------------------------------------

-- Deriva no anel (§2.4) e transições a KITE_MOVE_SPEED; quem rabeou mergulha RABEIO_DIVE.
local function playerStep(k: KiteState, dt: number)
	if k.status == STATUS_FLYING and k.faixa >= 3 then
		local peso = 1 - Config.RARITY_WEIGHT_STEP * (k.rarity - 1)
		k.theta += windSign * Config.RING[k.faixa].omega * peso * dt
	end
	local goal = if k.status == STATUS_DUELING and k.diveTarget then k.diveTarget else lajeGoal(k)
	k.pos = moveToward(k.pos, goal, Config.KITE_MOVE_SPEED * dt)
end

local function fallStep(k: KiteState, t: number, dt: number)
	local land = k.landPos or k.pos
	local remaining = k.statusUntil - t
	if remaining <= 0 then
		k.pos = land
		k.status = STATUS_GROUND
		k.statusUntil = t + Config.GROUND_TIME
	else
		k.pos = k.pos:Lerp(land, math.min(1, dt / remaining))
	end
end

local function stepKite(k: KiteState, t: number, dt: number)
	if k.status == STATUS_FLYING or k.status == STATUS_DUELING then
		if k.wild then
			if k.status == STATUS_DUELING and k.diveTarget then
				k.pos = moveToward(k.pos, k.diveTarget, Config.KITE_MOVE_SPEED * dt)
			else
				wildStep(k, dt)
			end
		else
			playerStep(k, dt)
		end
	elseif k.status == STATUS_FALLING then
		fallStep(k, t, dt)
	elseif k.status == STATUS_GROUND then
		local catcher = nearestCatcher(k, Config.CATCH_RADIUS, t)
		if catcher then
			catchKite(catcher, k)
		elseif t >= k.statusUntil then
			if k.rain then
				destroyKite(k) -- Chuva de Pipas: não pegas somem
			else
				toTree(k, t)
			end
		end
	elseif k.status == STATUS_TREE then
		local catcher = nearestCatcher(k, Config.TREE_CATCH_RADIUS, t)
		if catcher then
			catchKite(catcher, k)
		elseif t >= k.statusUntil then
			treeExpire(k)
		end
	end
end

local function spawnWildIfDue(t: number)
	if t < nextWildAt then
		return
	end
	local boost = activeBoost(t)
	local maxInAir = if boost then boost.maxInAir else Config.WILD_MAX
	if countWilds() < maxInAir then
		KiteService.spawnWild(nil, nil, nil)
	end
	nextWildAt = t + wildInterval(t)
end

local function tick(t: number, dt: number)
	for _, p in Players:GetPlayers() do
		sampleMovement(p, t)
		local data = dataOf(p)
		if data then
			watchSelection(p, data)
			antiAfk(p)
			updateVaral(p, data)
		end
	end
	local snapshot = {}
	for _, k in kites do
		table.insert(snapshot, k)
	end
	for _, k in snapshot do
		if kites[k.id] == k then
			stepKite(k, t, dt)
		end
	end
	for i = #duels, 1, -1 do
		local d = duels[i]
		if t >= d.endsAt then
			table.remove(duels, i)
			resolveDuel(d, t)
		end
	end
	spawnWildIfDue(t)
	for _, k in kites do
		syncConf(k)
	end
end

-- Jogadores -------------------------------------------------------------------------------------------

local function onLoaded(p: Player, data: ProfileData)
	lastPull[p] = os.clock()
	onboarding(p, 1)
	watchSelection(p, data)
	updateVaral(p, data)
	-- Pipa de Treino aos TUTORIAL_AT s de sessão, se ainda é novato e nunca cortou
	task.delay(Config.TUTORIAL_AT, function()
		local current = dataOf(p)
		if p.Parent ~= Players or tutorialGiven[p] or not current then
			return
		end
		if not DataService.isNovato(p) or current.Onboarding >= 4 then
			return
		end
		tutorialGiven[p] = true
		KiteService.spawnWild(WILD_TUTORIAL_RARITY, nil, { tutorialFor = p, points = Config.TUTORIAL_WILD_POINTS })
	end)
end

local function onPlayerRemoving(p: Player)
	local mine = flying[p]
	if mine then
		destroyKite(mine)
	end
	local tutorials = {}
	for _, k in kites do
		if k.tutorialFor == p then
			table.insert(tutorials, k)
		end
	end
	for _, k in tutorials do
		destroyKite(k)
	end
	holdStart[p] = nil
	holding[p] = nil
	holdSeq[p] = nil
	lastHoldEnd[p] = nil
	tapCooldown[p] = nil
	lastPull[p] = nil
	afkNextDrop[p] = nil
	moveSample[p] = nil
	catchBanUntil[p] = nil
	tutorialGiven[p] = nil
	pullLimiter:forget(p)
	selectLimiter:forget(p)
	emoteLimiter:forget(p)
end

local function onEmote(p: Player, id: unknown)
	if not emoteLimiter:allow(p) then
		return
	end
	local max = if p:GetAttribute("VIP") == true then 5 else 4
	if not Remotes.isInt(id, 1, max) then
		return
	end
	local name = `emote{id}`
	p:SetAttribute("Emote", name)
	task.delay(Config.EMOTE_SECONDS, function()
		if p.Parent == Players and p:GetAttribute("Emote") == name then
			p:SetAttribute("Emote", "")
		end
	end)
end

-- API pública -------------------------------------------------------------------------------------------

function KiteService.start(): ()
	DataService.hooks.faixaOf = KiteService.faixaOf
	local w = world()
	local sign = w:GetAttribute("WindSign")
	windSign = if sign == -1 then -1 else 1
	statesFolder()

	Remotes.get("Pull").OnServerEvent:Connect(onPull)
	Remotes.get("SelectKite").OnServerEvent:Connect(function(p: Player, kiteId: unknown)
		if not selectLimiter:allow(p) then
			return
		end
		local data = dataOf(p)
		if not data or not Remotes.isInt(kiteId, 1, data.NextKiteId) then
			return
		end
		KiteService.select(p, kiteId :: number)
	end)
	Remotes.get("Emote").OnServerEvent:Connect(onEmote)

	DataService.onLoaded(onLoaded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	nextWildAt = now() + wildInterval(now())
	task.spawn(function()
		while true do
			local dt = task.wait(1 / Config.SYNC_HZ)
			local ok, err = pcall(function(): string?
				tick(now(), dt)
				return nil
			end)
			if not ok then
				warn(`[KiteService] tick falhou: {err}`)
			end
		end
	end)
end

function KiteService.flyingOf(p: Player): KiteState?
	return flying[p]
end

-- Faixa da pipa no ar (0 se nada no ar).
function KiteService.faixaOf(p: Player): number
	local k = flying[p]
	return if k then k.faixa else 0
end

-- Troca a pipa selecionada; só com a atual Flying na faixa 0 (ou nada no ar).
function KiteService.select(p: Player, kiteId: number): boolean
	local data = dataOf(p)
	if not data or DataService.findKite(p, kiteId) == nil then
		return false
	end
	local k = flying[p]
	if k and (k.status ~= STATUS_FLYING or k.faixa ~= 0) then
		return false
	end
	if k and k.profileId == kiteId then
		return true
	end
	if k then
		destroyKite(k)
	end
	data.Selected = kiteId
	DataService.pushState(p, { Selected = kiteId })
	putUp(p, kiteId)
	updateVaral(p, data)
	return true
end

-- Puxa a pipa para a faixa 0 na hora (se estiver em duelo, vale depois dele).
function KiteService.recall(p: Player): ()
	local k = flying[p]
	if not k then
		return
	end
	setFaixa(k, 0)
	if k.status == STATUS_FLYING then
		k.pos = lajeGoal(k)
	end
end

-- Selvagem: entra pela borda, uma volta contra o vento no anel WILD_RING_R e sai; com tutorialFor,
-- é a Pipa de Treino que paira ao lado da pipa do novato.
function KiteService.spawnWild(rarity: number?, color: number?, opts: WildOpts?): KiteState
	local t = now()
	local boost = activeBoost(t)
	local weights = if boost then boost.weights else Config.WILD_TABLE
	local r = rarity or KiteService.rollRarity(weights)
	local c = color or rng:NextInteger(1, Config.COSMETIC_COLORS)
	local k = newState(0, "", Config.MODEL_BY_RARITY[r] or Config.MODEL_BY_RARITY[1], r, c, false, true)
	local tutorialFor = if opts then opts.tutorialFor else nil
	if tutorialFor then
		local laje = DataService.lajeOf(tutorialFor)
		k.tutorialFor = tutorialFor
		k.points = if opts and opts.points ~= nil then opts.points else Config.WILD_POINTS[r]
		k.laje = math.max(1, laje)
		k.faixa = 1
		k.wildPhase = "Tutorial"
		local angle = MapGen.lajeAngle(k.laje or 1)
		k.pos = ringPos(Config.MAP_RADIUS, Config.LAJE_FLOOR_Y + Config.FAIXA_HEIGHT_ABOVE_LAJE[1], angle)
	else
		local faixa = if rng:NextInteger(0, 1) == 0 then 3 else 4
		local h = Config.RING[faixa].h
		local phi = rng:NextNumber(0, 2 * math.pi)
		k.faixa = faixa
		k.theta = phi
		k.wildPhase = "Enter"
		k.pos = ringPos(Config.MAP_RADIUS, h, phi)
		k.wildTarget = ringPos(Config.WILD_RING_R, h, phi)
		if opts and opts.points ~= nil then
			k.points = opts.points
		end
	end
	syncConf(k)
	return k
end

-- Pipa caindo de RAIN_FROM_Y em RAIN_FALL_TIME até landPos (Chuva de Pipas). Sem dono (nil/0) ela some
-- se ninguém pegar em GROUND_TIME; com dono vai à árvore como uma pipa cortada.
function KiteService.drop(model: string, rarity: number, color: number, landPos: Vector3, ownerId: number?): KiteState
	local owner = ownerId or 0
	local ownerPl = if owner ~= 0 then Players:GetPlayerByUserId(owner) else nil
	local k = newState(owner, if ownerPl then ownerPl.DisplayName else "", model, rarity, color, false, false)
	k.status = STATUS_FALLING
	k.pos = Vector3.new(landPos.X, Config.RAIN_FROM_Y, landPos.Z)
	k.landPos = landPos
	k.statusUntil = now() + Config.RAIN_FALL_TIME
	k.rain = owner == 0
	syncConf(k)
	return k
end

-- Produto "Resgatar da Árvore": devolve ao varal a própria pipa presa na árvore.
function KiteService.rescueFromTree(p: Player): boolean
	if not dataOf(p) then
		return false
	end
	for _, k in kites do
		if k.status == STATUS_TREE and k.owner == p.UserId then
			DataService.addKite(p, k.model, k.rarity, k.color, k.golden)
			destroyKite(k)
			return true
		end
	end
	return false
end

-- +1 ou -1 (atributo WindSign de workspace.World).
function KiteService.setWind(sign: number): ()
	windSign = if sign < 0 then -1 else 1
	world():SetAttribute("WindSign", windSign)
end

-- Rajada / Rajada no Servidor: intervalo, máximo no ar e tabela de raridade até untilTime.
function KiteService.setWildBoost(intervalMin: number, intervalMax: number, maxInAir: number, weights: { number }, untilTime: number): ()
	wildBoost = { intervalMin = intervalMin, intervalMax = intervalMax, maxInAir = maxInAir, weights = weights, untilTime = untilTime }
	nextWildAt = math.min(nextWildAt, now() + rng:NextNumber(intervalMin, intervalMax))
end

-- Jogadores com a pipa no Céu Aberto (faixa 4) agora.
function KiteService.playersAtFaixa4(): { Player }
	local list = {}
	for p, k in flying do
		if k.faixa == 4 and (k.status == STATUS_FLYING or k.status == STATUS_DUELING) then
			table.insert(list, p)
		end
	end
	return list
end

-- Vento Dourado: golden = true permanente (×GOLDEN_MULT) + Toast("Dourada") para todos.
function KiteService.makeGolden(p: Player, kiteId: number): ()
	local data = dataOf(p)
	local kd = DataService.findKite(p, kiteId)
	if not data or not kd or kd.golden then
		return
	end
	kd.golden = true
	DataService.pushState(p, { Kites = data.Kites })
	local k = flying[p]
	if k and k.profileId == kiteId then
		k.golden = true
		syncConf(k)
	end
	updateVaral(p, data)
	toast(nil, "Dourada", { name = p.DisplayName, kite = kd.model })
end

-- (winner, loser, wild): wild = o duelo envolveu uma selvagem. ShopService usa para "Corte 3 selvagens".
function KiteService.onDuelEnd(cb: DuelEndCallback): ()
	table.insert(duelEndCallbacks, cb)
end

-- (p, k) a cada pega no campinho/árvore. ShopService usa para "Pegue 1 pipa".
function KiteService.onCatch(cb: CatchCallback): ()
	table.insert(catchCallbacks, cb)
end

return KiteService
