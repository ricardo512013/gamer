--!strict
--[[
	KiteService (STUB — área "core") — pipa no ar, faixas, deriva, selvagens, rabeio/duelo, queda, pega,
	árvore, anti-AFK, tutorial (GDD §2). Cria workspace/KiteStates/<id> (Configuration, tag Kite, Attributes §7.4).
	Requer: Config, Remotes, DataService, MapGen, Leaderboard (addWeekly "CortesPvP"). NUNCA requer
	ShopService/EventService/MonetizationService (ciclo): eles assinam onDuelEnd/onCatch; o Festival é lido
	de workspace.World (atributo Festival); Carretel Automático vem de DataService.hooks.hasAutoReel(p).
	Dono de Selected: escolhe a melhor pipa no load (DataService.onLoaded) e quando Selected == 0.
	Registra DataService.hooks.faixaOf no start().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local DataService = require(script.Parent.DataService)

export type KiteState = {
	id: number,
	owner: number, -- userId; 0 = selvagem
	model: string,
	rarity: number,
	color: number,
	golden: boolean,
	faixa: number,
	theta: number,
	pos: Vector3,
	status: string, -- Flying | Dueling | Falling | Ground | Tree
	statusUntil: number,
	duelWith: number?,
	immuneUntil: number,
	wild: boolean,
	tutorialFor: Player?,
	landPos: Vector3?,
	conf: Configuration,
}

export type WildOpts = { tutorialFor: Player?, points: number? }
export type DuelEndCallback = (winner: Player?, loser: Player?, wild: boolean) -> ()
export type CatchCallback = (p: Player, k: KiteState) -> ()

local KiteService = {}

local duelEndCallbacks: { DuelEndCallback } = {}
local catchCallbacks: { CatchCallback } = {}

local function stubState(model: string, rarity: number, color: number, wild: boolean): KiteState
	return {
		id = 0, owner = 0, model = model, rarity = rarity, color = color, golden = false,
		faixa = 0, theta = 0, pos = Vector3.zero, status = "Flying", statusUntil = 0,
		immuneUntil = 0, wild = wild, conf = Instance.new("Configuration"),
	}
end

function KiteService.start(): ()
	DataService.hooks.faixaOf = KiteService.faixaOf
	warn("[KiteService] stub", Config.SEED, #Remotes.NAMES)
end

function KiteService.flyingOf(p: Player): KiteState?
	return nil
end

-- 0 se nada no ar.
function KiteService.faixaOf(p: Player): number
	return 0
end

-- Só aceito com a pipa atual na faixa 0 e Flying.
function KiteService.select(p: Player, kiteId: number): boolean
	warn("[KiteService] stub select")
	return false
end

-- Faixa 0 imediato.
function KiteService.recall(p: Player): ()
	warn("[KiteService] stub recall")
end

function KiteService.spawnWild(rarity: number?, color: number?, opts: WildOpts?): KiteState
	warn("[KiteService] stub spawnWild")
	return stubState(Config.MODEL_BY_RARITY[rarity or 1], rarity or 1, color or 1, true)
end

-- Pipa caindo (Chuva de Pipas e corte).
function KiteService.drop(model: string, rarity: number, color: number, landPos: Vector3, ownerId: number?): KiteState
	warn("[KiteService] stub drop")
	local state = stubState(model, rarity, color, false)
	state.status = "Falling"
	state.landPos = landPos
	state.owner = ownerId or 0
	return state
end

function KiteService.rescueFromTree(p: Player): boolean
	warn("[KiteService] stub rescueFromTree")
	return false
end

-- +1 ou -1 (atributo WindSign de workspace.World).
function KiteService.setWind(sign: number): ()
	warn("[KiteService] stub setWind")
end

function KiteService.setWildBoost(intervalMin: number, intervalMax: number, maxInAir: number, table: { number }, untilTime: number): ()
	warn("[KiteService] stub setWildBoost")
end

function KiteService.playersAtFaixa4(): { Player }
	return {}
end

function KiteService.makeGolden(p: Player, kiteId: number): ()
	warn("[KiteService] stub makeGolden")
end

function KiteService.onDuelEnd(cb: DuelEndCallback): ()
	table.insert(duelEndCallbacks, cb)
end

function KiteService.onCatch(cb: CatchCallback): ()
	table.insert(catchCallbacks, cb)
end

return KiteService
