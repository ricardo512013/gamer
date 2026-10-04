--!strict
-- Holds the latest snapshot sent by the server.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local State = {}

State.Changed = Signal.new()
State.Data = nil :: Types.Snapshot?
State.Index = {} :: { [string]: boolean }

function State.Start()
	Net.Event("Sync").OnClientEvent:Connect(function(snapshot: Types.Snapshot)
		local index = snapshot.Index
		if index then
			State.Index = index
		end
		State.Data = snapshot
		State.Changed:Fire()
	end)
end

return State
