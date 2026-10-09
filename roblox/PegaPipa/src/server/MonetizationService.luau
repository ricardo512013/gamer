--!strict
--[[
	MonetizationService — passes e produtos (GDD §5.7).

	- Passes (Config.IDS.PASS_*): posse em cache por sessão (UserOwnsGamePassAsync em pcall ao entrar);
	  PromptGamePassPurchaseFinished atualiza o cache na hora. Efeitos: Vento em Dobro → ventoMult =
	  PASS_VENTO_DOBRO_MULT; Carretel Automático → hasAutoReel; VIP da Laje → isVIP, atributo VIP do Player e
	  offlineCap = OFFLINE_CAP_VIP; Kit Pipeiro → ShopService.grantKit no load (1×, KitClaimed).
	  Os quatro entram no DataService por DataService.hooks (registrados no start()).
	- Produtos (Config.IDS.PROD_*): MarketplaceService.ProcessReceipt idempotente (cheat sheet §7.2):
	  o PurchaseId fica em profile.Data.Purchases (últimos PURCHASE_HISTORY); conceder → profile:Save() →
	  PurchaseGranted só quando profile.LastSavedData.Purchases contém o id (até RECEIPT_SAVE_TIMEOUT s;
	  senão NotProcessedYet e a Roblox chama de novo). Rajada no Servidor / Vento Forte →
	  EventService.startServerBoost; Resgatar da Árvore → KiteService.rescueFromTree; Guardar Streak →
	  ShopService.useStreakSaver. Produto que não tinha o que conceder (nenhuma pipa na árvore, saver já usado
	  na semana) é registrado mesmo assim — o Robux já foi gasto — e o jogador recebe Toast("Erro").
	  Nenhum produto da v1 dá Vento; se algum der, use DataService.addVento(p, n, "Produto").
	- Ids 0 (placeholders até a publicação) = não configurado: o passe conta como não possuído e o produto
	  não tem handler. Nada aqui yielda fora da thread de PlayerAdded (ownsPass só espera a consulta inicial).
	Requer: Config, DataService, KiteService, ShopService, EventService (camada mais alta; ninguém o requer).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local DataService = require(script.Parent.DataService)
local KiteService = require(script.Parent.KiteService)
local ShopService = require(script.Parent.ShopService)
local EventService = require(script.Parent.EventService)

type ProfileData = Config.ProfileData
type Profile = DataService.Profile
type ReceiptInfo = { [string]: any }
type ProductHandler = (p: Player) -> boolean -- false = não havia o que conceder

local IDS = (Config.IDS :: any) :: { [string]: number }
local PASS_KEYS = { "PASS_VENTO_DOBRO", "PASS_CARRETEL_AUTO", "PASS_VIP", "PASS_KIT" }
local SAVE_POLL = 1 -- s entre checagens do LastSavedData no ProcessReceipt (não é regra de jogo)

local MonetizationService = {}

local passCache: { [Player]: { [string]: boolean } } = {}
local loading: { [Player]: boolean } = {}
local started = false

-- Produtos: chave de Config.IDS → concessão.
local PRODUCTS: { [string]: ProductHandler } = {
	PROD_RAJADA = function(p: Player): boolean
		EventService.startServerBoost("Rajada", p)
		return true
	end,
	PROD_VENTO_FORTE = function(p: Player): boolean
		EventService.startServerBoost("VentoForte", p)
		return true
	end,
	PROD_RESGATE = function(p: Player): boolean
		return KiteService.rescueFromTree(p)
	end,
	PROD_GUARDAR_STREAK = function(p: Player): boolean
		return ShopService.useStreakSaver(p)
	end,
}
-- Chave de Config.STRINGS do Toast("Erro") quando o produto não tinha o que conceder.
local PRODUCT_FAIL_KEY: { [string]: string } = { PROD_RESGATE = "errNoTree", PROD_GUARDAR_STREAK = "errSaverUsed" }

-- Passes -----------------------------------------------------------------------------------------

local function idOf(key: string): number
	return IDS[key] or 0
end

-- Consulta os passes configurados de p (pcall; falha = não possui) e guarda no cache da sessão.
local function loadPasses(p: Player)
	if loading[p] then
		return
	end
	loading[p] = true
	local owned: { [string]: boolean } = {}
	for _, key in PASS_KEYS do
		local id = idOf(key)
		if id ~= 0 then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, p.UserId, id)
			if ok then
				owned[key] = result == true
			else
				warn(`[MonetizationService] UserOwnsGamePassAsync({key}) falhou para {p.Name}: {result}`)
			end
		end
	end
	local previous = passCache[p] -- compra concluída enquanto a consulta rodava
	if previous then
		for key, has in previous do
			if has then
				owned[key] = true
			end
		end
	end
	if p.Parent == Players then
		passCache[p] = owned
	end
	loading[p] = nil
end

-- Posse de um passe (key = chave de Config.IDS). Id 0 → false. Só yielda enquanto a consulta inicial de p
-- ainda roda (ou se ela nunca rodou), o que só acontece na thread de PlayerAdded do DataService.
function MonetizationService.ownsPass(p: Player, key: string): boolean
	if idOf(key) == 0 then
		return false
	end
	if passCache[p] == nil then
		if loading[p] then
			while loading[p] do
				task.wait()
			end
		else
			loadPasses(p)
		end
	end
	local owned = passCache[p]
	return owned ~= nil and owned[key] == true
end

local function onPassGranted(p: Player, key: string)
	if key == "PASS_VIP" then
		p:SetAttribute("VIP", true)
	elseif key == "PASS_KIT" then
		ShopService.grantKit(p)
	end
	-- Vento em Dobro / Carretel Automático: o DataService lê os hooks a cada INCOME_TICK
end

local function onPassPurchaseFinished(p: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	for _, key in PASS_KEYS do
		if idOf(key) == passId then
			local owned = passCache[p] or {}
			passCache[p] = owned
			owned[key] = true
			onPassGranted(p, key)
		end
	end
end

-- Produtos (ProcessReceipt) ----------------------------------------------------------------------

local function productKeyOf(productId: number): string?
	for key in PRODUCTS do
		local id = idOf(key)
		if id ~= 0 and id == productId then
			return key
		end
	end
	return nil
end

local function rememberPurchase(data: ProfileData, purchaseId: string)
	table.insert(data.Purchases, purchaseId)
	while #data.Purchases > Config.PURCHASE_HISTORY do
		table.remove(data.Purchases, 1)
	end
end

-- Salva e só confirma quando o id aparece no último snapshot salvo (LastSavedData).
local function confirmSaved(profile: Profile, purchaseId: string): Enum.ProductPurchaseDecision
	profile:Save()
	local deadline = os.clock() + Config.RECEIPT_SAVE_TIMEOUT
	while os.clock() < deadline and profile:IsActive() do
		if table.find(profile.LastSavedData.Purchases, purchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		task.wait(SAVE_POLL)
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet -- já está no Data: a próxima chamada confirma
end

local function processReceipt(receipt: ReceiptInfo): Enum.ProductPurchaseDecision
	local playerId, purchaseId, productId = receipt.PlayerId, receipt.PurchaseId, receipt.ProductId
	if typeof(playerId) ~= "number" or typeof(purchaseId) ~= "string" or typeof(productId) ~= "number" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local p = Players:GetPlayerByUserId(playerId)
	if not p then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- saiu: a Roblox tenta de novo quando ele voltar
	end
	local profile = DataService.get(p)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- perfil ainda não carregou
	end
	if table.find(profile.LastSavedData.Purchases, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- já concedido e salvo
	end
	local data = profile.Data
	if not table.find(data.Purchases, purchaseId) then
		local key = productKeyOf(productId)
		if not key then
			warn(`[MonetizationService] produto sem handler: {productId}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local ok, granted = pcall(PRODUCTS[key], p)
		if not ok then
			warn(`[MonetizationService] falha ao conceder {key} para {p.Name}: {granted}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if granted == false then
			local msgKey = PRODUCT_FAIL_KEY[key] or "errProduct"
			DataService.toast(p, "Erro", { msg = Config.str(msgKey, "pt-BR"), key = msgKey })
		end
		rememberPurchase(data, purchaseId)
		print(`[Economia] {p.Name} comprou {key} ({purchaseId})`)
	end
	return confirmSaved(profile, purchaseId)
end

-- API pública -------------------------------------------------------------------------------------

-- PASS_VENTO_DOBRO_MULT com Vento em Dobro, senão 1.
function MonetizationService.ventoMult(p: Player): number
	return if MonetizationService.ownsPass(p, "PASS_VENTO_DOBRO") then Config.PASS_VENTO_DOBRO_MULT else 1
end

function MonetizationService.hasAutoReel(p: Player): boolean
	return MonetizationService.ownsPass(p, "PASS_CARRETEL_AUTO")
end

function MonetizationService.isVIP(p: Player): boolean
	return MonetizationService.ownsPass(p, "PASS_VIP")
end

-- OFFLINE_CAP ou OFFLINE_CAP_VIP (segundos).
function MonetizationService.offlineCap(p: Player): number
	return if MonetizationService.isVIP(p) then Config.OFFLINE_CAP_VIP else Config.OFFLINE_CAP
end

local function onLoaded(p: Player, data: ProfileData)
	p:SetAttribute("VIP", MonetizationService.isVIP(p)) -- garante o valor caso o cache tenha chegado depois do load
	if not data.KitClaimed and MonetizationService.ownsPass(p, "PASS_KIT") then
		ShopService.grantKit(p)
	end
end

function MonetizationService.start(): ()
	DataService.hooks.ventoMult = MonetizationService.ventoMult
	DataService.hooks.hasAutoReel = MonetizationService.hasAutoReel
	DataService.hooks.isVIP = MonetizationService.isVIP
	DataService.hooks.offlineCap = MonetizationService.offlineCap
	if started then
		return
	end
	started = true
	MarketplaceService.ProcessReceipt = processReceipt -- definido uma única vez
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchaseFinished)
	Players.PlayerAdded:Connect(function(p: Player)
		task.spawn(loadPasses, p)
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		passCache[p] = nil
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(loadPasses, p)
	end
	DataService.onLoaded(onLoaded)
	local configured = 0
	for _, id in IDS do
		if id ~= 0 then
			configured += 1
		end
	end
	if configured == 0 then
		warn("[MonetizationService] Config.IDS são placeholders (0): passes e produtos desativados até a publicação")
	end
end

return MonetizationService
