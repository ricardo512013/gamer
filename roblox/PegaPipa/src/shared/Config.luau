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
Config.FAIXA_HEIGHT_ABOVE_LAJE = { [1] = 35, [2] = 70 } :: { [number]: number } -- faixas 1-2 (y = 61.5 / 96.5)
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

-- adicionado por área core (KiteService / EventService) ------------------------------------------
Config.LAND_Y = 1.5 -- adicionado por área core: y do ponto de pouso no campinho (GDD §2.5)
Config.TELEPORT_WINDOW = 0.5 -- adicionado por área core: janela (s) do anti-teleport (TELEPORT_JUMP studs em 0.5 s)
Config.EMOTE_SECONDS = 2 -- adicionado por área core: duração do atributo Emote do Player (GDD §5.8)
Config.COSMETIC_COLORS = 8 -- adicionado por área core: cores cosméticas sorteadas = 1..8 (GDD §1)
Config.BOOST_VENTO_MULT = 2 -- adicionado por área core: multiplicador do produto Vento Forte (GDD §5.7)

-- adicionado por área mapa: textos fixos do mapa (placas e prompts vivem no servidor; pt-BR é o padrão) ----
Config.STRINGS.ptBR.promptStock = "Ver estoque" -- adicionado por área mapa: ProximityPrompt do balcão do Bar
Config.STRINGS.en.promptStock = "See stock" -- adicionado por área mapa
Config.STRINGS.ptBR.rankingTitle = "RANKING DA SEMANA" -- adicionado por área mapa: título da placa do Poste
Config.STRINGS.en.rankingTitle = "WEEKLY RANKING" -- adicionado por área mapa
Config.STRINGS.ptBR.rankingKing = "REI DA LAJE" -- adicionado por área mapa: coluna Vento da semana (GDD §3.1)
Config.STRINGS.en.rankingKing = "ROOFTOP KING" -- adicionado por área mapa
Config.STRINGS.ptBR.rankingScissors = "TESOURA DE OURO" -- adicionado por área mapa: coluna Cortes PvP (GDD §3.1)
Config.STRINGS.en.rankingScissors = "GOLDEN SCISSORS" -- adicionado por área mapa

return Config
