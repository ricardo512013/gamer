# GDD — PEGA PIPA / CATCH A KITE (v1 "básico, sem exagero")

**Versão 1.0 — 09/10/2026.** Lead design + direção técnica. Substitui `conceito-brasil.md` onde houver conflito e incorpora os 9 enxertos e os 9 must-fix de `veredito.md`. Regras do documento: (1) todo número vive em `Config.luau` (§7.5) — este GDD é a fonte, o Config é a cópia; (2) zero assets externos, zero scripts dentro do mapa, `--!strict` em todo arquivo; (3) o escopo é a lista de arquivos da §7.1 — o que não está aqui é v2 (§8). Engenheiros podem construir cada arquivo em paralelo só com este documento.

---

## 1. Identidade

| | Valor |
|---|---|
| Nome pt-BR | **Pega Pipa** |
| Nome en | **Catch a Kite** |
| Descrição es (só na loja) | *Atrapa la Cometa* |
| Pitch | Empine pipas na sua laje, deixe o Vento render no varal, suba até o Céu Aberto para cruzar linha com os outros — e quando uma pipa é cortada ela cai no campinho e **é de quem pegar primeiro**. |
| Gramática do botão | "Toca pra subir e brigar, segura pra puxar." |
| Servidor | 12 jogadores (2 vagas reservadas para amigos → enche em 10) |
| Subgênero (Creator Hub) | Party & Casual → **Childhood Game** |
| Público | 16+ na avaliação; conteúdo compatível com label Minimal (sem gore, sem cerol, sem fios) |

**Posicionamento obrigatório (must-fix 3).** Existem jogos de pipa no Roblox: *Kite Combat* (~114 M de visitas, arena de torneio, sem base/renda/corrida) e *Arena das Pipas*. O Pega Pipa se diferencia pelo **verbo "pegar"** (corrida pública pela pipa voada), pela **laje** (base intocável com renda offline) e pelo esqueleto de retenção. Regras: nunca usar "combat/combate", "arena", "torneio/tournament" em título, descrição ou tags; thumbnail mostra **uma pipa caindo com a linha solta e 4 avatares correndo de braço esticado no campinho** (nunca duas pipas brigando); descrição da loja começa com **"Pipa voada é de quem pega."** e segue: "Empine na sua laje, junte Vento, compre pipas no Bar do Vento, suba pro Céu Aberto e corra quando uma pipa voar. Festival do Morro todo sábado 15h." Nenhum item/upgrade se chama "Cerol" ou "Linha Chilena"; a linha é a **Linha de Vento** (mágica) e os níveis têm nomes de vento (§3.4). Dica de carregamento fixa: "Na vida real: pipa longe de fios e sem cerol."

**Ícone (512×512, legível a 64 px).** Céu azul chapado `(90,180,255)`; losango vermelho `(235,60,50)` com contorno preto 12 px e rabiola de 3 laços; texto em caixa alta, fonte grossa (Fredoka One/Luckiest Guy ou equivalente), "PEGA" em cima e "PIPA" embaixo, branco com contorno preto 10 px; versão en "CATCH A" / "KITE". Feito no Studio (print de uma pipa de Parts) + editor de imagem; não é asset do jogo.

**Paleta (RGB).** Céu `(90,180,255)` · Pipa vermelha `(235,60,50)` · Sol/amarelo `(255,205,60)` · Morro verde `(95,185,90)` · Terra do campinho `(150,105,60)` · Asfalto `(60,60,65)` · Laje laranja `(255,140,60)` · Rosa `(255,120,170)` · Lilás `(170,130,230)` · UI fundo `(30,30,45)` · UI texto `(255,255,255)` · Contorno `(20,20,30)`.
Cores de raridade (marcador, moldura das cartas, Billboard): Comum `(190,190,190)` · Incomum `(80,200,100)` · Rara `(60,140,255)` · Épica `(170,80,230)` · Lendária `(255,190,40)` · Mítica `(255,60,200)`. Raridade também é **forma** (cada raridade tem modelo próprio) — daltônicos leem pela silhueta.
8 cores cosméticas de pipa (sorteadas grátis): Vermelho `(235,60,50)`, Amarelo `(255,205,60)`, Verde `(95,185,90)`, Azul `(60,140,255)`, Laranja `(255,140,60)`, Rosa `(255,120,170)`, Lilás `(170,130,230)`, Branco `(245,245,245)`. Cores especiais: Jornal `(235,225,200)` fixa na starter; Raio `(255,255,0)` Neon; Pipeiro `(20,50,120)`; Festival `(0,230,230)`; Temporada n = `Color3.fromHSV((n×0,1)%1, 0,8, 1)`.

**Tom.** Cartoon próprio: SmoothPlastic + Neon, cores chapadas, UI com `UIStroke` de 3 px, humor leve (Morcegão, Capivara Voadora como pipa mítica). Nenhum meme de terceiros, nenhum estereótipo zombeteiro — a laje e o campinho são lugar de brincar, não piada.

---

## 2. Mecânica central

### 2.1 Estados de uma pipa

| Estado | Onde | Rende | Risco |
|---|---|---|---|
| **Varal** | pendurada na laje (base intocável) | `base × 0,25` | nenhum (online e offline) |
| **Selecionada, faixa 0–2** | 1 pipa por jogador; acima da própria laje | `base × FAIXA_MULT` | nenhum |
| **Selecionada, faixa 3–4** | céu compartilhado (anel sobre o campinho) | `base × 1,6 / 2,5` | pode ser cortada |
| **Duelo** | travada 2 s | 0 | decide quem cai |
| **Voada** (caindo 10 s → chão 20 s) | campinho | 0 | de quem pegar primeiro |
| **Árvore** | Árvore do Campinho, 180 s | 0 | quem subir pega |

Só **uma pipa no ar por jogador** (enxerto 1). Seleção padrão ao entrar = maior `base × (golden e 5 ou 1)`. Trocar de pipa (`SelectKite`) só é aceito com a atual na faixa 0.

### 2.2 Faixas de altitude

| Faixa | Nome | Mult. | Altura (y mundial) | Posição horizontal | Cortável |
|---|---|---|---|---|---|
| 0 | Na laje | ×0,25 (= varal)¹ | piso da laje (26,5) | sobre o carretel | não |
| 1 | Baixinha | ×0,5 | laje + 35 = 61,5 | sobre a laje, balanço ±3 | não |
| 2 | Média | ×1,0 | laje + 70 = 96,5 | sobre a laje, balanço ±3 | não |
| 3 | Zona de Briga | ×1,6 | 105 | anel r = 60 sobre o campinho | **sim** |
| 4 | Céu Aberto | ×2,5 | 125 | anel r = 50 sobre o campinho | **sim** — eventos e Dourada só aqui |

¹ Faixa 0 = ×0,25 (não ×0,1) para que nenhum estado online seja pior que o varal/offline; o anti-AFK continua valendo porque sem dedo vivo a pipa desce até aqui.

### 2.3 O botão PUXAR (um só) — gramática final (must-fix 1)

| Gesto | Condição (servidor decide) | Efeito |
|---|---|---|
| **Toque** (< 250 ms) | nenhuma pipa inimiga a ≤ 25 studs | sobe 1 faixa (cooldown 0,8 s; na faixa 4 só balança) |
| **Toque** (< 250 ms) | própria pipa na faixa 3–4 **e** pipa inimiga/selvagem `Flying` a ≤ 25 studs | **Rabeio** (mira automática na mais próxima): mergulho de 12 studs em 0,4 s → **Duelo** |
| **Segurar** (≥ 250 ms), fora de duelo | — | **Puxar a linha**: desce 1 faixa a cada 0,5 s enquanto segura (faixa 4 → 0 em 2 s); soltar para onde está |
| **Segurar**, dentro de duelo | — | cabo de guerra: conta +3 pontos se está segurando no fim dos 2 s (tolerância 300 ms) |
| Toque dentro de duelo | — | ignorado |

**Passo a passo (cliente → servidor):**
1. Cliente: `InputBegan` no botão (ou tecla Espaço/botão A) → `Remotes.get("Pull"):FireServer("Down")`; o botão encolhe para 90 % (`TweenService`, 0,08 s) e fica laranja. `InputEnded` → `FireServer("Up")`; botão volta.
2. Servidor (`KiteService`): em `Down` grava `holdStart[p] = os.clock()` e agenda `task.delay(0,25)`; se ainda está pressionado → `beginHold(p)` (`holding[p]=true`, inicia loop de descida de 0,5 s se a pipa está `Flying` e `faixa > 0`). Em `Up`: se `os.clock() − holdStart < 0,25` → `onTap(p)`; senão `endHold(p)`; sempre `lastHoldEnd[p] = os.clock()`.
3. `onTap`: ignora se `tapCooldown[p] > now` ou pipa não está `Flying`. Procura alvo = pipa `Flying` de outro dono (ou selvagem) com `ImmuneUntil < now`, distância ≤ `RABEIO_RANGE` (25) e própria `faixa ≥ 3` (exceção: alvo com `TutorialFor == p` vale em qualquer faixa ≥ 1). Com alvo → `startRabeio`; sem alvo e `faixa < 4` → `faixa += 1`. `tapCooldown[p] = now + 0,8`.
4. `startRabeio(a, b)`: `a.Status = b.Status = "Dueling"`, `DuelWith` cruzado, `DuelEndsAt = GetServerTimeNow() + 2,4` (0,4 s de mergulho + 2 s de barra). Posição de `a` interpola 12 studs na direção de `b`. Ambos recebem `Toast("Duelo", {oponente, linhaOponente})`.
5. Em `DuelEndsAt`: `pts(p) = Linha(p) + (isHolding(p) and 3 or 0) + rng:NextInteger(0,2)` onde `isHolding(p) = holding[p] or (now − lastHoldEnd[p] ≤ 0,3)`. Selvagem usa `WILD_POINTS[raridade]` fixo. Maior vence; empate → `rng:NextNumber() < 0,5` e ambos veem "SORTE!". Vencedor: `Toast("Cortou")`, `Stats.Cortes += 1`, `CortesPvP += 1` se humano, `ImmuneUntil = now + 3`. Perdedor: `Toast("Voou")`, `HapticService` no cliente; sua pipa vira **Voada** (§2.5) — exceto escudo/Jornal (§2.7). Selvagem que perde cai; selvagem que vence continua voando.
6. Cliente: HUD mostra barra central de 2 s com "SEGURA!" piscando; ao fim "CORTOU!" verde ou "VOOU!" vermelho em tela cheia por 1,2 s (`TextLabel` com `TextScaled`, tween de escala 1,4 → 1,0, Back/Out).

