--!strict
-- Builds planet models out of plain parts (no uploaded meshes needed).
-- Every model has a PrimaryPart called "Core"; all other parts are welded to it,
-- so moving Core moves the whole planet.
--
-- Want custom art? Put a Model named after the planet id (e.g. "Earth") inside
-- ReplicatedStorage.PlanetModels with a PrimaryPart. It will be used instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Planets = require(script.Parent.Planets)
local Mutations = require(script.Parent.Mutations)
local Format = require(script.Parent.Format)
local Economy = require(script.Parent.Economy)

local PlanetModel = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(15, 12, 20)
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic

function PlanetModel.RainbowSequence(): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 60)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 255, 120)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 200, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 90, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 200)),
	})
end

local function newPart(name: string, shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function ball(name: string, diameter: number, color: Color3, material: Enum.Material): Part
	return newPart(name, Enum.PartType.Ball, Vector3.new(diameter, diameter, diameter), color, material)
end

local function ellipsoid(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = newPart(name, Enum.PartType.Block, size, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Cylinder whose round faces point along the local Y axis (a flat disc when thin).
local function disc(name: string, diameter: number, thickness: number, color: Color3, material: Enum.Material): Part
	return newPart(name, Enum.PartType.Cylinder, Vector3.new(thickness, diameter, diameter), color, material)
end

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder's X axis into Y

local function attach(model: Model, core: BasePart, part: BasePart, offset: CFrame, body: boolean)
	part.CFrame = core.CFrame * offset
	if body then
		part:SetAttribute("Body", true)
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = core
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
end

-- Offset on the sphere surface whose -Z axis points outward (for flat decals).
local function onSurface(direction: Vector3, distance: number): CFrame
	local unit = direction.Unit
	local position = unit * distance
	return CFrame.lookAt(position, position + unit)
end

local function addParticles(core: BasePart, color: Color3, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkle"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(1, 2.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = core
end

local function addLight(core: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2
	light.Range = math.clamp(range, 6, 18)
	light.Shadows = false
	light.Parent = core
end

local function addFace(model: Model, core: BasePart, r: number, eyeColor: Color3, eyeMaterial: Enum.Material)
	for _, side in { -1, 1 } do
		local dir = Vector3.new(0.34 * side, 0.22, -1).Unit
		local eyePos = dir * r * 0.9
		attach(model, core, ball("Eye", r * 0.28, eyeColor, eyeMaterial), CFrame.new(eyePos), false)
		attach(
			model,
			core,
			ball("Shine", r * 0.1, WHITE, NEON),
			CFrame.new(eyePos + Vector3.new(0.04 * r, 0.06 * r, -0.11 * r)),
			false
		)
		attach(
			model,
			core,
			ellipsoid("Blush", Vector3.new(0.24 * r, 0.12 * r, 0.06 * r), Color3.fromRGB(255, 120, 150), SMOOTH),
			onSurface(Vector3.new(0.6 * side, -0.06, -1), r * 0.96),
			false
		)
	end
	attach(
		model,
		core,
		ellipsoid("Mouth", Vector3.new(0.34 * r, 0.11 * r, 0.06 * r), Color3.fromRGB(60, 25, 35), SMOOTH),
		onSurface(Vector3.new(0, -0.16, -1), r * 0.98),
		false
	)
	for _, name in { "Eye", "Shine", "Blush", "Mouth" } do
		for _, child in model:GetChildren() do
			if child.Name == name then
				child:SetAttribute("Face", true)
			end
		end
	end
end

local function addRing(model: Model, core: BasePart, diameter: number, color: Color3, tilt: number, transparency: number)
	local ring = disc("Ring", diameter, 0.12, color, NEON)
	ring.Transparency = transparency
	attach(model, core, ring, CFrame.Angles(math.rad(tilt), 0, 0) * VERTICAL, true)
end

local function addBands(model: Model, core: BasePart, r: number, count: number, color: Color3, material: Enum.Material)
	local heights: { number } = if count == 1
		then { 0 }
		elseif count == 2 then { 0.38 * r, -0.38 * r }
		else { 0.52 * r, 0, -0.52 * r }
	for _, y in heights do
		local diameter = 2 * math.sqrt(r * r - y * y) * 1.015
		attach(model, core, disc("Band", diameter, 0.16 * r, color, material), CFrame.new(0, y, 0) * VERTICAL, true)
	end
end

local function addSpots(model: Model, core: BasePart, r: number, color: Color3, dirs: { Vector3 }, size: Vector3)
	for _, dir in dirs do
		attach(model, core, ellipsoid("Spot", size, color, SMOOTH), onSurface(dir, r * 0.97), true)
	end
end

local function applyMutation(model: Model, core: BasePart, mutation: string)
	if mutation == "None" then
		return
	end
	local def = Mutations.Get(mutation)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Body") == true then
			if mutation == "Gold" then
				descendant.Color = def.Color
				if descendant.Material ~= NEON then
					descendant.Material = Enum.Material.Metal
					descendant.Reflectance = 0.25
				end
			elseif mutation == "Diamond" then
				descendant.Color = def.Color
				if descendant.Material ~= NEON then
					descendant.Material = Enum.Material.Glass
					descendant.Reflectance = 0.3
					descendant.Transparency = math.max(descendant.Transparency, 0.15)
				end
			elseif mutation == "Galaxy" then
				descendant.Color = def.Color
				descendant.Material = Enum.Material.ForceField
			end
		end
	end
	if mutation == "Rainbow" then
		model:SetAttribute("Rainbow", true)
	end
	addParticles(core, def.Color, if mutation == "Gold" then 4 else 8)
end

local function buildCustom(planetId: string, cframe: CFrame): Model?
	local folder = ReplicatedStorage:FindFirstChild("PlanetModels")
	if not folder then
		return nil
	end
	local template = folder:FindFirstChild(planetId)
	if not (template and template:IsA("Model") and template.PrimaryPart) then
		return nil
	end
	local model = template:Clone()
	local core = model.PrimaryPart :: BasePart
	core.Name = "Core"
	model:PivotTo(cframe)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.Anchored = false
			descendant:SetAttribute("Body", true)
			if descendant ~= core then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = core
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end
	return model
end

-- Builds the model at `cframe`. Core is anchored; everything else is welded to it.
function PlanetModel.Build(planetId: string, mutation: string, cframe: CFrame): Model
	local def = Planets.Get(planetId) or Planets.List[1]
	local v = def.Visual
	local size = v.Size
	local r = size / 2
	local secondary = v.Secondary or v.Color
	local material = v.Material or SMOOTH
	local kind = v.Kind

	local model: Model
	local core: BasePart
	local custom = buildCustom(def.Id, cframe)
	if custom then
		model = custom
		core = custom.PrimaryPart :: BasePart
	else
		local newModel = Instance.new("Model")
		newModel.Name = def.Name
		model = newModel

		local coreMaterial = material
		local coreColor = v.Color
		local coreSize = size
		local coreTransparency = 0
		if kind == "Star" or kind == "Pulsar" or kind == "BlackHole" or kind == "Quasar" then
			coreMaterial = NEON
		elseif kind == "Galaxy" then
			coreMaterial = NEON
			coreColor = WHITE
			coreSize = size * 0.35
		elseif kind == "Nebula" then
			coreMaterial = NEON
			coreSize = size * 0.6
			coreTransparency = 0.35
		elseif kind == "Multiverse" then
			coreMaterial = NEON
			coreSize = size * 0.55
		elseif kind == "Wormhole" then
			coreSize = size * 0.9
			coreTransparency = 1
		end

		local corePart = ball("Core", coreSize, coreColor, coreMaterial)
		corePart.Transparency = coreTransparency
		corePart.CFrame = cframe
		corePart:SetAttribute("Body", coreTransparency < 1)
		corePart.Parent = newModel
		core = corePart

		if kind == "Asteroid" then
			for _, info in
				{
					{ Vector3.new(0.62, 0.42, 0.38), 0.58 },
					{ Vector3.new(-0.66, -0.3, 0.42), 0.52 },
					{ Vector3.new(0.12, -0.62, 0.55), 0.46 },
				} :: { { any } }
			do
				local offset = info[1] :: Vector3
				local scale = info[2] :: number
				attach(newModel, core, ball("Bump", r * scale * 2, v.Color, material), CFrame.new(offset * r), true)
			end
			addFace(newModel, core, r, BLACK, SMOOTH)
		elseif kind == "Moon" then
			addSpots(newModel, core, r, secondary, {
				Vector3.new(0.85, 0.35, -0.35),
				Vector3.new(-0.8, 0.45, -0.3),
				Vector3.new(0.45, -0.75, 0.4),
				Vector3.new(-0.3, 0.6, 0.7),
				Vector3.new(0.1, 0.15, 1),
				Vector3.new(-0.9, -0.4, 0.2),
			}, Vector3.new(0.45 * r, 0.45 * r, 0.08 * r))
			addFace(newModel, core, r, BLACK, SMOOTH)
		elseif kind == "Planet" then
			if v.Bands then
				addBands(newModel, core, r, v.Bands, secondary, if material == Enum.Material.CrackedLava then NEON else SMOOTH)
			end
			if v.Ring then
				addRing(newModel, core, size * 2.1, secondary, v.RingTilt or 15, 0.25)
			end
			addFace(newModel, core, r, BLACK, SMOOTH)
		elseif kind == "Earth" then
			addSpots(newModel, core, r, secondary, {
				Vector3.new(0.9, 0.3, -0.2),
				Vector3.new(-0.85, 0.35, -0.25),
				Vector3.new(0.4, 0.65, 0.6),
				Vector3.new(-0.45, -0.6, 0.6),
				Vector3.new(0.65, -0.5, 0.55),
				Vector3.new(-0.2, 0.3, 0.95),
			}, Vector3.new(0.85 * r, 0.65 * r, 0.12 * r))
			attach(
				newModel,
				core,
				ellipsoid("IceCap", Vector3.new(r, 0.25 * r, r), WHITE, SMOOTH),
				CFrame.new(0, r * 0.9, 0),
				true
			)
			addFace(newModel, core, r, BLACK, SMOOTH)
		elseif kind == "Comet" then
			for i, info in { { 1.1, 0.8, 0.35 }, { 2.0, 0.6, 0.5 }, { 2.8, 0.4, 0.65 } } do
				local tail = ball("Tail" .. i, size * info[2], secondary, NEON)
				tail.Transparency = info[3]
				attach(newModel, core, tail, CFrame.new(0, 0, r * info[1]), true)
			end
			addFace(newModel, core, r, BLACK, SMOOTH)
		elseif kind == "Star" then
			local glow = ball("Glow", size * 1.3, v.Color, NEON)
			glow.Transparency = 0.8
			attach(newModel, core, glow, CFrame.new(), true)
			if v.Ring then
				addRing(newModel, core, size * 2.2, secondary, v.RingTilt or 10, 0.2)
			end
			addLight(core, v.Color, size * 3)
			addFace(newModel, core, r, BLACK, SMOOTH)
		elseif kind == "Pulsar" then
			for _, tilt in { 20, -20 } do
				local beam = disc("Beam", 0.35, size * 3.2, secondary, NEON)
				beam.Transparency = 0.25
				attach(newModel, core, beam, CFrame.Angles(math.rad(tilt), 0, 0) * VERTICAL, true)
			end
			addLight(core, v.Color, size * 3)
			addFace(newModel, core, r, BLACK, SMOOTH)
		elseif kind == "BlackHole" or kind == "Quasar" then
			addRing(newModel, core, size * 2.4, secondary, 15, 0.2)
			local inner = disc("InnerRing", size * 1.6, 0.14, Color3.fromRGB(255, 232, 190), NEON)
			inner.Transparency = 0.35
			attach(newModel, core, inner, CFrame.Angles(math.rad(15), 0, 0) * VERTICAL, true)
			if v.Ring then
				addRing(newModel, core, size * 3, secondary, v.RingTilt or 30, 0.5)
			end
			if kind == "Quasar" then
				local beam = disc("Beam", 0.4, size * 3.4, secondary, NEON)
				beam.Transparency = 0.2
				attach(newModel, core, beam, VERTICAL, true)
			end
			addLight(core, secondary, size * 3)
			addFace(newModel, core, r, WHITE, NEON)
		elseif kind == "Galaxy" then
			local glow = ball("Glow", size * 0.6, WHITE, NEON)
			glow.Transparency = 0.6
			attach(newModel, core, glow, CFrame.new(), true)
			local outer = disc("Arms", size * 1.7, 0.08, v.Color, NEON)
			outer.Transparency = 0.45
			attach(newModel, core, outer, CFrame.Angles(math.rad(20), 0, 0) * VERTICAL, true)
			local innerDisc = disc("InnerArms", size * 1.15, 0.1, secondary, NEON)
			innerDisc.Transparency = 0.3
			attach(newModel, core, innerDisc, CFrame.Angles(math.rad(20), math.rad(15), 0) * VERTICAL, true)
			addLight(core, v.Color, size * 3)
		elseif kind == "Nebula" then
			for i, info in
				{
					{ Vector3.new(0.35, 0.1, 0), 0.55, secondary, 0.45 },
					{ Vector3.new(-0.3, -0.12, 0.15), 0.5, Color3.fromRGB(200, 120, 255), 0.45 },
					{ Vector3.new(0.05, 0.3, -0.1), 0.45, v.Color, 0.5 },
					{ Vector3.new(-0.05, -0.32, -0.15), 0.4, secondary, 0.5 },
				} :: { { any } }
			do
				local cloud = ball("Cloud" .. i, size * (info[2] :: number), info[3] :: Color3, NEON)
				cloud.Transparency = info[4] :: number
				attach(newModel, core, cloud, CFrame.new((info[1] :: Vector3) * size), true)
			end
			addLight(core, v.Color, size * 3)
		elseif kind == "Wormhole" then
			local facing = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> Z (faces the front)
			attach(newModel, core, disc("Hole", size * 0.8, 0.3, secondary, NEON), facing, true)
			local ring1 = disc("Ring1", size * 1.05, 0.25, v.Color, NEON)
			ring1.Transparency = 0.1
			attach(newModel, core, ring1, CFrame.new(0, 0, 0.06) * facing, true)
			local ring2 = disc("Ring2", size * 1.3, 0.2, v.Color, NEON)
			ring2.Transparency = 0.55
			attach(newModel, core, ring2, CFrame.new(0, 0, 0.12) * facing, true)
			addLight(core, v.Color, size * 3)
		elseif kind == "Multiverse" then
			local colors = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 255, 140), Color3.fromRGB(90, 140, 255) }
			for i = 1, 3 do
				local angle = math.rad((i - 1) * 120)
				local offset = Vector3.new(math.cos(angle) * size * 0.7, (i - 2) * size * 0.12, math.sin(angle) * size * 0.7)
				attach(newModel, core, ball("Universe" .. i, size * 0.25, colors[i], NEON), CFrame.new(offset), true)
			end
			addRing(newModel, core, size * 1.7, WHITE, 15, 0.4)
			addLight(core, WHITE, size * 3)
		end

		if v.Particles then
			addParticles(core, if kind == "BlackHole" or kind == "Quasar" then secondary else v.Color, 6)
		end
		if v.Rainbow then
			newModel:SetAttribute("Rainbow", true)
		end
	end

	core.Anchored = true
	model.PrimaryPart = core
	applyMutation(model, core, mutation)
	model:SetAttribute("PlanetId", def.Id)
	model:SetAttribute("Mutation", mutation)
	return model
end

-- Info label floating above a planet. mode: "Belt" shows the price too.
function PlanetModel.CreateTag(planetId: string, mutation: string, mode: string): BillboardGui
	local def = Planets.Get(planetId) or Planets.List[1]
	local rarity = Planets.Rarity(def.Rarity)
	local mutationDef = Mutations.Get(mutation)

	local rows: { { name: string, text: string, color: Color3, gradient: boolean } } = {}
	if mutation ~= "None" then
		table.insert(rows, { name = "Mutation", text = mutationDef.Name, color = mutationDef.Color, gradient = mutation == "Rainbow" })
	end
	table.insert(rows, { name = "Title", text = def.Name, color = WHITE, gradient = false })
	table.insert(rows, {
		name = "Rarity",
		text = string.upper(def.Rarity),
		color = rarity.Color,
		gradient = rarity.Gradient == true,
	})
	table.insert(rows, {
		name = "Income",
		text = Format.PerSecond(Economy.PlanetIncome(def, mutation)),
		color = Color3.fromRGB(110, 255, 130),
		gradient = false,
	})
	if mode == "Belt" then
		table.insert(rows, {
			name = "Price",
			text = Format.Cash(Economy.PlanetPrice(def, mutation)),
			color = Color3.fromRGB(255, 215, 70),
			gradient = false,
		})
	end

	local rowHeight = 0.8
	local gui = Instance.new("BillboardGui")
	gui.Name = "InfoTag"
	gui.Size = UDim2.new(7, 0, #rows * rowHeight, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, def.Visual.Size * 0.5 + 0.8 + #rows * rowHeight * 0.5, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = if mode == "Belt" then 90 else 60

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = gui

	for i, row in rows do
		local label = Instance.new("TextLabel")
		label.Name = row.name
		label.LayoutOrder = i
		label.Size = UDim2.fromScale(1, 1 / #rows)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = row.text
		label.TextScaled = true
		label.TextColor3 = if row.gradient then WHITE else row.color
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(20, 10, 35)
		label.Parent = gui
		if row.gradient then
			local gradient = Instance.new("UIGradient")
			gradient.Color = PlanetModel.RainbowSequence()
			gradient.Parent = label
		end
	end
	return gui
end

return PlanetModel
