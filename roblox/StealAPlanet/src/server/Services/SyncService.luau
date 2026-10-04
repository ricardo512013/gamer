--!strict
-- Sends each player a snapshot of their state (cash, cash/s, index, daily...)
-- whenever it changes, plus a refresh every 2 seconds.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ProgressionService = require(script.Parent.ProgressionService)

local SyncService = {}

local sentIndexVersion: { [Player]: number } = {}

function SyncService.Send(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local version = player:GetAttribute("IndexVersion")
	local indexVersion = if type(version) == "number" then version else 0
	local includeIndex = sentIndexVersion[player] ~= indexVersion
	sentIndexVersion[player] = indexVersion

	local dailyReady, dailyNextAt, dailyNextDay = ProgressionService.DailyStatus(player)
	local playtimeStart, playtimeClaimed = ProgressionService.PlaytimeStatus(player)

	local snapshot: Types.Snapshot = {
		Cash = data.Cash,
		CashPerSec = PlotService.CashPerSec(player),
		TotalEarned = data.TotalEarned,
		Rebirths = data.Rebirths,
		Steals = data.Steals,
		Multiplier = PlotService.Multiplier(player),
		SlotsUnlocked = PlotService.UnlockedSlots(player),
		SlotsUsed = PlotService.UsedSlots(player),
		Pending = #data.Pending,
		Tools = data.Tools,
		Index = if includeIndex then data.Index else nil,
		IndexVersion = indexVersion,
		RebirthCost = Economy.RebirthCost(data.Rebirths + 1),
		DailyStreak = data.DailyStreak,
		DailyReady = dailyReady,
		DailyNextAt = dailyNextAt,
		DailyNextDay = dailyNextDay,
		PlaytimeStart = playtimeStart,
		PlaytimeClaimed = playtimeClaimed,
		Tutorial = data.Tutorial,
		GroupClaimed = data.GroupClaimed,
		HomePosition = PlotService.HomePosition(player),
	}
	Net.Event("Sync"):FireClient(player, snapshot)
end

function SyncService.Run()
	task.spawn(function()
		local elapsed = 0
		while true do
			task.wait(0.25)
			elapsed += 0.25
			if elapsed >= 2 then
				elapsed = 0
				for _, player in Players:GetPlayers() do
					DataService.MarkDirty(player)
				end
			end
			for _, player in DataService.TakeDirty() do
				if player.Parent then
					SyncService.Send(player)
				end
			end
		end
	end)
end

function SyncService.PlayerRemoving(player: Player)
	sentIndexVersion[player] = nil
end

return SyncService
