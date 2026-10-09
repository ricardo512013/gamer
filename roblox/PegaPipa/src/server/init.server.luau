--!strict
--[[
	Bootstrap do servidor (GDD §7.1). Ordem fixa:
	Remotes.init → MapGen → DataService → MonetizationService → KiteService → ShopService → EventService → Leaderboard
	Cada módulo é carregado (require) e iniciado (start) dentro de pcall: um módulo quebrado não derruba os outros.
	Os serviços são ModuleScripts filhos deste Script (script.X); entre si usam script.Parent.X.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local function boot(name: string, fn: () -> ())
	local ok, err = pcall(function(): string?
		fn()
		return nil
	end)
	if ok then
		print(`[PegaPipa] {name} ok`)
	else
		warn(`[PegaPipa] {name} falhou: {err}`)
	end
end

boot("Remotes.init", function()
	Remotes.init()
end)
boot("MapGen", function()
	require(script.MapGen).start()
end)
boot("DataService", function()
	require(script.DataService).start()
end)
boot("MonetizationService", function()
	require(script.MonetizationService).start()
end)
boot("KiteService", function()
	require(script.KiteService).start()
end)
boot("ShopService", function()
	require(script.ShopService).start()
end)
boot("EventService", function()
	require(script.EventService).start()
end)
boot("Leaderboard", function()
	require(script.Leaderboard).start()
end)
