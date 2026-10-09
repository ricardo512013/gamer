--!strict
--[[
	Config — TODAS as constantes do jogo (GDD §7.5), os tipos de dados do perfil (§5.1/§7.2),
	o template do perfil, a tabela de strings pt-BR/en (§6) e três ajudantes:
	Config.rarityOf(model), Config.baseRate(kite) e Config.str(key, locale, vars).

	Regra do projeto: nenhum número vive fora deste arquivo. O GDD é a fonte; este arquivo é a cópia.
	Chaves marcadas com "(impl.)" foram adicionadas pela implementação e não estão no bloco do GDD.
]]

local Config = {}

-- Tipos -----------------------------------------------------------------------------------------

export type KiteData = {
	id: number,
	model: string, -- Jornal | Lisa | Estrela | Arraia | Morcegao | Luz | Capivara | Raio | Pipeiro | Temporada
	rarity: number, -- 1..6
	color: number, -- 0 Jornal, 1-8 cosméticas, 9 Festival, 10 Raio, 11 Pipeiro, 100+n Temporada n
	golden: boolean,
	pet: boolean, -- estimação (sobrevive ao renascer)
	season: number, -- 0 = normal; n = Pipa de Temporada n
	starter: boolean, -- Pipa de Jornal: nunca perdida nem vendida
}

export type ProfileData = {
	Vento: number,
	Carretel: number,
	Linha: number,
	Vagas: number,
	Temporadas: number,
	Kites: { KiteData },
	NextKiteId: number,
	Selected: number, -- id da pipa selecionada (0 = nenhuma)
	PlayTime: number, -- segundos jogados (Novato enquanto < NOVATO_SECONDS)
	LastSeen: number, -- os.time() da última vez online (renda offline)
	Onboarding: number, -- último passo do funil concluído (0..6)
	KitClaimed: boolean,
	Streak: { Day: number, LastClaimDay: number, SaverWeek: number },
	Dailies: { Day: number, Cortes: number, Pegas: number, ClaimedCortes: boolean, ClaimedPegas: boolean },
	Stats: { Cortes: number, CortesPvP: number, Pegas: number, VentoTotal: number },
	Weekly: { Week: number, Vento: number, CortesPvP: number },
	Purchases: { string }, -- últimos PURCHASE_HISTORY PurchaseIds (idempotência do ProcessReceipt)
}

type StreakKite = { model: string, rarity: number, color: number? }
type EventDef = { name: string, chance: number, duration: number }

-- Mundo -----------------------------------------------------------------------------------------

Config.SEED = 2026
Config.MAX_PLAYERS = 12 -- Creator Hub: 12, reservados 2
Config.MAP_RADIUS = 200
Config.LAJE_RADIUS = 120 -- 12 lajes a cada 30°
Config.LAJE_COUNT = 12 -- (impl.) número de lajes
Config.LAJE_FLOOR_Y = 26.5
Config.CAMPINHO = { sizeX = 80, sizeZ = 50, landX = 35, landZ = 20 }
Config.BAR_POS = Vector3.new(0, 1.5, -38)
Config.TREE_TOP = Vector3.new(46, 20, 30)
Config.POSTE_POS = Vector3.new(16, 12, -42)
Config.SPAWN_POS = Vector3.new(0, 1, -32)

-- Faixas ----------------------------------------------------------------------------------------

Config.FAIXA_MULT = { [0] = 0.25, [1] = 0.5, [2] = 1.0, [3] = 1.6, [4] = 2.5 } :: { [number]: number }
Config.FAIXA_HEIGHT_ABOVE_LAJE = { [0] = 4, [1] = 35, [2] = 70 } :: { [number]: number } -- faixas 1-2 (y = 61.5 / 96.5); [0] (impl.) = pousada sobre o carretel
Config.RING = {
	[3] = { r = 60, h = 105, omega = 0.05 },
	[4] = { r = 50, h = 125, omega = 0.08 },
} :: { [number]: { r: number, h: number, omega: number } }
Config.RARITY_WEIGHT_STEP = 0.08 -- peso = 1 - 0.08*(raridade-1)
Config.KITE_MOVE_SPEED = 30 -- studs/s nas transições
Config.VARAL_MULT = 0.25
Config.OFFLINE_MULT = 0.25
Config.OFFLINE_CAP = 8 * 3600
Config.OFFLINE_CAP_VIP = 12 * 3600
Config.OFFLINE_MIN = 60
Config.CARRETEL_CAP_SECONDS = 900
Config.COLLECT_DIST = 12
Config.AFK_SECONDS = 180
Config.AFK_DROP_EVERY = 90
Config.REBIRTH_BONUS = 0.15
Config.FRIEND_BONUS = 1.1

-- Botão -----------------------------------------------------------------------------------------

