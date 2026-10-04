--!strict
-- Stealing and selling planets.
-- Steal: hold the prompt on a planet inside an UNLOCKED enemy base, carry it
-- (slower) to your own base. Getting hit, frozen, dying, touching that base's
-- laser or taking too long makes the planet fly back to its owner.
-- Sell: the owner holds the same prompt on their own planet.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Planets = require(Shared.Planets)

local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local StealService = {}

type Carry = {
	Thief: Player,
	Victim: Player,
	Plot: PlotService.PlotState,
	SlotIndex: number,
	Model: Model,
	Started: number,
	PlanetName: string,
	Rarity: string,
	LastPosition: Vector3,
	LastCheck: number,
}

local MAX_CARRY_SPEED = 90 -- studs per second (normal carrying speed is ~25)

local carrying: { [Player]: Carry } = {}
local lastSteal: { [Player]: number } = {}

function StealService.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

local function finish(thief: Player)
	carrying[thief] = nil
	PlotService.Reserve(thief, -1)
	CharacterService.SetCarrying(thief, false)
	if thief.Parent then
		Net.Effect(thief, "Carrying", { Active = false })
	end
end

-- Cancels a steal: the planet flies back to its owner's pedestal.
function StealService.Cancel(thief: Player, reason: string?)
	local state = carrying[thief]
	if not state then
		return
	end
	finish(thief)
	local core = state.Model.PrimaryPart
	local from = if core and state.Model.Parent then core.CFrame else nil
	PlotService.RestorePlanet(state.Plot, state.SlotIndex, from)
	if thief.Parent and reason then
		Net.Notify(thief, reason, "error")
	end
	if state.Victim.Parent then
		Net.Notify(state.Victim, "🛡️ Your " .. state.PlanetName .. " is back home!", "success")
	end
end

-- Called when a player gets hit / frozen.
function StealService.Drop(player: Player)
	if carrying[player] then
		StealService.Cancel(player, "💥 You dropped the planet!")
	end
end

local function complete(thief: Player)
	local state = carrying[thief]
	if not state then
		return
	end
	finish(thief)
	local victim = state.Victim
	local sd = PlotService.RemovePlanet(victim, state.SlotIndex)
	if not sd then
		return
	end
	-- the victim keeps the cash the planet had already produced
	if sd.Acc >= 1 then
		DataService.AddCash(victim, math.floor(sd.Acc))
	end
	PlotService.AddPlanet(thief, sd.Id, sd.Mut)

	local thiefData = DataService.Get(thief)
	if thiefData then
		thiefData.Steals += 1
	end
	local victimData = DataService.Get(victim)
	if victimData then
		victimData.TimesStolen += 1
	end
	DataService.MarkDirty(thief)
	DataService.MarkDirty(victim)

	Net.Notify(thief, "🦹 You stole " .. state.PlanetName .. " from " .. victim.DisplayName .. "!", "success")
	Net.Effect(thief, "Confetti", {})
	if victim.Parent then
		Net.Notify(victim, "😱 " .. thief.DisplayName .. " stole your " .. state.PlanetName .. "!", "error")
	end
	if Planets.RarityOrder(state.Rarity) >= 5 then
		Net.NotifyAll(
			"🚨 "
				.. thief.DisplayName
				.. " stole a "
				.. string.upper(state.Rarity)
				.. " "
				.. state.PlanetName
				.. " from "
				.. victim.DisplayName
				.. "!",
			"rare"
		)
	end
end

local function sell(player: Player, plot: PlotService.PlotState, slotIndex: number)
	local data = DataService.Get(player)
	local slot = plot.Slots[slotIndex]
	if not data or not slot or slot.Stealing then
		return
	end
	local sd = data.Slots[tostring(slotIndex)]
	local def = if sd then Planets.Get(sd.Id) else nil
	if not sd or not def then
		return
	end
	local value = Economy.SellValue(def, sd.Mut)
	local removed = PlotService.RemovePlanet(player, slotIndex)
	if not removed then
		return
	end
	DataService.AddCash(player, value + math.floor(removed.Acc))
	Net.Notify(player, "💸 Sold " .. def.Name .. " for " .. Format.Cash(value) .. "!", "success")
	Net.Effect(player, "CashPop", { Amount = value, Position = slot.Pad.Position })
end

