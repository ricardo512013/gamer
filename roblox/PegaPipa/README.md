# Pega Pipa / Catch a Kite

Jogo Roblox (Party & Casual → Childhood Game) em Luau `--!strict`, projeto Rojo, sem nenhum asset externo
(só Parts, Terrain, SurfaceGui/BillboardGui e TextLabels). O design completo está em [`docs/GDD.md`](docs/GDD.md).

## O que é o jogo

Empine pipas na sua laje do **Morro do Vento**, deixe o Vento render no varal, suba até o **Céu Aberto** para
cruzar linha com os outros jogadores — e quando uma pipa é cortada ela cai no campinho e **é de quem pegar
primeiro**. Com o Vento você compra pipas no Bar do Vento, Linha de Vento e vagas no varal; eventos de servidor,
Festival do Morro aos sábados, streak diário, ranking semanal no Poste e o Renascer ("Nova Temporada") fecham o laço.

**Gramática do botão (um só, PUXAR):** *"Toca pra subir e brigar, segura pra puxar."*
Toque (< 250 ms) sobe uma faixa; toque com uma pipa inimiga a ≤ 25 studs (faixa 3–4) vira **rabeio → duelo de 2 s**;
segurar puxa a linha (desce uma faixa a cada 0,5 s); segurar durante o duelo vale +3 pontos ("SEGURA!").

## Como abrir no Roblox Studio

**Opção A — arquivo pronto.** Roblox Studio → *Arquivo > Abrir do arquivo* (File > Open from File) →
`build/PegaPipa.rbxlx`. Aperte *Play*.