Config.TAP_MAX = 0.25
Config.TAP_COOLDOWN = 0.8
Config.HOLD_DESCEND_EVERY = 0.5
Config.RABEIO_RANGE = 25
Config.RABEIO_DIVE = 12
Config.RABEIO_TIME = 0.4
Config.DUEL_TIME = 2.0
Config.HOLD_GRACE = 0.3
Config.HOLD_BONUS = 3
Config.DUEL_RANDOM = 2
Config.POST_DUEL_IMMUNITY = 3
Config.WILD_POINTS = { [1] = 3, [2] = 5, [3] = 8, [4] = 10, [5] = 12, [6] = 14 } :: { [number]: number }
Config.TUTORIAL_WILD_POINTS = 0
Config.TUTORIAL_AT = 40 -- s de sessão do novato
Config.NOVATO_SECONDS = 1200

-- Queda / pega / árvore -------------------------------------------------------------------------

Config.FALL_TIME = 10
Config.GROUND_TIME = 20
Config.CATCH_RADIUS = 7
Config.TREE_CATCH_RADIUS = 6
Config.TREE_TIME = 180
Config.TELEPORT_JUMP = 40 -- studs em 0.5 s
Config.TELEPORT_PENALTY = 3
Config.RAIN_FALL_TIME = 5
Config.RAIN_FROM_Y = 60

-- Selvagens -------------------------------------------------------------------------------------

Config.WILD_INTERVAL = { 20, 40 }
Config.WILD_MAX = 3
Config.WILD_SPEED = 6
Config.WILD_RING_R = 55
Config.WILD_OMEGA = 0.06

-- Raridades (ids 1..6) --------------------------------------------------------------------------

Config.RARITY_NAMES = { "Comum", "Incomum", "Rara", "Epica", "Lendaria", "Mitica" }
Config.BASE_RATE = { 1, 4, 15, 60, 250, 1200 }
Config.WILD_TABLE = { 55, 28, 12, 4, 0.9, 0.1 } -- soma 100
Config.WILD_TABLE_RAJADA = { 30, 43.5, 18.7, 6.2, 1.4, 0.2 } -- soma 100
Config.SHOP_TABLE = { 50, 30, 15, 4.5, 0.5, 0 } -- soma 100
Config.SHOP_SPECIAL_TABLE = { 0, 0, 70, 25, 5, 0 } -- soma 100
Config.SHOP_PRICE = { 60, 450, 3000, 18000, 100000, math.huge }
Config.MODEL_BY_RARITY = { "Lisa", "Estrela", "Arraia", "Morcegao", "Luz", "Capivara" }
Config.MODEL_RARITY = { -- (impl.) modelo → raridade (base de Config.rarityOf)
	Jornal = 1, Lisa = 1, Estrela = 2, Arraia = 3, Morcegao = 4, Luz = 5, Capivara = 6,
	Raio = 3, Pipeiro = 3, Temporada = 4,
} :: { [string]: number }
Config.GOLDEN_MULT = 5
Config.AUTO_SELL_MULT = 30
Config.COLORS = { -- índice → Color3 ; 0 = Jornal
	[0] = Color3.fromRGB(235, 225, 200), Color3.fromRGB(235, 60, 50), Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(95, 185, 90), Color3.fromRGB(60, 140, 255), Color3.fromRGB(255, 140, 60),
	Color3.fromRGB(255, 120, 170), Color3.fromRGB(170, 130, 230), Color3.fromRGB(245, 245, 245),
	[9] = Color3.fromRGB(0, 230, 230), [10] = Color3.fromRGB(255, 255, 0), [11] = Color3.fromRGB(20, 50, 120),
} :: { [number]: Color3 }
Config.SEASON_COLOR_BASE = 100 -- (impl.) cor da Temporada n = SEASON_COLOR_BASE + n
Config.RARITY_COLORS = { Color3.fromRGB(190, 190, 190), Color3.fromRGB(80, 200, 100), Color3.fromRGB(60, 140, 255),
	Color3.fromRGB(170, 80, 230), Color3.fromRGB(255, 190, 40), Color3.fromRGB(255, 60, 200) }

-- Loja fixa -------------------------------------------------------------------------------------

Config.LINHA_MAX = 10
Config.LINHA_NAMES = { "Brisa", "Brisa Forte", "Rajada", "Rajada Forte", "Ventania", "Vendaval", "Trovao", "Tempestade", "Furacao", "Ciclone" }
function Config.linhaPrice(n: number): number -- n = 2..10
	return 300 * 2 ^ (n - 2)
end
Config.VAGA_PRICE = { [4] = 2000, [5] = 8000, [6] = 30000, [7] = 120000, [8] = 500000 } :: { [number]: number }
Config.VAGAS_START, Config.VAGAS_MAX = 3, 8
Config.RESTOCK_SECONDS = 300
Config.SHOP_DIST = 25
Config.SHOP_OPEN_DIST = 20

-- Renascer --------------------------------------------------------------------------------------