local function steal(thief: Player, plot: PlotService.PlotState, slotIndex: number)
	local victim = plot.Owner
	if not victim or victim == thief then
		return
	end
	if carrying[thief] then
		Net.Notify(thief, "You are already carrying a planet!", "error")
		return
	end
	if PlotService.IsLocked(plot) then
		Net.Notify(thief, "🔒 This base is locked!", "error")
		return
	end
	local root = CharacterService.GetRoot(thief)
	if not root or not CharacterService.IsAlive(thief) then
		return
	end
	if not PlotService.IsInside(plot, root.Position) then
		return
	end
	if not PlotService.GetPlot(thief) then
		return
	end
	if PlotService.FreeSlots(thief) <= 0 then
		Net.Notify(thief, "Your base is full! Sell a planet or rebirth first.", "error")
		return
	end
	if os.clock() - (lastSteal[thief] or 0) < Config.StealCooldown then
		return
	end
	local slot = plot.Slots[slotIndex]
	local model = if slot then slot.Planet else nil
	if not slot or not model or slot.Stealing then
		return
	end
	local victimData = DataService.Get(victim)
	local sd = if victimData then victimData.Slots[tostring(slotIndex)] else nil
	local def = if sd then Planets.Get(sd.Id) else nil
	local core = model.PrimaryPart
	if not sd or not def or not core then
		return
	end

	lastSteal[thief] = os.clock()
	slot.Stealing = thief
	PlotService.Reserve(thief, 1)

	model:SetAttribute("SpinCF", nil)
	model:SetAttribute("Carried", true)
	local prompt = core:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end
	core.Anchored = false
	core.CFrame = root.CFrame * CFrame.new(0, 3.2 + def.Visual.Size / 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = core
	weld.Parent = core

	carrying[thief] = {
		Thief = thief,
		Victim = victim,
		Plot = plot,
		SlotIndex = slotIndex,
		Model = model,
		Started = os.clock(),
		PlanetName = def.Name,
		Rarity = def.Rarity,
		LastPosition = root.Position,
		LastCheck = os.clock(),
	}
	CharacterService.SetCarrying(thief, true)

	Net.Notify(thief, "🏃 You grabbed " .. def.Name .. "! Run back to YOUR base!", "success")
	Net.Effect(thief, "Carrying", { Active = true, Home = PlotService.HomePosition(thief) })
	Net.Effect(victim, "StealAlert", { Thief = thief.DisplayName, Planet = def.Name })
end

local function onPrompt(player: Player, plot: PlotService.PlotState, slotIndex: number)
	if plot.Owner == player then
		sell(player, plot, slotIndex)
	else
		steal(player, plot, slotIndex)
	end
end

local accumulator = 0
local function monitor(dt: number)
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0
	local toComplete: { Player } = {}
	local toCancel: { { player: Player, reason: string } } = {}
	for thief, state in carrying do
		local root = CharacterService.GetRoot(thief)
		if not thief.Parent then
			table.insert(toCancel, { player = thief, reason = "" })
		elseif not state.Victim.Parent or not state.Model.Parent then
			table.insert(toCancel, { player = thief, reason = "The planet vanished!" })
		elseif not root or not CharacterService.IsAlive(thief) then
			table.insert(toCancel, { player = thief, reason = "💀 You lost the planet!" })
		elseif os.clock() - state.Started > Config.StealTimeout then
			table.insert(toCancel, { player = thief, reason = "⌛ Too slow! The planet flew back." })
		else
			-- anti-teleport: carrying makes you slow, so big jumps mean exploits
			local now = os.clock()
			local moved = (root.Position - state.LastPosition).Magnitude
			local allowed = MAX_CARRY_SPEED * (now - state.LastCheck) + 6
			state.LastPosition = root.Position
			state.LastCheck = now
			local home = PlotService.GetPlot(thief)
			if moved > allowed then
				table.insert(toCancel, { player = thief, reason = "The planet slipped away!" })
			elseif home and PlotService.IsInside(home, root.Position) then
				table.insert(toComplete, thief)
			end
		end
	end
	for _, info in toCancel do
		StealService.Cancel(info.player, if info.reason ~= "" then info.reason else nil)
	end
	for _, thief in toComplete do
		complete(thief)
	end
end

-- Cancel everything that involves a player who is leaving (call before PlotService.Release).
function StealService.PlayerRemoving(player: Player)
	StealService.Cancel(player, nil)
	for thief, state in carrying do
		if state.Victim == player then
			StealService.Cancel(thief, "The owner left the game!")
		end
	end
	lastSteal[player] = nil
end

function StealService.Init()
	PlotService.PlanetPrompt:Connect(onPrompt)
	PlotService.Intruder:Connect(function(player: Player, plot: PlotService.PlotState)
		local state = carrying[player]
		if state and state.Plot == plot then
			StealService.Cancel(player, "🔒 The base locked! The planet flew back.")
		end
	end)
	CharacterService.Died:Connect(function(player: Player)
		if carrying[player] then
			StealService.Cancel(player, "💀 You lost the planet!")
		end
	end)
end

function StealService.Run()
	RunService.Heartbeat:Connect(monitor)
	Players.PlayerRemoving:Connect(function(player)
		lastSteal[player] = nil
	end)
end

return StealService
