--!strict
-- The Cosmic Belt: random planets come out of a portal and travel along the
-- conveyor. Players buy them with cash (E) or Robux for rare ones (F).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Mutations = require(Shared.Mutations)
local Net = require(Shared.Net)
local PlanetModel = require(Shared.PlanetModel)
local Planets = require(Shared.Planets)
local Signal = require(Shared.Signal)

local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local MapBuilder = require(script.Parent.MapBuilder)
local PlotService = require(script.Parent.PlotService)

local BeltService = {}

-- Fired when a player wants to buy a belt planet with Robux: (player, productKey)
BeltService.InstantBuyRequested = Signal.new()

type Item = {
	Uid: number,
	Def: Planets.PlanetDef,
	Mut: string,
	Model: Model,
	Core: BasePart,
	Dist: number,
	Height: number,
	Price: number,
	Spin: number,
}

export type PendingBuy = { Id: string, Mut: string, Uid: number, Time: number }

local items: { [number]: Item } = {}
local nextUid = 0
local pendingRobux: { [Player]: PendingBuy } = {}
local folder: Folder
local rng = Random.new()

local START = MapBuilder.BELT_START
local DIRECTION = (MapBuilder.BELT_END - MapBuilder.BELT_START).Unit
local LENGTH = (MapBuilder.BELT_END - MapBuilder.BELT_START).Magnitude

local function rand(): number
	return rng:NextNumber()
end

local function productKeyFor(rarity: string): string
	return "Buy" .. rarity
end

local function robuxEnabled(rarity: string): boolean
	local product = Config.Products[productKeyFor(rarity)]
	if not product then
		return false
	end
	return product.Id > 0 or (RunService:IsStudio() and Config.TestPurchasesInStudio)
end

local function itemCFrame(item: Item, t: number): CFrame
	local position = START + DIRECTION * item.Dist + Vector3.new(0, item.Height, 0)
	return CFrame.new(position) * CFrame.Angles(0, t * 1.1 + item.Spin, 0)
end

local function removeItem(item: Item)
	items[item.Uid] = nil
	item.Model:Destroy()
end

local function tryBuy(player: Player, item: Item)
	if items[item.Uid] ~= item then
		return
	end
	local root = CharacterService.GetRoot(player)
	if not root or (root.Position - item.Core.Position).Magnitude > Config.Belt.BuyDistance then
		return
	end
	local data = DataService.Get(player)
	if not data or not PlotService.GetPlot(player) then
		return
	end
	if PlotService.FreeSlots(player) <= 0 then
		Net.Notify(player, "Your base is full! Sell a planet or rebirth for more slots.", "error")
		return
	end
	if not DataService.SpendCash(player, item.Price) then
		Net.Notify(player, "Not enough cash! You need " .. Format.Cash(item.Price) .. ".", "error")
		return
	end
	local from = item.Core.CFrame
	removeItem(item)
	PlotService.AddPlanet(player, item.Def.Id, item.Mut, from)
	if data.Tutorial == 0 then
		data.Tutorial = 1
	end
	local label = if item.Mut ~= "None" then Mutations.Get(item.Mut).Name .. " " .. item.Def.Name else item.Def.Name
	Net.Notify(player, "🪐 You bought " .. label .. "!", "success")
	if Planets.RarityOrder(item.Def.Rarity) >= 5 then
		Net.NotifyAll("💫 " .. player.DisplayName .. " bought a " .. string.upper(item.Def.Rarity) .. " " .. label .. "!", "rare")
	end
end

local function tryRobuxBuy(player: Player, item: Item)
	if items[item.Uid] ~= item then
		return
	end
	if PlotService.FreeSlots(player) <= 0 then
		Net.Notify(player, "Your base is full! Free a slot first.", "error")
		return
	end
	pendingRobux[player] = { Id = item.Def.Id, Mut = item.Mut, Uid = item.Uid, Time = os.clock() }
	BeltService.InstantBuyRequested:Fire(player, productKeyFor(item.Def.Rarity))
end