Config.REBIRTH_BASE = 250000
Config.REBIRTH_GROWTH = 3
Config.REBIRTH_MAX = 10
Config.REBIRTH_NEED_RARITY = 4
Config.PETS_KEPT, Config.PETS_KEPT_VIP = 1, 2

-- Eventos ---------------------------------------------------------------------------------------

Config.EVENT_INTERVAL = { 720, 900 }
Config.FIRST_EVENT_AT = 240
Config.EVENT_WARN = 10
Config.EVENTS = { -- chance em %, duração em s (Chuva: 10 s de aviso + 25 s)
	{ name = "Rajada", chance = 35, duration = 90 },
	{ name = "Chuva", chance = 25, duration = 25 },
	{ name = "Dourado", chance = 20, duration = 90 },
	{ name = "Virou", chance = 20, duration = 20 },
} :: { EventDef }
Config.RAJADA = { interval = { 7, 13 }, maxInAir = 6 }
Config.RAIN_COUNT = 8
Config.FESTIVAL = { wday = 7, hourUTC = 18, minutes = 40, rainEvery = 480, ventoMult = 2, color = 9 }
Config.BOOST_SECONDS = 900
Config.BOOST_RAJADA = { interval = { 10, 20 }, maxInAir = 6 }

-- Streak / dailies ------------------------------------------------------------------------------

Config.STREAK = { 300, 600, 1200, 2500, 5000, 10000, 20000 }
Config.STREAK_KITE = {
	[5] = { model = "Arraia", rarity = 3 },
	[7] = { model = "Raio", rarity = 3, color = 10 },
} :: { [number]: StreakKite }
Config.STREAK_CAP_DAY = 28
Config.DAILY = { Cortes = { goal = 3, reward = 500 }, Pegas = { goal = 1, reward = 800 } }
Config.DAY_SECONDS = 86400 -- (impl.) dia = os.time() // DAY_SECONDS

-- Ranking ---------------------------------------------------------------------------------------

Config.LEADERBOARD_PERIOD = 60
Config.WEEK_EPOCH_OFFSET = 345600
Config.WEEK_SECONDS = 604800 -- (impl.) semana = (os.time() - WEEK_EPOCH_OFFSET) // WEEK_SECONDS
Config.TOP3_CACHE_SECONDS = 600 -- (impl.) cache do top 3 da semana anterior

-- Rede ------------------------------------------------------------------------------------------

Config.RATE = { -- { por segundo, rajada }
	Pull = { 6, 10 }, SelectKite = { 2, 4 }, Collect = { 2, 4 }, Buy = { 2, 4 },
	ClaimStreak = { 1, 2 }, ClaimDaily = { 1, 2 }, Rebirth = { 1, 2 }, Emote = { 0.5, 2 },
	SetPet = { 2, 4 }, Ready = { 1, 2 }, -- (impl.) remotes SetPet (estimação) e Ready (cliente pronto)
} :: { [string]: { number } }
Config.SYNC_HZ = 10
Config.REMOTE_WAIT = 10 -- (impl.) s que o cliente espera por um remote antes de avisar
Config.INCOME_TICK = 1 -- (impl.) s entre créditos de renda (DataService)
Config.ECONOMY_LOG_EVERY = 60 -- (impl.) s entre logs agregados de Renda

-- Monetização (placeholders; preencher no Creator Hub) ------------------------------------------

Config.IDS = {
	PASS_VENTO_DOBRO = 0, -- pass "Vento em Dobro" (249)
	PASS_CARRETEL_AUTO = 0, -- pass "Carretel Automático" (179)
	PASS_VIP = 0, -- pass "VIP da Laje" (449)
	PASS_KIT = 0, -- pass "Kit Pipeiro" (299)
	PROD_RAJADA = 0, -- produto "Rajada no Servidor" (149)
	PROD_VENTO_FORTE = 0, -- produto "Vento Forte" (99)
	PROD_RESGATE = 0, -- produto "Resgatar da Árvore" (45)
	PROD_GUARDAR_STREAK = 0, -- produto "Guardar Streak" (39)
}
Config.KIT = { model = "Pipeiro", rarity = 3, color = 11, vento = 3000, linhaMin = 3 }
Config.BADGES = { PrimeiroCorte = 0, PrimeiraPega = 0, Temporada1 = 0, Dourada = 0, Mitica = 0 }
Config.PURCHASE_HISTORY = 50

Config.ONBOARDING_STEPS = { "SpawnLaje", "PrimeiroPull", "PrimeiraColeta", "PrimeiroCorte", "PrimeiraPega", "PrimeiraCompra" }

-- Template do perfil (GDD §5.1) -----------------------------------------------------------------

