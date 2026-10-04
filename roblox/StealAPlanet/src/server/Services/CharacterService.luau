--!strict
-- Character state: walk speed / jump height, stun (bat), freeze (ray),
-- invisibility (cloak) and spawning at the player's base.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local CharacterService = {}

CharacterService.Died = Signal.new() -- (player)

type State = {
	Carrying: boolean,
	StunUntil: number,
	FrozenUntil: number,
	SpeedCoil: boolean,
	GravityCoil: boolean,
	Invisible: boolean,
	Saved: { [Instance]: number },
}

local states: { [Player]: State } = {}
local spawnResolver: ((Player) -> CFrame?)? = nil

local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = {
			Carrying = false,
			StunUntil = 0,
			FrozenUntil = 0,
			SpeedCoil = false,
			GravityCoil = false,
			Invisible = false,
			Saved = {},
		}
		states[player] = state
	end
	return state
end

function CharacterService.GetHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function CharacterService.GetRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function CharacterService.IsAlive(player: Player): boolean
	local humanoid = CharacterService.GetHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0 and CharacterService.GetRoot(player) ~= nil
end

function CharacterService.Refresh(player: Player)
	local humanoid = CharacterService.GetHumanoid(player)
	if not humanoid then
		return
	end
	local state = getState(player)
	local t = os.clock()
	local disabled = t < state.StunUntil or t < state.FrozenUntil
	local speed = Config.BaseWalkSpeed
	if player:GetAttribute("Pass_SuperSpeed") == true then
		speed += Config.SpeedPassBonus
	end
	if state.SpeedCoil then
		speed += Config.Tools.SpeedCoil.SpeedBonus or 0
	end
	if state.Carrying then
		speed *= Config.CarrySpeedMult
	end
	humanoid.UseJumpPower = false
	humanoid.WalkSpeed = if disabled then 0 else speed
	local jump = if state.GravityCoil then (Config.Tools.GravityCoil.JumpHeight or Config.BaseJumpHeight) else Config.BaseJumpHeight
	humanoid.JumpHeight = if disabled then 0 else jump
end

function CharacterService.SetCarrying(player: Player, carrying: boolean)
	getState(player).Carrying = carrying
	CharacterService.Refresh(player)
end

function CharacterService.SetCoil(player: Player, toolId: string, equipped: boolean)
	local state = getState(player)
	if toolId == "SpeedCoil" then
		state.SpeedCoil = equipped
	elseif toolId == "GravityCoil" then
		state.GravityCoil = equipped
	end
	CharacterService.Refresh(player)
end

function CharacterService.Stun(player: Player, duration: number, direction: Vector3)
	local state = getState(player)
	state.StunUntil = math.max(state.StunUntil, os.clock() + duration)
	CharacterService.Refresh(player)
	Net.Effect(player, "Knockback", { Direction = direction, Power = 55, Duration = duration })
	task.delay(duration + 0.05, CharacterService.Refresh, player)
end

function CharacterService.Freeze(player: Player, duration: number)
	local root = CharacterService.GetRoot(player)
	if not root then
		return
	end
	local state = getState(player)
	state.FrozenUntil = math.max(state.FrozenUntil, os.clock() + duration)
	CharacterService.Refresh(player)

	local ice = Instance.new("Part")
	ice.Name = "FreezeIce"
	ice.Size = Vector3.new(5, 7, 5)
	ice.Color = Color3.fromRGB(160, 230, 255)
	ice.Material = Enum.Material.Ice
	ice.Transparency = 0.35
	ice.CanCollide = false
	ice.CanQuery = false
	ice.CanTouch = false
	ice.Massless = true
	ice.CastShadow = false
	ice.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = ice
	weld.Parent = ice
	ice.Parent = player.Character
	task.delay(duration, function()
		ice:Destroy()
		CharacterService.Refresh(player)
	end)
end

local function setVisible(player: Player, visible: boolean)
	local character = player.Character
	if not character then
		return
	end
	local state = getState(player)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" and descendant.Name ~= "FreezeIce" then
			if visible then
				local saved = state.Saved[descendant]
				descendant.Transparency = if saved then saved else 0
			else
				state.Saved[descendant] = descendant.Transparency
				descendant.Transparency = 1
			end
		elseif descendant:IsA("Decal") then
			if visible then
				local saved = state.Saved[descendant]
				descendant.Transparency = if saved then saved else 0
			else
				state.Saved[descendant] = descendant.Transparency
				descendant.Transparency = 1
			end
		end
	end
	if visible then
		table.clear(state.Saved)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = if visible
			then Enum.HumanoidDisplayDistanceType.Viewer
			else Enum.HumanoidDisplayDistanceType.None
	end
end

function CharacterService.SetInvisible(player: Player, duration: number)
	local state = getState(player)
	if state.Invisible then
		return
	end
	state.Invisible = true
	local character = player.Character
	setVisible(player, false)
	task.delay(duration, function()
		state.Invisible = false
		if player.Character == character then
			setVisible(player, true)
		end
	end)
end

function CharacterService.SetSpawnResolver(resolver: (Player) -> CFrame?)
	spawnResolver = resolver
end

function CharacterService.TeleportHome(player: Player)
	local resolver = spawnResolver
	local character = player.Character
	if not resolver or not character then
		return
	end
	local target = resolver(player)
	if target then
		character:PivotTo(target)
	end
end

local function onCharacter(player: Player, character: Model)
	local state = getState(player)
	state.Carrying = false
	state.StunUntil = 0
	state.FrozenUntil = 0
	state.SpeedCoil = false
	state.GravityCoil = false
	state.Invisible = false
	table.clear(state.Saved)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	CharacterService.Refresh(player)
	humanoid.Died:Connect(function()
		CharacterService.Died:Fire(player)
	end)
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.1)
	if player.Character == character then
		CharacterService.TeleportHome(player)
	end
end

function CharacterService.PlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	local character = player.Character
	if character then
		task.spawn(onCharacter, player, character)
	end
end

function CharacterService.PlayerRemoving(player: Player)
	states[player] = nil
end

function CharacterService.Init()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return CharacterService
