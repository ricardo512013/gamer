--!strict
-- Always-visible HUD: cash counter, cash/s, event & luck banners, tutorial
-- hint, menu buttons (left), playtime gift + group buttons (right).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local State = require(script.Parent.Parent.Controllers.State)
local Kit = require(script.Parent.Kit)
local Panels = require(script.Parent.Panels)

local HUD = {}

local player = Players.LocalPlayer

local cashLabel: TextLabel
local cpsLabel: TextLabel
local pendingLabel: TextLabel
local eventBanner: Frame
local eventLabel: TextLabel
local luckBanner: Frame
local luckLabel: TextLabel
local tutorialLabel: TextLabel
local adminButton: TextButton
local dailyDot: Frame
local giftDot: Frame
local giftTimer: TextLabel
local groupButton: TextButton?

local displayedCash = 0

local TUTORIAL = {
	[0] = "👉 Go to the glowing Cosmic Belt and press E to buy a planet!",
	[1] = "💰 Step on the green pad under your planet to collect cash!",
}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function dot(parent: Instance): Frame
	local d = Kit.Frame(parent, "Dot", UDim2.fromOffset(22, 22), UDim2.new(1, -16, 0, -6), Kit.Colors.Red)
	d.ZIndex = 5
	Kit.Corner(d, 11)
	Kit.Stroke(d, Kit.Colors.Stroke, 2)
	d.Visible = false
	return d
end

local function menuButton(parent: Instance, order: number, icon: string, text: string, color: Color3, panel: string): TextButton
	local button = Kit.Button(parent, panel, "", UDim2.fromOffset(78, 78), nil, color, function()
		Panels.Toggle(panel)
	end)
	button.LayoutOrder = order
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = icon
		label.Size = UDim2.new(1, -12, 0, 46)
		label.Position = UDim2.fromOffset(6, 4)
	end
	Kit.Label(button, "Caption", text, UDim2.new(1, -6, 0, 22), UDim2.new(0, 3, 1, -26))
	return button
end

