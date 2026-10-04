--!strict
-- Menu windows: Tool Shop, Robux Store, Rebirth, Planet Index, Daily rewards,
-- Codes, Playtime gifts and the Admin panel.

local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
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

local State = require(script.Parent.Parent.Controllers.State)
local Effects = require(script.Parent.Effects)
local Kit = require(script.Parent.Kit)

local Panels = {}

local player = Players.LocalPlayer
local screen: ScreenGui

type Panel = {
	Holder: Frame,
	Pop: UIScale,
	Body: ScrollingFrame,
	Refresh: () -> (),
}

local panels: { [string]: Panel } = {}
local openName: string? = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function studioTest(): boolean
	return RunService:IsStudio() and Config.TestPurchasesInStudio
end

local function result(res: Net.Result, successText: string?)
	if res.ok then
		if successText or res.msg then
			Effects.Toast(successText or res.msg or "", "success")
		end
	else
		Effects.Toast(res.msg or "Something went wrong", "error")
	end
end

local function createPanel(name: string, title: string, color: Color3): Panel
	local holder = Kit.Frame(screen, name .. "Panel", UDim2.fromOffset(680, 480), UDim2.fromScale(0.5, 0.53))
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Visible = false
	holder.ZIndex = 20
	Kit.AutoScale(holder)

	local panel = Kit.Frame(holder, "Panel", UDim2.fromScale(1, 1), nil, Kit.Colors.Panel)
	Kit.Corner(panel, 22)
	Kit.Stroke(panel, Kit.Colors.Stroke, 4)
	Kit.Gradient(panel, Color3.fromRGB(255, 255, 255), Color3.fromRGB(175, 165, 215))
	local pop = Instance.new("UIScale")
	pop.Parent = panel

	local titleLabel = Kit.Label(panel, "Title", title, UDim2.new(1, -140, 0, 46), UDim2.fromOffset(24, 10), color)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	Kit.Button(panel, "Close", "X", UDim2.fromOffset(48, 48), UDim2.new(1, -62, 0, 10), Kit.Colors.Red, function()
		Panels.Close()
	end)

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(14, 68)
	body.Size = UDim2.new(1, -28, 1, -82)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 8
	body.ScrollBarImageColor3 = color
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.Parent = panel

	local p: Panel = { Holder = holder, Pop = pop, Body = body, Refresh = function() end }
	panels[name] = p
	return p
end

local function sectionTitle(parent: Instance, text: string, order: number)
	local label = Kit.Label(parent, "Section", text, UDim2.new(1, -10, 0, 34), nil, Kit.Colors.Gold)
	label.LayoutOrder = order
	label.TextXAlignment = Enum.TextXAlignment.Left
end

---------------------------------------------------------------------------
-- Tool shop
---------------------------------------------------------------------------
local function buildShop()
	local p = createPanel("Shop", "🛠️ TOOL SHOP", Kit.Colors.Gold)
	Kit.List(p.Body, 8)
	type Row = { Button: TextButton, Label: TextLabel }
	local rows: { [string]: Row } = {}
	local ids: { string } = {}
	for id in Config.Tools do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return Config.Tools[a].Order < Config.Tools[b].Order
	end)
	for _, id in ids do
		local info = Config.Tools[id]
		local row = Kit.Frame(p.Body, id, UDim2.new(1, -14, 0, 86), nil, Kit.Colors.PanelLight)
		row.LayoutOrder = info.Order
		Kit.Corner(row, 14)
		Kit.Stroke(row, Kit.Colors.Stroke, 2)
		Kit.Label(row, "Icon", info.Icon, UDim2.fromOffset(62, 62), UDim2.fromOffset(12, 12))
		local nameLabel = Kit.Label(row, "Name", info.Name, UDim2.new(1, -270, 0, 34), UDim2.fromOffset(86, 8))
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		local desc = Kit.Label(row, "Desc", info.Description, UDim2.new(1, -270, 0, 30), UDim2.fromOffset(86, 46), Kit.Colors.SubText)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		local button, label = Kit.Button(row, "Buy", "", UDim2.fromOffset(160, 56), UDim2.new(1, -172, 0, 15), Kit.Colors.Green, function()
			result(Net.Request("BuyTool", id))
		end)
		rows[id] = { Button = button, Label = label }
	end
	p.Refresh = function()
		local data = State.Data
		if not data then
			return
		end
		for id, row in rows do
			local info = Config.Tools[id]
			if id == "Bat" or data.Tools[id] then
				row.Label.Text = "OWNED ✓"
				row.Button.BackgroundColor3 = Kit.Colors.Disabled
			elseif data.Rebirths < info.Rebirth then
				row.Label.Text = "🔒 Rebirth " .. info.Rebirth
				row.Button.BackgroundColor3 = Kit.Colors.Disabled
			else
				row.Label.Text = Format.Cash(info.Price)
				row.Button.BackgroundColor3 = if data.Cash >= info.Price then Kit.Colors.Green else Kit.Colors.Red
			end
		end
	end