**Pontos fixos das selvagens** (`WILD_POINTS`): Comum 3 · Incomum 5 · Rara 8 · Épica 10 · Lendária 12 · Mítica 14 · Pipa de Treino (onboarding) 0. Jogador segurando tira `Linha + 3 .. Linha + 5`; logo: L1 vence Comum sempre; L3 vence Incomum sempre; L6 vence Rara sempre e Épica em 50 %; L8 vence Épica sempre e Lendária em 50 %; L10 vence Lendária sempre e Mítica em 50 %. **Sem segurar** (Linha + 0..2) o L1 empata com Comum no melhor caso — "segura pra puxar" é a lição dos 40 s.

### 2.4 Deriva no céu compartilhado (≈20 linhas em `KiteService.tick`)

Pipa na faixa 3–4 tem ângulo `θ` (inicial = ângulo da laje do dono) num anel: `pos = (r·cos θ, h, r·sin θ)` com `r/h` = 60/105 (faixa 3) ou 50/125 (faixa 4). `θ += WindSign × ω × peso × dt`, `ω` = 0,05 rad/s (faixa 3) ou 0,08 (faixa 4), `peso` = `1 − 0,08 × (raridade − 1)` (Morcegão é pesado; pipas de pesos diferentes se alcançam). `WindSign` = +1 ou −1 (atributo de `workspace.World`); o evento **Virou o Vento** inverte. Transições (laje ↔ anel, faixa ↔ faixa) são interpoladas pelo servidor a 30 studs/s; o cliente faz lerp suave (§7.2 KiteRenderer).

### 2.5 Queda e pega

1. Pipa cortada: removida **na hora** do perfil do dono (`Kites`), vira `Status = "Falling"` por 10 s rumo a `LandPos` = ponto aleatório do campinho (`x ∈ [−35, 35]`, `z ∈ [−20, 20]`, `y = 1,5`), girando (cliente). Banner para todos: "A Arraia do Fulano voou!" (`Toast("Voada")`). Marcador: coluna Neon 2×200×2 na cor da raridade em `LandPos` (cliente), visível do mapa inteiro.
2. `Status = "Ground"` por 20 s (`StatusUntil`). O servidor, a 10 Hz, procura o `HumanoidRootPart` mais próximo a ≤ 7 studs de `Pos` (qualquer jogador, **inclusive o dono**); o primeiro encontrado recebe a pipa via `DataService.addKite` → `Toast("Pegou")` para ele, `Toast("PegaramSua", {quem})` para o ex-dono, `Dailies.Pegas += 1`. Jogadores com salto de posição > 40 studs em 0,5 s ficam 3 s fora da checagem (anti-teleport).
3. Ninguém pegou → **Árvore** (§2.6). Chuva de Pipas: pipas não pegas somem.

### 2.6 Árvore do Campinho (versão mínima, must-fix 8)

`Status = "Tree"`, `Pos = TREE_TOP (46, 20, 30)`, `StatusUntil = +180 s`. A pega é a mesma checagem de distância (raio 6) — sobe-se pelo `TrussPart`. Dev product **Resgatar da Árvore** (45 R$) devolve a própria pipa na hora. Ao expirar: dono online → volta ao varal; dono offline → destruída. **Fallback se o D2 atrasar:** pular a árvore ("ninguém pegou em 20 s → volta ao dono") e entregar na semana 2.

### 2.7 Escudo de iniciante e Pipa de Jornal

- Conta com `PlayTime < 1.200 s` (20 min) é **Novato**: pode cortar e pegar como qualquer um, mas ao perder um duelo a pipa **volta para a laje** sem cair ("VOOU! Escudo de iniciante: sua pipa voltou"). HUD mostra o escudo com contagem regressiva.
- **Pipa de Jornal** (starter) nunca é perdida nem vendida: cortada → volta à laje.

### 2.8 Pipas selvagens (origem da coleção)

A cada 20–40 s (máx. 3 no ar) entra uma selvagem pela borda (r = 200, ângulo aleatório), voa a 6 studs/s até o anel r = 55 (altura 105 ou 125 aleatória), dá **uma volta contra o vento** (`−WindSign`, ω 0,06 → ≈60 s, passando a ≤ 25 studs de toda pipa do anel exatamente uma vez) e sai pela borda. Nunca ataca; só reage a rabeio. Raridade pela tabela §3.2; cor 1–8 aleatória. Billboard: "Selvagem · Arraia (Rara)".

### 2.9 Feedback visual (só Parts e Tweens, no cliente)

| Momento | Feedback |
|---|---|
| Subir faixa | pipa sobe com lerp (30 studs/s), linha estica; HUD: número do V/s dá *pop* (escala 1,3→1, 0,25 s); na faixa 3 o HUD fica laranja "ZONA DE BRIGA" |
| Rabeio | rastro: 6 Parts 0,3³ Neon brancas espalhadas no caminho, somem em 0,4 s |
| Duelo | as duas linhas tremem (offset senoidal ±0,6 studs a 12 Hz); 4 Parts Neon amarelas piscando no ponto médio; barra central |
| Cortou / Voou | texto tela cheia + `HapticService:SetMotor(Gamepad1, LeftHand, 1)` 0,3 s no perdedor; linha do perdedor some |
| Queda | pipa gira 360°/s em Y e 90°/s em Z; coluna Neon no destino |
| Pega | pipa encolhe até 0 em 0,3 s na posição do jogador; texto "VOCÊ PEGOU: Arraia (RARA)" |
| Dourada | material Neon dourado + `ParticleEmitter` padrão (sem textura) 4/s |
| Coleta no carretel | 8 Parts Neon amarelas 0,5³ voam do carretel para a câmera em 0,5 s |

---

## 3. Loop e progressão

### 3.1 Quatro escalas

- **30 s:** toque ×3 (faixa 3) → selvagem passa → toque = duelo 2 s, "SEGURA!" → "CORTOU!" → corre 8 s, encosta → "+1 Estrela (Incomum) azul" → volta à laje, carretel: "+340 Vento".
- **5 min:** Bar reestoca (relógio no HUD) → compra Linha L2 ou uma pipa → 1º evento de servidor (forçado aos 4 min de vida do servidor) → "falta 1.200 pra Arraia".
- **1 h:** Rara aos ~12 min, Épica aos ~30 min, Linha L6, 5 vagas, 1–2 duelos perdidos (lição de puxar antes de sair) → Vento Dourado em uma pipa sua → 1º Renascer (~1 h). Ao sair, tudo recolhido; offline rende 25 % com cap de 8 h.
- **1 semana:** streak no Correio da Laje (D5 Rara, D7 Pipa Raio) → ranking semanal no Poste (Rei da Laje / Tesoura de Ouro) → sábado 15h **Festival do Morro** → update de sábado.

### 3.2 Raridades (chances somam 100 %)

| Raridade (id) | Modelo | V/s base | Selvagem | Selvagem na Rajada | Estoque do Bar | Preço no Bar | Venda automática (30× V/s) |
|---|---|---|---|---|---|---|---|
| Comum (1) | Pipa de Jornal / Pipa Lisa² | 1 | 55 % | 30 % | 50 % | 60 | 30 |
| Incomum (2) | Estrela | 4 | 28 % | 43,5 % | 30 % | 450 | 120 |
| Rara (3) | Arraia | 15 | 12 % | 18,7 % | 15 % | 3.000 | 450 |
| Épica (4) | Morcegão | 60 | 4 % | 6,2 % | 4,5 % | 18.000 | 1.800 |
| Lendária (5) | Pipa de Luz | 250 | 0,9 % | 1,4 % | 0,5 % | 100.000 | 7.500 |
| Mítica (6) | Capivara Voadora | 1.200 | 0,1 % | 0,2 % | 0 % | — | 36.000 |

² "Jornal" é só a starter (fixa, cor Jornal); Comuns pegas/compradas são "Pipa Lisa" com cor sorteada. Slot **especial** do Bar: Rara 70 % / Épica 25 % / Lendária 5 %. Pipas exclusivas: **Pipa Raio** (Rara, forma Arraia, cor Raio, streak D7), **Arraia Pipeiro** (Rara, Kit), **Pipa de Temporada n** (Épica, forma Morcegão, cor Temporada n).

### 3.3 Renda

