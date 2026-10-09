--!strict
--[[
	ShopService — a economia do jogador: Bar do Vento, Linha, vagas, streak, dailies, renascer e Kit.

	- Bar do Vento (GDD §5.2): estoque de SHOP_SLOTS_NORMAL slots normais (SHOP_TABLE) + SHOP_SLOTS_SPECIAL
	  especiais (SHOP_SPECIAL_TABLE). seed = os.time() // RESTOCK_SECONDS e Random.new(seed) → o mesmo
	  estoque em todo servidor; RestockAt = (seed + 1) × RESTOCK_SECONDS (epoch em segundos: o mesmo relógio
	  de os.time() e de workspace:GetServerTimeNow(), escrito em workspace.World.RestockAt). Cada slot é
	  comprado 1× por jogador por restock. ShopStock vai ao jogador no join e a todos no restock.
	- Linha de Vento (Config.linhaPrice, até LINHA_MAX) e vagas do varal (VAGA_PRICE, até VAGAS_MAX) a preço
	  fixo (§3.4). Toda compra exige HumanoidRootPart a ≤ SHOP_DIST do balcão (Config.BAR_POS) e Vento
	  (DataService.spendVento). Pipas compradas ganham cor cosmética 1..COSMETIC_COLORS.
	- Correio da Laje (§5.4): streak diário (dia = os.time() // DAY_SECONDS) D1-D7 = STREAK, D5/D7 também
	  STREAK_KITE, D8-D28 repetem o ciclo com Vento × STREAK_REPEAT_MULT, trava em STREAK_CAP_DAY;
	  2 dias sem resgatar → volta ao D1, salvo Guardar Streak usado na semana (Streak.SaverWeek).
	  Dailies "Corte 3 selvagens" / "Pegue 1 pipa" com reset diário (Dailies.Day); o progresso chega por
	  KiteService.onDuelEnd (vencedor humano contra selvagem) e KiteService.onCatch.
	- Renascer "Nova Temporada" (§3.6) e Kit Pipeiro (§5.7; grantKit, 1× por KitClaimed).

	Todo preço vem do Config; todo remote é hostil (tipo, faixa, distância e saldo validados aqui).
	Quem muda profile.Data chama DataService.pushState com os campos alterados; profile:Save() em compra,
	renascer e Kit. Toast("Erro", {msg, key, vars}): msg em pt-BR, key/vars para o HUD localizar.
	Requer: Config, Remotes, DataService, KiteService. NUNCA requer EventService/MonetizationService
	(VIP via DataService.hooks.isVIP).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local AnalyticsService = game:GetService("AnalyticsService")
local BadgeService = game:GetService("BadgeService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local DataService = require(script.Parent.DataService)
local KiteService = require(script.Parent.KiteService)

export type StockSlot = { model: string, rarity: number, price: number, special: boolean }
export type Stock = { seed: number, restockAt: number, slots: { StockSlot } }
export type BuyKind = "Kite" | "Linha" | "Vaga"
export type DailyKind = "Cortes" | "Pegas"

type ProfileData = Config.ProfileData
type KiteData = Config.KiteData
type Streak = { Day: number, LastClaimDay: number, SaverWeek: number }
type Dailies = { Day: number, Cortes: number, Pegas: number, ClaimedCortes: boolean, ClaimedPegas: boolean }
type BoughtSlots = { seed: number, slots: { [number]: boolean } }

local BUY_KINDS = { "Kite", "Linha", "Vaga" }
local DAILY_KINDS = { "Cortes", "Pegas" }
local SEASON_MODEL = "Temporada" -- modelo da Pipa de Temporada (§3.2)
local STATUS_FLYING = "Flying"
local RESTOCK_POLL = 1 -- s entre checagens do relógio do restock (não é regra de jogo)

local ShopService = {}

local rng = Random.new()
local stock: Stock = { seed = 0, restockAt = 0, slots = {} }
local bought: { [Player]: BoughtSlots } = {}
local stockRemote: RemoteEvent? = nil

local buyLimiter = Remotes.limiter(Config.RATE.Buy[1], Config.RATE.Buy[2])
local streakLimiter = Remotes.limiter(Config.RATE.ClaimStreak[1], Config.RATE.ClaimStreak[2])
local dailyLimiter = Remotes.limiter(Config.RATE.ClaimDaily[1], Config.RATE.ClaimDaily[2])
local rebirthLimiter = Remotes.limiter(Config.RATE.Rebirth[1], Config.RATE.Rebirth[2])
local petLimiter = Remotes.limiter(Config.RATE.SetPet[1], Config.RATE.SetPet[2])
local readyLimiter = Remotes.limiter(Config.RATE.Ready[1], Config.RATE.Ready[2])

-- Ajudantes ---------------------------------------------------------------------------------------

local function dataOf(p: Player): ProfileData?
	local profile = DataService.get(p)
	return if profile then profile.Data else nil
end

-- Dia UTC: os.time() // DAY_SECONDS.
local function today(): number
	return os.time() // Config.DAY_SECONDS
end

-- Semana desde segunda 00:00 UTC (mesma fórmula do Leaderboard, que não pode ser requerido daqui).
local function weekIndex(): number
	return (os.time() - Config.WEEK_EPOCH_OFFSET) // Config.WEEK_SECONDS
end

-- workspace/World (Configuration criada pelo MapGen; criada aqui se faltar).
local function world(): Configuration
	local found = Workspace:FindFirstChild("World")
	if found and found:IsA("Configuration") then
		return found
	end
	local conf = Instance.new("Configuration")
	conf.Name = "World"
	conf.Parent = Workspace
	return conf
end

-- HumanoidRootPart a ≤ SHOP_DIST do balcão do Bar (o cliente pode disparar Buy de qualquer lugar).
local function nearBar(p: Player): boolean
	local character = p.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - Config.BAR_POS).Magnitude <= Config.SHOP_DIST
end

-- Toast "Erro" (texto pt-BR + chave para o HUD localizar) e retorna false para encurtar os `return`.
local function fail(p: Player, key: string, vars: { [string]: any }?): boolean
	DataService.toast(p, "Erro", { msg = Config.str(key, "pt-BR", vars), key = key, vars = vars })
	return false
end

-- Passo do funil (§5.8): só avança; loga no AnalyticsService.
local function onboarding(p: Player, data: ProfileData, stepName: string)
	local step = table.find(Config.ONBOARDING_STEPS, stepName)
	if not step or data.Onboarding >= step then
		return
	end
	data.Onboarding = step
	DataService.pushState(p, { Onboarding = step })
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(p, step, stepName)
	end)
end

-- Badge (ids 0 = ainda não criada no Creator Hub → ignora).
local function awardBadge(p: Player, badgeId: number)
	if badgeId == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function(): boolean
			return BadgeService:AwardBadgeAsync(p.UserId, badgeId)
		end)
		if not ok then
			warn(`[ShopService] badge {badgeId} falhou para {p.Name}: {err}`)
		end
	end)