end

---------------------------------------------------------------------------
-- Robux store
---------------------------------------------------------------------------
local prices: { [number]: number } = {}

local function fetchPrice(id: number, infoType: Enum.InfoType)
	if id <= 0 or prices[id] then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, infoType)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			prices[id] = info.PriceInRobux
		end
	end)
end

local function priceText(id: number, suggested: number): string
	if id > 0 then
		return " R$ " .. tostring(prices[id] or suggested)
	elseif studioTest() then
		return "TEST (free)"
	end
	return "Soon"
end

local function buildStore()
	local p = createPanel("Store", "⭐ STORE", Kit.Colors.Pink)
	Kit.List(p.Body, 8)

	type Card = { Kind: string, Key: string, Button: TextButton, Label: TextLabel, Desc: TextLabel }
	local cards: { Card } = {}

	local function card(parent: Instance, order: number, icon: string, name: string, description: string, color: Color3): (TextButton, TextLabel, TextLabel)
		local frame = Kit.Frame(parent, name, UDim2.fromOffset(196, 168), nil, Kit.Colors.PanelLight)
		frame.LayoutOrder = order
		Kit.Corner(frame, 14)
		Kit.Stroke(frame, color, 3)
		Kit.Label(frame, "Icon", icon, UDim2.fromOffset(50, 44), UDim2.new(0.5, -25, 0, 6))
		Kit.Label(frame, "Name", name, UDim2.new(1, -12, 0, 26), UDim2.fromOffset(6, 50), color)
		local desc = Kit.Label(frame, "Desc", description, UDim2.new(1, -14, 0, 38), UDim2.fromOffset(7, 78), Kit.Colors.SubText)
		local button, label = Kit.Button(frame, "Buy", "", UDim2.new(1, -24, 0, 38), UDim2.new(0, 12, 1, -46), Kit.Colors.Green)
		return button, label, desc
	end

	sectionTitle(p.Body, "👑 GAME PASSES (forever)", 1)
	local passGrid = Kit.Frame(p.Body, "Passes", UDim2.new(1, -10, 0, 360))
	passGrid.LayoutOrder = 2
	Kit.Grid(passGrid, Vector2.new(196, 168), 10)
	local passKeys: { string } = {}
	for key in Config.GamePasses do
		table.insert(passKeys, key)
	end
	table.sort(passKeys, function(a, b)
		return Config.GamePasses[a].Order < Config.GamePasses[b].Order
	end)
	for _, key in passKeys do
		local info = Config.GamePasses[key]
		fetchPrice(info.Id, Enum.InfoType.GamePass)
		local button, label, desc = card(passGrid, info.Order, info.Icon, info.Name, info.Description, Kit.Colors.Gold)
		button.Activated:Connect(function()
			if player:GetAttribute("Pass_" .. key) == true then
				return
			end
			if info.Id > 0 then
				MarketplaceService:PromptGamePassPurchase(player, info.Id)
			elseif studioTest() then
				result(Net.Request("TestPurchase", "Pass", key))
			else
				Effects.Toast("Coming soon!", "info")
			end
		end)
		table.insert(cards, { Kind = "Pass", Key = key, Button = button, Label = label, Desc = desc })
	end

	sectionTitle(p.Body, "⚡ BOOSTS & CASH", 3)
	local productGrid = Kit.Frame(p.Body, "Products", UDim2.new(1, -10, 0, 540))
	productGrid.LayoutOrder = 4
	Kit.Grid(productGrid, Vector2.new(196, 168), 10)
	local productKeys: { string } = {}
	for key, info in Config.Products do
		if not info.Hidden then
			table.insert(productKeys, key)
		end
	end
	table.sort(productKeys, function(a, b)
		return Config.Products[a].Order < Config.Products[b].Order
	end)
	for _, key in productKeys do
		local info = Config.Products[key]
		fetchPrice(info.Id, Enum.InfoType.Product)
		local button, label, desc = card(productGrid, info.Order, info.Icon, info.Name, info.Description, Kit.Colors.Blue)
		button.Activated:Connect(function()
			if info.Id > 0 then
				MarketplaceService:PromptProductPurchase(player, info.Id)
			elseif studioTest() then
				result(Net.Request("TestPurchase", "Product", key))
			else
				Effects.Toast("Coming soon!", "info")
			end
		end)
		table.insert(cards, { Kind = "Product", Key = key, Button = button, Label = label, Desc = desc })
	end

	p.Refresh = function()
		local data = State.Data
		for _, c in cards do
			if c.Kind == "Pass" then
				local info = Config.GamePasses[c.Key]
				if player:GetAttribute("Pass_" .. c.Key) == true then
					c.Label.Text = "OWNED ✓"
					c.Button.BackgroundColor3 = Kit.Colors.Disabled
				else
					c.Label.Text = priceText(info.Id, info.SuggestedPrice)
					c.Button.BackgroundColor3 = Kit.Colors.Green
				end
			else
				local info = Config.Products[c.Key]
				c.Label.Text = priceText(info.Id, info.SuggestedPrice)
				if info.Kind == "Cash" and data then
					local amount = Economy.ScaledReward(data.CashPerSec, info.Seconds or 600, info.Minimum or 0)
					c.Desc.Text = "+" .. Format.Cash(amount)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------
