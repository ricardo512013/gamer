--!strict
--[[
	HUD (STUB — área "cliente") — toda a UI (GDD §6): botão PUXAR, Vento/Carretel, cartas do varal, faixa,
	escudo, emotes, botões de topo, banner de evento, barra de duelo, tela cheia, painel do Bar,
	Correio da Laje, Renascer, Loja de passes, popup Offline, onboarding. ScreenGui + Frame/TextLabel/TextButton,
	UICorner/UIStroke 3 px, sem imagens. Strings via HUD.t (Config.str; en se LocalizationService começa com "en").
	Os callbacks on* são definidos por init.client, que fala com os remotes. Requer Config (e KiteRenderer se quiser).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HUD = {}

HUD.onPull = nil :: ((down: boolean) -> ())?
HUD.onSelect = nil :: ((id: number) -> ())?
HUD.onBuy = nil :: ((kind: string, slot: number?) -> ())?
HUD.onClaim = nil :: ((which: string) -> ())? -- "Streak" | "Cortes" | "Pegas"
HUD.onRebirth = nil :: (() -> ())?
HUD.onEmote = nil :: ((id: number) -> ())?

function HUD.start(): ()
	warn("[HUD] stub")
end

-- Patch de State (§7.3): só os campos presentes mudam.
function HUD.applyState(patch: { [string]: any }): ()
	warn("[HUD] stub applyState")
end

-- kinds em §7.3 (Cortou, Voou, Pegou, PegaramSua, Voada, Duelo, Sorte, Dourada, Arvore, VendaAuto, Offline,
-- Streak, Evento, Renasceu, Boost, Erro).
function HUD.toast(kind: string, args: { [string]: any }): ()
	warn("[HUD] stub toast", kind)
end

-- {seed, restockAt, slots = {StockSlot & {bought}}}
function HUD.setStock(stock: { [string]: any }): ()
	warn("[HUD] stub setStock")
end

function HUD.setDuel(active: boolean, endsAt: number, opponent: string?): ()
	warn("[HUD] stub setDuel", active)
end

function HUD.setPressed(down: boolean): ()
	warn("[HUD] stub setPressed", down)
end

function HUD.onboardingStep(n: number): ()
	warn("[HUD] stub onboardingStep", n)
end

function HUD.t(key: string, vars: { [string]: any }?): string
	return Config.str(key, "pt-BR", vars)
end

return HUD