local PROFILE_TEMPLATE: ProfileData = {
	Vento = 0,
	Carretel = 0,
	Linha = 1,
	Vagas = Config.VAGAS_START,
	Temporadas = 0,
	Kites = { { id = 1, model = "Jornal", rarity = 1, color = 0, golden = false, pet = false, season = 0, starter = true } },
	NextKiteId = 2,
	Selected = 1,
	PlayTime = 0,
	LastSeen = 0,
	Onboarding = 0,
	KitClaimed = false,
	Streak = { Day = 0, LastClaimDay = 0, SaverWeek = 0 },
	Dailies = { Day = 0, Cortes = 0, Pegas = 0, ClaimedCortes = false, ClaimedPegas = false },
	Stats = { Cortes = 0, CortesPvP = 0, Pegas = 0, VentoTotal = 0 },
	Weekly = { Week = 0, Vento = 0, CortesPvP = 0 },
	Purchases = {},
}
Config.PROFILE_TEMPLATE = PROFILE_TEMPLATE

-- Strings (GDD §6). Listas viraram chaves: band0..band4, event_<Nome>, rarity1..6, kite_<Modelo>, emote1..4, onb1..6.

Config.STRINGS = {
	ptBR = {
		pull = "PUXAR", hold = "SEGURA!", cut = "CORTOU!", flew = "VOOU!", luck = "SORTE!",
		caught = "VOCÊ PEGOU: {kite} ({rarity})",
		flewBanner = "A {kite} de {name} voou!",
		someoneCaught = "{name} pegou a sua {kite}",
		shield = "Escudo de iniciante {time}",
		shieldBack = "Escudo: sua pipa voltou pra laje",
		wind = "Vento", perSec = "+{n}/s", reel = "Carretel", collect = "PEGAR VENTO",
		band0 = "Na laje", band1 = "Baixinha", band2 = "Média", band3 = "ZONA DE BRIGA", band4 = "CÉU ABERTO",
		bar = "BAR DO VENTO", restock = "Reestoca em {time}", buy = "COMPRAR", bought = "COMPRADO",
		line = "Linha de Vento L{n} · {name}", slot = "Vaga {n} no varal",
		autoSold = "Varal cheio: {kite} vendida por {n} Vento",
		mail = "CORREIO DA LAJE", day = "Dia {n}", claim = "RESGATAR",
		dailyCuts = "Corte 3 selvagens ({n}/3)", dailyCatch = "Pegue 1 pipa no campinho ({n}/1)",
		rebirth = "RENASCER — Nova Temporada {n}", rebirthNeed = "{vento} Vento + 1 pipa Épica",
		rebirthKeep = "Fica: Linha, vagas, streak, Jornal, estimação",
		offline = "Enquanto você saiu, suas pipas juntaram {n} Vento ({time})", receive = "RECEBER",
		event_Rajada = "Rajada", event_Chuva = "Chuva de Pipas", event_Dourado = "Vento Dourado",
		event_Virou = "Virou o Vento", event_Festival = "Festival do Morro",
		eventIn = "{event} em {time}", golden = "A {kite} de {name} virou DOURADA!",
		wild = "Selvagem", tree = "Presa na árvore {time}", rescue = "Resgatar da Árvore",
		rarity1 = "Comum", rarity2 = "Incomum", rarity3 = "Rara", rarity4 = "Épica", rarity5 = "Lendária", rarity6 = "Mítica",
		kite_Jornal = "Pipa de Jornal", kite_Lisa = "Pipa Lisa", kite_Estrela = "Estrela", kite_Arraia = "Arraia",
		kite_Morcegao = "Morcegão", kite_Luz = "Pipa de Luz", kite_Capivara = "Capivara Voadora",
		kite_Raio = "Pipa Raio", kite_Pipeiro = "Arraia Pipeiro", kite_Temporada = "Pipa de Temporada {n}",
		emote1 = "Pega!", emote2 = "Valeu!", emote3 = "Cuidado!", emote4 = "Bora!",
		invite = "Chamar amigo (+10 % Vento)",
		loadingTip = "Na vida real: pipa longe de fios e sem cerol.",
		onb1 = "TOCA pra subir", onb2 = "Toca até a faixa 2", onb3 = "TOCA pra brigar!",
		onb4 = "CORRE! Pega a pipa", onb5 = "Pega seu Vento no carretel", onb6 = "Compra uma pipa no Bar",
	},
	en = {
		pull = "PULL", hold = "HOLD!", cut = "CUT!", flew = "FLEW AWAY!", luck = "LUCKY!",
		caught = "YOU CAUGHT: {kite} ({rarity})",
		flewBanner = "{name}'s {kite} flew away!",
		someoneCaught = "{name} caught your {kite}",
		shield = "Beginner shield {time}",
		shieldBack = "Shield: your kite went back home",
		wind = "Wind", perSec = "+{n}/s", reel = "Reel", collect = "COLLECT WIND",
		band0 = "On the roof", band1 = "Low", band2 = "Mid", band3 = "FIGHT ZONE", band4 = "OPEN SKY",
		bar = "WIND BAR", restock = "Restocks in {time}", buy = "BUY", bought = "OWNED",
		line = "Wind Line L{n} · {name}", slot = "Clothesline slot {n}",
		autoSold = "Clothesline full: {kite} sold for {n} Wind",
		mail = "ROOFTOP MAIL", day = "Day {n}", claim = "CLAIM",
		dailyCuts = "Cut 3 wild kites ({n}/3)", dailyCatch = "Catch 1 kite on the field ({n}/1)",
		rebirth = "REBIRTH — New Season {n}", rebirthNeed = "{vento} Wind + 1 Epic kite",
		rebirthKeep = "Keeps: Line, slots, streak, Jornal, pet",
		offline = "While you were away your kites gathered {n} Wind ({time})", receive = "COLLECT",
		event_Rajada = "Gust", event_Chuva = "Kite Rain", event_Dourado = "Golden Wind",
		event_Virou = "Wind Turned", event_Festival = "Hill Festival",
		eventIn = "{event} in {time}", golden = "{name}'s {kite} turned GOLDEN!",
		wild = "Wild", tree = "Stuck in the tree {time}", rescue = "Rescue from Tree",
		rarity1 = "Common", rarity2 = "Uncommon", rarity3 = "Rare", rarity4 = "Epic", rarity5 = "Legendary", rarity6 = "Mythic",
		kite_Jornal = "Newspaper Kite", kite_Lisa = "Plain Kite", kite_Estrela = "Star", kite_Arraia = "Stingray",
		kite_Morcegao = "Big Bat", kite_Luz = "Light Kite", kite_Capivara = "Flying Capybara",
		kite_Raio = "Lightning Kite", kite_Pipeiro = "Kiter Stingray", kite_Temporada = "Season {n} Kite",
		emote1 = "Catch it!", emote2 = "Thanks!", emote3 = "Watch out!", emote4 = "Let's go!",
		invite = "Invite a friend (+10 % Wind)",
		loadingTip = "In real life: keep kites away from power lines.",
		onb1 = "TAP to go up", onb2 = "Tap up to band 2", onb3 = "TAP to fight!",
		onb4 = "RUN! Catch the kite", onb5 = "Collect your Wind at the reel", onb6 = "Buy a kite at the Bar",
	},
} :: { ptBR: { [string]: string }, en: { [string]: string } }

