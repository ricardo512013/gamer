--!strict
-- Tools: Space Bat (free), Speed Coil, Gravity Coil, Freeze Ray, Invisibility Cloak.
-- Tools are built from parts, owned tools are saved and given on every spawn.
-- Using a tool goes through the "UseTool" remote and is validated here.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local StealService = require(script.Parent.StealService)

local ToolService = {}

local cooldowns: { [Player]: { [string]: number } } = {}

local function weldTo(handle: BasePart, part: BasePart, offset: CFrame)
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	part.CFrame = handle.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
	part.Parent = handle.Parent
end

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Shape = shape or Enum.PartType.Block
	part.CanCollide = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

function ToolService.CreateTool(toolId: string): Tool?
	local info = Config.Tools[toolId]
	if not info then
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = info.Name
	tool.ToolTip = info.Description
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", toolId)

	local handle: Part
	if toolId == "Bat" then
		handle = newPart("Handle", Vector3.new(0.5, 0.5, 4.4), info.Color, Enum.Material.Wood)
		handle.Parent = tool
		weldTo(handle, newPart("Barrel", Vector3.new(0.9, 0.9, 2), info.Color, Enum.Material.Wood), CFrame.new(0, 0, -1.4))
		weldTo(
			handle,
			newPart("Tip", Vector3.new(1, 1, 1), Color3.fromRGB(170, 90, 255), Enum.Material.Neon, Enum.PartType.Ball),
			CFrame.new(0, 0, -2.5)
		)
		tool.Grip = CFrame.new(0, 0, 1.6)
	elseif toolId == "FreezeRay" then
		handle = newPart("Handle", Vector3.new(0.6, 1, 2.2), Color3.fromRGB(70, 80, 110), Enum.Material.Metal)
		handle.Parent = tool
		weldTo(
			handle,
			newPart("Barrel", Vector3.new(1.6, 0.5, 0.5), info.Color, Enum.Material.Neon, Enum.PartType.Cylinder),
			CFrame.new(0, 0.2, -1.6) * CFrame.Angles(0, math.rad(90), 0)
		)
		tool.Grip = CFrame.new(0, -0.2, 0.4)
	elseif toolId == "Cloak" then
		handle = newPart("Handle", Vector3.new(1, 1.4, 0.4), info.Color, Enum.Material.Fabric)
		handle.Parent = tool
		weldTo(
			handle,
			newPart("Gem", Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(200, 170, 255), Enum.Material.Neon, Enum.PartType.Ball),
			CFrame.new(0, 0.3, -0.25)
		)
		tool.Grip = CFrame.new(0, 0, 0)
	else
		-- coils
		handle = newPart("Handle", Vector3.new(1, 1, 1), info.Color, Enum.Material.Neon, Enum.PartType.Cylinder)
		handle.Parent = tool
		weldTo(
			handle,
			newPart("Core", Vector3.new(1.2, 0.5, 0.5), Color3.fromRGB(255, 255, 255), Enum.Material.Metal, Enum.PartType.Cylinder),
			CFrame.new()
		)
		tool.Grip = CFrame.new(0, 0, 0)
	end

	if toolId == "SpeedCoil" or toolId == "GravityCoil" then
		local holder: Player? = nil
		tool.Equipped:Connect(function()
			local character = tool.Parent
			local player = if character and character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
			if player then
				holder = player
				CharacterService.SetCoil(player, toolId, true)
			end
		end)
		tool.Unequipped:Connect(function()
			local player = holder
			holder = nil
			if player then
				CharacterService.SetCoil(player, toolId, false)
			end
		end)
	end
	return tool
end

