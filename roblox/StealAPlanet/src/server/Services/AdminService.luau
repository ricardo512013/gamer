--!strict
-- Admin panel actions ("admin abuse" events are a proven way to pull players in:
-- announce them on your socials and run them here).
-- Admins: the game owner, group members with rank >= Config.AdminGroupRank,
-- user ids in Config.Admins, and everyone while testing in Studio.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Mutations = require(Shared.Mutations)
local Net = require(Shared.Net)
local Planets = require(Shared.Planets)

local BeltService = require(script.Parent.BeltService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)

local AdminService = {}

local admins: { [Player]: boolean } = {}
local rng = Random.new()

local function computeIsAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Config.Admins, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, result = pcall(function()
			return GroupService:GetRolesInGroupAsync(player.UserId, game.CreatorId)
		end)
		if not ok or type(result) ~= "table" or result.IsMember ~= true or type(result.Roles) ~= "table" then
			return false
		end
		for _, role in result.Roles do
			if type(role) == "table" and type(role.Rank) == "number" and role.Rank >= Config.AdminGroupRank then
				return true
			end
		end
		return false
	end
	return false
end

local function adminAbuse()
	Net.NotifyAll("🚨 ADMIN ABUSE! Rare planets incoming for 60 seconds + Server Luck x5!", "event")
	EventService.AddLuck(5 * 60, 5, nil)
	EventService.Start("MeteorShower", 120, "Admin")
	task.spawn(function()
		for _ = 1, 12 do
			local rarity = if rng:NextNumber() < 0.15 then "Cosmic" elseif rng:NextNumber() < 0.5 then "Mythic" else "Legendary"
			local def = Planets.RandomOfRarity(function()
				return rng:NextNumber()
			end, rarity)
			local mutation = Mutations.Roll(function()
				return rng:NextNumber()
			end, { Gold = 6, Diamond = 6, Rainbow = 6, Galaxy = 6 })
			BeltService.Spawn(def, mutation)
			task.wait(5)
		end
	end)
end

local function handle(player: Player, action: any, arg1: any, arg2: any): Net.Result
	if not admins[player] then
		return { ok = false, msg = "Not an admin" }
	end
	if action == "Event" and type(arg1) == "string" and EventService.Get(arg1) then
		EventService.Start(arg1, nil, "Admin")
	elseif action == "GlobalEvent" and type(arg1) == "string" and EventService.Get(arg1) then
		EventService.StartGlobal(arg1)
	elseif action == "StopEvent" then
		EventService.Stop()
	elseif action == "Luck" and type(arg1) == "number" then
		EventService.AddLuck(10 * 60, math.clamp(arg1, 2, 10), nil)
	elseif action == "Cash" and type(arg1) == "number" then
		DataService.AddCash(player, math.clamp(arg1, 0, 1e15))
	elseif action == "Spawn" and type(arg1) == "string" and Planets.Get(arg1) then
		local mutation = if type(arg2) == "string" and Mutations.IsValid(arg2) then arg2 else "None"
		BeltService.Spawn(Planets.Get(arg1) :: Planets.PlanetDef, mutation)
	elseif action == "AdminAbuse" then
		adminAbuse()
	else
		return { ok = false, msg = "Unknown admin action" }
	end
	return { ok = true }
end

function AdminService.PlayerAdded(player: Player)
	local isAdmin = computeIsAdmin(player)
	if isAdmin then
		admins[player] = true
	else
		admins[player] = nil
	end
	player:SetAttribute("IsAdmin", isAdmin)
end

function AdminService.Init()
	Net.Handle("Admin", handle)
	Players.PlayerRemoving:Connect(function(player)
		admins[player] = nil
	end)
end

return AdminService