end

-- Bar do Vento: estoque ---------------------------------------------------------------------------------

-- Sorteia uma raridade pelos pesos (pesos 0 nunca saem).
local function rollRarity(r: Random, weights: { number }): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local x = r:NextNumber() * total
	local acc = 0
	local last = 1
	for rarity, w in weights do
		if w > 0 then
			acc += w
			last = rarity
			if x < acc then
				return rarity
			end
		end
	end
	return last
end

local function newSlot(r: Random, weights: { number }, special: boolean): StockSlot
	local rarity = rollRarity(r, weights)
	return { model = Config.MODEL_BY_RARITY[rarity], rarity = rarity, price = Config.SHOP_PRICE[rarity], special = special }
end

-- Estoque determinístico da janela `seed` (igual em todo servidor).
local function buildStock(seed: number): Stock
	local r = Random.new(seed)
	local slots: { StockSlot } = {}
	for _ = 1, Config.SHOP_SLOTS_NORMAL do
		table.insert(slots, newSlot(r, Config.SHOP_TABLE, false))
	end
	for _ = 1, Config.SHOP_SLOTS_SPECIAL do
		table.insert(slots, newSlot(r, Config.SHOP_SPECIAL_TABLE, true))
	end
	return { seed = seed, restockAt = (seed + 1) * Config.RESTOCK_SECONDS, slots = slots }
end

-- Slots já comprados por p neste restock (zera quando o seed muda).
local function boughtSlots(p: Player): { [number]: boolean }
	local mine = bought[p]
	if mine and mine.seed == stock.seed then
		return mine.slots
	end
	local fresh: BoughtSlots = { seed = stock.seed, slots = {} }
	bought[p] = fresh
	return fresh.slots
end

