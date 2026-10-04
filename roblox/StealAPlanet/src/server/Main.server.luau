--!strict
-- STEAL A PLANET - server entry point.
-- Builds the map, starts every service and runs the join/leave sequence in a
-- fixed order (data -> passes -> base -> planets -> tools -> sync).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local Services = script.Parent:WaitForChild("Services")
local AdminService = require(Services.AdminService)
local BeltService = require(Services.BeltService)
local CharacterService = require(Services.CharacterService)
local DataService = require(Services.DataService)
local EventService = require(Services.EventService)
local FriendsService = require(Services.FriendsService)
local LeaderboardService = require(Services.LeaderboardService)
local MapBuilder = require(Services.MapBuilder)
local MonetizationService = require(Services.MonetizationService)
local PlotService = require(Services.PlotService)
local ProgressionService = require(Services.ProgressionService)
local StealService = require(Services.StealService)
local SyncService = require(Services.SyncService)
local ToolService = require(Services.ToolService)

Workspace.Gravity = Config.Gravity
Net.StartServer()

MapBuilder.SetupLighting(Lighting)
local map = MapBuilder.Build(Workspace)

DataService.Init()
EventService.Init()
CharacterService.Init()
PlotService.Init(map)
StealService.Init()
BeltService.Init()
ToolService.Init()
ProgressionService.Init()
MonetizationService.Init()
LeaderboardService.Init(map)
AdminService.Init()

CharacterService.SetSpawnResolver(PlotService.SpawnCFrame)

local function onPlayerAdded(player: Player)
	CharacterService.PlayerAdded(player)
	if not DataService.Load(player) or not player.Parent then
		return
	end
	MonetizationService.CheckPasses(player)
	AdminService.PlayerAdded(player)
	ProgressionService.PlayerAdded(player)

	local plot = PlotService.Assign(player)
	if not plot then
		player:Kick("This server is full! Please join another one.")
		return
	end
	local offline, seconds = PlotService.ApplyOffline(player)
	LeaderboardService.Setup(player)
	ToolService.PlayerAdded(player)
	task.spawn(FriendsService.PlayerAdded, player)

	DataService.MarkDirty(player)
	SyncService.Send(player)
	if offline > 0 then
		Net.Effect(player, "Welcome", { Amount = offline, Seconds = seconds })
	end
	Net.Notify(player, "🪐 Welcome to " .. Config.GameName .. "! Buy planets on the Cosmic Belt!", "info")
	local data = DataService.Get(player)
	if data and data.Rebirths > 0 then
		Net.Notify(player, "♻️ Rebirth " .. data.Rebirths .. " - cash x" .. Format.Number(PlotService.Multiplier(player)), "info")
	end
end

local function onPlayerRemoving(player: Player)
	StealService.PlayerRemoving(player)
	BeltService.PlayerRemoving(player)
	ToolService.PlayerRemoving(player)
	ProgressionService.PlayerRemoving(player)
	FriendsService.PlayerRemoving(player)
	SyncService.PlayerRemoving(player)
	PlotService.Release(player)
	CharacterService.PlayerRemoving(player)
	if DataService.IsLoaded(player) then
		DataService.Release(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

DataService.Start()
EventService.Run()
PlotService.Run()
StealService.Run()
BeltService.Run()
LeaderboardService.Run()
SyncService.Run()

print("[" .. Config.GameName .. "] server ready")
