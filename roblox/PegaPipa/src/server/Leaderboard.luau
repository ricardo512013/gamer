--!strict
--[[
	Leaderboard (STUB — área "economia") — ranking semanal (GDD §5.5): OrderedDataStores Rei_{semana} (Vento)
	e Tesoura_{semana} (CortesPvP), SetAsync a cada LEADERBOARD_PERIOD só se mudou, GetSortedAsync com cache →
	SurfaceGui do Poste (tag Poste). Top 3 da semana anterior → atributo RabiolaRank 1-3 do Player.
	Dono de profile.Data.Weekly (reseta quando a semana muda). Requer: Config, DataService.
	Registra DataService.hooks.addWeekly no start(). KiteService chama addWeekly(p, "CortesPvP", 1).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local DataService = require(script.Parent.DataService)

export type WeeklyStat = "Vento" | "CortesPvP"

local Leaderboard = {}

function Leaderboard.start(): ()
	DataService.hooks.addWeekly = Leaderboard.addWeekly
	warn("[Leaderboard] stub", Config.LEADERBOARD_PERIOD)
end

-- Soma n em Weekly[stat] (reseta Weekly se a semana mudou).
function Leaderboard.addWeekly(p: Player, stat: WeeklyStat, n: number): ()
end

-- Semana desde segunda 00:00 UTC: (os.time() - WEEK_EPOCH_OFFSET) // WEEK_SECONDS.
function Leaderboard.weekIndex(): number
	return (os.time() - Config.WEEK_EPOCH_OFFSET) // Config.WEEK_SECONDS
end

-- userIds do top 3 da semana anterior (cache TOP3_CACHE_SECONDS).
function Leaderboard.previousTop3(): { number }
	return {}
end

return Leaderboard