`V/s = Σ_pipas base(raridade) × posMult × (1 + 0,15 × Temporadas) × (golden ? 5 : 1) × (VentoEmDobro ? 2 : 1) × eventoMult × (amigoNoServidor ? 1,1 : 1)`
`posMult` = `FAIXA_MULT[faixa]` para a pipa no ar, `0,25` para as do varal. `eventoMult` = 2 no Festival, ×2 com Vento Forte ativo (acumula → 4). Offline: todas as pipas a `0,25`, sem evento/amizade, `elapsed = min(agora − LastSeen, 8 h)` (12 h VIP), creditado no popup "Enquanto você saiu…" com botão RECEBER. O Vento das pipas cai no **carretel** (cap = 900 × V/s atual, isto é 15 min); coleta por `ProximityPrompt` ou botão do HUD a ≤ 12 studs. Carretel Automático deposita direto. **Anti-AFK "linha frouxa":** 180 s sem `Pull` → a pipa desce 1 faixa a cada 90 s.

### 3.4 Preços fixos e venda automática

- **Linha de Vento** (força no duelo), nível n custa `300 × 2^(n−2)`: L2 300 · L3 600 · L4 1.200 · L5 2.400 · L6 4.800 · L7 9.600 · L8 19.200 · L9 38.400 · L10 76.800. Nomes: L1 Brisa, L2 Brisa Forte, L3 Rajada, L4 Rajada Forte, L5 Ventania, L6 Vendaval, L7 Trovão, L8 Tempestade, L9 Furacão, L10 Ciclone.
- **Vagas no varal:** começa com 3; 4ª 2.000 · 5ª 8.000 · 6ª 30.000 · 7ª 120.000 · 8ª 500.000.
- **Varal cheio = venda automática** (enxerto 7): ao receber uma pipa com `#Kites == Vagas`, vende-se a de menor valor entre as candidatas (exclui Jornal, pets e pipas de Temporada) por `30 × base × (golden ? 5 : 1)`; se a nova pipa vale ≤ a menor candidata, a nova é vendida. `Toast("VendaAuto")`. Não existe UI de inventário/venda na v1.

### 3.5 Curva até o 1º Renascer (caminho de referência, grátis)

| Minuto | O que acontece | V/s | Vento acumulado (líquido) |
|---|---|---|---|
| 0–1 | Correio D1 +300; Jornal na faixa 3 | 1,6 | 300 |
| 0:40 | Pipa de Treino (Comum) cortada e pega | 1,9 | 450 |
| 2–5 | dailies +500/+800; compra L2 (300) e Estrela (450); Estrela na faixa 4 | 10 | 1.200 |
| 5–12 | catch de Incomuns; L3 (600), L4 (1.200); Rara no Bar (3.000) | 37,5 | 2.000 |
| 12–20 | Rara na faixa 4; L5 (2.400), 4ª vaga (2.000) | 40 | 12.000 |
| 20–30 | L6 (4.800); Épica no Bar (18.000) ou selvagem Épica a 50 % | 150+ | 15.000 |
| 30–60 | Épica na faixa 4 (150 V/s = 9.000/min) + 5ª vaga (8.000) | 160 | ≈ 250.000 aos 58–65 min |

Com Vento em Dobro: ~45 min. Vento Dourado numa Rara (×5 = 187 V/s) encurta ~10 min.

### 3.6 Renascer — "Nova Temporada"

Custo da temporada n: `250.000 × 3^(n−1)` Vento **+ 1 pipa Épica no varal** (enxerto 8); máx. 10. A Épica consumida **renasce como Pipa de Temporada n** (Épica, cor única). Ganha **+15 % de Vento permanente** por temporada, badge e `Temporadas` no leaderstats. Reseta Vento, Carretel e pipas. **Mantém:** Linha, vagas, streak, passes, Jornal, pipas de Temporada, Arraia Pipeiro e **1 pipa de estimação** marcada pelo jogador (`pet = true`; 2 com VIP). Botão RENASCER no HUD fica habilitado só quando as duas condições valem.

---

## 4. Mapa — "Morro do Vento" (400 × 400 studs, origem no centro do campinho)

Gerado por `MapGen.start()` com `Random.new(2026)`; idêntico em todo servidor. Eixo X = leste, Z = norte, y = 0 no campinho.

### 4.1 Zonas (terreno)

| Zona | Geometria | Como gerar |
|---|---|---|
| Base verde | disco r 200, y 0→24 | `Terrain:FillCylinder(CFrame.new(0,12,0), 24, 200, Grass)` |
| Degrau 2 (r 90–150, y 12) | — | `FillCylinder(CFrame.new(0,18,0), 12, 150, Air)` |
| Centro (r < 90, y 0) | — | `FillCylinder(CFrame.new(0,6,0), 12, 90, Air)` |
| Rua (anel r 95–105 no degrau 2) | asfalto | `FillCylinder(CFrame.new(0,12,0), 1, 105, Asphalt)` depois `FillCylinder(CFrame.new(0,12,0), 1, 95, Grass)` |
| Borda do mundo | r > 200 | `FillBlock(CFrame.new(0,-6,0), Vector3.new(1200,12,1200), Water)` + Parts invisíveis `CanCollide` em r = 210 (4 paredes 420×60×1) |
| Rampas campinho ↔ degrau 2 | 4 | `WedgePart` 16×12×24, Material Grass, cor `(95,185,90)`, a r = 78, ângulos 45°/135°/225°/315°, rampa virada para o centro |

### 4.2 Pontos fixos e as 12 lajes

| Objeto | Posição (x, y, z) |
|---|---|
| Campinho (Part 80×1×50, Ground, `(150,105,60)`) | (0, 0,5, 0) — 6 linhas brancas 0,3 de espessura (laterais, meio, círculo central de 8 Parts) e 2 traves (postes 0,6×8×0,6 em x = ±40, z = ±6 + travessão 12,6×0,6×0,6 a y 8) |
| Spawn (`SpawnLocation` 8×1×8, Neutral) | (0, 1, −32) |
| Bar do Vento | corpo 16×10×12 em (0, 5, −46); balcão 16×3×2 em (0, 1,5, −38) com `ProximityPrompt` "Ver estoque"; toldo 8 faixas 2×0,4×6 alternando `(235,60,50)`/branco em y 10,5, z −39; placa 14×3×0,5 com `SurfaceGui` "BAR DO VENTO" |
| Poste do Ranking (Part 2×24×2 cinza) | (16, 12, −42), `SurfaceGui` na face −Z |
| Árvore do Campinho | tronco Cylinder (18, 4, 4) Wood em (46, 9, 30); 3 Balls Ø12 verdes em (46,18,30), (42,21,33), (50,21,27); `TrussPart` 2×18×2 em (43, 9, 30); `TREE_TOP` = (46, 20, 30) |
| Laje i (i = 1..12) | ângulo `(i−1) × 30°`, r = 120 → **centro da casa** `(120·cos, 19, 120·sin)`: L1 (120, 19, 0) · L2 (103,9, 19, 60) · L3 (60, 19, 103,9) · L4 (0, 19, 120) · L5 (−60, 19, 103,9) · L6 (−103,9, 19, 60) · L7 (−120, 19, 0) · L8 (−103,9, 19, −60) · L9 (−60, 19, −103,9) · L10 (0, 19, −120) · L11 (60, 19, −103,9) · L12 (103,9, 19, −60). Frente virada para o centro. |

**Uma laje** (Model com tag `Laje`, Attributes `Index`, `OwnerId`, `Angle`, `VaralCodes`): casa Part 22×14×22 SmoothPlastic em 1 de 12 cores pastel (y 12–26); piso `Floor` 24×1×24 `(255,140,60)` a y 26,5; 4 muretas 24×2×1 a y 28; caixa-d'água Cylinder (5,5,5) azul no canto traseiro-esquerdo; **carretel** Cylinder (2,3,3) laranja `(255,140,60)` na borda frontal, tag `Carretel`, `ProximityPrompt` (ActionText "Pegar Vento", MaxActivationDistance 10); **varal**: 2 postes 0,4×4×0,4 + linha 0,2×0,2×16 a y 30 (8 vagas a cada 2 studs, pipas em miniatura penduradas pelo cliente); porta 4×7×0,3 e 2 janelas Neon 3×3×0,3 na frente; `TrussPart` 2×14×2 da rua (y 12) ao piso (y 26) na frente. Casa do VIP ganha muretas Neon. Atribuição: ao entrar, primeira laje com `OwnerId == 0`; liberada no `PlayerRemoving`; `CharacterAdded` → `task.wait()` → `character:PivotTo(CFrame.new(centro do piso + Vector3.new(0, 3, 0)))`.

**Casas de enfeite:** 36 Parts (8–16 × 8–14 × 8–16) em r 160–190, ângulos aleatórios, cores pastel, 2 janelas Neon cada; 1 igrejinha branca 14×18×14 a 15°/r 175 com torre 6×26×6 e cruz (2 Parts). Sem postes, sem fios.

### 4.3 Orçamento de Parts (≤ 1.200)

Servidor: 12 lajes × 15 = 180 · enfeites 112 · campinho 20 · rampas 4 · Bar 11 · Poste 1 · Árvore 5 · spawn/paredes 5 → **≈ 340**. Cliente: pipas no ar ≤ 15 × 12 = 180 · caindo/árvore ≤ 11 × 12 = 132 · marcadores 11 · varais ≤ 96 · efeitos ≤ 30 → **≈ 450**. Total ≈ 800. Rabiolas escondidas a > 150 studs da câmera; `GlobalShadows = false`; `StreamingEnabled = false`.

