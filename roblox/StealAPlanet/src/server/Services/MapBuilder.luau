--!strict
-- Builds the whole map (bases, cosmic belt, stalls, leaderboards, decoration)
-- out of plain parts. It is self-contained (no requires), so you can bake the
-- map into the place to edit it by hand. In Studio's Command Bar run:
--   require(game.ServerScriptService.Server.Services.MapBuilder).Build(workspace)
-- If workspace.Map already exists when the game starts, it is reused as is.

local MapBuilder = {}

MapBuilder.PLOT_COUNT = 8
MapBuilder.BELT_START = Vector3.new(-160, 0, 0)
MapBuilder.BELT_END = Vector3.new(160, 0, 0)
MapBuilder.BELT_TOP = 1.2
MapBuilder.LOBBY = Vector3.new(190, 0, 0)

local BELT_LENGTH = 320
local BELT_WIDTH = 14
local PLOT_X = { -135, -45, 45, 135 }
local PLOT_Z = 108
local SLOT_ROW_Z = { -9, 2, 13, 24 }
local SLOT_SPACING = 11
local WALL_HEIGHT = 20

local PLOT_COLORS = {
	Color3.fromRGB(255, 85, 85),
	Color3.fromRGB(255, 165, 60),
	Color3.fromRGB(255, 225, 70),
	Color3.fromRGB(90, 230, 110),
	Color3.fromRGB(70, 200, 255),
	Color3.fromRGB(95, 115, 255),
	Color3.fromRGB(190, 95, 255),
	Color3.fromRGB(255, 100, 200),
}

local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local WHITE = Color3.fromRGB(255, 255, 255)
local SPACE_DARK = Color3.fromRGB(20, 16, 40)

