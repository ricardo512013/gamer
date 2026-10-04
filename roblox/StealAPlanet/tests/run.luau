--!nocheck
-- Logic tests for the shared modules, run with Lune:
--   lune run tests/run.luau
-- Loads the real game modules (src/shared) with a tiny `script`/`require` shim.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local cache = {}
local loadModule

local function makeEnv(name)
	local parentProxy = setmetatable({}, {
		__index = function(_, key)
			return { __module = key }
		end,
	})
	return setmetatable({
		script = { Name = name, Parent = parentProxy },
		require = function(target)
			assert(type(target) == "table" and target.__module, "unsupported require in " .. name)
			return loadModule(target.__module)
		end,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Enum = roblox.Enum,
	}, { __index = _G })
end

function loadModule(name)
	if cache[name] ~= nil then
		return cache[name]
	end
	local source = fs.readFile("src/shared/" .. name .. ".luau")
	local chunk = luau.load(source, { debugName = name, environment = makeEnv(name) })
	local result = chunk()
	cache[name] = result
	return result
end

local Config = loadModule("Config")
local Planets = loadModule("Planets")
local Mutations = loadModule("Mutations")
local Format = loadModule("Format")
local Economy = loadModule("Economy")
local DataSchema = loadModule("DataSchema")

local passed, failed = 0, 0
local function check(name, condition, detail)
	if condition then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. tostring(detail) .. ")" else ""))
	end
