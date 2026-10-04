--!strict
-- Rebirths, daily rewards (7-day streak), playtime gifts, codes and the
-- group reward. All reward types go through GrantReward.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Mutations = require(Shared.Mutations)
local Net = require(Shared.Net)
local Planets = require(Shared.Planets)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StealService = require(script.Parent.StealService)

local ProgressionService = {}

local rng = Random.new()
local sessionStart: { [Player]: number } = {} -- os.clock() at join
local sessionStartServer: { [Player]: number } = {} -- server time at join (for the client timer)
local playtimeClaimed: { [Player]: { [string]: boolean } } = {}

local function rand(): number
	return rng:NextNumber()
end

-- Grants a reward and returns a short description ("+$5K", "Earth").
function ProgressionService.GrantReward(player: Player, reward: Config.Reward): string
	local parts: { string } = {}
	local cash = 0
	if reward.Cash then
		cash += reward.Cash
	end
	if reward.Seconds then
		cash += Economy.ScaledReward(PlotService.CashPerSec(player), reward.Seconds, reward.Minimum or 0)
	end
	if cash > 0 then
		DataService.AddCash(player, cash)
		table.insert(parts, "+" .. Format.Cash(cash))
	end
	local planetId: string? = nil
	local mutation = reward.Mutation or "None"
	if reward.Planet and Planets.Get(reward.Planet) then
		planetId = reward.Planet
	elseif reward.Rarity then
		planetId = Planets.RandomOfRarity(rand, reward.Rarity).Id
	end
	if planetId then
		local def = Planets.Get(planetId)
		if def then
			PlotService.AddPlanet(player, def.Id, mutation)
			local label = if mutation ~= "None" then Mutations.Get(mutation).Name .. " " .. def.Name else def.Name
			table.insert(parts, label .. " (" .. def.Rarity .. ")")
		end
	end
	DataService.MarkDirty(player)
	return table.concat(parts, " + ")
end

-- Describes a reward without granting it (for the UI).
function ProgressionService.DescribeReward(player: Player, reward: Config.Reward): string
	local parts: { string } = {}
	local cash = reward.Cash or 0
	if reward.Seconds then
		cash += Economy.ScaledReward(PlotService.CashPerSec(player), reward.Seconds, reward.Minimum or 0)
	end
	if cash > 0 then
		table.insert(parts, Format.Cash(cash))
	end
	if reward.Planet then
		table.insert(parts, reward.Planet)
	elseif reward.Rarity then
		table.insert(parts, reward.Rarity .. " Planet")
	end
	return table.concat(parts, " + ")
end

local function rebirth(player: Player): Net.Result
	local data = DataService.Get(player)
	if not data then
		return { ok = false, msg = "Data not loaded" }
	end
	local cost = Economy.RebirthCost(data.Rebirths + 1)
	if data.Cash < cost then
		return { ok = false, msg = "You need " .. Format.Cash(cost) .. " to rebirth!" }
	end
	if StealService.IsCarrying(player) then
		StealService.Cancel(player, nil)
	end
	data.Rebirths += 1
	data.Cash = Config.StartingCash
	PlotService.ClearAll(player)
	PlotService.RefreshSlotLocks(player)
	DataService.MarkDirty(player)
	Net.Effect(player, "Confetti", {})
	Net.NotifyAll(
		"♻️ "
			.. player.DisplayName
			.. " reached REBIRTH "
			.. data.Rebirths
			.. "! (cash "
			.. Format.Multiplier(Economy.RebirthMultiplier(data.Rebirths))
			.. ")",
		"rare"
	)
	return { ok = true }
end

function ProgressionService.DailyStatus(player: Player): (boolean, number, number)
	local data = DataService.Get(player)
	if not data then
		return false, 0, 1
	end
	local now = os.time()
	local ready = now - data.DailyLast >= Config.DailyCooldown
	local nextDay: number
	if data.DailyLast == 0 or now - data.DailyLast > Config.DailyStreakWindow then
		nextDay = 1
	else
		nextDay = data.DailyStreak % #Config.DailyRewards + 1
	end
	return ready, data.DailyLast + Config.DailyCooldown, nextDay
end