-- Payload de ShopStock (§7.3): os slots com o campo bought do próprio jogador.
local function stockFor(p: Player): { [string]: any }
	local mine = boughtSlots(p)
	local slots = {}
	for i, s in stock.slots do
		slots[i] = { model = s.model, rarity = s.rarity, price = s.price, special = s.special, bought = mine[i] == true }
	end
	return { seed = stock.seed, restockAt = stock.restockAt, slots = slots }
end

local function sendStock(p: Player)
	if stockRemote then
		stockRemote:FireClient(p, stockFor(p))
	end
end

-- Troca o estoque, zera as compras do restock anterior e avisa todo mundo.
local function restock(seed: number)
	stock = buildStock(seed)
	table.clear(bought)
	world():SetAttribute("RestockAt", stock.restockAt)
	for _, p in Players:GetPlayers() do
		sendStock(p)
	end
end

local function restockLoop()
	while true do
		task.wait(RESTOCK_POLL)
		local seed = os.time() // Config.RESTOCK_SECONDS
		if seed ~= stock.seed then
			restock(seed)
		end
	end
end

-- Bar do Vento: compras ---------------------------------------------------------------------------------

local function buyKite(p: Player, slot: number?): boolean
	local s = if slot then stock.slots[slot] else nil
	if not s or not slot then
		return false
	end
	local mine = boughtSlots(p)
	if mine[slot] then
		return fail(p, "errBought")
	end
	if s.price == math.huge then
		return false -- raridade sem preço (a Mítica não é vendida)
	end
	if not DataService.spendVento(p, s.price, "Pipa") then
		return fail(p, "errVento", { n = s.price })
	end
	mine[slot] = true
	DataService.addKite(p, s.model, s.rarity, rng:NextInteger(1, Config.COSMETIC_COLORS), false)
	sendStock(p)
	return true
end

local function buyLinha(p: Player, data: ProfileData): boolean
	local level = data.Linha + 1
	if level > Config.LINHA_MAX then
		return fail(p, "errMaxLinha")
	end
	local price = Config.linhaPrice(level)
	if not DataService.spendVento(p, price, "Linha") then
		return fail(p, "errVento", { n = price })
	end
	data.Linha = level
	DataService.pushState(p, { Linha = level })
	return true
end

local function buyVaga(p: Player, data: ProfileData): boolean
	local vagas = data.Vagas + 1
	local price = Config.VAGA_PRICE[vagas]
	if vagas > Config.VAGAS_MAX or not price then
		return fail(p, "errMaxVagas")
	end
	if not DataService.spendVento(p, price, "Vaga") then
		return fail(p, "errVento", { n = price })
	end
	data.Vagas = vagas
	DataService.pushState(p, { Vagas = vagas })
	return true
end

-- Compra no Bar: Kite (slot 1..5 do estoque), Linha (próximo nível) ou Vaga (próxima vaga).
function ShopService.buy(p: Player, kind: BuyKind, slot: number?): boolean
	local profile = DataService.get(p)
	if not profile then
		return false
	end
	if not nearBar(p) then
		return fail(p, "errFarBar")
	end
	local data = profile.Data
	local ok = false
	if kind == "Kite" then
		ok = buyKite(p, slot)
	elseif kind == "Linha" then
		ok = buyLinha(p, data)
	elseif kind == "Vaga" then
		ok = buyVaga(p, data)
	end
	if ok then
		onboarding(p, data, "PrimeiraCompra")
		profile:Save()
	end
	return ok
end

