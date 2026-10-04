--!strict
-- STEAL A PLANET - every tunable setting of the game lives in this file.
-- Monetization IDs start at 0 (disabled). Create the Game Passes / Developer
-- Products in the Creator Dashboard and paste their IDs here (see README).

export type PassInfo = {
	Id: number,
	Name: string,
	Description: string,
	Icon: string,
	SuggestedPrice: number,
	Order: number,
}

export type ProductInfo = {
	Id: number,
	Name: string,
	Description: string,
	Icon: string,
	Kind: string, -- "Cash" | "ServerLuck" | "Event" | "Lock" | "BuyPlanet"
	SuggestedPrice: number,
	Order: number,
	Seconds: number?, -- Cash: how many seconds of the buyer's income
	Minimum: number?, -- Cash: minimum amount granted
	Rarity: string?, -- BuyPlanet: rarity of the planet
	Hidden: boolean?, -- not listed in the store (bought from the belt)
}

export type ToolInfo = {
	Name: string,
	Description: string,
	Icon: string,
	Price: number,
	Rebirth: number,
	Order: number,
	Color: Color3,
	Cooldown: number?,
	Range: number?,
	StunTime: number?,
	SpeedBonus: number?,
	JumpHeight: number?,
	FreezeTime: number?,
	Duration: number?,
}

export type Reward = {
	Cash: number?, -- fixed cash
	Seconds: number?, -- cash = income per second * Seconds
	Minimum: number?, -- minimum cash when using Seconds
	Rarity: string?, -- random planet of this rarity
	Planet: string?, -- specific planet id
	Mutation: string?, -- mutation for Planet
}

export type PlaytimeReward = {
	Minutes: number,
	Cash: number?,
	Seconds: number?,
	Minimum: number?,
	Rarity: string?,
	Planet: string?,
	Mutation: string?,
}

export type EventInfo = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Color: Color3,
	LuckMult: number?,
	IncomeMult: number?,
	MutationMult: { [string]: number }?,
}

local Config = {}

Config.GameName = "Steal a Planet"
Config.DataStoreName = "StealAPlanet_Data_v1"
Config.LeaderboardPrefix = "StealAPlanet_LB_v1_"
Config.MaxPlayers = 8 -- there are 8 bases. Set Game Settings > Places > Max Players = 8.

-- Economy -------------------------------------------------------------------
Config.StartingCash = 100
Config.MaxSlots = 20
Config.BaseSlots = 10
Config.SlotsPerRebirth = 2
Config.SellRatio = 0.5
Config.RebirthBaseCost = 500_000
Config.RebirthCostGrowth = 8
Config.RebirthMultiplierStep = 0.5
Config.OfflineCapHours = 3
Config.OfflineCapHoursPass = 12
Config.AutoCollectInterval = 2
Config.MaxPendingPlanets = 30

-- Base lock -----------------------------------------------------------------
Config.LockDuration = 60
Config.LockPerRebirth = 5
Config.JoinLockDuration = 30

-- Stealing ------------------------------------------------------------------
Config.StealHoldTime = 1.2
Config.SellHoldTime = 1.5
Config.StealTimeout = 90
Config.StealCooldown = 3
Config.CarrySpeedMult = 0.7

-- Character -----------------------------------------------------------------
Config.BaseWalkSpeed = 18
Config.BaseJumpHeight = 7.5
Config.SpeedPassBonus = 8
Config.Gravity = 170

-- Cosmic belt (the conveyor where planets are sold) ------------------------
Config.Belt = {
	SpawnInterval = 2.0,
	Speed = 7,
	BuyDistance = 14,
	AnnounceRarityOrder = 6, -- announce to the server when a Mythic or better spawns
}

-- Cosmic events (server-wide weather) --------------------------------------
Config.EventFirstDelay = 180
Config.EventInterval = 420
Config.EventDuration = 150

Config.Events = {
	{
		Id = "MeteorShower",
		Name = "Meteor Shower",
		Icon = "☄️",
		Description = "Mutation chance x3!",
		Color = Color3.fromRGB(255, 150, 70),
		MutationMult = { Gold = 3, Diamond = 3, Rainbow = 3, Galaxy = 3 },
	},
	{
		Id = "SolarFlare",
		Name = "Solar Flare",
		Icon = "☀️",
		Description = "Gold planets x8!",
		Color = Color3.fromRGB(255, 200, 60),
		MutationMult = { Gold = 8 },
	},
	{
		Id = "Supernova",
		Name = "Supernova",
		Icon = "💥",
		Description = "Rare planet luck x3!",
		Color = Color3.fromRGB(255, 90, 140),
		LuckMult = 3,
	},
	{
		Id = "BlackHole",
		Name = "Black Hole",
		Icon = "🕳️",
		Description = "All income x2!",
		Color = Color3.fromRGB(140, 90, 255),
		IncomeMult = 2,
	},
	{
		Id = "GalaxyNight",
		Name = "Galaxy Night",
		Icon = "🌌",
		Description = "Galaxy x10 & Rainbow x5 mutations!",
		Color = Color3.fromRGB(110, 70, 255),
		MutationMult = { Galaxy = 10, Rainbow = 5 },
	},
} :: { EventInfo }

