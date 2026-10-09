--!strict
--[[
	HUD — toda a interface 2D (GDD §6), mobile-first e construída em código: ScreenGui (IgnoreGuiInset,
	DeviceSafeInsets) + Frame/TextLabel/TextButton, UICorner, UIStroke 3 px, UDim2.fromScale +
	UIAspectRatioConstraint, GothamBlack/GothamBold, TextScaled com mínimo de 14 px (UITextSizeConstraint),
	sem imagens. Strings via HUD.t (Config.str no locale do jogador: "en…" → inglês, senão pt-BR).

	Elementos: botão PUXAR (0,16 da altura, ≥ 128 px; encolhe ao apertar; "SEGURA!" piscando no duelo; anel
	pulsante no onboarding), Vento com count-up e "+n/s" com pop, barra do Carretel + PEGAR VENTO (só a
	≤ COLLECT_DIST do próprio carretel), cartas do varal (toque = selecionar, toque longo = estimação),
	faixa (cinza 0-2 / laranja 3-4), escudo com contagem, 4 emotes, botões de topo (BAR só perto do balcão,
	CORREIO com badge, RENASCER, LOJA, SOM), banner de evento (atributos de workspace.World), barra de
	duelo, tela cheia (CORTOU!/VOOU!/VOCÊ PEGOU/SORTE!), toasts, painéis do Bar, Correio da Laje, Renascer,
	Loja de passes (preços via GetProductInfoAsync em pcall), popup Offline e onboarding (dica + setas 3D).
	Os callbacks on* são definidos por init.client, que fala com os remotes. Requer Config e KiteRenderer.
	Todo número vive em Config.CLIENT; toda cor em Config.PALETTE / RARITY_COLORS.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")
local LocalizationService = game:GetService("LocalizationService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local KiteRenderer = require(script.Parent.KiteRenderer)

type KiteData = Config.KiteData
type Patch = { [string]: any }

local C = Config.CLIENT
local PAL = Config.PALETTE
local FONT_BLACK = Font.fromEnum(Enum.Font.GothamBlack)
local FONT_BOLD = Font.fromEnum(Enum.Font.GothamBold)
local IDS = (Config.IDS :: any) :: { [string]: number }
local DAILY = (Config.DAILY :: any) :: { [string]: { goal: number, reward: number } }

local localPlayer = Players.LocalPlayer
local locale = LocalizationService.RobloxLocaleId
local isEn = string.sub(locale, 1, 2) == "en"

local HUD = {}

-- Callbacks definidos por init.client (falam com os remotes).
HUD.onPull = nil :: ((down: boolean) -> ())?
HUD.onSelect = nil :: ((id: number) -> ())?
HUD.onBuy = nil :: ((kind: string, slot: number?) -> ())?
HUD.onClaim = nil :: ((which: string) -> ())? -- "Streak" | "Cortes" | "Pegas"
HUD.onRebirth = nil :: (() -> ())?
HUD.onEmote = nil :: ((id: number) -> ())?
HUD.onCollect = nil :: (() -> ())? -- botão PEGAR VENTO → Collect
HUD.onPet = nil :: ((id: number) -> ())? -- toque longo na carta → SetPet

-- Referências da UI (criadas de uma vez em build()).
type UI = {
	gui: ScreenGui,
	root: Frame,
	vento: TextLabel,
	rate: TextLabel,
	rateScale: UIScale,
	carretelFill: Frame,
	carretelText: TextLabel,
	collectBtn: TextButton,
	banner: TextLabel,
	toasts: Frame,
	cards: Frame,
	pullBtn: TextButton,
	pullText: TextLabel,
	pullScale: UIScale,
	pullRing: Frame,
	pullRingStroke: UIStroke,
	faixa: TextLabel,
	shield: TextLabel,
	hint: TextLabel,
	btnBar: TextButton,
	btnMail: TextButton,
	mailBadge: Frame,
	btnRebirth: TextButton,
	btnShop: TextButton,
	btnSound: TextButton,
	duel: Frame,
	duelNames: TextLabel,
	duelHold: TextLabel,
	duelFill: Frame,
	flash: TextLabel,
	flashScale: UIScale,
	dim: Frame,
	barPanel: Frame,
	barClock: TextLabel,
	barSlots: Frame,
	barLinha: TextButton,
	barVaga: TextButton,
	mailPanel: Frame,
	mailDays: Frame,
	mailStreakBtn: TextButton,
	mailCuts: TextLabel,
	mailCutsBtn: TextButton,
	mailCatch: TextLabel,
	mailCatchBtn: TextButton,
	rebirthPanel: Frame,
	rebirthTitle: TextLabel,
	rebirthNeed: TextLabel,
	rebirthEpic: TextLabel,
	rebirthBtn: TextButton,
	shopPanel: Frame,
	shopList: Frame,
	offlinePanel: Frame,
	offlineText: TextLabel,
}

local ui: UI? = nil

-- Estado espelhado do State (§7.3) + estado local do HUD.
local S = {
	Vento = 0,
	shownVento = -1, -- count-up
	Carretel = 0,
	CarretelCap = 0,
	Rate = 0,
	Linha = 1,
	Vagas = Config.VAGAS_START,
	Temporadas = 0,
	Kites = {} :: { KiteData },
	Selected = 0,
	Streak = { Day = 0, LastClaimDay = 0, SaverWeek = 0 },
	Dailies = { Day = 0, Cortes = 0, Pegas = 0, ClaimedCortes = false, ClaimedPegas = false },
	Novato = false,
	NovatoUntil = 0,
	Onboarding = 0,
	faixa = 0,
	ownStatus = "",
	lastLandPos = nil :: Vector3?,
	lastLandUntil = 0,
	duelActive = false,
	duelEndsAt = 0,
	duelLinha = 0,
	stock = nil :: Patch?,
	nearCarretel = false,
	nearBar = false,
	soundOn = true,
	panel = "",
	onbStep = -1,
	onbKey = "",
	arrowRemove = nil :: (() -> ())?,
	flashSeq = 0,
	toastSeq = 0,
	prices = {} :: { [string]: string },
	pricesAt = 0,
	pressedByButton = false,
}

-- Strings e formatação ---------------------------------------------------------------------------------

function HUD.t(key: string, vars: { [string]: any }?): string
	return Config.str(key, locale, vars)
end

local t = HUD.t

-- "1.240" / "12,4 K" / "1,2 M" (en: "1,240" / "12.4 K").
local function fmtNumber(n: number): string
	local dec = if isEn then "." else ","
	local grp = if isEn then "," else "."
	local abs = math.abs(n)
	local sign = if n < 0 then "-" else ""
	local function short(v: number, suffix: string): string
		local s = string.format("%.1f", v)
		s = string.gsub(s, "%.0$", "")
		s = string.gsub(s, "%.", dec)
		return sign .. s .. " " .. suffix
	end
	if abs >= 1e9 then
		return short(abs / 1e9, "B")
	elseif abs >= 1e6 then
		return short(abs / 1e6, "M")
	elseif abs >= 1e4 then
		return short(abs / 1e3, "K")
	end
	local digits = tostring(math.floor(abs + 0.5))
	local out = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1" .. grp)))
	if string.sub(out, 1, 1) == grp then
		out = string.sub(out, 2)
	end
	return sign .. out
end

-- "0,25" / "1,6" / "37,5" (en: "0.25"): até 2 casas, sem zeros à direita — V/s e multiplicadores de faixa.
local function fmtDecimal(n: number): string
	if math.abs(n) >= 1e4 then
		return fmtNumber(n)
	end
	local s = string.format("%.2f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return (string.gsub(s, "%.", if isEn then "." else ","))
end

-- "m:ss"
local function fmtClock(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- "3 h 12" / "12 min"
local function fmtLong(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return t("hours", { h = s // 3600, m = string.format("%02d", (s % 3600) // 60) })
	end
	return t("minutes", { m = s // 60 })
end

local function kiteName(model: string, season: number?): string
	return t("kite_" .. model, { n = season or 0 })
end

local function rarityName(rarity: number): string
	return t("rarity" .. rarity)
end

local function kiteColor(k: KiteData): Color3
	if k.golden then
		return Config.RARITY_COLORS[5]
	end
	if k.color >= Config.SEASON_COLOR_BASE then
		return Color3.fromHSV(((k.color - Config.SEASON_COLOR_BASE) * Config.SEASON_HUE.step) % 1, Config.SEASON_HUE.sat, Config.SEASON_HUE.val)
	end
	return Config.COLORS[k.color] or Config.COLORS[0]
end

local function today(): number
	return os.time() // Config.DAY_SECONDS
end

-- Semana desde segunda 00:00 UTC (a mesma fórmula do servidor): Guardar Streak vale por semana.
local function weekIndex(): number
	return (os.time() - Config.WEEK_EPOCH_OFFSET) // Config.WEEK_SECONDS
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function num(v: any, default: number): number
	return if typeof(v) == "number" then v else default
end

local function attrNumber(inst: Instance, name: string, default: number): number
	return num(inst:GetAttribute(name), default)
end

local function attrString(inst: Instance, name: string, default: string): string
	local v = inst:GetAttribute(name)
	return if typeof(v) == "string" then v else default
end

local function rootPart(): BasePart?
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Posição do próprio carretel (Part com tag Carretel e LajeIndex == atributo Laje do jogador).
local function carretelPos(): Vector3?
	local laje = attrNumber(localPlayer, "Laje", 0)
	if laje == 0 then
		return nil
	end
	for _, inst in CollectionService:GetTagged("Carretel") do
		if inst:IsA("BasePart") and attrNumber(inst, "LajeIndex", 0) == laje then
			return inst.Position
		end
	end
	return nil
end

-- Configuration da própria pipa no ar (Owner == UserId), se houver.
local function ownConf(): Instance?
	for _, inst in CollectionService:GetTagged("Kite") do
		if attrNumber(inst, "Owner", 0) == localPlayer.UserId then
			return inst
		end
	end
	return nil
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Construtores de UI -----------------------------------------------------------------------------------

local function apply(inst: Instance, props: { [string]: any })
	for k, v in props do
		(inst :: any)[k] = v
	end
end

local function textMin(inst: Instance)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = C.MIN_TEXT_PX
	constraint.Parent = inst
end

local function corner(inst: Instance, radius: UDim?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0.2, 0)
	c.Parent = inst
	return c
end

local function stroke(inst: Instance, color: Color3?, px: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = px or C.STROKE_PX
	s.Color = color or PAL.Outline
	s.Parent = inst
	return s
end

local function aspect(inst: Instance, ratio: number)
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = ratio
	a.Parent = inst
end

local function frame(name: string, props: { [string]: any }, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = PAL.UIBg
	apply(f, props)
	f.Parent = parent
	return f
end

local function label(name: string, text: string, props: { [string]: any }, parent: Instance?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = UDim2.fromScale(1, 1)
	l.FontFace = FONT_BOLD
	l.TextColor3 = PAL.UIText
	l.TextScaled = true
	l.Text = text
	apply(l, props)
	textMin(l)
	l.Parent = parent
	return l
end

local function button(name: string, text: string, props: { [string]: any }, parent: Instance?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.BackgroundColor3 = PAL.Laje
	b.FontFace = FONT_BLACK
	b.TextColor3 = PAL.UIText
	b.TextScaled = true
	b.Text = text
	apply(b, props)
	textMin(b)
	b.Parent = parent
	return b
end

-- Botão "cartão": fundo colorido, canto (radius, padrão 20 %), contorno 3 px.
local function pillButton(name: string, text: string, color: Color3, props: { [string]: any }, parent: Instance?, radius: UDim?): TextButton
	local b = button(name, text, props, parent)
	b.BackgroundColor3 = color
	corner(b, radius)
	stroke(b)
	return b
end

local function setEnabled(b: TextButton, enabled: boolean)
	b.Active = enabled
	b.AutoButtonColor = enabled
	b.BackgroundTransparency = if enabled then 0 else 0.5
	b.TextTransparency = if enabled then 0 else 0.4
end

local function list(parent: Instance, direction: Enum.FillDirection, padding: number, align: Enum.HorizontalAlignment?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(padding, 0)
	l.HorizontalAlignment = align or Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Parent = parent
	return l
end

local function clearChildren(parent: Instance, className: string)
	for _, child in parent:GetChildren() do
		if child:IsA(className) then
			child:Destroy()
		end
	end
end

-- Painel modal: Frame com título e botão X; devolve (painel, conteúdo).
local function panel(name: string, size: UDim2, anchor: Vector2, pos: UDim2, title: string, parent: Instance, onClose: () -> ()): (Frame, Frame)
	local p = frame(name, { Size = size, AnchorPoint = anchor, Position = pos, Visible = false }, parent)
	corner(p)
	stroke(p, PAL.Sun)
	local scale = Instance.new("UIScale")
	scale.Name = "Escala"
	scale.Parent = p
	label("Titulo", title, { Size = UDim2.fromScale(0.8, 0.12), Position = UDim2.fromScale(0.03, 0.02), FontFace = FONT_BLACK, TextXAlignment = Enum.TextXAlignment.Left }, p)
	local close = pillButton("Fechar", "X", PAL.Red, { Size = UDim2.fromScale(0, 0.1), Position = UDim2.fromScale(0.97, 0.03), AnchorPoint = Vector2.new(1, 0) }, p)
	aspect(close, 1)
	close.Activated:Connect(onClose)
	local content = frame("Conteudo", { Size = UDim2.fromScale(0.94, 0.82), Position = UDim2.fromScale(0.03, 0.16), BackgroundTransparency = 1 }, p)
	return p, content
end

-- Construção ---------------------------------------------------------------------------------------------

local function build(): UI
	local gui = Instance.new("ScreenGui")
	gui.Name = "PegaPipaHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10

	local root = frame("Root", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)

	-- Topo centro: Vento, V/s, Carretel, PEGAR VENTO, banner, toasts
	local vento = label("Vento", "0 " .. t("wind"), { Size = UDim2.fromScale(0.34, 0.06), Position = UDim2.fromScale(0.5, 0.015), AnchorPoint = Vector2.new(0.5, 0), FontFace = FONT_BLACK }, root)
	stroke(vento, PAL.Outline, 2)
	local rate = label("Rate", t("perSec", { n = "0" }), { Size = UDim2.fromScale(0.2, 0.035), Position = UDim2.fromScale(0.5, 0.078), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = PAL.Sun }, root)
	stroke(rate, PAL.Outline, 2)
	local rateScale = Instance.new("UIScale")
	rateScale.Parent = rate

	local carretel = frame("Carretel", { Size = UDim2.fromScale(0.28, 0.035), Position = UDim2.fromScale(0.5, 0.118), AnchorPoint = Vector2.new(0.5, 0) }, root)
	corner(carretel, UDim.new(0.5, 0))
	stroke(carretel)
	local carretelFill = frame("Cheio", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = PAL.Laje }, carretel)
	corner(carretelFill, UDim.new(0.5, 0))
	local carretelText = label("Texto", "", { ZIndex = 2 }, carretel)
	stroke(carretelText, PAL.Outline, 2)

	local collectBtn = pillButton("PegarVento", t("collect"), PAL.Sun, { Size = UDim2.fromScale(0.2, 0.05), Position = UDim2.fromScale(0.5, 0.16), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = PAL.Outline, Visible = false }, root)

	local banner = label("Banner", "", { Size = UDim2.fromScale(0.38, 0.045), Position = UDim2.fromScale(0.5, 0.215), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 0, BackgroundColor3 = PAL.Red, FontFace = FONT_BLACK, Visible = false }, root)
	corner(banner)
	stroke(banner)

	local toasts = frame("Toasts", { Size = UDim2.fromScale(0.5, 0.2), Position = UDim2.fromScale(0.5, 0.27), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, root)
	list(toasts, Enum.FillDirection.Vertical, 0.02)

	-- Coluna esquerda: cartas do varal
	local cards = frame("Cartas", { Size = UDim2.fromScale(0.105, 0.64), Position = UDim2.fromScale(0.012, 0.12), BackgroundTransparency = 1 }, root)
	local cardsList = list(cards, Enum.FillDirection.Vertical, 0.008)
	cardsList.VerticalAlignment = Enum.VerticalAlignment.Top

	-- Direita: PUXAR (tamanho em px calculado por fitButton: 0,16 da altura, nunca < BUTTON_MIN_PX), faixa, escudo, dica
	local pullRing = frame("Anel", { Position = UDim2.fromScale(0.985, 0.975), AnchorPoint = Vector2.new(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 0 }, root)
	corner(pullRing, UDim.new(0.5, 0))
	local pullRingStroke = stroke(pullRing, PAL.Sun, C.STROKE_PX + 1)

	local pullBtn = button("Puxar", "", { Position = UDim2.fromScale(0.985, 0.975), AnchorPoint = Vector2.new(1, 1), AutoButtonColor = false, ZIndex = 1 }, root)
	corner(pullBtn, UDim.new(0.5, 0))
	stroke(pullBtn, PAL.Outline, C.STROKE_PX + 1)
	local pullScale = Instance.new("UIScale")
	pullScale.Parent = pullBtn
	local pullText = label("Texto", t("pull"), { Size = UDim2.fromScale(0.8, 0.4), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), FontFace = FONT_BLACK }, pullBtn)
	stroke(pullText, PAL.Outline, 2)

	local faixa = label("Faixa", "", { Size = UDim2.fromScale(0.24, 0.045), Position = UDim2.fromScale(0.985, 0.79), AnchorPoint = Vector2.new(1, 1), BackgroundTransparency = 0, FontFace = FONT_BLACK }, root)
	corner(faixa)
	stroke(faixa)
	local shield = label("Escudo", "", { Size = UDim2.fromScale(0.24, 0.04), Position = UDim2.fromScale(0.985, 0.74), AnchorPoint = Vector2.new(1, 1), TextColor3 = PAL.Sky, Visible = false }, root)
	stroke(shield, PAL.Outline, 2)
	local hint = label("Dica", "", { Size = UDim2.fromScale(0.32, 0.05), Position = UDim2.fromScale(0.985, 0.695), AnchorPoint = Vector2.new(1, 1), TextColor3 = PAL.Sun, FontFace = FONT_BLACK, Visible = false }, root)
	stroke(hint, PAL.Outline, 2)

	-- Topo direito: BAR, CORREIO, RENASCER, LOJA, SOM
	local topBtns = frame("TopoDireito", { Size = UDim2.fromScale(0.42, 0.07), Position = UDim2.fromScale(0.985, 0.015), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1 }, root)
	list(topBtns, Enum.FillDirection.Horizontal, 0.012, Enum.HorizontalAlignment.Right)
	local function topButton(name: string, text: string, color: Color3, order: number): TextButton
		local b = pillButton(name, text, color, { Size = UDim2.fromScale(0, 1), LayoutOrder = order }, topBtns)
		aspect(b, 1)
		return b
	end
	local btnBar = topButton("Bar", t("btnBar"), PAL.Red, 1)
	btnBar.Visible = false
	local btnMail = topButton("Correio", t("btnMail"), PAL.Sky, 2)
	local mailBadge = frame("Badge", { Size = UDim2.fromScale(0.3, 0.3), Position = UDim2.fromScale(0.95, 0.05), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = PAL.Red, Visible = false, ZIndex = 3 }, btnMail)
	corner(mailBadge, UDim.new(0.5, 0))
	stroke(mailBadge, PAL.Outline, 2)
	local btnRebirth = topButton("Renascer", t("btnRebirth"), PAL.Lilac, 3)
	local btnShop = topButton("Loja", t("btnShop"), PAL.Hill, 4)
	local btnSound = topButton("Som", t("btnSound"), PAL.Asphalt, 5)

	-- Canto inferior esquerdo: 4 emotes
	local emotes = frame("Emotes", { Size = UDim2.fromScale(0.34, 0.07), Position = UDim2.fromScale(0.012, 0.975), AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1 }, root)
	list(emotes, Enum.FillDirection.Horizontal, 0.012, Enum.HorizontalAlignment.Left)
	for i = 1, 4 do
		local b = pillButton(`Emote{i}`, t(`emote{i}`), if i % 2 == 1 then PAL.Pink else PAL.Lilac, { Size = UDim2.fromScale(0, 1), LayoutOrder = i }, emotes, UDim.new(0.5, 0))
		aspect(b, 1)
		b.Activated:Connect(function()
			local cb = HUD.onEmote
			if cb then
				cb(i)
			end
		end)
	end

	-- Centro: barra de duelo e tela cheia
	local duel = frame("Duelo", { Size = UDim2.fromScale(0.5, 0.07), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false }, root)
	corner(duel)
	stroke(duel, PAL.Sun)
	local duelNames = label("Nomes", "", { Size = UDim2.fromScale(0.96, 0.4), Position = UDim2.fromScale(0.02, 0.04) }, duel)
	local duelHold = label("Segura", t("hold"), { Size = UDim2.fromScale(0.96, 0.4), Position = UDim2.fromScale(0.02, 0.4), TextColor3 = PAL.Sun, FontFace = FONT_BLACK }, duel)
	local duelTrack = frame("Trilho", { Size = UDim2.fromScale(0.96, 0.14), Position = UDim2.fromScale(0.02, 0.82), BackgroundColor3 = PAL.Asphalt }, duel)
	corner(duelTrack, UDim.new(0.5, 0))
	local duelFill = frame("Cheio", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = PAL.Sun }, duelTrack)
	corner(duelFill, UDim.new(0.5, 0))

	local flash = label("TelaCheia", "", { Size = UDim2.fromScale(0.8, 0.14), Position = UDim2.fromScale(0.5, 0.33), AnchorPoint = Vector2.new(0.5, 0.5), FontFace = FONT_BLACK, Visible = false, ZIndex = 5 }, root)
	stroke(flash, PAL.Outline, C.STROKE_PX)
	local flashScale = Instance.new("UIScale")
	flashScale.Parent = flash

	-- Painéis (sobre um escurecimento)
	local dim = frame("Escuro", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = PAL.Outline, BackgroundTransparency = 0.4, Visible = false, ZIndex = 10 }, root)
	local function closeAll()
		S.panel = ""
		dim.Visible = false
	end

	local barPanel, barContent = panel("Bar", UDim2.fromScale(0.74, 0.6), Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), t("bar"), dim, closeAll)
	local barClock = label("Relogio", "", { Size = UDim2.fromScale(0.4, 0.1), Position = UDim2.fromScale(0.5, 0.02), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = PAL.Sun }, barPanel)
	local barSlots = frame("Slots", { Size = UDim2.fromScale(1, 0.62), BackgroundTransparency = 1 }, barContent)
	list(barSlots, Enum.FillDirection.Horizontal, 0.012)
	local barBottom = frame("Fixos", { Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.68), BackgroundTransparency = 1 }, barContent)
	list(barBottom, Enum.FillDirection.Horizontal, 0.02)
	local barLinha = pillButton("Linha", "", PAL.Sky, { Size = UDim2.fromScale(0.46, 0.9), LayoutOrder = 1 }, barBottom)
	local barVaga = pillButton("Vaga", "", PAL.Hill, { Size = UDim2.fromScale(0.46, 0.9), LayoutOrder = 2 }, barBottom)

	local mailPanel, mailContent = panel("Correio", UDim2.fromScale(0.7, 0.6), Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), t("mail"), dim, closeAll)
	local mailDays = frame("Dias", { Size = UDim2.fromScale(1, 0.42), BackgroundTransparency = 1 }, mailContent)
	list(mailDays, Enum.FillDirection.Horizontal, 0.01)
	local mailStreakBtn = pillButton("ResgatarStreak", t("claim"), PAL.Sun, { Size = UDim2.fromScale(0.3, 0.14), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = PAL.Outline }, mailContent)
	local mailCuts = label("Cortes", "", { Size = UDim2.fromScale(0.62, 0.14), Position = UDim2.fromScale(0, 0.66), TextXAlignment = Enum.TextXAlignment.Left }, mailContent)
	local mailCutsBtn = pillButton("ResgatarCortes", t("claim"), PAL.Sun, { Size = UDim2.fromScale(0.3, 0.14), Position = UDim2.fromScale(1, 0.66), AnchorPoint = Vector2.new(1, 0), TextColor3 = PAL.Outline }, mailContent)
	local mailCatch = label("Pegas", "", { Size = UDim2.fromScale(0.62, 0.14), Position = UDim2.fromScale(0, 0.84), TextXAlignment = Enum.TextXAlignment.Left }, mailContent)
	local mailCatchBtn = pillButton("ResgatarPegas", t("claim"), PAL.Sun, { Size = UDim2.fromScale(0.3, 0.14), Position = UDim2.fromScale(1, 0.84), AnchorPoint = Vector2.new(1, 0), TextColor3 = PAL.Outline }, mailContent)

	local rebirthPanel, rebirthContent = panel("Renascer", UDim2.fromScale(0.6, 0.42), Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), "", dim, closeAll)
	local rebirthTitle = rebirthPanel:FindFirstChild("Titulo") :: TextLabel
	local rebirthNeed = label("Custo", "", { Size = UDim2.fromScale(1, 0.18), Position = UDim2.fromScale(0, 0), TextColor3 = PAL.Sun }, rebirthContent)
	local rebirthEpic = label("Epica", "", { Size = UDim2.fromScale(1, 0.16), Position = UDim2.fromScale(0, 0.2) }, rebirthContent)
	label("Bonus", t("rebirthBonus"), { Size = UDim2.fromScale(1, 0.16), Position = UDim2.fromScale(0, 0.38), TextColor3 = PAL.Green }, rebirthContent)
	label("Fica", t("rebirthKeep"), { Size = UDim2.fromScale(1, 0.14), Position = UDim2.fromScale(0, 0.56), TextColor3 = PAL.Gray }, rebirthContent)
	local rebirthBtn = pillButton("Confirmar", t("confirm"), PAL.Lilac, { Size = UDim2.fromScale(0.4, 0.22), Position = UDim2.fromScale(0.5, 0.76), AnchorPoint = Vector2.new(0.5, 0) }, rebirthContent)

	local shopPanel, shopContent = panel("Loja", UDim2.fromScale(0.62, 0.78), Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), t("btnShop"), dim, closeAll)
	local shopList = frame("Lista", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, shopContent)
	local shopLayout = list(shopList, Enum.FillDirection.Vertical, 0.012)
	shopLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	local offlinePanel, offlineContent = panel("Offline", UDim2.fromScale(0.6, 0.36), Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), t("offlineTitle"), dim, closeAll)
	local offlineText = label("Texto", "", { Size = UDim2.fromScale(1, 0.5), Position = UDim2.fromScale(0, 0.02), TextWrapped = true }, offlineContent)
	local offlineBtn = pillButton("Receber", t("receive"), PAL.Sun, { Size = UDim2.fromScale(0.4, 0.3), Position = UDim2.fromScale(0.5, 0.65), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = PAL.Outline }, offlineContent)
	offlineBtn.Activated:Connect(closeAll)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	return {
		gui = gui, root = root,
		vento = vento, rate = rate, rateScale = rateScale,
		carretelFill = carretelFill, carretelText = carretelText, collectBtn = collectBtn,
		banner = banner, toasts = toasts, cards = cards,
		pullBtn = pullBtn, pullText = pullText, pullScale = pullScale, pullRing = pullRing, pullRingStroke = pullRingStroke,
		faixa = faixa, shield = shield, hint = hint,
		btnBar = btnBar, btnMail = btnMail, mailBadge = mailBadge, btnRebirth = btnRebirth, btnShop = btnShop, btnSound = btnSound,
		duel = duel, duelNames = duelNames, duelHold = duelHold, duelFill = duelFill,
		flash = flash, flashScale = flashScale, dim = dim,
		barPanel = barPanel, barClock = barClock, barSlots = barSlots, barLinha = barLinha, barVaga = barVaga,
		mailPanel = mailPanel, mailDays = mailDays, mailStreakBtn = mailStreakBtn,
		mailCuts = mailCuts, mailCutsBtn = mailCutsBtn, mailCatch = mailCatch, mailCatchBtn = mailCatchBtn,
		rebirthPanel = rebirthPanel, rebirthTitle = rebirthTitle, rebirthNeed = rebirthNeed, rebirthEpic = rebirthEpic, rebirthBtn = rebirthBtn,
		shopPanel = shopPanel, shopList = shopList,
		offlinePanel = offlinePanel, offlineText = offlineText,
	}
end

-- Efeitos de UI --------------------------------------------------------------------------------------------

local function pop(scale: UIScale)
	scale.Scale = C.POP_SCALE
	TweenService:Create(scale, TweenInfo.new(C.POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Texto em tela cheia por FULLSCREEN_SECONDS (escala FULLSCREEN_FROM → 1, Back/Out).
local function flash(u: UI, text: string, color: Color3)
	u.flash.Text = text
	u.flash.TextColor3 = color
	u.flash.Visible = true
	u.flashScale.Scale = C.FULLSCREEN_FROM
	TweenService:Create(u.flashScale, TweenInfo.new(C.POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	S.flashSeq += 1
	local seq = S.flashSeq
	task.delay(C.FULLSCREEN_SECONDS, function()
		if S.flashSeq == seq then
			u.flash.Visible = false
		end
	end)
end

-- Toast pequeno na pilha do topo (some em TOAST_SECONDS; no máximo TOAST_MAX).
local function toastText(u: UI, text: string, color: Color3?)
	local l = label("Toast", text, { Size = UDim2.fromScale(1, 1 / C.TOAST_MAX), TextColor3 = color or PAL.UIText, FontFace = FONT_BLACK, LayoutOrder = S.toastSeq }, u.toasts)
	stroke(l, PAL.Outline, 2)
	S.toastSeq += 1
	local labels: { TextLabel } = {}
	for _, child in u.toasts:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	table.sort(labels, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #labels - C.TOAST_MAX do
		labels[i]:Destroy()
	end
	task.delay(C.TOAST_SECONDS, function()
		l:Destroy()
	end)
end

-- Painéis ---------------------------------------------------------------------------------------------------

local function panelOf(u: UI, name: string): Frame?
	if name == "bar" then
		return u.barPanel
	elseif name == "mail" then
		return u.mailPanel
	elseif name == "rebirth" then
		return u.rebirthPanel
	elseif name == "shop" then
		return u.shopPanel
	elseif name == "offline" then
		return u.offlinePanel
	end
	return nil
end

local function closePanels(u: UI)
	S.panel = ""
	u.dim.Visible = false
end

local refreshBar, refreshMail, refreshRebirth, refreshShop -- definidas abaixo

local function openPanel(u: UI, name: string)
	if S.panel == name then
		closePanels(u)
		return
	end
	for _, other in { "bar", "mail", "rebirth", "shop", "offline" } do
		local p = panelOf(u, other)
		if p then
			p.Visible = other == name
		end
	end
	S.panel = name
	u.dim.Visible = true
	local p = panelOf(u, name)
	if p then
		local scale = p:FindFirstChild("Escala")
		if scale and scale:IsA("UIScale") then
			scale.Scale = 0.9
			TweenService:Create(scale, TweenInfo.new(C.PANEL_TWEEN, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	if name == "bar" then
		refreshBar(u)
	elseif name == "mail" then
		refreshMail(u)
	elseif name == "rebirth" then
		refreshRebirth(u)
	elseif name == "shop" then
		refreshShop(u)
	end
end

-- Bar do Vento (§5.2): 5 cartas + Linha + Vaga + relógio.
local function refreshBarClock(u: UI)
	local stock = S.stock
	local restockAt = if stock then num(stock.restockAt, 0) else 0
	u.barClock.Text = t("restock", { time = fmtClock(restockAt - os.time()) })
end

refreshBar = function(u: UI)
	clearChildren(u.barSlots, "Frame")
	local stock = S.stock
	local slots: { Patch } = if stock and typeof(stock.slots) == "table" then stock.slots else {}
	if #slots == 0 then
		label("Vazio", t("stockEmpty"), { TextColor3 = PAL.Gray }, u.barSlots)
	end
	for i, slot in slots do
		local rarity = num(slot.rarity, 1)
		local price = num(slot.price, 0)
		local bought = slot.bought == true
		local rc = Config.RARITY_COLORS[rarity] or PAL.Gray
		local card = frame(`Slot{i}`, { Size = UDim2.fromScale(0.19, 1), LayoutOrder = i, BackgroundColor3 = PAL.Outline }, u.barSlots)
		corner(card)
		stroke(card, rc)
		local model = if typeof(slot.model) == "string" then slot.model else "Lisa"
		label("Nome", kiteName(model, nil), { Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.04), FontFace = FONT_BLACK }, card)
		label("Raridade", rarityName(rarity), { Size = UDim2.fromScale(0.9, 0.14), Position = UDim2.fromScale(0.05, 0.28), TextColor3 = rc }, card)
		label("Preco", t("vento", { n = fmtNumber(price) }), { Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.44), TextColor3 = PAL.Sun }, card)
		if slot.special == true then
			label("Especial", t("special"), { Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.6), TextColor3 = PAL.Pink, FontFace = FONT_BLACK }, card)
		end
		local b = pillButton("Comprar", if bought then t("bought") else t("buy"), PAL.Laje, { Size = UDim2.fromScale(0.9, 0.2), Position = UDim2.fromScale(0.05, 0.76) }, card)
		setEnabled(b, not bought and S.Vento >= price)
		b.Activated:Connect(function()
			local cb = HUD.onBuy
			if cb and not bought then
				cb("Kite", i)
			end
		end)
	end
	-- Linha (próximo nível) e vaga (próxima)
	local nextLinha = S.Linha + 1
	if nextLinha > Config.LINHA_MAX then
		u.barLinha.Text = t("linhaMax")
		setEnabled(u.barLinha, false)
	else
		local price = Config.linhaPrice(nextLinha)
		u.barLinha.Text = `{t("line", { n = nextLinha, name = Config.LINHA_NAMES[nextLinha] })}\n{t("vento", { n = fmtNumber(price) })}`
		setEnabled(u.barLinha, S.Vento >= price)
	end
	local nextVaga = S.Vagas + 1
	local vagaPrice = Config.VAGA_PRICE[nextVaga]
	if nextVaga > Config.VAGAS_MAX or not vagaPrice then
		u.barVaga.Text = t("vagaMax")
		setEnabled(u.barVaga, false)
	else
		u.barVaga.Text = `{t("slot", { n = nextVaga })}\n{t("vento", { n = fmtNumber(vagaPrice) })}`
		setEnabled(u.barVaga, S.Vento >= vagaPrice)
	end
	refreshBarClock(u)
end

-- Correio da Laje (§5.4): fila D1-D7 do ciclo atual + 2 dailies.
local function streakClaimable(): boolean -- o servidor decide o resto (reset após 2 dias, trava no D28)
	return today() > num(S.Streak.LastClaimDay, 0)
end

local function dailyProgress(which: string): (number, boolean)
	if num(S.Dailies.Day, 0) ~= today() then
		return 0, false
	end
	local progress = num((S.Dailies :: any)[which], 0)
	local claimed = (S.Dailies :: any)["Claimed" .. which] == true
	return progress, claimed
end

local function dailyClaimable(which: string): boolean
	local progress, claimed = dailyProgress(which)
	return progress >= DAILY[which].goal and not claimed
end

local function refreshBadge(u: UI)
	u.mailBadge.Visible = streakClaimable() or dailyClaimable("Cortes") or dailyClaimable("Pegas")
end

refreshMail = function(u: UI)
	clearChildren(u.mailDays, "Frame")
	local day = num(S.Streak.Day, 0)
	local lastClaim = num(S.Streak.LastClaimDay, 0)
	local saved = num(S.Streak.SaverWeek, 0) == weekIndex() -- Guardar Streak usado nesta semana
	local broke = lastClaim == 0 or (today() - lastClaim >= 2 and not saved)
	local nextDay = if broke then 1 else math.min(day + 1, Config.STREAK_CAP_DAY)
	local cycleStart = ((nextDay - 1) // #Config.STREAK) * #Config.STREAK
	local mult = if cycleStart > 0 then 2 else 1
	for i, amount in Config.STREAK do
		local d = cycleStart + i
		local isNext = d == nextDay
		local done = d < nextDay
		local tile = frame(`Dia{i}`, { Size = UDim2.fromScale(0.135, 1), LayoutOrder = i, BackgroundColor3 = if isNext then PAL.Laje else PAL.Outline, BackgroundTransparency = if done then 0.5 else 0 }, u.mailDays)
		corner(tile)
		stroke(tile, if isNext then PAL.Sun else PAL.Outline)
		label("Dia", t("day", { n = d }), { Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.05), FontFace = FONT_BLACK }, tile)
		label("Valor", fmtNumber(amount * mult), { Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.38), TextColor3 = PAL.Sun }, tile)
		local kite = Config.STREAK_KITE[i]
		if kite then
			label("Pipa", "+ " .. kiteName(kite.model, nil), { Size = UDim2.fromScale(0.9, 0.25), Position = UDim2.fromScale(0.05, 0.7), TextColor3 = Config.RARITY_COLORS[kite.rarity] or PAL.Gray }, tile)
		end
	end
	setEnabled(u.mailStreakBtn, streakClaimable())
	local cuts, cutsClaimed = dailyProgress("Cortes")
	u.mailCuts.Text = t("dailyCuts", { n = cuts })
	u.mailCutsBtn.Text = if cutsClaimed then t("claimed") else t("claim")
	setEnabled(u.mailCutsBtn, dailyClaimable("Cortes"))
	local catches, catchClaimed = dailyProgress("Pegas")
	u.mailCatch.Text = t("dailyCatch", { n = catches })
	u.mailCatchBtn.Text = if catchClaimed then t("claimed") else t("claim")
	setEnabled(u.mailCatchBtn, dailyClaimable("Pegas"))
	refreshBadge(u)
end

-- Renascer (§3.6): custo, Épica no varal, bônus, CONFIRMAR.
local function rebirthCost(): number
	return Config.REBIRTH_BASE * Config.REBIRTH_GROWTH ^ S.Temporadas
end

-- Mesma regra do ShopService.findEpic: Épica ou melhor que não seja a Jornal nem uma Pipa de Temporada.
local function hasEpic(): boolean
	for _, k in S.Kites do
		if k.rarity >= Config.REBIRTH_NEED_RARITY and not k.starter and k.season == 0 then
			return true
		end
	end
	return false
end

refreshRebirth = function(u: UI)
	local maxed = S.Temporadas >= Config.REBIRTH_MAX
	u.rebirthTitle.Text = if maxed then t("rebirthMax") else t("rebirth", { n = S.Temporadas + 1 })
	u.rebirthNeed.Text = t("rebirthNeed", { vento = fmtNumber(rebirthCost()) })
	local epic = hasEpic()
	u.rebirthEpic.Text = if epic then t("epicOk") else t("epicNo")
	u.rebirthEpic.TextColor3 = if epic then PAL.Green else PAL.Red
	setEnabled(u.rebirthBtn, not maxed and epic and S.Vento >= rebirthCost())
end

-- Loja de passes (§5.7): 4 passes + 4 produtos (preço via GetProductInfoAsync em pcall) + Chamar amigo.
local function fetchPrice(key: string, id: number, isPass: boolean, target: TextLabel)
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product)
		end)
		local price = if ok and typeof(info) == "table" then num(info.PriceInRobux, 0) else 0
		local text = if price > 0 then t("robux", { n = price }) else t("soon")
		S.prices[key] = text
		if target.Parent then
			target.Text = text
		end
	end)
end

local function shopRow(u: UI, key: string, isPass: boolean, order: number)
	local id = IDS[key] or 0
	local row = frame(key, { Size = UDim2.fromScale(1, 0.085), LayoutOrder = order, BackgroundColor3 = PAL.Outline }, u.shopList)
	corner(row)
	stroke(row, if isPass then PAL.Sun else PAL.Sky, 2)
	label("Nome", t("item_" .. key), { Size = UDim2.fromScale(0.52, 0.8), Position = UDim2.fromScale(0.02, 0.1), TextXAlignment = Enum.TextXAlignment.Left }, row)
	local price = label("Preco", S.prices[key] or (if id == 0 then t("soon") else "…"), { Size = UDim2.fromScale(0.2, 0.8), Position = UDim2.fromScale(0.55, 0.1), TextColor3 = PAL.Sun }, row)
	local b = pillButton("Comprar", t("buy"), PAL.Laje, { Size = UDim2.fromScale(0.2, 0.8), Position = UDim2.fromScale(0.98, 0.1), AnchorPoint = Vector2.new(1, 0) }, row)
	setEnabled(b, id ~= 0)
	if id ~= 0 and not S.prices[key] then
		fetchPrice(key, id, isPass, price)
	end
	b.Activated:Connect(function()
		if id == 0 then
			return
		end
		pcall(function()
			if isPass then
				MarketplaceService:PromptGamePassPurchase(localPlayer, id)
			else
				MarketplaceService:PromptProductPurchase(localPlayer, id)
			end
		end)
	end)
end

refreshShop = function(u: UI)
	clearChildren(u.shopList, "Frame")
	clearChildren(u.shopList, "TextLabel")
	clearChildren(u.shopList, "TextButton")
	if os.time() - S.pricesAt > C.PRICE_CACHE then
		S.prices = {}
		S.pricesAt = os.time()
	end
	local order = 0
	local function header(text: string)
		order += 1
		label("Cabecalho", text, { Size = UDim2.fromScale(1, 0.06), LayoutOrder = order, TextColor3 = PAL.Gray, TextXAlignment = Enum.TextXAlignment.Left }, u.shopList)
	end
	header(t("passes"))
	for _, key in Config.PASS_ORDER do
		order += 1
		shopRow(u, key, true, order)
	end
	header(t("products"))
	for _, key in Config.PRODUCT_ORDER do
		order += 1
		shopRow(u, key, false, order)
	end
	order += 1
	local invite = pillButton("Convidar", t("invite"), PAL.Hill, { Size = UDim2.fromScale(1, 0.085), LayoutOrder = order }, u.shopList)
	invite.Activated:Connect(function()
		pcall(function()
			SocialService:PromptGameInvite(localPlayer)
		end)
	end)
end

-- Elementos do HUD ------------------------------------------------------------------------------------------

local function refreshCarretel(u: UI)
	local cap = math.max(1, S.CarretelCap)
	local frac = math.clamp(S.Carretel / cap, 0, 1)
	u.carretelFill.Size = UDim2.fromScale(frac, 1)
	u.carretelText.Text = `{t("reel")} {fmtNumber(S.Carretel)} / {fmtNumber(S.CarretelCap)}`
end

local function refreshRate(u: UI)
	u.rate.Text = t("perSec", { n = fmtDecimal(S.Rate) })
end

local function refreshFaixa(u: UI)
	local n = S.faixa
	local mult = Config.FAIXA_MULT[n] or Config.VARAL_MULT
	u.faixa.Text = t("band", { n = n, name = t("band" .. n), mult = fmtDecimal(mult) })
	local fight = n >= 3
	u.faixa.BackgroundColor3 = if fight then PAL.Laje else PAL.UIBg
	u.faixa.TextColor3 = if fight then PAL.UIText else PAL.Gray
end

local function refreshShield(u: UI, now: number)
	local left = S.NovatoUntil - now
	local visible = S.Novato and left > 0
	u.shield.Visible = visible
	if visible then
		u.shield.Text = t("shield", { time = fmtClock(left) })
	end
end

-- Banner de evento/boost pelos atributos de workspace.World (§7.4).
local function refreshBanner(u: UI, now: number)
	local world = Workspace:FindFirstChild("World")
	local text, color = "", PAL.Red
	if world then
		local name = attrString(world, "EventName", "")
		local phase = attrString(world, "EventPhase", "")
		local endsAt = attrNumber(world, "EventEndsAt", 0)
		local rajadaUntil = attrNumber(world, "BoostRajadaUntil", 0)
		local ventoUntil = attrNumber(world, "BoostVentoUntil", 0)
		if name ~= "" and phase ~= "" and endsAt > now then
			local vars = { event = t("event_" .. name), time = fmtClock(endsAt - now) }
			text = if phase == "Warn" then t("eventWarn", vars) else t("eventNow", vars)
			color = if phase == "Warn" then PAL.Lilac else PAL.Red
		elseif world:GetAttribute("Festival") == true then
			text = "▲ " .. t("event_Festival")
			color = PAL.Pink
		elseif rajadaUntil > now then
			text = t("boostBanner", { event = t("event_Rajada"), time = fmtClock(rajadaUntil - now), name = attrString(world, "BoostBy", "") })
			color = PAL.Sky
		elseif ventoUntil > now then
			text = t("boostBanner", { event = t("item_PROD_VENTO_FORTE"), time = fmtClock(ventoUntil - now), name = attrString(world, "BoostBy", "") })
			color = PAL.Sky
		end
	end
	u.banner.Visible = text ~= ""
	if text ~= "" then
		u.banner.Text = text
		u.banner.BackgroundColor3 = color
	end
end

-- Cartas do varal: toque = selecionar, toque longo (PET_HOLD) = estimação.
local function refreshCards(u: UI)
	clearChildren(u.cards, "Frame")
	local cardH = 0.07 / 0.64 -- carta de 0,07 da tela dentro da coluna de 0,64
	for i, k in S.Kites do
		local rc = Config.RARITY_COLORS[k.rarity] or PAL.Gray
		local selected = k.id == S.Selected
		local card = frame(`Carta{k.id}`, { Size = UDim2.fromScale(1, cardH), LayoutOrder = i }, u.cards)
		corner(card)
		stroke(card, if selected then PAL.UIText else rc)
		local swatch = frame("Cor", { Size = UDim2.fromScale(0, 0.26), Position = UDim2.fromScale(0.88, 0.22), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, BackgroundColor3 = kiteColor(k) }, card)
		aspect(swatch, 1)
		stroke(swatch, PAL.Outline, 1)
		label("Nome", kiteName(k.model, k.season), { Size = UDim2.fromScale(0.74, 0.42), Position = UDim2.fromScale(0.04, 0.03), TextXAlignment = Enum.TextXAlignment.Left, FontFace = FONT_BLACK }, card)
		label("Raridade", rarityName(k.rarity) .. (if k.pet then " " .. t("pet") else ""), { Size = UDim2.fromScale(0.92, 0.26), Position = UDim2.fromScale(0.04, 0.45), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = rc }, card)
		local posMult = if selected then (Config.FAIXA_MULT[S.faixa] or Config.VARAL_MULT) else Config.VARAL_MULT
		local renda = if selected then t("inAir") .. " " else ""
		label("Renda", renda .. t("perSec", { n = fmtDecimal(Config.baseRate(k) * posMult) }), { Size = UDim2.fromScale(0.92, 0.24), Position = UDim2.fromScale(0.04, 0.72), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = PAL.Sun }, card)
		local hit = button("Toque", "", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, card)
		local t0 = 0
		hit.InputBegan:Connect(function(input: InputObject)
			if isPress(input) then
				t0 = os.clock()
			end
		end)
		hit.InputEnded:Connect(function(input: InputObject)
			if not isPress(input) or t0 == 0 then
				return
			end
			local held = os.clock() - t0
			t0 = 0
			if held >= C.PET_HOLD then
				local cb = HUD.onPet
				if cb then
					cb(k.id)
				end
			elseif not selected then
				local cb = HUD.onSelect
				if cb then
					cb(k.id)
				end
			end
		end)
	end
end

-- Onboarding (§6): dica + anel no botão (1-3) ou seta 3D (4-6) conforme o passo do funil e a faixa.
local function onboardingTarget(step: number): Vector3?
	if step == 4 then
		return S.lastLandPos
	elseif step == 5 then
		return carretelPos()
	elseif step == 6 then
		return Config.BAR_POS
	end
	return nil
end

function HUD.onboardingStep(n: number): ()
	local u = ui
	if not u then
		return
	end
	S.onbStep = n
	local remover = S.arrowRemove
	if remover then
		remover()
		S.arrowRemove = nil
	end
	local show = n >= 1 and n <= 6
	u.hint.Visible = show
	u.pullRing.Visible = n >= 1 and n <= 3
	if not show then
		return
	end
	local text = t("onb" .. n)
	u.hint.Text = text
	local target = onboardingTarget(n)
	if target then
		S.arrowRemove = KiteRenderer.arrow3D(target, text)
	end
end

local function refreshOnboarding(now: number)
	if S.lastLandPos and now > S.lastLandUntil then
		S.lastLandPos = nil
	end
	local step = 0
	if S.Novato and S.Onboarding < 6 then
		local o = S.Onboarding
		if o <= 1 then
			step = 1
		elseif o == 2 or o == 3 then
			step = if S.faixa >= 2 then 3 else 2
		elseif o == 4 then
			step = 4
		else
			step = if S.Carretel > 0 then 5 else 6
		end
	end
	local target = onboardingTarget(step)
	local key = `{step}:{if target then tostring(target) else ""}`
	if step ~= S.onbStep or key ~= S.onbKey then
		S.onbKey = key
		HUD.onboardingStep(step)
	end
end

-- API pública -------------------------------------------------------------------------------------------------

function HUD.setPressed(down: boolean): ()
	local u = ui
	if not u then
		return
	end
	local info = TweenInfo.new(C.PRESS_SECONDS)
	TweenService:Create(u.pullScale, info, { Scale = if down then C.PRESS_SCALE else 1 }):Play()
	u.pullBtn.BackgroundColor3 = if down then PAL.Laje:Lerp(PAL.Outline, 0.3) else PAL.Laje
end

function HUD.setDuel(active: boolean, endsAt: number, opponent: string?): ()
	local u = ui
	if not u then
		return
	end
	S.duelActive = active
	S.duelEndsAt = endsAt
	u.duel.Visible = active
	if active then
		u.duelNames.Text = t("duelVs", { a = t("you"), b = opponent or "?", linha = S.duelLinha })
		u.duelFill.Size = UDim2.fromScale(1, 1)
	end
	u.pullText.Text = if active then t("hold") else t("pull")
	u.pullText.TextTransparency = 0
end

-- {seed, restockAt, slots = {StockSlot & {bought}}}
function HUD.setStock(stock: { [string]: any }): ()
	S.stock = stock
	local u = ui
	if u and S.panel == "bar" then
		refreshBar(u)
	end
end

-- Patch de State (§7.3): só os campos presentes mudam.
function HUD.applyState(patch: { [string]: any }): ()
	local rateChanged = patch.Rate ~= nil and num(patch.Rate, S.Rate) ~= S.Rate
	S.Vento = num(patch.Vento, S.Vento)
	S.Carretel = num(patch.Carretel, S.Carretel)
	S.CarretelCap = num(patch.CarretelCap, S.CarretelCap)
	S.Rate = num(patch.Rate, S.Rate)
	S.Linha = num(patch.Linha, S.Linha)
	S.Vagas = num(patch.Vagas, S.Vagas)
	S.Temporadas = num(patch.Temporadas, S.Temporadas)
	S.Selected = num(patch.Selected, S.Selected)
	S.NovatoUntil = num(patch.NovatoUntil, S.NovatoUntil)
	S.Onboarding = num(patch.Onboarding, S.Onboarding)
	if typeof(patch.Kites) == "table" then
		S.Kites = patch.Kites
	end
	if typeof(patch.Streak) == "table" then
		S.Streak = patch.Streak
	end
	if typeof(patch.Dailies) == "table" then
		S.Dailies = patch.Dailies
	end
	if patch.Novato ~= nil then
		S.Novato = patch.Novato == true
	end
	local u = ui
	if not u then
		return
	end
	if S.shownVento < 0 then
		S.shownVento = S.Vento
	end
	if rateChanged then
		refreshRate(u)
		pop(u.rateScale)
	end
	if patch.Carretel ~= nil or patch.CarretelCap ~= nil then
		refreshCarretel(u)
	end
	if patch.Kites ~= nil or patch.Selected ~= nil then
		refreshCards(u)
	end
	if patch.Streak ~= nil or patch.Dailies ~= nil then
		refreshBadge(u)
		if S.panel == "mail" then
			refreshMail(u)
		end
	end
	if S.panel == "bar" and (patch.Vento ~= nil or patch.Linha ~= nil or patch.Vagas ~= nil) then
		refreshBar(u)
	end
	if S.panel == "rebirth" and (patch.Vento ~= nil or patch.Kites ~= nil or patch.Temporadas ~= nil) then
		refreshRebirth(u)
	end
end

-- Toasts (§7.3): cada kind com os args combinados com o servidor.
function HUD.toast(kind: string, args: { [string]: any }): ()
	local u = ui
	if not u then
		return
	end
	local a: Patch = if typeof(args) == "table" then args else {}
	local kite = if typeof(a.kite) == "string" then kiteName(a.kite, nil) else ""
	local rarity = num(a.rarity, 0)
	local name = if typeof(a.name) == "string" then a.name else ""
	if kind == "Cortou" then
		flash(u, t("cut"), PAL.Green)
		HUD.setDuel(false, 0, nil)
	elseif kind == "Voou" then
		flash(u, t("flew"), PAL.Red)
		if a.shield == true then
			toastText(u, t("shieldBack"), PAL.Sky)
		end
		HUD.setDuel(false, 0, nil)
	elseif kind == "Sorte" then
		flash(u, t("luck"), PAL.Sun)
	elseif kind == "Pegou" then
		flash(u, t("caught", { kite = kite, rarity = string.upper(rarityName(rarity)) }), Config.RARITY_COLORS[rarity] or PAL.Sun)
	elseif kind == "PegaramSua" then
		toastText(u, t("someoneCaught", { name = name, kite = kite }), PAL.Red)
	elseif kind == "Voada" then
		local wild = a.wild == true or name == ""
		toastText(u, if wild then t("flewWild", { kite = kite }) else t("flewBanner", { kite = kite, name = name }), Config.RARITY_COLORS[rarity] or PAL.UIText)
		if typeof(a.landPos) == "Vector3" then
			S.lastLandPos = a.landPos
			S.lastLandUntil = num(a.untilTime, serverNow() + C.LAND_MEMORY)
		end
	elseif kind == "Duelo" then
		S.duelLinha = num(a.linha, 0)
		local opponent = if a.wild == true then t("wild") elseif typeof(a.opponent) == "string" then a.opponent else nil
		HUD.setDuel(true, num(a.endsAt, serverNow() + Config.RABEIO_TIME + Config.DUEL_TIME), opponent)
	elseif kind == "Dourada" then
		if a.blank == true then
			toastText(u, t("goldenBlank"), PAL.Gray)
		else
			toastText(u, t("golden", { kite = kite, name = name }), Config.RARITY_COLORS[5])
		end
	elseif kind == "Arvore" then
		toastText(u, t("tree", { time = fmtClock(num(a.time, Config.TREE_TIME)) }), PAL.Hill)
	elseif kind == "VendaAuto" then
		toastText(u, t("autoSold", { kite = kite, n = fmtNumber(num(a.n, 0)) }), PAL.Sun)
	elseif kind == "Offline" then
		u.offlineText.Text = t("offline", { n = fmtNumber(num(a.n, 0)), time = fmtLong(num(a.time, 0)) })
		openPanel(u, "offline")
	elseif kind == "Streak" then
		local text = t("streakGot", { day = num(a.day, 0), n = fmtNumber(num(a.n, 0)) })
		if kite ~= "" then
			text ..= " + " .. kite
		end
		toastText(u, text, PAL.Sun)
	elseif kind == "Evento" then
		local event = if typeof(a.event) == "string" then t("event_" .. a.event) else ""
		local endsAt = num(a.endsAt, serverNow())
		local vars = { event = event, time = fmtClock(endsAt - serverNow()) }
		toastText(u, if a.phase == "Warn" then t("eventWarn", vars) else t("eventNow", vars), PAL.Lilac)
		refreshBanner(u, serverNow())
	elseif kind == "Renasceu" then
		flash(u, t("renasceu", { n = num(a.n, S.Temporadas) }), PAL.Lilac)
	elseif kind == "Boost" then
		toastText(u, t(if a.kind == "Rajada" then "boostRajada" else "boostVento", { name = name }), PAL.Sky)
	elseif kind == "Erro" then
		toastText(u, if typeof(a.msg) == "string" then a.msg else t("errDefault"), PAL.Red)
	else
		toastText(u, kind, PAL.Gray)
	end
end

-- Conexões dos botões ---------------------------------------------------------------------------------------

local function wire(u: UI)
	-- PUXAR: InputBegan/InputEnded no botão; soltura global por segurança (dedo que sai do botão)
	u.pullBtn.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			S.pressedByButton = true
			local cb = HUD.onPull
			if cb then
				cb(true)
			end
		end
	end)
	local function release(input: InputObject)
		if isPress(input) and S.pressedByButton then
			S.pressedByButton = false
			local cb = HUD.onPull
			if cb then
				cb(false)
			end
		end
	end
	u.pullBtn.InputEnded:Connect(release)
	UserInputService.InputEnded:Connect(release)

	u.collectBtn.Activated:Connect(function()
		local cb = HUD.onCollect
		if cb then
			cb()
		end
	end)
	u.btnBar.Activated:Connect(function()
		openPanel(u, "bar")
	end)
	u.btnMail.Activated:Connect(function()
		openPanel(u, "mail")
	end)
	u.btnRebirth.Activated:Connect(function()
		openPanel(u, "rebirth")
	end)
	u.btnShop.Activated:Connect(function()
		openPanel(u, "shop")
	end)
	-- Som: a v1 não tem áudio (sem assets externos); o botão guarda a preferência em HUD.soundOn.
	u.btnSound.Activated:Connect(function()
		S.soundOn = not S.soundOn
		HUD.soundOn = S.soundOn
		toastText(u, t("soundState", { state = t(if S.soundOn then "on" else "off") }), PAL.Gray)
		u.btnSound.BackgroundTransparency = if S.soundOn then 0 else 0.4
	end)
	u.barLinha.Activated:Connect(function()
		local cb = HUD.onBuy
		if cb then
			cb("Linha", nil)
		end
	end)
	u.barVaga.Activated:Connect(function()
		local cb = HUD.onBuy
		if cb then
			cb("Vaga", nil)
		end
	end)
	local function claim(which: string)
		return function()
			local cb = HUD.onClaim
			if cb then
				cb(which)
			end
		end
	end
	u.mailStreakBtn.Activated:Connect(claim("Streak"))
	u.mailCutsBtn.Activated:Connect(claim("Cortes"))
	u.mailCatchBtn.Activated:Connect(claim("Pegas"))
	u.rebirthBtn.Activated:Connect(function()
		local cb = HUD.onRebirth
		if cb then
			cb()
		end
		closePanels(u)
	end)
	-- Prompt "Ver estoque" do balcão (MapGen): abre o painel do Bar como o botão BAR.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "VerEstoque" and S.panel ~= "bar" then
			openPanel(u, "bar")
		end
	end)
end

HUD.soundOn = true

-- Loops --------------------------------------------------------------------------------------------------------

-- A cada frame: count-up do Vento, barra do duelo, piscar de "SEGURA!", anel do onboarding.
local function frameTick(u: UI, dt: number)
	if S.shownVento ~= S.Vento then
		local before = math.floor(S.shownVento)
		S.shownVento += (S.Vento - S.shownVento) * math.min(1, dt * C.COUNT_UP)
		if math.abs(S.Vento - S.shownVento) < 0.5 then
			S.shownVento = S.Vento
		end
		if math.floor(S.shownVento) ~= before or S.shownVento == S.Vento then
			u.vento.Text = `{fmtNumber(S.shownVento)} {t("wind")}`
		end
	end
	local clock = os.clock()
	if S.duelActive then
		local left = math.clamp((S.duelEndsAt - serverNow()) / Config.DUEL_TIME, 0, 1)
		u.duelFill.Size = UDim2.fromScale(left, 1)
		local on = math.sin(clock * 2 * math.pi * C.BLINK_HZ) > 0
		u.duelHold.TextTransparency = if on then 0 else 0.6
		u.pullText.TextTransparency = if on then 0 else 0.5
	end
	if u.pullRing.Visible then
		u.pullRingStroke.Transparency = 0.5 + 0.5 * math.sin(clock * 2 * math.pi * C.RING_HZ)
	end
end

-- A cada SLOW_TICK: faixa da própria pipa, distâncias, escudo, banner, relógio do Bar, fim do duelo, onboarding.
local function slowTick(u: UI)
	local now = serverNow()
	local conf = ownConf()
	local faixa = if conf then attrNumber(conf, "Faixa", 0) else 0
	local status = if conf then attrString(conf, "Status", "") else ""
	if faixa ~= S.faixa or status ~= S.ownStatus then
		S.faixa = faixa
		S.ownStatus = status
		refreshFaixa(u)
		refreshCards(u)
	end

	local root = rootPart()
	local nearCarretel, nearBar = false, false
	if root then
		local c = carretelPos()
		nearCarretel = c ~= nil and (root.Position - c).Magnitude <= Config.COLLECT_DIST
		nearBar = (root.Position - Config.BAR_POS).Magnitude <= Config.SHOP_OPEN_DIST
	end
	if nearCarretel ~= S.nearCarretel then
		S.nearCarretel = nearCarretel
		u.collectBtn.Visible = nearCarretel
	end
	if nearBar ~= S.nearBar then
		S.nearBar = nearBar
		u.btnBar.Visible = nearBar
		if not nearBar and S.panel == "bar" then
			closePanels(u)
		end
	end

	refreshShield(u, now)
	refreshBanner(u, now)
	if S.panel == "bar" then
		refreshBarClock(u)
	end
	if S.duelActive and now > S.duelEndsAt + Config.HOLD_GRACE + Config.DUEL_TIME then
		HUD.setDuel(false, 0, nil) -- resultado não chegou: fecha a barra
	end
	refreshOnboarding(now)
end

-- Botão PUXAR em px: BUTTON_HEIGHT da altura da tela, nunca menor que BUTTON_MIN_PX (§6); o anel é 18 % maior.
local function fitButton(u: UI)
	local px = math.max(C.BUTTON_MIN_PX, math.floor(u.gui.AbsoluteSize.Y * C.BUTTON_HEIGHT))
	u.pullBtn.Size = UDim2.fromOffset(px, px)
	local ring = math.floor(px * 1.18)
	u.pullRing.Size = UDim2.fromOffset(ring, ring)
end

local function refreshAll(u: UI)
	fitButton(u)
	u.vento.Text = `{fmtNumber(math.max(0, S.shownVento))} {t("wind")}`
	refreshRate(u)
	refreshCarretel(u)
	refreshFaixa(u)
	refreshCards(u)
	refreshBadge(u)
end

-- Constrói a UI, liga os botões e os loops. Idempotente.
function HUD.start(): ()
	if ui then
		return
	end
	local u = build()
	ui = u
	wire(u)
	if S.shownVento < 0 then
		S.shownVento = S.Vento
	end
	refreshAll(u)
	u.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		fitButton(u)
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		frameTick(u, dt)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= C.SLOW_TICK then
			acc = 0
			slowTick(u)
		end
	end)
	-- respawn: o ScreenGui não reseta (ResetOnSpawn = false); só solta o botão se estava apertado
	localPlayer.CharacterAdded:Connect(function()
		if S.pressedByButton then
			S.pressedByButton = false
			local cb = HUD.onPull
			if cb then
				cb(false)
			end
		end
	end)
end

return HUD
