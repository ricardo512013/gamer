# Pega Pipa / Catch a Kite

Jogo Roblox (Party & Casual → Childhood Game) em Luau `--!strict`, projeto Rojo. Empine pipas na sua laje,
deixe o Vento render no varal, suba até o Céu Aberto para cruzar linha com os outros — e quando uma pipa é
cortada ela cai no campinho e **é de quem pegar primeiro**. O design completo está no GDD (`design/GDD.md`
do workflow); toda constante vive em `src/shared/Config.luau`.

## Estrutura

```
PegaPipa/
├─ default.project.json            Rojo: Shared, Services, Client, Workspace/Lighting/HttpService
├─ README.md
└─ src/
   ├─ shared/Config.luau            → ReplicatedStorage/Shared/Config   (constantes, tipos, template, strings)
   ├─ shared/Remotes.luau           → ReplicatedStorage/Shared/Remotes  (nomes, init/get, limiter, isFinite/isInt)
   ├─ server/init.server.luau       → ServerScriptService/Services      (bootstrap; os módulos abaixo são filhos)
   ├─ server/ProfileStore.luau      vendorizado (MAD STUDIO), não editar
   ├─ server/DataService.luau       perfis, laje, leaderstats, offline, Vento/Carretel, State/Toast
   ├─ server/MapGen.luau            Morro do Vento (terreno, 12 lajes, Bar, Poste, Árvore)
   ├─ server/KiteService.luau       pipa no ar, faixas, deriva, selvagens, duelo, queda, pega, árvore
   ├─ server/ShopService.luau       Bar do Vento, Linha, vagas, streak, dailies, renascer, Kit
   ├─ server/EventService.luau      eventos de servidor, Festival, boosts
   ├─ server/MonetizationService.luau  passes, produtos, ProcessReceipt idempotente
   ├─ server/Leaderboard.luau       ranking semanal (OrderedDataStore) e Poste
   ├─ client/init.client.luau       → StarterPlayer/StarterPlayerScripts/Client (LocalScript; filhos abaixo)
   ├─ client/KiteRenderer.luau      pipas, linhas, varais, marcadores, efeitos (só Parts e Tweens)
   └─ client/HUD.luau               UI mobile-first (ScreenGui, sem imagens)
```

## Regras de dependência (sem ciclos de require)

`Config`/`Remotes` ← todos · `MapGen` ← só Config · `DataService` ← Config, Remotes, ProfileStore, MapGen ·
`Leaderboard` ← DataService · `KiteService` ← DataService, MapGen, Leaderboard · `ShopService`/`EventService`
← DataService, KiteService · `MonetizationService` ← DataService, KiteService, ShopService, EventService.
O que o DataService precisa "de cima" entra por `DataService.hooks` (preenchido nos `start()`); o que o
KiteService precisa de cima entra por `KiteService.onDuelEnd/onCatch` e pelos atributos de `workspace.World`.

## Verificação e build

```
check.sh /caminho/para/PegaPipa            # rojo sourcemap + luau-lsp analyze (deve terminar com exit=0)
rojo build default.project.json -o PegaPipa.rbxlx
```

No Studio sem "Studio Access to API Services" o DataService usa `ProfileStore.Mock` (nada é salvo).
`Lighting.LightingStyle = Soft` deve ser marcado no Studio (o Rojo 7.4.4 não conhece a propriedade).
