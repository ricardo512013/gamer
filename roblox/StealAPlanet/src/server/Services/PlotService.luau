--!strict
-- Player bases: plot assignment, planet slots, income, collecting, lock/laser,
-- storage for planets that do not fit, and the planet index (collection book).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Mutations = require(Shared.Mutations)
local Net = require(Shared.Net)
local PlanetModel = require(Shared.PlanetModel)
local Planets = require(Shared.Planets)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local MapBuilder = require(script.Parent.MapBuilder)

export type SlotState = {
	Index: number,
	Pedestal: BasePart,
	Pad: BasePart,
	Anchor: CFrame,
	AccLabel: TextLabel,
	LockedGui: BillboardGui,
	LockedLabel: TextLabel,
	Planet: Model?,
	Stealing: Player?,
	LastCollect: number,
}

export type PlotState = {
	Index: number,
	Model: Model,
	Frame: CFrame,
	Owner: Player?,
	Slots: { SlotState },
	Laser: BasePart,
	LockPad: BasePart,
	Spawn: BasePart,
	SignLabel: TextLabel,
	SignLabelInner: TextLabel,
	LockLabel: TextLabel,
	PlanetsFolder: Folder,
	LockedUntil: number,
	LastLockText: string,
}

local PlotService = {}

PlotService.PlanetPrompt = Signal.new() -- (player, plot, slotIndex)
PlotService.Intruder = Signal.new() -- (player, plot) touched a locked laser

local plots: { PlotState } = {}
local plotOf: { [Player]: PlotState } = {}
local reserved: { [Player]: number } = {}
local cashPerSec: { [Player]: number } = {}
local lastAutoCollect: { [Player]: number } = {}
local laserDebounce: { [Player]: number } = {}

local OPEN_COLOR = Color3.fromRGB(140, 255, 160)
local LOCKED_COLOR = Color3.fromRGB(255, 110, 110)

local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function child<T>(parent: Instance, name: string): T
	return (parent:WaitForChild(name, 30) :: any) :: T
end

function PlotService.GetPlot(player: Player): PlotState?
	return plotOf[player]
end

function PlotService.GetPlots(): { PlotState }
	return plots
end

function PlotService.IsLocked(plot: PlotState): boolean
	return os.clock() < plot.LockedUntil
end

function PlotService.LockRemaining(plot: PlotState): number
	return math.max(0, plot.LockedUntil - os.clock())
end

function PlotService.IsInside(plot: PlotState, position: Vector3): boolean
	local p = plot.Frame:PointToObjectSpace(position)
	return math.abs(p.X) <= 32.5 and math.abs(p.Z) <= 30.5 and p.Y > -4 and p.Y < 40
end

function PlotService.SpawnCFrame(player: Player): CFrame?
	local plot = plotOf[player]
	if not plot then
		return nil
	end
	local position = plot.Spawn.Position + Vector3.new(0, 3.5, 0)
	return CFrame.lookAt(position, position - plot.Frame.LookVector)
end

function PlotService.HomePosition(player: Player): Vector3?
	local plot = plotOf[player]
	return if plot then plot.Spawn.Position else nil
end

local function getUnlocked(player: Player): number
	local data = DataService.Get(player)
	return Economy.UnlockedSlots(if data then data.Rebirths else 0)
end

function PlotService.UnlockedSlots(player: Player): number
	return getUnlocked(player)
end

local function findFreeSlot(player: Player): SlotState?
	local plot = plotOf[player]
	local data = DataService.Get(player)
	if not plot or not data then
		return nil
	end
	local unlocked = getUnlocked(player)
	for i = 1, unlocked do
		local slot = plot.Slots[i]
		if slot and data.Slots[tostring(i)] == nil and slot.Planet == nil then
			return slot
		end
	end
	return nil
end

-- Empty unlocked slots minus slots reserved by planets being carried home.
function PlotService.FreeSlots(player: Player): number
	local plot = plotOf[player]
	local data = DataService.Get(player)
	if not plot or not data then
		return 0
	end
	local free = 0
	for i = 1, getUnlocked(player) do
		local slot = plot.Slots[i]
		if slot and data.Slots[tostring(i)] == nil and slot.Planet == nil then
			free += 1
		end
	end
	return free - (reserved[player] or 0)
end

