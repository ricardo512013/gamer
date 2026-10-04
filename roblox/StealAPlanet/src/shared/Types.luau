--!strict
-- Shared data shapes (saved player data and the snapshot synced to the client).

export type SlotData = {
	Id: string,
	Mut: string,
	Acc: number,
}

export type PendingPlanet = {
	Id: string,
	Mut: string,
}

export type PlayerData = {
	Version: number,
	Cash: number,
	TotalEarned: number,
	Rebirths: number,
	Steals: number,
	TimesStolen: number,
	Slots: { [string]: SlotData },
	Pending: { PendingPlanet },
	Tools: { [string]: boolean },
	Index: { [string]: boolean },
	Codes: { [string]: boolean },
	DailyStreak: number,
	DailyLast: number,
	LastOnline: number,
	FirstJoin: number,
	PlayTime: number,
	GroupClaimed: boolean,
	Tutorial: number,
	Receipts: { string },
	SessionJob: string?,
	SessionTime: number?,
}

export type Snapshot = {
	Cash: number,
	CashPerSec: number,
	TotalEarned: number,
	Rebirths: number,
	Steals: number,
	Multiplier: number,
	SlotsUnlocked: number,
	SlotsUsed: number,
	Pending: number,
	Tools: { [string]: boolean },
	Index: { [string]: boolean }?,
	IndexVersion: number,
	RebirthCost: number,
	DailyStreak: number,
	DailyReady: boolean,
	DailyNextAt: number,
	DailyNextDay: number,
	PlaytimeStart: number,
	PlaytimeClaimed: { [string]: boolean },
	Tutorial: number,
	GroupClaimed: boolean,
	HomePosition: Vector3?,
}

return {}