local function buildRebirth()
	local p = createPanel("Rebirth", "♻️ REBIRTH", Color3.fromRGB(90, 255, 200))
	Kit.List(p.Body, 10)
	local header = Kit.Label(p.Body, "Header", "", UDim2.new(1, -20, 0, 44), nil, Kit.Colors.Text)
	header.LayoutOrder = 1
	local costLabel = Kit.Label(p.Body, "Cost", "", UDim2.new(1, -20, 0, 34), nil, Kit.Colors.Gold)
	costLabel.LayoutOrder = 2

	local barBack = Kit.Frame(p.Body, "Bar", UDim2.new(1, -60, 0, 26), nil, Kit.Colors.Background)
	barBack.LayoutOrder = 3
	Kit.Corner(barBack, 13)
	Kit.Stroke(barBack, Kit.Colors.Stroke, 3)
	local barFill = Kit.Frame(barBack, "Fill", UDim2.fromScale(0, 1), nil, Kit.Colors.Green)
	Kit.Corner(barFill, 13)

	local rewards = Kit.Label(p.Body, "Rewards", "", UDim2.new(1, -40, 0, 130), nil, Kit.Colors.Text)
	rewards.LayoutOrder = 4
	rewards.TextScaled = true
	local warning = Kit.Label(
		p.Body,
		"Warning",
		"⚠️ Your cash and planets will be reset! Tools are kept.",
		UDim2.new(1, -40, 0, 28),
		nil,
		Kit.Colors.Red
	)
	warning.LayoutOrder = 5
	local button = Kit.Button(p.Body, "Rebirth", "REBIRTH!", UDim2.fromOffset(260, 60), nil, Kit.Colors.Green, function()
		local res = Net.Request("Rebirth")
		if res.ok then
			Panels.Close()
		else
			result(res)
		end
	end)
	button.LayoutOrder = 6

	p.Refresh = function()
		local data = State.Data
		if not data then
			return
		end
		local nextRebirth = data.Rebirths + 1
		header.Text = "Rebirth " .. data.Rebirths .. "  ➜  " .. nextRebirth
		costLabel.Text = Format.Cash(data.Cash) .. " / " .. Format.Cash(data.RebirthCost)
		barFill.Size = UDim2.fromScale(math.clamp(data.Cash / data.RebirthCost, 0, 1), 1)
		local lines = {
			"💰 Cash multiplier: "
				.. Format.Multiplier(Economy.RebirthMultiplier(data.Rebirths))
				.. " ➜ "
				.. Format.Multiplier(Economy.RebirthMultiplier(nextRebirth)),
			"🪐 Planet slots: " .. Economy.UnlockedSlots(data.Rebirths) .. " ➜ " .. Economy.UnlockedSlots(nextRebirth),
			"🔒 Lock time: "
				.. Economy.LockDuration(data.Rebirths, false)
				.. "s ➜ "
				.. Economy.LockDuration(nextRebirth, false)
				.. "s",
		}
		for _, info in Config.Tools do
			if info.Rebirth == nextRebirth then
				table.insert(lines, "🛠️ Unlocks: " .. info.Icon .. " " .. info.Name)
			end
		end
		rewards.Text = table.concat(lines, "\n")
		button.BackgroundColor3 = if data.Cash >= data.RebirthCost then Kit.Colors.Green else Kit.Colors.Disabled
	end