-- Ajudantes -------------------------------------------------------------------------------------

-- Raridade (1..6) de um modelo; 1 se o modelo for desconhecido.
function Config.rarityOf(model: string): number
	return Config.MODEL_RARITY[model] or 1
end

-- V/s base de uma pipa = BASE_RATE[raridade] × (dourada ? GOLDEN_MULT : 1).
function Config.baseRate(k: KiteData): number
	local base = Config.BASE_RATE[k.rarity] or Config.BASE_RATE[1]
	return base * (if k.golden then Config.GOLDEN_MULT else 1)
end

-- String localizada: "en..." usa a tabela en, qualquer outro locale usa pt-BR; cai na outra tabela
-- e por fim na própria chave. {var} é substituído por vars[var].
function Config.str(key: string, locale: string, vars: { [string]: any }?): string
	local primary = if string.sub(locale, 1, 2) == "en" then Config.STRINGS.en else Config.STRINGS.ptBR
	local text = primary[key] or Config.STRINGS.ptBR[key] or Config.STRINGS.en[key] or key
	if vars then
		text = string.gsub(text, "{(%w+)}", function(name: string): string
			local value = vars[name]
			return if value == nil then "{" .. name .. "}" else tostring(value)
		end)
	end
	return text
end

-- Constantes da implementação (impl.) do KiteService / EventService -------------------------------
Config.LAND_Y = 1.5 -- (impl.) y do ponto de pouso no campinho (GDD §2.5)
Config.TELEPORT_WINDOW = 0.5 -- (impl.) janela (s) do anti-teleport (TELEPORT_JUMP studs em 0.5 s)
Config.EMOTE_SECONDS = 2 -- (impl.) duração do atributo Emote do Player (GDD §5.8)
Config.COSMETIC_COLORS = 8 -- (impl.) cores cosméticas sorteadas = 1..8 (GDD §1)
Config.BOOST_VENTO_MULT = 2 -- (impl.) multiplicador do produto Vento Forte (GDD §5.7)

-- Textos fixos do mapa (placas e prompts são criados no servidor; pt-BR é o padrão) ----------------
Config.STRINGS.ptBR.promptStock = "Ver estoque" -- (impl.) ProximityPrompt do balcão do Bar
Config.STRINGS.en.promptStock = "See stock"
Config.STRINGS.ptBR.rankingTitle = "RANKING DA SEMANA" -- (impl.) título da placa do Poste
Config.STRINGS.en.rankingTitle = "WEEKLY RANKING"
Config.STRINGS.ptBR.rankingKing = "REI DA LAJE" -- (impl.) coluna Vento da semana (GDD §3.1)
Config.STRINGS.en.rankingKing = "ROOFTOP KING"
Config.STRINGS.ptBR.rankingScissors = "TESOURA DE OURO" -- (impl.) coluna Cortes PvP (GDD §3.1)
Config.STRINGS.en.rankingScissors = "GOLDEN SCISSORS"