### 4.4 Luz

`Lighting.ClockTime = 16,5`, `Brightness 2`, `LightingStyle = Soft` (cartoon), `Atmosphere{Density 0,25, Haze 1,0, Glare 0,1}`, `OutdoorAmbient (140,160,190)`. Sem sombras.

---

## 5. Sistemas v1

### 5.1 Dados (ProfileStore, chave `User_{UserId}`, store `PegaPipa_v1`)

```json
{
  "Vento": 0, "Carretel": 0, "Linha": 1, "Vagas": 3, "Temporadas": 0,
  "Kites": [ { "id": 1, "model": "Jornal", "rarity": 1, "color": 0, "golden": false, "pet": false, "season": 0, "starter": true } ],
  "NextKiteId": 2, "Selected": 1,
  "PlayTime": 0, "LastSeen": 0, "Onboarding": 0, "KitClaimed": false,
  "Streak": { "Day": 0, "LastClaimDay": 0, "SaverWeek": 0 },
  "Dailies": { "Day": 0, "Cortes": 0, "Pegas": 0, "ClaimedCortes": false, "ClaimedPegas": false },
  "Stats": { "Cortes": 0, "CortesPvP": 0, "Pegas": 0, "VentoTotal": 0 },
  "Weekly": { "Week": 0, "Vento": 0, "CortesPvP": 0 },
  "Purchases": []
}
```
`color`: 0 Jornal, 1–8 cosméticas, 9 Festival, 10 Raio, 11 Pipeiro, 100+n Temporada n. `model` ∈ {Jornal, Lisa, Estrela, Arraia, Morcegao, Luz, Capivara, Raio, Pipeiro, Temporada}. `Purchases` guarda os últimos 50 `PurchaseId`. `profile:Reconcile()` no load; `Save()` em compra, renascer e `ProcessReceipt`; auto-save 300 s; `.Mock` no Studio. Dia = `os.time() // 86400`; semana = `(os.time() − 345600) // 604800` (segunda 00:00 UTC).

### 5.2 Bar do Vento (loja rotativa)

Estoque = 4 slots normais + 1 especial, `seed = os.time() // 300`, `Random.new(seed)` → mesmo estoque em todos os servidores; `RestockAt = (seed + 1) × 300`. Cada slot pode ser comprado **1× por jogador por restock**. Também vende Linha (próximo nível) e vaga (próxima) a preço fixo. Compra exige `HumanoidRootPart` a ≤ 25 studs do balcão. O cliente abre o painel quando a ≤ 20 studs (botão BAR aparece).

### 5.3 Eventos de servidor (`EventService`)

Intervalo 720–900 s após o fim do anterior; **primeiro evento forçado aos 240 s de vida do servidor**. Banner com contagem regressiva 10 s antes.

| Evento | Chance | Duração | Efeito |
|---|---|---|---|
| Rajada | 35 % | 90 s | intervalo de selvagens 7–13 s, máx. 6 no ar, tabela de raridade "Rajada" (§3.2) |
| Chuva de Pipas | 25 % | 10 s de aviso + 25 s | 8 pipas (tabela Rajada) caem de y 60 em 5 s em pontos aleatórios do campinho; 20 s de pega; sem duelo; não pegas somem |
| Vento Dourado | 20 % | 90 s | ao fim, 1 pipa aleatória de jogador na faixa 4 vira Dourada (`golden = true`, ×5 permanente); nenhuma → "o vento passou em branco" |
| Virou o Vento | 20 % | 20 s de aviso | `WindSign = −WindSign` (permanente até o próximo) |

**Festival do Morro:** sábado 15:00–15:40 BRT (`os.date("!*t")`: `wday == 7`, `hour == 18`, `min < 40`): Chuva de Pipas a cada 8 min (5 no total), `eventoMult × 2`, toda pipa pega recebe cor Festival (9). Publicar como Experience Event semanal. **Pipa Gigante:** fora da v1; se o D3 fechar no prazo, forma simples "3+ jogadores segurando ao mesmo tempo a derrubam, todos ganham uma Épica" (§8), senão semana 3.

### 5.4 Streak diário e dailies ("Correio da Laje", popup no join)

D1 300 · D2 600 · D3 1.200 · D4 2.500 · D5 **Arraia (Rara) garantida** + 5.000 · D6 10.000 · D7 **Pipa Raio** + 20.000; D8–D28 repetem o ciclo com Vento ×2 (pipas repetem); trava no D28. `today − LastClaimDay ≥ 2` → volta ao D1, salvo **Guardar Streak** (39 R$, 1×/semana: `SaverWeek`). Dailies (reset diário): "Corte 3 selvagens" → 500 V; "Pegue 1 pipa no campinho" → 800 V.

### 5.5 Ranking e leaderstats

`OrderedDataStore` `Rei_{semana}` (Vento ganho na semana) e `Tesoura_{semana}` (duelos PvP vencidos); `SetAsync` por jogador a cada 60 s só se mudou; `GetSortedAsync(false, 10)` a cada 60 s com cache → `SurfaceGui` do Poste (2 colunas de `TextLabel`). Top 3 da semana anterior (lido 1×/10 min por servidor) recebe atributo `RabiolaRank` 1–3 (rabiola dourada/prata/bronze, cosmético). `leaderstats`: Vento, Pipas, Cortes, Temporadas.

### 5.6 Anti-exploit (todo remote é hostil)

Token bucket por jogador e remote (§7.3); `typeof` + finito + faixa em todo argumento; preços e raridades **só do servidor**; distância validada no servidor (carretel 12, Bar 25, pega 7/6, prompt `MaxActivationDistance + 5`); altitude, deriva, duelo, queda e pega decididos no servidor — o cliente só interpola; `ProcessReceipt` idempotente; anti-teleport na pega; `Access Control = Secure within universe only`; nenhuma lógica de servidor em `ReplicatedStorage`; `RemoteFunction` inexistente.

### 5.7 Monetização (passes Listed, Managed Pricing ligado, preços via `GetProductInfoAsync`)

| Tipo | Chave no Config | Nome | Preço base | Efeito |
|---|---|---|---|---|
| Pass | `PASS_VENTO_DOBRO` | Vento em Dobro | 249 | ×2 Vento (online e offline) |
| Pass | `PASS_CARRETEL_AUTO` | Carretel Automático | 179 | renda vai direto ao Vento (sem cap de 15 min) + puxa a linha sozinho ao perder um duelo |
| Pass | `PASS_VIP` | VIP da Laje | 449 | muretas Neon, nome dourado, rabiola exclusiva, emote extra, cap offline 12 h, **2 pipas de estimação mantidas no renascer** (must-fix 7: sem renda bruta) |
| Pass | `PASS_KIT` | Kit Pipeiro | 299 | Arraia Pipeiro (Rara, cor 11, sobrevive ao renascer) + 3.000 V + Linha mínima L3; concedido 1× (`KitClaimed`) |
| Produto | `PROD_RAJADA` | Rajada no Servidor | 149 | 15 min: selvagens ×2 (intervalo 10–20 s), tabela Rajada, para todo o servidor; banner "Fulano pagou uma Rajada!" |
| Produto | `PROD_VENTO_FORTE` | Vento Forte | 99 | 15 min: ×2 Vento para todo o servidor |
| Produto | `PROD_RESGATE` | Resgatar da Árvore | 45 | devolve a própria pipa presa na árvore |
| Produto | `PROD_GUARDAR_STREAK` | Guardar Streak | 39 | recupera o dia perdido (1×/semana) |

Nada aleatório é vendido; `PolicyService` não bloqueia nada. IDs são placeholders `0` no `Config.IDS` até a publicação.

### 5.8 Funil, co-play e sem chat

`LogOnboardingFunnelStepEvent`: 1 SpawnLaje · 2 PrimeiroPull · 3 PrimeiraColeta · 4 PrimeiroCorte · 5 PrimeiraPega · 6 PrimeiraCompra (meta ≤ 3 min). `LogEconomyEvent` em toda fonte (Renda, Offline, Streak, Daily, VendaAuto, Kit, Produto) e sumidouro (Pipa, Linha, Vaga, Renascer). Botão "Chamar amigo" → `SocialService:PromptGameInvite`; ≥ 1 amigo no servidor → ×1,1 para os dois. **Sem chat:** 4 emotes-balão (Pega! / Valeu! / Cuidado! / Bora!) via atributo `Emote` + `BillboardGui` 2 s; banners automáticos com nomes; vibração.

---

## 6. UI (mobile-first, `ScreenGui` + Frame/TextLabel/TextButton + UICorner/UIStroke 3 px; sem imagens)

Tudo em escala (`UDim2.fromScale`) com `UIAspectRatioConstraint`; fonte `GothamBlack` para títulos, `GothamBold` para texto; `TextScaled` com mínimo efetivo 14 px; `IgnoreGuiInset = true`, `ScreenInsets = DeviceSafeInsets`.

