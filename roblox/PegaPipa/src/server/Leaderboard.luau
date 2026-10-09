--!strict
--[[
	Leaderboard — ranking semanal (GDD §5.5).

	- Dono de profile.Data.Weekly: addWeekly(p, stat, n) soma em Weekly.Vento / Weekly.CortesPvP e zera o
	  bloco quando a semana (weekIndex: segunda 00:00 UTC) muda. DataService (todo Vento creditado) e
	  KiteService (CortesPvP) chamam via DataService.hooks.addWeekly — ninguém requer este módulo.
	- OrderedDataStores "Rei_{semana}" (Vento) e "Tesoura_{semana}" (CortesPvP): a cada LEADERBOARD_PERIOD s,
	  SetAsync por jogador só se o valor mudou (inteiros, pcall) e GetSortedAsync(false, LEADERBOARD_TOP)
	  com cache → SurfaceGui do Poste (Part com a tag Poste). O MapGen cria o SurfaceGui "Ranking" com as
	  colunas "Rei" e "Tesoura" (TextLabel); se faltar, uma placa simples é criada aqui.
	- Top RABIOLA_TOP da semana anterior (Rei_{semana-1}), lido 1× por TOP3_CACHE_SECONDS → atributo
	  RabiolaRank 1..3 do Player (0 para os demais; o DataService inicializa 0 no load).
	Studio sem acesso à API: toda chamada está em pcall; avisa uma vez e segue (a placa fica vazia).
	Requer: Config, DataService (nada mais).
]]

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local DataService = require(script.Parent.DataService)

export type WeeklyStat = "Vento" | "CortesPvP"
type ProfileData = Config.ProfileData
type Weekly = { Week: number, Vento: number, CortesPvP: number }
type Entry = { userId: number, value: number }

local STATS: { WeeklyStat } = { "Vento", "CortesPvP" }
local STORE_PREFIX: { [string]: string } = { Vento = "Rei_", CortesPvP = "Tesoura_" }
local LABEL_NAME: { [string]: string } = { Vento = "Rei", CortesPvP = "Tesoura" }
local EMPTY_TEXT = "—"
-- Placa de reserva (só se o MapGen não criou as colunas): mesma geometria da placa do MapGen.
local FALLBACK = { x = { Vento = 0.02, CortesPvP = 0.51 } :: { [string]: number }, y = 0.32, w = 0.47, h = 0.66 }

local Leaderboard = {}

-- Semana desde segunda 00:00 UTC: (os.time() - WEEK_EPOCH_OFFSET) // WEEK_SECONDS.
function Leaderboard.weekIndex(): number
	return (os.time() - Config.WEEK_EPOCH_OFFSET) // Config.WEEK_SECONDS
end

local boards: { [string]: { Entry } } = { Vento = {}, CortesPvP = {} }
local lastWritten: { [Player]: { [string]: number } } = {} -- week + último valor enviado por stat
local nameCache: { [number]: string } = {}
local top: { number } = {} -- userIds do top da semana anterior
local topWeek = -1
local topAt = 0 -- os.clock() da última leitura do top
local apiDown = false

-- Ajudantes --------------------------------------------------------------------------------------

local function dataOf(p: Player): ProfileData?
	local profile = DataService.get(p)
	return if profile then profile.Data else nil
end

-- Avisa uma vez quando o DataStore falha (Studio sem API, throttling) e de novo só depois de recuperar.
local function reportError(err: any)
	if not apiDown then
		apiDown = true
		warn(`[Leaderboard] DataStore indisponível (seguindo sem ranking): {err}`)
	end
end

local function reportOk()
	if apiDown then
		apiDown = false
		print("[Leaderboard] DataStore voltou")
	end
end

local function storeFor(stat: WeeklyStat, week: number): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(`{STORE_PREFIX[stat]}{week}`)
end

local function weeklyGet(w: Weekly, stat: WeeklyStat): number
	return if stat == "Vento" then w.Vento else w.CortesPvP
end

-- Zera Weekly quando a semana mudou. Retorna true se zerou.
local function ensureWeek(w: Weekly): boolean
	local week = Leaderboard.weekIndex()
	if w.Week == week then
		return false
	end
	w.Week = week
	w.Vento = 0
	w.CortesPvP = 0
	return true
end

-- DataStore (tudo em pcall) ------------------------------------------------------------------------

local function writeScore(stat: WeeklyStat, week: number, userId: number, value: number): boolean
	local ok, err = pcall(function(): string?
		storeFor(stat, week):SetAsync(tostring(userId), value)
		return nil
	end)
	if ok then
		reportOk()
	else
		reportError(err)
	end
	return ok
end

-- Top `n` de uma loja (decrescente); nil se o DataStore falhou.
local function readTop(stat: WeeklyStat, week: number, n: number): { Entry }?
	local ok, result = pcall(function(): { Entry }
		local page = storeFor(stat, week):GetSortedAsync(false, n):GetCurrentPage()
		local list: { Entry } = {}
		for _, item in page do
			table.insert(list, { userId = tonumber(item.key) or 0, value = tonumber(item.value) or 0 })
		end
		return list
	end)
	if ok then
		reportOk()
		return result
	end
	reportError(result)
	return nil
end

-- Placa do Poste --------------------------------------------------------------------------------------

-- Nome exibido de um userId (presente → DisplayName; senão GetNameFromUserIdAsync com cache).
local function nameOf(userId: number): string
	local present = Players:GetPlayerByUserId(userId)
	if present then
		return present.DisplayName
	end
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if ok then
		nameCache[userId] = name
		return name
	end
	return tostring(userId)
end

