--!nocheck
-- Builds every planet model (all mutations) and its info tags with real
-- Roblox instances through Lune, so invalid properties/values fail here.
--   lune run tests/smoke.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local game = roblox.Instance.new("DataModel")
local cache = {}
local loadModule
local function makeEnv(name)
	local parentProxy = setmetatable({}, {
		__index = function(_, key)
			return { __module = key }
		end,
	})
	return setmetatable({
		script = { Name = name, Parent = parentProxy },
		require = function(target)
			return loadModule(target.__module)
		end,
		game = game,
		Instance = roblox.Instance,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		CFrame = roblox.CFrame,
		Enum = roblox.Enum,
		Font = roblox.Font,
	}, { __index = _G })
end
function loadModule(name)
	if cache[name] ~= nil then
		return cache[name]
	end
	local source = fs.readFile("src/shared/" .. name .. ".luau")
	local result = luau.load(source, { debugName = name, environment = makeEnv(name) })()
	cache[name] = result
	return result
end

local Planets = loadModule("Planets")
local Mutations = loadModule("Mutations")
local PlanetModel = loadModule("PlanetModel")

local built, failures, parts = 0, 0, 0
for _, def in Planets.List do
	for _, mutation in Mutations.List do
		local ok, err = pcall(function()
			local model = PlanetModel.Build(def.Id, mutation.Id, roblox.CFrame.new(1, 2, 3))
			assert(model.PrimaryPart and model.PrimaryPart.Name == "Core", "missing Core")
			assert(model.PrimaryPart.Anchored == true, "Core must be anchored")
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					if d ~= model.PrimaryPart then
						assert(d.Anchored == false, d.Name .. " should be unanchored")
						local weld = d:FindFirstChildOfClass("WeldConstraint")
						assert(weld and weld.Part0 == model.PrimaryPart and weld.Part1 == d, d.Name .. " not welded to Core")
					end
					assert(d.CanCollide == false, d.Name .. " collides")
				end
			end
			assert(model:GetAttribute("PlanetId") == def.Id)
			assert(model:GetAttribute("Mutation") == mutation.Id)
			if mutation.Id == "Rainbow" or def.Visual.Rainbow then
				assert(model:GetAttribute("Rainbow") == true, "rainbow attribute")
			end
			for _, mode in { "Belt", "Base" } do
				local tag = PlanetModel.CreateTag(def.Id, mutation.Id, mode)
				assert(tag:FindFirstChild("Title") and tag:FindFirstChild("Income"), "tag rows")
				assert((tag:FindFirstChild("Price") ~= nil) == (mode == "Belt"), "price row")
			end
		end)
		if ok then
			built += 1
		else
			failures += 1
			print("FAIL " .. def.Id .. " / " .. mutation.Id .. ": " .. tostring(err))
		end
	end
end
print(string.format("Built %d planet models (%d parts), %d failures", built, parts, failures))
if failures > 0 then
	process.exit(1)
end