-- Deterministic pseudo random numbers (same decoration every time).
local seed = 20261004
local function rand(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if material == Enum.Material.Neon then
		p.CastShadow = false
	end
	p.Parent = parent
	return p
end

local function shaped(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = part(parent, name, size, cframe, color, material)
	p.Shape = shape
	return p
end

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

local function textLabel(parent: Instance, name: string, text: string, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = SPACE_DARK
	label.Parent = parent
	return label
end

local function surfaceText(target: BasePart, face: Enum.NormalId, name: string, text: string, color: Color3): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = name .. "Gui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = target
	local label = textLabel(gui, name, text, color)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label
	return label
end

local function billboard(
	target: Instance,
	name: string,
	size: Vector2,
	offset: Vector3,
	text: string,
	color: Color3,
	maxDistance: number
): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = name .. "Gui"
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.StudsOffsetWorldSpace = offset
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance
	gui.Parent = target
	return textLabel(gui, name, text, color)
end

local function openPrompt(target: BasePart, uiName: string, actionText: string, objectText: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenUI", uiName)
	prompt.Parent = target
end

local function buildGround(map: Instance)
	part(map, "Ground", Vector3.new(440, 4, 330), CFrame.new(0, -2, 0), Color3.fromRGB(34, 28, 62), Enum.Material.Slate)
	local rimColor = Color3.fromRGB(140, 90, 255)
	part(map, "Rim", Vector3.new(440, 0.4, 1), CFrame.new(0, 0.2, 164.5), rimColor, Enum.Material.Neon)
	part(map, "Rim", Vector3.new(440, 0.4, 1), CFrame.new(0, 0.2, -164.5), rimColor, Enum.Material.Neon)
	part(map, "Rim", Vector3.new(1, 0.4, 330), CFrame.new(219.5, 0.2, 0), rimColor, Enum.Material.Neon)
	part(map, "Rim", Vector3.new(1, 0.4, 330), CFrame.new(-219.5, 0.2, 0), rimColor, Enum.Material.Neon)

	-- invisible boundary walls
	for _, info in
		{
			{ Vector3.new(1, 140, 332), Vector3.new(221, 70, 0) },
			{ Vector3.new(1, 140, 332), Vector3.new(-221, 70, 0) },
			{ Vector3.new(442, 140, 1), Vector3.new(0, 70, 166) },
			{ Vector3.new(442, 140, 1), Vector3.new(0, 70, -166) },
		}
	do
		local wall = part(map, "Boundary", info[1], CFrame.new(info[2]), WHITE, Enum.Material.SmoothPlastic)
		wall.Transparency = 1
	end

	-- paths from each base entrance to the belt
	for _, x in PLOT_X do
		for _, sign in { 1, -1 } do
			part(
				map,
				"Path",
				Vector3.new(16, 0.2, 70),
				CFrame.new(x, 0.1, sign * 43),
				Color3.fromRGB(58, 50, 100),
				Enum.Material.SmoothPlastic
			)
		end
	end
end

local function buildBelt(map: Instance)
	local belt = Instance.new("Model")
	belt.Name = "CosmicBelt"
	belt.Parent = map
	local top = MapBuilder.BELT_TOP
	part(
		belt,
		"Belt",
		Vector3.new(BELT_LENGTH, top, BELT_WIDTH),
		CFrame.new(0, top / 2, 0),
		Color3.fromRGB(44, 44, 58),
		Enum.Material.DiamondPlate
	)
	local edge = Color3.fromRGB(0, 230, 255)
	for _, z in { BELT_WIDTH / 2 + 0.4, -(BELT_WIDTH / 2 + 0.4) } do
		part(belt, "Edge", Vector3.new(BELT_LENGTH, top + 0.4, 0.8), CFrame.new(0, (top + 0.4) / 2, z), edge, Enum.Material.Neon)
	end
	-- chevrons pointing in the direction the planets travel (+X)
	local x = -BELT_LENGTH / 2 + 10
	while x < BELT_LENGTH / 2 - 5 do
		for _, side in { 1, -1 } do
			local chevron = part(
				belt,
				"Chevron",
				Vector3.new(5, 0.1, 0.6),
				CFrame.new(x, top + 0.05, side * 1.6) * CFrame.Angles(0, math.rad(40 * side), 0),
				Color3.fromRGB(120, 240, 255),
				Enum.Material.Neon
			)
			chevron.Transparency = 0.35
			chevron.CanCollide = false
		end
		x += 16
	end

	-- arch with the title
	local archColor = Color3.fromRGB(60, 50, 110)
	for _, px in { -16, 16 } do
		for _, pz in { -10, 10 } do
			part(belt, "ArchPillar", Vector3.new(2, 18, 2), CFrame.new(px, 9, pz), archColor, Enum.Material.Metal)
		end
		part(belt, "ArchTop", Vector3.new(2, 2, 22), CFrame.new(px, 19, 0), archColor, Enum.Material.Metal)
	end
	local sign = part(belt, "ArchSign", Vector3.new(34, 5, 1.5), CFrame.new(0, 21.5, 0), SPACE_DARK, Enum.Material.SmoothPlastic)
	surfaceText(sign, Enum.NormalId.Front, "Title", "🪐 COSMIC BELT 🪐", Color3.fromRGB(120, 240, 255))
	surfaceText(sign, Enum.NormalId.Back, "Title", "🪐 COSMIC BELT 🪐", Color3.fromRGB(120, 240, 255))

	-- portals at both ends
	for _, px in { -168, 168 } do
		local ring = shaped(
			belt,
			"PortalRing",
			Enum.PartType.Cylinder,
			Vector3.new(1, 24, 24),
			CFrame.new(px, 12, 0),
			Color3.fromRGB(170, 80, 255),
			Enum.Material.Neon
		)
		ring.CanCollide = false
		local hole = shaped(
			belt,
			"PortalHole",
			Enum.PartType.Cylinder,
			Vector3.new(1.4, 19, 19),
			CFrame.new(px, 12, 0),
			Color3.fromRGB(8, 0, 20),
			Enum.Material.Neon
		)
		hole.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(170, 80, 255)
		light.Range = 30
		light.Brightness = 3
		light.Parent = ring
	end
end

local function buildSlot(slots: Instance, plotFrame: CFrame, index: number, x: number, z: number, color: Color3)
	local slot = Instance.new("Model")
	slot.Name = "Slot" .. index
	slot:SetAttribute("SlotIndex", index)
	slot.Parent = slots

	local pedestal = shaped(
		slot,
		"Pedestal",
		Enum.PartType.Cylinder,
		Vector3.new(2, 6, 6),
		plotFrame * CFrame.new(x, 2, z) * VERTICAL,
		Color3.fromRGB(72, 68, 104),
		Enum.Material.Metal
	)
	local rim = shaped(
		slot,
		"Rim",
		Enum.PartType.Cylinder,
		Vector3.new(0.3, 6.4, 6.4),
		plotFrame * CFrame.new(x, 2.9, z) * VERTICAL,
		color,
		Enum.Material.Neon
	)
	rim.CanCollide = false

	local pad = part(
		slot,
		"CollectPad",
		Vector3.new(4.6, 0.3, 2.2),
		plotFrame * CFrame.new(x, 1.15, z - 4.4),
		Color3.fromRGB(80, 255, 120),
		Enum.Material.Neon
	)
	pad.Transparency = 0.15
	billboard(pad, "Amount", Vector2.new(5, 1.2), Vector3.new(0, 1.6, 0), "", Color3.fromRGB(120, 255, 150), 45)

	local lockedLabel = billboard(
		pedestal,
		"Locked",
		Vector2.new(6, 1.4),
		Vector3.new(0, 3, 0),
		"🔒 Rebirth",
		Color3.fromRGB(255, 120, 120),
		50
	)
	local lockedGui = lockedLabel.Parent :: BillboardGui
	lockedGui.Enabled = false
end

local function buildPlot(plots: Instance, index: number, frame: CFrame)
	local color = PLOT_COLORS[index]
	local dark = color:Lerp(Color3.fromRGB(22, 18, 40), 0.78)
	local glass = color:Lerp(WHITE, 0.25)

	local plot = Instance.new("Model")
	plot.Name = "Plot" .. index
	plot:SetAttribute("PlotIndex", index)
	plot.Parent = plots

	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	part(plot, "Floor", Vector3.new(64, 1, 60), at(0, 0.5, 0), dark, Enum.Material.SmoothPlastic)
	for _, info in
		{
			{ Vector3.new(64, 0.3, 0.6), Vector3.new(0, 1.05, 29.7) },
			{ Vector3.new(64, 0.3, 0.6), Vector3.new(0, 1.05, -29.7) },
			{ Vector3.new(0.6, 0.3, 60), Vector3.new(31.7, 1.05, 0) },
			{ Vector3.new(0.6, 0.3, 60), Vector3.new(-31.7, 1.05, 0) },
		}
	do
		local trim = part(plot, "FloorTrim", info[1], at(info[2].X, info[2].Y, info[2].Z), color, Enum.Material.Neon)
		trim.CanCollide = false
	end

	local wallY = 1 + WALL_HEIGHT / 2
	local walls = {
		{ Vector3.new(1, WALL_HEIGHT, 60), Vector3.new(-32.5, wallY, 0) },
		{ Vector3.new(1, WALL_HEIGHT, 60), Vector3.new(32.5, wallY, 0) },
		{ Vector3.new(66, WALL_HEIGHT, 1), Vector3.new(0, wallY, 30.5) },
		{ Vector3.new(24.5, WALL_HEIGHT, 1), Vector3.new(-20.25, wallY, -30.5) },
		{ Vector3.new(24.5, WALL_HEIGHT, 1), Vector3.new(20.25, wallY, -30.5) },
	}
	for _, info in walls do
		local wall = part(plot, "Wall", info[1], at(info[2].X, info[2].Y, info[2].Z), glass, Enum.Material.Glass)
		wall.Transparency = 0.55
		local trimSize = Vector3.new(info[1].X + 0.2, 0.6, info[1].Z + 0.2)
		local trim = part(plot, "WallTrim", trimSize, at(info[2].X, 1 + WALL_HEIGHT + 0.3, info[2].Z), color, Enum.Material.Neon)
		trim.CanCollide = false
	end

	local lintel = part(plot, "Sign", Vector3.new(16, 5, 1), at(0, 18.5, -30.5), SPACE_DARK, Enum.Material.SmoothPlastic)
	surfaceText(lintel, Enum.NormalId.Front, "SignLabel", "EMPTY BASE", color:Lerp(WHITE, 0.3))
	surfaceText(lintel, Enum.NormalId.Back, "SignLabelInner", "EMPTY BASE", color:Lerp(WHITE, 0.3))
	billboard(lintel, "LockLabel", Vector2.new(12, 2.6), Vector3.new(0, 5, 0), "🔓 OPEN", Color3.fromRGB(140, 255, 160), 220)

	local laser = part(plot, "Laser", Vector3.new(16, 15, 0.6), at(0, 8.5, -30.5), Color3.fromRGB(255, 40, 60), Enum.Material.Neon)
	laser.CanCollide = false
	laser.Transparency = 1

	local lockPad = part(plot, "LockPad", Vector3.new(7, 0.4, 7), at(20, 1.2, -23), Color3.fromRGB(255, 90, 90), Enum.Material.Neon)
	lockPad.Transparency = 0.1
	billboard(lockPad, "LockPadLabel", Vector2.new(7, 1.6), Vector3.new(0, 2.5, 0), "🔒 STEP TO LOCK", WHITE, 60)

	local spawnPad = shaped(
		plot,
		"Spawn",
		Enum.PartType.Cylinder,
		Vector3.new(0.3, 7, 7),
		at(-20, 1.15, -23) * VERTICAL,
		color,
		Enum.Material.Neon
	)
	spawnPad.CanCollide = false
	spawnPad.Transparency = 0.3

	local slots = Instance.new("Folder")
	slots.Name = "Slots"
	slots.Parent = plot
	for row = 1, #SLOT_ROW_Z do
		for column = 1, 5 do
			local slotIndex = (row - 1) * 5 + column
			buildSlot(slots, frame, slotIndex, (column - 3) * SLOT_SPACING, SLOT_ROW_Z[row], color)
		end
	end

	local planets = Instance.new("Folder")
	planets.Name = "Planets"
	planets.Parent = plot
end

local function buildStall(
	map: Instance,
	name: string,
	position: Vector3,
	facingSign: number,
	color: Color3,
	title: string,
	uiName: string,
	action: string
)
	local stall = Instance.new("Model")
	stall.Name = name
	stall.Parent = map
	-- the stall front looks toward the belt (z = 0)
	local frame = CFrame.lookAt(position, position + Vector3.new(0, 0, -facingSign))
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local counter = part(stall, "Counter", Vector3.new(14, 3.5, 4), at(0, 1.75, 0), Color3.fromRGB(110, 75, 50), Enum.Material.WoodPlanks)
	part(stall, "CounterTop", Vector3.new(14.4, 0.4, 4.4), at(0, 3.7, 0), color, Enum.Material.Neon)
	for _, px in { -6.5, 6.5 } do
		part(stall, "Post", Vector3.new(1, 11, 1), at(px, 5.5, 3), Color3.fromRGB(80, 70, 120), Enum.Material.Metal)
	end
	part(stall, "Back", Vector3.new(14, 9, 1), at(0, 4.5, 3.5), Color3.fromRGB(45, 38, 80), Enum.Material.SmoothPlastic)
	part(stall, "Roof", Vector3.new(16, 1, 8), at(0, 11.5, 1.5), color:Lerp(SPACE_DARK, 0.4), Enum.Material.SmoothPlastic)
	local sign = part(stall, "Sign", Vector3.new(14, 3.4, 0.6), at(0, 13.6, 0), SPACE_DARK, Enum.Material.SmoothPlastic)
	surfaceText(sign, Enum.NormalId.Front, "Title", title, color:Lerp(WHITE, 0.2))
	surfaceText(sign, Enum.NormalId.Back, "Title", title, color:Lerp(WHITE, 0.2))
	openPrompt(counter, uiName, action, title)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 20
	light.Brightness = 2
	light.Parent = sign
end

local function buildRebirthAltar(map: Instance, position: Vector3)
	local altar = Instance.new("Model")
	altar.Name = "RebirthAltar"
	altar.Parent = map
	local base = shaped(
		altar,
		"Base",
		Enum.PartType.Cylinder,
		Vector3.new(1, 16, 16),
		CFrame.new(position + Vector3.new(0, 0.5, 0)) * VERTICAL,
		Color3.fromRGB(50, 40, 90),
		Enum.Material.Marble
	)
	local ring = shaped(
		altar,
		"Ring",
		Enum.PartType.Cylinder,
		Vector3.new(0.3, 16.6, 16.6),
		CFrame.new(position + Vector3.new(0, 1, 0)) * VERTICAL,
		Color3.fromRGB(90, 255, 200),
		Enum.Material.Neon
	)
	ring.CanCollide = false
	local crystal = shaped(
		altar,
		"Crystal",
		Enum.PartType.Ball,
		Vector3.new(5, 5, 5),
		CFrame.new(position + Vector3.new(0, 7, 0)),
		Color3.fromRGB(90, 255, 200),
		Enum.Material.Neon
	)
	crystal.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(90, 255, 200)
	light.Range = 24
	light.Brightness = 3
	light.Parent = crystal
	billboard(crystal, "AltarLabel", Vector2.new(12, 2.4), Vector3.new(0, 5, 0), "♻️ REBIRTH", Color3.fromRGB(140, 255, 220), 150)
	openPrompt(base, "Rebirth", "Rebirth", "Rebirth Altar")
end

local function buildLeaderboards(map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = map
	type BoardInfo = { name: string, title: string, z: number, color: Color3 }
	local boards: { BoardInfo } = {
		{ name = "LB_TotalEarned", title = "💰 TOP EARNERS", z = -40, color = Color3.fromRGB(255, 210, 70) },
		{ name = "LB_Steals", title = "🦹 TOP THIEVES", z = 0, color = Color3.fromRGB(255, 90, 120) },
		{ name = "LB_Rebirths", title = "♻️ TOP REBIRTHS", z = 40, color = Color3.fromRGB(90, 255, 200) },
	}
	for _, info in boards do
		local boardName = info.name
		local title = info.title
		local z = info.z
		local color = info.color
		local model = Instance.new("Model")
		model.Name = boardName
		model.Parent = folder
		local board = part(model, "Board", Vector3.new(1, 26, 18), CFrame.new(-200, 15, z), SPACE_DARK, Enum.Material.SmoothPlastic)
		part(model, "Frame", Vector3.new(0.8, 27, 19), CFrame.new(-200.3, 15, z), color, Enum.Material.Neon)
		part(model, "Leg", Vector3.new(1, 2, 4), CFrame.new(-200, 1, z), Color3.fromRGB(70, 60, 110), Enum.Material.Metal)

		local gui = Instance.new("SurfaceGui")
		gui.Name = "BoardGui"
		gui.Face = Enum.NormalId.Right
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = board

		local titleLabel = textLabel(gui, "Title", title, color)
		titleLabel.Size = UDim2.fromScale(1, 0.12)

		local rows = Instance.new("Frame")
		rows.Name = "Rows"
		rows.BackgroundTransparency = 1
		rows.Position = UDim2.fromScale(0.05, 0.14)
		rows.Size = UDim2.fromScale(0.9, 0.84)
		rows.Parent = gui
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = rows
		for i = 1, 10 do
			local row = textLabel(rows, "Row" .. i, if i == 1 then "Loading..." else "", WHITE)
			row.LayoutOrder = i
			row.Size = UDim2.fromScale(1, 0.1)
			row.TextXAlignment = Enum.TextXAlignment.Left
		end
	end
end

local function buildLobby(map: Instance)
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "LobbySpawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(14, 1, 14)
	spawnLocation.CFrame = CFrame.new(MapBuilder.LOBBY + Vector3.new(0, 0.5, 0))
	spawnLocation.Color = Color3.fromRGB(140, 90, 255)
	spawnLocation.Material = Enum.Material.Neon
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.TopSurface = Enum.SurfaceType.Smooth
	spawnLocation.BottomSurface = Enum.SurfaceType.Smooth
	spawnLocation.Parent = map

	local board = part(
		map,
		"WelcomeBoard",
		Vector3.new(1, 16, 30),
		CFrame.new(MapBuilder.LOBBY + Vector3.new(16, 10, 0)),
		SPACE_DARK,
		Enum.Material.SmoothPlastic
	)
	surfaceText(
		board,
		Enum.NormalId.Left,
		"Welcome",
		"🪐 STEAL A PLANET 🪐\nBuy planets on the Cosmic Belt, steal from other bases and become the richest in the galaxy!\n⭐ Like & Favorite for updates!",
		WHITE
	)
end

local function buildLamps(map: Instance)
	local x = -150
	while x <= 150 do
		for _, z in { 15, -15 } do
			part(map, "LampPost", Vector3.new(0.8, 9, 0.8), CFrame.new(x, 4.5, z), Color3.fromRGB(80, 70, 120), Enum.Material.Metal)
			local bulb = shaped(
				map,
				"LampBulb",
				Enum.PartType.Ball,
				Vector3.new(2, 2, 2),
				CFrame.new(x, 9.6, z),
				Color3.fromRGB(190, 160, 255),
				Enum.Material.Neon
			)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(190, 160, 255)
			light.Range = 18
			light.Brightness = 1.5
			light.Parent = bulb
		end
		x += 30
	end
end

local function buildDecoration(map: Instance)
	local deco = Instance.new("Folder")
	deco.Name = "Decoration"
	deco.Parent = map
	for _ = 1, 40 do
		local angle = rand() * math.pi * 2
		local px = math.cos(angle) * (265 + rand() * 90)
		local pz = math.sin(angle) * (205 + rand() * 90)
		local size = 4 + rand() * 12
		local rock = shaped(
			deco,
			"Asteroid",
			Enum.PartType.Ball,
			Vector3.new(size, size, size),
			CFrame.new(px, 8 + rand() * 70, pz),
			Color3.fromRGB(90, 80, 120):Lerp(Color3.fromRGB(150, 130, 170), rand()),
			Enum.Material.Slate
		)
		rock.CanCollide = false
		rock.CastShadow = false
	end

	local giant = shaped(
		deco,
		"GiantPlanet",
		Enum.PartType.Ball,
		Vector3.new(260, 260, 260),
		CFrame.new(380, 190, 560),
		Color3.fromRGB(125, 90, 210),
		Enum.Material.SmoothPlastic
	)
	giant.CanCollide = false
	giant.CastShadow = false
	local giantRing = shaped(
		deco,
		"GiantRing",
		Enum.PartType.Cylinder,
		Vector3.new(3, 560, 560),
		CFrame.new(380, 190, 560) * CFrame.Angles(math.rad(20), 0, 0) * VERTICAL,
		Color3.fromRGB(200, 170, 255),
		Enum.Material.Neon
	)
	giantRing.Transparency = 0.55
	giantRing.CanCollide = false
	giantRing.CastShadow = false

	local moon = shaped(
		deco,
		"BigMoon",
		Enum.PartType.Ball,
		Vector3.new(140, 140, 140),
		CFrame.new(-500, 240, -400),
		Color3.fromRGB(205, 205, 220),
		Enum.Material.Slate
	)
	moon.CanCollide = false
	moon.CastShadow = false

	local star = shaped(
		deco,
		"FarStar",
		Enum.PartType.Ball,
		Vector3.new(70, 70, 70),
		CFrame.new(-320, 320, 620),
		Color3.fromRGB(255, 210, 90),
		Enum.Material.Neon
	)
	star.CanCollide = false
	star.CastShadow = false
end

-- Builds workspace.Map (or returns the existing one).
function MapBuilder.Build(root: Instance): Instance
	local existing = root:FindFirstChild("Map")
	if existing and existing:FindFirstChild("Plots") then
		return existing
	end
	seed = 20261004

	local map = Instance.new("Folder")
	map.Name = "Map"

	buildGround(map)
	buildBelt(map)

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = map
	local index = 0
	for _, side in { 1, -1 } do
		for _, x in PLOT_X do
			index += 1
			local center = Vector3.new(x, 0, PLOT_Z * side)
			buildPlot(plots, index, CFrame.lookAt(center, Vector3.new(x, 0, 0)))
		end
	end

	buildStall(map, "ToolShop", Vector3.new(0, 0, 44), 1, Color3.fromRGB(255, 180, 60), "🛠️ TOOL SHOP", "Shop", "Open Shop")
	buildStall(map, "IndexStand", Vector3.new(-90, 0, 44), 1, Color3.fromRGB(90, 200, 255), "📖 PLANET INDEX", "Index", "Open Index")
	buildStall(map, "StoreStand", Vector3.new(-90, 0, -44), -1, Color3.fromRGB(255, 110, 200), "⭐ STORE", "Store", "Open Store")
	buildRebirthAltar(map, Vector3.new(0, 0, -44))
	buildLeaderboards(map)
	buildLobby(map)
	buildLamps(map)
	buildDecoration(map)

	map:SetAttribute("Built", true)
	map.Parent = root
	return map
end

-- Space look: night sky, purple atmosphere, bloom.
function MapBuilder.SetupLighting(lighting: Lighting)
	lighting.ClockTime = 0
	lighting.Brightness = 2
	lighting.Ambient = Color3.fromRGB(95, 85, 140)
	lighting.OutdoorAmbient = Color3.fromRGB(125, 112, 175)
	lighting.EnvironmentDiffuseScale = 0.4
	lighting.EnvironmentSpecularScale = 0.6
	lighting.GlobalShadows = true
	lighting.FogEnd = 100000

	if not lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.StarCount = 3000
		sky.CelestialBodiesShown = false
		sky.Parent = lighting
	end
	if not lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.22
		atmosphere.Offset = 0.1
		atmosphere.Color = Color3.fromRGB(120, 90, 200)
		atmosphere.Decay = Color3.fromRGB(70, 40, 130)
		atmosphere.Glare = 0
		atmosphere.Haze = 1.2
		atmosphere.Parent = lighting
	end
	if not lighting:FindFirstChild("SAP_Bloom") then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "SAP_Bloom"
		bloom.Intensity = 0.7
		bloom.Size = 28
		bloom.Threshold = 1.4
		bloom.Parent = lighting
	end
	if not lighting:FindFirstChild("SAP_ColorCorrection") then
		local correction = Instance.new("ColorCorrectionEffect")
		correction.Name = "SAP_ColorCorrection"
		correction.Saturation = 0.15
		correction.Contrast = 0.08
		correction.Brightness = 0.03
		correction.Parent = lighting
	end
end

return MapBuilder
