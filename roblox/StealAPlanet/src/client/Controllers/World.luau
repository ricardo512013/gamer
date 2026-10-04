--!strict
-- World-side visuals and server effects:
-- * planets float/sway on their pedestals, rainbow planets cycle colors
-- * Steal/Sell prompt text depending on who owns the planet
-- * guide beam (tutorial + "bring it home" when carrying)
-- * knockback, swing/hit sounds, freeze beam, meteors during Meteor Shower
-- * stall prompts open menus, favorite prompt after a few minutes

local AvatarEditorService = game:GetService("AvatarEditorService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)
local Effects = require(script.Parent.Parent.UI.Effects)
local Panels = require(script.Parent.Parent.UI.Panels)

local World = {}

local player = Players.LocalPlayer

type Tracked = {
	Model: Model,
	Core: BasePart,
	Phase: number,
	Rainbow: { BasePart }?,
}

local tracked: { [Model]: Tracked } = {}
local carrying = false
local carryHome: Vector3? = nil

local function getRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function setupPrompt(model: Model)
	local core = model.PrimaryPart
	if not core then
		return
	end
	local prompt = core:FindFirstChild("PlanetPrompt")
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		return
	end
	if model:GetAttribute("OwnerUserId") == player.UserId then
		local value = model:GetAttribute("SellValue")
		prompt.ActionText = "Sell " .. Format.Cash(if type(value) == "number" then value else 0)
		prompt.HoldDuration = Config.SellHoldTime
	else
		prompt.ActionText = "Steal"
		prompt.HoldDuration = Config.StealHoldTime
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or tracked[instance] then
		return
	end
	local core = instance.PrimaryPart
	if not core then
		local found = instance:WaitForChild("Core", 5)
		if found and found:IsA("BasePart") then
			core = found
		end
	end
	if not core then
		return
	end
	local rainbow: { BasePart }? = nil
	if instance:GetAttribute("Rainbow") == true then
		local parts: { BasePart } = {}
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("BasePart") and descendant:GetAttribute("Body") == true then
				table.insert(parts, descendant)
			end
		end
		rainbow = parts
	end
	tracked[instance] = { Model = instance, Core = core, Phase = math.random() * 10, Rainbow = rainbow }
	setupPrompt(instance)
	instance:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		setupPrompt(instance)
	end)
end

local function untrack(instance: Instance)
	if instance:IsA("Model") then
		tracked[instance] = nil
	end
end

local function animate()
	local t = os.clock()
	local camera = Workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	for model, entry in tracked do
		if not model.Parent then
			tracked[model] = nil
			continue
		end
		local spin = model:GetAttribute("SpinCF")
		if typeof(spin) == "CFrame" and entry.Core.Anchored and (spin.Position - cameraPosition).Magnitude < 220 then
			entry.Core.CFrame = spin
				* CFrame.new(0, math.sin(t * 2 + entry.Phase) * 0.3, 0)
				* CFrame.Angles(0, math.sin(t * 0.9 + entry.Phase) * 0.5, 0)
		end
		local rainbow = entry.Rainbow
		if rainbow and (entry.Core.Position - cameraPosition).Magnitude < 200 then
			for i, part in rainbow do
				part.Color = Color3.fromHSV((t * 0.25 + i * 0.07) % 1, 0.65, 1)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Guide beam (tutorial / carrying)
---------------------------------------------------------------------------
local guidePart: Part? = nil
local guideBeam: Beam? = nil
local rootAttachment: Attachment? = nil

