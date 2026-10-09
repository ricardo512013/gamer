--!strict
--[[
	Cliente (STUB — área "cliente"; o engenheiro do cliente substitui este arquivo).
	Versão final: HUD.start(), KiteRenderer.start(); input (botão, Espaço, ButtonA) → Pull "Down"/"Up";
	conecta State → HUD.applyState, Toast → HUD.toast, ShopStock → HUD.setStock; define HUD.on*;
	SoundService.ListenerLocation = Character. Este stub só espera os remotes e inicia os módulos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HUD = require(script.HUD)
local KiteRenderer = require(script.KiteRenderer)

for _, name in Remotes.NAMES do
	Remotes.get(name)
end

HUD.start()
KiteRenderer.start()
