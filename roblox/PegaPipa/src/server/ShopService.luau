--!strict
--[[
	ShopService (STUB — área "economia") — Bar do Vento (estoque rotativo §5.2), Linha, vagas, streak e dailies
	(§5.4), renascer (§3.6) e Kit Pipeiro. Conecta os remotes Buy, ClaimStreak, ClaimDaily, Rebirth e
	envia ShopStock. Escreve RestockAt em workspace.World.
	Requer: Config, Remotes, DataService, KiteService (recall/select ao renascer; onDuelEnd/onCatch para
	progressDaily). NUNCA requer EventService/MonetizationService (VIP via DataService.hooks.isVIP).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local DataService = require(script.Parent.DataService)

export type StockSlot = { model: string, rarity: number, price: number, special: boolean }
export type Stock = { seed: number, restockAt: number, slots: { StockSlot } }
export type BuyKind = "Kite" | "Linha" | "Vaga"
export type DailyKind = "Cortes" | "Pegas"

local ShopService = {}

function ShopService.start(): ()
	warn("[ShopService] stub", Config.RESTOCK_SECONDS)
end

-- Estoque atual (seed = os.time() // RESTOCK_SECONDS; igual em todos os servidores).
function ShopService.stock(): Stock
	return { seed = 0, restockAt = 0, slots = {} }
end

function ShopService.buy(p: Player, kind: BuyKind, slot: number?): boolean
	warn("[ShopService] stub buy", kind, slot)
	return false
end

function ShopService.claimStreak(p: Player): boolean
	warn("[ShopService] stub claimStreak")
	return false
end

function ShopService.claimDaily(p: Player, which: DailyKind): boolean
	warn("[ShopService] stub claimDaily", which)
	return false
end

-- Chamado via KiteService.onDuelEnd (Cortes em selvagens) e KiteService.onCatch (Pegas).
function ShopService.progressDaily(p: Player, which: DailyKind, n: number): ()
	warn("[ShopService] stub progressDaily", which, n)
end

function ShopService.rebirth(p: Player): boolean
	warn("[ShopService] stub rebirth")
	return false
end

-- Kit Pipeiro: Arraia Pipeiro + KIT.vento + Linha mínima; 1x (KitClaimed).
function ShopService.grantKit(p: Player): ()
	warn("[ShopService] stub grantKit")
end

-- Guardar Streak (1x/semana: Streak.SaverWeek).
function ShopService.useStreakSaver(p: Player): boolean
	warn("[ShopService] stub useStreakSaver")
	return false
end

return ShopService
