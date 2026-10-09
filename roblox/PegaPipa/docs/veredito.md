# VEREDITO DO JÚRI — qual conceito vira o jogo (09/10/2026)

**Juiz:** publisher veterano de Roblox (centenas de lançamentos vistos), em modo adversarial.
**Insumos lidos na íntegra:** `research/BRIEF.md`, `design/conceito-viral.md` (Corta Pipa / Cut a Kite), `design/conceito-brasil.md` (Pega Pipa / Catch a Kite), `design/conceito-mvp.md` (Empilha Capivara / Stack a Capybara).
**Restrição do usuário que pesa acima de tudo:** "não precisa ser nada exagerado" — jogo BÁSICO, 1 dev, 1 projeto Rojo com ~10–14 arquivos Luau, só Parts/Terrain/UI programática, um botão no celular, sem chat, sem item aleatório pago.

---

## 0. Resumo executivo

| | Nota final (de 60) | Veredito |
|---|---|---|
| **Pega Pipa / Catch a Kite** (brasil) | **47** | **VENCEDOR** — com 7 enxertos e 9 must-fix que cortam escopo |
| Empilha Capivara / Stack a Capybara (mvp) | 46 | 2º — o mais barato de construir, mas objeto saturado e loop de "coleta e entrega" |
| Corta Pipa / Cut a Kite (viral) | 41 | 3º — o título nomeia exatamente o que o Kite Combat (114 M de visitas) já faz, e carrega o fantasma do cerol |

**Nome final:** **Pega Pipa** (pt-BR) / **Catch a Kite** (en) / *Atrapa la Cometa* (es, só descrição). Nenhum jogo de Roblox com esses nomes foi encontrado (seção 4).

**Por que a pipa ganha da capivara por 1 ponto, e por que esse ponto é decisivo:**
1. **Demanda provada dentro da plataforma, sem líder atual.** A pesquisa encontrou o que o BRIEF e os três designers não viram: o *Kite Combat* (set/2024) tem ~114,5 M de visitas e 8,6 M de favoritos, no subgênero oficial "Childhood Game", classificação Minimal — mas hoje gira em 1–2 K CCU, é uma arena de torneio sem base, sem renda, sem corrida pela pipa caída e sem renascer. O tema de pipa já provou tração no Roblox; ninguém aplicou nele o esqueleto "coletar → base → renda → conflito leve → renascer". É exatamente o espaço #4 do BRIEF ("Steal a" com verbo, objeto e stat novos).
2. **O verbo do título é o que ninguém tem.** "Cortar" já é do Kite Combat e do Arena das Pipas; "roubar" é do SAB; "pegar" (a corrida pública pela pipa voada) não está em nenhum jogo de Roblox encontrado. O título conta o clipe.
3. **O clipe é maior.** "CORTOU!" no céu → pipa girando com marcador de luz → seis bonecos descendo a laje → novato encosta primeiro → "VOOU!" na tela do veterano. Dois lados filmáveis em 15 s, sem texto. A pilha de capivaras caindo é engraçada, mas é um clipe de 1 pessoa; a corrida é um clipe de servidor.
4. **A capivara está saturada e o ícone vai parecer clone.** Steal a Capybara (51,7 M de visitas), Capybaras vs Plants (49 K de pico de CCU em 08/2026), Capybara Evolution, Capybara Race Simulator, Capybara Run — a 64 px, um bloco marrom com cara de capivara é indistinguível do "Roube uma Capivara", e o algoritmo de 2026 desprioriza "não únicos".

A vantagem real do Empilha Capivara é **simplicidade (9 vs 6)**. O júri aceita o Pega Pipa **somente** com a lista de must-fix da seção 7, que traz o escopo dele ao nível do MVP (1 pipa no ar, 1 botão, duelo sem toque repetido, sem chefe, 6–7 dias).

---

## 1. Fato novo que muda o julgamento: o Roblox já tem jogo de pipa

Os três conceitos (e o BRIEF) afirmam "nenhum jogo de pipa aparece nas seis lentes nem nos tops de 2024–2026". A busca desta rodada mostra que a afirmação é falsa no que importa:

