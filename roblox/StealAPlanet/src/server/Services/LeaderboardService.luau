--!strict
-- leaderstats (player list) + global leaderboards (OrderedDataStore) shown on
-- the boards next to the west portal.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

type Board = {
	Name: string,
	Store: OrderedDataStore?,
	Rows: { TextLabel },
	Value: (Types.PlayerData) -> number,
	Display: (number) -> string,
}

local boards: { Board } = {}
local nameCache: { [number]: string } = {}
local MAX_VALUE = 9e18

local function getName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else "Player"
	nameCache[userId] = result
	return result
end

function LeaderboardService.Setup(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Value = Format.Cash(data.Cash)
	cash.Parent = stats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = data.Rebirths
	rebirths.Parent = stats
	local steals = Instance.new("IntValue")
	steals.Name = "Steals"
	steals.Value = data.Steals
	steals.Parent = stats
	stats.Parent = player
end

local function updateStats()
	for _, player in Players:GetPlayers() do
		local data = DataService.Get(player)
		local stats = player:FindFirstChild("leaderstats")
		if data and stats then
			local cash = stats:FindFirstChild("Cash")
			if cash and cash:IsA("StringValue") then
				local text = Format.Cash(data.Cash)
				if cash.Value ~= text then
					cash.Value = text
				end
			end
			local rebirths = stats:FindFirstChild("Rebirths")
			if rebirths and rebirths:IsA("IntValue") and rebirths.Value ~= data.Rebirths then
				rebirths.Value = data.Rebirths
			end
			local steals = stats:FindFirstChild("Steals")
			if steals and steals:IsA("IntValue") and steals.Value ~= data.Steals then
				steals.Value = data.Steals
			end
		end
	end
end

local function pushScores()
	for _, board in boards do
		local store = board.Store
		if store then
			for _, player in Players:GetPlayers() do
				local data = DataService.Get(player)
				if data then
					local value = math.clamp(math.floor(board.Value(data)), 0, MAX_VALUE)
					pcall(function()
						store:SetAsync(tostring(player.UserId), value)
					end)
				end
			end
		end
	end
end

local function refreshBoards()
	for _, board in boards do
		local store = board.Store
		if not store then
			board.Rows[1].Text = "Leaderboard offline"
			continue
		end
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, 10)
		end)
		if not ok or not pages then
			board.Rows[1].Text = "Leaderboard offline"
			continue
		end
		local entries = pages:GetCurrentPage()
		for i, row in board.Rows do
			local entry = entries[i]
			if entry then
				local userId = tonumber(entry.key) or 0
				local value = tonumber(entry.value) or 0
				local medal = if i == 1 then "🥇" elseif i == 2 then "🥈" elseif i == 3 then "🥉" else "#" .. i
				row.Text = medal .. "  " .. getName(userId) .. "  -  " .. board.Display(value)
			else
				row.Text = if i == 1 then "Be the first!" else ""
			end
		end
	end
end

function LeaderboardService.Init(map: Instance)
	local folder = map:WaitForChild("Leaderboards", 10)
	local definitions = {
		{
			Name = "LB_TotalEarned",
			Value = function(data: Types.PlayerData): number
				return data.TotalEarned
			end,
			Display = Format.Cash,
		},
		{
			Name = "LB_Steals",
			Value = function(data: Types.PlayerData): number
				return data.Steals
			end,
			Display = function(n: number): string
				return Format.Number(n) .. " steals"
			end,
		},
		{
			Name = "LB_Rebirths",
			Value = function(data: Types.PlayerData): number
				return data.Rebirths
			end,
			Display = function(n: number): string
				return Format.Number(n) .. " rebirths"
			end,
		},
	}
	for _, def in definitions do
		local model = if folder then folder:FindFirstChild(def.Name) else nil
		local boardPart = if model then model:FindFirstChild("Board") else nil
		local gui = if boardPart then boardPart:FindFirstChild("BoardGui") else nil
		local rowsFrame = if gui then gui:FindFirstChild("Rows") else nil
		if rowsFrame then
			local rows: { TextLabel } = {}
			for i = 1, 10 do
				local row = rowsFrame:FindFirstChild("Row" .. i)
				if row and row:IsA("TextLabel") then
					table.insert(rows, row)
				end
			end
			local store: OrderedDataStore? = nil
			local ok, result = pcall(function()
				return DataStoreService:GetOrderedDataStore(Config.LeaderboardPrefix .. def.Name)
			end)
			if ok then
				store = result
			end
			if #rows == 10 then
				table.insert(boards, {
					Name = def.Name,
					Store = store,
					Rows = rows,
					Value = def.Value,
					Display = def.Display,
				})
			end
		end
	end
end

function LeaderboardService.Run()
	task.spawn(function()
		while true do
			updateStats()
			task.wait(1)
		end
	end)
	task.spawn(function()
		task.wait(15)
		while true do
			pushScores()
			task.wait(5)
			refreshBoards()
			task.wait(115)
		end
	end)
end

return LeaderboardService