| Elemento | Posição / tamanho | Conteúdo |
|---|---|---|
| **PUXAR** (botão principal) | canto inferior direito, 0,16 da altura da tela (≥ 128 px), círculo laranja `(255,140,60)` | "PUXAR"; segurando: laranja-escuro + anel de progresso; em duelo: "SEGURA!" piscando |
| Vento | topo centro, 0,06 da altura | "12,4 K Vento" + "+37,5/s" (pop a cada mudança de V/s) |
| Carretel | abaixo do Vento | barra "Carretel 1.240 / 3.600" + botão PEGAR VENTO (só a ≤ 12 studs da própria laje) |
| Cartas do varal | coluna esquerda, 3–8 cartas 0,09×0,07 | nome, raridade (moldura na cor), cor, V/s; selecionada com borda branca; toque = selecionar (só na faixa 0); toque longo 1 s = marcar estimação |
| Faixa | acima do botão | "Faixa 3 · ZONA DE BRIGA ×1,6" (cinza 0–2, laranja 3–4) |
| Escudo | sob a faixa | "Escudo de iniciante 14:32" |
| Emotes | canto inferior esquerdo, 4 círculos 0,07 | Pega! Valeu! Cuidado! Bora! |
| Botões de topo direito | 4 ícones-texto 0,07 | BAR (só perto), CORREIO (badge quando há resgate), RENASCER, LOJA |
| Banner de evento | topo, sob o Vento | "▲ RAJADA — 1:12" / "✂ VIROU O VENTO em 20 s" |
| Barra de duelo | centro, 0,5×0,06 | nome dos dois + "SEGURA!" + barra de 2 s |
| Tela cheia | centro, 1,2 s | "CORTOU!" / "VOOU!" / "VOCÊ PEGOU: …" / "SORTE!" |
| Painel Bar (bottom sheet 0,6 da altura) | `UIListLayout` | 5 cartas de pipa (nome, raridade, preço, COMPRAR/COMPRADO), Linha (próximo nível, nome, preço), Vaga (próxima, preço), relógio "Reestoca em 3:12" |
| Correio da Laje (popup) | 0,7×0,6 | fila D1–D7 com o dia atual em destaque + RESGATAR; 2 dailies com progresso e RESGATAR |
| Renascer (popup) | 0,6×0,4 | custo, "1 Épica no varal: ✓/✗", "+15 % permanente", lista do que fica; CONFIRMAR |
| Loja de passes (popup) | lista | 4 passes + 4 produtos com preço via `GetProductInfoAsync` |
| Offline (popup no join) | 0,6×0,35 | "Enquanto você saiu, suas pipas juntaram 12.400 Vento (3 h 12)" + RECEBER |
| Onboarding | setas 3D (`WedgePart` Neon 2×2×3 flutuando com bob de ±1 stud, `BillboardGui` com texto) + anel pulsante no botão | 1 "TOCA pra subir" → 2 "Toca até a faixa 2" → 3 "TOCA pra brigar!" → duelo "SEGURA!" → 4 "CORRE! Pega a pipa" → 5 "Pega seu Vento no carretel" → 6 "Compra uma pipa no Bar" |

**Tabela de strings (chaves em `Config.STRINGS`; en escolhido quando `LocalizationService` do jogador começa com "en")**

| Chave | pt-BR | en |
|---|---|---|
| pull | PUXAR | PULL |
| hold | SEGURA! | HOLD! |
| cut | CORTOU! | CUT! |
| flew | VOOU! | FLEW AWAY! |
| luck | SORTE! | LUCKY! |
| caught | VOCÊ PEGOU: {kite} ({rarity}) | YOU CAUGHT: {kite} ({rarity}) |
| flewBanner | A {kite} de {name} voou! | {name}'s {kite} flew away! |
| someoneCaught | {name} pegou a sua {kite} | {name} caught your {kite} |
| shield | Escudo de iniciante {time} | Beginner shield {time} |
| shieldBack | Escudo: sua pipa voltou pra laje | Shield: your kite went back home |
| wind | Vento | Wind |
| perSec | +{n}/s | +{n}/s |
| reel | Carretel | Reel |
| collect | PEGAR VENTO | COLLECT WIND |
| band0..4 | Na laje / Baixinha / Média / ZONA DE BRIGA / CÉU ABERTO | On the roof / Low / Mid / FIGHT ZONE / OPEN SKY |
| bar | BAR DO VENTO | WIND BAR |
| restock | Reestoca em {time} | Restocks in {time} |
| buy / bought | COMPRAR / COMPRADO | BUY / OWNED |
| line | Linha de Vento L{n} · {name} | Wind Line L{n} · {name} |
| slot | Vaga {n} no varal | Clothesline slot {n} |
| autoSold | Varal cheio: {kite} vendida por {n} Vento | Clothesline full: {kite} sold for {n} Wind |
| mail | CORREIO DA LAJE | ROOFTOP MAIL |
| day | Dia {n} | Day {n} |
| claim | RESGATAR | CLAIM |
| dailyCuts | Corte 3 selvagens ({n}/3) | Cut 3 wild kites ({n}/3) |
| dailyCatch | Pegue 1 pipa no campinho ({n}/1) | Catch 1 kite on the field ({n}/1) |
| rebirth | RENASCER — Nova Temporada {n} | REBIRTH — New Season {n} |
| rebirthNeed | {vento} Vento + 1 pipa Épica | {vento} Wind + 1 Epic kite |
| rebirthKeep | Fica: Linha, vagas, streak, Jornal, estimação | Keeps: Line, slots, streak, Jornal, pet |
| offline | Enquanto você saiu, suas pipas juntaram {n} Vento ({time}) | While you were away your kites gathered {n} Wind ({time}) |
| receive | RECEBER | COLLECT |
| events | Rajada / Chuva de Pipas / Vento Dourado / Virou o Vento / Festival do Morro | Gust / Kite Rain / Golden Wind / Wind Turned / Hill Festival |
| eventIn | {event} em {time} | {event} in {time} |
| golden | A {kite} de {name} virou DOURADA! | {name}'s {kite} turned GOLDEN! |
| wild | Selvagem | Wild |
| tree | Presa na árvore {time} | Stuck in the tree {time} |
| rescue | Resgatar da Árvore | Rescue from Tree |
| rarities | Comum / Incomum / Rara / Épica / Lendária / Mítica | Common / Uncommon / Rare / Epic / Legendary / Mythic |
| kites | Pipa de Jornal / Pipa Lisa / Estrela / Arraia / Morcegão / Pipa de Luz / Capivara Voadora / Pipa Raio / Arraia Pipeiro / Pipa de Temporada {n} | Newspaper Kite / Plain Kite / Star / Stingray / Big Bat / Light Kite / Flying Capybara / Lightning Kite / Kiter Stingray / Season {n} Kite |
| emotes | Pega! / Valeu! / Cuidado! / Bora! | Catch it! / Thanks! / Watch out! / Let's go! |
| invite | Chamar amigo (+10 % Vento) | Invite a friend (+10 % Wind) |
| loadingTip | Na vida real: pipa longe de fios e sem cerol. | In real life: keep kites away from power lines. |
| onb1..6 | TOCA pra subir / Toca até a faixa 2 / TOCA pra brigar! / CORRE! Pega a pipa / Pega seu Vento no carretel / Compra uma pipa no Bar | TAP to go up / Tap up to band 2 / TAP to fight! / RUN! Catch the kite / Collect your Wind at the reel / Buy a kite at the Bar |

---

## 7. Contratos técnicos

### 7.1 Projeto Rojo (13 Luau + ProfileStore vendorizado + `default.project.json`)

```
pega-pipa/
├─ default.project.json  rokit.toml  wally.toml (só ProfileStore, ou vendorizar)  selene.toml  stylua.toml
└─ src/
   ├─ shared/Config.luau                 → ReplicatedStorage/Shared/Config
   ├─ shared/Remotes.luau                → ReplicatedStorage/Shared/Remotes
   ├─ server/init.server.luau            → ServerScriptService/Services (Script; módulos abaixo são filhos)
   ├─ server/ProfileStore.luau           (vendorizado)
   ├─ server/MapGen.luau
   ├─ server/DataService.luau
   ├─ server/KiteService.luau
   ├─ server/ShopService.luau
   ├─ server/EventService.luau
   ├─ server/MonetizationService.luau
   ├─ server/Leaderboard.luau
   ├─ client/init.client.luau            → StarterPlayer/StarterPlayerScripts/Client (LocalScript; módulos filhos)
   ├─ client/KiteRenderer.luau
   └─ client/HUD.luau
```

`default.project.json` (resumo): `emitLegacyScripts: true` (padrão — `.client.luau` vira `LocalScript`, válido em `StarterPlayerScripts`); `ReplicatedStorage.Shared ← src/shared`; `ServerScriptService.Services ← src/server`; `StarterPlayer.StarterPlayerScripts.Client ← src/client`; `Workspace.$properties = {SignalBehavior: "Deferred", StreamingEnabled: false}`; `Lighting.$properties = {ClockTime: 16.5, Brightness: 2, GlobalShadows: false}` + `Atmosphere`; `HttpService.HttpEnabled = false`. Ordem no `init.server.luau`: `Remotes.init()` → `MapGen.start()` → `DataService.start()` → `MonetizationService.start()` → `KiteService.start()` → `ShopService.start()` → `EventService.start()` → `Leaderboard.start()`. Instâncias criadas em runtime: `ReplicatedStorage/Remotes` (Folder), `workspace/Map` (Folder), `workspace/KiteStates` (Folder de `Configuration`), `workspace/World` (`Configuration`).

### 7.2 Arquivos: responsabilidade e API pública

