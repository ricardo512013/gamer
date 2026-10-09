--!strict
--[[
	MapGen — gera o "Morro do Vento" (GDD §4) inteiro no início do servidor, só com Terrain e Parts
	(nenhum asset externo). Determinístico: Random.new(Config.SEED) → todo servidor tem o mesmo mapa.

	O que constrói (tudo Anchored, agrupado em workspace/Map):
	- Terreno: disco verde r 200, degrau 2 (y 12), centro escavado (y 0), rua de asfalto, água em volta.
	- Campinho (Part Ground + 5 linhas + círculo central + 2 traves), SpawnLocation, 4 rampas.
	- Bar do Vento (corpo, balcão com tag Bar + ProximityPrompt "Ver estoque", toldo, placa SurfaceGui).
	- Poste do Ranking (Part tag Poste + placa; SurfaceGui "Ranking" na face −Z, que o Leaderboard preenche).
	- Árvore do Campinho (tronco tag Tree, 3 copas, TrussPart para subir).
	- 12 lajes: Model "Laje_i" com tag Laje e Attributes Index / OwnerId (0 = livre) / Angle (rad) /
	  VaralCodes (escrito pelo KiteService). Dentro: casa pastel, piso "Floor", muretas (Neon para VIP),
	  caixa-d'água, carretel (tag Carretel, Attribute LajeIndex, ProximityPrompt "PEGAR VENTO"), varal, porta,
	  janelas Neon e TrussPart da rua até o piso.
	- 36 casas de enfeite + igrejinha no morro, 4 paredes invisíveis em r 210.
	- Luz (§4.4) e os contêineres de runtime: workspace/KiteStates (Folder) e workspace/World (Configuration).

	API: MapGen.start() (idempotente: destrói workspace.Map antes), lajeModel(i), lajeFloor(i),
	carretelPos(i), lajeAngle(i). Depende SÓ de Config — nunca de outro serviço.
	As medidas do §4 que não estão no bloco Config do §7.5 vivem na tabela GEO abaixo.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MapGen = {}

-- Paleta (GDD §1) ------------------------------------------------------------------------------

local PAL = {
	Pipa = Color3.fromRGB(235, 60, 50),
	Sol = Color3.fromRGB(255, 205, 60),
	Morro = Color3.fromRGB(95, 185, 90),
	Terra = Color3.fromRGB(150, 105, 60),
	Asfalto = Color3.fromRGB(60, 60, 65),
	Laje = Color3.fromRGB(255, 140, 60),
	Lilas = Color3.fromRGB(170, 130, 230),
	Branco = Color3.fromRGB(245, 245, 245),
	UIFundo = Color3.fromRGB(30, 30, 45),
	UITexto = Color3.fromRGB(255, 255, 255),
	Contorno = Color3.fromRGB(20, 20, 30),
	Cinza = Color3.fromRGB(120, 120, 130),
	Agua = Color3.fromRGB(60, 140, 255),
	Madeira = Color3.fromRGB(120, 80, 45),
	Porta = Color3.fromRGB(70, 45, 35),
	Janela = Color3.fromRGB(255, 245, 180), -- Neon: luz acesa
	Folha = Color3.fromRGB(70, 160, 75),
}

-- 12 cores pastel (uma por laje; as casas de enfeite sorteiam entre elas).
local PASTEL: { Color3 } = {}
for i = 1, 12 do
	PASTEL[i] = Color3.fromHSV((i - 1) / 12, 0.38, 1)
end

-- Geometria do mapa (GDD §4, em studs). Só o que o bloco Config (§7.5) não cobre. --------------------

local GEO = {
	-- §4.1 terreno
	BASE_TOP = 24, -- disco verde: topo em y 24
	BASE_BOTTOM = -12, -- (impl.) o disco desce até o fundo da água para o centro escavado ficar em grama
	STEP2_Y = 12, -- degrau 2 (r 90–150)
	STEP2_R = 150,
	CENTER_R = 90, -- centro escavado até y 0
	ROAD_R_OUT = 105,
	ROAD_R_IN = 95,
	ROAD_THICK = 4, -- (impl.) 1 voxel de terreno (y 8–12), alinhado ao grid: sem lascas de meio-voxel
	WATER_SIZE = 1200,
	WATER_DEPTH = 12,
	WALL_R = 210,
	WALL_LEN = 420,
	WALL_H = 60,
	WALL_T = 1,
	RAMP_SIZE = Vector3.new(16, 12, 24),
	RAMP_R = 78,
	RAMP_ANGLES = { 45, 135, 225, 315 },
	-- §4.2 campinho / spawn
	FIELD_Y = 0.5,
	LINE_W = 0.3, -- espessura das linhas brancas
	LINE_H = 0.2,
	CIRCLE_R = 8,
	CIRCLE_SEGMENTS = 8,
	GOAL_POST = Vector3.new(0.6, 8, 0.6),
	GOAL_HALF_Z = 6,
	GOAL_BAR = Vector3.new(0.6, 0.6, 12.6),
	GOAL_BAR_Y = 8.2,
	SPAWN_SIZE = Vector3.new(8, 1, 8),
	-- §4.2 Bar do Vento
	BAR_BODY = Vector3.new(16, 10, 12),
	BAR_BODY_POS = Vector3.new(0, 5, -46),
	BAR_COUNTER = Vector3.new(16, 3, 2),
	BAR_AWNING = Vector3.new(2, 0.4, 6),
	BAR_AWNING_Y = 10.5,
	BAR_AWNING_Z = -39,
	BAR_AWNING_N = 8,
	BAR_SIGN = Vector3.new(14, 3, 0.5),
	BAR_SIGN_POS = Vector3.new(0, 8, -39.7),
	-- §4.2 Poste do Ranking (o poste do GDD tem 2 studs de largura: a placa dá área legível ao SurfaceGui)
	POSTE_SIZE = Vector3.new(2, 24, 2),
	POSTE_BOARD = Vector3.new(12, 8, 0.5),
	POSTE_BOARD_OFFSET = Vector3.new(0, 7, 1.3), -- relativo a POSTE_POS, na frente (lado do campinho)
	-- §4.2 Árvore do Campinho
	TREE_TRUNK = Vector3.new(18, 4, 4),
	TREE_TRUNK_POS = Vector3.new(46, 9, 30),
	TREE_BALL = Vector3.new(12, 12, 12),
	TREE_BALLS = { Vector3.new(46, 18, 30), Vector3.new(42, 21, 33), Vector3.new(50, 21, 27) },
	TREE_TRUSS = Vector3.new(2, 18, 2),
	TREE_TRUSS_POS = Vector3.new(43, 9, 30),
	-- §4.2 laje (coordenadas locais: −Z = frente, virada para o centro; X = direita; y = mundial)
	HOUSE = Vector3.new(22, 14, 22),
	HOUSE_Y = 19,
	FLOOR = Vector3.new(24, 1, 24),
	MURETA_H = 2,
	MURETA_T = 1,
	MURETA_Y = 28,
	MURETA_HALF = 11.5,
	GATE_W = 4, -- (impl.) vão na mureta da frente, onde a escada chega
	TANK = Vector3.new(5, 5, 5),
	TANK_LOCAL = Vector3.new(-8, 29.5, 8), -- canto traseiro-esquerdo
	CARRETEL = Vector3.new(2, 3, 3),
	CARRETEL_LOCAL = Vector3.new(-6, 28.5, -9.5), -- borda frontal, ao lado do vão
	CARRETEL_PROMPT_DIST = 10, -- ≤ Config.COLLECT_DIST (o servidor revalida a distância)
	VARAL_POST = Vector3.new(0.4, 4, 0.4),
	VARAL_LINE = Vector3.new(16, 0.2, 0.2), -- 16 studs ao longo do X local: 8 vagas a cada 2 studs
	VARAL_Y = 30,
	VARAL_Z = 3,
	VARAL_HALF = 8,
	DOOR = Vector3.new(4, 7, 0.3),
	DOOR_Y = 15.5,
	WINDOW = Vector3.new(3, 3, 0.3),
	WINDOW_X = 6,
	WINDOW_Y = 20,
	FACADE_Z = -11.15, -- porta/janelas encostadas na frente da casa
	TRUSS = Vector3.new(2, 15, 2), -- da rua (y 12) ao topo do piso (y 27)
	TRUSS_LOCAL = Vector3.new(0, 19.5, -13),
	-- §4.2 casas de enfeite e igrejinha
	HILL_Y = 24,
	DECO_COUNT = 36,
	DECO_R = { 160, 190 },
	DECO_SX = { 8, 16 },
	DECO_SY = { 8, 14 },
	DECO_SZ = { 8, 16 },
	DECO_ARC_START = 30, -- os 36 enfeites ocupam 30°..360°; 0°..30° fica para a igrejinha
	DECO_JITTER = 1.5, -- ± graus
	DECO_WINDOW = Vector3.new(2, 2, 0.3),
	CHURCH_ANGLE = 15,
	CHURCH_R = 175,
	CHURCH = Vector3.new(14, 18, 14),
	TOWER = Vector3.new(6, 26, 6),
	TOWER_X = 10, -- ao lado direito do corpo
	CROSS_V = Vector3.new(0.6, 4, 0.6),
	CROSS_H = Vector3.new(2.4, 0.6, 0.6),
	-- placas
	SIGN_PPS = 40, -- PixelsPerStud dos SurfaceGui
}

-- Luz (GDD §4.4)
local LIGHT = {
	ClockTime = 16.5,
	Brightness = 2,
	OutdoorAmbient = Color3.fromRGB(140, 160, 190),
	Density = 0.25,
	Haze = 1.0,
	Glare = 0.1,
}

-- Atributos iniciais de workspace/World (GDD §7.4)
local WORLD_DEFAULTS: { [string]: any } = {
	WindSign = 1,
	EventName = "",
	EventPhase = "",
	EventEndsAt = 0,
	Festival = false,
	RestockAt = 0,
	BoostRajadaUntil = 0,
	BoostVentoUntil = 0,
	BoostBy = "",
}

-- Estado interno ---------------------------------------------------------------------------------

local built = false
local partCount = 0
local lajes: { [number]: Model } = {}
local carretels: { [number]: Vector3 } = {}
local muretasOf: { [number]: { Part } } = {}
local connections: { RBXScriptConnection } = {}
local vipConnections: { [Player]: RBXScriptConnection } = {}

-- Ajudantes de construção ------------------------------------------------------------------------

type PartOpts = { shape: Enum.PartType?, material: Enum.Material?, collide: boolean?, transparency: number? }

-- Part Anchored, SmoothPlastic por padrão. O Parent é um Model/Folder ainda fora do workspace:
-- o mapa inteiro replica de uma vez quando workspace/Map é parentado no fim de start().
local function newPart(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance, opts: PartOpts?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if opts and opts.material then opts.material else Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts then
		if opts.shape then
			p.Shape = opts.shape
		end
		if opts.collide ~= nil then
			p.CanCollide = opts.collide
		end
		if opts.transparency then
			p.Transparency = opts.transparency
		end
	end
	partCount += 1
	p.Parent = parent
	return p
end

local function newWedge(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	partCount += 1
	w.Parent = parent
	return w
end

local function newTruss(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): TrussPart
	local t = Instance.new("TrussPart")
	t.Name = name
	t.Anchored = true
	t.Size = size
	t.CFrame = cf
	t.Color = color
	t.Material = Enum.Material.SmoothPlastic
	partCount += 1
	t.Parent = parent
	return t
end

local function newModel(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	return m
end

-- SurfaceGui de texto (sem imagens). face Front = −Z do adornee.
local function newSign(parent: BasePart, adornee: BasePart?, name: string): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = GEO.SIGN_PPS
	gui.LightInfluence = 0
	if adornee then
		gui.Adornee = adornee
	end
	gui.Parent = parent
	return gui
end

local function newLabel(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = pos
	label.Size = size
	label.Font = font
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = PAL.Contorno
	stroke.Parent = label
	label.Parent = parent
	return label
end

-- Cilindro em pé: o eixo de um Cylinder é o X local; girar 90° em Z põe o eixo na vertical.
local function upright(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.pi / 2)
end

-- Referencial virado para o centro do mapa (−Z aponta para (0, y, 0)); sem inclinação.
local function facingCenter(pos: Vector3): CFrame
	return CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
end

-- Part girada 180° em Y: a face Front (−Z) passa a olhar para +Z (lado do campinho, para quem está ao sul).
local function facingNorth(pos: Vector3): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, math.pi, 0)
end

local function ptBR(key: string): string
	return Config.str(key, "pt-BR")
end

-- Geometria das lajes ----------------------------------------------------------------------------

-- Ângulo (rad) da laje i: (i-1) × 360°/LAJE_COUNT.
function MapGen.lajeAngle(i: number): number
	return (i - 1) * (2 * math.pi / Config.LAJE_COUNT)
end

-- Referencial da laje i: origem em (R·cos, 0, R·sin), −Z para o centro, y mundial.
local function lajeFrame(i: number): CFrame
	local a = MapGen.lajeAngle(i)
	return facingCenter(Vector3.new(Config.LAJE_RADIUS * math.cos(a), 0, Config.LAJE_RADIUS * math.sin(a)))
end

-- Centro do piso da laje i (y = LAJE_FLOOR_Y).
function MapGen.lajeFloor(i: number): Vector3
	local a = MapGen.lajeAngle(i)
	return Vector3.new(Config.LAJE_RADIUS * math.cos(a), Config.LAJE_FLOOR_Y, Config.LAJE_RADIUS * math.sin(a))
end

-- Terreno (§4.1) ---------------------------------------------------------------------------------

local function buildTerrain()
	local terrain = Workspace.Terrain
	terrain:Clear()
	-- água em volta do mundo (y −12 → 0)
	terrain:FillBlock(CFrame.new(0, -GEO.WATER_DEPTH / 2, 0), Vector3.new(GEO.WATER_SIZE, GEO.WATER_DEPTH, GEO.WATER_SIZE), Enum.Material.Water)
	-- disco verde r 200: do fundo da água até y 24 (assim o centro escavado fica em grama, não em água)
	local baseH = GEO.BASE_TOP - GEO.BASE_BOTTOM
	terrain:FillCylinder(CFrame.new(0, GEO.BASE_BOTTOM + baseH / 2, 0), baseH, Config.MAP_RADIUS, Enum.Material.Grass)
	-- rua de asfalto: anel r 95–105 cujo topo é a superfície do degrau 2 (y 12). Pintada ANTES das
	-- escavações: assim o que cai dentro do centro (r < 90) é removido junto, sem sobrar lasca de voxel.
	local roadY = GEO.STEP2_Y - GEO.ROAD_THICK / 2
	terrain:FillCylinder(CFrame.new(0, roadY, 0), GEO.ROAD_THICK, GEO.ROAD_R_OUT, Enum.Material.Asphalt)
	terrain:FillCylinder(CFrame.new(0, roadY, 0), GEO.ROAD_THICK, GEO.ROAD_R_IN, Enum.Material.Grass)
	-- degrau 2 (r < 150 desce para y 12) e centro (r < 90 desce para y 0)
	local step2H = GEO.BASE_TOP - GEO.STEP2_Y
	terrain:FillCylinder(CFrame.new(0, GEO.STEP2_Y + step2H / 2, 0), step2H, GEO.STEP2_R, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(0, GEO.STEP2_Y / 2, 0), GEO.STEP2_Y, GEO.CENTER_R, Enum.Material.Air)
end

-- Campinho, spawn, rampas e paredes (§4.1/§4.2) --------------------------------------------------

local function buildCampinho(folder: Folder)
	local m = newModel("Campinho")
	local sx, sz = Config.CAMPINHO.sizeX, Config.CAMPINHO.sizeZ
	local field = newPart("Campo", Vector3.new(sx, 1, sz), CFrame.new(0, GEO.FIELD_Y, 0), PAL.Terra, m, { material = Enum.Material.Ground })
	m.PrimaryPart = field
	local lineY = GEO.FIELD_Y + 0.5 + GEO.LINE_H / 2
	local lineOpts: PartOpts = { collide = false }
	-- 2 laterais (ao longo de X), 2 fundos (ao longo de Z) e a linha do meio
	for _, s in { -1, 1 } do
		newPart("Lateral", Vector3.new(sx, GEO.LINE_H, GEO.LINE_W), CFrame.new(0, lineY, s * (sz / 2 - GEO.LINE_W / 2)), PAL.Branco, m, lineOpts)
		newPart("Fundo", Vector3.new(GEO.LINE_W, GEO.LINE_H, sz), CFrame.new(s * (sx / 2 - GEO.LINE_W / 2), lineY, 0), PAL.Branco, m, lineOpts)
	end
	newPart("Meio", Vector3.new(GEO.LINE_W, GEO.LINE_H, sz), CFrame.new(0, lineY, 0), PAL.Branco, m, lineOpts)
	-- círculo central: polígono de CIRCLE_SEGMENTS segmentos
	local segLen = 2 * GEO.CIRCLE_R * math.sin(math.pi / GEO.CIRCLE_SEGMENTS)
	for k = 0, GEO.CIRCLE_SEGMENTS - 1 do
		local a = (k + 0.5) * (2 * math.pi / GEO.CIRCLE_SEGMENTS)
		local center = Vector3.new(GEO.CIRCLE_R * math.cos(a), lineY, GEO.CIRCLE_R * math.sin(a))
		newPart("Circulo", Vector3.new(segLen, GEO.LINE_H, GEO.LINE_W), facingCenter(center), PAL.Branco, m, lineOpts)
	end
	-- 2 traves: postes em x = ±sx/2, z = ±GOAL_HALF_Z + travessão
	local postY = GEO.FIELD_Y + GEO.GOAL_POST.Y / 2
	for _, s in { -1, 1 } do
		local x = s * sx / 2
		for _, zs in { -1, 1 } do
			newPart("Trave", GEO.GOAL_POST, CFrame.new(x, postY, zs * GEO.GOAL_HALF_Z), PAL.Branco, m)
		end
		newPart("Travessao", GEO.GOAL_BAR, CFrame.new(x, GEO.GOAL_BAR_Y, 0), PAL.Branco, m)
	end
	m.Parent = folder
end

local function buildSpawn(folder: Folder)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = GEO.SPAWN_SIZE
	spawn.CFrame = CFrame.new(Config.SPAWN_POS)
	spawn.Color = PAL.Laje
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.AllowTeamChangeOnTouch = false
	partCount += 1
	spawn.Parent = folder
end

-- 4 rampas campinho ↔ degrau 2: a borda fina do WedgePart (face Front) olha para o centro.
local function buildRampas(folder: Folder)
	local m = newModel("Rampas")
	for _, deg in GEO.RAMP_ANGLES do
		local a = math.rad(deg)
		local pos = Vector3.new(GEO.RAMP_R * math.cos(a), GEO.RAMP_SIZE.Y / 2, GEO.RAMP_R * math.sin(a))
		newWedge(`Rampa_{deg}`, GEO.RAMP_SIZE, facingCenter(pos), PAL.Morro, Enum.Material.Grass, m)
	end
	m.Parent = folder
end

-- 4 paredes invisíveis em r 210 (CanCollide; a água fica do lado de fora).
local function buildParedes(folder: Folder)
	local m = newModel("Paredes")
	local opts: PartOpts = { transparency = 1, collide = true }
	local y = GEO.WALL_H / 2
	local alongZ = Vector3.new(GEO.WALL_T, GEO.WALL_H, GEO.WALL_LEN) -- 1 × 60 × 420
	local alongX = Vector3.new(GEO.WALL_LEN, GEO.WALL_H, GEO.WALL_T)
	for _, s in { -1, 1 } do
		newPart("Parede", alongZ, CFrame.new(s * GEO.WALL_R, y, 0), PAL.Cinza, m, opts)
		newPart("Parede", alongX, CFrame.new(0, y, s * GEO.WALL_R), PAL.Cinza, m, opts)
	end
	m.Parent = folder
end

-- Bar do Vento, Poste e Árvore (§4.2) ------------------------------------------------------------

local function buildBar(folder: Folder)
	local m = newModel("Bar")
	newPart("Corpo", GEO.BAR_BODY, CFrame.new(GEO.BAR_BODY_POS), PAL.Sol, m)
	-- balcão: tag Bar + prompt "Ver estoque" (ShopService valida a distância SHOP_DIST no servidor)
	local counter = newPart("Balcao", GEO.BAR_COUNTER, CFrame.new(Config.BAR_POS), PAL.Madeira, m)
	counter:AddTag("Bar")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VerEstoque"
	prompt.ActionText = ptBR("promptStock")
	prompt.ObjectText = ptBR("bar")
	prompt.MaxActivationDistance = Config.SHOP_OPEN_DIST
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	-- toldo: faixas alternando vermelho/branco
	local x0 = -(GEO.BAR_AWNING_N - 1) * GEO.BAR_AWNING.X / 2
	for k = 0, GEO.BAR_AWNING_N - 1 do
		local color = if k % 2 == 0 then PAL.Pipa else PAL.Branco
		newPart("Toldo", GEO.BAR_AWNING, CFrame.new(x0 + k * GEO.BAR_AWNING.X, GEO.BAR_AWNING_Y, GEO.BAR_AWNING_Z), color, m)
	end
	-- placa "BAR DO VENTO" virada para o campinho
	local sign = newPart("Placa", GEO.BAR_SIGN, facingNorth(GEO.BAR_SIGN_POS), PAL.UIFundo, m)
	local gui = newSign(sign, nil, "Texto")
	newLabel(gui, "Titulo", ptBR("bar"), UDim2.fromScale(0.03, 0.1), UDim2.fromScale(0.94, 0.8), PAL.UITexto, Enum.Font.GothamBlack)
	m.Parent = folder
end

-- Poste do Ranking: Part 2×24×2 (tag Poste) + placa na frente. O SurfaceGui "Ranking" fica como filho do
-- Part com a tag (Adornee = placa, face −Z): o Leaderboard preenche Rei.Text e Tesoura.Text.
local function buildPoste(folder: Folder)
	local m = newModel("Poste")
	local pole = newPart("Poste", GEO.POSTE_SIZE, facingNorth(Config.POSTE_POS), PAL.Cinza, m)
	pole:AddTag("Poste")
	local board = newPart("Placa", GEO.POSTE_BOARD, facingNorth(Config.POSTE_POS + GEO.POSTE_BOARD_OFFSET), PAL.UIFundo, m)
	local gui = newSign(pole, board, "Ranking")
	newLabel(gui, "Titulo", ptBR("rankingTitle"), UDim2.fromScale(0.02, 0.02), UDim2.fromScale(0.96, 0.16), PAL.Sol, Enum.Font.GothamBlack)
	newLabel(gui, "ReiTitulo", ptBR("rankingKing"), UDim2.fromScale(0.02, 0.2), UDim2.fromScale(0.47, 0.1), PAL.UITexto, Enum.Font.GothamBlack)
	newLabel(gui, "TesouraTitulo", ptBR("rankingScissors"), UDim2.fromScale(0.51, 0.2), UDim2.fromScale(0.47, 0.1), PAL.UITexto, Enum.Font.GothamBlack)
	local columns: { { name: string, x: number } } = { { name = "Rei", x = 0.02 }, { name = "Tesoura", x = 0.51 } }
	for _, col in columns do
		local list = newLabel(gui, col.name, "—", UDim2.fromScale(col.x, 0.32), UDim2.fromScale(0.47, 0.66), PAL.UITexto, Enum.Font.GothamBold)
		list.TextXAlignment = Enum.TextXAlignment.Left
		list.TextYAlignment = Enum.TextYAlignment.Top
	end
	m.Parent = folder
end

local function buildArvore(folder: Folder)
	local m = newModel("Arvore")
	local trunk = newPart("Tronco", GEO.TREE_TRUNK, upright(CFrame.new(GEO.TREE_TRUNK_POS)), PAL.Madeira, m, { shape = Enum.PartType.Cylinder, material = Enum.Material.Wood })
	trunk:AddTag("Tree")
	trunk:SetAttribute("Top", Config.TREE_TOP)
	m.PrimaryPart = trunk
	for k, pos in GEO.TREE_BALLS do
		newPart(`Copa_{k}`, GEO.TREE_BALL, CFrame.new(pos), PAL.Folha, m, { shape = Enum.PartType.Ball })
	end
	newTruss("Escada", GEO.TREE_TRUSS, CFrame.new(GEO.TREE_TRUSS_POS), PAL.Madeira, m)
	m.Parent = folder
end

-- Lajes (§4.2) -----------------------------------------------------------------------------------

local function buildLaje(i: number, folder: Folder)
	local frame = lajeFrame(i)
	local m = newModel(`Laje_{i}`)
	m:SetAttribute("Index", i)
	m:SetAttribute("OwnerId", 0)
	m:SetAttribute("Angle", MapGen.lajeAngle(i))
	m:SetAttribute("VaralCodes", "")
	m:AddTag("Laje")

	newPart("Casa", GEO.HOUSE, frame * CFrame.new(0, GEO.HOUSE_Y, 0), PASTEL[i], m)
	local floor = newPart("Floor", GEO.FLOOR, frame * CFrame.new(0, Config.LAJE_FLOOR_Y, 0), PAL.Laje, m)
	m.PrimaryPart = floor

	-- muretas: fundo, 2 laterais e a da frente em 2 pedaços (vão GATE_W onde a escada chega)
	local muretas: { Part } = {}
	local full = GEO.FLOOR.X
	local half = GEO.MURETA_HALF
	local segLen = (full - GEO.GATE_W) / 2
	local segX = GEO.GATE_W / 2 + segLen / 2
	local function mureta(name: string, size: Vector3, offset: Vector3)
		table.insert(muretas, newPart(name, size, frame * CFrame.new(offset), PAL.Laje, m))
	end
	mureta("MuretaFundo", Vector3.new(full, GEO.MURETA_H, GEO.MURETA_T), Vector3.new(0, GEO.MURETA_Y, half))
	mureta("MuretaEsq", Vector3.new(GEO.MURETA_T, GEO.MURETA_H, full), Vector3.new(-half, GEO.MURETA_Y, 0))
	mureta("MuretaDir", Vector3.new(GEO.MURETA_T, GEO.MURETA_H, full), Vector3.new(half, GEO.MURETA_Y, 0))
	mureta("MuretaFrenteEsq", Vector3.new(segLen, GEO.MURETA_H, GEO.MURETA_T), Vector3.new(-segX, GEO.MURETA_Y, -half))
	mureta("MuretaFrenteDir", Vector3.new(segLen, GEO.MURETA_H, GEO.MURETA_T), Vector3.new(segX, GEO.MURETA_Y, -half))
	muretasOf[i] = muretas

	newPart("CaixaDagua", GEO.TANK, upright(frame * CFrame.new(GEO.TANK_LOCAL)), PAL.Agua, m, { shape = Enum.PartType.Cylinder })

	-- carretel: tag Carretel + LajeIndex + prompt (parentado ANTES de o Part entrar no workspace)
	local carretelCF = frame * CFrame.new(GEO.CARRETEL_LOCAL)
	local carretel = newPart("Carretel", GEO.CARRETEL, carretelCF, PAL.Laje, m, { shape = Enum.PartType.Cylinder })
	carretel:AddTag("Carretel")
	carretel:SetAttribute("LajeIndex", i)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PegarVento"
	prompt.ActionText = ptBR("collect")
	prompt.ObjectText = ptBR("reel")
	prompt.MaxActivationDistance = GEO.CARRETEL_PROMPT_DIST
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = carretel
	carretels[i] = carretelCF.Position

	-- varal: 2 postes + linha de 16 studs ao longo do X local (o cliente pendura as miniaturas)
	local postY = Config.LAJE_FLOOR_Y + GEO.FLOOR.Y / 2 + GEO.VARAL_POST.Y / 2
	for _, s in { -1, 1 } do
		newPart("VaralPoste", GEO.VARAL_POST, frame * CFrame.new(s * GEO.VARAL_HALF, postY, GEO.VARAL_Z), PAL.Cinza, m)
	end
	newPart("Varal", GEO.VARAL_LINE, frame * CFrame.new(0, GEO.VARAL_Y, GEO.VARAL_Z), PAL.Branco, m, { collide = false })

	-- fachada: porta e 2 janelas Neon
	newPart("Porta", GEO.DOOR, frame * CFrame.new(0, GEO.DOOR_Y, GEO.FACADE_Z), PAL.Porta, m)
	for _, s in { -1, 1 } do
		newPart("Janela", GEO.WINDOW, frame * CFrame.new(s * GEO.WINDOW_X, GEO.WINDOW_Y, GEO.FACADE_Z), PAL.Janela, m, { material = Enum.Material.Neon })
	end

	-- escada da rua (y 12) ao piso (y 27), na frente, no vão da mureta
	newTruss("Escada", GEO.TRUSS, frame * CFrame.new(GEO.TRUSS_LOCAL), PAL.Cinza, m)

	lajes[i] = m
	m.Parent = folder
end

-- Casas de enfeite e igrejinha (§4.2) ------------------------------------------------------------

local function buildEnfeites(folder: Folder, rng: Random)
	local m = newModel("Enfeites")
	local step = (360 - GEO.DECO_ARC_START) / GEO.DECO_COUNT
	for k = 1, GEO.DECO_COUNT do
		local deg = GEO.DECO_ARC_START + (k - 0.5) * step + rng:NextNumber(-GEO.DECO_JITTER, GEO.DECO_JITTER)
		local r = rng:NextNumber(GEO.DECO_R[1], GEO.DECO_R[2])
		local size = Vector3.new(rng:NextInteger(GEO.DECO_SX[1], GEO.DECO_SX[2]), rng:NextInteger(GEO.DECO_SY[1], GEO.DECO_SY[2]), rng:NextInteger(GEO.DECO_SZ[1], GEO.DECO_SZ[2]))
		local color = PASTEL[rng:NextInteger(1, #PASTEL)]
		local a = math.rad(deg)
		local frame = facingCenter(Vector3.new(r * math.cos(a), GEO.HILL_Y + size.Y / 2, r * math.sin(a)))
		newPart(`Casa_{k}`, size, frame, color, m)
		for _, s in { -1, 1 } do
			local offset = Vector3.new(s * size.X / 4, size.Y / 6, -(size.Z / 2 + GEO.DECO_WINDOW.Z / 2))
			newPart("Janela", GEO.DECO_WINDOW, frame * CFrame.new(offset), PAL.Janela, m, { material = Enum.Material.Neon })
		end
	end
	-- igrejinha branca com torre e cruz
	local a = math.rad(GEO.CHURCH_ANGLE)
	local base = Vector3.new(GEO.CHURCH_R * math.cos(a), 0, GEO.CHURCH_R * math.sin(a))
	local frame = facingCenter(base)
	newPart("Igreja", GEO.CHURCH, frame * CFrame.new(0, GEO.HILL_Y + GEO.CHURCH.Y / 2, 0), PAL.Branco, m)
	newPart("Torre", GEO.TOWER, frame * CFrame.new(GEO.TOWER_X, GEO.HILL_Y + GEO.TOWER.Y / 2, 0), PAL.Branco, m)
	local towerTop = GEO.HILL_Y + GEO.TOWER.Y
	newPart("Cruz", GEO.CROSS_V, frame * CFrame.new(GEO.TOWER_X, towerTop + GEO.CROSS_V.Y / 2, 0), PAL.Sol, m)
	newPart("Cruz", GEO.CROSS_H, frame * CFrame.new(GEO.TOWER_X, towerTop + GEO.CROSS_V.Y * 0.7, 0), PAL.Sol, m)
	m.Parent = folder
end

-- Luz e contêineres de runtime -------------------------------------------------------------------

local function setupLighting()
	Lighting.ClockTime = LIGHT.ClockTime
	Lighting.Brightness = LIGHT.Brightness
	Lighting.GlobalShadows = false
	Lighting.OutdoorAmbient = LIGHT.OutdoorAmbient
	pcall(function() -- cartoon; o Rojo 7.4.4 não conhece a propriedade, por isso é aplicada aqui
		Lighting.LightingStyle = Enum.LightingStyle.Soft
	end)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = LIGHT.Density
	atmo.Haze = LIGHT.Haze
	atmo.Glare = LIGHT.Glare
	atmo.Parent = Lighting
end

local function ensureFolder(name: string): Folder
	local existing = Workspace:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	return folder
end

-- workspace/World: cria se não existe; garante cada atributo sem apagar valores já escritos pelos serviços.
local function ensureWorld(): Configuration
	local existing = Workspace:FindFirstChild("World")
	local world: Configuration
	if existing and existing:IsA("Configuration") then
		world = existing
	else
		world = Instance.new("Configuration")
		world.Name = "World"
	end
	for key, value in WORLD_DEFAULTS do
		if world:GetAttribute(key) == nil then
			world:SetAttribute(key, value)
		end
	end
	world.Parent = Workspace
	return world
end

-- Muretas Neon do VIP (lê o atributo VIP do Player; nunca requer MonetizationService) --------------

local function refreshMuretas(i: number)
	local model = lajes[i]
	local parts = muretasOf[i]
	if not model or not parts then
		return
	end
	local raw = model:GetAttribute("OwnerId")
	local ownerId: number = if typeof(raw) == "number" then raw else 0
	local owner = if ownerId > 0 then Players:GetPlayerByUserId(ownerId) else nil
	local vip = owner ~= nil and owner:GetAttribute("VIP") == true
	for _, part in parts do
		part.Material = if vip then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Color = if vip then PAL.Sol else PAL.Laje
	end
end

local function refreshMuretasOf(p: Player)
	for i, model in lajes do
		if model:GetAttribute("OwnerId") == p.UserId then
			refreshMuretas(i)
		end
	end
end

local function watchPlayer(p: Player)
	vipConnections[p] = p:GetAttributeChangedSignal("VIP"):Connect(function()
		refreshMuretasOf(p)
	end)
end

local function forgetPlayer(p: Player)
	local conn = vipConnections[p]
	if conn then
		conn:Disconnect()
		vipConnections[p] = nil
	end
end

local function watchVip()
	for i, model in lajes do
		table.insert(connections, model:GetAttributeChangedSignal("OwnerId"):Connect(function()
			refreshMuretas(i)
		end))
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(forgetPlayer))
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
end

local function disconnectAll()
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)
	for p in vipConnections do
		forgetPlayer(p)
	end
end

-- API pública ------------------------------------------------------------------------------------

-- Gera o mapa inteiro. Idempotente: destrói workspace.Map (e refaz o terreno) antes de gerar de novo.
function MapGen.start(): ()
	local old = Workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	disconnectAll()
	table.clear(lajes)
	table.clear(carretels)
	table.clear(muretasOf)
	partCount = 0

	local rng = Random.new(Config.SEED)
	setupLighting()
	buildTerrain()

	local map = Instance.new("Folder")
	map.Name = "Map"
	buildCampinho(map)
	buildSpawn(map)
	buildBar(map)
	buildPoste(map)
	buildArvore(map)
	local lajesFolder = Instance.new("Folder")
	lajesFolder.Name = "Lajes"
	for i = 1, Config.LAJE_COUNT do
		buildLaje(i, lajesFolder)
	end
	lajesFolder.Parent = map
	buildRampas(map)
	buildEnfeites(map, rng)
	buildParedes(map)
	map.Parent = Workspace -- Parent por último: tudo (prompts inclusive) replica de uma vez

	ensureFolder("KiteStates")
	ensureWorld()
	built = true
	watchVip()
	print(`[MapGen] Morro do Vento gerado: {partCount} Parts, {Config.LAJE_COUNT} lajes`)
end

local function ensureBuilt()
	if not built then
		warn("[MapGen] chamado antes de start(); gerando o mapa agora")
		MapGen.start()
	end
end

-- Model da laje i (tag Laje, Attributes Index/OwnerId/Angle/VaralCodes; PrimaryPart = Floor).
function MapGen.lajeModel(i: number): Model
	ensureBuilt()
	local model = lajes[i]
	if not model then
		error(`[MapGen] laje {i} não existe (1..{Config.LAJE_COUNT})`)
	end
	return model
end

-- Posição (centro) do carretel da laje i.
function MapGen.carretelPos(i: number): Vector3
	ensureBuilt()
	local pos = carretels[i]
	if not pos then
		error(`[MapGen] laje {i} não existe (1..{Config.LAJE_COUNT})`)
	end
	return pos
end

return MapGen
