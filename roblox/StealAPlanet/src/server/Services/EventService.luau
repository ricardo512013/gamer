--!strict
-- Cosmic events (server-wide weather) and Server Luck.
-- Global state is published as attributes on ReplicatedStorage so every client
-- can show banners/timers without extra remotes:
--   EventId, EventEndsAt, LuckMult, LuckEndsAt

local Lighting = game:GetService("Lighting")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local EventService = {}

local GLOBAL_TOPIC = "StealAPlanet_Global"

local current: Config.EventInfo? = nil
local eventToken = 0
local luckMult = 1
local luckEndsAt = 0
local visual: Instance? = nil

local baseAmbient = Lighting.Ambient
local baseOutdoor = Lighting.OutdoorAmbient

local function now(): number
	return Workspace:GetServerTimeNow()
end

function EventService.Get(id: string): Config.EventInfo?
	for _, info in Config.Events do
		if info.Id == id then
			return info
		end
	end
	return nil
end

local function tweenLighting(color: Color3?)
	local info = TweenInfo.new(3, Enum.EasingStyle.Sine)
	local ambient = if color then baseAmbient:Lerp(color, 0.45) else baseAmbient
	local outdoor = if color then baseOutdoor:Lerp(color, 0.45) else baseOutdoor
	TweenService:Create(Lighting, info, { Ambient = ambient, OutdoorAmbient = outdoor }):Play()
	local correction = Lighting:FindFirstChild("SAP_ColorCorrection")
	if correction and correction:IsA("ColorCorrectionEffect") then
		local tint = if color then Color3.fromRGB(255, 255, 255):Lerp(color, 0.25) else Color3.fromRGB(255, 255, 255)
		TweenService:Create(correction, info, { TintColor = tint }):Play()
	end
end

local function clearVisual()
	local old = visual
	if old then
		old:Destroy()
		visual = nil
	end
end

local function createBlackHoleVisual()
	clearVisual()
	local model = Instance.new("Model")
	model.Name = "EventBlackHole"
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(60, 60, 60)
	core.Color = Color3.fromRGB(0, 0, 0)
	core.Material = Enum.Material.Neon
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.CFrame = CFrame.new(0, 150, 0)
	core.Parent = model
	type RingInfo = { diameter: number, color: Color3, transparency: number }
	local rings: { RingInfo } = {
		{ diameter = 150, color = Color3.fromRGB(255, 140, 40), transparency = 0.15 },
		{ diameter = 105, color = Color3.fromRGB(255, 230, 180), transparency = 0.35 },
	}
	for i, info in rings do
		local ring = Instance.new("Part")
		ring.Name = "Ring" .. i
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(1, info.diameter, info.diameter)
		ring.Color = info.color
		ring.Transparency = info.transparency
		ring.Material = Enum.Material.Neon
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.CFrame = CFrame.new(0, 150, 0) * CFrame.Angles(math.rad(15), 0, math.rad(90))
		ring.Parent = model
	end
	model.Parent = Workspace
	visual = model
end

function EventService.Stop()
	eventToken += 1
	if current then
		Net.NotifyAll(current.Icon .. " " .. current.Name .. " has ended.", "info")
	end
	current = nil
	ReplicatedStorage:SetAttribute("EventId", "")
	ReplicatedStorage:SetAttribute("EventEndsAt", 0)
	clearVisual()
	tweenLighting(nil)
end

function EventService.Start(id: string, duration: number?, startedBy: string?)
	local info = EventService.Get(id)
	if not info then
		return
	end
	local length = duration or Config.EventDuration
	eventToken += 1
	local token = eventToken
	current = info
	ReplicatedStorage:SetAttribute("EventId", info.Id)
	ReplicatedStorage:SetAttribute("EventEndsAt", now() + length)
	tweenLighting(info.Color)
	if info.Id == "BlackHole" then
		createBlackHoleVisual()
	else
		clearVisual()
	end
	local by = if startedBy then " (thanks " .. startedBy .. "!)" else ""
	Net.NotifyAll(info.Icon .. " " .. string.upper(info.Name) .. "! " .. info.Description .. by, "event")
	task.delay(length, function()
		if eventToken == token then
			EventService.Stop()
		end
	end)
end

function EventService.StartRandom(startedBy: string?)
	local info = Config.Events[math.random(1, #Config.Events)]
	EventService.Start(info.Id, nil, startedBy)
end

function EventService.CurrentId(): string?
	local info = current
	return if info then info.Id else nil
end

function EventService.GetLuck(): number
	local luck = if now() < luckEndsAt then luckMult else 1
	local info = current
	if info and info.LuckMult then
		luck *= info.LuckMult
	end
	return luck
end

function EventService.GetMutationMultipliers(): { [string]: number }?
	local info = current
	return if info then info.MutationMult else nil
end

function EventService.GetIncomeMultiplier(): number
	local info = current
	return if info and info.IncomeMult then info.IncomeMult else 1
end

local function publishLuck()
	ReplicatedStorage:SetAttribute("LuckMult", if now() < luckEndsAt then luckMult else 1)
	ReplicatedStorage:SetAttribute("LuckEndsAt", luckEndsAt)
end

-- Adds Server Luck time (purchases stack time). mult can be raised by admins.
function EventService.AddLuck(seconds: number, mult: number?, boughtBy: string?)
	local t = now()
	local active = luckEndsAt > t
	local base = if active then luckEndsAt else t
	luckEndsAt = math.min(base + seconds, t + Config.ServerLuck.MaxDuration)
	luckMult = math.max(if active then luckMult else 1, mult or Config.ServerLuck.Multiplier)
	publishLuck()
	if boughtBy then
		Net.NotifyAll("🍀 " .. boughtBy .. " bought SERVER LUCK x" .. luckMult .. " for everyone!", "rare")
	else
		Net.NotifyAll("🍀 SERVER LUCK x" .. luckMult .. " is active!", "rare")
	end
end

-- Admin: start an event on every server.
function EventService.StartGlobal(id: string)
	local ok, err = pcall(function()
		MessagingService:PublishAsync(GLOBAL_TOPIC, { Type = "Event", Id = id })
	end)
	if not ok then
		warn("[EventService] global publish failed: " .. tostring(err))
		EventService.Start(id, nil, "Admin")
	end
end

function EventService.Init()
	ReplicatedStorage:SetAttribute("EventId", "")
	ReplicatedStorage:SetAttribute("EventEndsAt", 0)
	ReplicatedStorage:SetAttribute("LuckMult", 1)
	ReplicatedStorage:SetAttribute("LuckEndsAt", 0)
	baseAmbient = Lighting.Ambient
	baseOutdoor = Lighting.OutdoorAmbient
end

function EventService.Run()
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(GLOBAL_TOPIC, function(message)
				local payload = message.Data
				if type(payload) == "table" and payload.Type == "Event" and type(payload.Id) == "string" then
					EventService.Start(payload.Id, nil, "Admin")
				end
			end)
		end)
		if not ok then
			warn("[EventService] MessagingService unavailable: " .. tostring(err))
		end
	end)

	task.spawn(function()
		task.wait(Config.EventFirstDelay)
		while true do
			if not current then
				EventService.StartRandom(nil)
			end
			task.wait(Config.EventDuration + Config.EventInterval)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(5)
			if luckEndsAt > 0 and now() >= luckEndsAt then
				luckEndsAt = 0
				luckMult = 1
				publishLuck()
			end
		end
	end)
end

return EventService
