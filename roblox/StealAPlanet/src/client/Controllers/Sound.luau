--!strict
-- Plays the sounds listed in Config.Sounds (2D for UI, 3D at a position).

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Sound = {}

local cache: { [string]: Sound } = {}

local function idFor(name: string): string?
	local id = (Config.Sounds :: { [string]: string })[name]
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

function Sound.Play(name: string, volume: number?)
	local id = idFor(name)
	if not id then
		return
	end
	local sound = cache[name]
	if not sound then
		local newSound = Instance.new("Sound")
		newSound.Name = "SAP_" .. name
		newSound.SoundId = id
		newSound.Volume = volume or 0.5
		newSound.Parent = SoundService
		cache[name] = newSound
		sound = newSound
	end
	SoundService:PlayLocalSound(sound)
end

function Sound.PlayAt(name: string, position: Vector3, volume: number?)
	local id = idFor(name)
	if not id then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "SoundAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.RollOffMaxDistance = 80
	sound.Parent = anchor
	anchor.Parent = Workspace
	sound:Play()
	task.delay(3, function()
		anchor:Destroy()
	end)
end

function Sound.StartMusic()
	local id = idFor("Music")
	if not id then
		return
	end
	local music = Instance.new("Sound")
	music.Name = "SAP_Music"
	music.SoundId = id
	music.Looped = true
	music.Volume = 0.25
	music.Parent = SoundService
	music:Play()
end

return Sound
