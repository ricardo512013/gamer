--!strict
-- Client side of the tools: swing animation and sending "UseTool" to the server.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Effects = require(script.Parent.Parent.UI.Effects)

local Tools = {}

local player = Players.LocalPlayer
local hooked: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local swinging: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function getRoot(character: Model?): BasePart?
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function swing(tool: Tool)
	if swinging[tool] then
		return
	end
	swinging[tool] = true
	local original = tool.Grip
	local down = TweenService:Create(tool, TweenInfo.new(0.08), { Grip = original * CFrame.Angles(math.rad(-75), 0, 0) })
	down:Play()
	down.Completed:Wait()
	local up = TweenService:Create(tool, TweenInfo.new(0.16), { Grip = original })
	up:Play()
	up.Completed:Wait()
	swinging[tool] = nil
end

local function findTarget(range: number): Player?
	local myRoot = getRoot(player.Character)
	local camera = Workspace.CurrentCamera
	if not myRoot or not camera then
		return nil
	end
	local mouse = player:GetMouse()
	local hit = mouse.Target
	if hit then
		local model = hit:FindFirstAncestorOfClass("Model")
		local target = if model then Players:GetPlayerFromCharacter(model) else nil
		local targetRoot = if target then getRoot(target.Character) else nil
		if target and target ~= player and targetRoot and (targetRoot.Position - myRoot.Position).Magnitude <= range then
			return target
		end
	end
	local best: Player? = nil
	local bestDot = 0.9
	local look = camera.CFrame.LookVector
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local root = getRoot(other.Character)
			if root then
				local offset = root.Position - myRoot.Position
				local distance = offset.Magnitude
				if distance > 0 and distance <= range then
					local dot = look:Dot(offset.Unit)
					if dot > bestDot then
						best = other
						bestDot = dot
					end
				end
			end
		end
	end
	return best
end

local function hook(instance: Instance)
	if not instance:IsA("Tool") or hooked[instance] then
		return
	end
	local id = instance:GetAttribute("ToolId")
	if type(id) ~= "string" then
		return
	end
	hooked[instance] = true
	local useTool = Net.Event("UseTool")
	instance.Activated:Connect(function()
		if id == "Bat" then
			task.spawn(swing, instance)
			useTool:FireServer("Bat")
		elseif id == "FreezeRay" then
			local target = findTarget(Config.Tools.FreezeRay.Range or 45)
			if target then
				useTool:FireServer("FreezeRay", target)
			else
				Effects.Toast("Aim at a player in range!", "error")
			end
		elseif id == "Cloak" then
			useTool:FireServer("Cloak")
		end
	end)
end

local function watch(container: Instance)
	for _, child in container:GetChildren() do
		hook(child)
	end
	container.ChildAdded:Connect(hook)
end

function Tools.Start()
	local function onCharacter(character: Model)
		watch(character)
		local backpack = player:WaitForChild("Backpack", 10)
		if backpack then
			watch(backpack)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	local character = player.Character
	if character then
		task.spawn(onCharacter, character)
	end
end

return Tools
