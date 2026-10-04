--!strict
-- Small UI toolkit: consistent colors, rounded corners, strokes, buttons with a
-- press animation, and automatic scaling for phones/tablets/PC.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Sound = require(script.Parent.Parent.Controllers.Sound)

local Kit = {}

Kit.Font = Enum.Font.FredokaOne

Kit.Colors = {
	Background = Color3.fromRGB(26, 20, 52),
	Panel = Color3.fromRGB(40, 31, 78),
	PanelLight = Color3.fromRGB(60, 47, 110),
	Stroke = Color3.fromRGB(12, 8, 28),
	Accent = Color3.fromRGB(130, 95, 255),
	Green = Color3.fromRGB(70, 205, 105),
	Red = Color3.fromRGB(235, 70, 90),
	Gold = Color3.fromRGB(255, 195, 55),
	Blue = Color3.fromRGB(70, 160, 255),
	Pink = Color3.fromRGB(255, 100, 190),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(200, 190, 240),
	Disabled = Color3.fromRGB(95, 90, 120),
}

local scales: { UIScale } = {}

local function currentScale(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end
	local size = camera.ViewportSize
	return math.clamp(math.min(size.X / 1280, size.Y / 720), 0.55, 1.3)
end

function Kit.AutoScale(target: GuiObject): UIScale
	local scale = Instance.new("UIScale")
	scale.Scale = currentScale()
	scale.Parent = target
	table.insert(scales, scale)
	return scale
end

function Kit.StartAutoScale()
	local function update()
		local value = currentScale()
		for _, scale in scales do
			scale.Scale = value
		end
	end
	local function hook()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	hook()
end

function Kit.Corner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = parent
	return corner
end

function Kit.Stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Kit.Colors.Stroke
	stroke.Thickness = thickness or 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Kit.Padding(parent: Instance, pixels: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = parent
	return padding
end

function Kit.Gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	gradient.Parent = parent
	return gradient
end

function Kit.List(parent: Instance, padding: number, horizontal: boolean?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = parent
	return layout
end

function Kit.Grid(parent: Instance, cell: Vector2, padding: number): UIGridLayout
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	grid.CellPadding = UDim2.fromOffset(padding, padding)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = parent
	return grid
end

function Kit.Frame(parent: Instance, name: string, size: UDim2, position: UDim2?, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position or UDim2.new()
	frame.BackgroundColor3 = color or Kit.Colors.Panel
	frame.BorderSizePixel = 0
	if not color then
		frame.BackgroundTransparency = 1
	end
	frame.Parent = parent
	return frame
end

function Kit.Label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2?, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position or UDim2.new()
	label.BackgroundTransparency = 1
	label.Font = Kit.Font
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color or Kit.Colors.Text
	label.TextWrapped = true
	label.RichText = true
	local stroke = Instance.new("UIStroke")
	stroke.Color = Kit.Colors.Stroke
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	label.Parent = parent
	return label
end

function Kit.Tween(target: Instance, time: number, properties: { [string]: any }): Tween
	local tween = TweenService:Create(target, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
	tween:Play()
	return tween
end

-- Colored rounded button with a press animation. Returns the button and its label.
function Kit.Button(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2?,
	color: Color3?,
	onClick: (() -> ())?
): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position or UDim2.new()
	button.BackgroundColor3 = color or Kit.Colors.Accent
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	Kit.Corner(button, 12)
	Kit.Stroke(button, Kit.Colors.Stroke, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 190))
	gradient.Rotation = 90
	gradient.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local label = Kit.Label(button, "Label", text, UDim2.fromScale(0.9, 0.7), UDim2.fromScale(0.05, 0.15))
	button.MouseEnter:Connect(function()
		Kit.Tween(scale, 0.12, { Scale = 1.06 })
	end)
	button.MouseLeave:Connect(function()
		Kit.Tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		Kit.Tween(scale, 0.08, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(function()
		Kit.Tween(scale, 0.1, { Scale = 1 })
	end)
	if onClick then
		button.Activated:Connect(function()
			Sound.Play("Click")
			onClick()
		end)
	end
	button.Parent = parent
	return button, label
end

return Kit
