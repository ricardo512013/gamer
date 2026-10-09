--!strict
--[[
	MapGen (STUB — área "mapa") — gera o Morro do Vento (GDD §4) com Random.new(Config.SEED):
	terreno, campinho, Bar, Poste, Árvore, 12 lajes (tag Laje + Attributes Index/OwnerId/Angle/VaralCodes,
	carretel com tag Carretel + ProximityPrompt, LajeIndex), casas de enfeite, paredes.
	Também cria os contêineres de runtime: workspace/Map (Folder), workspace/KiteStates (Folder) e
	workspace/World (Configuration com WindSign=1, EventName, EventPhase, EventEndsAt, Festival, RestockAt,
	BoostRajadaUntil, BoostVentoUntil, BoostBy). Depende SÓ de Config (nunca de DataService).
	O stub devolve Models vazios com os Attributes certos para o DataService atribuir lajes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MapGen = {}

local lajes: { [number]: Model } = {}

-- Ângulo (rad) da laje i: (i-1) × 360°/LAJE_COUNT.
function MapGen.lajeAngle(i: number): number
	return (i - 1) * (2 * math.pi / Config.LAJE_COUNT)
end

-- Centro do piso da laje i (y = LAJE_FLOOR_Y).
function MapGen.lajeFloor(i: number): Vector3
	local a = MapGen.lajeAngle(i)
	return Vector3.new(Config.LAJE_RADIUS * math.cos(a), Config.LAJE_FLOOR_Y, Config.LAJE_RADIUS * math.sin(a))
end

-- Posição do carretel da laje i (stub: centro do piso).
function MapGen.carretelPos(i: number): Vector3
	warn("[MapGen] stub carretelPos")
	return MapGen.lajeFloor(i)
end

-- Model da laje i (stub: Model vazio, não parentado, com os Attributes do GDD §7.4).
function MapGen.lajeModel(i: number): Model
	local model = lajes[i]
	if not model then
		model = Instance.new("Model")
		model.Name = `Laje_{i}`
		model:SetAttribute("Index", i)
		model:SetAttribute("OwnerId", 0)
		model:SetAttribute("Angle", MapGen.lajeAngle(i))
		model:SetAttribute("VaralCodes", "")
		model:AddTag("Laje")
		lajes[i] = model
	end
	return model
end

-- Idempotente: destrói workspace.Map antes de gerar de novo.
function MapGen.start(): ()
	warn("[MapGen] stub: mapa não gerado")
end

return MapGen
