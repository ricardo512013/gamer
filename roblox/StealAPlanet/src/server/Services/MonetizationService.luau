--!strict
-- Game Passes (player attributes "Pass_<Key>") and Developer Products
-- (ProcessReceipt, idempotent via saved receipt ids).
-- In Studio, items with Id = 0 can be "bought" for free to test everything.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Mutations = require(Shared.Mutations)
local Net = require(Shared.Net)
local Planets = require(Shared.Planets)

local BeltService = require(script.Parent.BeltService)
local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local PlotService = require(script.Parent.PlotService)

local MonetizationService = {}

local passKeyById: { [number]: string } = {}
local productKeyById: { [number]: string } = {}
local rng = Random.new()

local function studioTest(): boolean
	return RunService:IsStudio() and Config.TestPurchasesInStudio
end

local function grantPass(player: Player, key: string, announce: boolean)
	local info = Config.GamePasses[key]
	if not info then
		return
	end
	player:SetAttribute("Pass_" .. key, true)
	CharacterService.Refresh(player)
	DataService.MarkDirty(player)
	if announce then
		Net.Notify(player, info.Icon .. " Thank you! " .. info.Name .. " is now active!", "success")
		Net.Effect(player, "Confetti", {})
		Net.NotifyAll("💜 " .. player.DisplayName .. " bought " .. info.Name .. "!", "info")
	end
end

-- Returns true when the product was granted.
local function grantProduct(player: Player, key: string): boolean
	local info = Config.Products[key]
	if not info or not DataService.Get(player) then
		return false
	end
	if info.Kind == "Cash" then
		local amount = Economy.ScaledReward(PlotService.CashPerSec(player), info.Seconds or 600, info.Minimum or 0)
		DataService.AddCash(player, amount)
		Net.Notify(player, info.Icon .. " +" .. Format.Cash(amount) .. "! Thank you!", "success")
		Net.Effect(player, "Confetti", {})
	elseif info.Kind == "ServerLuck" then
		EventService.AddLuck(Config.ServerLuck.DurationPerPurchase, Config.ServerLuck.Multiplier, player.DisplayName)
	elseif info.Kind == "Event" then
		EventService.StartRandom(player.DisplayName)
	elseif info.Kind == "Lock" then
		PlotService.Lock(player, true)
	elseif info.Kind == "BuyPlanet" then
		local rarity = info.Rarity or "Legendary"
		local id, mutation, from = BeltService.TakePending(player, rarity)
		if not id then
			id = Planets.RandomOfRarity(function()
				return rng:NextNumber()
			end, rarity).Id
			mutation = "None"
		end
		local planetId = id :: string
		local mut = mutation or "None"
		PlotService.AddPlanet(player, planetId, mut, from)
		local def = Planets.Get(planetId)
		if def then
			local label = if mut ~= "None" then Mutations.Get(mut).Name .. " " .. def.Name else def.Name
			Net.Notify(player, "🌟 You got " .. label .. "! Thank you!", "success")
			Net.NotifyAll("💫 " .. player.DisplayName .. " instantly bought a " .. string.upper(def.Rarity) .. " " .. label .. "!", "rare")
		end
		Net.Effect(player, "Confetti", {})
	else
		return false
	end
	DataService.MarkDirty(player)
	return true
end

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local userId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local purchaseId = tostring(receiptInfo.PurchaseId)
	local player = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.Get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(data.Receipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = if type(productId) == "number" then productKeyById[productId] else nil
	if not key then
		warn("[Monetization] Unknown product id " .. tostring(productId) .. " - add it to Config.Products")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(grantProduct, player, key)
	if not ok or not granted then
		warn("[Monetization] Failed to grant " .. key .. ": " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > 50 do
		table.remove(data.Receipts, 1)
	end
	task.spawn(DataService.Save, player, false)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function promptProduct(player: Player, key: string)
	local info = Config.Products[key]
	if not info then
		return
	end
	if info.Id > 0 then
		MarketplaceService:PromptProductPurchase(player, info.Id)
	elseif studioTest() then
		grantProduct(player, key)
	else
		Net.Notify(player, "This item is not available yet!", "error")
	end
end

-- Studio-only free test purchase for items whose Id is still 0.
local function testPurchase(player: Player, kind: any, key: any): Net.Result
	if not studioTest() or type(kind) ~= "string" or type(key) ~= "string" then
		return { ok = false, msg = "Not available" }
	end
	if kind == "Pass" and Config.GamePasses[key] then
		grantPass(player, key, true)
		return { ok = true }
	elseif kind == "Product" and Config.Products[key] then
		return { ok = grantProduct(player, key) }
	end
	return { ok = false, msg = "Unknown item" }
end

function MonetizationService.CheckPasses(player: Player)
	for key, info in Config.GamePasses do
		if info.Id > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, info.Id)
			end)
			if ok and owns then
				grantPass(player, key, false)
			end
		end
	end
end

function MonetizationService.Init()
	for key, info in Config.GamePasses do
		if info.Id > 0 then
			passKeyById[info.Id] = key
		end
	end
	for key, info in Config.Products do
		if info.Id > 0 then
			productKeyById[info.Id] = key
		end
	end
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local key = passKeyById[passId]
		if purchased and key then
			grantPass(player, key, true)
		end
	end)
	BeltService.InstantBuyRequested:Connect(promptProduct)
	Net.Handle("TestPurchase", testPurchase)
	Net.Handle("PromptProduct", function(player: Player, key: any): Net.Result
		if type(key) ~= "string" or not Config.Products[key] then
			return { ok = false }
		end
		promptProduct(player, key)
		return { ok = true }
	end)
end

return MonetizationService