-- Estoque atual (seed = os.time() // RESTOCK_SECONDS; igual em todos os servidores).
function ShopService.stock(): Stock
	return stock
end

-- Correio da Laje: streak (§5.4) --------------------------------------------------------------------------

-- Dia do streak a pagar hoje: D1 na 1ª vez ou depois de 2+ dias sem resgatar (salvo Guardar Streak usado
-- nesta semana); senão o dia seguinte, travado em STREAK_CAP_DAY.
local function nextStreakDay(s: Streak): number
	if s.LastClaimDay == 0 then
		return 1
	end
	local gap = today() - s.LastClaimDay
	if gap >= 2 and s.SaverWeek ~= weekIndex() then
		return 1
	end
	return math.min(s.Day + 1, Config.STREAK_CAP_DAY)
end

-- Resgata o dia de hoje: Vento (D8+ × STREAK_REPEAT_MULT) e, nos dias de STREAK_KITE, uma pipa.
function ShopService.claimStreak(p: Player): boolean
	local data = dataOf(p)
	if not data then
		return false
	end
	local s = data.Streak
	local day = today()
	if day <= s.LastClaimDay then
		return fail(p, "errStreak")
	end
	local d = nextStreakDay(s)
	local cycle = (d - 1) % #Config.STREAK + 1 -- posição D1..D7 dentro do ciclo
	local mult = if d > #Config.STREAK then Config.STREAK_REPEAT_MULT else 1
	local vento = Config.STREAK[cycle] * mult
	s.Day = d
	s.LastClaimDay = day
	DataService.addVento(p, vento, "Streak")
	local args: { [string]: any } = { day = d, n = vento }
	local kite = Config.STREAK_KITE[cycle]
	if kite then
		local color = kite.color or rng:NextInteger(1, Config.COSMETIC_COLORS)
		DataService.addKite(p, kite.model, kite.rarity, color, false)
		args.kite = kite.model
	end
	DataService.pushState(p, { Streak = s })
	DataService.toast(p, "Streak", args)
	return true
end

-- Guardar Streak (produto, 1×/semana): protege o streak contra uma falta nesta semana.
function ShopService.useStreakSaver(p: Player): boolean
	local data = dataOf(p)
	if not data then
		return false
	end
	local week = weekIndex()
	if data.Streak.SaverWeek == week then
		return false
	end
	data.Streak.SaverWeek = week
	DataService.pushState(p, { Streak = data.Streak })
	return true
end

-- Correio da Laje: dailies ---------------------------------------------------------------------------------

-- Zera as dailies quando o dia mudou. Retorna true se zerou.
local function ensureDailies(data: ProfileData): boolean
	local d = data.Dailies
	local day = today()
	if d.Day == day then
		return false
	end
	d.Day = day
	d.Cortes = 0
	d.Pegas = 0
	d.ClaimedCortes = false
	d.ClaimedPegas = false
	return true
end

local function dailyDef(which: DailyKind): { goal: number, reward: number }
	return if which == "Cortes" then Config.DAILY.Cortes else Config.DAILY.Pegas
end

local function dailyProgress(d: Dailies, which: DailyKind): number
	return if which == "Cortes" then d.Cortes else d.Pegas
end

local function dailyClaimed(d: Dailies, which: DailyKind): boolean
	return if which == "Cortes" then d.ClaimedCortes else d.ClaimedPegas
end

-- Chamado via KiteService.onDuelEnd (Cortes em selvagens) e KiteService.onCatch (Pegas).
function ShopService.progressDaily(p: Player, which: DailyKind, n: number): ()
	local data = dataOf(p)
	if not data or n <= 0 then
		return
	end
	ensureDailies(data)
	local d = data.Dailies
	if which == "Cortes" then
		d.Cortes += n
	else
		d.Pegas += n
	end
	DataService.pushState(p, { Dailies = d })
end

-- Paga Config.DAILY[which].reward se a meta foi batida e ainda não foi resgatada hoje.
function ShopService.claimDaily(p: Player, which: DailyKind): boolean
	local data = dataOf(p)
	if not data then
		return false
	end
	ensureDailies(data)
	local d = data.Dailies
	local def = dailyDef(which)
	if dailyClaimed(d, which) or dailyProgress(d, which) < def.goal then
		return fail(p, "errDaily")
	end
	if which == "Cortes" then
		d.ClaimedCortes = true
	else
		d.ClaimedPegas = true
	end
	DataService.addVento(p, def.reward, "Daily")
	DataService.pushState(p, { Dailies = d })
	return true
end

-- Renascer "Nova Temporada" (§3.6) --------------------------------------------------------------------------

-- Custo da temporada seguinte: REBIRTH_BASE × REBIRTH_GROWTH^(n-1), com n = Temporadas + 1.
local function rebirthCost(temporadas: number): number
	return Config.REBIRTH_BASE * Config.REBIRTH_GROWTH ^ temporadas
end

-- A pipa consumida: a de menor valor com raridade ≥ REBIRTH_NEED_RARITY (Jornal e Pipas de Temporada ficam de fora).
local function findEpic(data: ProfileData): KiteData?
	local best: KiteData? = nil
	for _, k in data.Kites do
		if k.rarity >= Config.REBIRTH_NEED_RARITY and not k.starter and k.season == 0 then
			if not best or Config.baseRate(k) < Config.baseRate(best) then
				best = k
			end
		end
	end
	return best
end

-- Pipa de maior base × (dourada ? GOLDEN_MULT : 1): a mesma regra da seleção padrão (§2.1).
local function bestKite(kites: { KiteData }): KiteData?
	local best: KiteData? = nil
	for _, k in kites do
		if not best or Config.baseRate(k) > Config.baseRate(best) then
			best = k
		end
	end
	return best
end

-- Estimações mantidas no renascer: PETS_KEPT (PETS_KEPT_VIP com VIP).
local function petLimit(p: Player): number
	return if DataService.hooks.isVIP(p) then Config.PETS_KEPT_VIP else Config.PETS_KEPT
end

-- O que fica no varal (§3.6): Jornal, Pipas de Temporada, Arraia Pipeiro e as petLimit(p) estimações de maior
-- valor. A Épica consumida não entra aqui (vira a Pipa de Temporada nova).
local function keptKites(p: Player, data: ProfileData, consumed: KiteData): { KiteData }
	local maxPets = petLimit(p)
	local kept: { KiteData } = {}
	local pets: { KiteData } = {}
	for _, k in data.Kites do
		if k == consumed then
			continue
		end
		if k.starter or k.season > 0 or k.model == Config.KIT.model then
			table.insert(kept, k)
		elseif k.pet then
			table.insert(pets, k)
		end
	end
	table.sort(pets, function(a: KiteData, b: KiteData): boolean
		return Config.baseRate(a) > Config.baseRate(b)
	end)
	for i = 1, math.min(maxPets, #pets) do
		table.insert(kept, pets[i])
	end
	return kept
end

-- Renascer: exige Vento ≥ custo e uma Épica no varal; consome TODO o Vento e o Carretel, reduz o varal ao
-- que fica (§3.6), cria a Pipa de Temporada n (cor SEASON_COLOR_BASE + n) e soma 1 em Temporadas.
function ShopService.rebirth(p: Player): boolean
	local profile = DataService.get(p)
	if not profile then
		return false
	end
	local data = profile.Data
	if data.Temporadas >= Config.REBIRTH_MAX then
		return fail(p, "errRebirthMax")
	end
	local cost = rebirthCost(data.Temporadas)
	local epic = findEpic(data)
	if data.Vento < cost or not epic then
		return fail(p, "errRebirth", { vento = cost })
	end
	local flying = KiteService.flyingOf(p)
	if flying and flying.status ~= STATUS_FLYING then
		return fail(p, "errDuel") -- em duelo a pipa no ar ainda pode mudar de dono
	end
	local n = data.Temporadas + 1
	KiteService.recall(p)
	DataService.spendVento(p, data.Vento, "Renascer") -- todo o Vento vai embora, não só o custo
	local kites = keptKites(p, data, epic)
	local season: KiteData = {
		id = data.NextKiteId,
		model = SEASON_MODEL,
		rarity = Config.rarityOf(SEASON_MODEL),
		color = Config.SEASON_COLOR_BASE + n,
		golden = epic.golden,
		pet = epic.pet,
		season = n,
		starter = false,
	}
	data.NextKiteId += 1
	table.insert(kites, season)
	data.Kites = kites
	data.Carretel = 0
	data.Temporadas = n
	local best = bestKite(kites)
	data.Selected = if best then best.id else 0
	DataService.pushState(p, { Vento = data.Vento, Carretel = 0, Temporadas = n, Kites = kites, Selected = data.Selected })
	if best then
		KiteService.select(p, best.id) -- sobe a nova selecionada na faixa 0
	end
	DataService.toast(p, "Renasceu", { n = n })
	if n == 1 then
		awardBadge(p, Config.BADGES.Temporada1)
	end
	profile:Save()
	return true
end

-- Kit Pipeiro (§5.7) ---------------------------------------------------------------------------------------------

-- Arraia Pipeiro + KIT.vento + Linha mínima KIT.linhaMin; 1× por conta (KitClaimed).
function ShopService.grantKit(p: Player): ()
	local profile = DataService.get(p)
	if not profile or profile.Data.KitClaimed then
		return
	end
	local data = profile.Data
	data.KitClaimed = true
	DataService.addKite(p, Config.KIT.model, Config.KIT.rarity, Config.KIT.color, false)
	DataService.addVento(p, Config.KIT.vento, "Kit")
	if data.Linha < Config.KIT.linhaMin then
		data.Linha = Config.KIT.linhaMin
		DataService.pushState(p, { Linha = data.Linha })
	end
	profile:Save()
end

-- Estimação (remote SetPet) ----------------------------------------------------------------------------------------

-- Marca/desmarca a pipa como estimação (toque longo na carta, §3.6/§6). Jornal e Pipas de Temporada já ficam no
-- renascer, então não podem ser marcadas; no máximo petLimit(p) marcadas ao mesmo tempo.
function ShopService.setPet(p: Player, kiteId: number): boolean
	local data = dataOf(p)
	local k = DataService.findKite(p, kiteId)
	if not data or not k or k.starter or k.season > 0 then
		return false
	end
	if not k.pet then
		local limit = petLimit(p)
		local marked = 0
		for _, other in data.Kites do
			if other.pet then
				marked += 1
			end
		end
		if marked >= limit then
			return fail(p, "errPetMax", { n = limit })
		end
	end
	k.pet = not k.pet
	DataService.pushState(p, { Kites = data.Kites })
	return true
end

-- Remotes e início ---------------------------------------------------------------------------------------------

local function onSetPet(p: Player, kiteId: unknown)
	if not petLimiter:allow(p) then
		return
	end
	local data = dataOf(p)
	if not data or not Remotes.isInt(kiteId, 1, data.NextKiteId) then
		return
	end
	ShopService.setPet(p, (kiteId :: any) :: number)
end

local function onBuy(p: Player, kind: unknown, slot: unknown)
	if not buyLimiter:allow(p) then
		return
	end
	if typeof(kind) ~= "string" or not table.find(BUY_KINDS, kind) then
		return
	end
	if kind == "Kite" and not Remotes.isInt(slot, 1, #stock.slots) then
		return
	end
	local buyKind: BuyKind = (kind :: any) :: BuyKind -- anotação explícita: sem ela o analisador alarga para string
	ShopService.buy(p, buyKind, if buyKind == "Kite" then (slot :: any) :: number else nil)
end

local function onClaimDaily(p: Player, which: unknown)
	if not dailyLimiter:allow(p) then
		return
	end
	if typeof(which) ~= "string" or not table.find(DAILY_KINDS, which) then
		return
	end
	ShopService.claimDaily(p, (which :: any) :: DailyKind)
end

local function onLoaded(p: Player, data: ProfileData)
	if ensureDailies(data) then
		DataService.pushState(p, { Dailies = data.Dailies })
	end
	sendStock(p)
end

local function onPlayerRemoving(p: Player)
	bought[p] = nil
	buyLimiter:forget(p)
	streakLimiter:forget(p)
	dailyLimiter:forget(p)
	rebirthLimiter:forget(p)
	petLimiter:forget(p)
	readyLimiter:forget(p)
end

function ShopService.start(): ()
	stockRemote = Remotes.get("ShopStock")
	restock(os.time() // Config.RESTOCK_SECONDS)
	Remotes.get("Buy").OnServerEvent:Connect(onBuy)
	Remotes.get("ClaimStreak").OnServerEvent:Connect(function(p: Player)
		if streakLimiter:allow(p) then
			ShopService.claimStreak(p)
		end
	end)
	Remotes.get("ClaimDaily").OnServerEvent:Connect(onClaimDaily)
	Remotes.get("Rebirth").OnServerEvent:Connect(function(p: Player)
		if rebirthLimiter:allow(p) then
			ShopService.rebirth(p)
		end
	end)
	KiteService.onDuelEnd(function(winner: Player?, _loser: Player?, wild: boolean)
		if winner and wild then
			ShopService.progressDaily(winner, "Cortes", 1) -- "Corte 3 selvagens"
		end
	end)
	KiteService.onCatch(function(p: Player, _k: KiteService.KiteState)
		ShopService.progressDaily(p, "Pegas", 1) -- "Pegue 1 pipa no campinho"
	end)
	Remotes.get("SetPet").OnServerEvent:Connect(onSetPet)
	Remotes.get("Ready").OnServerEvent:Connect(function(p: Player) -- o cliente acabou de conectar ShopStock
		if readyLimiter:allow(p) then
			sendStock(p)
		end
	end)
	DataService.onLoaded(onLoaded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	task.spawn(restockLoop)
end

return ShopService