**`shared/Config.luau`** — todas as constantes (§7.5) e tipos: `export type KiteData = {id: number, model: string, rarity: number, color: number, golden: boolean, pet: boolean, season: number, starter: boolean}`; `export type ProfileData = {…schema §5.1…}`; `Config.rarityOf(model: string): number`; `Config.baseRate(k: KiteData): number` (= `BASE_RATE[rarity] × (golden and 5 or 1)`); `Config.str(key: string, locale: string, vars: {[string]: any}?): string`.

**`shared/Remotes.luau`** — `Remotes.NAMES: {string}`; `Remotes.init(): ()` (servidor cria `ReplicatedStorage/Remotes/<nome>`); `Remotes.get(name: string): RemoteEvent` (cliente usa `WaitForChild`); `Remotes.limiter(rate: number, burst: number): Limiter` com `Limiter:allow(p: Player): boolean`, `Limiter:forget(p: Player): ()`; `Remotes.isFinite(n: unknown): boolean`; `Remotes.isInt(n: unknown, min: number, max: number): boolean`.

**`server/MapGen.luau`** — `MapGen.start(): ()` (idempotente: destrói `workspace.Map` antes); `MapGen.lajeModel(i: number): Model`; `MapGen.lajeFloor(i: number): Vector3` (centro do piso, y 26,5); `MapGen.carretelPos(i: number): Vector3`; `MapGen.lajeAngle(i: number): number` (rad).

**`server/DataService.luau`** — perfis, laje, leaderstats, offline, estado para o cliente. `DataService.start(): ()`; `DataService.get(p: Player): Profile?`; `DataService.onLoaded(cb: (p: Player, data: Config.ProfileData) -> ()): ()`; `DataService.addVento(p: Player, n: number, source: string): ()` (**única** porta de entrada de Vento; respeita Carretel vs auto; `LogEconomyEvent`); `DataService.spendVento(p: Player, n: number, sink: string): boolean`; `DataService.collect(p: Player): number` (carretel → Vento, valida distância 12); `DataService.addKite(p: Player, model: string, rarity: number, color: number, golden: boolean?): Config.KiteData?` (aplica venda automática; retorna a pipa criada ou `nil` se ela mesma foi vendida); `DataService.removeKite(p: Player, id: number): Config.KiteData?`; `DataService.findKite(p: Player, id: number): Config.KiteData?`; `DataService.lajeOf(p: Player): number`; `DataService.isNovato(p: Player): boolean`; `DataService.pushState(p: Player, patch: {[string]: any}): ()` (dispara `State`); `DataService.toast(p: Player?, kind: string, args: {[string]: any}): ()` (`nil` = broadcast); `DataService.rateOf(p: Player): number` (V/s, fórmula §3.3; consulta `KiteService.faixaOf` e `EventService.ventoMultiplier`).

**`server/KiteService.luau`** — pipa no ar, faixas, deriva, selvagens, rabeio/duelo, queda, pega, árvore, anti-AFK, tutorial. `export type KiteState = {id: number, owner: number, model: string, rarity: number, color: number, golden: boolean, faixa: number, theta: number, pos: Vector3, status: string, statusUntil: number, duelWith: number?, immuneUntil: number, wild: boolean, tutorialFor: Player?, landPos: Vector3?, conf: Configuration}`. `KiteService.start(): ()`; `KiteService.flyingOf(p: Player): KiteState?`; `KiteService.faixaOf(p: Player): number` (0 se nada no ar); `KiteService.select(p: Player, kiteId: number): boolean`; `KiteService.recall(p: Player): ()` (faixa 0 imediato); `KiteService.spawnWild(rarity: number?, color: number?, opts: {tutorialFor: Player?, points: number?}?): KiteState`; `KiteService.drop(model: string, rarity: number, color: number, landPos: Vector3, ownerId: number?): KiteState` (Chuva e corte); `KiteService.rescueFromTree(p: Player): boolean`; `KiteService.setWind(sign: number): ()`; `KiteService.setWildBoost(intervalMin: number, intervalMax: number, maxInAir: number, table: {number}, untilTime: number): ()`; `KiteService.playersAtFaixa4(): {Player}`; `KiteService.makeGolden(p: Player, kiteId: number): ()`; `KiteService.onDuelEnd(cb: (winner: Player?, loser: Player?, wild: boolean) -> ()): ()`; `KiteService.onCatch(cb: (p: Player, k: KiteState) -> ()): ()`.

**`server/ShopService.luau`** — Bar, Linha, vagas, streak, dailies, renascer, Kit. `ShopService.start(): ()`; `export type StockSlot = {model: string, rarity: number, price: number, special: boolean}`; `ShopService.stock(): {seed: number, restockAt: number, slots: {StockSlot}}`; `ShopService.buy(p: Player, kind: "Kite" | "Linha" | "Vaga", slot: number?): boolean`; `ShopService.claimStreak(p: Player): boolean`; `ShopService.claimDaily(p: Player, which: "Cortes" | "Pegas"): boolean`; `ShopService.progressDaily(p: Player, which: "Cortes" | "Pegas", n: number): ()`; `ShopService.rebirth(p: Player): boolean`; `ShopService.grantKit(p: Player): ()`; `ShopService.useStreakSaver(p: Player): boolean`.

**`server/EventService.luau`** — `EventService.start(): ()`; `EventService.current(): {name: string, phase: "Warn" | "Active", endsAt: number}?`; `EventService.ventoMultiplier(): number` (1/2/4); `EventService.isFestival(): boolean`; `EventService.force(name: string): ()`; `EventService.startServerBoost(kind: "Rajada" | "VentoForte", by: Player): ()`.

**`server/MonetizationService.luau`** — `MonetizationService.start(): ()` (define `ProcessReceipt`, `PromptGamePassPurchaseFinished`, concede Kit no load); `MonetizationService.ownsPass(p: Player, key: string): boolean` (cache por sessão); `MonetizationService.ventoMult(p: Player): number`; `MonetizationService.hasAutoReel(p: Player): boolean`; `MonetizationService.isVIP(p: Player): boolean`; `MonetizationService.offlineCap(p: Player): number` (28.800 ou 43.200).

**`server/Leaderboard.luau`** — `Leaderboard.start(): ()`; `Leaderboard.addWeekly(p: Player, stat: "Vento" | "CortesPvP", n: number): ()`; `Leaderboard.weekIndex(): number`; `Leaderboard.previousTop3(): {number}` (userIds, cache 600 s).

**`client/init.client.luau`** — bootstrap: `HUD.start()`, `KiteRenderer.start()`; input (botão `InputBegan/InputEnded`, `Space`, `ButtonA`) → `Pull`; conecta `State`, `Toast`, `ShopStock`; `SoundService.ListenerLocation = Character`.

**`client/KiteRenderer.luau`** — `KiteRenderer.start(): ()` (assina tag `Kite` e `Laje`); `KiteRenderer.build(model: string, rarity: number, color: number, golden: boolean, scale: number): Model` (Parts da §2.9/§4; `scale` 0,4 no varal); `KiteRenderer.attach(conf: Configuration): ()` (cria render, lerp de `Pos` a cada frame para a própria e 20 Hz para as outras; linha Cylinder do carretel ao corpo; rabiola com balanço senoidal; `BillboardGui` nome/raridade/Linha); `KiteRenderer.detach(conf: Configuration): ()`; `KiteRenderer.showMarker(pos: Vector3, untilTime: number, rarity: number): ()`; `KiteRenderer.renderVaral(laje: Model, codes: string): ()`; `KiteRenderer.arrow3D(pos: Vector3, text: string): () -> ()` (retorna função que remove); `KiteRenderer.burst(pos: Vector3, color: Color3, n: number): ()`.

**`client/HUD.luau`** — `HUD.start(): ()`; `HUD.applyState(patch: {[string]: any}): ()`; `HUD.toast(kind: string, args: {[string]: any}): ()`; `HUD.setStock(stock: {[string]: any}): ()`; `HUD.setDuel(active: boolean, endsAt: number, opponent: string?): ()`; `HUD.setPressed(down: boolean): ()`; `HUD.onboardingStep(n: number): ()`; `HUD.t(key: string, vars: {[string]: any}?): string`; `HUD.onPull: ((down: boolean) -> ())?`, `HUD.onSelect: ((id: number) -> ())?`, `HUD.onBuy`, `HUD.onClaim`, `HUD.onRebirth`, `HUD.onEmote` (callbacks definidos por `init.client`).

### 7.3 RemoteEvents (todos em `ReplicatedStorage/Remotes`; nenhum RemoteFunction)

| Nome | Direção | Payload | Validação no servidor |
|---|---|---|---|
| `Pull` | C→S | `phase: "Down" \| "Up"` | string ∈ {Down, Up}; 6/s, burst 10; lógica §2.3 |
| `SelectKite` | C→S | `kiteId: number` | inteiro 1..NextKiteId; pipa existe; pipa atual em faixa 0 e `Flying`; 2/s |
| `Collect` | C→S | — | distância ≤ 12 do próprio carretel; 2/s |
| `Buy` | C→S | `kind: string, slot: number?` | kind ∈ {Kite, Linha, Vaga}; slot inteiro 1..5; distância ≤ 25 do balcão; Vento suficiente; vagas; slot não comprado; 2/s |
| `ClaimStreak` | C→S | — | `today > LastClaimDay`; 1/s |
| `ClaimDaily` | C→S | `which: string` | ∈ {Cortes, Pegas}; progresso completo; não resgatado hoje; 1/s |
| `Rebirth` | C→S | — | Vento ≥ custo e Épica no varal; `Temporadas < 10`; 1/s |
| `Emote` | C→S | `id: number` | inteiro 1..4 (5 só VIP); cooldown 2 s |
| `State` | S→C | `patch: {Vento?, Carretel?, CarretelCap?, Rate?, Linha?, Vagas?, Temporadas?, Kites?, Selected?, Streak?, Dailies?, Novato?, NovatoUntil?, Onboarding?}` | — |
| `Toast` | S→C (ou broadcast) | `kind: string, args: {[string]: any}` — kinds: Cortou, Voou, Pegou, PegaramSua, Voada, Duelo, Sorte, Dourada, Arvore, VendaAuto, Offline, Streak, Evento, Renasceu, Boost, Erro | — |
| `ShopStock` | S→C (broadcast no restock + join) | `{seed, restockAt, slots: {StockSlot & {bought: boolean}}}` | — |

