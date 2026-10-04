--!strict
-- Number and time formatting helpers ("$1.25M", "2:05", "1h 05m").

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trim(s: string): string
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

function Format.Number(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	local text: string
	if n < 1000 then
		text = tostring(math.floor(n))
	else
		local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
		local value = n / 10 ^ (tier * 3)
		-- guard against floating point error in log10 (values are truncated, never rounded up)
		if value >= 1000 and tier < #SUFFIXES - 1 then
			tier += 1
			value /= 1000
		elseif value < 1 and tier > 1 then
			tier -= 1
			value *= 1000
		end
		local formatted: string
		if value >= 100 then
			formatted = string.format("%.0f", math.floor(value + 1e-6))
		elseif value >= 10 then
			formatted = trim(string.format("%.1f", math.floor(value * 10 + 1e-6) / 10))
		else
			formatted = trim(string.format("%.2f", math.floor(value * 100 + 1e-6) / 100))
		end
		text = formatted .. SUFFIXES[tier + 1]
	end
	return if negative then "-" .. text else text
end

function Format.Cash(n: number): string
	return "$" .. Format.Number(n)
end

function Format.PerSecond(n: number): string
	return "$" .. Format.Number(n) .. "/s"
end

-- 125 -> "2:05", 3725 -> "1:02:05"
function Format.Clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- 3725 -> "1h 02m", 125 -> "2m 05s", 9 -> "9s"
function Format.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

function Format.Multiplier(n: number): string
	return "x" .. trim(string.format("%.2f", n))
end

return Format