end
local function eq(name, actual, expected)
	check(name, actual == expected, "got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

-- deterministic RNG for the tests
local seed = 12345
local function rand()
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end

---------------------------------------------------------------------------
-- Planets
---------------------------------------------------------------------------
eq("30 planets", #Planets.List, 30)
local rarityWeight = {}
local previousPrice, previousIncome = 0, 0
for i, def in Planets.List do
	check("rarity valid " .. def.Id, Planets.Rarity(def.Rarity).Id == def.Rarity)
	check("price increases " .. def.Id, def.Price > previousPrice, def.Price)
	check("income increases " .. def.Id, def.Income > previousIncome, def.Income)
	check("visual size " .. def.Id, def.Visual.Size >= 2 and def.Visual.Size <= 6.5)
	check("order " .. def.Id, def.Order == i)
	check("get " .. def.Id, Planets.Get(def.Id) == def)
	previousPrice, previousIncome = def.Price, def.Income
	rarityWeight[def.Rarity] = (rarityWeight[def.Rarity] or 0) + def.Weight
end
for _, info in Planets.Rarities do
	check("rarity weight " .. info.Id, math.abs((rarityWeight[info.Id] or 0) - info.Weight) < 1e-9, rarityWeight[info.Id])
end

local counts = {}
local N = 200000
for _ = 1, N do
	local def = Planets.Roll(rand, 1)
	counts[def.Rarity] = (counts[def.Rarity] or 0) + 1
end
local totalWeight = 0
for _, info in Planets.Rarities do
	totalWeight += info.Weight
end
local commonShare = counts.Common / N
check("common share ~55%", math.abs(commonShare - 55 / totalWeight) < 0.01, commonShare)
local epicPlus = 0
for rarity, c in counts do
	if Planets.RarityOrder(rarity) >= 4 then
		epicPlus += c
	end
end
local luckyCounts = 0
for _ = 1, N do
	if Planets.RarityOrder(Planets.Roll(rand, 3).Rarity) >= 4 then
		luckyCounts += 1
	end
end
check("luck x3 boosts epic+", luckyCounts > epicPlus * 2.3, luckyCounts .. " vs " .. epicPlus)
for _, info in Planets.Rarities do
	for _ = 1, 50 do
		eq("RandomOfRarity " .. info.Id, Planets.RandomOfRarity(rand, info.Id).Rarity, info.Id)
	end
end
print(string.format("Belt odds per spawn: Common %.1f%% | Mythic+ 1 in %d | Cosmic+ 1 in %d | Secret 1 in %d",
	commonShare * 100,
	math.floor(totalWeight / (0.33 + 0.06 + 0.01)),
	math.floor(totalWeight / (0.06 + 0.01)),
	math.floor(totalWeight / 0.01)))

---------------------------------------------------------------------------
-- Mutations
---------------------------------------------------------------------------
local mutationCounts = {}
for _ = 1, N do
	local id = Mutations.Roll(rand, nil)
	mutationCounts[id] = (mutationCounts[id] or 0) + 1
end
check("gold ~4%", math.abs((mutationCounts.Gold or 0) / N - 0.04) < 0.004, (mutationCounts.Gold or 0) / N)
check("none majority", (mutationCounts.None or 0) / N > 0.9)
local boosted = 0
for _ = 1, N do
	if Mutations.Roll(rand, { Gold = 8 }) == "Gold" then
		boosted += 1
	end
end
check("solar flare gold ~30%", boosted / N > 0.25 and boosted / N < 0.36, boosted / N)
eq("mult galaxy", Mutations.Mult("Galaxy"), 5)
eq("mult unknown", Mutations.Mult("Nope"), 1)
eq("get unknown -> None", Mutations.Get("Nope").Id, "None")

---------------------------------------------------------------------------
-- Format
---------------------------------------------------------------------------
eq("fmt 0", Format.Cash(0), "$0")
eq("fmt 999", Format.Cash(999), "$999")
eq("fmt 1000", Format.Cash(1000), "$1K")
eq("fmt 1250", Format.Cash(1250), "$1.25K")
eq("fmt 1150", Format.Cash(1150), "$1.15K")
eq("fmt 12345", Format.Cash(12345), "$12.3K")
eq("fmt 999999", Format.Cash(999999), "$999K")
eq("fmt 1e6", Format.Cash(1e6), "$1M")
eq("fmt 2.5e9", Format.Cash(2.5e9), "$2.5B")
eq("fmt 1e12", Format.Cash(1e12), "$1T")
eq("fmt 1e15", Format.Cash(1e15), "$1Qa")
eq("fmt negative", Format.Number(-1500), "-1.5K")
eq("fmt nan", Format.Number(0 / 0), "0")
eq("fmt fraction", Format.Cash(12.9), "$12")
eq("per second", Format.PerSecond(4500), "$4.5K/s")
eq("clock 125", Format.Clock(125), "2:05")
eq("clock 3725", Format.Clock(3725), "1:02:05")
eq("clock negative", Format.Clock(-5), "0:00")
eq("duration 3725", Format.Duration(3725), "1h 02m")
eq("duration 9", Format.Duration(9), "9s")
eq("multiplier", Format.Multiplier(1.5), "x1.5")
eq("multiplier int", Format.Multiplier(2), "x2")
for exponent = 3, 35 do
	local text = Format.Number(10 ^ exponent)
	check("power of ten " .. exponent, string.sub(text, 1, 1) == "1" and not string.find(text, "1000"), text)
end

---------------------------------------------------------------------------
-- Economy
---------------------------------------------------------------------------
eq("rebirth cost 1", Economy.RebirthCost(1), 500000)
eq("rebirth cost 2", Economy.RebirthCost(2), 4000000)
eq("rebirth mult 0", Economy.RebirthMultiplier(0), 1)
eq("rebirth mult 3", Economy.RebirthMultiplier(3), 2.5)
eq("slots r0", Economy.UnlockedSlots(0), 10)
eq("slots r1", Economy.UnlockedSlots(1), 12)
eq("slots r5", Economy.UnlockedSlots(5), 20)
eq("slots r9", Economy.UnlockedSlots(9), 20)
eq("slot req 10", Economy.SlotRebirthRequirement(10), 0)
eq("slot req 11", Economy.SlotRebirthRequirement(11), 1)
eq("slot req 12", Economy.SlotRebirthRequirement(12), 1)
eq("slot req 13", Economy.SlotRebirthRequirement(13), 2)
eq("slot req 20", Economy.SlotRebirthRequirement(20), 5)
for slot = 1, Config.MaxSlots do
	local req = Economy.SlotRebirthRequirement(slot)
	check("slot " .. slot .. " unlocked at its rebirth", Economy.UnlockedSlots(req) >= slot)
	if req > 0 then
		check("slot " .. slot .. " locked before", Economy.UnlockedSlots(req - 1) < slot)
	end
end
eq("lock r0", Economy.LockDuration(0, false), 60)
eq("lock r2 double", Economy.LockDuration(2, true), 140)
local earth = Planets.Get("Earth")
eq("income gold earth", Economy.PlanetIncome(earth, "Gold"), 210)
eq("price diamond earth", Economy.PlanetPrice(earth, "Diamond"), 18000)
eq("sell earth", Economy.SellValue(earth, "None"), 4500)
check("index bonus", math.abs(Economy.IndexBonus({ Earth = true, Mars = true, ["Earth:Gold"] = true }) - 0.025) < 1e-9)
local p, v = Economy.IndexCounts({ Earth = true, ["Earth:Gold"] = true, Mars = false })
eq("index counts planets", p, 1)
eq("index counts variants", v, 1)
local function near(name, actual, expected)
	check(name, math.abs(actual - expected) < 1e-9, "got " .. tostring(actual) .. ", expected " .. tostring(expected))
end
near(
	"multiplier",
	Economy.Multiplier({
		Rebirths = 2,
		VIP = true,
		DoubleCash = true,
		IndexBonus = 0.1,
		FriendBonus = 0.2,
		GroupBonus = 0.1,
		EventMult = 2,
	}),
	2 * 1.5 * 2 * 1.4 * 2
)
eq("scaled reward min", Economy.ScaledReward(0, 600, 10000), 10000)
eq("scaled reward", Economy.ScaledReward(100, 600, 10), 60000)
eq("offline none", Economy.OfflineSeconds(0, 1000, 3), 0)
eq("offline capped", Economy.OfflineSeconds(1000, 1000 + 99999, 3), 10800)
eq("offline normal", Economy.OfflineSeconds(1000, 1600, 3), 600)

---------------------------------------------------------------------------
-- DataSchema
---------------------------------------------------------------------------
local default = DataSchema.Reconcile(nil)
eq("default cash", default.Cash, Config.StartingCash)
eq("default version", default.Version, DataSchema.Version)
local messy = DataSchema.Reconcile({
	Cash = 0 / 0,
	TotalEarned = -5,
	Rebirths = 2.7,
	Slots = {
		["1"] = { Id = "Earth", Mut = "Gold", Acc = 50 },
		["2"] = { Id = "DeletedPlanet", Mut = "None", Acc = 0 },
		["3"] = { Id = "Mars", Mut = "Weird", Acc = 0 },
		["99"] = { Id = "Mars", Mut = "None", Acc = 0 },
		["1.5"] = { Id = "Mars", Mut = "None", Acc = 0 },
		bad = "x",
	},
	Pending = { { Id = "Sun", Mut = "None" }, { Id = 5, Mut = "None" }, "junk" },
	Tools = { SpeedCoil = true, Cloak = "yes" },
	Index = { Earth = true, [5] = true },
	Receipts = { "a", 5, "b" },
	GroupClaimed = "true",
	SessionJob = "job-1",
	SessionTime = 100,
})
eq("nan cash -> default", messy.Cash, Config.StartingCash)
eq("negative earned clamped", messy.TotalEarned, 0)
eq("rebirths floored", messy.Rebirths, 2)
check("valid slot kept", messy.Slots["1"] ~= nil and messy.Slots["1"].Acc == 50)
check("deleted planet dropped", messy.Slots["2"] == nil)
check("bad mutation dropped", messy.Slots["3"] == nil)
check("out of range slot dropped", messy.Slots["99"] == nil)
check("fractional slot dropped", messy.Slots["1.5"] == nil)
eq("pending filtered", #messy.Pending, 1)
check("tools filtered", messy.Tools.SpeedCoil == true and messy.Tools.Cloak == nil)
check("index filtered", messy.Index.Earth == true)
eq("receipts filtered", #messy.Receipts, 2)
eq("group claimed strict", messy.GroupClaimed, false)
eq("session job kept", messy.SessionJob, "job-1")

---------------------------------------------------------------------------
-- Config sanity
---------------------------------------------------------------------------
for key, info in Config.Products do
	check("product kind " .. key, info.Kind == "Cash" or info.Kind == "ServerLuck" or info.Kind == "Event" or info.Kind == "Lock" or info.Kind == "BuyPlanet")
	if info.Kind == "BuyPlanet" then
		check("product rarity " .. key, info.Rarity ~= nil and #Planets.OfRarity(info.Rarity) > 0)
		eq("product key matches rarity " .. key, key, "Buy" .. info.Rarity)
	end
end
for i, reward in Config.DailyRewards do
	check("daily reward " .. i, reward.Seconds ~= nil or reward.Rarity ~= nil or reward.Cash ~= nil)
end
for code, reward in Config.Codes do
	eq("code uppercase " .. code, string.upper(code), code)
	if reward.Planet then
		check("code planet exists " .. code, Planets.Get(reward.Planet) ~= nil)
	end
	if reward.Mutation then
		check("code mutation exists " .. code, Mutations.IsValid(reward.Mutation))
	end
end
for _, info in Config.Events do
	if info.MutationMult then
		for id in info.MutationMult do
			check("event mutation " .. info.Id .. " " .. id, Mutations.IsValid(id))
		end
	end
end
for id, info in Config.Tools do
	check("tool order " .. id, type(info.Order) == "number")
end

---------------------------------------------------------------------------
-- Economy pacing simulation (greedy player, ideal collecting)
---------------------------------------------------------------------------
local function simulate(maxSeconds)
	local cash = Config.StartingCash
	local rebirths = 0
	local slots = {}
	local belt = {}
	local milestones = {}
	local visible = math.floor(320 / (Config.Belt.Speed * Config.Belt.SpawnInterval))
	for t = 1, maxSeconds do
		if t % Config.Belt.SpawnInterval == 0 then
			local def = Planets.Roll(rand, 1)
			table.insert(belt, { def = def, mut = Mutations.Roll(rand, nil) })
			if #belt > visible then
				table.remove(belt, 1)
			end
		end
		local mult = Economy.RebirthMultiplier(rebirths)
		local income = 0
		for _, s in slots do
			income += Economy.PlanetIncome(s.def, s.mut) * mult
		end
		cash += income
		-- buy the best affordable planet on the belt
		local bestIndex, bestIncome = nil, 0
		for i, item in belt do
			local price = Economy.PlanetPrice(item.def, item.mut)
			local inc = Economy.PlanetIncome(item.def, item.mut)
			if price <= cash and inc > bestIncome then
				bestIndex, bestIncome = i, inc
			end
		end
		if bestIndex then
			local item = belt[bestIndex]
			local capacity = Economy.UnlockedSlots(rebirths)
			local worstIndex, worstIncome = nil, math.huge
			for i, s in slots do
				local inc = Economy.PlanetIncome(s.def, s.mut)
				if inc < worstIncome then
					worstIndex, worstIncome = i, inc
				end
			end
			if #slots < capacity then
				cash -= Economy.PlanetPrice(item.def, item.mut)
				table.insert(slots, item)
				table.remove(belt, bestIndex)
			elseif worstIndex and bestIncome > worstIncome * 1.5 then
				cash -= Economy.PlanetPrice(item.def, item.mut)
				cash += Economy.SellValue(slots[worstIndex].def, slots[worstIndex].mut)
				slots[worstIndex] = item
				table.remove(belt, bestIndex)
			end
		end
		if cash >= Economy.RebirthCost(rebirths + 1) then
			rebirths += 1
			cash = Config.StartingCash
			slots = {}
			table.insert(milestones, string.format("rebirth %d at %s", rebirths, Format.Duration(t)))
		end
	end
	return milestones, rebirths
end
local milestones = simulate(6 * 3600)
print("Pacing (greedy simulated player, 6h): " .. (if #milestones > 0 then table.concat(milestones, " | ") else "no rebirth"))
check("first rebirth reachable in 6h", #milestones >= 1)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