local function ensureGuide(root: BasePart): (Part, Beam)
	local part = guidePart
	local beam = guideBeam
	if part and beam and part.Parent and rootAttachment and rootAttachment.Parent == root then
		return part, beam
	end
	if part then
		part:Destroy()
	end
	local newPart = Instance.new("Part")
	newPart.Name = "GuideTarget"
	newPart.Anchored = true
	newPart.CanCollide = false
	newPart.CanQuery = false
	newPart.CanTouch = false
	newPart.Transparency = 1
	newPart.Size = Vector3.new(1, 1, 1)
	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = newPart
	local attachment = Instance.new("Attachment")
	attachment.Name = "GuideAttachment"
	attachment.Parent = root
	rootAttachment = attachment
	local newBeam = Instance.new("Beam")
	newBeam.Attachment0 = attachment
	newBeam.Attachment1 = targetAttachment
	newBeam.Width0 = 1
	newBeam.Width1 = 1
	newBeam.FaceCamera = true
	newBeam.LightEmission = 1
	newBeam.Segments = 1
	newBeam.Transparency = NumberSequence.new(0.25)
	newBeam.Parent = newPart
	newPart.Parent = Workspace
	guidePart = newPart
	guideBeam = newBeam
	return newPart, newBeam
end

local function updateGuide()
	local root = getRoot()
	local data = State.Data
	local target: Vector3? = nil
	local color = Color3.fromRGB(255, 210, 70)
	if root and data then
		if carrying and carryHome then
			target = carryHome
			color = Color3.fromRGB(90, 255, 120)
		elseif data.Tutorial == 0 then
			target = Vector3.new(math.clamp(root.Position.X, -150, 150), 3, 0)
		elseif data.Tutorial == 1 then
			target = data.HomePosition
		end
	end
	if root and target and (target - root.Position).Magnitude > 8 then
		local part, beam = ensureGuide(root)
		part.CFrame = CFrame.new(target + Vector3.new(0, 2, 0))
		beam.Color = ColorSequence.new(color)
		beam.Enabled = true
	else
		local beam = guideBeam
		if beam then
			beam.Enabled = false
		end
	end
end