### 7.4 Attributes e tags

| Instância | Tag | Attributes |
|---|---|---|
| `Player` | — | `Laje` (1–12), `Novato` (bool), `VIP` (bool), `RabiolaRank` (0–3), `Temporadas`, `Emote` (string, 2 s) |
| `workspace/KiteStates/<id>` (`Configuration`) | `Kite` | `Id`, `Owner` (userId, 0 = selvagem), `Model`, `Rarity`, `Color`, `Golden`, `Faixa`, `Pos` (Vector3, 10 Hz), `Status` (Flying/Dueling/Falling/Ground/Tree), `StatusUntil`, `DuelWith`, `DuelEndsAt`, `LandPos`, `Wild`, `Linha` (do dono), `OwnerName` |
| `workspace/Map/Laje_i` (Model) | `Laje` | `Index`, `OwnerId`, `Angle`, `VaralCodes` ("model:rarity:color:golden,…", pipas fora do ar) |
| carretel / balcão / árvore / poste | `Carretel`, `Bar`, `Tree`, `Poste` | `LajeIndex` (carretel) |
| `workspace/World` (`Configuration`) | — | `WindSign` (±1), `EventName`, `EventPhase`, `EventEndsAt`, `Festival` (bool), `RestockAt`, `BoostRajadaUntil`, `BoostVentoUntil`, `BoostBy` |

Tempos replicados usam `workspace:GetServerTimeNow()`.

### 7.5 `Config.luau` — todas as constantes

```lua
--!strict
local Config = {}
Config.SEED = 2026
Config.MAX_PLAYERS = 12            -- Creator Hub: 12, reservados 2
Config.MAP_RADIUS = 200
Config.LAJE_RADIUS = 120           -- 12 lajes a cada 30°
Config.LAJE_FLOOR_Y = 26.5
Config.CAMPINHO = { sizeX = 80, sizeZ = 50, landX = 35, landZ = 20 }
Config.BAR_POS = Vector3.new(0, 1.5, -38)
Config.TREE_TOP = Vector3.new(46, 20, 30)
Config.POSTE_POS = Vector3.new(16, 12, -42)
Config.SPAWN_POS = Vector3.new(0, 1, -32)

-- faixas
Config.FAIXA_MULT = { [0] = 0.25, [1] = 0.5, [2] = 1.0, [3] = 1.6, [4] = 2.5 }
Config.FAIXA_HEIGHT_ABOVE_LAJE = { [1] = 35, [2] = 70 }      -- faixas 1-2 (y = 61.5 / 96.5)
Config.RING = { [3] = { r = 60, h = 105, omega = 0.05 }, [4] = { r = 50, h = 125, omega = 0.08 } }
Config.RARITY_WEIGHT_STEP = 0.08   -- peso = 1 - 0.08*(raridade-1)
Config.KITE_MOVE_SPEED = 30        -- studs/s nas transições
Config.VARAL_MULT = 0.25
Config.OFFLINE_MULT = 0.25
Config.OFFLINE_CAP = 8 * 3600
Config.OFFLINE_CAP_VIP = 12 * 3600
Config.OFFLINE_MIN = 60
Config.CARRETEL_CAP_SECONDS = 900
Config.COLLECT_DIST = 12
Config.AFK_SECONDS = 180
Config.AFK_DROP_EVERY = 90
Config.REBIRTH_BONUS = 0.15
Config.FRIEND_BONUS = 1.1

-- botão
Config.TAP_MAX = 0.25
Config.TAP_COOLDOWN = 0.8
Config.HOLD_DESCEND_EVERY = 0.5
Config.RABEIO_RANGE = 25
Config.RABEIO_DIVE = 12
Config.RABEIO_TIME = 0.4
Config.DUEL_TIME = 2.0
Config.HOLD_GRACE = 0.3
Config.HOLD_BONUS = 3
Config.DUEL_RANDOM = 2
Config.POST_DUEL_IMMUNITY = 3
Config.WILD_POINTS = { [1] = 3, [2] = 5, [3] = 8, [4] = 10, [5] = 12, [6] = 14 }
Config.TUTORIAL_WILD_POINTS = 0
Config.TUTORIAL_AT = 40            -- s de sessão do novato
Config.NOVATO_SECONDS = 1200

-- queda / pega / árvore
Config.FALL_TIME = 10
Config.GROUND_TIME = 20
Config.CATCH_RADIUS = 7
Config.TREE_CATCH_RADIUS = 6
Config.TREE_TIME = 180
Config.TELEPORT_JUMP = 40          -- studs em 0.5 s
Config.TELEPORT_PENALTY = 3
Config.RAIN_FALL_TIME = 5
Config.RAIN_FROM_Y = 60

-- selvagens
Config.WILD_INTERVAL = { 20, 40 }
Config.WILD_MAX = 3
Config.WILD_SPEED = 6
Config.WILD_RING_R = 55
Config.WILD_OMEGA = 0.06

-- raridades (ids 1..6)
Config.RARITY_NAMES = { "Comum", "Incomum", "Rara", "Epica", "Lendaria", "Mitica" }
Config.BASE_RATE = { 1, 4, 15, 60, 250, 1200 }
Config.WILD_TABLE = { 55, 28, 12, 4, 0.9, 0.1 }
Config.WILD_TABLE_RAJADA = { 30, 43.5, 18.7, 6.2, 1.4, 0.2 }
Config.SHOP_TABLE = { 50, 30, 15, 4.5, 0.5, 0 }
Config.SHOP_SPECIAL_TABLE = { 0, 0, 70, 25, 5, 0 }
Config.SHOP_PRICE = { 60, 450, 3000, 18000, 100000, math.huge }
Config.MODEL_BY_RARITY = { "Lisa", "Estrela", "Arraia", "Morcegao", "Luz", "Capivara" }
Config.GOLDEN_MULT = 5
Config.AUTO_SELL_MULT = 30
Config.COLORS = { -- índice → Color3 ; 0 = Jornal
	[0] = Color3.fromRGB(235, 225, 200), Color3.fromRGB(235, 60, 50), Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(95, 185, 90), Color3.fromRGB(60, 140, 255), Color3.fromRGB(255, 140, 60),
	Color3.fromRGB(255, 120, 170), Color3.fromRGB(170, 130, 230), Color3.fromRGB(245, 245, 245),
	[9] = Color3.fromRGB(0, 230, 230), [10] = Color3.fromRGB(255, 255, 0), [11] = Color3.fromRGB(20, 50, 120),
}
Config.RARITY_COLORS = { Color3.fromRGB(190,190,190), Color3.fromRGB(80,200,100), Color3.fromRGB(60,140,255),
	Color3.fromRGB(170,80,230), Color3.fromRGB(255,190,40), Color3.fromRGB(255,60,200) }

-- loja fixa
Config.LINHA_MAX = 10
Config.LINHA_NAMES = { "Brisa", "Brisa Forte", "Rajada", "Rajada Forte", "Ventania", "Vendaval", "Trovao", "Tempestade", "Furacao", "Ciclone" }
function Config.linhaPrice(n: number): number return 300 * 2 ^ (n - 2) end   -- n = 2..10
Config.VAGA_PRICE = { [4] = 2000, [5] = 8000, [6] = 30000, [7] = 120000, [8] = 500000 }
Config.VAGAS_START, Config.VAGAS_MAX = 3, 8
Config.RESTOCK_SECONDS = 300
Config.SHOP_DIST = 25
Config.SHOP_OPEN_DIST = 20

-- renascer
Config.REBIRTH_BASE = 250000
Config.REBIRTH_GROWTH = 3
Config.REBIRTH_MAX = 10
Config.REBIRTH_NEED_RARITY = 4
Config.PETS_KEPT, Config.PETS_KEPT_VIP = 1, 2

-- eventos
Config.EVENT_INTERVAL = { 720, 900 }
Config.FIRST_EVENT_AT = 240
Config.EVENT_WARN = 10
Config.EVENTS = { { "Rajada", 35, 90 }, { "Chuva", 25, 25 }, { "Dourado", 20, 90 }, { "Virou", 20, 20 } }
Config.RAJADA = { interval = { 7, 13 }, maxInAir = 6 }
Config.RAIN_COUNT = 8
Config.FESTIVAL = { wday = 7, hourUTC = 18, minutes = 40, rainEvery = 480, ventoMult = 2, color = 9 }
Config.BOOST_SECONDS = 900
Config.BOOST_RAJADA = { interval = { 10, 20 }, maxInAir = 6 }

-- streak / dailies
Config.STREAK = { 300, 600, 1200, 2500, 5000, 10000, 20000 }
Config.STREAK_KITE = { [5] = { model = "Arraia", rarity = 3 }, [7] = { model = "Raio", rarity = 3, color = 10 } }
Config.STREAK_CAP_DAY = 28
Config.DAILY = { Cortes = { goal = 3, reward = 500 }, Pegas = { goal = 1, reward = 800 } }

-- ranking
Config.LEADERBOARD_PERIOD = 60
Config.WEEK_EPOCH_OFFSET = 345600

-- rede
Config.RATE = { Pull = { 6, 10 }, SelectKite = { 2, 4 }, Collect = { 2, 4 }, Buy = { 2, 4 },
	ClaimStreak = { 1, 2 }, ClaimDaily = { 1, 2 }, Rebirth = { 1, 2 }, Emote = { 0.5, 2 } }
Config.SYNC_HZ = 10

-- monetização (placeholders; preencher no Creator Hub)
Config.IDS = { PASS_VENTO_DOBRO = 0, PASS_CARRETEL_AUTO = 0, PASS_VIP = 0, PASS_KIT = 0,
	PROD_RAJADA = 0, PROD_VENTO_FORTE = 0, PROD_RESGATE = 0, PROD_GUARDAR_STREAK = 0 }
Config.KIT = { model = "Pipeiro", rarity = 3, color = 11, vento = 3000, linhaMin = 3 }
Config.BADGES = { PrimeiroCorte = 0, PrimeiraPega = 0, Temporada1 = 0, Dourada = 0, Mitica = 0 }
Config.PURCHASE_HISTORY = 50

Config.ONBOARDING_STEPS = { "SpawnLaje", "PrimeiroPull", "PrimeiraColeta", "PrimeiroCorte", "PrimeiraPega", "PrimeiraCompra" }
Config.STRINGS = { ptBR = { --[[ tabela §6 ]] }, en = { --[[ tabela §6 ]] } }
return Config
```

