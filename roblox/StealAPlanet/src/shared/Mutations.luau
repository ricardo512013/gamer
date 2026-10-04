--!strict
-- Mutations multiply a planet's price and income and change its look.

export type MutationDef = {
	Id: string,
	Name: string,
	Mult: number,
	Chance: number,
	Color: Color3,
	Order: number,
}

local Mutations = {}

Mutations.List = {
	{ Id = "None", Name = "Normal", Mult = 1, Chance = 0, Color = Color3.fromRGB(255, 255, 255), Order = 0 },
	{ Id = "Gold", Name = "Gold", Mult = 1.5, Chance = 0.04, Color = Color3.fromRGB(255, 200, 50), Order = 1 },
	{ Id = "Diamond", Name = "Diamond", Mult = 2, Chance = 0.015, Color = Color3.fromRGB(140, 230, 255), Order = 2 },
	{ Id = "Rainbow", Name = "Rainbow", Mult = 3, Chance = 0.005, Color = Color3.fromRGB(255, 120, 200), Order = 3 },
	{ Id = "Galaxy", Name = "Galaxy", Mult = 5, Chance = 0.0015, Color = Color3.fromRGB(160, 90, 255), Order = 4 },
} :: { MutationDef }

local byId: { [string]: MutationDef } = {}
for _, def in Mutations.List do
	byId[def.Id] = def
end

function Mutations.Get(id: string): MutationDef
	return byId[id] or Mutations.List[1]
end

function Mutations.IsValid(id: string): boolean
	return byId[id] ~= nil
end

function Mutations.Mult(id: string): number
	local def = byId[id]
	return if def then def.Mult else 1
end

-- Rolls from the rarest mutation to the most common one.
-- multipliers: optional chance multiplier per mutation id (cosmic events).
function Mutations.Roll(rand: () -> number, multipliers: { [string]: number }?): string
	for i = #Mutations.List, 2, -1 do
		local def = Mutations.List[i]
		local mult = if multipliers then (multipliers[def.Id] or 1) else 1
		if rand() < def.Chance * mult then
			return def.Id
		end
	end
	return "None"
end

return Mutations
