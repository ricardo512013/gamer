--!strict
--[[
	KiteRenderer — tudo o que o cliente desenha em 3D, só com Parts, Tweens e BillboardGuis (GDD §2.9, §4, §7.2).

	• Pipas: assina a tag "Kite" (Configurations em workspace.KiteStates, atributos §7.4) → attach/detach.
	  Cada raridade tem forma própria (losango / Estrela / Arraia / Morcegão / Luz / Capivara), cor
	  Config.COLORS[color] (Temporada n = HSV), dourada = Neon dourado + ParticleEmitter padrão (sem textura).
	  Linha = Cylinder do carretel da laje do dono até o corpo; rabiola com balanço senoidal (escondida a mais
	  de TAIL_HIDE_DIST da câmera); BillboardGui "dono · pipa (raridade) · Ln" ou "Selvagem · pipa (raridade)".
	  Pos é lida a cada frame para a própria pipa e a Config.SYNC_HZ para as outras; o render interpola a
	  KITE_MOVE_SPEED (mais rápido se ficou para trás; salto > SNAP_DIST não interpola).
	  Status: Dueling → linha/pipa tremem e 4 faíscas no ponto médio; Falling → gira 360°/s Y e 90°/s Z e
	  acende o marcador no LandPos; Ground/Tree → parada; detach (pega) → encolhe em SHRINK_SECONDS.
	• Varal: assina a tag "Laje" e o atributo VaralCodes → miniaturas (1 Part cada) penduradas no Part "Varal".
	• Marcador (coluna Neon no LandPos), setas 3D do onboarding, rastro do rabeio, burst da coleta e
	  balões de emote (atributo Emote do Player, GDD §5.8).
	Requer SÓ Config. Orçamento de Parts no cliente ≈ 450 (GDD §4.3). Muretas Neon do VIP ficam com o MapGen.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local LocalizationService = game:GetService("LocalizationService")
local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local C = Config.CLIENT
local PAL = Config.PALETTE
local GOLD = Config.RARITY_COLORS[5] -- dourado = cor da Lendária (255,190,40)
local FONT_BOLD = Font.fromEnum(Enum.Font.GothamBold)
local FONT_BLACK = Font.fromEnum(Enum.Font.GothamBlack)

local STATUS_FLYING, STATUS_DUELING, STATUS_FALLING, STATUS_GROUND, STATUS_TREE = "Flying", "Dueling", "Falling", "Ground", "Tree"

local KiteRenderer = {}

-- Render de uma pipa no ar (um por Configuration com tag Kite).
type Render = {
	conf: Configuration,
	id: number,
	owner: number, -- userId (0 = selvagem)
	own: boolean, -- é a pipa do jogador local (lerp a cada frame)
	wild: boolean,
	model: string,
	rarity: number,
	color: number,
	golden: boolean,
	rig: Model, -- corpo + peças + rabiola
	body: BasePart,
	line: Part, -- Cylinder carretel → corpo
	tail: { Part },
	label: TextLabel,
	pos: Vector3, -- posição renderizada
	target: Vector3, -- último Pos lido do atributo
	nextSync: number, -- os.clock() da próxima leitura (outras pipas)
	snapped: boolean,
	status: string,
	lastStatus: string,
	spinT: number, -- segundos caindo (giro)
	tailHidden: boolean,
	sparks: { Part }?, -- faíscas do duelo (só na pipa de menor Id do par)
	conns: { RBXScriptConnection },
}

-- Peça de uma pipa: tamanho, deslocamento e giro em Z relativos ao corpo (plano XY, fina em Z).
type Piece = { size: Vector3, offset: Vector3, rotZ: number, color: Color3?, material: Enum.Material?, shape: Enum.PartType? }

local localPlayer = Players.LocalPlayer
local locale = LocalizationService.RobloxLocaleId

local renders: { [Configuration]: Render } = {}
local byId: { [number]: Render } = {}
local carretelByLaje: { [number]: BasePart } = {}
local varalMinis: { [Model]: { Model } } = {}
local varalConns: { [Model]: RBXScriptConnection } = {}
local markers: { [string]: { part: Part, untilTime: number } } = {}
local arrows: { [WedgePart]: { base: Vector3, phase: number } } = {}
local emoteConns: { [Player]: RBXScriptConnection } = {}
local emoteBubbles: { [Player]: BillboardGui } = {}
local fxFolder: Folder? = nil
local started = false

-- Ajudantes --------------------------------------------------------------------------------------

local function str(key: string, vars: { [string]: any }?): string
	return Config.str(key, locale, vars)
end

-- Pasta workspace/KiteRender com tudo o que este módulo cria.
local function fx(): Folder
	local folder = fxFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "KiteRender"
	created.Parent = Workspace
	fxFolder = created
	return created
end

local function attrNumber(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

local function attrString(inst: Instance, name: string, default: string): string
	local v = inst:GetAttribute(name)
	return if typeof(v) == "string" then v else default
end

local function attrBool(inst: Instance, name: string): boolean
	return inst:GetAttribute(name) == true
end

local function attrVector(inst: Instance, name: string): Vector3?
	local v = inst:GetAttribute(name)
	if typeof(v) == "Vector3" then
		return v
	end
	return nil
end

local function hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- Cor da pipa: dourada → ouro; Temporada n → HSV; senão Config.COLORS[color] (0 = Jornal).
local function colorOf(color: number, golden: boolean): Color3
	if golden then
		return GOLD
	end
	if color >= Config.SEASON_COLOR_BASE then
		local n = color - Config.SEASON_COLOR_BASE
		return Color3.fromHSV((n * Config.SEASON_HUE.step) % 1, Config.SEASON_HUE.sat, Config.SEASON_HUE.val)
	end
	return Config.COLORS[color] or Config.COLORS[0]
end

local function stylePart(part: BasePart, color: Color3, material: Enum.Material)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	stylePart(part, color, material)
	part.Parent = parent
	return part
end

local function newLabel(text: string, color: Color3, font: Font, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.RichText = true
	label.FontFace = font
	label.TextColor3 = color
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = PAL.Outline
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function newBillboard(name: string, size: UDim2, up: number, maxDist: number, onTop: boolean): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffset = Vector3.new(0, up, 0)
	gui.MaxDistance = maxDist
	gui.LightInfluence = 0
	gui.AlwaysOnTop = onTop
	gui.ResetOnSpawn = false
	return gui
end

-- Formas (uma por raridade; Raio/Pipeiro = Arraia, Temporada = Morcegão) -----------------------------

local function piecesFor(rarity: number): { Piece }
	local thin = 0.12
	if rarity == 2 then -- Estrela: losango + 2 barras cruzadas
		return {
			{ size = Vector3.new(1.7, 1.7, thin), offset = Vector3.zero, rotZ = 45 },
			{ size = Vector3.new(2.8, 0.7, thin), offset = Vector3.zero, rotZ = 30 },
			{ size = Vector3.new(2.8, 0.7, thin), offset = Vector3.zero, rotZ = -30 },
		}
	elseif rarity == 3 then -- Arraia: corpo largo, 2 asas e ferrão
		return {
			{ size = Vector3.new(2.6, 1.3, thin), offset = Vector3.zero, rotZ = 0 },
			{ size = Vector3.new(1.6, 0.6, thin), offset = Vector3.new(-1.5, 0.35, 0), rotZ = 30 },
			{ size = Vector3.new(1.6, 0.6, thin), offset = Vector3.new(1.5, 0.35, 0), rotZ = -30 },
			{ size = Vector3.new(0.15, 1.3, thin), offset = Vector3.new(0, -1.2, 0), rotZ = 0 },
		}
	elseif rarity == 4 then -- Morcegão: corpo largo, 2 asas angulosas, 2 orelhas
		return {
			{ size = Vector3.new(3.0, 1.3, thin), offset = Vector3.zero, rotZ = 0 },
			{ size = Vector3.new(2.0, 1.0, thin), offset = Vector3.new(-2.1, 0.2, 0), rotZ = 25 },
			{ size = Vector3.new(2.0, 1.0, thin), offset = Vector3.new(2.1, 0.2, 0), rotZ = -25 },
			{ size = Vector3.new(0.35, 0.6, thin), offset = Vector3.new(-0.7, 0.9, 0), rotZ = 15 },
			{ size = Vector3.new(0.35, 0.6, thin), offset = Vector3.new(0.7, 0.9, 0), rotZ = -15 },
		}
	elseif rarity == 5 then -- Pipa de Luz: losango Neon + 2 barras Neon brancas cruzadas
		return {
			{ size = Vector3.new(2.2, 2.2, thin), offset = Vector3.zero, rotZ = 45, material = Enum.Material.Neon },
			{ size = Vector3.new(3.2, 0.25, thin + 0.02), offset = Vector3.zero, rotZ = 45, material = Enum.Material.Neon, color = PAL.White },
			{ size = Vector3.new(3.2, 0.25, thin + 0.02), offset = Vector3.zero, rotZ = -45, material = Enum.Material.Neon, color = PAL.White },
		}
	elseif rarity == 6 then -- Capivara Voadora: bicho marrom com vela losango na cor da pipa
		return {
			{ size = Vector3.new(2.0, 1.1, 1.0), offset = Vector3.new(0, -0.3, 0), rotZ = 0, color = PAL.Dirt },
			{ size = Vector3.new(0.9, 0.9, 0.9), offset = Vector3.new(1.2, 0.1, 0), rotZ = 0, color = PAL.Dirt, shape = Enum.PartType.Ball },
			{ size = Vector3.new(0.25, 0.3, 0.25), offset = Vector3.new(1.35, 0.6, 0.25), rotZ = 0, color = PAL.Dirt },
			{ size = Vector3.new(0.25, 0.3, 0.25), offset = Vector3.new(1.35, 0.6, -0.25), rotZ = 0, color = PAL.Dirt },
			{ size = Vector3.new(1.8, 1.8, thin), offset = Vector3.new(-0.3, 1.2, 0), rotZ = 45 },
		}
	end
	-- Comum (Jornal / Lisa): losango
	return { { size = Vector3.new(2.2, 2.2, thin), offset = Vector3.zero, rotZ = 45 } }
end

-- Model da pipa com PrimaryPart "Body" na origem. scale < 0.6 (miniaturas do varal) usa só a peça principal.
function KiteRenderer.build(model: string, rarity: number, color: number, golden: boolean, scale: number): Model
	local rig = Instance.new("Model")
	rig.Name = model
	local base = colorOf(color, golden)
	local detailed = scale >= 0.6
	for i, piece in piecesFor(rarity) do
		if i > 1 and not detailed then
			break
		end
		local part = Instance.new("Part")
		part.Name = if i == 1 then "Body" else `Peca{i}`
		part.Size = piece.size * scale
		if piece.shape then
			part.Shape = piece.shape
		end
		local pieceColor = if golden then GOLD else (piece.color or base)
		local material = if golden then Enum.Material.Neon else (piece.material or Enum.Material.SmoothPlastic)
		stylePart(part, pieceColor, material)
		part.CFrame = CFrame.new(piece.offset * scale) * CFrame.Angles(0, 0, math.rad(piece.rotZ))
		part.Parent = rig
		if i == 1 then
			rig.PrimaryPart = part
		end
	end
	if golden and detailed then -- Dourada: partículas padrão (sem textura) GOLDEN_PARTICLES/s
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = C.GOLDEN_PARTICLES
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(1, 2)
		emitter.Size = NumberSequence.new(0.35)
		emitter.Color = ColorSequence.new(GOLD)
		emitter.LightEmission = 1
		emitter.Parent = rig.PrimaryPart
	end
	return rig
end

-- Efeitos ------------------------------------------------------------------------------------------

-- Rastro do rabeio: TRAIL_PARTS Parts brancas Neon ao longo do caminho, somem em TRAIL_SECONDS.
local function trail(from: Vector3, to: Vector3)
	local size = Vector3.new(C.TRAIL_SIZE, C.TRAIL_SIZE, C.TRAIL_SIZE)
	local info = TweenInfo.new(C.TRAIL_SECONDS)
	for i = 1, C.TRAIL_PARTS do
		local part = newPart("Rastro", size, PAL.White, Enum.Material.Neon, nil)
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		part.Position = from:Lerp(to, i / C.TRAIL_PARTS) + jitter
		part.Parent = fx()
		local tween = TweenService:Create(part, info, { Transparency = 1 })
		tween.Completed:Connect(function()
			part:Destroy()
		end)
		tween:Play()
	end
end

-- n Parts Neon de `color` voam de pos até a câmera em BURST_SECONDS (coleta no carretel).
function KiteRenderer.burst(pos: Vector3, color: Color3, n: number): ()
	local cam = Workspace.CurrentCamera
	local to = if cam then cam.CFrame.Position + cam.CFrame.LookVector * 3 else pos + Vector3.new(0, 10, 0)
	local size = Vector3.new(C.BURST_SIZE, C.BURST_SIZE, C.BURST_SIZE)
	local info = TweenInfo.new(C.BURST_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _ = 1, n do
		local part = newPart("Burst", size, color, Enum.Material.Neon, nil)
		local spread = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2
		part.Position = pos + spread
		part.Parent = fx()
		local tween = TweenService:Create(part, info, { Position = to + spread, Transparency = 1 })
		tween.Completed:Connect(function()
			part:Destroy()
		end)
		tween:Play()
	end
end

-- Coluna Neon MARKER_SIZE na cor da raridade em pos até untilTime (GetServerTimeNow). Mesmo ponto → só estende.
function KiteRenderer.showMarker(pos: Vector3, untilTime: number, rarity: number): ()
	local key = `{math.floor(pos.X)}_{math.floor(pos.Z)}`
	local existing = markers[key]
	if existing then
		existing.untilTime = math.max(existing.untilTime, untilTime)
		return
	end
	local part = newPart("Marcador", C.MARKER_SIZE, Config.RARITY_COLORS[rarity] or PAL.Gray, Enum.Material.Neon, nil)
	part.Transparency = C.MARKER_TRANSPARENCY
	part.Position = Vector3.new(pos.X, pos.Y + C.MARKER_SIZE.Y / 2, pos.Z)
	part.Parent = fx()
	markers[key] = { part = part, untilTime = untilTime }
end

-- Seta de onboarding: WedgePart Neon flutuando ARROW_HEIGHT acima de pos com bob ±ARROW_BOB + texto. Devolve o removedor.
function KiteRenderer.arrow3D(pos: Vector3, text: string): () -> ()
	local wedge = Instance.new("WedgePart")
	wedge.Name = "Seta"
	wedge.Size = C.ARROW_SIZE
	stylePart(wedge, PAL.Sun, Enum.Material.Neon)
	local gui = newBillboard("Texto", UDim2.fromOffset(260, 50), 2.5, 500, true)
	newLabel(text, PAL.Sun, FONT_BLACK, gui)
	gui.Parent = wedge
	wedge.CFrame = CFrame.new(pos + Vector3.new(0, C.ARROW_HEIGHT, 0))
	wedge.Parent = fx()
	arrows[wedge] = { base = pos, phase = math.random() * 2 * math.pi }
	return function()
		arrows[wedge] = nil
		wedge:Destroy()
	end
end

-- Pega: a pipa encolhe até sumir em SHRINK_SECONDS e é destruída.
local function shrinkAndDestroy(rig: Model)
	task.spawn(function()
		local t0 = os.clock()
		while rig.Parent do
			local k = (os.clock() - t0) / C.SHRINK_SECONDS
			if k >= 1 then
				break
			end
			rig:ScaleTo(math.max(0.01, 1 - k))
			RunService.Heartbeat:Wait()
		end
		rig:Destroy()
	end)
end

-- Linha, rabiola e Billboard ---------------------------------------------------------------------------

local function ownerPlayer(r: Render): Player?
	if r.owner == 0 then
		return nil
	end
	return Players:GetPlayerByUserId(r.owner)
end

-- Topo do carretel da laje do dono (atributo Laje do Player → Part com tag Carretel e LajeIndex igual).
local function lineAnchor(r: Render): Vector3?
	local p = ownerPlayer(r)
	if not p then
		return nil
	end
	local carretel = carretelByLaje[attrNumber(p, "Laje", 0)]
	if not carretel then
		return nil
	end
	return carretel.Position + Vector3.new(0, C.LINE_ANCHOR_UP, 0)
end

local function kiteName(model: string, color: number): string
	return str("kite_" .. model, { n = math.max(0, color - Config.SEASON_COLOR_BASE) })
end

local function billboardText(r: Render): string
	local kite = kiteName(r.model, r.color)
	local rarity = str("rarity" .. r.rarity)
	if r.wild then
		return `{str("wild")} · {kite} ({rarity})`
	end
	local name = attrString(r.conf, "OwnerName", "")
	local p = ownerPlayer(r)
	if p and attrBool(p, "VIP") then -- VIP: nome dourado
		name = `<font color="{hex(GOLD)}">{name}</font>`
	end
	return `{name} · {kite} ({rarity}) · L{attrNumber(r.conf, "Linha", 1)}`
end

-- Cor/material da rabiola: RabiolaRank 1-3 (ouro/prata/bronze), VIP Neon dourada, senão branca.
local function tailStyle(r: Render): (Color3, Enum.Material)
	local p = ownerPlayer(r)
	if p then
		local rankColor = Config.RABIOLA_COLORS[attrNumber(p, "RabiolaRank", 0)]
		if rankColor then
			return rankColor, Enum.Material.Neon
		end
		if attrBool(p, "VIP") then
			return GOLD, Enum.Material.Neon
		end
	end
	return PAL.White, Enum.Material.SmoothPlastic
end

-- CFrame do corpo: olha para o carretel (ou para o centro), inclinada TILT_DEG; Dueling treme; Falling gira; Ground deitada.
local function kiteCFrame(r: Render, anchor: Vector3?, now: number): CFrame
	local pos = r.pos
	if r.status == STATUS_FALLING then
		return CFrame.new(pos) * CFrame.Angles(0, math.rad(C.FALL_SPIN_Y) * r.spinT, math.rad(C.FALL_SPIN_Z) * r.spinT)
	elseif r.status == STATUS_GROUND then
		return CFrame.new(pos) * CFrame.Angles(-math.pi / 2, 0, 0)
	end
	local face = anchor or Vector3.zero
	local flat = Vector3.new(face.X, pos.Y, face.Z)
	if (flat - pos).Magnitude < 0.5 then
		flat = pos + Vector3.new(0, 0, 1)
	end
	local cf = CFrame.lookAt(pos, flat) * CFrame.Angles(math.rad(-C.TILT_DEG), 0, 0)
	if r.status == STATUS_DUELING then
		cf = cf * CFrame.new(math.sin(now * 2 * math.pi * C.DUEL_SHAKE_HZ) * C.DUEL_SHAKE, 0, 0)
	end
	return cf
end

local function updateLine(r: Render, anchor: Vector3?, bodyPos: Vector3)
	local visible = anchor ~= nil and (r.status == STATUS_FLYING or r.status == STATUS_DUELING)
	if not visible or not anchor then
		r.line.Transparency = 1
		return
	end
	local delta = bodyPos - anchor
	local len = delta.Magnitude
	if len < 0.1 then
		r.line.Transparency = 1
		return
	end
	r.line.Transparency = 0
	r.line.Size = Vector3.new(len, C.LINE_THICKNESS, C.LINE_THICKNESS)
	r.line.CFrame = CFrame.lookAt(anchor + delta / 2, bodyPos) * CFrame.Angles(0, math.pi / 2, 0)
end

local function updateTail(r: Render, cf: CFrame, now: number, camPos: Vector3)
	local far = (cf.Position - camPos).Magnitude > C.TAIL_HIDE_DIST
	local hidden = far or r.status == STATUS_GROUND or r.status == STATUS_TREE
	if hidden ~= r.tailHidden then
		r.tailHidden = hidden
		for _, part in r.tail do
			part.Transparency = if hidden then 1 else 0
		end
	end
	if hidden then
		return
	end
	for i, part in r.tail do
		local x = math.sin(now * 2 * math.pi * C.TAIL_HZ + i * 0.9) * C.TAIL_SWAY
		part.CFrame = cf * CFrame.new(x, -(0.9 + 0.6 * i), 0)
	end
end

-- Faíscas do duelo (4 Parts amarelas piscando no ponto médio entre as duas pipas).
local function ensureSparks(r: Render)
	if r.sparks then
		return
	end
	local list: { Part } = {}
	local size = Vector3.new(C.DUEL_SPARK_SIZE, C.DUEL_SPARK_SIZE, C.DUEL_SPARK_SIZE)
	for _ = 1, C.DUEL_SPARKS do
		table.insert(list, newPart("Faisca", size, PAL.Sun, Enum.Material.Neon, fx()))
	end
	r.sparks = list
end

local function clearSparks(r: Render)
	local sparks = r.sparks
	if not sparks then
		return
	end
	for _, part in sparks do
		part:Destroy()
	end
	r.sparks = nil
end

local function updateSparks(r: Render, now: number)
	local sparks = r.sparks
	if not sparks then
		return
	end
	local partner = byId[attrNumber(r.conf, "DuelWith", 0)]
	local mid = if partner then (r.pos + partner.pos) / 2 else r.pos
	for i, part in sparks do
		local a = now * 3 + i * (2 * math.pi / #sparks)
		part.Position = mid + Vector3.new(math.cos(a) * 1.2, math.sin(a * 1.7) * 0.8, math.sin(a) * 1.2)
		part.Transparency = if math.sin(now * 2 * math.pi * C.DUEL_BLINK_HZ + i) > 0 then 0 else 0.7
	end
end

-- Mudança de Status: rastro + faíscas ao entrar em duelo; marcador ao começar a cair.
local function onStatusChanged(r: Render, serverNow: number)
	local s = r.status
	if s == STATUS_DUELING then
		local duelWith = attrNumber(r.conf, "DuelWith", 0)
		if duelWith == 0 or r.id < duelWith then
			ensureSparks(r)
		end
		if (r.target - r.pos).Magnitude > 2 then -- quem mergulhou deixa rastro
			trail(r.pos, r.target)
		end
	else
		clearSparks(r)
	end
	if s == STATUS_FALLING then
		r.spinT = 0
		local land = attrVector(r.conf, "LandPos")
		if land and land.Magnitude > 0 then
			KiteRenderer.showMarker(land, attrNumber(r.conf, "StatusUntil", serverNow) + Config.GROUND_TIME, r.rarity)
		end
	end
	r.lastStatus = s
end

-- attach / detach --------------------------------------------------------------------------------------

local function remove(r: Render, shrink: boolean)
	renders[r.conf] = nil
	if byId[r.id] == r then
		byId[r.id] = nil
	end
	for _, conn in r.conns do
		conn:Disconnect()
	end
	clearSparks(r)
	r.line:Destroy()
	if shrink then
		shrinkAndDestroy(r.rig)
	else
		r.rig:Destroy()
	end
end

-- Cria o render de um KiteState (Configuration com atributos §7.4) e começa a interpolar.
function KiteRenderer.attach(conf: Configuration): ()
	if renders[conf] then
		return
	end
	local owner = attrNumber(conf, "Owner", 0)
	local model = attrString(conf, "Model", "Lisa")
	local rarity = attrNumber(conf, "Rarity", 1)
	local color = attrNumber(conf, "Color", 1)
	local golden = attrBool(conf, "Golden")
	local rig = KiteRenderer.build(model, rarity, color, golden, 1)
	local body = rig.PrimaryPart
	if not body then
		rig:Destroy()
		return
	end
	local pos = attrVector(conf, "Pos") or Vector3.zero
	rig:PivotTo(CFrame.new(pos))

	local line = newPart("Linha", Vector3.new(1, C.LINE_THICKNESS, C.LINE_THICKNESS), PAL.White, Enum.Material.SmoothPlastic, nil)
	line.Shape = Enum.PartType.Cylinder
	line.Transparency = 1

	local gui = newBillboard("Nome", UDim2.fromOffset(220, 44), C.BILLBOARD_UP, C.BILLBOARD_DIST, false)
	local label = newLabel("", Config.RARITY_COLORS[rarity] or PAL.White, FONT_BOLD, gui)
	gui.Parent = body

	local r: Render = {
		conf = conf,
		id = attrNumber(conf, "Id", 0),
		owner = owner,
		own = owner ~= 0 and owner == localPlayer.UserId,
		wild = attrBool(conf, "Wild"),
		model = model,
		rarity = rarity,
		color = color,
		golden = golden,
		rig = rig,
		body = body,
		line = line,
		tail = {},
		label = label,
		pos = pos,
		target = pos,
		nextSync = 0,
		snapped = true,
		status = attrString(conf, "Status", STATUS_FLYING),
		lastStatus = "",
		spinT = 0,
		tailHidden = false,
		sparks = nil,
		conns = {},
	}
	local tailColor, tailMaterial = tailStyle(r)
	for i = 1, C.TAIL_PARTS do
		local part = newPart(`Rabiola{i}`, Vector3.new(0.25, 0.25, 0.25), tailColor, tailMaterial, rig)
		table.insert(r.tail, part)
	end
	r.label.Text = billboardText(r)
	renders[conf] = r
	byId[r.id] = r
	rig.Parent = fx()
	line.Parent = fx()

	table.insert(r.conns, conf:GetAttributeChangedSignal("Linha"):Connect(function()
		r.label.Text = billboardText(r)
	end))
	table.insert(r.conns, conf:GetAttributeChangedSignal("Golden"):Connect(function() -- Vento Dourado: reconstrói
		if attrBool(conf, "Golden") ~= r.golden then
			remove(r, false)
			KiteRenderer.attach(conf)
		end
	end))
end

-- Remove o render (pega: encolhe antes de sumir).
function KiteRenderer.detach(conf: Configuration): ()
	local r = renders[conf]
	if r then
		remove(r, true)
	end
end

-- Varal (tag Laje + atributo VaralCodes) ------------------------------------------------------------------

-- codes = "model:rarity:color:golden,…" → miniaturas penduradas no Part "Varal" da laje, a cada VARAL_STEP studs.
function KiteRenderer.renderVaral(laje: Model, codes: string): ()
	local old = varalMinis[laje]
	if old then
		for _, mini in old do
			mini:Destroy()
		end
	end
	varalMinis[laje] = nil
	local varal = laje:FindFirstChild("Varal")
	if not varal or not varal:IsA("BasePart") or codes == "" then
		return
	end
	local minis: { Model } = {}
	for code in string.gmatch(codes, "[^,]+") do
		if #minis >= Config.VAGAS_MAX then
			break
		end
		local model, rarity, color, golden = string.match(code, "^(%w+):(%d+):(%d+):(%a+)$")
		if model and rarity and color and golden then
			table.insert(minis, KiteRenderer.build(model, tonumber(rarity) or 1, tonumber(color) or 0, golden == "true", C.VARAL_SCALE))
		end
	end
	local count = #minis
	for i, mini in minis do
		local x = (i - 1 - (count - 1) / 2) * C.VARAL_STEP
		mini:PivotTo(varal.CFrame * CFrame.new(x, -C.VARAL_HANG, 0))
		mini.Parent = fx()
	end
	varalMinis[laje] = minis
end

local function hookLaje(inst: Instance)
	if not inst:IsA("Model") or varalConns[inst] then
		return
	end
	local function refresh()
		KiteRenderer.renderVaral(inst, attrString(inst, "VaralCodes", ""))
	end
	varalConns[inst] = inst:GetAttributeChangedSignal("VaralCodes"):Connect(refresh)
	refresh()
end

local function unhookLaje(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local conn = varalConns[inst]
	if conn then
		conn:Disconnect()
	end
	varalConns[inst] = nil
	local minis = varalMinis[inst]
	if minis then
		for _, mini in minis do
			mini:Destroy()
		end
	end
	varalMinis[inst] = nil
end

-- Carretéis (tag Carretel + LajeIndex): âncora da linha ----------------------------------------------------

local function hookCarretel(inst: Instance)
	if inst:IsA("BasePart") then
		carretelByLaje[attrNumber(inst, "LajeIndex", 0)] = inst
	end
end

local function unhookCarretel(inst: Instance)
	if inst:IsA("BasePart") then
		local i = attrNumber(inst, "LajeIndex", 0)
		if carretelByLaje[i] == inst then
			carretelByLaje[i] = nil
		end
	end
end

-- Emotes-balão (atributo Emote do Player = "emoteN" por EMOTE_SECONDS) -------------------------------------

local function showEmote(p: Player, key: string)
	local old = emoteBubbles[p]
	if old then
		old:Destroy()
		emoteBubbles[p] = nil
	end
	if key == "" then
		return
	end
	local character = p.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = newBillboard("Emote", UDim2.fromOffset(180, 56), C.EMOTE_BUBBLE_UP, 200, true)
	local bubble = Instance.new("Frame")
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.BackgroundColor3 = PAL.UIBg
	bubble.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = C.STROKE_PX
	stroke.Color = PAL.Sun
	stroke.Parent = bubble
	newLabel(str(key), PAL.UIText, FONT_BLACK, bubble)
	bubble.Parent = gui
	gui.Parent = head
	emoteBubbles[p] = gui
	task.delay(Config.EMOTE_SECONDS, function()
		if emoteBubbles[p] == gui then
			emoteBubbles[p] = nil
			gui:Destroy()
		end
	end)
end

local function hookPlayer(p: Player)
	emoteConns[p] = p:GetAttributeChangedSignal("Emote"):Connect(function()
		showEmote(p, attrString(p, "Emote", ""))
	end)
end

local function unhookPlayer(p: Player)
	local conn = emoteConns[p]
	if conn then
		conn:Disconnect()
	end
	emoteConns[p] = nil
	local bubble = emoteBubbles[p]
	if bubble then
		bubble:Destroy()
	end
	emoteBubbles[p] = nil
end

-- Loop por frame -----------------------------------------------------------------------------------------

local function step(dt: number)
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	local cam = Workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero

	for conf, r in renders do
		-- leitura do alvo: própria pipa a cada frame, as outras a SYNC_HZ
		if r.own or now >= r.nextSync then
			r.nextSync = now + 1 / Config.SYNC_HZ
			local p = attrVector(conf, "Pos")
			if p then
				r.target = p
			end
			r.status = attrString(conf, "Status", r.status)
		end
		-- interpolação a KITE_MOVE_SPEED (ou mais rápido se ficou para trás); salto grande não interpola
		local delta = r.target - r.pos
		local dist = delta.Magnitude
		if not r.snapped or dist > C.SNAP_DIST then
			r.pos = r.target
			r.snapped = true
		elseif dist > 0.001 then
			local speed = math.max(Config.KITE_MOVE_SPEED, dist * C.CATCHUP)
			local stepLen = math.min(dist, speed * dt)
			r.pos = r.pos + delta * (stepLen / dist)
		end
		if r.status ~= r.lastStatus then
			onStatusChanged(r, serverNow)
		end
		if r.status == STATUS_FALLING then
			r.spinT += dt
		end
		local anchor = lineAnchor(r)
		local cf = kiteCFrame(r, anchor, now)
		r.rig:PivotTo(cf)
		updateLine(r, anchor, cf.Position)
		updateTail(r, cf, now, camPos)
		if r.sparks then
			updateSparks(r, now)
		end
	end

	for key, marker in markers do -- marcadores vencidos
		if serverNow > marker.untilTime then
			marker.part:Destroy()
			markers[key] = nil
		end
	end

	for wedge, a in arrows do -- setas: bob + giro lento, ponta para baixo
		local y = C.ARROW_HEIGHT + math.sin(now * 2 + a.phase) * C.ARROW_BOB
		wedge.CFrame = CFrame.new(a.base + Vector3.new(0, y, 0)) * CFrame.Angles(0, now * C.ARROW_SPIN, 0) * CFrame.Angles(math.pi / 2, 0, 0)
	end
end

local function onKiteAdded(inst: Instance)
	if inst:IsA("Configuration") then
		KiteRenderer.attach(inst)
	end
end

local function onKiteRemoved(inst: Instance)
	if inst:IsA("Configuration") then
		KiteRenderer.detach(inst)
	end
end

-- Assina as tags Kite, Laje e Carretel, os emotes dos jogadores e o loop por frame.
function KiteRenderer.start(): ()
	if started then
		return
	end
	started = true
	fx()
	for _, inst in CollectionService:GetTagged("Carretel") do
		hookCarretel(inst)
	end
	CollectionService:GetInstanceAddedSignal("Carretel"):Connect(hookCarretel)
	CollectionService:GetInstanceRemovedSignal("Carretel"):Connect(unhookCarretel)

	for _, inst in CollectionService:GetTagged("Laje") do
		hookLaje(inst)
	end
	CollectionService:GetInstanceAddedSignal("Laje"):Connect(hookLaje)
	CollectionService:GetInstanceRemovedSignal("Laje"):Connect(unhookLaje)

	for _, inst in CollectionService:GetTagged("Kite") do
		onKiteAdded(inst)
	end
	CollectionService:GetInstanceAddedSignal("Kite"):Connect(onKiteAdded)
	CollectionService:GetInstanceRemovedSignal("Kite"):Connect(onKiteRemoved)

	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(unhookPlayer)

	RunService.RenderStepped:Connect(step)
end

return KiteRenderer
