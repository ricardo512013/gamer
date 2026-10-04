--!strict
-- Every planet in the game. Price = cost on the Cosmic Belt, Income = cash per second.
-- Visual describes how PlanetModel builds it out of plain parts (no uploads needed).

export type Visual = {
	Kind: string, -- Asteroid | Moon | Planet | Earth | Comet | Star | BlackHole | Quasar | Pulsar | Galaxy | Nebula | Wormhole | Multiverse
	Color: Color3,
	Secondary: Color3?,
	Material: Enum.Material?,
	Size: number,
	Ring: boolean?,
	RingTilt: number?,
	Bands: number?,
	Particles: boolean?,
	Rainbow: boolean?,
}

export type PlanetDef = {
	Id: string,
	Name: string,
	Rarity: string,
	Price: number,
	Income: number,
	Order: number,
	Weight: number,
	Visual: Visual,
}

export type RarityInfo = {
	Id: string,
	Order: number,
	Color: Color3,
	Weight: number,
	Gradient: boolean?,
}

local Planets = {}

Planets.Rarities = {
	{ Id = "Common", Order = 1, Color = Color3.fromRGB(205, 205, 215), Weight = 55 },
	{ Id = "Uncommon", Order = 2, Color = Color3.fromRGB(90, 225, 100), Weight = 26 },
	{ Id = "Rare", Order = 3, Color = Color3.fromRGB(70, 155, 255), Weight = 12 },
	{ Id = "Epic", Order = 4, Color = Color3.fromRGB(175, 85, 255), Weight = 5 },
	{ Id = "Legendary", Order = 5, Color = Color3.fromRGB(255, 195, 45), Weight = 1.6 },
	{ Id = "Mythic", Order = 6, Color = Color3.fromRGB(255, 70, 95), Weight = 0.33 },
	{ Id = "Cosmic", Order = 7, Color = Color3.fromRGB(0, 255, 225), Weight = 0.06, Gradient = true },
	{ Id = "Secret", Order = 8, Color = Color3.fromRGB(255, 255, 255), Weight = 0.01, Gradient = true },
} :: { RarityInfo }

-- Rarities at or above this order are boosted by luck (server luck, Supernova...).
Planets.LuckyRarityOrder = 4

local rarityById: { [string]: RarityInfo } = {}
for _, info in Planets.Rarities do
	rarityById[info.Id] = info
end

-- Share of the rarity weight given to the 1st, 2nd, 3rd and 4th planet of a rarity.
local SHARE = { 0.4, 0.3, 0.2, 0.1 }

local C = Color3.fromRGB
local M = Enum.Material

local list: { PlanetDef } = {}
local byId: { [string]: PlanetDef } = {}

local function add(id: string, name: string, rarity: string, price: number, income: number, visual: Visual)
	local rarityInfo = rarityById[rarity]
	assert(rarityInfo, "unknown rarity " .. rarity)
	local def: PlanetDef = {
		Id = id,
		Name = name,
		Rarity = rarity,
		Price = price,
		Income = income,
		Order = #list + 1,
		Weight = 0,
		Visual = visual,
	}
	table.insert(list, def)
	byId[id] = def
end

-- Common
add("Pebble", "Pebble", "Common", 25, 1, { Kind = "Asteroid", Color = C(125, 120, 115), Material = M.Slate, Size = 2.2 })
add("SpaceRock", "Space Rock", "Common", 60, 2, { Kind = "Asteroid", Color = C(150, 105, 75), Material = M.Rock, Size = 2.6 })
add("CheeseMoon", "Cheese Moon", "Common", 120, 4, {
	Kind = "Moon",
	Color = C(255, 214, 90),
	Secondary = C(222, 170, 50),
	Size = 2.8,
})
add("Moon", "Moon", "Common", 250, 7, {
	Kind = "Moon",
	Color = C(205, 205, 212),
	Secondary = C(150, 150, 158),
	Material = M.Slate,
	Size = 3,
})