**Opção B — Rojo (edite o código no editor e sincronize).** Instale o [Rojo 7.4.4](https://rojo.space)
(`rokit install` lê o `rokit.toml`) e o plugin do Rojo no Studio:

```
rojo serve default.project.json            # no Studio: Plugins > Rojo > Connect
rojo build default.project.json -o build/PegaPipa.rbxlx   # gera o arquivo de lugar
```

## O que ligar no Studio (uma vez, em *Game Settings*)

| Onde | O quê | Por quê |
|---|---|---|
| *Security* | **Enable Studio Access to API Services** = ligado | DataStore (ProfileStore) e OrderedDataStore do ranking. Sem isso o jogo usa `ProfileStore.Mock` e avisa no Output: nada é salvo. |
| *Basic Info / Places* | **Max players** = `Config.MAX_PLAYERS` (12) e **Reserved server slots** = 2 | GDD §1: 12 jogadores, 2 vagas reservadas para amigos (enche em 10). |
| *Avatar* | padrão (R15, sem itens forçados) | O jogo não usa animações nem acessórios próprios. |
| *Communication* / chat | pode ficar **desligado** | GDD §5.8: não há chat — 4 emotes-balão (Pega! / Valeu! / Cuidado! / Bora!), banners automáticos e vibração. Se preferir manter o chat, nada quebra. |
| *Permissions* | Access Control: **Secure within universe only** (quando publicar) | GDD §5.6 (anti-exploit). |
| *Lighting* (Explorer) | `LightingStyle = Soft` | O `MapGen` tenta aplicar em runtime (`pcall`); o Rojo 7.4.4 não conhece a propriedade, então marque no Studio se quiser vê-la no editor. |

Classificação: público 16+ na avaliação; conteúdo compatível com o label *Minimal* (sem gore, sem cerol, sem fios).
Na loja use a descrição do GDD §1 ("Pipa voada é de quem pega." …) e nunca as palavras *combat/arena/torneio*.

## Passes e produtos (IDs)

1. No Creator Hub crie os 4 passes e os 4 produtos de desenvolvedor da tabela do GDD §5.7 (Listed, Managed Pricing).
2. Cole os IDs em `src/shared/Config.luau`, tabela `Config.IDS`:

```lua
Config.IDS = {
	PASS_VENTO_DOBRO = 0,   -- pass "Vento em Dobro" (249 R$)
	PASS_CARRETEL_AUTO = 0, -- pass "Carretel Automático" (179)
	PASS_VIP = 0,           -- pass "VIP da Laje" (449)
	PASS_KIT = 0,           -- pass "Kit Pipeiro" (299)
	PROD_RAJADA = 0,        -- produto "Rajada no Servidor" (149)
	PROD_VENTO_FORTE = 0,   -- produto "Vento Forte" (99)
	PROD_RESGATE = 0,       -- produto "Resgatar da Árvore" (45)
	PROD_GUARDAR_STREAK = 0,-- produto "Guardar Streak" (39)
}
```

Enquanto um id é `0` o item aparece como "Em breve" na Loja, o passe conta como não possuído e o produto não tem
handler (o `MonetizationService` avisa no Output). Os preços mostrados na Loja vêm de `GetProductInfoAsync`.
Badges: `Config.BADGES` (ids 0 = ignorados). `ProcessReceipt` é idempotente: o `PurchaseId` fica em
`profile.Data.Purchases` e só é confirmado depois de salvo.

## Estrutura de pastas

```
PegaPipa/
├─ default.project.json          Rojo: Shared, Services, Client, Workspace/Lighting/HttpService
├─ rokit.toml · stylua.toml · selene.toml   ferramentas (Rojo 7.4.4, formatação, lint)
├─ README.md
├─ build/PegaPipa.rbxlx          lugar pronto para abrir no Studio
├─ docs/GDD.md · veredito.md · pesquisa.md   design, revisão do design e pesquisa de mercado
└─ src/
   ├─ shared/Config.luau          → ReplicatedStorage/Shared/Config   TODAS as constantes (GDD §7.5), tipos do perfil,
   │                                template, strings pt-BR/en (Config.str) — nenhum número vive fora daqui
   ├─ shared/Remotes.luau         → ReplicatedStorage/Shared/Remotes  nomes dos RemoteEvents, init (servidor) /
   │                                get (cliente), limiter token-bucket, isFinite/isInt
   ├─ server/init.server.luau     → ServerScriptService/Services      bootstrap (Script); os módulos abaixo são filhos
   ├─ server/ProfileStore.luau    vendorizado (MAD STUDIO) — não editar
   ├─ server/MapGen.luau          Morro do Vento: terreno, campinho, Bar, Poste, Árvore, 12 lajes, enfeites, luz
   ├─ server/DataService.luau     perfis (ProfileStore), laje do jogador, leaderstats, renda offline,
   │                              Vento/Carretel (única porta de entrada/saída de Vento), remotes State/Toast
   ├─ server/KiteService.luau     pipa no ar, faixas, botão PUXAR, deriva, selvagens, rabeio/duelo, queda, pega,
   │                              árvore, escudo de novato, anti-AFK, tutorial (Pipa de Treino)
   ├─ server/ShopService.luau     Bar do Vento (estoque de 5 min), Linha, vagas, streak, dailies, renascer, Kit, estimação
   ├─ server/EventService.luau    Rajada / Chuva de Pipas / Vento Dourado / Virou o Vento, Festival do Morro, boosts pagos
   ├─ server/MonetizationService.luau  passes (cache por sessão) e produtos (ProcessReceipt idempotente)
   ├─ server/Leaderboard.luau     ranking semanal (OrderedDataStore Rei_/Tesoura_), placa do Poste, RabiolaRank
   ├─ client/init.client.luau     → StarterPlayer/StarterPlayerScripts/Client (LocalScript; módulos abaixo são filhos)
   │                              input (botão, Espaço, ButtonA) → Pull; callbacks do HUD → remotes; State/Toast/ShopStock
   ├─ client/KiteRenderer.luau    pipas (uma forma por raridade), linha, rabiola, varal em miniatura, marcador Neon,
   │                              faíscas do duelo, setas do onboarding, burst da coleta, balões de emote
   └─ client/HUD.luau             UI mobile-first em código: PUXAR, Vento/Carretel, cartas do varal, faixa, escudo,
                                  emotes, Bar, Correio da Laje, Renascer, Loja, Offline, banner de evento, toasts
```

**Ordem de boot** (`init.server.luau`): `Remotes.init` → `MapGen` → `DataService` → `MonetizationService` →
`KiteService` → `ShopService` → `EventService` → `Leaderboard`. Cada `start()` roda em `pcall`.

**Sem ciclos de require.** `Config`/`Remotes` ← todos · `MapGen` ← só Config · `DataService` ← Config, Remotes,
ProfileStore (MapGen só dentro das funções) · `Leaderboard` ← DataService · `KiteService` ← DataService, MapGen ·
`ShopService`/`EventService` ← DataService, KiteService · `MonetizationService` ← DataService, KiteService,
ShopService, EventService. O que o DataService precisa "de cima" (faixa da pipa, multiplicadores, passes, ranking)
entra por `DataService.hooks`, preenchido nos `start()`; o que o KiteService precisa de cima entra por
`KiteService.onDuelEnd/onCatch` e pelos atributos de `workspace.World`.

**Instâncias criadas em runtime:** `ReplicatedStorage/Remotes` (RemoteEvents), `workspace/Map` (mapa inteiro),
`workspace/KiteStates/<id>` (uma `Configuration` com tag `Kite` por pipa no ar — o cliente só interpola),
`workspace/World` (`Configuration`: WindSign, EventName/Phase/EndsAt, Festival, RestockAt, Boost*).

## Ajustar a economia (tudo em `src/shared/Config.luau`)

| Quero mudar… | Chaves |
|---|---|
| Renda por pipa | `BASE_RATE` (V/s por raridade), `GOLDEN_MULT`, `FAIXA_MULT` (faixa 0–4), `VARAL_MULT`, `FRIEND_BONUS`, `REBIRTH_BONUS` |
| Carretel e offline | `CARRETEL_CAP_SECONDS` (15 min de renda), `COLLECT_DIST`, `OFFLINE_MULT`, `OFFLINE_CAP`, `OFFLINE_CAP_VIP`, `OFFLINE_MIN` |
| Bar do Vento | `SHOP_TABLE` / `SHOP_SPECIAL_TABLE` (chances, somam 100), `SHOP_PRICE`, `SHOP_SLOTS_NORMAL/SPECIAL`, `RESTOCK_SECONDS`, `SHOP_DIST`, `SHOP_OPEN_DIST` |
| Linha e vagas | `Config.linhaPrice(n)` (300 × 2^(n−2)), `LINHA_MAX`, `LINHA_NAMES`, `VAGA_PRICE`, `VAGAS_START`, `VAGAS_MAX` |
| Venda automática | `AUTO_SELL_MULT` (30 × V/s base) |
| Selvagens | `WILD_TABLE`, `WILD_TABLE_RAJADA`, `WILD_INTERVAL`, `WILD_MAX`, `WILD_SPEED`, `WILD_RING_R`, `WILD_OMEGA`, `WILD_POINTS` |
| Duelo e botão | `TAP_MAX`, `TAP_COOLDOWN`, `HOLD_DESCEND_EVERY`, `RABEIO_RANGE`, `DUEL_TIME`, `HOLD_BONUS`, `DUEL_RANDOM`, `POST_DUEL_IMMUNITY` |
| Queda / pega / árvore | `FALL_TIME`, `GROUND_TIME`, `CATCH_RADIUS`, `TREE_CATCH_RADIUS`, `TREE_TIME`, `TELEPORT_JUMP`, `TELEPORT_PENALTY` |
| Novato e tutorial | `NOVATO_SECONDS` (escudo de 20 min), `TUTORIAL_AT`, `TUTORIAL_WILD_POINTS`, `AFK_SECONDS`, `AFK_DROP_EVERY` |
| Eventos | `EVENT_INTERVAL`, `FIRST_EVENT_AT`, `EVENT_WARN`, `EVENTS` (chances somam 100), `RAJADA`, `RAIN_COUNT`, `FESTIVAL`, `BOOST_SECONDS`, `BOOST_RAJADA`, `BOOST_VENTO_MULT` |
| Streak e dailies | `STREAK` (D1–D7), `STREAK_KITE`, `STREAK_REPEAT_MULT`, `STREAK_CAP_DAY`, `DAILY` |
| Renascer | `REBIRTH_BASE`, `REBIRTH_GROWTH`, `REBIRTH_MAX`, `REBIRTH_NEED_RARITY`, `PETS_KEPT`, `PETS_KEPT_VIP` |
| Kit Pipeiro / passes | `KIT`, `PASS_VENTO_DOBRO_MULT`, `IDS` |
| Rede / anti-exploit | `RATE` (fichas por segundo e rajada de cada remote), `SYNC_HZ` |
| Textos | `STRINGS.ptBR` / `STRINGS.en` (`Config.str(chave, locale, vars)`) |

As medidas de geometria do mapa que o GDD não põe no Config ficam na tabela `GEO` no topo de `MapGen.luau`;
os números só do cliente (tamanhos, tempos de tween, distâncias de render) em `Config.CLIENT`.

## Como testar

**Play Solo** (um jogador) testa quase tudo; **Test > Clients and Servers** (*Local Server*, 2–3 players) é
necessário para duelo PvP, pega por terceiro, emotes para o outro cliente e ranking. Sem acesso à API o Output
mostra `[DataService] API do DataStore indisponível no Studio: usando ProfileStore.Mock` — o jogo roda inteiro,
só não salva (e o Mock some ao parar o teste).

Comandos úteis no *Command Bar* do **servidor** (`p = game.Players:GetPlayers()[1]`):

```lua
local S = game.ServerScriptService.Services
local DS, KS, ES = require(S.DataService), require(S.KiteService), require(S.EventService)
DS.addVento(p, 250000, "Produto")             -- Vento para testar Bar/Linha/vagas/Renascer
DS.addKite(p, "Morcegao", 4, 1)               -- uma Épica no varal (Renascer)
DS.get(p).Data.Streak.LastClaimDay -= 1       -- "avançar 1 dia" do streak (−2 = pular 2 dias)
ES.force("Chuva")                             -- Rajada | Chuva | Dourado | Virou
KS.spawnWild(3)                               -- uma selvagem Rara agora
```

Festival do Morro fora do sábado 15h BRT: mude temporariamente `Config.FESTIVAL.wday/hourUTC` para o dia/hora atual
em UTC (`os.date("!*t")`). Renda offline: com API ligada, pare o jogo, espere ≥ `OFFLINE_MIN` (60 s) e entre de novo —
o popup "Enquanto você saiu…" mostra `Σ base × 0,25 × segundos` (cap 8 h; 12 h VIP).

**Checklist de aceitação (GDD §9, resumo — a lista completa com os números está em `docs/GDD.md`):**

1. Mapa determinístico: dois Play seguidos dão o mesmo número de Parts em `workspace.Map`; `Laje_4` em (0, 19, 120).
2. Spawn na própria laje; atributo `Laje` distinto por jogador; `OwnerId` volta a 0 ao sair.
3. 4 toques → `Faixa = 4` em ≤ 4 s; HUD mostra "×2,5" e fica laranja na faixa 3.
4. Segurar 2 s da faixa 4 leva a 0; soltar após 0,6 s para na 3.
5. Jornal na faixa 2 por 60 s → Carretel +60; para de subir em `900 × Rate`.
6. Prompt do carretel coleta; `Collect` a 30 studs é ignorado sem erro.
7. Aos 40 s o novato vê a Pipa de Treino ("TOCA pra brigar!"), vence sempre, a pipa cai; funil 1–5 logado.
8. Duelo PvP: A e B na faixa 3 a ≤ 25 studs; B segurando (L1) × A sem segurar (L1) → B vence 10/10.
9. Empate L2 × L2 segurando → ~50 %; "SORTE!" quando os pontos empatam.
10. Pipa cortada chega ao chão em 10 s dentro do campinho; coluna Neon visível; quem encosta primeiro recebe; dono vê "C pegou a sua Arraia"; `Dailies.Pegas = 1`.
11. O próprio dono pode pegar de volta.
12. 20 s sem pega → `TREE_TOP`; subir o Truss e chegar a ≤ 6 studs pega; 180 s → volta ao varal (dono online) ou some.
13. Novato (`PlayTime < 1.200`) perde → pipa volta à laje; Jornal volta sempre e nunca é vendida.
14. Varal 3/3 + compra → a de menor valor é vendida por 30 × base; nova mais barata → a nova é vendida.
15. Bar: `RestockAt` a cada 300 s; mesmo estoque em todo servidor; compra a 30 studs e 2ª compra do slot negadas; L2 = 300, 4ª vaga = 2.000.
16. Offline: 3 h com Estrela + Comum = 13.500; 20 h usa 8 h (36.000); VIP 12 h.
17. 1º evento aos 240 s; distribuição 35/25/20/20; Virou inverte `WindSign` após 20 s; Chuva derruba 8 que somem em 20 s; Dourado marca 1 pipa (ou "passou em branco").
18. Streak: D1 300 → D2 600; 2 dias sem resgatar → D1; D5 Arraia; D7 Pipa Raio cor 10; D8 = 600.
19. Renascer: 250.000 + 1 Épica → `Temporadas = 1`, Vento 0, Linha/vagas/Jornal/estimação mantidos, Épica vira `Temporada` cor 101; custo seguinte 750.000.
20. `ProcessReceipt` 2× com o mesmo `PurchaseId` aplica 1×; Vento em Dobro dobra `Rate`; Kit 1× com Linha ≥ 3.
21. `Pull` a 20/s é limitado sem kick; `Buy("Kite", "abc")` e `SelectKite(999)` ignorados; teleporte de 100 studs bloqueia a pega por 3 s.
22. Após 60 s o Poste lista o top 10 de Vento e de Cortes PvP; `leaderstats` = Vento/Pipas/Cortes/Temporadas.
23. Emulador 720×1600: PUXAR ≥ 120 px, nenhum texto < 14 px, emotes aparecem para o outro cliente.
24. 3 clientes + 3 selvagens + 3 pipas caindo: ≤ 1.200 Parts no cliente; `KiteStates` ≤ 15.
25. Locale `en` vê "PULL" / "CUT!" / "FLEW AWAY!"; qualquer outro locale vê pt-BR.

## Verificação do código

```
check.sh /caminho/para/PegaPipa [build/PegaPipa.rbxlx]
```
roda `rojo sourcemap` + `luau-lsp analyze` com os tipos do Roblox (deve terminar com `luau-lsp analyze exit=0`) e,
com o segundo argumento, `rojo build` (`BUILD OK`). `ProfileStore.luau` fica fora da análise. Para formatar e lintar:
`stylua src` e `selene src` (com `selene generate-roblox-std` uma vez).

## O que fica para a v2 (GDD §8)

Troca entre jogadores, rabiolas/varetas cosméticas e skins de laje vendidas direto, season pass, Party/`LaunchData`
para nascer na laje do amigo, ciclo dia/noite com mutação Neon, **Pipa Gigante** (3+ segurando ao mesmo tempo),
zonas Praia e Feira, eventos sazonais (festa junina, Carnaval), times de laje, mini-obby na árvore, renascer 11+,
rewarded video, UI de inventário/venda manual, 1 modelo novo por raridade, ranking mensal e strings em espanhol.
Na v1 tudo isso está intencionalmente fora: o escopo é a lista de arquivos acima.