function ToolService.GiveTools(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local data = DataService.Get(player)
	if not backpack or not data then
		return
	end
	local owned: { [string]: boolean } = { Bat = true }
	for toolId, has in data.Tools do
		if has and Config.Tools[toolId] then
			owned[toolId] = true
		end
	end
	local present: { [string]: boolean } = {}
	local containers: { Instance } = { backpack }
	local character = player.Character
	if character then
		table.insert(containers, character)
	end
	for _, container in containers do
		for _, item in container:GetChildren() do
			local id = item:GetAttribute("ToolId")
			if item:IsA("Tool") and type(id) == "string" then
				present[id] = true
			end
		end
	end
	local ordered: { string } = {}
	for toolId in owned do
		table.insert(ordered, toolId)
	end
	table.sort(ordered, function(a, b)
		return Config.Tools[a].Order < Config.Tools[b].Order
	end)
	for _, toolId in ordered do
		if not present[toolId] then
			local tool = ToolService.CreateTool(toolId)
			if tool then
				tool.Parent = backpack
			end
		end
	end
end

local function equippedTool(player: Player, toolId: string): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("ToolId") == toolId then
		return tool
	end
	return nil
end

local function onCooldown(player: Player, toolId: string, seconds: number): boolean
	local map = cooldowns[player]
	if not map then
		map = {}
		cooldowns[player] = map
	end
	local now = os.clock()
	if now - (map[toolId] or 0) < seconds then
		return true
	end
	map[toolId] = now
	return false
end

local function useBat(player: Player)
	local info = Config.Tools.Bat
	local root = CharacterService.GetRoot(player)
	if not root then
		return
	end
	local range = info.Range or 9
	local look = root.CFrame.LookVector
	local best: Player? = nil
	local bestDistance = math.huge
	for _, other in Players:GetPlayers() do
		if other ~= player and CharacterService.IsAlive(other) then
			local otherRoot = CharacterService.GetRoot(other)
			if otherRoot then
				local offset = otherRoot.Position - root.Position
				local distance = offset.Magnitude
				if distance <= range and distance < bestDistance and (distance < 3 or look:Dot(offset.Unit) > 0.2) then
					best = other
					bestDistance = distance
				end
			end
		end
	end
	Net.EffectAll("Swing", { Position = root.Position })
	local target = best
	if target then
		local targetRoot = CharacterService.GetRoot(target)
		local direction = if targetRoot then (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1) else look
		if direction.Magnitude < 0.01 then
			direction = look
		end
		StealService.Drop(target)
		CharacterService.Stun(target, info.StunTime or 1.2, direction.Unit)
		Net.EffectAll("Hit", { Position = if targetRoot then targetRoot.Position else root.Position })
	end
end

local function useFreeze(player: Player, target: any)
	local info = Config.Tools.FreezeRay
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == player then
		return
	end
	local targetPlayer = target :: Player
	local root = CharacterService.GetRoot(player)
	local targetRoot = CharacterService.GetRoot(targetPlayer)
	if not root or not targetRoot or not CharacterService.IsAlive(targetPlayer) then
		return
	end
	if (targetRoot.Position - root.Position).Magnitude > (info.Range or 45) + 5 then
		return
	end
	if onCooldown(player, "FreezeRay", info.Cooldown or 12) then
		return
	end
	StealService.Drop(targetPlayer)
	CharacterService.Freeze(targetPlayer, info.FreezeTime or 3)
	Net.EffectAll("FreezeBeam", { From = root.Position, To = targetRoot.Position })
	Net.Notify(targetPlayer, "❄️ " .. player.DisplayName .. " froze you!", "error")
end

local function useCloak(player: Player)
	local info = Config.Tools.Cloak
	if onCooldown(player, "Cloak", info.Cooldown or 35) then
		Net.Notify(player, "Cloak is recharging...", "info")
		return
	end
	CharacterService.SetInvisible(player, info.Duration or 8)
	Net.Notify(player, "👻 You are invisible for " .. (info.Duration or 8) .. " seconds!", "success")
end

local function onUseTool(player: Player, toolId: any, target: any)
	if type(toolId) ~= "string" or not Config.Tools[toolId] then
		return
	end
	if not equippedTool(player, toolId) or not CharacterService.IsAlive(player) then
		return
	end
	if toolId == "Bat" then
		if not onCooldown(player, "Bat", Config.Tools.Bat.Cooldown or 0.9) then
			useBat(player)
		end
	elseif toolId == "FreezeRay" then
		useFreeze(player, target)
	elseif toolId == "Cloak" then
		useCloak(player)
	end
end

function ToolService.BuyTool(player: Player, toolId: any): Net.Result
	if type(toolId) ~= "string" then
		return { ok = false, msg = "Unknown tool" }
	end
	local info = Config.Tools[toolId]
	local data = DataService.Get(player)
	if not info or not data then
		return { ok = false, msg = "Unknown tool" }
	end
	if toolId == "Bat" or data.Tools[toolId] then
		return { ok = false, msg = "You already own this!" }
	end
	if data.Rebirths < info.Rebirth then
		return { ok = false, msg = "Requires Rebirth " .. info.Rebirth .. "!" }
	end
	if not DataService.SpendCash(player, info.Price) then
		return { ok = false, msg = "You need " .. Format.Cash(info.Price) .. "!" }
	end
	data.Tools[toolId] = true
	DataService.MarkDirty(player)
	ToolService.GiveTools(player)
	Net.Notify(player, info.Icon .. " You bought the " .. info.Name .. "!", "success")
	return { ok = true }
end

function ToolService.Init()
	Net.Event("UseTool").OnServerEvent:Connect(onUseTool)
	Net.Handle("BuyTool", ToolService.BuyTool)
end

function ToolService.PlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		ToolService.GiveTools(player)
	end)
	if player.Character then
		ToolService.GiveTools(player)
	end
end

function ToolService.PlayerRemoving(player: Player)
	cooldowns[player] = nil
end

return ToolService
