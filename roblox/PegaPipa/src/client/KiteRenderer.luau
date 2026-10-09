--!strict
--[[
	KiteRenderer (STUB — área "cliente") — desenha pipas, linhas, rabiolas, varais, marcadores e efeitos
	só com Parts/Tweens (GDD §2.9, §4). Assina as tags Kite (Configurations em workspace.KiteStates) e Laje.
	Lerp de Pos a cada frame para a própria pipa e a SYNC_HZ para as outras. Requer SÓ Config.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local KiteRenderer = {}

function KiteRenderer.start(): ()
	warn("[KiteRenderer] stub", Config.SYNC_HZ)
end

-- Model da pipa (Parts da §2.9/§4); scale 0.4 no varal.
function KiteRenderer.build(model: string, rarity: number, color: number, golden: boolean, scale: number): Model
	warn("[KiteRenderer] stub build")
	local m = Instance.new("Model")
	m.Name = model
	return m
end

-- Cria o render de um KiteState (Configuration com Attributes §7.4) e começa a interpolar.
function KiteRenderer.attach(conf: Configuration): ()
	warn("[KiteRenderer] stub attach")
end

function KiteRenderer.detach(conf: Configuration): ()
	warn("[KiteRenderer] stub detach")
end

-- Coluna Neon 2×200×2 na cor da raridade até untilTime (GetServerTimeNow).
function KiteRenderer.showMarker(pos: Vector3, untilTime: number, rarity: number): ()
	warn("[KiteRenderer] stub showMarker")
end

-- codes = "model:rarity:color:golden,…" (atributo VaralCodes da laje).
function KiteRenderer.renderVaral(laje: Model, codes: string): ()
	warn("[KiteRenderer] stub renderVaral")
end

-- Seta 3D de onboarding; devolve a função que a remove.
function KiteRenderer.arrow3D(pos: Vector3, text: string): () -> ()
	warn("[KiteRenderer] stub arrow3D", text)
	return function() end
end

-- n Parts Neon voando de pos (coleta, rabeio).
function KiteRenderer.burst(pos: Vector3, color: Color3, n: number): ()
	warn("[KiteRenderer] stub burst")
end

return KiteRenderer
