--!strict
-- STEAL A PLANET - client entry point.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")
local UIFolder = script.Parent:WaitForChild("UI")

local Chat = require(Controllers:WaitForChild("Chat"))
local Sound = require(Controllers:WaitForChild("Sound"))
local State = require(Controllers:WaitForChild("State"))
local Tools = require(Controllers:WaitForChild("Tools"))
local World = require(Controllers:WaitForChild("World"))
local Effects = require(UIFolder:WaitForChild("Effects"))
local HUD = require(UIFolder:WaitForChild("HUD"))
local Kit = require(UIFolder:WaitForChild("Kit"))
local Panels = require(UIFolder:WaitForChild("Panels"))

local player = Players.LocalPlayer

State.Start()

local screen = Instance.new("ScreenGui")
screen.Name = "StealAPlanetUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
screen.Parent = player:WaitForChild("PlayerGui")

Kit.StartAutoScale()
Effects.Init(screen)
Panels.Init(screen)
HUD.Init(screen)
World.Start()
Tools.Start()
Chat.Start()
Sound.StartMusic()

Net.Event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
	if type(text) == "string" then
		Effects.Toast(text, if type(kind) == "string" then kind else "info")
	end
end)
