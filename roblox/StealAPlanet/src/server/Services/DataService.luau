--!strict
-- Loads/saves player data with DataStoreService.
-- * UpdateAsync everywhere, with retries
-- * session lock so two servers never write the same player at the same time
-- * autosave + save on leave + save on shutdown
-- In Studio without "Enable Studio Access to API Services" it falls back to
-- temporary data (nothing is saved) instead of erroring.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local DataSchema = require(Shared.DataSchema)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local DataService = {}

DataService.Loaded = Signal.new() -- (player, data)

local store: DataStore? = nil
local profiles: { [Player]: Types.PlayerData } = {}
local canSave: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
local saving: { [Player]: boolean } = {}
local warnedStudio = false

local function key(player: Player): string
	return "Player_" .. player.UserId
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable: " .. tostring(result))
	end
end

local function useTemporaryData(player: Player, reason: string): boolean
	if not warnedStudio then
		warnedStudio = true
		warn(
			"[DataService] Using temporary data (nothing will be saved): "
				.. reason
				.. "\nTo test saving in Studio: Game Settings > Security > Enable Studio Access to API Services."
		)
	end
	local data = DataSchema.Default()
	data.FirstJoin = os.time()
	profiles[player] = data
	canSave[player] = false
	return true
end

-- Returns true when data is ready. Kicks the player if it cannot be loaded in a live server.
function DataService.Load(player: Player): boolean
	local dataStore = store
	if not dataStore then
		if RunService:IsStudio() then
			return useTemporaryData(player, "no DataStore")
		end
		player:Kick("Could not load your data (DataStore offline). Please rejoin in a moment!")
		return false
	end

	local loaded: Types.PlayerData? = nil
	local lastError = ""
	for attempt = 1, 6 do
		local lockedByOther = false
		local forceLock = attempt >= 5
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key(player), function(old: any)
				lockedByOther = false
				loaded = nil
				local data = DataSchema.Reconcile(old)
				local otherJob = data.SessionJob
				local lockTime = data.SessionTime or 0
				if
					not forceLock
					and otherJob
					and otherJob ~= ""
					and otherJob ~= game.JobId
					and os.time() - lockTime < Config.SessionLockTimeout
				then
					lockedByOther = true
					return nil
				end
				if data.FirstJoin == 0 then
					data.FirstJoin = os.time()
				end
				data.SessionJob = game.JobId
				data.SessionTime = os.time()
				loaded = data
				return data
			end)
		end)
		if ok and loaded and not lockedByOther then
			break
		end
		loaded = nil
		if not ok then
			lastError = tostring(err)
			if RunService:IsStudio() then
				return useTemporaryData(player, lastError)
			end
		end
		if not player.Parent then
			return false
		end
		task.wait(if lockedByOther then 3 else attempt)
	end

	local final = loaded
	if not player.Parent then
		if final then
			-- the player left while loading: release the session lock right away
			profiles[player] = final
			canSave[player] = true
			DataService.Release(player)
		end
		return false
	end
	if not final then
		player:Kick("Could not load your data. Please rejoin! (" .. lastError .. ")")
		return false
	end
	profiles[player] = final
	canSave[player] = true
	DataService.Loaded:Fire(player, final)
	return true
end

function DataService.Save(player: Player, release: boolean): boolean
	local data = profiles[player]
	local dataStore = store
	if not data or not canSave[player] or not dataStore then
		return false
	end
	if saving[player] then
		if not release then
			return false
		end
		-- let the running autosave finish so the final (lock releasing) write lands last
		local started = os.clock()
		while saving[player] and os.clock() - started < 15 do
			task.wait(0.1)
		end
	end
	saving[player] = true
	data.LastOnline = os.time()
	local success = false
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key(player), function(old: any)
				if
					type(old) == "table"
					and type(old.SessionJob) == "string"
					and old.SessionJob ~= ""
					and old.SessionJob ~= game.JobId
				then
					-- another server owns this player now; never overwrite it
					return nil
				end
				data.SessionJob = if release then nil else game.JobId
				data.SessionTime = os.time()
				return data
			end)
		end)
		if ok then
			success = true
			break
		end
		warn("[DataService] Save failed for " .. player.Name .. " (attempt " .. attempt .. "): " .. tostring(err))
		task.wait(attempt * 2)
	end
	saving[player] = nil
	return success
end

function DataService.Release(player: Player)
	DataService.Save(player, true)
	profiles[player] = nil
	canSave[player] = nil
	dirty[player] = nil
end

function DataService.Get(player: Player): Types.PlayerData?
	return profiles[player]
end

function DataService.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService.MarkDirty(player: Player)
	dirty[player] = true
end

function DataService.TakeDirty(): { Player }
	local list = {}
	for player in dirty do
		table.insert(list, player)
	end
	table.clear(dirty)
	return list
end

function DataService.AddCash(player: Player, amount: number)
	local data = profiles[player]
	if not data or amount ~= amount then
		return
	end
	data.Cash = math.max(0, data.Cash + amount)
	if amount > 0 then
		data.TotalEarned += amount
	end
	dirty[player] = true
end

function DataService.SpendCash(player: Player, amount: number): boolean
	local data = profiles[player]
	if not data or amount < 0 or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	dirty[player] = true
	return true
end

function DataService.Start()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(DataService.Save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for _, player in Players:GetPlayers() do
			if profiles[player] and canSave[player] then
				pending += 1
				task.spawn(function()
					DataService.Save(player, true)
					pending -= 1
				end)
			end
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

return DataService