-- Called by MonetizationService when an instant-buy product is paid.
-- Returns the planet the player chose (or nil) and where to fly it from.
function BeltService.TakePending(player: Player, rarity: string): (string?, string?, CFrame?)
	local pending = pendingRobux[player]
	pendingRobux[player] = nil
	if not pending or os.clock() - pending.Time > 600 then
		return nil, nil, nil
	end
	local def = Planets.Get(pending.Id)
	if not def or def.Rarity ~= rarity then
		return nil, nil, nil
	end
	local item = items[pending.Uid]
	local from: CFrame? = nil
	if item then
		from = item.Core.CFrame
		removeItem(item)
	end
	return pending.Id, pending.Mut, from
end

function BeltService.Spawn(def: Planets.PlanetDef, mutation: string)
	nextUid += 1
	local uid = nextUid
	local height = MapBuilder.BELT_TOP + 1 + def.Visual.Size / 2
	local price = Economy.PlanetPrice(def, mutation)
	local item: Item
	local model = PlanetModel.Build(def.Id, mutation, CFrame.new(START + Vector3.new(0, height, 0)))
	model.Name = def.Name
	model:SetAttribute("Mode", "Belt")
	model:SetAttribute("Price", price)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local core = model.PrimaryPart :: BasePart

	local tag = PlanetModel.CreateTag(def.Id, mutation, "Belt")
	tag.Parent = core

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy " .. Format.Cash(price)
	prompt.ObjectText = def.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = core

	if robuxEnabled(def.Rarity) then
		local robuxPrompt = Instance.new("ProximityPrompt")
		robuxPrompt.Name = "RobuxPrompt"
		robuxPrompt.ActionText = "Instant Buy (R$)"
		robuxPrompt.ObjectText = def.Rarity
		robuxPrompt.HoldDuration = 0
		robuxPrompt.MaxActivationDistance = 11
		robuxPrompt.RequiresLineOfSight = false
		robuxPrompt.KeyboardKeyCode = Enum.KeyCode.F
		robuxPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		robuxPrompt.UIOffset = Vector2.new(0, 80)
		robuxPrompt.Parent = core
		robuxPrompt.Triggered:Connect(function(player: Player)
			tryRobuxBuy(player, item)
		end)
	end

	item = {
		Uid = uid,
		Def = def,
		Mut = mutation,
		Model = model,
		Core = core,
		Dist = 0,
		Height = height,
		Price = price,
		Spin = rng:NextNumber() * math.pi * 2,
	}
	prompt.Triggered:Connect(function(player: Player)
		tryBuy(player, item)
	end)

	model.Parent = folder
	CollectionService:AddTag(model, "BeltPlanet")
	items[uid] = item

	if Planets.RarityOrder(def.Rarity) >= Config.Belt.AnnounceRarityOrder then
		local label = if mutation ~= "None" then Mutations.Get(mutation).Name .. " " .. def.Name else def.Name
		Net.NotifyAll("🌟 A " .. string.upper(def.Rarity) .. " " .. label .. " appeared on the Cosmic Belt!", "rare")
	end
end

function BeltService.SpawnRandom()
	local def = Planets.Roll(rand, EventService.GetLuck())
	local mutation = Mutations.Roll(rand, EventService.GetMutationMultipliers())
	BeltService.Spawn(def, mutation)
end

local spawnTimer = 0
local function step(dt: number)
	local t = Workspace:GetServerTimeNow()
	for _, item in items do
		item.Dist += Config.Belt.Speed * dt
		if item.Dist >= LENGTH then
			removeItem(item)
		else
			item.Core.CFrame = itemCFrame(item, t)
		end
	end
	spawnTimer += dt
	if spawnTimer >= Config.Belt.SpawnInterval then
		spawnTimer -= Config.Belt.SpawnInterval
		BeltService.SpawnRandom()
	end
end

function BeltService.Init()
	local existing = Workspace:FindFirstChild("BeltPlanets")
	if existing then
		existing:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "BeltPlanets"
	folder.Parent = Workspace
end

function BeltService.Run()
	-- pre-fill the belt so it is not empty when the server starts
	local count = math.floor(LENGTH / (Config.Belt.Speed * Config.Belt.SpawnInterval))
	for i = count, 1, -1 do
		BeltService.SpawnRandom()
		local item = items[nextUid]
		if item then
			item.Dist = i * Config.Belt.Speed * Config.Belt.SpawnInterval
		end
	end
	RunService.Heartbeat:Connect(step)
end

function BeltService.PlayerRemoving(player: Player)
	pendingRobux[player] = nil
end

return BeltService
