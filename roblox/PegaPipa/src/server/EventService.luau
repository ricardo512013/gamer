--!strict
--[[
	EventService (STUB — área "core") — eventos de servidor (GDD §5.3): Rajada, Chuva de Pipas, Vento Dourado,
	Virou o Vento, Festival do Morro e boosts pagos (Rajada no Servidor / Vento Forte). Escreve os atributos
	EventName/EventPhase/EventEndsAt/Festival/BoostRajadaUntil/BoostVentoUntil/BoostBy em workspace.World.
	Requer: Config, Remotes, DataService, KiteService (setWind, spawnWild, drop, setWildBoost,
	playersAtFaixa4, makeGolden). NUNCA requer ShopService/MonetizationService.
	Registra DataService.hooks.ventoMultiplier no start().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local DataService = require(script.Parent.DataService)

export type EventPhase = "Warn" | "Active"
export type CurrentEvent = { name: string, phase: EventPhase, endsAt: number }
export type BoostKind = "Rajada" | "VentoForte"

local EventService = {}

function EventService.start(): ()
	DataService.hooks.ventoMultiplier = EventService.ventoMultiplier
	warn("[EventService] stub", Config.FIRST_EVENT_AT)
end

function EventService.current(): CurrentEvent?
	return nil
end

-- 1 normal, 2 Festival ou Vento Forte, 4 os dois.
function EventService.ventoMultiplier(): number
	return 1
end

function EventService.isFestival(): boolean
	return false
end

-- Força um evento agora (Rajada | Chuva | Dourado | Virou).
function EventService.force(name: string): ()
	warn("[EventService] stub force", name)
end

-- Boost pago por BOOST_SECONDS para todo o servidor; banner "Fulano pagou uma Rajada!".
function EventService.startServerBoost(kind: BoostKind, by: Player): ()
	warn("[EventService] stub startServerBoost", kind, by.Name)
end

return EventService