Config.ServerLuck = {
	Multiplier = 2,
	DurationPerPurchase = 15 * 60,
	MaxDuration = 3 * 60 * 60,
}

-- Social bonuses ------------------------------------------------------------
Config.FriendBonusPer = 0.1
Config.FriendBonusMax = 0.5
Config.GroupId = 0 -- your Roblox group id (0 = disabled)
Config.GroupBonus = 0.1
Config.GroupReward = { Rarity = "Rare", Cash = 2_500 } :: Reward
Config.FavoritePromptMinutes = 8

-- Admins (user ids). The game owner (or group owner rank) is always admin.
Config.Admins = {} :: { number }
Config.AdminGroupRank = 254

-- Data ----------------------------------------------------------------------
Config.AutosaveInterval = 90
Config.SessionLockTimeout = 300

-- Tools ---------------------------------------------------------------------
Config.Tools = {
	Bat = {
		Name = "Space Bat",
		Description = "Smack thieves to make them drop your planet!",
		Icon = "🏏",
		Price = 0,
		Rebirth = 0,
		Order = 1,
		Color = Color3.fromRGB(150, 100, 60),
		Cooldown = 0.9,
		Range = 9,
		StunTime = 1.4,
	},
	SpeedCoil = {
		Name = "Speed Coil",
		Description = "+10 walk speed while held.",
		Icon = "⚡",
		Price = 2_500,
		Rebirth = 0,
		Order = 2,
		Color = Color3.fromRGB(70, 170, 255),
		SpeedBonus = 10,
	},
	GravityCoil = {
		Name = "Gravity Coil",
		Description = "Jump twice as high while held.",
		Icon = "🌀",
		Price = 12_000,
		Rebirth = 0,
		Order = 3,
		Color = Color3.fromRGB(170, 90, 255),
		JumpHeight = 15,
	},
	FreezeRay = {
		Name = "Freeze Ray",
		Description = "Freeze a player for 3s. They drop what they carry!",
		Icon = "❄️",
		Price = 250_000,
		Rebirth = 1,
		Order = 4,
		Color = Color3.fromRGB(120, 230, 255),
		Cooldown = 12,
		Range = 45,
		FreezeTime = 3,
	},
	Cloak = {
		Name = "Invisibility Cloak",
		Description = "Turn invisible for 8 seconds.",
		Icon = "👻",
		Price = 5_000_000,
		Rebirth = 2,
		Order = 5,
		Color = Color3.fromRGB(110, 80, 160),
		Cooldown = 35,
		Duration = 8,
	},
} :: { [string]: ToolInfo }

-- Monetization --------------------------------------------------------------
-- When an Id is 0 the item is disabled in live servers. In Studio, with
-- TestPurchasesInStudio = true, clicking it grants it for free so you can test.
Config.TestPurchasesInStudio = true

Config.GamePasses = {
	VIP = {
		Id = 0,
		Name = "VIP",
		Description = "x1.5 cash forever, [VIP] chat tag.",
		Icon = "👑",
		SuggestedPrice = 299,
		Order = 1,
	},
	DoubleCash = {
		Id = 0,
		Name = "2x Cash",
		Description = "Every planet earns double, forever.",
		Icon = "💰",
		SuggestedPrice = 249,
		Order = 2,
	},
	AutoCollect = {
		Id = 0,
		Name = "Auto Collect",
		Description = "Cash is collected for you automatically.",
		Icon = "🧲",
		SuggestedPrice = 149,
		Order = 3,
	},
	SuperSpeed = {
		Id = 0,
		Name = "Super Speed",
		Description = "+8 walk speed forever. Outrun everyone!",
		Icon = "👟",
		SuggestedPrice = 99,
		Order = 4,
	},
	DoubleLock = {
		Id = 0,
		Name = "Double Lock Time",
		Description = "Your base stays locked twice as long.",
		Icon = "🔒",
		SuggestedPrice = 129,
		Order = 5,
	},
	OfflineEarnings = {
		Id = 0,
		Name = "12h Offline Earnings",
		Description = "Earn for up to 12 hours while offline (normal: 3h).",
		Icon = "🌙",
		SuggestedPrice = 99,
		Order = 6,
	},
} :: { [string]: PassInfo }

