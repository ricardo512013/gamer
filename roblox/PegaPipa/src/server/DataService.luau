--!strict
--[[
	DataService — perfis (ProfileStore), laje do jogador, leaderstats, renda offline,
	Carretel/Vento, atributos do Player (GDD §7.4) e envio de estado ao cliente (State/Toast).

	Regras:
	- É a ÚNICA porta de entrada/saída de Vento: addVento / spendVento / collect.
	- Não requer nenhum outro serviço no topo (o analisador proíbe ciclos de require, mesmo
	  preguiçosos). O que vem "de cima" (KiteService, EventService, MonetizationService,
	  Leaderboard) entra por DataService.hooks, preenchido por esses serviços no start() deles.
	  MapGen (que só depende de Config) é requerido preguiçosamente dentro das funções.
	- Todo número vive em Config.
	- Quem altera profile.Data diretamente (ShopService, KiteService…) chama
	  DataService.pushState(p, { Campo = valor }) com os campos que mudou.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local AnalyticsService = game:GetService("AnalyticsService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ProfileStore = require(script.Parent.ProfileStore)

export type ProfileData = Config.ProfileData
export type KiteData = Config.KiteData
export type Patch = { [string]: any }
export type WeeklyStat = "Vento" | "CortesPvP"

-- Perfil do ProfileStore visto pelo jogo, com Data/LastSavedData tipados como ProfileData.
-- (O genérico vendorizado `Profile<T>` usa `T & JSONAcceptable`, que o luau-lsp não unifica;
-- o cast para este tipo acontece uma única vez, em onPlayerAdded.)
type Connection = { Disconnect: (self: any) -> () }
export type Profile = {
	Data: ProfileData,
	LastSavedData: ProfileData, -- último snapshot salvo (idempotência do ProcessReceipt)
	Key: string,
	UserIds: { number },
	OnSave: { Connect: (self: any, listener: () -> ()) -> Connection },
	OnLastSave: { Connect: (self: any, listener: (reason: string) -> ()) -> Connection },
	OnSessionEnd: { Connect: (self: any, listener: () -> ()) -> Connection },
	OnAfterSave: { Connect: (self: any, listener: (lastSaved: ProfileData) -> ()) -> Connection },
	IsActive: (self: Profile) -> boolean,
	Reconcile: (self: Profile) -> (),
	EndSession: (self: Profile) -> (),
	AddUserId: (self: Profile, userId: number) -> (),
	Save: (self: Profile) -> (),
}

local STORE_NAME = "PegaPipa_v1"
local KICK_LOAD_FAILED = "Falha ao carregar seus dados. Tente entrar de novo."
local KICK_SESSION_END = "Seus dados foram abertos em outro servidor. Entre de novo."

-- MapGen só é requerido dentro das funções (depois de MapGen.start()).
local function map()
	return require(script.Parent.MapGen)
end

local DataService = {}

-- Ganchos preenchidos pelos serviços de cima no start() deles. Os padrões são o comportamento
-- "sem o serviço": nada no ar, sem evento, sem passe, sem ranking.
DataService.hooks = {
	faixaOf = function(_p: Player): number -- KiteService (0 = nada no ar)
		return 0
	end,
	ventoMultiplier = function(): number -- EventService (1 / 2 / 4)
		return 1
	end,
	ventoMult = function(_p: Player): number -- MonetizationService: Vento em Dobro → 2
		return 1
	end,
	hasAutoReel = function(_p: Player): boolean -- MonetizationService: Carretel Automático
		return false
	end,
	isVIP = function(_p: Player): boolean -- MonetizationService
		return false
	end,
	offlineCap = function(_p: Player): number -- MonetizationService: OFFLINE_CAP ou OFFLINE_CAP_VIP
		return Config.OFFLINE_CAP
	end,
	addWeekly = function(_p: Player, _stat: WeeklyStat, _n: number) -- Leaderboard
	end,
}

-- Estado interno -------------------------------------------------------------------------------

local store = ProfileStore.New(STORE_NAME, Config.PROFILE_TEMPLATE)
local activeStore: typeof(store.Mock) = store
local storeDecided = false

local profiles: { [Player]: Profile } = {}
local lajeByPlayer: { [Player]: number } = {}
local rateCache: { [Player]: number } = {}
local rendaAcc: { [Player]: number } = {} -- Renda acumulada para o log de economia (1x/min)
local friendsOf: { [Player]: { [Player]: boolean } } = {}
local loadedCallbacks: { (p: Player, data: ProfileData) -> () } = {}

local stateRemote: RemoteEvent? = nil
local toastRemote: RemoteEvent? = nil
local collectLimiter = Remotes.limiter(Config.RATE.Collect[1], Config.RATE.Collect[2])

-- Enum.AnalyticsEconomyTransactionType por fonte/sumidouro (padrão: Gameplay)
local TRANSACTION_TYPE: { [string]: string } = {
	Renda = "Gameplay", Offline = "Gameplay", Streak = "TimedReward", Daily = "TimedReward",
	VendaAuto = "Shop", Kit = "IAP", Produto = "IAP",
	Pipa = "Shop", Linha = "Shop", Vaga = "Shop", Renascer = "ProgressionReward",
}

-- Ajudantes ------------------------------------------------------------------------------------

local function dataOf(p: Player): ProfileData?
	local profile = profiles[p]
	if profile and profile:IsActive() then
		return profile.Data
	end
	return nil
end

local function rootOf(p: Player): BasePart?
	local character = p.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Log de economia: print + AnalyticsService (dentro de pcall; opcional).
local function logEconomy(p: Player, flow: Enum.AnalyticsEconomyFlowType, amount: number, balance: number, kind: string)
	if amount <= 0 then
		return
	end
	print(`[Economia] {p.Name} {flow.Name} {kind} {math.floor(amount)} → saldo {math.floor(balance)}`)
	pcall(function()
		AnalyticsService:LogEconomyEvent(p, flow, "Vento", math.floor(amount), math.floor(balance), TRANSACTION_TYPE[kind] or "Gameplay", kind)
	end)
end

local function createLeaderstats(p: Player)
	if p:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, name in { "Vento", "Pipas", "Cortes", "Temporadas" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Value = 0
		value.Parent = folder
	end
	folder.Parent = p
end

local function syncLeaderstats(p: Player, data: ProfileData)
	local folder = p:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local function set(name: string, value: number)
		local stat = folder:FindFirstChild(name)
		if stat and stat:IsA("IntValue") then
			stat.Value = math.floor(value)
		end
	end
	set("Vento", data.Vento)
	set("Pipas", #data.Kites)
	set("Cortes", data.Stats.Cortes)
	set("Temporadas", data.Temporadas)
end

local function hasFriend(p: Player): boolean
	local set = friendsOf[p]
	return set ~= nil and next(set) ~= nil
end

-- Marca amizades com quem já está no servidor (bônus FRIEND_BONUS para os dois).
local function registerFriends(p: Player)
	for _, other in Players:GetPlayers() do
		if other ~= p then
			task.spawn(function()
				local ok, isFriend = pcall(p.IsFriendsWithAsync, p, other.UserId)
				local mine, theirs = friendsOf[p], friendsOf[other]
				if ok and isFriend == true and mine and theirs then
					mine[other] = true
					theirs[p] = true
				end
			end)
		end
	end
end

local function carretelCap(p: Player): number
	local rate = rateCache[p] or DataService.rateOf(p)
	return Config.CARRETEL_CAP_SECONDS * rate
end

local function novatoUntil(data: ProfileData): number
	return Workspace:GetServerTimeNow() + math.max(0, Config.NOVATO_SECONDS - data.PlayTime)
end

-- Patch completo enviado no load (as outras mudanças mandam só os campos alterados).
local function fullState(p: Player, data: ProfileData): Patch
	return {
		Vento = data.Vento,
		Carretel = data.Carretel,
		CarretelCap = carretelCap(p),
		Rate = rateCache[p] or 0,
		Linha = data.Linha,
		Vagas = data.Vagas,
		Temporadas = data.Temporadas,
		Kites = data.Kites,
		Selected = data.Selected,
		Streak = data.Streak,
		Dailies = data.Dailies,
		Novato = data.PlayTime < Config.NOVATO_SECONDS,
		NovatoUntil = novatoUntil(data),
		Onboarding = data.Onboarding,
	}
end

-- Vento entrando de fato no saldo (depois do carretel). Renda é logada agregada 1x/min.
local function creditVento(p: Player, data: ProfileData, n: number, source: string)
	data.Vento += n
	data.Stats.VentoTotal += n
	DataService.hooks.addWeekly(p, "Vento", n)
	if source == "Renda" then
		rendaAcc[p] = (rendaAcc[p] or 0) + n
	else
		logEconomy(p, Enum.AnalyticsEconomyFlowType.Source, n, data.Vento, source)
		DataService.pushState(p, { Vento = data.Vento })
	end
end

-- API pública: Vento ---------------------------------------------------------------------------

-- V/s atual (GDD §3.3). A pipa selecionada usa FAIXA_MULT[faixa]; as outras, VARAL_MULT.
function DataService.rateOf(p: Player): number
	local data = dataOf(p)
	if not data then
		return 0
	end
	local airMult = Config.FAIXA_MULT[DataService.hooks.faixaOf(p)] or Config.VARAL_MULT
	local sum = 0
	for _, k in data.Kites do
		local posMult = if k.id == data.Selected then airMult else Config.VARAL_MULT
		sum += Config.baseRate(k) * posMult
	end
	local friendMult = if hasFriend(p) then Config.FRIEND_BONUS else 1
	return sum
		* (1 + Config.REBIRTH_BONUS * data.Temporadas)
		* DataService.hooks.ventoMult(p)
		* DataService.hooks.ventoMultiplier()
		* friendMult
end

-- Única entrada de Vento. source "Renda" cai no carretel (cap CARRETEL_CAP_SECONDS × V/s),
-- salvo Carretel Automático; qualquer outra fonte (Offline, Streak, Daily, VendaAuto, Kit, Produto)
-- vai direto ao saldo e é logada.
function DataService.addVento(p: Player, n: number, source: string): ()
	local data = dataOf(p)
	if not data or not Remotes.isFinite(n) or n <= 0 then
		return
	end
	if source == "Renda" and not DataService.hooks.hasAutoReel(p) then
		local cap = carretelCap(p)
		data.Carretel = math.max(data.Carretel, math.min(cap, data.Carretel + n))
		return -- o tick de INCOME_TICK envia Carretel/CarretelCap
	end
	creditVento(p, data, n, source)
end

-- Gasta Vento; false se não há saldo. sink: Pipa | Linha | Vaga | Renascer.
function DataService.spendVento(p: Player, n: number, sink: string): boolean
	local data = dataOf(p)
	if not data or not Remotes.isFinite(n) or n < 0 or data.Vento < n then
		return false
	end
	data.Vento -= n
	logEconomy(p, Enum.AnalyticsEconomyFlowType.Sink, n, data.Vento, sink)
	DataService.pushState(p, { Vento = data.Vento })
	return true
end

-- Carretel → Vento se o jogador está a ≤ COLLECT_DIST do próprio carretel. Retorna o valor coletado.
function DataService.collect(p: Player): number
	local data = dataOf(p)
	local laje = lajeByPlayer[p]
	local root = rootOf(p)
	if not data or not laje or laje == 0 or not root then
		return 0
	end
	if (root.Position - map().carretelPos(laje)).Magnitude > Config.COLLECT_DIST then
		return 0
	end
	local n = data.Carretel
	if n <= 0 then
		return 0
	end
	data.Carretel = 0
	creditVento(p, data, n, "Renda")
	DataService.pushState(p, { Vento = data.Vento, Carretel = 0 })
	return n
end

-- API pública: pipas ---------------------------------------------------------------------------

local function kiteValue(k: KiteData): number -- venda automática: AUTO_SELL_MULT × base × (dourada ? 5 : 1)
	return Config.AUTO_SELL_MULT * Config.baseRate(k)
end

-- Candidata à venda automática: não é Jornal, não é estimação, não é de Temporada e não está selecionada
-- (a selecionada fica de fora para o KiteService nunca ver sua pipa no ar sumir do varal).
local function canAutoSell(k: KiteData, data: ProfileData): boolean
	return not k.starter and not k.pet and k.season == 0 and k.id ~= data.Selected
end

local function autoSell(p: Player, data: ProfileData, k: KiteData)
	local value = kiteValue(k)
	creditVento(p, data, value, "VendaAuto")
	DataService.toast(p, "VendaAuto", { kite = k.model, rarity = k.rarity, n = value })
end

-- Cria a pipa no varal. Varal cheio (#Kites == Vagas) → venda automática (GDD §3.4):
-- vende a candidata de menor valor, ou a própria pipa nova se ela vale ≤ a candidata (retorna nil).
function DataService.addKite(p: Player, model: string, rarity: number, color: number, golden: boolean?): KiteData?
	local data = dataOf(p)
	if not data then
		return nil
	end
	local newKite: KiteData = {
		id = data.NextKiteId,
		model = model,
		rarity = rarity,
		color = color,
		golden = golden == true,
		pet = false,
		season = 0,
		starter = false,
	}
	data.NextKiteId += 1
	if #data.Kites >= data.Vagas then
		local worstIndex, worstValue = 0, math.huge
		for i, k in data.Kites do
			if canAutoSell(k, data) and kiteValue(k) < worstValue then
				worstIndex, worstValue = i, kiteValue(k)
			end
		end
		if worstIndex == 0 or kiteValue(newKite) <= worstValue then
			autoSell(p, data, newKite)
			DataService.pushState(p, { Kites = data.Kites })
			return nil
		end
		local sold = table.remove(data.Kites, worstIndex) :: KiteData
		autoSell(p, data, sold)
	end
	table.insert(data.Kites, newKite)
	DataService.pushState(p, { Kites = data.Kites, Selected = data.Selected })
	return newKite
end

-- Tira a pipa do varal (corte, renascer). Se era a selecionada, Selected vira 0 (KiteService escolhe outra).
function DataService.removeKite(p: Player, id: number): KiteData?
	local data = dataOf(p)
	if not data then
		return nil
	end
	for i, k in data.Kites do
		if k.id == id then
			table.remove(data.Kites, i)
			if data.Selected == id then
				data.Selected = 0
			end
			DataService.pushState(p, { Kites = data.Kites, Selected = data.Selected })
			return k
		end
	end
	return nil
end

function DataService.findKite(p: Player, id: number): KiteData?
	local data = dataOf(p)
	if not data then
		return nil
	end
	for _, k in data.Kites do
		if k.id == id then
			return k
		end
	end
	return nil
end

-- API pública: consultas -----------------------------------------------------------------------

function DataService.get(p: Player): Profile?
	local profile = profiles[p]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

function DataService.lajeOf(p: Player): number
	return lajeByPlayer[p] or 0
end

function DataService.isNovato(p: Player): boolean
	local data = dataOf(p)
	return data ~= nil and data.PlayTime < Config.NOVATO_SECONDS
end

-- Chama cb para todo perfil carregado (inclusive os que já estavam carregados ao registrar).
function DataService.onLoaded(cb: (p: Player, data: ProfileData) -> ()): ()
	table.insert(loadedCallbacks, cb)
	for p in profiles do
		local data = dataOf(p)
		if data then
			task.spawn(cb, p, data)
		end
	end
end

-- API pública: cliente -------------------------------------------------------------------------

-- Envia um patch de State (§7.3) e espelha leaderstats/atributo Temporadas.
function DataService.pushState(p: Player, patch: Patch): ()
	local data = dataOf(p)
	if data then
		syncLeaderstats(p, data)
		p:SetAttribute("Temporadas", data.Temporadas)
	end
	if stateRemote then
		stateRemote:FireClient(p, patch)
	end
end

-- Toast para um jogador ou para todos (p = nil). kinds em §7.3.
function DataService.toast(p: Player?, kind: string, args: Patch): ()
	if not toastRemote then
		return
	end
	if p then
		toastRemote:FireClient(p, kind, args)
	else
		toastRemote:FireAllClients(kind, args)
	end
end

-- Laje -----------------------------------------------------------------------------------------

local function assignLaje(p: Player): number
	for i = 1, Config.LAJE_COUNT do
		local model = map().lajeModel(i)
		if model:GetAttribute("OwnerId") == 0 then
			model:SetAttribute("OwnerId", p.UserId)
			lajeByPlayer[p] = i
			p:SetAttribute("Laje", i)
			return i
		end
	end
	warn(`[DataService] sem laje livre para {p.Name}`)
	return 0
end

local function releaseLaje(p: Player)
	local i = lajeByPlayer[p]
	lajeByPlayer[p] = nil
	if not i or i == 0 then
		return
	end
	local ok, model = pcall(function()
		return map().lajeModel(i)
	end)
	if ok and model:GetAttribute("OwnerId") == p.UserId then
		model:SetAttribute("OwnerId", 0)
	end
end

local function spawnOnLaje(p: Player, character: Model)
	local i = lajeByPlayer[p]
	if not i or i == 0 then
		return
	end
	task.wait()
	character:PivotTo(CFrame.new(map().lajeFloor(i) + Vector3.new(0, 3, 0)))
end

-- Carga do perfil ------------------------------------------------------------------------------

-- Renda offline (§3.3): todas as pipas a OFFLINE_MULT, sem evento/amizade, elapsed limitado ao cap.
local function creditOffline(p: Player, data: ProfileData)
	if data.LastSeen <= 0 then
		return
	end
	local elapsed = math.min(os.time() - data.LastSeen, DataService.hooks.offlineCap(p))
	if elapsed < Config.OFFLINE_MIN then
		return
	end
	local sum = 0
	for _, k in data.Kites do
		sum += Config.baseRate(k)
	end
	local amount = math.floor(sum * Config.OFFLINE_MULT * (1 + Config.REBIRTH_BONUS * data.Temporadas) * DataService.hooks.ventoMult(p) * elapsed)
	if amount <= 0 then
		return
	end
	creditVento(p, data, amount, "Offline")
	DataService.toast(p, "Offline", { n = amount, time = elapsed })
end

local function onProfileLoaded(p: Player, data: ProfileData)
	createLeaderstats(p)
	p:SetAttribute("Novato", data.PlayTime < Config.NOVATO_SECONDS)
	p:SetAttribute("VIP", DataService.hooks.isVIP(p))
	p:SetAttribute("RabiolaRank", 0)
	p:SetAttribute("Emote", "")
	p:SetAttribute("Temporadas", data.Temporadas)
	creditOffline(p, data)
	data.LastSeen = os.time()
	rateCache[p] = DataService.rateOf(p)
	DataService.pushState(p, fullState(p, data))
	for _, cb in loadedCallbacks do
		task.spawn(cb, p, data)
	end
end

local function onPlayerAdded(p: Player)
	friendsOf[p] = {}
	registerFriends(p)
	assignLaje(p)
	p.CharacterAdded:Connect(function(character)
		spawnOnLaje(p, character)
	end)
	if p.Character then
		task.spawn(spawnOnLaje, p, p.Character)
	end

	while not storeDecided do
		task.wait()
	end
	local raw = activeStore:StartSessionAsync(`User_{p.UserId}`, { Steal = false })
	if raw == nil then
		p:Kick(KICK_LOAD_FAILED)
		return
	end
	local profile = (raw :: any) :: Profile
	profile:AddUserId(p.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[p] = nil
		if p.Parent == Players then
			p:Kick(KICK_SESSION_END)
		end
	end)
	if p.Parent ~= Players then
		profile:EndSession()
		return
	end
	profiles[p] = profile
	onProfileLoaded(p, profile.Data)
end

local function onPlayerRemoving(p: Player)
	local profile = profiles[p]
	if profile then
		if profile:IsActive() then
			local data: ProfileData = profile.Data
			data.LastSeen = os.time()
		end
		profiles[p] = nil
		profile:EndSession()
	end
	releaseLaje(p)
	local set = friendsOf[p]
	if set then
		for other in set do
			local theirs = friendsOf[other]
			if theirs then
				theirs[p] = nil
			end
		end
	end
	friendsOf[p] = nil
	rateCache[p] = nil
	rendaAcc[p] = nil
	collectLimiter:forget(p)
end

-- Tick de renda (INCOME_TICK s) ------------------------------------------------------------------

local function tickPlayer(p: Player, dt: number)
	local data = dataOf(p)
	if not data then
		return
	end
	data.PlayTime += dt
	data.LastSeen = os.time()
	if p:GetAttribute("Novato") == true and data.PlayTime >= Config.NOVATO_SECONDS then
		p:SetAttribute("Novato", false)
		DataService.pushState(p, { Novato = false })
	end
	local rate = DataService.rateOf(p)
	rateCache[p] = rate
	DataService.addVento(p, rate * dt, "Renda")
	DataService.pushState(p, { Vento = data.Vento, Carretel = data.Carretel, CarretelCap = carretelCap(p), Rate = rate })
end

local function flushRendaLog()
	for p, n in rendaAcc do
		local data = dataOf(p)
		if data and n > 0 then
			logEconomy(p, Enum.AnalyticsEconomyFlowType.Source, n, data.Vento, "Renda")
		end
		rendaAcc[p] = 0
	end
end

local function startTick()
	task.spawn(function()
		local sinceLog = 0
		while true do
			local dt = task.wait(Config.INCOME_TICK)
			for p in profiles do
				local ok, err = pcall(function(): string?
					tickPlayer(p, dt)
					return nil
				end)
				if not ok then
					warn(`[DataService] tick de {p.Name} falhou: {err}`)
				end
			end
			sinceLog += dt
			if sinceLog >= Config.ECONOMY_LOG_EVERY then
				sinceLog = 0
				flushRendaLog()
			end
		end
	end)
end

-- No Studio sem acesso à API do DataStore usa ProfileStore.Mock (nada é salvo).
local function decideStore()
	if RunService:IsStudio() then
		local ok = pcall(function()
			DataStoreService:GetDataStore("PegaPipa_probe"):GetAsync("probe")
		end)
		if not ok then
			warn("[DataService] API do DataStore indisponível no Studio: usando ProfileStore.Mock (nada será salvo)")
			activeStore = store.Mock
		end
	end
	storeDecided = true
end

-- Prompt "Pegar Vento" do carretel (criado pelo MapGen com a tag Carretel).
local function hookCarretel(inst: Instance)
	local prompt = inst:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(p: Player)
			DataService.collect(p)
		end)
	end
end

function DataService.start(): ()
	stateRemote = Remotes.get("State")
	toastRemote = Remotes.get("Toast")
	Remotes.get("Collect").OnServerEvent:Connect(function(p: Player)
		if collectLimiter:allow(p) then
			DataService.collect(p)
		end
	end)
	for _, inst in CollectionService:GetTagged("Carretel") do
		hookCarretel(inst)
	end
	CollectionService:GetInstanceAddedSignal("Carretel"):Connect(hookCarretel)

	task.spawn(decideStore)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	startTick()
end

return DataService
