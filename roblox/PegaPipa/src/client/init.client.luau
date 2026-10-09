--!strict
--[[
	Bootstrap do cliente (LocalScript; HUD e KiteRenderer são filhos: script.HUD / script.KiteRenderer).

	• Inicia HUD e KiteRenderer (cada um em pcall: um módulo quebrado não derruba o outro).
	• Input → Pull: InputBegan/InputEnded no botão PUXAR (HUD.onPull), tecla Espaço e Gamepad ButtonA
	  (ContextActionService) → Remotes "Pull" com "Down"/"Up" + HUD.setPressed. Nunca manda "Down" duas vezes.
	• Callbacks do HUD → remotes: SelectKite(kiteId), Buy(kind, slot), ClaimStreak(), ClaimDaily(which),
	  Rebirth(), Emote(id), Collect() (+ burst do carretel), SetPet(kiteId).
	• Remotes S→C: State → HUD.applyState; Toast → HUD.toast (+ vibração no "Voou", marcador no "Voada");
	  ShopStock → HUD.setStock. Por fim dispara "Ready" para o servidor reenviar State/ShopStock.
	• SoundService.ListenerLocation = Character (áudio 3D segue o personagem).
	Usa só Remotes.get (WaitForChild com timeout) e Config.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local HapticService = game:GetService("HapticService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local HUD = require(script.HUD)
local KiteRenderer = require(script.KiteRenderer)

local C = Config.CLIENT
local PAL = Config.PALETTE
local localPlayer = Players.LocalPlayer

-- Áudio 3D segue o personagem (propriedade nova da Audio API; pcall para builds sem ela).
pcall(function()
	(SoundService :: any).ListenerLocation = Enum.ListenerLocation.Character
end)

-- Módulos ---------------------------------------------------------------------------------------------------

local function boot(name: string, fn: () -> ())
	local ok, err = pcall(function(): string?
		fn()
		return nil
	end)
	if not ok then
		warn(`[Cliente] {name} falhou: {err}`)
	end
end

boot("HUD", HUD.start)
boot("KiteRenderer", KiteRenderer.start)

-- Remotes ---------------------------------------------------------------------------------------------------

local pullRemote = Remotes.get("Pull")
local selectRemote = Remotes.get("SelectKite")
local collectRemote = Remotes.get("Collect")
local buyRemote = Remotes.get("Buy")
local claimStreakRemote = Remotes.get("ClaimStreak")
local claimDailyRemote = Remotes.get("ClaimDaily")
local rebirthRemote = Remotes.get("Rebirth")
local emoteRemote = Remotes.get("Emote")
local setPetRemote = Remotes.get("SetPet")
local readyRemote = Remotes.get("Ready")
local stateRemote = Remotes.get("State")
local toastRemote = Remotes.get("Toast")
local shopRemote = Remotes.get("ShopStock")

-- Botão PUXAR (§2.3): "Down" ao apertar, "Up" ao soltar; nunca repete a mesma fase.
local pressed = false

local function pull(down: boolean)
	if down == pressed then
		return
	end
	pressed = down
	pullRemote:FireServer(if down then "Down" else "Up")
	HUD.setPressed(down)
end

HUD.onPull = pull

-- Espaço e Gamepad ButtonA; Pass para não roubar o pulo nem a UI; ignora com caixa de texto focada.
ContextActionService:BindAction("PegaPipaPuxar", function(_actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if inputState == Enum.UserInputState.Begin then
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		pull(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		pull(false)
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

UserInputService.WindowFocusReleased:Connect(function()
	pull(false)
end)

-- Posição do próprio carretel (para o burst da coleta).
local function carretelPos(): Vector3?
	local laje = localPlayer:GetAttribute("Laje")
	for _, inst in CollectionService:GetTagged("Carretel") do
		if inst:IsA("BasePart") and inst:GetAttribute("LajeIndex") == laje then
			return inst.Position
		end
	end
	return nil
end

-- Callbacks do HUD → remotes (o servidor valida tudo).
HUD.onSelect = function(id: number)
	selectRemote:FireServer(id)
end
HUD.onBuy = function(kind: string, slot: number?)
	buyRemote:FireServer(kind, slot)
end
HUD.onClaim = function(which: string)
	if which == "Streak" then
		claimStreakRemote:FireServer()
	else
		claimDailyRemote:FireServer(which)
	end
end
HUD.onRebirth = function()
	rebirthRemote:FireServer()
end
HUD.onEmote = function(id: number)
	emoteRemote:FireServer(id)
end
HUD.onPet = function(id: number)
	setPetRemote:FireServer(id)
end
-- 8 Parts amarelas voam do próprio carretel para a câmera (§2.9): botão PEGAR VENTO e prompt do carretel.
local function burstAtCarretel()
	local pos = carretelPos()
	if pos then
		KiteRenderer.burst(pos + Vector3.new(0, C.LINE_ANCHOR_UP, 0), PAL.Sun, C.BURST_PARTS)
	end
end
HUD.onCollect = function()
	collectRemote:FireServer()
	burstAtCarretel()
end
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
	local part = prompt.Parent
	if prompt.Name == "PegarVento" and part and part:GetAttribute("LajeIndex") == localPlayer:GetAttribute("Laje") then
		burstAtCarretel() -- o servidor já coletou pelo Triggered do prompt
	end
end)

-- Vibração no gamepad ao perder um duelo (§2.9).
local function haptic()
	pcall(function()
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.LeftHand, 1)
		task.delay(C.HAPTIC_SECONDS, function()
			pcall(function()
				HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.LeftHand, 0)
			end)
		end)
	end)
end

-- S→C -------------------------------------------------------------------------------------------------------

stateRemote.OnClientEvent:Connect(function(patch: any)
	if typeof(patch) == "table" then
		HUD.applyState(patch)
	end
end)

toastRemote.OnClientEvent:Connect(function(kind: any, args: any)
	if typeof(kind) ~= "string" then
		return
	end
	local a: { [string]: any } = if typeof(args) == "table" then args else {}
	HUD.toast(kind, a)
	if kind == "Voou" then
		haptic()
	elseif kind == "Voada" and typeof(a.landPos) == "Vector3" then
		local untilTime = if typeof(a.untilTime) == "number" then a.untilTime else 0
		local rarity = if typeof(a.rarity) == "number" then a.rarity else 1
		KiteRenderer.showMarker(a.landPos, untilTime, rarity)
	end
end)

shopRemote.OnClientEvent:Connect(function(stock: any)
	if typeof(stock) == "table" then
		HUD.setStock(stock)
	end
end)

-- Personagem: ao renascer, solta o botão (o estado do HUD/render não depende do personagem).
localPlayer.CharacterAdded:Connect(function()
	pull(false)
end)

-- Tudo ligado: pede o State completo e o estoque (o load do perfil pode ter disparado antes de ouvirmos).
readyRemote:FireServer()