-- 12400 → "12,4K"; 1200000 → "1,2M"; 340 → "340".
local function fmt(n: number): string
	local text: string
	if n >= 1e6 then
		text = string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		text = string.format("%.1fK", n / 1e3)
	else
		return tostring(math.floor(n))
	end
	return (string.gsub(text, "%.", ","))
end

-- SurfaceGui do Poste (o do MapGen, ou uma placa simples na face -Z do próprio poste).
local function posteGui(): SurfaceGui?
	for _, inst in CollectionService:GetTagged("Poste") do
		local gui = inst:FindFirstChildWhichIsA("SurfaceGui")
		if gui then
			return gui
		end
		if inst:IsA("BasePart") then
			local created = Instance.new("SurfaceGui")
			created.Name = "Ranking"
			created.Face = Enum.NormalId.Front
			created.LightInfluence = 0
			created.Parent = inst
			return created
		end
	end
	return nil
end

-- Coluna "Rei" / "Tesoura" da placa (criada se o MapGen não a fez).
local function columnLabel(gui: SurfaceGui, stat: WeeklyStat): TextLabel
	local name = LABEL_NAME[stat]
	local found = gui:FindFirstChild(name)
	if found and found:IsA("TextLabel") then
		return found
	end
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(FALLBACK.x[stat], FALLBACK.y)
	label.Size = UDim2.fromScale(FALLBACK.w, FALLBACK.h)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = EMPTY_TEXT
	label.Parent = gui
	return label
end

-- Escreve as duas colunas ("1. Nome — 12,4K" por linha). Pode yield (nomes de quem não está no servidor).
local function render()
	local gui = posteGui()
	if not gui then
		return
	end
	for _, stat: WeeklyStat in STATS do
		local lines = {}
		for i, e in boards[stat] do
			table.insert(lines, `{i}. {nameOf(e.userId)} — {fmt(e.value)}`)
		end
		columnLabel(gui, stat).Text = if #lines > 0 then table.concat(lines, "\n") else EMPTY_TEXT
	end
end

-- Rabiola (top da semana anterior) --------------------------------------------------------------------

local function applyRank(p: Player, ids: { number })
	local rank = table.find(ids, p.UserId) or 0
	if p:GetAttribute("RabiolaRank") ~= rank then
		p:SetAttribute("RabiolaRank", rank)
	end
end

-- userIds do top RABIOLA_TOP da semana anterior (Rei_{semana-1}); lido 1× por TOP3_CACHE_SECONDS. Pode yield.
function Leaderboard.previousTop3(): { number }
	local week = Leaderboard.weekIndex()
	if topWeek == week and os.clock() - topAt < Config.TOP3_CACHE_SECONDS then
		return top
	end
	local list = readTop("Vento", week - 1, Config.RABIOLA_TOP)
	if list then
		top = {}
		for _, e in list do
			table.insert(top, e.userId)
		end
	elseif topWeek ~= week then
		top = {} -- semana nova e leitura falhou: o top antigo não vale mais
	end
	topWeek = week
	topAt = os.clock()
	return top
end

-- Ciclo de LEADERBOARD_PERIOD ------------------------------------------------------------------------------

-- Últimos valores enviados por p nesta semana (novo bloco quando a semana muda).
local function lastFor(p: Player, week: number): { [string]: number }
	local last = lastWritten[p]
	if last and last.week == week then
		return last
	end
	local fresh: { [string]: number } = { week = week }
	lastWritten[p] = fresh
	return fresh
end

-- Envia ao OrderedDataStore os valores que mudaram desde o último envio (inteiros > 0).
local function pushScores()
	local week = Leaderboard.weekIndex()
	for _, p in Players:GetPlayers() do
		local data = dataOf(p)
		if not data then
			continue
		end
		ensureWeek(data.Weekly)
		local last = lastFor(p, week)
		for _, stat: WeeklyStat in STATS do
			local value = math.floor(weeklyGet(data.Weekly, stat))
			if value > 0 and value ~= last[stat] and writeScore(stat, week, p.UserId, value) then
				last[stat] = value
			end
		end
	end
end

local function refreshBoards()
	local week = Leaderboard.weekIndex()
	for _, stat: WeeklyStat in STATS do
		local list = readTop(stat, week, Config.LEADERBOARD_TOP)
		if list then
			boards[stat] = list
		end
	end
	render()
end

local function cycle()
	pushScores()
	refreshBoards()
	local ids = Leaderboard.previousTop3()
	for _, p in Players:GetPlayers() do
		applyRank(p, ids)
	end
end

local function loop()
	while true do
		local ok, err = pcall(function(): string?
			cycle()
			return nil
		end)
		if not ok then
			warn(`[Leaderboard] ciclo falhou: {err}`)
		end
		task.wait(Config.LEADERBOARD_PERIOD)
	end
end

-- API pública -------------------------------------------------------------------------------------------------

-- Soma n em Weekly[stat] (zera Weekly se a semana mudou).
function Leaderboard.addWeekly(p: Player, stat: WeeklyStat, n: number): ()
	local data = dataOf(p)
	if not data or n ~= n or n <= 0 then
		return
	end
	ensureWeek(data.Weekly)
	if stat == "Vento" then
		data.Weekly.Vento += n
	else
		data.Weekly.CortesPvP += n
	end
end

local function onLoaded(p: Player, data: ProfileData)
	ensureWeek(data.Weekly)
	applyRank(p, Leaderboard.previousTop3())
end

function Leaderboard.start(): ()
	DataService.hooks.addWeekly = Leaderboard.addWeekly
	DataService.onLoaded(onLoaded)
	Players.PlayerRemoving:Connect(function(p: Player)
		lastWritten[p] = nil
	end)
	task.spawn(loop)
end

return Leaderboard
