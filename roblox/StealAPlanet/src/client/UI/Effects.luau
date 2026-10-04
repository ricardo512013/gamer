--!strict
-- Toast notifications, confetti, floating "+$" text, steal alarm and popups.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Format)
local PlanetModel = require(Shared.PlanetModel)

local Sound = require(script.Parent.Parent.Controllers.Sound)
local Kit = require(script.Parent.Kit)

local Effects = {}

local gui: ScreenGui
local toastHolder: Frame
local alertLabel: TextLabel
local carryLabel: TextLabel
local alertToken = 0

local KIND_COLORS: { [string]: Color3 } = {
	info = Color3.fromRGB(60, 47, 110),
	success = Color3.fromRGB(40, 150, 80),
	error = Color3.fromRGB(190, 50, 70),
	rare = Color3.fromRGB(255, 255, 255),
	event = Color3.fromRGB(120, 70, 220),
}

function Effects.Init(screen: ScreenGui)
	gui = screen

	local holder = Kit.Frame(screen, "Toasts", UDim2.fromOffset(560, 260), UDim2.new(0.5, 0, 1, -120))
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.ZIndex = 50
	local layout = Kit.List(holder, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	Kit.AutoScale(holder)
	toastHolder = holder

	local alertFrame = Kit.Frame(screen, "Alert", UDim2.fromOffset(760, 80), UDim2.fromScale(0.5, 0.28))
	alertFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	alertFrame.ZIndex = 60
	Kit.AutoScale(alertFrame)
	alertLabel = Kit.Label(alertFrame, "Text", "", UDim2.fromScale(1, 1), nil, Kit.Colors.Red)
	alertLabel.ZIndex = 60
	alertLabel.Visible = false

	local carryFrame = Kit.Frame(screen, "Carry", UDim2.fromOffset(620, 44), UDim2.new(0.5, 0, 0, 190))
	carryFrame.AnchorPoint = Vector2.new(0.5, 0)
	Kit.AutoScale(carryFrame)
	carryLabel = Kit.Label(carryFrame, "Text", "🏃 Bring the planet to YOUR base!", UDim2.fromScale(1, 1), nil, Kit.Colors.Gold)
	carryLabel.Visible = false
end

function Effects.Toast(text: string, kind: string?)
	local k = kind or "info"
	local toast = Kit.Frame(toastHolder, "Toast", UDim2.fromOffset(540, 42), nil, KIND_COLORS[k] or KIND_COLORS.info)
	toast.LayoutOrder = math.floor(os.clock() * 100)
	toast.BackgroundTransparency = 0.05
	Kit.Corner(toast, 10)
	Kit.Stroke(toast, Kit.Colors.Stroke, 2)
	if k == "rare" then
		local gradient = Instance.new("UIGradient")
		gradient.Color = PlanetModel.RainbowSequence()
		gradient.Parent = toast
	end
	local label = Kit.Label(toast, "Text", text, UDim2.new(1, -16, 1, -8), UDim2.fromOffset(8, 4))
	label.TextXAlignment = Enum.TextXAlignment.Center

	local toasts = {}
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 5 then
		table.sort(toasts, function(a: Frame, b: Frame)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	if k == "rare" or k == "event" then
		Sound.Play("Cash")
	end
	task.delay(if k == "rare" or k == "event" then 6 else 3.5, function()
		if toast.Parent then
			Kit.Tween(toast, 0.3, { BackgroundTransparency = 1 })
			Kit.Tween(label, 0.3, { TextTransparency = 1 })
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

function Effects.Confetti()
	local colors = {
		Kit.Colors.Gold,
		Kit.Colors.Pink,
		Kit.Colors.Blue,
		Kit.Colors.Green,
		Kit.Colors.Accent,
	}
	for _ = 1, 45 do
		local piece = Instance.new("Frame")
		piece.Size = UDim2.fromOffset(math.random(8, 14), math.random(12, 20))
		piece.Position = UDim2.new(math.random(), 0, 0, -30)
		piece.BackgroundColor3 = colors[math.random(1, #colors)]
		piece.BorderSizePixel = 0
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 80
		piece.Parent = gui
		local duration = 1.6 + math.random() * 1.2
		Kit.Tween(piece, duration, {
			Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0),
			Rotation = piece.Rotation + math.random(-360, 360),
		})
		task.delay(duration, function()
			piece:Destroy()
		end)
	end
end

function Effects.CashPop(amount: number, position: Vector3)
	Sound.Play("Cash", 0.4)
	local anchor = Instance.new("Part")
	anchor.Name = "CashPop"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(6, 1.6)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = anchor
	local label = Kit.Label(billboard, "Text", "+" .. Format.Cash(amount), UDim2.fromScale(1, 1), nil, Kit.Colors.Green)
	anchor.Parent = Workspace
	Kit.Tween(billboard, 1, { StudsOffsetWorldSpace = Vector3.new(0, 3, 0) })
	task.delay(0.6, function()
		Kit.Tween(label, 0.4, { TextTransparency = 1 })
	end)
	task.delay(1.05, function()
		anchor:Destroy()
	end)
end

function Effects.Alert(text: string, color: Color3, duration: number)
	alertToken += 1
	local token = alertToken
	alertLabel.Text = text
	alertLabel.TextColor3 = color
	alertLabel.Visible = true
	task.spawn(function()
		local started = os.clock()
		while alertToken == token and os.clock() - started < duration do
			alertLabel.TextTransparency = if alertLabel.TextTransparency == 0 then 0.35 else 0
			task.wait(0.25)
		end
		if alertToken == token then
			alertLabel.Visible = false
			alertLabel.TextTransparency = 0
		end
	end)
end

function Effects.StealAlert(thief: string, planet: string)
	Effects.Alert("⚠️ " .. thief .. " IS STEALING YOUR " .. string.upper(planet) .. "!", Kit.Colors.Red, 4)
	task.spawn(function()
		for _ = 1, 3 do
			Sound.Play("Alarm", 0.8)
			task.wait(0.35)
		end
	end)
end

function Effects.SetCarrying(active: boolean)
	carryLabel.Visible = active
end

function Effects.Popup(title: string, body: string)
	local holder = Kit.Frame(gui, "Popup", UDim2.fromOffset(460, 250), UDim2.fromScale(0.5, 0.5))
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.ZIndex = 70
	Kit.AutoScale(holder)
	local panel = Kit.Frame(holder, "Panel", UDim2.fromScale(1, 1), nil, Kit.Colors.Panel)
	Kit.Corner(panel, 18)
	Kit.Stroke(panel, Kit.Colors.Stroke, 4)
	Kit.Gradient(panel, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 160, 210))
	Kit.Label(panel, "Title", title, UDim2.new(1, -30, 0, 50), UDim2.fromOffset(15, 14), Kit.Colors.Gold)
	local bodyLabel = Kit.Label(panel, "Body", body, UDim2.new(1, -40, 0, 100), UDim2.fromOffset(20, 72))
	bodyLabel.TextScaled = true
	Kit.Button(panel, "Ok", "AWESOME!", UDim2.fromOffset(200, 50), UDim2.new(0.5, -100, 1, -66), Kit.Colors.Green, function()
		holder:Destroy()
	end)
end

function Effects.Welcome(amount: number, seconds: number)
	Effects.Popup(
		"🌙 Welcome back!",
		"While you were away (" .. Format.Duration(seconds) .. ") your planets made " .. Format.Cash(amount) .. ".\nCollect it on the green pads in your base!"
	)
end

function Effects.LocalPlayer(): Player
	return Players.LocalPlayer
end

return Effects
