--!strict
--[[
	MonetizationService (STUB — área "economia") — passes e produtos (GDD §5.7): ProcessReceipt idempotente
	(PurchaseId em profile.Data.Purchases, PurchaseGranted só depois do Save), PromptGamePassPurchaseFinished,
	cache de passes por sessão, Kit no load, atributo VIP do Player.
	Requer: Config, DataService, KiteService (rescueFromTree), ShopService (grantKit, useStreakSaver),
	EventService (startServerBoost). É a camada mais alta: ninguém requer este módulo.
	Registra DataService.hooks.ventoMult / hasAutoReel / isVIP / offlineCap no start().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local DataService = require(script.Parent.DataService)

local MonetizationService = {}

function MonetizationService.start(): ()
	DataService.hooks.ventoMult = MonetizationService.ventoMult
	DataService.hooks.hasAutoReel = MonetizationService.hasAutoReel
	DataService.hooks.isVIP = MonetizationService.isVIP
	DataService.hooks.offlineCap = MonetizationService.offlineCap
	warn("[MonetizationService] stub", Config.IDS.PASS_VIP)
end

-- key = chave de Config.IDS (PASS_VENTO_DOBRO, PASS_CARRETEL_AUTO, PASS_VIP, PASS_KIT); cache por sessão.
function MonetizationService.ownsPass(p: Player, key: string): boolean
	return false
end

-- 2 com Vento em Dobro, senão 1.
function MonetizationService.ventoMult(p: Player): number
	return 1
end

function MonetizationService.hasAutoReel(p: Player): boolean
	return false
end

function MonetizationService.isVIP(p: Player): boolean
	return false
end

-- OFFLINE_CAP ou OFFLINE_CAP_VIP (segundos).
function MonetizationService.offlineCap(p: Player): number
	return Config.OFFLINE_CAP
end

return MonetizationService
