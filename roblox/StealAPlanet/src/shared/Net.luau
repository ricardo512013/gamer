--!strict
-- Remote events/functions. The server creates them, the client waits for them.
-- All client -> server requests go through one RemoteFunction ("Request") with
-- per-player rate limiting; handlers are registered with Net.Handle().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Net = {}

local FOLDER_NAME = "Remotes"
local EVENTS = { "Notify", "Sync", "Effect", "UseTool" }
local FUNCTIONS = { "Request" }

local RATE_WINDOW = 2
local RATE_MAX = 30

local folder: Folder? = nil

local function getFolder(): Folder
	local existing = folder
	if existing then
		return existing
	end
	local result: Folder
	if RunService:IsServer() then
		local found = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if found and found:IsA("Folder") then
			result = found
		else
			result = Instance.new("Folder")
			result.Name = FOLDER_NAME
			for _, name in EVENTS do
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = result
			end
			for _, name in FUNCTIONS do
				local remote = Instance.new("RemoteFunction")
				remote.Name = name
				remote.Parent = result
			end
			result.Parent = ReplicatedStorage
		end
	else
		result = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	folder = result
	return result
end

function Net.Event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

export type Result = { ok: boolean, msg: string? }
type Handler = (Player, ...any) -> any

local handlers: { [string]: Handler } = {}
local rate: { [Player]: { start: number, count: number } } = {}

function Net.Handle(action: string, fn: Handler)
	handlers[action] = fn
end

local function allowed(player: Player): boolean
	local now = os.clock()
	local entry = rate[player]
	if not entry or now - entry.start > RATE_WINDOW then
		rate[player] = { start = now, count = 1 }
		return true
	end
	entry.count += 1
	return entry.count <= RATE_MAX
end

-- Server only: start answering client requests.
function Net.StartServer()
	getFolder()
	local request = Net.Function("Request")
	request.OnServerInvoke = function(player: Player, action: any, ...: any): any
		if type(action) ~= "string" then
			return { ok = false, msg = "Bad request" }
		end
		if not allowed(player) then
			return { ok = false, msg = "Slow down!" }
		end
		local handler = handlers[action]
		if not handler then
			return { ok = false, msg = "Unknown action" }
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn("[Net] handler '" .. action .. "' failed: " .. tostring(result))
			return { ok = false, msg = "Something went wrong, try again." }
		end
		return result
	end
	Players.PlayerRemoving:Connect(function(player)
		rate[player] = nil
	end)
end

-- kind: "info" | "success" | "error" | "rare" | "event"
function Net.Notify(player: Player, text: string, kind: string?)
	Net.Event("Notify"):FireClient(player, text, kind or "info")
end

function Net.NotifyAll(text: string, kind: string?)
	Net.Event("Notify"):FireAllClients(text, kind or "info")
end

function Net.Effect(player: Player, name: string, payload: { [string]: any }?)
	Net.Event("Effect"):FireClient(player, name, payload or {})
end

function Net.EffectAll(name: string, payload: { [string]: any }?)
	Net.Event("Effect"):FireAllClients(name, payload or {})
end

-- Client only.
function Net.Request(action: string, ...: any): Result
	local ok, result = pcall(function(...)
		return Net.Function("Request"):InvokeServer(action, ...)
	end, ...)
	if ok and type(result) == "table" then
		return result :: Result
	end
	return { ok = false, msg = "Request failed" }
end

return Net