-- Uncommon
add("Comet", "Comet", "Uncommon", 500, 12, {
	Kind = "Comet",
	Color = C(175, 230, 255),
	Secondary = C(90, 200, 255),
	Material = M.Ice,
	Size = 2.6,
})
add("Mercury", "Mercury", "Uncommon", 900, 20, {
	Kind = "Moon",
	Color = C(165, 145, 128),
	Secondary = C(110, 95, 85),
	Material = M.Slate,
	Size = 2.8,
})
add("Pluto", "Pluto", "Uncommon", 1_600, 32, {
	Kind = "Moon",
	Color = C(235, 215, 195),
	Secondary = C(190, 150, 120),
	Size = 2.6,
})
add("Mars", "Mars", "Uncommon", 2_800, 50, {
	Kind = "Planet",
	Color = C(215, 92, 55),
	Secondary = C(170, 60, 40),
	Material = M.Sand,
	Size = 3.2,
	Bands = 1,
})

-- Rare
add("Venus", "Venus", "Rare", 5_000, 85, {
	Kind = "Planet",
	Color = C(238, 188, 100),
	Secondary = C(210, 150, 70),
	Material = M.Sand,
	Size = 3.4,
	Bands = 2,
})
add("Earth", "Earth", "Rare", 9_000, 140, {
	Kind = "Earth",
	Color = C(60, 130, 230),
	Secondary = C(70, 185, 80),
	Size = 3.5,
})
add("Neptune", "Neptune", "Rare", 15_000, 220, {
	Kind = "Planet",
	Color = C(50, 90, 225),
	Secondary = C(90, 140, 255),
	Size = 3.8,
	Bands = 2,
})
add("Uranus", "Uranus", "Rare", 25_000, 350, {
	Kind = "Planet",
	Color = C(140, 220, 232),
	Secondary = C(205, 240, 245),
	Size = 3.8,
	Ring = true,
	RingTilt = 75,
})

-- Epic
add("Saturn", "Saturn", "Epic", 45_000, 600, {
	Kind = "Planet",
	Color = C(232, 202, 142),
	Secondary = C(200, 170, 110),
	Size = 4.2,
	Bands = 2,
	Ring = true,
	RingTilt = 18,
})
add("Jupiter", "Jupiter", "Epic", 80_000, 1_000, {
	Kind = "Planet",
	Color = C(218, 162, 112),
	Secondary = C(172, 110, 70),
	Size = 4.6,
	Bands = 3,
})
add("MagmaWorld", "Magma World", "Epic", 140_000, 1_600, {
	Kind = "Planet",
	Color = C(70, 30, 22),
	Secondary = C(255, 110, 25),
	Material = M.CrackedLava,
	Size = 4,
	Bands = 1,
	Particles = true,
})
add("CandyPlanet", "Candy Planet", "Epic", 250_000, 2_600, {
	Kind = "Planet",
	Color = C(255, 145, 205),
	Secondary = C(255, 255, 255),
	Size = 4,
	Bands = 3,
	Ring = true,
	RingTilt = 25,
})

-- Legendary
add("Sun", "Sun", "Legendary", 500_000, 4_500, {
	Kind = "Star",
	Color = C(255, 205, 45),
	Size = 4.8,
	Particles = true,
})
add("RedGiant", "Red Giant", "Legendary", 1_000_000, 8_000, {
	Kind = "Star",
	Color = C(255, 85, 45),
	Size = 5.2,
	Particles = true,
})
add("BlueGiant", "Blue Giant", "Legendary", 2_000_000, 14_000, {
	Kind = "Star",
	Color = C(90, 165, 255),
	Size = 5.2,
	Particles = true,
})
add("DiscoPlanet", "Disco Planet", "Legendary", 4_000_000, 25_000, {
	Kind = "Planet",
	Color = C(230, 230, 242),
	Secondary = C(255, 255, 255),
	Material = M.Foil,
	Size = 4.2,
	Ring = true,
	RingTilt = 20,
	Rainbow = true,
})

-- Mythic
add("NeutronStar", "Neutron Star", "Mythic", 8_000_000, 45_000, {
	Kind = "Star",
	Color = C(205, 242, 255),
	Size = 3,
	Particles = true,
})
add("Pulsar", "Pulsar", "Mythic", 16_000_000, 80_000, {
	Kind = "Pulsar",
	Color = C(150, 222, 255),
	Secondary = C(120, 200, 255),
	Size = 3.2,
	Particles = true,
})
add("Nebula", "Nebula", "Mythic", 35_000_000, 150_000, {
	Kind = "Nebula",
	Color = C(255, 100, 205),
	Secondary = C(100, 125, 255),
	Size = 5,
	Particles = true,
})
add("Supernova", "Supernova", "Mythic", 70_000_000, 280_000, {
	Kind = "Star",
	Color = C(255, 240, 205),
	Secondary = C(255, 140, 50),
	Size = 5.4,
	Ring = true,
	RingTilt = 10,
	Particles = true,
})

