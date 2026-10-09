--!strict
--[[
	EventService — eventos de servidor (GDD §5.3): a cada EVENT_INTERVAL s após o fim do anterior (o 1º
	forçado aos FIRST_EVENT_AT s de vida do servidor) sorteia pela tabela Config.EVENTS:
	  Rajada  → KiteService.setWildBoost (selvagens mais frequentes, tabela Rajada) por `duration`;
	  Chuva   → RAIN_COUNT KiteService.drop de RAIN_FROM_Y em pontos aleatórios do campinho;
	  Dourado → ao fim, 1 jogador aleatório na faixa 4 ganha uma pipa Dourada (ou "passou em branco");
	  Virou   → aviso de `duration` s e depois KiteService.setWind(-WindSign).
	Todo evento tem fase Warn (EVENT_WARN s; o Virou usa a própria duração) e Active.
	Festival do Morro (sábado FESTIVAL.hourUTC UTC, FESTIVAL.minutes min): Chuva a cada rainEvery s,
	ventoMultiplier × FESTIVAL.ventoMult e atributo Festival = true (KiteService pinta pegas de cor 9).
	Boosts pagos (startServerBoost): Rajada no Servidor e Vento Forte por BOOST_SECONDS.

	Escreve em workspace.World: EventName, EventPhase, EventEndsAt, Festival, BoostRajadaUntil,
	BoostVentoUntil, BoostBy. Toasts (broadcast): Evento {event, phase, endsAt}, Boost {kind, name},
	Dourada {name = "", kite = "", blank = true} quando o Vento Dourado passa em branco.
	Requer: Config, Remotes (nada direto), DataService, KiteService. NUNCA requer ShopService/
	MonetizationService. Registra DataService.hooks.ventoMultiplier no start().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DataService = require(script.Parent.DataService)
local KiteService = require(script.Parent.KiteService)

export type EventPhase = "Warn" | "Active"
export type CurrentEvent = { name: string, phase: EventPhase, endsAt: number }
export type BoostKind = "Rajada" | "VentoForte"

type EventDef = { name: string, chance: number, duration: number }

local EVENT_RAJADA = "Rajada"
local EVENT_CHUVA = "Chuva"
local EVENT_DOURADO = "Dourado"
local EVENT_VIROU = "Virou"
local EVENT_FESTIVAL = "Festival"
local LOOP_STEP = 1 -- s entre checagens do relógio (não é regra de jogo)

local EventService = {}

local rng = Random.new()
local current: CurrentEvent? = nil
local nextEventAt = 0
local festival = false
local boostVentoUntil = 0
local boostRajadaUntil = 0

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

local function findDef(name: string): EventDef?
	for _, def in Config.EVENTS do
		if def.name == name then
			return def
		end
	end
	return nil
end

-- Sorteio pela coluna `chance` (35/25/20/20).
local function pickEvent(): EventDef
	local total = 0
	for _, def in Config.EVENTS do
		total += def.chance
	end
	local roll = rng:NextNumber() * total
	for _, def in Config.EVENTS do
		if def.chance > 0 and roll < def.chance then
			return def
		end
		roll -= def.chance
	end
	return Config.EVENTS[1]
end

-- Atualiza `current`, os atributos de workspace.World e manda o banner para todos.
local function setPhase(name: string, phase: EventPhase, endsAt: number)
	current = { name = name, phase = phase, endsAt = endsAt }
	local w = world()
	w:SetAttribute("EventName", name)
	w:SetAttribute("EventPhase", phase)
	w:SetAttribute("EventEndsAt", endsAt)
	DataService.toast(nil, "Evento", { event = name, phase = phase, endsAt = endsAt })
end

local function clearEvent()
	current = nil
	local w = world()
	w:SetAttribute("EventName", "")
	w:SetAttribute("EventPhase", "")
	w:SetAttribute("EventEndsAt", 0)
end

local function randomColor(): number
	return rng:NextInteger(1, Config.COSMETIC_COLORS)
end

-- Efeitos ------------------------------------------------------------------------------------------

-- Chuva de Pipas: RAIN_COUNT pipas (tabela Rajada) caem de RAIN_FROM_Y em pontos aleatórios do campinho.
local function rain()
	for _ = 1, Config.RAIN_COUNT do
		local rarity = KiteService.rollRarity(Config.WILD_TABLE_RAJADA)
		local model = Config.MODEL_BY_RARITY[rarity] or Config.MODEL_BY_RARITY[1]
		KiteService.drop(model, rarity, randomColor(), KiteService.randomLandPos(), nil)
	end
end

-- Vento Dourado: 1 jogador aleatório na faixa 4 ganha a pipa Dourada; ninguém → "passou em branco".
local function goldenFinish()
	local candidates = KiteService.playersAtFaixa4()
	if #candidates == 0 then
		DataService.toast(nil, "Dourada", { name = "", kite = "", blank = true })
		return
	end
	local p = candidates[rng:NextInteger(1, #candidates)]
	local profile = DataService.get(p)
	if profile and profile.Data.Selected ~= 0 then
		KiteService.makeGolden(p, profile.Data.Selected)
	end
end

local function currentWindSign(): number
	local sign = world():GetAttribute("WindSign")
	return if sign == -1 then -1 else 1
end

-- Roda um evento completo (Warn → Active → fim) e agenda o próximo. Deve rodar em task.spawn.
local function runEvent(def: EventDef)
	local name = def.name
	local warnTime = if name == EVENT_VIROU then def.duration else Config.EVENT_WARN
	setPhase(name, "Warn", now() + warnTime)
	task.wait(warnTime)

	local t = now()
	if name == EVENT_RAJADA then
		local endsAt = t + def.duration
		setPhase(name, "Active", endsAt)
		KiteService.setWildBoost(Config.RAJADA.interval[1], Config.RAJADA.interval[2], Config.RAJADA.maxInAir, Config.WILD_TABLE_RAJADA, endsAt)
		task.wait(def.duration)
	elseif name == EVENT_CHUVA then
		setPhase(name, "Active", t + def.duration)
		rain()
		task.wait(def.duration)
	elseif name == EVENT_DOURADO then
		setPhase(name, "Active", t + def.duration)
		task.wait(def.duration)
		goldenFinish()
	elseif name == EVENT_VIROU then
		KiteService.setWind(-currentWindSign())
		setPhase(name, "Active", t + Config.EVENT_WARN) -- banner "Virou o Vento" por EVENT_WARN s
		task.wait(Config.EVENT_WARN)
	end

	clearEvent()
	nextEventAt = now() + rng:NextNumber(Config.EVENT_INTERVAL[1], Config.EVENT_INTERVAL[2])
end

-- Festival do Morro ----------------------------------------------------------------------------------

local function inFestivalWindow(): boolean
	local date = os.date("!*t")
	local f = Config.FESTIVAL
	return date.wday == f.wday and date.hour == f.hourUTC and date.min < f.minutes
end

-- Chuva a cada rainEvery s enquanto o Festival durar (como evento quando o céu está livre).
local function festivalRains()
	task.spawn(function()
		while festival do
			if current == nil then
				local def = findDef(EVENT_CHUVA)
				if def then
					task.spawn(runEvent, def)
				end
			else
				rain()
			end
			task.wait(Config.FESTIVAL.rainEvery)
		end
	end)
end

local function setFestival(on: boolean)
	if festival == on then
		return
	end
	festival = on
	world():SetAttribute("Festival", on)
	if on then
		local endsAt = now() + Config.FESTIVAL.minutes * 60
		DataService.toast(nil, "Evento", { event = EVENT_FESTIVAL, phase = "Active", endsAt = endsAt })
		festivalRains()
	end
end

-- Laço ---------------------------------------------------------------------------------------------

local function loop()
	while true do
		task.wait(LOOP_STEP)
		local ok, err = pcall(function(): string?
			setFestival(inFestivalWindow())
			if current == nil and now() >= nextEventAt then
				nextEventAt = math.huge -- runEvent reagenda ao terminar
				task.spawn(runEvent, pickEvent())
			end
			return nil
		end)
		if not ok then
			warn(`[EventService] laço falhou: {err}`)
		end
	end
end

-- API pública -----------------------------------------------------------------------------------------

function EventService.start(): ()
	DataService.hooks.ventoMultiplier = EventService.ventoMultiplier
	local w = world()
	w:SetAttribute("Festival", false)
	w:SetAttribute("BoostRajadaUntil", 0)
	w:SetAttribute("BoostVentoUntil", 0)
	w:SetAttribute("BoostBy", "")
	clearEvent()
	nextEventAt = now() + Config.FIRST_EVENT_AT
	task.spawn(loop)
end

function EventService.current(): CurrentEvent?
	return current
end

-- 1 normal; ×FESTIVAL.ventoMult no Festival; ×BOOST_VENTO_MULT com Vento Forte (acumulam → 4).
function EventService.ventoMultiplier(): number
	local mult = 1
	if festival then
		mult *= Config.FESTIVAL.ventoMult
	end
	if boostVentoUntil > now() then
		mult *= Config.BOOST_VENTO_MULT
	end
	return mult
end

function EventService.isFestival(): boolean
	return festival
end

-- Força um evento agora (Rajada | Chuva | Dourado | Virou); ignorado se já há um em andamento.
function EventService.force(name: string): ()
	local def = findDef(name)
	if not def then
		warn(`[EventService] evento desconhecido: {name}`)
		return
	end
	if current ~= nil then
		warn(`[EventService] já há um evento em andamento ({current.name}); force({name}) ignorado`)
		return
	end
	nextEventAt = math.huge
	task.spawn(runEvent, def)
end

-- Boost pago por BOOST_SECONDS para todo o servidor (prolonga se já ativo); banner "Fulano pagou…".
function EventService.startServerBoost(kind: BoostKind, by: Player): ()
	local t = now()
	local w = world()
	if kind == "Rajada" then
		boostRajadaUntil = math.max(t, boostRajadaUntil) + Config.BOOST_SECONDS
		KiteService.setWildBoost(Config.BOOST_RAJADA.interval[1], Config.BOOST_RAJADA.interval[2], Config.BOOST_RAJADA.maxInAir, Config.WILD_TABLE_RAJADA, boostRajadaUntil)
		w:SetAttribute("BoostRajadaUntil", boostRajadaUntil)
	else
		boostVentoUntil = math.max(t, boostVentoUntil) + Config.BOOST_SECONDS
		w:SetAttribute("BoostVentoUntil", boostVentoUntil)
	end
	w:SetAttribute("BoostBy", by.DisplayName)
	DataService.toast(nil, "Boost", { kind = kind, name = by.DisplayName })
end

return EventService