---------------------------------------------------------------------------
-- Effects from the server
---------------------------------------------------------------------------
local function knockback(payload: { [string]: any })
	local character = player.Character
	local root = getRoot()
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local direction = payload.Direction
	local power = payload.Power
	local duration = payload.Duration
	if not root or not humanoid or typeof(direction) ~= "Vector3" or type(power) ~= "number" then
		return
	end
	if direction.Magnitude < 0.01 then
		return
	end
	root.AssemblyLinearVelocity = direction.Unit * power + Vector3.new(0, power * 0.45, 0)
	if type(duration) == "number" and duration > 0 then
		humanoid.PlatformStand = true
		task.delay(duration, function()
			if humanoid.Parent then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
end

local function flash(position: Vector3, color: Color3, size: number)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(position)
	part.Parent = Workspace
	local tween = TweenService:Create(part, TweenInfo.new(0.35), { Size = Vector3.new(size, size, size), Transparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

local function freezeBeam(from: Vector3, to: Vector3)
	local distance = (to - from).Magnitude
	if distance < 0.1 then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(120, 230, 255)
	part.Size = Vector3.new(0.5, 0.5, distance)
	part.CFrame = CFrame.lookAt((from + to) / 2, to)
	part.Parent = Workspace
	local tween = TweenService:Create(part, TweenInfo.new(0.5), { Transparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
	flash(to, Color3.fromRGB(160, 240, 255), 8)
end

local function onEffect(name: string, payload: { [string]: any })
	if name == "Knockback" then
		knockback(payload)
	elseif name == "CashPop" then
		if type(payload.Amount) == "number" and typeof(payload.Position) == "Vector3" then
			Effects.CashPop(payload.Amount, payload.Position)
		end
	elseif name == "StealAlert" then
		Effects.StealAlert(tostring(payload.Thief), tostring(payload.Planet))
	elseif name == "Carrying" then
		carrying = payload.Active == true
		carryHome = if typeof(payload.Home) == "Vector3" then payload.Home else nil
		Effects.SetCarrying(carrying)
	elseif name == "Confetti" then
		Effects.Confetti()
	elseif name == "Swing" then
		if typeof(payload.Position) == "Vector3" then
			Sound.PlayAt("Swing", payload.Position)
		end
	elseif name == "Hit" then
		if typeof(payload.Position) == "Vector3" then
			flash(payload.Position, Color3.fromRGB(255, 230, 120), 6)
		end
	elseif name == "FreezeBeam" then
		if typeof(payload.From) == "Vector3" and typeof(payload.To) == "Vector3" then
			freezeBeam(payload.From, payload.To)
		end
	elseif name == "Welcome" then
		if type(payload.Amount) == "number" and type(payload.Seconds) == "number" then
			Effects.Welcome(payload.Amount, payload.Seconds)
		end
	end
end

---------------------------------------------------------------------------
-- Meteor shower visuals
---------------------------------------------------------------------------
local meteorCount = 0
local function spawnMeteor()
	if meteorCount >= 18 then
		return
	end
	meteorCount += 1
	local target = Vector3.new(math.random(-200, 200), 0, math.random(-150, 150))
	local start = target + Vector3.new(math.random(-60, 60), 220, math.random(-60, 60))
	local meteor = Instance.new("Part")
	meteor.Name = "Meteor"
	meteor.Shape = Enum.PartType.Ball
	meteor.Size = Vector3.new(3, 3, 3)
	meteor.Material = Enum.Material.Neon
	meteor.Color = Color3.fromRGB(255, 160, 70)
	meteor.Anchored = true
	meteor.CanCollide = false
	meteor.CanQuery = false
	meteor.CanTouch = false
	meteor.CastShadow = false
	meteor.CFrame = CFrame.new(start)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.2, 0)
	a0.Parent = meteor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.2, 0)
	a1.Parent = meteor
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 80, 40))
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Parent = meteor
	meteor.Parent = Workspace
	local tween = TweenService:Create(meteor, TweenInfo.new(1.6, Enum.EasingStyle.Linear), { CFrame = CFrame.new(target) })
	tween:Play()
	tween.Completed:Connect(function()
		flash(target, Color3.fromRGB(255, 170, 80), 12)
		meteor:Destroy()
		meteorCount -= 1
	end)
end

function World.Start()
	CollectionService:GetInstanceAddedSignal("Planet"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Planet"):Connect(untrack)
	CollectionService:GetInstanceAddedSignal("BeltPlanet"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("BeltPlanet"):Connect(untrack)
	for _, instance in CollectionService:GetTagged("Planet") do
		task.spawn(track, instance)
	end
	for _, instance in CollectionService:GetTagged("BeltPlanet") do
		task.spawn(track, instance)
	end

	RunService.RenderStepped:Connect(function()
		animate()
		updateGuide()
	end)

	Net.Event("Effect").OnClientEvent:Connect(function(name: any, payload: any)
		if type(name) == "string" and type(payload) == "table" then
			onEffect(name, payload)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player then
			return
		end
		local ui = prompt:GetAttribute("OpenUI")
		if type(ui) == "string" then
			Panels.Open(ui)
		end
	end)

	player.CharacterAdded:Connect(function()
		carrying = false
		carryHome = nil
		Effects.SetCarrying(false)
	end)

	task.spawn(function()
		while true do
			task.wait(0.35)
			if ReplicatedStorage:GetAttribute("EventId") == "MeteorShower" then
				spawnMeteor()
			end
		end
	end)

	-- hide "Steal" on planets of locked bases
	task.spawn(function()
		while true do
			task.wait(0.3)
			for model, entry in tracked do
				if
					model:GetAttribute("Mode") == "Base"
					and model:GetAttribute("OwnerUserId") ~= player.UserId
					and model:GetAttribute("Carried") ~= true
				then
					local prompt = entry.Core:FindFirstChild("PlanetPrompt")
					local folder = model.Parent
					local plotModel = if folder then folder.Parent else nil
					if prompt and prompt:IsA("ProximityPrompt") and plotModel then
						prompt.Enabled = plotModel:GetAttribute("Locked") ~= true
					end
				end
			end
		end
	end)

	task.delay(Config.FavoritePromptMinutes * 60, function()
		if game.PlaceId ~= 0 then
			pcall(function()
				AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
			end)
		end
	end)
end

return World