end

---------------------------------------------------------------------------
-- Planet index
---------------------------------------------------------------------------
local function buildIndex()
	local p = createPanel("Index", "📖 PLANET INDEX", Kit.Colors.Blue)
	Kit.List(p.Body, 8)
	local header = Kit.Label(p.Body, "Header", "", UDim2.new(1, -20, 0, 30), nil, Kit.Colors.SubText)
	header.LayoutOrder = 1
	local gridHolder = Kit.Frame(p.Body, "Grid", UDim2.new(1, -10, 0, math.ceil(#Planets.List / 5) * 162))
	gridHolder.LayoutOrder = 2
	Kit.Grid(gridHolder, Vector2.new(116, 154), 8)

	type Cell = {
		Def: Planets.PlanetDef,
		Viewport: ViewportFrame,
		Name: TextLabel,
		Dots: { [string]: Frame },
		Shown: boolean?,
	}
	local cells: { Cell } = {}

	for i, def in Planets.List do
		local rarity = Planets.Rarity(def.Rarity)
		local frame = Kit.Frame(gridHolder, def.Id, UDim2.fromOffset(116, 154), nil, Kit.Colors.PanelLight)
		frame.LayoutOrder = i
		Kit.Corner(frame, 12)
		Kit.Stroke(frame, rarity.Color, 3)
		local viewport = Instance.new("ViewportFrame")
		viewport.Size = UDim2.fromOffset(100, 82)
		viewport.Position = UDim2.fromOffset(8, 6)
		viewport.BackgroundTransparency = 1
		viewport.Ambient = Color3.fromRGB(200, 200, 220)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.Parent = frame
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		local size = def.Visual.Size
		camera.CFrame = CFrame.lookAt(Vector3.new(0, size * 0.35, -size * 2.6), Vector3.zero)

		local nameLabel = Kit.Label(frame, "Name", "???", UDim2.new(1, -8, 0, 22), UDim2.fromOffset(4, 88))
		Kit.Label(frame, "Rarity", def.Rarity, UDim2.new(1, -8, 0, 18), UDim2.fromOffset(4, 110), rarity.Color)
		local dotsFrame = Kit.Frame(frame, "Dots", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 132))
		Kit.List(dotsFrame, 6, true)
		local dots: { [string]: Frame } = {}
		for _, mutation in Mutations.List do
			if mutation.Id ~= "None" then
				local dot = Kit.Frame(dotsFrame, mutation.Id, UDim2.fromOffset(14, 14), nil, Kit.Colors.Background)
				dot.LayoutOrder = mutation.Order
				Kit.Corner(dot, 7)
				Kit.Stroke(dot, mutation.Color, 2)
				dots[mutation.Id] = dot
			end
		end
		table.insert(cells, { Def = def, Viewport = viewport, Name = nameLabel, Dots = dots, Shown = nil })
	end

	local function showModel(cell: Cell, discovered: boolean)
		for _, child in cell.Viewport:GetChildren() do
			if child:IsA("Model") then
				child:Destroy()
			end
		end
		local model = PlanetModel.Build(cell.Def.Id, "None", CFrame.new())
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("ParticleEmitter") or descendant:IsA("PointLight") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") and not discovered then
				descendant.Color = Color3.fromRGB(10, 8, 20)
				descendant.Material = Enum.Material.SmoothPlastic
			end
		end
		model.Parent = cell.Viewport
	end

	p.Refresh = function()
		local index = State.Index
		local planets, variants = Economy.IndexCounts(index)
		header.Text = "Planets "
			.. planets
			.. "/"
			.. #Planets.List
			.. "  •  Variants "
			.. variants
			.. "/"
			.. #Planets.List * (#Mutations.List - 1)
			.. "  •  Bonus +"
			.. string.format("%.1f", Economy.IndexBonus(index) * 100)
			.. "% cash"
		for _, cell in cells do
			local discovered = index[cell.Def.Id] == true
			if cell.Shown ~= discovered then
				cell.Shown = discovered
				showModel(cell, discovered)
				cell.Name.Text = if discovered then cell.Def.Name else "???"
			end
			for mutationId, dot in cell.Dots do
				local found = index[cell.Def.Id .. ":" .. mutationId] == true
				dot.BackgroundColor3 = if found then Mutations.Get(mutationId).Color else Kit.Colors.Background
			end
		end
	end
end

---------------------------------------------------------------------------
-- Daily rewards
---------------------------------------------------------------------------
local function rewardText(reward: Config.Reward, cashPerSec: number): string
	if reward.Planet then
		return reward.Planet
	elseif reward.Rarity then
		return reward.Rarity .. "\nPlanet"
	end
	local cash = (reward.Cash or 0)
	if reward.Seconds then
		cash += Economy.ScaledReward(cashPerSec, reward.Seconds, reward.Minimum or 0)
	end
	return Format.Cash(cash)
end

local function buildDaily()
	local p = createPanel("Daily", "🎁 DAILY REWARDS", Kit.Colors.Green)
	Kit.List(p.Body, 12)
	local row = Kit.Frame(p.Body, "Days", UDim2.new(1, -10, 0, 140))
	row.LayoutOrder = 1
	Kit.List(row, 6, true)
	type Tile = { Frame: Frame, Reward: TextLabel, Check: TextLabel, Stroke: UIStroke }
	local tiles: { Tile } = {}
	for day = 1, #Config.DailyRewards do
		local tile = Kit.Frame(row, "Day" .. day, UDim2.fromOffset(84, 134), nil, Kit.Colors.PanelLight)
		tile.LayoutOrder = day
		Kit.Corner(tile, 12)
		local stroke = Kit.Stroke(tile, Kit.Colors.Stroke, 3)
		Kit.Label(tile, "Day", "Day " .. day, UDim2.new(1, -8, 0, 26), UDim2.fromOffset(4, 6), Kit.Colors.Gold)
		local reward = Kit.Label(tile, "Reward", "", UDim2.new(1, -10, 0, 56), UDim2.fromOffset(5, 38))
		local check = Kit.Label(tile, "Check", "✓", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 98), Kit.Colors.Green)
		table.insert(tiles, { Frame = tile, Reward = reward, Check = check, Stroke = stroke })
	end
	local status = Kit.Label(p.Body, "Status", "", UDim2.new(1, -20, 0, 32), nil, Kit.Colors.SubText)
	status.LayoutOrder = 2
	local button, buttonLabel = Kit.Button(p.Body, "Claim", "CLAIM", UDim2.fromOffset(280, 60), nil, Kit.Colors.Green, function()
		result(Net.Request("ClaimDaily"))
	end)
	button.LayoutOrder = 3
	local hint = Kit.Label(
		p.Body,
		"Hint",
		"Come back every day! Missing a day for more than 48h resets your streak.",
		UDim2.new(1, -40, 0, 26),
		nil,
		Kit.Colors.SubText
	)
	hint.LayoutOrder = 4

	p.Refresh = function()
		local data = State.Data
		if not data then
			return
		end
		local claimedUpTo = if data.DailyReady then data.DailyNextDay - 1 else data.DailyStreak
		local highlight = data.DailyNextDay
		for day, tile in tiles do
			tile.Reward.Text = rewardText(Config.DailyRewards[day], data.CashPerSec)
			tile.Check.Visible = day <= claimedUpTo
			tile.Stroke.Color = if day == highlight then Kit.Colors.Gold else Kit.Colors.Stroke
			tile.Stroke.Thickness = if day == highlight then 4 else 3
		end
		if data.DailyReady then
			buttonLabel.Text = "CLAIM DAY " .. data.DailyNextDay
			button.BackgroundColor3 = Kit.Colors.Green
			status.Text = "Your reward is ready!"
		else
			buttonLabel.Text = "COME BACK LATER"
			button.BackgroundColor3 = Kit.Colors.Disabled
			status.Text = "Next reward in " .. Format.Clock(data.DailyNextAt - serverNow())
		end
	end
end

---------------------------------------------------------------------------
-- Codes
---------------------------------------------------------------------------
local function buildCodes()
	local p = createPanel("Codes", "🎟️ CODES", Kit.Colors.Accent)
	Kit.List(p.Body, 14)
	local info = Kit.Label(
		p.Body,
		"Info",
		"Enter a code to get free rewards!\nNew codes are posted when the game hits like goals.",
		UDim2.new(1, -40, 0, 60),
		nil,
		Kit.Colors.SubText
	)
	info.LayoutOrder = 1
	local box = Instance.new("TextBox")
	box.Name = "CodeBox"
	box.LayoutOrder = 2
	box.Size = UDim2.fromOffset(420, 60)
	box.BackgroundColor3 = Kit.Colors.Background
	box.Font = Kit.Font
	box.PlaceholderText = "Type a code..."
	box.PlaceholderColor3 = Kit.Colors.Disabled
	box.Text = ""
	box.TextScaled = true
	box.TextColor3 = Kit.Colors.Text
	box.ClearTextOnFocus = false
	Kit.Corner(box, 12)
	Kit.Stroke(box, Kit.Colors.Accent, 3)
	Kit.Padding(box, 10)
	box.Parent = p.Body
	local status = Kit.Label(p.Body, "Status", "", UDim2.new(1, -40, 0, 32), nil, Kit.Colors.SubText)
	status.LayoutOrder = 4
	local button = Kit.Button(p.Body, "Redeem", "REDEEM", UDim2.fromOffset(240, 58), nil, Kit.Colors.Green, function()
		local res = Net.Request("RedeemCode", box.Text)
		status.Text = res.msg or (if res.ok then "Redeemed!" else "Invalid code")
		status.TextColor3 = if res.ok then Kit.Colors.Green else Kit.Colors.Red
		if res.ok then
			box.Text = ""
			Effects.Confetti()
		end
	end)
	button.LayoutOrder = 3
end

---------------------------------------------------------------------------
-- Playtime gifts
---------------------------------------------------------------------------
local function buildPlaytime()
	local p = createPanel("Playtime", "⏱️ PLAYTIME GIFTS", Kit.Colors.Pink)
	Kit.List(p.Body, 10)
	local info = Kit.Label(p.Body, "Info", "Stay in the game to unlock free gifts!", UDim2.new(1, -40, 0, 30), nil, Kit.Colors.SubText)
	info.LayoutOrder = 1
	local grid = Kit.Frame(p.Body, "Gifts", UDim2.new(1, -10, 0, math.ceil(#Config.PlaytimeRewards / 4) * 168))
	grid.LayoutOrder = 2
	Kit.Grid(grid, Vector2.new(146, 158), 10)
	type Gift = { Reward: TextLabel, Button: TextButton, Label: TextLabel }
	local gifts: { Gift } = {}
	for i, reward in ipairs(Config.PlaytimeRewards) do
		local tile = Kit.Frame(grid, "Gift" .. i, UDim2.fromOffset(146, 158), nil, Kit.Colors.PanelLight)
		tile.LayoutOrder = i
		Kit.Corner(tile, 14)
		Kit.Stroke(tile, Kit.Colors.Pink, 3)
		Kit.Label(tile, "Time", "🎁 " .. reward.Minutes .. " min", UDim2.new(1, -10, 0, 30), UDim2.fromOffset(5, 6), Kit.Colors.Gold)
		local rewardLabel = Kit.Label(tile, "Reward", "", UDim2.new(1, -12, 0, 52), UDim2.fromOffset(6, 40))
		local button, label = Kit.Button(tile, "Claim", "", UDim2.new(1, -20, 0, 44), UDim2.new(0, 10, 1, -54), Kit.Colors.Green, function()
			result(Net.Request("ClaimPlaytime", i))
		end)
		table.insert(gifts, { Reward = rewardLabel, Button = button, Label = label })
	end
	p.Refresh = function()
		local data = State.Data
		if not data then
			return
		end
		local elapsed = serverNow() - data.PlaytimeStart
		for i, gift in gifts do
			local reward = Config.PlaytimeRewards[i]
			gift.Reward.Text = rewardText({
				Cash = reward.Cash,
				Seconds = reward.Seconds,
				Minimum = reward.Minimum,
				Rarity = reward.Rarity,
				Planet = reward.Planet,
			}, data.CashPerSec)
			if data.PlaytimeClaimed[tostring(i)] then
				gift.Label.Text = "CLAIMED ✓"
				gift.Button.BackgroundColor3 = Kit.Colors.Disabled
			elseif elapsed >= reward.Minutes * 60 then
				gift.Label.Text = "CLAIM!"
				gift.Button.BackgroundColor3 = Kit.Colors.Green
			else
				gift.Label.Text = Format.Clock(reward.Minutes * 60 - elapsed)
				gift.Button.BackgroundColor3 = Kit.Colors.Disabled
			end
		end
	end
end

---------------------------------------------------------------------------
-- Admin
---------------------------------------------------------------------------
local function buildAdmin()
	local p = createPanel("Admin", "⚙️ ADMIN PANEL", Kit.Colors.Red)
	Kit.Grid(p.Body, Vector2.new(196, 60), 10)
	local order = 0
	local function add(text: string, color: Color3, ...: any)
		order += 1
		local args = table.pack(...)
		local button = Kit.Button(p.Body, "Admin" .. order, text, UDim2.fromOffset(196, 60), nil, color, function()
			result(Net.Request("Admin", table.unpack(args, 1, args.n)), "Done!")
		end)
		button.LayoutOrder = order
	end
	add("🚨 ADMIN ABUSE", Kit.Colors.Red, "AdminAbuse")
	for _, info in Config.Events do
		add(info.Icon .. " " .. info.Name, Kit.Colors.Accent, "Event", info.Id)
	end
	add("⏹ Stop Event", Kit.Colors.Disabled, "StopEvent")
	add("🍀 Luck x5 (10m)", Kit.Colors.Green, "Luck", 5)
	add("🌍 Global Meteor", Kit.Colors.Blue, "GlobalEvent", "MeteorShower")
	add("💰 +$1B", Kit.Colors.Gold, "Cash", 1e9)
	add("❓ Spawn Secret", Kit.Colors.Pink, "Spawn", "Multiverse", "Rainbow")
	add("🕳️ Spawn Black Hole", Kit.Colors.Pink, "Spawn", "BlackHole", "Galaxy")
end

---------------------------------------------------------------------------

function Panels.Open(name: string)
	local target = panels[name]
	if not target then
		return
	end
	for other, p in panels do
		if other ~= name then
			p.Holder.Visible = false
		end
	end
	openName = name
	target.Refresh()
	target.Holder.Visible = true
	target.Pop.Scale = 0.85
	Kit.Tween(target.Pop, 0.18, { Scale = 1 })
end

function Panels.Close()
	for _, p in panels do
		p.Holder.Visible = false
	end
	openName = nil
end

function Panels.Toggle(name: string)
	if openName == name then
		Panels.Close()
	else
		Panels.Open(name)
	end
end

function Panels.IsOpen(name: string): boolean
	return openName == name
end

function Panels.Refresh()
	local name = openName
	if name then
		local p = panels[name]
		if p then
			p.Refresh()
		end
	end
end

function Panels.JoinGroup()
	if Config.GroupId <= 0 then
		Effects.Toast("Group rewards are not set up yet.", "info")
		return
	end
	pcall(function()
		GroupService:PromptJoinAsync(Config.GroupId)
	end)
	result(Net.Request("ClaimGroup"))
end

function Panels.Init(gui: ScreenGui)
	screen = gui
	buildShop()
	buildStore()
	buildRebirth()
	buildIndex()
	buildDaily()
	buildCodes()
	buildPlaytime()
	buildAdmin()
	State.Changed:Connect(Panels.Refresh)
end

return Panels
