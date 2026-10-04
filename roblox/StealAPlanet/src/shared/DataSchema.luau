--!strict
-- Default player data and validation of whatever comes back from the DataStore.

local Config = require(script.Parent.Config)
local Planets = require(script.Parent.Planets)
local Mutations = require(script.Parent.Mutations)
local Types = require(script.Parent.Types)

local DataSchema = {}

DataSchema.Version = 1

function DataSchema.Default(): Types.PlayerData
	return {
		Version = DataSchema.Version,
		Cash = Config.StartingCash,
		TotalEarned = 0,
		Rebirths = 0,
		Steals = 0,
		TimesStolen = 0,
		Slots = {},
		Pending = {},
		Tools = {},
		Index = {},
		Codes = {},
		DailyStreak = 0,
		DailyLast = 0,
		LastOnline = 0,
		FirstJoin = 0,
		PlayTime = 0,
		GroupClaimed = false,
		Tutorial = 0,
		Receipts = {},
		SessionJob = nil,
		SessionTime = nil,
	}
end

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function num(v: any, default: number, minimum: number?): number
	if isNumber(v) then
		if minimum and v < minimum then
			return minimum
		end
		return v
	end
	return default
end

local function boolMap(v: any): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if type(v) == "table" then
		for key, value in v do
			if type(key) == "string" and value == true then
				result[key] = true
			end
		end
	end
	return result
end

local function validPlanet(id: any, mut: any): boolean
	return type(id) == "string" and Planets.Get(id) ~= nil and type(mut) == "string" and Mutations.IsValid(mut)
end

function DataSchema.Reconcile(raw: any): Types.PlayerData
	local data = DataSchema.Default()
	if type(raw) ~= "table" then
		return data
	end

	data.Cash = num(raw.Cash, data.Cash, 0)
	data.TotalEarned = num(raw.TotalEarned, 0, 0)
	data.Rebirths = math.floor(num(raw.Rebirths, 0, 0))
	data.Steals = math.floor(num(raw.Steals, 0, 0))
	data.TimesStolen = math.floor(num(raw.TimesStolen, 0, 0))
	data.DailyStreak = math.floor(num(raw.DailyStreak, 0, 0))
	data.DailyLast = num(raw.DailyLast, 0, 0)
	data.LastOnline = num(raw.LastOnline, 0, 0)
	data.FirstJoin = num(raw.FirstJoin, 0, 0)
	data.PlayTime = num(raw.PlayTime, 0, 0)
	data.Tutorial = math.floor(num(raw.Tutorial, 0, 0))
	data.GroupClaimed = raw.GroupClaimed == true
	data.Tools = boolMap(raw.Tools)
	data.Index = boolMap(raw.Index)
	data.Codes = boolMap(raw.Codes)

	if type(raw.Slots) == "table" then
		for key, slot in raw.Slots do
			local index = tonumber(key)
			if
				index
				and index >= 1
				and index <= Config.MaxSlots
				and index == math.floor(index)
				and type(slot) == "table"
				and validPlanet(slot.Id, slot.Mut)
			then
				data.Slots[tostring(index)] = {
					Id = slot.Id,
					Mut = slot.Mut,
					Acc = num(slot.Acc, 0, 0),
				}
			end
		end
	end

	if type(raw.Pending) == "table" then
		for _, item in raw.Pending do
			if type(item) == "table" and validPlanet(item.Id, item.Mut) and #data.Pending < Config.MaxPendingPlanets then
				table.insert(data.Pending, { Id = item.Id, Mut = item.Mut })
			end
		end
	end

	if type(raw.Receipts) == "table" then
		for _, receipt in raw.Receipts do
			if type(receipt) == "string" then
				table.insert(data.Receipts, receipt)
			end
		end
	end

	if type(raw.SessionJob) == "string" then
		data.SessionJob = raw.SessionJob
	end
	if isNumber(raw.SessionTime) then
		data.SessionTime = raw.SessionTime
	end

	return data
end

return DataSchema