-- Cosmic
add("BlackHole", "Black Hole", "Cosmic", 150_000_000, 550_000, {
	Kind = "BlackHole",
	Color = C(0, 0, 0),
	Secondary = C(255, 140, 40),
	Size = 4.4,
	Particles = true,
})
add("Quasar", "Quasar", "Cosmic", 350_000_000, 1_100_000, {
	Kind = "Quasar",
	Color = C(0, 0, 0),
	Secondary = C(120, 205, 255),
	Size = 4.4,
	Particles = true,
})
add("Galaxy", "Galaxy", "Cosmic", 800_000_000, 2_200_000, {
	Kind = "Galaxy",
	Color = C(180, 120, 255),
	Secondary = C(90, 165, 255),
	Size = 5,
	Particles = true,
})
add("Wormhole", "Wormhole", "Cosmic", 2_000_000_000, 4_500_000, {
	Kind = "Wormhole",
	Color = C(175, 65, 255),
	Secondary = C(20, 0, 45),
	Size = 5,
	Particles = true,
})

-- Secret
add("TON618", "TON 618", "Secret", 5_000_000_000, 10_000_000, {
	Kind = "BlackHole",
	Color = C(0, 0, 0),
	Secondary = C(255, 215, 90),
	Size = 6,
	Ring = true,
	RingTilt = 30,
	Particles = true,
})
add("Multiverse", "The Multiverse", "Secret", 15_000_000_000, 25_000_000, {
	Kind = "Multiverse",
	Color = C(255, 255, 255),
	Secondary = C(255, 255, 255),
	Size = 5.5,
	Particles = true,
	Rainbow = true,
})

-- Distribute each rarity's weight among its planets (cheaper ones are more common).
do
	local seen: { [string]: number } = {}
	for _, def in list do
		local n = (seen[def.Rarity] or 0) + 1
		seen[def.Rarity] = n
		local share = SHARE[n] or SHARE[#SHARE]
		def.Weight = rarityById[def.Rarity].Weight * share
	end
	-- Normalise shares when a rarity has fewer than 4 planets.
	for rarityId, count in seen do
		local used = 0
		for i = 1, count do
			used += SHARE[i] or SHARE[#SHARE]
		end
		for _, def in list do
			if def.Rarity == rarityId then
				def.Weight /= used
			end
		end
	end
end

Planets.List = list

function Planets.Get(id: string): PlanetDef?
	return byId[id]
end

function Planets.Rarity(id: string): RarityInfo
	return rarityById[id] or Planets.Rarities[1]
end

function Planets.RarityOrder(id: string): number
	local info = rarityById[id]
	return if info then info.Order else 1
end

-- rand() must return a number in [0, 1).
function Planets.Roll(rand: () -> number, luck: number): PlanetDef
	local total = 0
	for _, def in list do
		local w = def.Weight
		if Planets.RarityOrder(def.Rarity) >= Planets.LuckyRarityOrder then
			w *= luck
		end
		total += w
	end
	local pick = rand() * total
	for _, def in list do
		local w = def.Weight
		if Planets.RarityOrder(def.Rarity) >= Planets.LuckyRarityOrder then
			w *= luck
		end
		pick -= w
		if pick <= 0 then
			return def
		end
	end
	return list[1]
end

function Planets.OfRarity(rarity: string): { PlanetDef }
	local result = {}
	for _, def in list do
		if def.Rarity == rarity then
			table.insert(result, def)
		end
	end
	return result
end

function Planets.RandomOfRarity(rand: () -> number, rarity: string): PlanetDef
	local pool = Planets.OfRarity(rarity)
	if #pool == 0 then
		return list[1]
	end
	local total = 0
	for _, def in pool do
		total += def.Weight
	end
	local pick = rand() * total
	for _, def in pool do
		pick -= def.Weight
		if pick <= 0 then
			return def
		end
	end
	return pool[#pool]
end

return Planets