local function claimDaily(player: Player): Net.Result
	local data = DataService.Get(player)
	if not data then
		return { ok = false, msg = "Data not loaded" }
	end
	local ready, _, nextDay = ProgressionService.DailyStatus(player)
	if not ready then
		return { ok = false, msg = "Come back later for your next reward!" }
	end
	data.DailyStreak = nextDay
	data.DailyLast = os.time()
	local text = ProgressionService.GrantReward(player, Config.DailyRewards[nextDay])
	Net.Notify(player, "🎁 Day " .. nextDay .. " reward: " .. text, "success")
	Net.Effect(player, "Confetti", {})
	return { ok = true, msg = text }
end

function ProgressionService.PlaytimeStatus(player: Player): (number, { [string]: boolean })
	return sessionStartServer[player] or Workspace:GetServerTimeNow(), playtimeClaimed[player] or {}
end

local function claimPlaytime(player: Player, index: any): Net.Result
	if type(index) ~= "number" then
		return { ok = false, msg = "Bad gift" }
	end
	local reward = Config.PlaytimeRewards[index]
	local start = sessionStart[player]
	local claimed = playtimeClaimed[player]
	if not reward or not start or not claimed then
		return { ok = false, msg = "Bad gift" }
	end
	local key = tostring(index)
	if claimed[key] then
		return { ok = false, msg = "Already claimed!" }
	end
	if os.clock() - start < reward.Minutes * 60 - 1 then
		return { ok = false, msg = "Not ready yet!" }
	end
	claimed[key] = true
	local text = ProgressionService.GrantReward(player, {
		Cash = reward.Cash,
		Seconds = reward.Seconds,
		Minimum = reward.Minimum,
		Rarity = reward.Rarity,
		Planet = reward.Planet,
		Mutation = reward.Mutation,
	})
	Net.Notify(player, "🎁 Gift: " .. text, "success")
	DataService.MarkDirty(player)
	return { ok = true, msg = text }
end

local function redeemCode(player: Player, code: any): Net.Result
	local data = DataService.Get(player)
	if not data or type(code) ~= "string" or #code > 40 then
		return { ok = false, msg = "Invalid code" }
	end
	local normalized = string.upper((string.gsub(code, "%s", "")))
	local reward = Config.Codes[normalized]
	if not reward then
		return { ok = false, msg = "Invalid code" }
	end
	if data.Codes[normalized] then
		return { ok = false, msg = "Already redeemed!" }
	end
	data.Codes[normalized] = true
	local text = ProgressionService.GrantReward(player, reward)
	return { ok = true, msg = "Redeemed: " .. text }
end

local function isInGroup(player: Player): boolean
	if Config.GroupId <= 0 then
		return false
	end
	local ok, result = pcall(function()
		return player:IsInGroupAsync(Config.GroupId)
	end)
	return ok and result == true
end

local function claimGroup(player: Player): Net.Result
	local data = DataService.Get(player)
	if not data then
		return { ok = false, msg = "Data not loaded" }
	end
	if Config.GroupId <= 0 then
		return { ok = false, msg = "Group rewards are not set up yet." }
	end
	if not isInGroup(player) then
		return { ok = false, msg = "Join the group first, then press again!" }
	end
	player:SetAttribute("InGroup", true)
	if data.GroupClaimed then
		return { ok = true, msg = "Group bonus active: +" .. math.floor(Config.GroupBonus * 100) .. "% cash!" }
	end
	data.GroupClaimed = true
	local text = ProgressionService.GrantReward(player, Config.GroupReward)
	return { ok = true, msg = "Thanks for joining! " .. text }
end

function ProgressionService.PlayerAdded(player: Player)
	sessionStart[player] = os.clock()
	sessionStartServer[player] = Workspace:GetServerTimeNow()
	playtimeClaimed[player] = {}
	if isInGroup(player) then
		player:SetAttribute("InGroup", true)
	end
end

function ProgressionService.PlayerRemoving(player: Player)
	local data = DataService.Get(player)
	local start = sessionStart[player]
	if data and start then
		data.PlayTime += os.clock() - start
	end
	sessionStart[player] = nil
	sessionStartServer[player] = nil
	playtimeClaimed[player] = nil
end

function ProgressionService.Init()
	Net.Handle("Rebirth", rebirth)
	Net.Handle("ClaimDaily", claimDaily)
	Net.Handle("ClaimPlaytime", claimPlaytime)
	Net.Handle("RedeemCode", redeemCode)
	Net.Handle("ClaimGroup", claimGroup)
end

return ProgressionService
