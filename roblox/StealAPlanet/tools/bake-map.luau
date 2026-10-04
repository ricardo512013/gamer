--!nocheck
-- Lune script: runs MapBuilder on a built place file so the map is visible in
-- Studio edit mode. Usage: lune run tools/bake-map.luau <in.rbxlx> <out.rbxlx>
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local input = process.args[1]
local output = process.args[2] or input
assert(input, "usage: lune run tools/bake-map.luau <in.rbxlx> [out.rbxlx]")

local game = roblox.deserializePlace(fs.readFile(input))
local workspace = game:GetService("Workspace")
local lighting = game:GetService("Lighting")

local env = setmetatable({
	Instance = roblox.Instance,
	CFrame = roblox.CFrame,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	Color3 = roblox.Color3,
	Font = roblox.Font,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	game = game,
	workspace = workspace,
}, { __index = _G })

local source = fs.readFile("src/server/Services/MapBuilder.luau")
local MapBuilder = luau.load(source, { debugName = "MapBuilder", environment = env })()

local existing = workspace:FindFirstChild("Map")
if existing then
	existing:Destroy()
end
MapBuilder.Build(workspace)
MapBuilder.SetupLighting(lighting)

local count = 0
for _, d in workspace:FindFirstChild("Map"):GetDescendants() do
	count += 1
end
print("Map instances:", count)

fs.writeFile(output, roblox.serializePlace(game, output:sub(-6) == ".rbxlx"))
print("Wrote " .. output)