### 7.6 Plano de 7 dias (must-fix 6)

D1 Rojo + `Config` + `Remotes` + `MapGen` + `KiteRenderer` (pipa, linha, varal) + faixas + renda/carretel · D2 rabeio, duelo por segurar, queda, pega, árvore mínima, selvagens · D3 ProfileStore, offline com cap, Bar de 5 min, Linha/vagas, venda automática, seleção · D4 4 eventos + Festival, streak, dailies, renascer · D5 passes/produtos com `ProcessReceipt`, ranking, onboarding com setas, strings en, emotes · D6 teste em Android barato com 3 contas + tuning de números · D7 publicação fechada (amigos) medindo bounce < 60 s, sessão ≥ 8 min, D1 ≥ 10 % e **taxa de pega por terceiros** (alvo 40–60 %) antes de qualquer anúncio.

---

## 8. Eventos ao vivo (4 semanas) e v2

| Semana | Entrega (sábado) | "Momento" |
|---|---|---|
| 1 | lançamento fechado → aberto; Festival do Morro nº 1 como Experience Event | 1º vídeo: corrida de 6 pelo Morcegão |
| 2 | Árvore completa (se ficou de fora), strings es, badge de coleção "8 cores", notificação diária opt-in | código de Vento no TikTok |
| 3 | **Pipa Gigante** (3+ segurando ao mesmo tempo derrubam; todos ganham Épica) no Festival | clipe de servidor inteiro |
| 4 | 1 modelo novo por raridade (ex.: Rara "Peixe", Épica "Dragão de Papel"), ranking mensal, Rabiola de Ouro visível na Home | "temporada 1" oficial |

**Fica para a v2:** troca entre jogadores (`IsPaidItemTradingAllowed`), rabiolas/varetas cosméticas vendidas direto, skins de laje, season pass leve, Party/`LaunchData` para nascer na laje do amigo, ciclo dia/noite com mutação Neon, Pipa Gigante global, zonas Praia e Feira, sazonais (festa junina, Carnaval), times de laje, mini-obby na árvore, renascer 11+, rewarded video com dev product fixo, UI de inventário/venda manual.

---

## 9. Checklist de aceitação (Studio, Local Server com 2–3 clientes)

1. **Mapa determinístico:** dois "Play" consecutivos geram `workspace.Map` com o mesmo número de BaseParts (≤ 400) e a Laje 4 centrada em (0, 19, 120) ± 0,1.
2. **Spawn na laje:** cada cliente nasce a ≤ 6 studs do piso da própria laje; atributo `Laje` distinto por jogador; ao sair, `OwnerId` da laje volta a 0.
3. **Toque sobe:** 4 toques → `Faixa = 4` em ≤ 4 s; HUD mostra "×2,5"; ao entrar na faixa 3 o HUD fica laranja.
4. **Segurar puxa:** segurar 2 s da faixa 4 leva a 0; soltar após 0,6 s para na faixa 3.
5. **Renda:** Jornal na faixa 2 por 60 s → `Carretel` sobe 60 ± 2; ao atingir `900 × Rate` para de subir.
6. **Coleta:** prompt do carretel transfere Carretel → Vento; `Collect` disparado a 30 studs é ignorado (sem erro no Output).
7. **Tutorial aos 40 s:** novato na faixa ≥ 1 vê a Pipa de Treino com seta "TOCA pra brigar!"; toque inicia duelo; vence sempre; pipa cai no campinho; funil 1–5 logado em ordem.
8. **Duelo PvP:** A e B na faixa 3 a ≤ 25 studs; toque de A inicia duelo para ambos (`Status = Dueling`, `DuelEndsAt` igual); B segurando (L1) vs A sem segurar (L1) → B vence em 10/10.
9. **Empate:** L2 segurando × L2 segurando, 20 duelos → 6–14 vitórias para cada lado; "SORTE!" aparece quando os pontos empatam.
10. **Queda e pega:** pipa cortada chega ao chão em 10 s dentro de x ∈ [−35, 35], z ∈ [−20, 20]; coluna Neon visível de qualquer laje; cliente C que encosta primeiro recebe a pipa em `State.Kites`; dono recebe "C pegou a sua Arraia"; `Dailies.Pegas` de C = 1.
11. **Dono recupera:** o próprio dono pode pegar a pipa de volta.
12. **Árvore:** 20 s sem pega → pipa em `TREE_TOP`; subir o Truss e chegar a ≤ 6 studs pega; sem pega, após 180 s volta ao varal do dono online; com dono offline é destruída.
13. **Escudo e Jornal:** conta com `PlayTime < 1.200` perde → pipa volta à laje com toast de escudo; Pipa de Jornal cortada volta sempre e nunca aparece na venda automática.
14. **Venda automática:** varal 3/3 (Jornal + 2 Comuns) e compra de uma Estrela → 1 Comum vendida por 30 V; comprar outra Comum com varal cheio de Incomuns → a Comum nova é vendida.
15. **Bar:** `RestockAt` avança a cada 300 s; dois servidores com o mesmo `os.time() // 300` mostram os 5 mesmos slots; compra a 30 studs negada; segunda compra do mesmo slot negada; L2 custa 300, 4ª vaga 2.000, preços da UI iguais ao Config.
16. **Offline:** sair com Estrela + Comum, ajustar `LastSeen = agora − 3 h` no Mock → popup com `(4 + 1) × 0,25 × 10.800 = 13.500`; com `LastSeen = agora − 20 h` o valor usa 8 h (36.000); VIP usa 12 h.
17. **Eventos:** evento forçado aos 240 s; em 200 sorteios com seed fixa a distribuição fica em 35/25/20/20 ± 5; Virou o Vento inverte `WindSign` 20 s após o aviso; Chuva derruba 8 pipas que somem após 20 s; Vento Dourado marca `golden = true` em exatamente 1 pipa da faixa 4 (ou mostra "passou em branco").
18. **Streak:** 1º join → D1 300; avançar 1 dia no Mock → D2 600; pular 2 dias → D1; D5 entrega Arraia; D7 entrega Pipa Raio cor 10; D8 paga 600.
19. **Renascer:** com 250.000 V + 1 Épica → `Temporadas = 1`, Vento 0, Linha/vagas/Jornal/estimação mantidos, a Épica vira `Temporada` cor 101; sem Épica, botão desabilitado e remote negado; custo da temporada 2 = 750.000.
20. **Monetização:** chamar `ProcessReceipt` duas vezes com o mesmo `PurchaseId` de Vento Forte aplica o boost 1×; Vento em Dobro dobra `Rate`; Kit concedido 1× (`KitClaimed`) com Linha ≥ 3; preços da loja vêm de `GetProductInfoAsync`.
21. **Anti-exploit:** `Pull` a 20/s é limitado sem kick; `Buy("Kite", "abc")` e `SelectKite(999)` ignorados; jogador teleportado 100 studs não pega por 3 s.
22. **Ranking:** após 60 s o Poste lista o top 10 de Vento e de Cortes PvP; `leaderstats` mostra Vento/Pipas/Cortes/Temporadas.
23. **Mobile sem chat:** emulador 720×1600 → PUXAR ≥ 120 px, nenhum texto < 14 px, emotes aparecem como balões para o outro cliente; nenhuma ação exige chat ou dois toques simultâneos.
24. **Performance:** 3 clientes + 3 selvagens + 3 pipas caindo → BaseParts no cliente ≤ 1.200; servidor ≤ 2 ms/frame no MicroProfiler; `KiteStates` com ≤ 15 Configurations.
25. **Localização:** conta com locale `en` vê "PULL", "CUT!", "FLEW AWAY!" e nomes em inglês; pt-BR é o padrão para qualquer outro locale.