function HUD.Init(screen: ScreenGui)
	-- top bar ----------------------------------------------------------------
	local top = Kit.Frame(screen, "TopBar", UDim2.fromOffset(380, 110), UDim2.new(0.5, 0, 0, 4))
	top.AnchorPoint = Vector2.new(0.5, 0)
	Kit.AutoScale(top)
	local cashBack = Kit.Frame(top, "CashBack", UDim2.fromOffset(330, 56), UDim2.fromOffset(25, 0), Kit.Colors.Panel)
	Kit.Corner(cashBack, 16)
	Kit.Stroke(cashBack, Kit.Colors.Stroke, 3)
	Kit.Gradient(cashBack, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 160, 210))
	cashLabel = Kit.Label(cashBack, "Cash", "$0", UDim2.new(1, -20, 1, -8), UDim2.fromOffset(10, 4), Kit.Colors.Gold)
	cpsLabel = Kit.Label(top, "Cps", "$0/s", UDim2.fromOffset(330, 28), UDim2.fromOffset(25, 58), Kit.Colors.Green)
	pendingLabel = Kit.Label(top, "Pending", "", UDim2.fromOffset(330, 22), UDim2.fromOffset(25, 86), Kit.Colors.SubText)

	-- banners ----------------------------------------------------------------
	local banners = Kit.Frame(screen, "Banners", UDim2.fromOffset(420, 80), UDim2.new(0.5, 0, 0, 118))
	banners.AnchorPoint = Vector2.new(0.5, 0)
	Kit.AutoScale(banners)
	Kit.List(banners, 6)
	eventBanner = Kit.Frame(banners, "Event", UDim2.fromOffset(420, 36), nil, Color3.fromRGB(120, 70, 220))
	eventBanner.LayoutOrder = 1
	Kit.Corner(eventBanner, 12)
	Kit.Stroke(eventBanner, Kit.Colors.Stroke, 3)
	eventLabel = Kit.Label(eventBanner, "Text", "", UDim2.new(1, -16, 1, -6), UDim2.fromOffset(8, 3))
	eventBanner.Visible = false
	luckBanner = Kit.Frame(banners, "Luck", UDim2.fromOffset(340, 32), nil, Color3.fromRGB(40, 160, 80))
	luckBanner.LayoutOrder = 2
	Kit.Corner(luckBanner, 12)
	Kit.Stroke(luckBanner, Kit.Colors.Stroke, 3)
	luckLabel = Kit.Label(luckBanner, "Text", "", UDim2.new(1, -16, 1, -6), UDim2.fromOffset(8, 3))
	luckBanner.Visible = false

	-- tutorial ---------------------------------------------------------------
	local tutorialFrame = Kit.Frame(screen, "Tutorial", UDim2.fromOffset(640, 40), UDim2.new(0.5, 0, 0, 200))
	tutorialFrame.AnchorPoint = Vector2.new(0.5, 0)
	Kit.AutoScale(tutorialFrame)
	tutorialLabel = Kit.Label(tutorialFrame, "Text", "", UDim2.fromScale(1, 1), nil, Kit.Colors.Text)
	tutorialLabel.Visible = false

	-- left menu --------------------------------------------------------------
	local left = Kit.Frame(screen, "Menu", UDim2.fromOffset(172, 360), UDim2.new(0, 10, 0.5, 0))
	left.AnchorPoint = Vector2.new(0, 0.5)
	Kit.AutoScale(left)
	local grid = Kit.Grid(left, Vector2.new(78, 78), 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	menuButton(left, 1, "🛠️", "Shop", Kit.Colors.Gold, "Shop")
	menuButton(left, 2, "⭐", "Store", Kit.Colors.Pink, "Store")
	menuButton(left, 3, "♻️", "Rebirth", Color3.fromRGB(60, 200, 160), "Rebirth")
	menuButton(left, 4, "📖", "Index", Kit.Colors.Blue, "Index")
	local daily = menuButton(left, 5, "🎁", "Daily", Kit.Colors.Green, "Daily")
	dailyDot = dot(daily)
	menuButton(left, 6, "🎟️", "Codes", Kit.Colors.Accent, "Codes")
	adminButton = menuButton(left, 7, "⚙️", "Admin", Kit.Colors.Red, "Admin")
	adminButton.Visible = false

	-- right side -------------------------------------------------------------
	local right = Kit.Frame(screen, "Right", UDim2.fromOffset(96, 200), UDim2.new(1, -10, 0.5, 0))
	right.AnchorPoint = Vector2.new(1, 0.5)
	Kit.AutoScale(right)
	Kit.List(right, 10)
	local gift = Kit.Button(right, "Gifts", "", UDim2.fromOffset(90, 90), nil, Kit.Colors.Pink, function()
		Panels.Toggle("Playtime")
	end)
	gift.LayoutOrder = 1
	local giftIcon = gift:FindFirstChild("Label")
	if giftIcon and giftIcon:IsA("TextLabel") then
		giftIcon.Text = "🎁"
		giftIcon.Size = UDim2.new(1, -16, 0, 50)
		giftIcon.Position = UDim2.fromOffset(8, 4)
	end
	giftTimer = Kit.Label(gift, "Timer", "", UDim2.new(1, -8, 0, 26), UDim2.new(0, 4, 1, -30))
	giftDot = dot(gift)

	if Config.GroupId > 0 then
		local groupBtn = Kit.Button(right, "Group", "👥 +10%", UDim2.fromOffset(90, 56), nil, Kit.Colors.Blue, function()
			Panels.JoinGroup()
		end)
		groupBtn.LayoutOrder = 2
		groupButton = groupBtn
	end

	RunService.RenderStepped:Connect(function(dt: number)
		local data = State.Data
		if not data then
			return
		end
		displayedCash += (data.Cash - displayedCash) * math.min(1, dt * 10)
		if math.abs(data.Cash - displayedCash) < 1 then
			displayedCash = data.Cash
		end
		cashLabel.Text = Format.Cash(displayedCash)
	end)

	State.Changed:Connect(HUD.Refresh)
	task.spawn(function()
		while true do
			HUD.RefreshTimers()
			task.wait(0.5)
		end
	end)
end

function HUD.Refresh()
	local data = State.Data
	if not data then
		return
	end
	cpsLabel.Text = "+" .. Format.PerSecond(data.CashPerSec) .. "  (" .. Format.Multiplier(data.Multiplier) .. ")"
	local pendingText = "🪐 " .. data.SlotsUsed .. "/" .. data.SlotsUnlocked .. " slots"
	if data.Pending > 0 then
		pendingText ..= "  •  📦 " .. data.Pending .. " in storage"
	end
	pendingLabel.Text = pendingText
	local tip = TUTORIAL[data.Tutorial]
	tutorialLabel.Visible = tip ~= nil
	tutorialLabel.Text = tip or ""
	dailyDot.Visible = data.DailyReady
	adminButton.Visible = player:GetAttribute("IsAdmin") == true
	local groupBtn = groupButton
	if groupBtn then
		groupBtn.Visible = not data.GroupClaimed or player:GetAttribute("InGroup") ~= true
	end
end

function HUD.RefreshTimers()
	local now = serverNow()
	local eventId = ReplicatedStorage:GetAttribute("EventId")
	local eventEnds = ReplicatedStorage:GetAttribute("EventEndsAt")
	local info: Config.EventInfo? = nil
	if type(eventId) == "string" and eventId ~= "" then
		for _, e in Config.Events do
			if e.Id == eventId then
				info = e
			end
		end
	end
	if info and type(eventEnds) == "number" and eventEnds > now then
		eventBanner.Visible = true
		eventBanner.BackgroundColor3 = info.Color:Lerp(Color3.fromRGB(30, 20, 60), 0.35)
		eventLabel.Text = info.Icon .. " " .. string.upper(info.Name) .. " - " .. info.Description .. "  " .. Format.Clock(eventEnds - now)
	else
		eventBanner.Visible = false
	end

	local luck = ReplicatedStorage:GetAttribute("LuckMult")
	local luckEnds = ReplicatedStorage:GetAttribute("LuckEndsAt")
	if type(luck) == "number" and luck > 1 and type(luckEnds) == "number" and luckEnds > now then
		luckBanner.Visible = true
		luckLabel.Text = "🍀 SERVER LUCK x" .. luck .. "  " .. Format.Clock(luckEnds - now)
	else
		luckBanner.Visible = false
	end

	local data = State.Data
	if data then
		local elapsed = now - data.PlaytimeStart
		local nextIn: number? = nil
		local ready = false
		for i, reward in ipairs(Config.PlaytimeRewards) do
			if not data.PlaytimeClaimed[tostring(i)] then
				local remaining = reward.Minutes * 60 - elapsed
				if remaining <= 0 then
					ready = true
				elseif not nextIn or remaining < nextIn then
					nextIn = remaining
				end
			end
		end
		giftDot.Visible = ready
		giftTimer.Text = if ready then "READY!" elseif nextIn then Format.Clock(nextIn) else "DONE"
		if Panels.IsOpen("Daily") or Panels.IsOpen("Playtime") then
			Panels.Refresh()
		end
	end
end

return HUD