| Jogo (Roblox) | O que é | Escala (rastreadores de terceiros) | Fonte |
|---|---|---|---|
| **Kite Combat 🪁** (zFighttx, 21/09/2024) | "Fly a kite with your friends. Cut the kite line of other kites. Get new kites. Buy new lines. Win the kite tournament." Moedas Money + Diamonds; passes VIP Bronze 400 → Silver 599 → Gold 799 → Platinum 999 → Diamond 1.499 R$. Party & Casual / "Childhood Game", Minimal (All Ages). | ~114,5 M visitas, 8,6 M favoritos, pico 15,2 K CCU, 915 CCU no snapshot (média 7 d ≈ 2,1 K), rank global #596 | [rotrends](https://rotrends.com/game/6579282112/Kite-Combat), [roblox.com](https://www.roblox.com/games/127099886596040/Kite-Combat), [rolimons](https://www.rolimons.com/game/127099886596040), [robloxden](https://robloxden.com/game-codes/kite-combat) |
| **Kite Arena / Arena das Pipas** | arena brasileira: "equipe sua pipa no inventário (B), corte outros jogadores, compre linhas melhores" | escala não encontrada (pequeno) | [roblox.com](https://www.roblox.com/games/134035005891152/Arena-das-Pipas) |
| **Kite Simulator (Kite V1.0)** | simulador pequeno | não encontrado (pequeno) | [roblox.com](https://www.roblox.com/games/136120445451428/Kite-V1-0) |
| Every Second You Get +1 Kite | incremental irrelevante | 26,6 K visitas | [bloxodes](https://bloxodes.com/stats/games/every-second-you-get-1-kite-7751435781) |

Fora do Roblox, o tema é um gênero inteiro: *Pipa Combate 3D*, *CS Diamantes Pipas* (que já tem "colete pipas caídas para trocar por troféus"), *The Last Kite Fighter* (itch.io, com "kite runner" que fica com a pipa que pega) e *Yakko Tako Royale* (Steam, em breve).

**Leitura do júri:** isso é **bom** para o Pega Pipa e **ruim** para o Corta Pipa. O Kite Combat prova demanda na plataforma (114 M de visitas num jogo de 2 anos, feito por 1 pessoa, sem o esqueleto de retenção). O que ele **não** tem — laje/base, renda passiva com offline, loja de 5 min, eventos de servidor, renascer, e a **corrida pública pela pipa voada** — é o núcleo do Pega Pipa. Já o Corta Pipa escolheu como título o verbo que o Kite Combat já ocupa ("cut the kite line"), e a thumbnail "duas pipas brigando" ficaria idêntica.

---

## 2. Passada adversarial (antes de dar nota)

### 2.1 Corta Pipa / Cut a Kite (viral)

**"É clone?"** Do SAB, não: verbo, objeto e stat mudam, a base é intocável, a perda é opt-in. **Do Kite Combat, parcialmente sim no que o título e a thumbnail mostram:** cortar linha de pipa, comprar linha mais forte, pipas novas. O que o diferencia (varal, renda × linha solta, corrida) não está no nome.

**"É sem graça?"** Risco real. No modo "Empinando" o jogador fica parado na laje, movimento travado, olhando uma pipa a 80–180 studs de altura (um pontinho na tela de 6") derivar sozinha. A única decisão é "quando recolher". O duelo de 2 s é `nível da Linha + 3 se segurando + aleatório 0–2`: quase nada a fazer. O cruzamento de linhas entre 12 lajes num anel, com vento global girando, é **ilegível no celular**: o jogador não consegue prever com quem vai enroscar. A corrida (parte boa) só acontece depois de um trecho passivo.

**"É grande demais?"** Sim para "básico": vetor de vento global que gira, deriva, rajadas spawnando à frente, distância segmento-segmento de 66 pares a 10 Hz, dois modos de jogo com câmera própria (`KiteView`), pipa física caindo, Pipa Gigante que exige 3+ jogadores segurando, Arco-Íris, 5 eventos + Festival. 13 arquivos e 2.500 linhas são plausíveis, mas o plano de 6 dias não tem folga de teste.

**Política:** "Corta/Cut" no título + pipa = associação imediata com cerol/linha chilena na imprensa brasileira (motociclistas mortos, leis municipais). O documento mitiga dentro do jogo, mas o título é o que o pai lê na loja. Fallback "Empina uma Pipa" existe, mas aí o verbo some.

### 2.2 Pega Pipa / Catch a Kite (brasil)

**"É clone?"** Do SAB/Steal an Egg/GaG, não (objeto, verbo e stat mudam; sem invasão de base; sem esteira). **Do Kite Combat:** compartilha objeto e o ato de cortar, mas o verbo do título (pegar), o stat (altitude = dial de risco/renda), a base (laje com varal e renda offline), a loja de 5 min, eventos, renascer e a corrida pública são novos. Passa a regra "≥2 de 3" tanto contra a família Steal-a quanto contra o Kite Combat.

**"É sem graça?"** Menos risco que o viral: o céu compartilhado é **um círculo de 70 studs sobre o campinho**, então "lá em cima é a arena" lê de longe; subir é consentir; o rabeio dá agência (você escolhe atacar); pipas selvagens dão conteúdo para servidor vazio; a pipa cai no centro do mapa, onde todo mundo vê. **Mas:** o duelo de "toque repetido, 8 toques/s" é um anti-padrão clássico (autoclicker, fadiga de dedo, quem tem 250 ms de ping na Vivo perde toques); e o botão único vira dois (PUXAR + RECOLHER), violando a restrição.

**"É grande demais?"** Como está escrito, sim: bando de até 8 pipas por jogador voando juntas (12 × 8 = 96 pipas + rabiolas = ~1.000 Parts só de pipa), chefe Pipa Gigante com 2.000 pontos e recompensa por participante, árvore escalável, 4 eventos + Festival, 2 botões, plano de **4 dias** (irreal). Tudo isso é cortável sem perder o núcleo (seção 7).

**Política:** nome limpo; "cortar" continua no gameplay, mas o Kite Combat é classificado **Minimal** com o mesmo ato, o que é evidência empírica de que a Roblox não vê problema. Mapa sem fios/postes, "Linha de Vento" mágica, dica de carregamento — mantém.

### 2.3 Empilha Capivara / Stack a Capybara (mvp)

**"É clone?"** Do SAB, não (verbo e stat novos, lagoa sagrada). **Mas o objeto é o mais usado do Roblox-BR em 2025–26:** Steal a Capybara (51,7 M visitas), Capybaras vs Plants (49 K CCU de pico em 08/2026, códigos "45MVISITS"), Capybara Evolution, Capybara Race Simulator, Capybara Run. Dois dos 3 elementos (verbo + stat) são novos — passa a regra do BRIEF no papel, mas **a 64 px o ícone é "mais um jogo de capivara"**. Na App Store existe *Capybara Stack* (torre casual, iOS) — colisão de nome fora da plataforma. O mecanismo "carregar pilha que balança na cabeça" é o padrão hiper-casual de celular (estilo Stacky Dash) — conhecido, não original.

**"É sem graça?"** O loop é andar até o bicho, apertar, andar de volta, depositar: **simulador de coleta e entrega**, gênero mais comum do Roblox. O push-your-luck ("pego mais uma?") e o esbarrão salvam, mas a tensão vem de velocidade reduzida, que no celular vira "andar devagar". A sorte visível é só cor/enfeite.

**"É grande demais?"** Não — é o mais barato. Welds, zero simulação, balanço cosmético no cliente, jogável no dia 1. ~3,6 K Parts (300 capivaras × 12) é o maior orçamento dos três, resolvido com StreamingEnabled. Esse é o motivo do 9 em simplicidade e do 2º lugar.

**Política:** baixíssimo. Percepção de "maus-tratos" é mitigada pelo próprio meme (capivara deixa bicho sentar nela).

---

## 3. Notas (1–10; policy_risk 10 = sem risco)

| Critério | Corta Pipa (viral) | **Pega Pipa (brasil)** | Empilha Capivara (mvp) |
|---|---|---|---|
| Originalidade | 6 | **7** | 6 |
| Potencial de sucesso (fórmula viral + esqueleto de retenção) | 7 | **8** | 7 |
| Simplicidade (básico, parts-only, ~12 Luau) | 5 | **6** | 9 |
| Clipabilidade | 9 | **9** | 7 |
| Apelo BR + global | 8 | **9** | 8 |
| Risco de política (10 = nenhum) | 6 | **8** | 9 |
| **Total** | **41** | **47** | **46** |

**Justificativas curtas**
- *Originalidade:* viral 6 porque o título duplica o Kite Combat; brasil 7 porque o verbo e o loop são novos mas o objeto já existe no Roblox; mvp 6 porque o objeto é saturado e a mecânica é hiper-casual conhecida.
- *Sucesso:* brasil 8 = demanda provada (Kite Combat) + esqueleto Steal-a + arena legível + consentimento + selvagens para servidor vazio + corrida. Viral 7 = clipe ótimo, mas voo passivo e cruzamento ilegível. Mvp 7 = legível em 3 s, meme global, mas é coleta-e-entrega num tema lotado.
- *Simplicidade:* mvp 9 (welds); brasil 6 como escrito (sobe para ~8 com os must-fix); viral 5 (vento + geometria + dois modos + câmera).
- *Clipe:* os dois de pipa 9 (corrida de servidor com nomes automáticos); mvp 7 (queda de pilha é engraçada mas individual).
- *BR + global:* brasil 9 — "pega!" é o grito real da rua; "Catch a Kite" é wholesome em inglês; pipa é universal (Chile, Índia, Paquistão, Indonésia, Guiana) e a capivara entra como pipa mítica (piscadela sem virar tema). Viral 8 (mesmo tema, título mais agressivo). Mvp 8 (capivara é meme global, mas já carimbada por 5 jogos).
- *Política:* viral 6 ("Cut"/"Corta" + cerol na manchete); brasil 8 (nome limpo, ato de cortar já aceito como Minimal no Kite Combat); mvp 9.

---

## 4. Checagem de originalidade (busca web, 09/10/2026)

**Ferramenta:** WebSearch (14 buscas pt-BR/en) + tentativas de WebFetch (rotrends, rolimons, roblox.com, robloxden, gamerant, apps.apple.com **bloqueados pelo proxy** — os números abaixo vêm dos trechos de busca e devem ser conferidos na página do jogo antes de qualquer citação pública).

### 4.1 Pega Pipa / Catch a Kite (vencedor)
- `roblox "Catch a Kite"` → **nenhum jogo** com esse nome. Resultado mais próximo: **Kite Combat 🪁** (dados na seção 1).
- `roblox "Pega Pipa" jogo` → **nenhum**; só *Pipa Park* (itch.io, Windows), *CS Diamantes Pipas* (iOS) e o minijogo "pega-pega" do Roblox Squid Game.
- `roblox kite fighting game cut line catch fallen kite` → nenhum jogo de Roblox com "corrida pela pipa caída"; a mecânica de "kite runner fica com a pipa" aparece só em *The Last Kite Fighter* (itch.io) e em *CS Diamantes Pipas* (troféus).
- `roblox jogo de pipa empinar cortar linha` → nenhum; só *CS Diamantes Pipas* (mobile) com "soltar linha / puxar".
- Padrão "Catch a X" está vivo no Roblox: *Catch a Brainrot* (2026, RPG de coleção) — não conflita, mas confirma que "Catch a" é lido como título de jogo.
- **Conclusão:** nome livre nos dois idiomas; mecânica "cortar" existe (Kite Combat, Arena das Pipas); mecânica "pegar a pipa voada em corrida pública + base/renda/renascer" **não existe** no Roblox. O nome fica.

### 4.2 Empilha Capivara / Stack a Capybara (2º)
- `roblox "Stack a Capybara"` → **nenhum jogo de Roblox**. Existe **Capybara Stack** (iOS, torre casual, grátis com IAP) — colisão de nome fora da plataforma.
- `roblox "Empilha Capivara"` → nenhum; resultados são *Capybaras vs Plants* e *Grow a Garden*.
- `roblox stacking carry stack on head` → nenhum jogo de Roblox encontrado (só brinquedos de madeira *Animal Upon Animal* / *Woodland Wobble*).
- `roblox "Stack a Brainrot" / "Stack a"` → nenhum "Stack a" no Roblox; o formato "X a Brainrot" segue (Steal, Catch, Be, Escape Tsunami For).
- Saturação do objeto: **Steal a Capybara** 51,7 M visitas (criado 26/05/2025, 2,7 M favoritos), **Capybaras vs Plants** 5,9 M → ~45 M visitas, pico 49 K CCU (08/2026), **Capybara Evolution**, **Capybara Race Simulator**, **Capybara Run**.
- **Conclusão:** nome livre no Roblox, verbo inédito, mas o objeto é o mais disputado do Roblox-BR.

### 4.3 Corta Pipa / Cut a Kite (3º, checado por ser irmão do vencedor)
- `roblox "Cut a Kite" OR "Corta Pipa"` → nenhum jogo de Roblox com o nome; mas o verbo é literalmente a descrição do Kite Combat ("Cut the kite line of other kites") e do Arena das Pipas. Nome livre, posicionamento ocupado.

---

## 5. Vencedor e nome

**Pega Pipa / Catch a Kite.** Mantém o nome; nenhuma troca necessária. Fallbacks já verificados como livres caso a loja ou um teste com crianças reprove: *Solta Pipa / Fly a Kite* (não buscado — verificar antes de usar) e *Corta Pipa / Cut a Kite* (livre, mas **não recomendado** pela seção 1 e pelo cerol).

**Posicionamento obrigatório contra o Kite Combat** (vai na descrição da loja e na thumbnail, não só no documento):
- Nunca usar "combat/combate", "arena", "torneio/tournament" no título, descrição ou tags.
- A thumbnail mostra o **verbo do título**: uma pipa caindo com a linha solta e 4 avatares correndo de braço esticado no campinho — **não** duas pipas brigando no céu.
- Descrição começa pela regra de rua: "Pipa voada é de quem pega." Depois: laje, Vento, Bar, Festival.
- Subgênero no Creator Hub: Party & Casual → "Childhood Game" (o mesmo do Kite Combat, onde a demanda já está).

---

## 6. Enxertos dos perdedores (sem aumentar escopo — todos reduzem ou mantêm)

**Do Corta Pipa (viral):**
1. **Uma pipa no ar por vez; o resto fica no varal da laje rendendo passivo.** Substitui o "bando de 3–8 pipas voando juntas". Corta ~85 % das Parts de pipa, deixa óbvio qual pipa está em risco, e a laje/varal vira a "base intocável" (nada é perdido no varal, nada é perdido offline). As "vagas" continuam sendo o upgrade de base (3 → 8 vagas no varal).
2. **Duelo por "segurar", não por toque repetido.** Ao enroscar: barra de 2 s; pontos = nível da Linha + 3 se está **segurando PUXAR** no fim + aleatório 0–2. Um input, tolerante a 300 ms, sem autoclicker, e um iniciante atento ainda bate um nível 3 distraído. Selvagens usam pontos fixos por raridade (tabela do brasil).
3. **Evento "Virou o Vento"** (aviso de 20 s, a deriva do céu compartilhado inverte): ~20 linhas de código, zero Parts, e produz o clipe de "corte em cadeia".
4. **Escudo de iniciante do tipo "pode cortar, não perde":** nos primeiros 20 min da conta, pipa cortada do novato sempre volta para a laje dele, mas ele já pode cortar e pegar as dos outros. Substitui a "imunidade a duelos por 15 min" (que impede o novato de viver o clipe).
5. **Pipa Gigante no modelo "3+ segurando ao mesmo tempo"** se (e só se) o D3 estiver no prazo; caso contrário fica para a semana 3 do roadmap. Mais simples que o chefe de 2.000 pontos.

**Do Empilha Capivara (mvp):**
6. **Onboarding com setas 3D + primeiro evento de servidor forçado aos 4 min de vida do servidor**, para que todo novato veja um evento na primeira sessão. Zero sistema novo.
7. **Varal cheio = venda automática da pipa de menor valor por 30 × o seu V/s.** Elimina a UI de inventário/venda da v1.
8. **Renascer exige 1 pipa de raridade específica além do Vento** (Nova Temporada 1 = 250 K + 1 Épica no varal). Liga o renascer à caçada, como no SAB; custo zero.
9. **Streak com pipa em vez de só moeda no D5 e no D7** (D5 Rara garantida, D7 Pipa Raio exclusiva) — o DevForum mostra que daily só de moeda não move playtime. O brasil já tinha o D7; adiciona o D5.

---

## 7. Must-fix (violações de restrição/brief no vencedor, como está escrito)

1. **Dois botões (PUXAR + RECOLHER) → um botão.** Gramática final de **PUXAR**: *toque* (< 250 ms) = sobe 1 faixa; se houver linha inimiga a ≤ 20 studs, o toque vira **rabeio** (mira automática); *segurar* (≥ 250 ms) = **puxar a linha**: fora de duelo recolhe até a faixa 0 (fuga), dentro de duelo é o cabo de guerra (enxerto 2). "Toca pra subir e brigar, segura pra puxar." Entendido em 30 s.
2. **Duelo por toque repetido (8/s) → removido** (enxerto 2). Anti-padrão: autoclicker, fadiga, ping da Vivo decide, e é o remote que exploit mira.
3. **Afirmação "nenhum jogo de pipa no Roblox" → corrigir no documento e no posicionamento.** Kite Combat (~114 M visitas) e Arena das Pipas existem. Diferenciar por verbo (pegar), base/renda e corrida; thumbnail e descrição como na seção 5.
4. **Bando de 8 pipas voando → 1 pipa no ar** (enxerto 1). Orçamento alvo: ≤ 1.200 Parts no total; 12 pipas no ar + ≤ 3 selvagens + 12 varais.
5. **Chefe Pipa Gigante (2.000 pts, recompensa por participante, Lendária ao último toque) → fora da v1** ou na forma simples do enxerto 5. Eventos da v1: Rajada, Chuva de Pipas, Vento Dourado, Virou o Vento. Festival de sábado usa Chuva a cada 8 min em vez de Gigante.
6. **Plano de 4 dias → 6–7 dias.** D1 MapGen + render da pipa + faixas + renda · D2 enrosco, duelo, queda, pega, árvore simples · D3 ProfileStore, offline com cap, Bar de 5 min, Linha/vagas, venda automática · D4 eventos, streak, dailies, renascer · D5 passes/dev products, ranking, onboarding com setas, localização · D6 teste em Android barato com 3 contas + tuning · D7 folga/publicação fechada para medir bounce < 60 s, sessão ≥ 8 min e D1 ≥ 10 % antes de qualquer anúncio (BRIEF §7).
7. **VIP com "1.000 V no Correio por dia" → trocar por perk cosmético/QoL** (ex.: 2 pipas de estimação mantidas no renascer, ou cor exclusiva de rabiola). O BRIEF define VIP como "cosmético + QoL, sem vantagem bruta"; renda diária é vantagem bruta.
8. **Árvore do Campinho: manter só na versão mínima** (TrussPart + pipa reparentada por 3 min; "Resgatar da Árvore" 45 R$ continua, pois é ação única determinística). Se D2 atrasar, substituir por "ninguém pegou em 20 s → volta ao dono" (modelo do viral) e levar a árvore para a semana 2.
9. **Cerol e fios:** manter o que o conceito já diz (linha mágica "Linha de Vento", sem postes/fios no mapa, dica de carregamento). Acrescentar: nenhum upgrade pode se chamar "Linha Chilena" ou "Cerol"; nomes de vento (Brisa, Rajada, Trovão). Checar a descrição da loja com a mesma régua.

Itens conferidos e **aprovados** sem mudança: monetização (Vento em Dobro 249, Carretel Automático 179, VIP 449, Kit Pipeiro 299, Rajada no Servidor 149, Vento Forte 99, Resgatar 45, Guardar Streak 39 — todos dentro da escada validada, nenhum item aleatório pago, `PolicyService` não bloqueia nada no BR < 18); offline 25 % com cap de 8 h (12 h VIP); Bar de 5 min com seed global `floor(os.time()/300)`; anti-AFK "linha frouxa"; servidor de 12 (faixa 6–12 do BRIEF para base/renda); jogável 100 % sem chat (balões de emote, banners automáticos com nomes, vibração); mapa gerado por script com seed fixa, zero asset externo; pipas de Parts (2 WedgeParts + varetas + rabiola de 5 Parts + linha Cylinder).

---

## 8. Spec consolidada da v1 (o que o implementador constrói)

**Núcleo:** laje própria (base intocável) com varal de 3–8 vagas; **1 pipa no ar** por vez (a selecionada na carta do HUD; padrão = a mais valiosa). Faixas 0–4 (×0,1 / ×0,5 / ×1,0 / ×1,6 / ×2,5); faixas 3–4 derivam para o círculo de 70 studs sobre o campinho e são as únicas cortáveis. Botão único PUXAR (seção 7, item 1). Enrosco a ≤ 8 studs (rabeio) → duelo de 2 s por "segurar" → perdedor vê a pipa cair em 10 s num ponto aleatório do campinho (raio 30) com marcador Neon → 20 s em que **qualquer um, inclusive o dono**, pega por distância (≤ 7 studs, servidor) → ninguém pegou: árvore 3 min (ou volta ao dono, conforme item 8) . Pipa de Jornal nunca se perde. Escudo de iniciante de 20 min (pode cortar, não perde).

**Selvagens:** 1 a cada 20–40 s, faixa 3–4, cruzam o céu em ~60 s; raridade pela tabela do brasil (Comum 55 % … Mítica 0,1 %); 8 cores aleatórias grátis.

**Economia:** Vento só no servidor; renda = base × faixa × (1 + 0,25 × temporadas) × mutação × passes; carretel com cap de 15 min; offline 25 % cap 8 h; Bar 4 pipas + 1 especial a cada 5 min; Linha L2–L10 = 300 × 2^(n−2); vagas 4ª 2 K … 8ª 500 K; venda automática ao lotar; Renascer "Nova Temporada" 250 K × 3^(n−1) + 1 Épica (item 8 dos enxertos), mantém Linha, vagas, streak, passes, Jornal, pipas de Temporada, Kit e 1 pipa de estimação.

**Eventos (12–15 min, 90–120 s):** Rajada 35 % · Chuva de Pipas 25 % · Vento Dourado 20 % · Virou o Vento 20 %. Primeiro evento forçado aos 4 min de servidor. Festival do Morro: sábado 15h BRT, 40 min, Chuva a cada 8 min, Vento ×2, cor "Festival" exclusiva, publicado como Experience Event.

**Retenção:** streak D1–D7 (D5 Rara, D7 Pipa Raio) + 2 dailies ≤ 5 min; ranking semanal (Rei da Laje / Tesoura de Ouro) em OrderedDataStore 1×/min; badges; funil `LogOnboardingFunnelStepEvent` de 6 passos; "Chamar amigo" com +10 % de Vento para ambos.

**Arquivos (13 Luau + `default.project.json`, ProfileStore via Wally):** `shared/Config`, `shared/Remotes`, `server/init.server`, `server/MapGen`, `server/DataService`, `server/KiteService`, `server/ShopService`, `server/EventService`, `server/MonetizationService`, `server/Leaderboard`, `client/init.client`, `client/KiteRenderer`, `client/HUD`. Zero script no mapa; tags + Attributes; `--!strict`; todo remote com `typeof`/faixa/distância/cooldown.

---

## 9. O que o júri espera medir na semana 1 (antes de 1 Robux em ads)

First play bounce < 60 s baixo (meta: primeiro "CORTOU!" roteirizado aos 40 s contra selvagem Comum), sessão ≥ 8 min, D1 ≥ 10 % (bom: 20 %), e **a taxa de "pegas" por corte** (quantas pipas cortadas são pegas por alguém que não é o dono — é o número que diz se a corrida está funcionando; alvo: 40–60 %). Se a corrida não acontece, o jogo vira Kite Combat com laje, e o júri terá errado.
