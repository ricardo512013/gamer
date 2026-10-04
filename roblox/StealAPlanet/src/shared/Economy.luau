--!strict
-- Pure economy formulas shared by the server and the client UI.

local Config = require(script.Parent.Config)
local Planets = require(script.Parent.Planets)
local Mutations = require(script.Parent.Mutations)

local Economy = {}

export type MultiplierParams = {
	Rebirths: number,
	VIP: boolean,
	DoubleCash: boolean,
	IndexBonus: number,
	FriendBonus: number,
	GroupBonus: number,
	EventMult: number,
}

function Economy.PlanetIncome(def: Planets.PlanetDef, mutation: string): number
	return def.Income * Mutations.Mult(mutation)
end

function Economy.PlanetPrice(def: Planets.PlanetDef, mutation: string): number
	return def.Price * Mutations.Mult(mutation)
end

function Economy.SellValue(def: Planets.PlanetDef, mutation: string): number
	return math.floor(Economy.PlanetPrice(def, mutation) * Config.SellRatio)
end

-- Cost of rebirth number n (n = 1 for the first rebirth).
function Economy.RebirthCost(n: number): number
	return Config.RebirthBaseCost * Config.RebirthCostGrowth ^ (math.max(n, 1) - 1)
end

function Economy.RebirthMultiplier(rebirths: number): number
	return 1 + Config.RebirthMultiplierStep * rebirths
end

function Economy.UnlockedSlots(rebirths: number): number
	return math.min(Config.MaxSlots, Config.BaseSlots + Config.SlotsPerRebirth * rebirths)
end

-- Rebirths needed to unlock a slot index (0 if it is unlocked from the start).
function Economy.SlotRebirthRequirement(slotIndex: number): number
	if slotIndex <= Config.BaseSlots then
		return 0
	end
	return math.ceil((slotIndex - Config.BaseSlots) / Config.SlotsPerRebirth)
end

function Economy.LockDuration(rebirths: number, doubleLock: boolean): number
	local seconds = Config.LockDuration + Config.LockPerRebirth * rebirths
	return if doubleLock then seconds * 2 else seconds
end

-- Each discovered planet gives +1% income, each discovered mutation variant +0.5%.
function Economy.IndexBonus(index: { [string]: boolean }): number
	local bonus = 0
	for key, found in index do
		if found then
			if string.find(key, ":", 1, true) then
				bonus += 0.005
			else
				bonus += 0.01
			end
		end
	end
	return bonus
end

function Economy.IndexCounts(index: { [string]: boolean }): (number, number)
	local planets, variants = 0, 0
	for key, found in index do
		if found then
			if string.find(key, ":", 1, true) then
				variants += 1
			else
				planets += 1
			end
		end
	end
	return planets, variants
end

function Economy.Multiplier(p: MultiplierParams): number
	local mult = Economy.RebirthMultiplier(p.Rebirths)
	if p.VIP then
		mult *= 1.5
	end
	if p.DoubleCash then
		mult *= 2
	end
	mult *= 1 + p.IndexBonus + p.FriendBonus + p.GroupBonus
	mult *= p.EventMult
	return mult
end

-- Cash rewards scale with the player's income so they stay meaningful.
function Economy.ScaledReward(incomePerSecond: number, seconds: number, minimum: number): number
	return math.max(minimum, math.floor(incomePerSecond * seconds))
end

function Economy.OfflineSeconds(lastOnline: number, now: number, capHours: number): number
	if lastOnline <= 0 or now <= lastOnline then
		return 0
	end
	return math.min(now - lastOnline, capHours * 3600)
end

return Economy