-- Cliente (impl.): constantes do HUD/KiteRenderer, paleta §1, ordem da Loja de passes e strings -----
Config.SEASON_HUE = { step = 0.1, sat = 0.8, val = 1 } -- (impl.) cor da Temporada n = HSV((n×step)%1, sat, val) (GDD §1)
Config.RABIOLA_COLORS = { Color3.fromRGB(255, 190, 40), Color3.fromRGB(200, 200, 210), Color3.fromRGB(205, 127, 50) } -- (impl.) RabiolaRank 1-3 (ouro/prata/bronze)
Config.PASS_ORDER = { "PASS_VENTO_DOBRO", "PASS_CARRETEL_AUTO", "PASS_VIP", "PASS_KIT" } -- (impl.) ordem na Loja (GDD §5.7)
Config.PRODUCT_ORDER = { "PROD_RAJADA", "PROD_VENTO_FORTE", "PROD_RESGATE", "PROD_GUARDAR_STREAK" }
Config.PALETTE = { -- (impl.) paleta do GDD §1 (RGB)
	Sky = Color3.fromRGB(90, 180, 255), Red = Color3.fromRGB(235, 60, 50), Sun = Color3.fromRGB(255, 205, 60),
	Hill = Color3.fromRGB(95, 185, 90), Dirt = Color3.fromRGB(150, 105, 60), Asphalt = Color3.fromRGB(60, 60, 65),
	Laje = Color3.fromRGB(255, 140, 60), Pink = Color3.fromRGB(255, 120, 170), Lilac = Color3.fromRGB(170, 130, 230),
	UIBg = Color3.fromRGB(30, 30, 45), UIText = Color3.fromRGB(255, 255, 255), Outline = Color3.fromRGB(20, 20, 30),
	Gray = Color3.fromRGB(190, 190, 190), Green = Color3.fromRGB(80, 200, 100), White = Color3.fromRGB(245, 245, 245),
}
Config.CLIENT = { -- (impl.) números do render e do HUD (GDD §2.9, §4.3, §6)
	-- KiteRenderer
	TAIL_HIDE_DIST = 150, -- rabiola escondida além disto (studs da câmera)
	TAIL_PARTS = 3, -- Parts por rabiola
	TAIL_SWAY = 0.35, -- amplitude (studs) do balanço senoidal
	TAIL_HZ = 0.5, -- ciclos/s do balanço
	SNAP_DIST = 80, -- salto de Pos maior que isto não interpola (recall / spawn)
	CATCHUP = 4, -- velocidade de alcance = max(KITE_MOVE_SPEED, distância × CATCHUP)
	TILT_DEG = 20, -- inclinação da pipa para trás
	DUEL_SHAKE = 0.6, -- tremor em duelo (studs)
	DUEL_SHAKE_HZ = 12,
	DUEL_SPARKS = 4, -- Parts amarelas no ponto médio
	DUEL_SPARK_SIZE = 0.4,
	DUEL_BLINK_HZ = 6,
	FALL_SPIN_Y = 360, -- graus/s em Y na queda
	FALL_SPIN_Z = 90, -- graus/s em Z na queda
	MARKER_SIZE = Vector3.new(2, 200, 2), -- coluna Neon no LandPos
	MARKER_TRANSPARENCY = 0.35,
	SHRINK_SECONDS = 0.3, -- pega: a pipa encolhe até sumir
	TRAIL_PARTS = 6, -- rastro do rabeio
	TRAIL_SIZE = 0.3,
	TRAIL_SECONDS = 0.4,
	BURST_PARTS = 8, -- coleta no carretel
	BURST_SIZE = 0.5,
	BURST_SECONDS = 0.5,
	ARROW_SIZE = Vector3.new(2, 2, 3), -- seta de onboarding (WedgePart Neon)
	ARROW_HEIGHT = 5, -- studs acima do alvo
	ARROW_BOB = 1, -- ±1 stud
	ARROW_SPIN = 1.5, -- rad/s
	BILLBOARD_DIST = 300, -- MaxDistance do nome da pipa
	BILLBOARD_UP = 2.2, -- studs acima do corpo
	VARAL_SCALE = 0.4, -- miniaturas do varal
	VARAL_STEP = 2, -- 8 vagas a cada 2 studs
	VARAL_HANG = 1.0, -- studs abaixo da linha
	LINE_THICKNESS = 0.15,
	LINE_ANCHOR_UP = 1.5, -- topo do carretel (raio do Cylinder)
	GOLDEN_PARTICLES = 4, -- ParticleEmitter por segundo
	EMOTE_BUBBLE_UP = 2.5,
	-- HUD
	BUTTON_HEIGHT = 0.16, -- fração da altura da tela
	BUTTON_MIN_PX = 128,
	MIN_TEXT_PX = 14,
	STROKE_PX = 3,
	PRESS_SCALE = 0.9,
	PRESS_SECONDS = 0.08,
	POP_SCALE = 1.3,
	POP_SECONDS = 0.25,
	FULLSCREEN_SECONDS = 1.2,
	FULLSCREEN_FROM = 1.4,
	TOAST_SECONDS = 3,
	TOAST_MAX = 4,
	PET_HOLD = 1, -- toque longo na carta = estimação
	COUNT_UP = 6, -- count-up do Vento (fração da diferença por segundo)
	SLOW_TICK = 0.2, -- s entre checagens de distância e relógios
	HAPTIC_SECONDS = 0.3,
	BLINK_HZ = 4, -- "SEGURA!" piscando
	RING_HZ = 1.2, -- anel pulsante do onboarding
	PRICE_CACHE = 600, -- s de cache dos preços da Loja
	LAND_MEMORY = 40, -- s que o HUD lembra o último LandPos (seta "CORRE!")
	PANEL_TWEEN = 0.18,
}
-- Strings do HUD/KiteRenderer (impl.) ----------------------------------------------------------------
local ptBR, en = Config.STRINGS.ptBR, Config.STRINGS.en
ptBR.close, en.close = "FECHAR", "CLOSE"
ptBR.confirm, en.confirm = "CONFIRMAR", "CONFIRM"
ptBR.btnBar, en.btnBar = "BAR", "BAR"
ptBR.btnMail, en.btnMail = "CORREIO", "MAIL"
ptBR.btnRebirth, en.btnRebirth = "RENASCER", "REBIRTH"
ptBR.btnShop, en.btnShop = "LOJA", "SHOP"
ptBR.btnSound, en.btnSound = "SOM", "SOUND"
ptBR.soundState, en.soundState = "Som: {state}", "Sound: {state}"
ptBR.on, en.on = "LIGADO", "ON"
ptBR.off, en.off = "DESLIGADO", "OFF"
ptBR.band, en.band = "Faixa {n} · {name} ×{mult}", "Band {n} · {name} ×{mult}"
ptBR.you, en.you = "Você", "You"
ptBR.duelVs, en.duelVs = "{a}  ×  {b} (L{linha})", "{a}  ×  {b} (L{linha})"
ptBR.pet, en.pet = "★ Estimação", "★ Pet"
ptBR.inAir, en.inAir = "NO AR", "IN AIR"
ptBR.max, en.max = "MÁX", "MAX"
ptBR.special, en.special = "ESPECIAL", "SPECIAL"
ptBR.soon, en.soon = "Em breve", "Coming soon"
ptBR.robux, en.robux = "{n} R$", "R$ {n}"
ptBR.vento, en.vento = "{n} Vento", "{n} Wind"
ptBR.epicOk, en.epicOk = "1 Épica no varal: ✓", "1 Epic on the clothesline: ✓"
ptBR.epicNo, en.epicNo = "1 Épica no varal: ✗", "1 Epic on the clothesline: ✗"
ptBR.rebirthBonus, en.rebirthBonus = "+15 % de Vento permanente", "+15 % permanent Wind"
ptBR.rebirthMax, en.rebirthMax = "Temporada máxima!", "Max season!"
ptBR.boostRajada, en.boostRajada = "{name} pagou uma Rajada!", "{name} paid for a Gust!"
ptBR.boostVento, en.boostVento = "{name} pagou Vento Forte!", "{name} paid for Strong Wind!"
ptBR.renasceu, en.renasceu = "NOVA TEMPORADA {n}!", "NEW SEASON {n}!"
ptBR.streakGot, en.streakGot = "Dia {day}: +{n} Vento", "Day {day}: +{n} Wind"
ptBR.goldenBlank, en.goldenBlank = "O vento passou em branco…", "The wind passed by…"
ptBR.eventNow, en.eventNow = "▲ {event} — {time}", "▲ {event} — {time}"
ptBR.eventWarn, en.eventWarn = "✂ {event} em {time}", "✂ {event} in {time}"
ptBR.boostBanner, en.boostBanner = "★ {event} — {time} ({name})", "★ {event} — {time} ({name})"
ptBR.flewWild, en.flewWild = "Uma {kite} selvagem voou!", "A wild {kite} flew away!"
ptBR.offlineTitle, en.offlineTitle = "Enquanto você saiu…", "While you were away…"
ptBR.stockEmpty, en.stockEmpty = "Sem estoque", "No stock"
ptBR.linhaMax, en.linhaMax = "Linha no máximo", "Line maxed"
ptBR.vagaMax, en.vagaMax = "Varal completo", "Clothesline maxed"
ptBR.claimed, en.claimed = "RESGATADO", "CLAIMED"
ptBR.hours, en.hours = "{h} h {m}", "{h} h {m}"
ptBR.minutes, en.minutes = "{m} min", "{m} min"
ptBR.errDefault, en.errDefault = "Não deu certo", "That didn't work"
ptBR.passes, en.passes = "PASSES", "PASSES"
ptBR.products, en.products = "PRODUTOS", "PRODUCTS"
ptBR.item_PASS_VENTO_DOBRO, en.item_PASS_VENTO_DOBRO = "Vento em Dobro", "Double Wind"
ptBR.item_PASS_CARRETEL_AUTO, en.item_PASS_CARRETEL_AUTO = "Carretel Automático", "Auto Reel"
ptBR.item_PASS_VIP, en.item_PASS_VIP = "VIP da Laje", "Rooftop VIP"
ptBR.item_PASS_KIT, en.item_PASS_KIT = "Kit Pipeiro", "Kiter Kit"
ptBR.item_PROD_RAJADA, en.item_PROD_RAJADA = "Rajada no Servidor", "Server Gust"
ptBR.item_PROD_VENTO_FORTE, en.item_PROD_VENTO_FORTE = "Vento Forte", "Strong Wind"
ptBR.item_PROD_RESGATE, en.item_PROD_RESGATE = "Resgatar da Árvore", "Rescue from Tree"
ptBR.item_PROD_GUARDAR_STREAK, en.item_PROD_GUARDAR_STREAK = "Guardar Streak", "Save Streak"