Config.Products = {
	CashSmall = {
		Id = 0,
		Name = "Pouch of Stardust",
		Description = "10 minutes of your income.",
		Icon = "💵",
		Kind = "Cash",
		SuggestedPrice = 19,
		Order = 1,
		Seconds = 600,
		Minimum = 10_000,
	},
	CashMedium = {
		Id = 0,
		Name = "Bag of Stardust",
		Description = "1 hour of your income.",
		Icon = "💰",
		Kind = "Cash",
		SuggestedPrice = 79,
		Order = 2,
		Seconds = 3600,
		Minimum = 100_000,
	},
	CashLarge = {
		Id = 0,
		Name = "Chest of Stardust",
		Description = "6 hours of your income.",
		Icon = "🧰",
		Kind = "Cash",
		SuggestedPrice = 249,
		Order = 3,
		Seconds = 6 * 3600,
		Minimum = 1_000_000,
	},
	CashHuge = {
		Id = 0,
		Name = "Vault of Stardust",
		Description = "24 hours of your income. BEST VALUE!",
		Icon = "🏦",
		Kind = "Cash",
		SuggestedPrice = 699,
		Order = 4,
		Seconds = 24 * 3600,
		Minimum = 10_000_000,
	},
	ServerLuck = {
		Id = 0,
		Name = "Server Luck x2",
		Description = "x2 rare planet luck for EVERYONE for 15 min (stacks).",
		Icon = "🍀",
		Kind = "ServerLuck",
		SuggestedPrice = 99,
		Order = 5,
	},
	CosmicEvent = {
		Id = 0,
		Name = "Start Cosmic Event",
		Description = "Start a random cosmic event right now!",
		Icon = "🌠",
		Kind = "Event",
		SuggestedPrice = 149,
		Order = 6,
	},
	RemoteLock = {
		Id = 0,
		Name = "Remote Lock",
		Description = "Lock your base from anywhere, right now.",
		Icon = "🛡️",
		Kind = "Lock",
		SuggestedPrice = 25,
		Order = 7,
	},
	BuyLegendary = {
		Id = 0,
		Name = "Instant Legendary",
		Description = "Buy a Legendary planet from the belt.",
		Icon = "🌟",
		Kind = "BuyPlanet",
		SuggestedPrice = 79,
		Order = 8,
		Rarity = "Legendary",
		Hidden = true,
	},
	BuyMythic = {
		Id = 0,
		Name = "Instant Mythic",
		Description = "Buy a Mythic planet from the belt.",
		Icon = "🔥",
		Kind = "BuyPlanet",
		SuggestedPrice = 199,
		Order = 9,
		Rarity = "Mythic",
		Hidden = true,
	},
	BuyCosmic = {
		Id = 0,
		Name = "Instant Cosmic",
		Description = "Buy a Cosmic planet from the belt.",
		Icon = "🌌",
		Kind = "BuyPlanet",
		SuggestedPrice = 499,
		Order = 10,
		Rarity = "Cosmic",
		Hidden = true,
	},
	BuySecret = {
		Id = 0,
		Name = "Instant Secret",
		Description = "Buy a Secret planet from the belt.",
		Icon = "❓",
		Kind = "BuyPlanet",
		SuggestedPrice = 999,
		Order = 11,
		Rarity = "Secret",
		Hidden = true,
	},
} :: { [string]: ProductInfo }

-- Rewards -------------------------------------------------------------------
Config.DailyCooldown = 20 * 3600
Config.DailyStreakWindow = 48 * 3600
Config.DailyRewards = {
	{ Seconds = 120, Minimum = 500 },
	{ Seconds = 240, Minimum = 1_500 },
	{ Rarity = "Rare" },
	{ Seconds = 600, Minimum = 8_000 },
	{ Rarity = "Epic" },
	{ Seconds = 1_800, Minimum = 50_000 },
	{ Rarity = "Legendary" },
} :: { Reward }

Config.PlaytimeRewards = {
	{ Minutes = 2, Seconds = 90, Minimum = 300 },
	{ Minutes = 5, Rarity = "Rare" },
	{ Minutes = 10, Seconds = 300, Minimum = 2_500 },
	{ Minutes = 15, Rarity = "Epic" },
	{ Minutes = 25, Seconds = 900, Minimum = 25_000 },
	{ Minutes = 40, Rarity = "Legendary" },
	{ Minutes = 60, Seconds = 3600, Minimum = 250_000 },
} :: { PlaytimeReward }

-- Codes (players type them in the Codes menu). Keys must be UPPERCASE.
Config.Codes = {
	LAUNCH = { Cash = 1_000 },
	PLANETS = { Cash = 5_000 },
	GOLDMARS = { Planet = "Mars", Mutation = "Gold" },
	BLACKHOLE = { Rarity = "Epic" },
} :: { [string]: Reward }

-- Sounds (rbxasset:// files ship with every Roblox client). Replace with your
-- own uploaded "rbxassetid://..." ids if you want.
Config.Sounds = {
	Click = "rbxasset://sounds/button.wav",
	Cash = "rbxasset://sounds/electronicpingshort.wav",
	Swing = "rbxasset://sounds/swordslash.wav",
	Alarm = "rbxasset://sounds/electronicpingshort.wav",
	Music = "", -- e.g. "rbxassetid://1234567890" (leave empty for no music)
}

return Config