function PlotService.UsedSlots(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 0
	end
	local used = 0
	for _ in data.Slots do
		used += 1
	end
	return used
end

function PlotService.Reserve(player: Player, delta: number)
	reserved[player] = math.max(0, (reserved[player] or 0) + delta)
end

function PlotService.Multiplier(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return 1
	end
	local friendBoost = player:GetAttribute("FriendBoost")
	return Economy.Multiplier({
		Rebirths = data.Rebirths,
		VIP = player:GetAttribute("Pass_VIP") == true,
		DoubleCash = player:GetAttribute("Pass_DoubleCash") == true,
		IndexBonus = Economy.IndexBonus(data.Index),
		FriendBonus = if type(friendBoost) == "number" then friendBoost else 0,
		GroupBonus = if player:GetAttribute("InGroup") == true then Config.GroupBonus else 0,
		EventMult = EventService.GetIncomeMultiplier(),
	})
end

local function computeCashPerSec(player: Player): number
	local data = DataService.Get(player)
	local plot = plotOf[player]
	if not data or not plot then
		return 0
	end
	local mult = PlotService.Multiplier(player)
	local total = 0
	for key, sd in data.Slots do
		local slot = plot.Slots[tonumber(key) or 0]
		local def = Planets.Get(sd.Id)
		if def and slot and not slot.Stealing then
			total += Economy.PlanetIncome(def, sd.Mut) * mult
		end
	end
	return total
end

function PlotService.CashPerSec(player: Player): number
	return cashPerSec[player] or computeCashPerSec(player)
end

local function discover(player: Player, data: Types.PlayerData, id: string, mutation: string)
	local def = Planets.Get(id)
	if not def then
		return
	end
	local changed = false
	if not data.Index[id] then
		data.Index[id] = true
		changed = true
		Net.Notify(player, "📖 New planet discovered: " .. def.Name .. "! (+1% cash)", "success")
	end
	if mutation ~= "None" then
		local variant = id .. ":" .. mutation
		if not data.Index[variant] then
			data.Index[variant] = true
			changed = true
			Net.Notify(player, "📖 New variant: " .. Mutations.Get(mutation).Name .. " " .. def.Name .. "! (+0.5% cash)", "success")
		end
	end
	if changed then
		local version = player:GetAttribute("IndexVersion")
		player:SetAttribute("IndexVersion", (if type(version) == "number" then version else 0) + 1)
	end
end

local function slotTarget(slot: SlotState, def: Planets.PlanetDef): CFrame
	return slot.Anchor * CFrame.new(0, def.Visual.Size / 2 + 1.4, 0)
end

local function spawnModel(plot: PlotState, slot: SlotState, sd: Types.SlotData, from: CFrame?)
	local def = Planets.Get(sd.Id)
	local owner = plot.Owner
	if not def or not owner then
		return
	end
	local old = slot.Planet
	if old then
		old:Destroy()
	end
	local target = slotTarget(slot, def)
	local model = PlanetModel.Build(def.Id, sd.Mut, from or target)
	model:SetAttribute("Mode", "Base")
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("PlotIndex", plot.Index)
	model:SetAttribute("SlotIndex", slot.Index)
	model:SetAttribute("SellValue", Economy.SellValue(def, sd.Mut))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local core = model.PrimaryPart :: BasePart

	local tag = PlanetModel.CreateTag(def.Id, sd.Mut, "Base")
	tag.Parent = core

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlanetPrompt"
	prompt.ActionText = "Steal"
	prompt.ObjectText = def.Name
	prompt.HoldDuration = Config.StealHoldTime
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = core
	local slotIndex = slot.Index
	prompt.Triggered:Connect(function(who: Player)
		PlotService.PlanetPrompt:Fire(who, plot, slotIndex)
	end)

	model.Parent = plot.PlanetsFolder
	CollectionService:AddTag(model, "Planet")
	slot.Planet = model

	if from then
		local tween = TweenService:Create(
			core,
			TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = target }
		)
		tween.Completed:Connect(function()
			if slot.Planet == model and model.Parent and core.Anchored then
				model:SetAttribute("SpinCF", target)
			end
		end)
		tween:Play()
	else
		model:SetAttribute("SpinCF", target)
	end
end

local function placePending(player: Player)
	local data = DataService.Get(player)
	local plot = plotOf[player]
	if not data or not plot then
		return
	end
	while #data.Pending > 0 do
		local slot = findFreeSlot(player)
		if not slot then
			break
		end
		local item = table.remove(data.Pending, 1) :: Types.PendingPlanet
		local sd: Types.SlotData = { Id = item.Id, Mut = item.Mut, Acc = 0 }
		data.Slots[tostring(slot.Index)] = sd
		spawnModel(plot, slot, sd, nil)
	end
	DataService.MarkDirty(player)
end

-- Gives a planet to a player. Returns the slot index, or nil if it went to storage.
function PlotService.AddPlanet(player: Player, id: string, mutation: string, from: CFrame?): number?
	local data = DataService.Get(player)
	local def = Planets.Get(id)
	if not data or not def then
		return nil
	end
	if not Mutations.IsValid(mutation) then
		mutation = "None"
	end
	discover(player, data, id, mutation)
	DataService.MarkDirty(player)

	local plot = plotOf[player]
	local slot = findFreeSlot(player)
	if not plot or not slot then
		if #data.Pending < Config.MaxPendingPlanets then
			table.insert(data.Pending, { Id = id, Mut = mutation })
			Net.Notify(player, "📦 Base full! " .. def.Name .. " was sent to storage. Free a slot to place it.", "info")
		else
			Net.Notify(player, "Storage is full! Sell planets to make room.", "error")
		end
		return nil
	end
	local sd: Types.SlotData = { Id = id, Mut = mutation, Acc = 0 }
	data.Slots[tostring(slot.Index)] = sd
	spawnModel(plot, slot, sd, from)
	return slot.Index
end

-- Removes a planet from a player's base and returns its data.
function PlotService.RemovePlanet(player: Player, slotIndex: number): Types.SlotData?
	local data = DataService.Get(player)
	local plot = plotOf[player]
	if not data or not plot then
		return nil
	end
	local key = tostring(slotIndex)
	local sd = data.Slots[key]
	if not sd then
		return nil
	end
	data.Slots[key] = nil
	local slot = plot.Slots[slotIndex]
	if slot then
		local model = slot.Planet
		if model then
			model:Destroy()
		end
		slot.Planet = nil
		slot.Stealing = nil
		slot.AccLabel.Text = ""
	end
	placePending(player)
	DataService.MarkDirty(player)
	return sd
end

-- Puts a planet back on its pedestal (used when a steal is cancelled).
function PlotService.RestorePlanet(plot: PlotState, slotIndex: number, from: CFrame?)
	local slot = plot.Slots[slotIndex]
	if not slot then
		return
	end
	slot.Stealing = nil
	local owner = plot.Owner
	local data = if owner then DataService.Get(owner) else nil
	local sd = if data then data.Slots[tostring(slotIndex)] else nil
	if sd then
		spawnModel(plot, slot, sd, from)
	else
		local model = slot.Planet
		if model then
			model:Destroy()
		end
		slot.Planet = nil
	end
end

function PlotService.ClearAll(player: Player)
	local data = DataService.Get(player)
	local plot = plotOf[player]
	if not data or not plot then
		return
	end
	table.clear(data.Slots)
	table.clear(data.Pending)
	for _, slot in plot.Slots do
		local model = slot.Planet
		if model then
			model:Destroy()
		end
		slot.Planet = nil
		slot.Stealing = nil
		slot.AccLabel.Text = ""
	end
	DataService.MarkDirty(player)
end

function PlotService.Collect(player: Player, slotIndex: number, silent: boolean?): number
	local data = DataService.Get(player)
	local plot = plotOf[player]
	if not data or not plot then
		return 0
	end
	local slot = plot.Slots[slotIndex]
	local sd = data.Slots[tostring(slotIndex)]
	if not slot or not sd or sd.Acc < 1 then
		return 0
	end
	if not silent and os.clock() - slot.LastCollect < 0.25 then
		return 0
	end
	slot.LastCollect = os.clock()
	local amount = math.floor(sd.Acc)
	sd.Acc -= amount
	DataService.AddCash(player, amount)
	slot.AccLabel.Text = ""
	if not silent then
		Net.Effect(player, "CashPop", { Amount = amount, Position = slot.Pad.Position })
	end
	if data.Tutorial == 1 then
		data.Tutorial = 2
	end
	return amount
end

function PlotService.CollectAll(player: Player): number
	local plot = plotOf[player]
	if not plot then
		return 0
	end
	local total = 0
	for _, slot in plot.Slots do
		total += PlotService.Collect(player, slot.Index, true)
	end
	return total
end

local function updateLockVisual(plot: PlotState)
	local locked = PlotService.IsLocked(plot)
	if plot.Model:GetAttribute("Locked") ~= locked then
		plot.Model:SetAttribute("Locked", locked)
	end
	plot.Laser.Transparency = if locked then 0.35 else 1
	local text: string
	if not plot.Owner then
		text = ""
	elseif locked then
		text = "🔒 LOCKED " .. math.ceil(PlotService.LockRemaining(plot)) .. "s"
	else
		text = "🔓 OPEN"
	end
	if text ~= plot.LastLockText then
		plot.LastLockText = text
		plot.LockLabel.Text = text
		plot.LockLabel.TextColor3 = if locked then LOCKED_COLOR else OPEN_COLOR
	end
end

-- Locks the player's base. force = extend even if already locked (Remote Lock product).
function PlotService.Lock(player: Player, force: boolean?): boolean
	local plot = plotOf[player]
	local data = DataService.Get(player)
	if not plot or not data then
		return false
	end
	if PlotService.IsLocked(plot) and not force then
		return false
	end
	local duration = Economy.LockDuration(data.Rebirths, player:GetAttribute("Pass_DoubleLock") == true)
	plot.LockedUntil = math.max(plot.LockedUntil, os.clock() + duration)
	updateLockVisual(plot)
	Net.Notify(player, "🔒 Base locked for " .. math.ceil(PlotService.LockRemaining(plot)) .. " seconds!", "success")
	return true
end

function PlotService.RefreshSlotLocks(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	local unlocked = getUnlocked(player)
	for _, slot in plot.Slots do
		local locked = slot.Index > unlocked
		slot.LockedGui.Enabled = locked
		slot.LockedLabel.Text = "🔒 Rebirth " .. Economy.SlotRebirthRequirement(slot.Index)
		slot.Pedestal.Transparency = if locked then 0.6 else 0
		slot.Pad.Transparency = if locked then 0.85 else 0.15
	end
	placePending(player)
end

function PlotService.Assign(player: Player): PlotState?
	for _, plot in plots do
		if not plot.Owner then
			plot.Owner = player
			plotOf[player] = plot
			reserved[player] = 0
			plot.LockedUntil = os.clock() + Config.JoinLockDuration
			plot.SignLabel.Text = player.DisplayName .. "'s Base"
			plot.SignLabelInner.Text = player.DisplayName .. "'s Base"
			plot.Model:SetAttribute("OwnerUserId", player.UserId)
			player:SetAttribute("PlotIndex", plot.Index)
			PlotService.RefreshSlotLocks(player)

			local data = DataService.Get(player)
			if data then
				for key, sd in data.Slots do
					local slot = plot.Slots[tonumber(key) or 0]
					if slot then
						spawnModel(plot, slot, sd, nil)
					end
				end
			end
			placePending(player)
			updateLockVisual(plot)
			CharacterService.TeleportHome(player)
			return plot
		end
	end
	return nil
end

function PlotService.Release(player: Player)
	local plot = plotOf[player]
	plotOf[player] = nil
	reserved[player] = nil
	cashPerSec[player] = nil
	lastAutoCollect[player] = nil
	laserDebounce[player] = nil
	if not plot then
		return
	end
	plot.Owner = nil
	plot.LockedUntil = 0
	plot.Model:SetAttribute("OwnerUserId", nil)
	plot.SignLabel.Text = "EMPTY BASE"
	plot.SignLabelInner.Text = "EMPTY BASE"
	for _, slot in plot.Slots do
		local model = slot.Planet
		if model then
			model:Destroy()
		end
		slot.Planet = nil
		slot.Stealing = nil
		slot.AccLabel.Text = ""
		slot.LockedGui.Enabled = false
		slot.Pedestal.Transparency = 0
		slot.Pad.Transparency = 0.15
	end
	for _, leftover in plot.PlanetsFolder:GetChildren() do
		leftover:Destroy()
	end
	updateLockVisual(plot)
end

-- Adds offline earnings to every slot. Returns (total, seconds).
function PlotService.ApplyOffline(player: Player): (number, number)
	local data = DataService.Get(player)
	if not data then
		return 0, 0
	end
	local cap = if player:GetAttribute("Pass_OfflineEarnings") == true
		then Config.OfflineCapHoursPass
		else Config.OfflineCapHours
	local seconds = Economy.OfflineSeconds(data.LastOnline, os.time(), cap)
	if seconds < 60 then
		return 0, 0
	end
	local mult = PlotService.Multiplier(player)
	local total = 0
	for _, sd in data.Slots do
		local def = Planets.Get(sd.Id)
		if def then
			local earned = Economy.PlanetIncome(def, sd.Mut) * mult * seconds
			sd.Acc += earned
			total += earned
		end
	end
	return total, seconds
end

local function incomeTick()
	for _, plot in plots do
		local owner = plot.Owner
		local data = if owner then DataService.Get(owner) else nil
		if owner and data then
			local mult = PlotService.Multiplier(owner)
			local total = 0
			for _, slot in plot.Slots do
				local sd = data.Slots[tostring(slot.Index)]
				if sd then
					local def = Planets.Get(sd.Id)
					if def and not slot.Stealing then
						local income = Economy.PlanetIncome(def, sd.Mut) * mult
						sd.Acc += income
						total += income
					end
					local text = if sd.Acc >= 1 then Format.Cash(sd.Acc) else ""
					if slot.AccLabel.Text ~= text then
						slot.AccLabel.Text = text
					end
				end
			end
			cashPerSec[owner] = total
			if
				owner:GetAttribute("Pass_AutoCollect") == true
				and os.clock() - (lastAutoCollect[owner] or 0) >= Config.AutoCollectInterval
			then
				lastAutoCollect[owner] = os.clock()
				PlotService.CollectAll(owner)
			end
		end
	end
end

function PlotService.Init(map: Instance)
	local plotsFolder = child(map, "Plots") :: Instance
	for i = 1, MapBuilder.PLOT_COUNT do
		local model = child(plotsFolder, "Plot" .. i) :: Model
		local floor = child(model, "Floor") :: BasePart
		local sign = child(model, "Sign") :: BasePart
		local slotsFolder = child(model, "Slots") :: Instance
		local planetsFolder = model:FindFirstChild("Planets")
		if not (planetsFolder and planetsFolder:IsA("Folder")) then
			local folder = Instance.new("Folder")
			folder.Name = "Planets"
			folder.Parent = model
			planetsFolder = folder
		end
		local frame = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)

		local plot: PlotState = {
			Index = i,
			Model = model,
			Frame = frame,
			Owner = nil,
			Slots = {},
			Laser = child(model, "Laser") :: BasePart,
			LockPad = child(model, "LockPad") :: BasePart,
			Spawn = child(model, "Spawn") :: BasePart,
			SignLabel = child(child(sign, "SignLabelGui"), "SignLabel") :: TextLabel,
			SignLabelInner = child(child(sign, "SignLabelInnerGui"), "SignLabelInner") :: TextLabel,
			LockLabel = child(child(sign, "LockLabelGui"), "LockLabel") :: TextLabel,
			PlanetsFolder = planetsFolder :: Folder,
			LockedUntil = 0,
			LastLockText = "?",
		}

		for s = 1, Config.MaxSlots do
			local slotModel = child(slotsFolder, "Slot" .. s) :: Instance
			local pedestal = child(slotModel, "Pedestal") :: BasePart
			local pad = child(slotModel, "CollectPad") :: BasePart
			local lockedGui = child(pedestal, "LockedGui") :: BillboardGui
			local top = pedestal.Position + Vector3.new(0, pedestal.Size.X / 2, 0)
			local slot: SlotState = {
				Index = s,
				Pedestal = pedestal,
				Pad = pad,
				Anchor = CFrame.new(top) * frame.Rotation,
				AccLabel = child(child(pad, "AmountGui"), "Amount") :: TextLabel,
				LockedGui = lockedGui,
				LockedLabel = child(lockedGui, "Locked") :: TextLabel,
				Planet = nil,
				Stealing = nil,
				LastCollect = 0,
			}
			plot.Slots[s] = slot
			pad.Touched:Connect(function(hit: BasePart)
				local player = playerFromHit(hit)
				if player and plot.Owner == player then
					PlotService.Collect(player, s)
				end
			end)
		end

		plot.LockPad.Touched:Connect(function(hit: BasePart)
			local player = playerFromHit(hit)
			if player and plot.Owner == player then
				PlotService.Lock(player)
			end
		end)

		plot.Laser.Touched:Connect(function(hit: BasePart)
			local player = playerFromHit(hit)
			if not player or player == plot.Owner or not PlotService.IsLocked(plot) then
				return
			end
			local last = laserDebounce[player] or 0
			if os.clock() - last < 0.4 then
				return
			end
			laserDebounce[player] = os.clock()
			PlotService.Intruder:Fire(player, plot)
			Net.Effect(player, "Knockback", { Direction = plot.Frame.LookVector, Power = 70, Duration = 0 })
		end)

		table.insert(plots, plot)
		updateLockVisual(plot)
	end
end

function PlotService.Run()
	task.spawn(function()
		while true do
			task.wait(1)
			incomeTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, plot in plots do
				updateLockVisual(plot)
			end
		end
	end)
end

return PlotService