-- Economia (impl.): ShopService / MonetizationService / Leaderboard -------------------------------
Config.SHOP_SLOTS_NORMAL = 4 -- (impl.) slots normais do Bar (SHOP_TABLE) (GDD §5.2)
Config.SHOP_SLOTS_SPECIAL = 1 -- (impl.) slots especiais do Bar (SHOP_SPECIAL_TABLE) (GDD §5.2)
Config.STREAK_REPEAT_MULT = 2 -- (impl.) D8-D28 repetem o ciclo com Vento ×2 (GDD §5.4)
Config.PASS_VENTO_DOBRO_MULT = 2 -- (impl.) multiplicador do passe Vento em Dobro (GDD §5.7)
Config.RECEIPT_SAVE_TIMEOUT = 30 -- (impl.) s que o ProcessReceipt espera o Save antes de NotProcessedYet
Config.LEADERBOARD_TOP = 10 -- (impl.) entradas por coluna no Poste (GetSortedAsync) (GDD §5.5)
Config.RABIOLA_TOP = 3 -- (impl.) top N da semana anterior que recebe RabiolaRank (GDD §5.5)
-- Toast("Erro", {msg, key, vars}): msg já em pt-BR; o HUD pode relocalizar com Config.str(key, locale, vars).
Config.STRINGS.ptBR.errFarBar = "Chegue mais perto do Bar do Vento"
Config.STRINGS.en.errFarBar = "Get closer to the Wind Bar"
Config.STRINGS.ptBR.errVento = "Vento insuficiente (precisa de {n})"
Config.STRINGS.en.errVento = "Not enough Wind (needs {n})"
Config.STRINGS.ptBR.errBought = "Você já comprou este slot neste estoque"
Config.STRINGS.en.errBought = "You already bought this slot this restock"
Config.STRINGS.ptBR.errMaxLinha = "Linha de Vento já no nível máximo"
Config.STRINGS.en.errMaxLinha = "Wind Line already at max level"
Config.STRINGS.ptBR.errMaxVagas = "Varal já com todas as vagas"
Config.STRINGS.en.errMaxVagas = "Clothesline already has every slot"
Config.STRINGS.ptBR.errStreak = "Correio já resgatado hoje"
Config.STRINGS.en.errStreak = "Mail already claimed today"
Config.STRINGS.ptBR.errDaily = "Missão ainda não concluída (ou já resgatada)"
Config.STRINGS.en.errDaily = "Quest not done yet (or already claimed)"
Config.STRINGS.ptBR.errRebirth = "Renascer precisa de {vento} Vento e 1 pipa Épica no varal"
Config.STRINGS.en.errRebirth = "Rebirth needs {vento} Wind and 1 Epic kite"
Config.STRINGS.ptBR.errRebirthMax = "Você já está na temporada máxima"
Config.STRINGS.en.errRebirthMax = "You are already at the max season"
Config.STRINGS.ptBR.errDuel = "Espere o duelo acabar"
Config.STRINGS.en.errDuel = "Wait for the duel to end"
Config.STRINGS.ptBR.errPetMax = "Só {n} pipa(s) de estimação por vez"
Config.STRINGS.en.errPetMax = "Only {n} pet kite(s) at a time"
Config.STRINGS.ptBR.errNoTree = "Nenhuma pipa sua está presa na árvore"
Config.STRINGS.en.errNoTree = "None of your kites is stuck in the tree"
Config.STRINGS.ptBR.errSaverUsed = "Guardar Streak já foi usado nesta semana"
Config.STRINGS.en.errSaverUsed = "Streak Saver already used this week"
Config.STRINGS.ptBR.errProduct = "Compra registrada, mas não havia o que conceder"
Config.STRINGS.en.errProduct = "Purchase recorded, but there was nothing to grant"

return Config
