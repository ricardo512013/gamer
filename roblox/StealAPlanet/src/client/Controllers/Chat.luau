--!strict
-- Adds a golden [VIP] tag in chat for players who own the VIP pass.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Chat = {}

function Chat.Start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		if not source then
			return nil
		end
		local sender = Players:GetPlayerByUserId(source.UserId)
		if sender and sender:GetAttribute("Pass_VIP") == true then
			local properties = Instance.new("TextChatMessageProperties")
			properties.PrefixText = '<font color="#FFD24A">[VIP]</font> ' .. message.PrefixText
			return properties
		end
		return nil
	end
end

return Chat
