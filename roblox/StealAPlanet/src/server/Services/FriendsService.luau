--!strict
-- +10% cash per friend in the same server (max +50%). Encourages inviting friends.
-- Result is stored in the player attribute "FriendBoost" (e.g. 0.2 = +20%).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local FriendsService = {}

local friends: { [Player]: { [Player]: boolean } } = {}

local function recompute()
	for _, player in Players:GetPlayers() do
		local count = 0
		local set = friends[player]
		if set then
			for other in set do
				if other.Parent == Players then
					count += 1
				end
			end
		end
		player:SetAttribute("FriendBoost", math.min(count * Config.FriendBonusPer, Config.FriendBonusMax))
	end
end

local function isFriend(a: Player, b: Player): boolean
	local ok, result = pcall(function()
		return a:IsFriendsWithAsync(b.UserId)
	end)
	return ok and result == true
end

function FriendsService.PlayerAdded(player: Player)
	friends[player] = friends[player] or {}
	for _, other in Players:GetPlayers() do
		if other ~= player and isFriend(player, other) then
			(friends[player] :: { [Player]: boolean })[other] = true
			friends[other] = friends[other] or {};
			(friends[other] :: { [Player]: boolean })[player] = true
		end
	end
	recompute()
end

function FriendsService.PlayerRemoving(player: Player)
	friends[player] = nil
	for _, set in friends do
		set[player] = nil
	end
	recompute()
end

return FriendsService
