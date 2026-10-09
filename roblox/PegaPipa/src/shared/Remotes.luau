--!strict
--[[
	Remotes — nomes dos RemoteEvents (GDD §7.3), criação no servidor (init), busca no cliente (get),
	limitador token-bucket por jogador (limiter) e validadores numéricos (isFinite / isInt).
	Todo remote é hostil: o servidor valida tipo, faixa e distância antes de agir. Não existe RemoteFunction.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent:WaitForChild("Config"))

local Remotes = {}

Remotes.FOLDER_NAME = "Remotes"

-- C→S: Pull, SelectKite, Collect, Buy, ClaimStreak, ClaimDaily, Rebirth, Emote
-- S→C: State, Toast, ShopStock
Remotes.NAMES = {
	"Pull", "SelectKite", "Collect", "Buy", "ClaimStreak", "ClaimDaily", "Rebirth", "Emote",
	"State", "Toast", "ShopStock",
} :: { string }

type Bucket = { tokens: number, last: number }

export type Limiter = {
	allow: (self: Limiter, p: Player) -> boolean,
	forget: (self: Limiter, p: Player) -> (),
}

-- Servidor: cria ReplicatedStorage/Remotes/<nome> para cada nome (idempotente).
function Remotes.init(): ()
	local existing = ReplicatedStorage:FindFirstChild(Remotes.FOLDER_NAME)
	local folder: Instance
	if existing then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = Remotes.FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
	end
	for _, name in Remotes.NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

-- Cliente (ou servidor depois de init): espera o remote até REMOTE_WAIT s; avisa e continua esperando.
function Remotes.get(name: string): RemoteEvent
	assert(table.find(Remotes.NAMES, name) ~= nil, `[Remotes] nome desconhecido: {name}`)
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, Config.REMOTE_WAIT)
	if not folder then
		warn(`[Remotes] pasta {Remotes.FOLDER_NAME} não apareceu em {Config.REMOTE_WAIT}s; continuando a esperar`)
		folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	end
	local remote = folder:WaitForChild(name, Config.REMOTE_WAIT)
	if not remote then
		warn(`[Remotes] remote {name} não apareceu em {Config.REMOTE_WAIT}s; continuando a esperar`)
		remote = folder:WaitForChild(name)
	end
	return remote :: RemoteEvent
end

-- Token bucket por jogador: `rate` fichas/s, até `burst` acumuladas. Uso: if not lim:allow(p) then return end
function Remotes.limiter(rate: number, burst: number): Limiter
	local buckets: { [Player]: Bucket } = {}
	local limiter: Limiter = {
		allow = function(_self: Limiter, p: Player): boolean
			local now = os.clock()
			local bucket = buckets[p]
			if not bucket then
				bucket = { tokens = burst, last = now }
				buckets[p] = bucket
			end
			bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * rate)
			bucket.last = now
			if bucket.tokens >= 1 then
				bucket.tokens -= 1
				return true
			end
			return false
		end,
		forget = function(_self: Limiter, p: Player)
			buckets[p] = nil
		end,
	}
	return limiter
end

-- true só para number finito (nem NaN nem ±inf).
function Remotes.isFinite(n: unknown): boolean
	return typeof(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- true só para inteiro finito dentro de [min, max].
function Remotes.isInt(n: unknown, min: number, max: number): boolean
	if typeof(n) ~= "number" or n ~= n then
		return false
	end
	return n % 1 == 0 and n >= min and n <= max
end

return Remotes
