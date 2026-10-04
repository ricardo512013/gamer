# 🪐 Steal a Planet — jogo completo para Roblox

Jogo de **roubar e defender** (o gênero de *Steal a Brainrot* e *Steal an Egg*) com tema próprio:
planetas, estrelas, buracos negros e galáxias com carinhas fofas. Mapa, sistemas, interface e
monetização estão todos prontos.

> **Arquivo pronto para abrir no Roblox Studio:** [`build/StealAPlanet.rbxl`](build/StealAPlanet.rbxl)
> (o mapa já vem montado; é só abrir e apertar **Play**).

---

## 1. Por que este jogo (pesquisa de out/2026)

| O que a pesquisa mostrou | Fonte |
|---|---|
| As categorias que mais crescem em 2026: **tycoons de roubar e defender**, simuladores de crescer/idle, terror co-op, anime e moda. | [atriarch.com](https://www.atriarch.com/best-roblox-games-to-play-in-2026/), [game-ace.com](https://game-ace.com/blog/roblox-trends-in-gaming/) |
| *Steal a Brainrot* passou de **68 bilhões de visitas** e faturou cerca de **US$ 64 milhões**. | [Wikipedia](https://en.wikipedia.org/wiki/Steal_a_Brainrot), [Bloomberg](https://www.bloomberg.com/news/articles/2026-03-24/roblox-s-hit-game-steal-a-brainrot-battles-its-many-imitators) |
| *Steal An Egg* (lançado em 25/07/2026) chegou a **~3 milhões de jogadores e 3,1 bilhões de visitas em menos de 2 meses**. | [atriarch.com](https://www.atriarch.com/best-roblox-games-to-play-in-2026/) |
| Tycoons têm a **2ª maior fatia de jogadores simultâneos** do Roblox e retêm melhor que quase tudo, porque o ciclo dá motivo para voltar no dia seguinte. | [endsights.com](https://endsights.com/roblox-tycoon-games) |
| O que dá mais Robux: passes para ganhos permanentes + produtos consumíveis em pacotes com uma opção "melhor custo-benefício". | [generalistprogrammer.com](https://generalistprogrammer.com/tutorials/roblox-game-monetization-complete-revenue-strategy-guide) |

**Por que planetas:** crianças adoram vídeos de planetas (comparação de tamanhos, "Sol vs Buraco
Negro", Solarballs). Por isso a escada de raridade é **Pedrinha → Lua → Terra → Sol → Estrela de
Nêutrons → Buraco Negro → TON 618 → Multiverso**, que qualquer criança entende na hora. Além disso,
planetas ficam bonitos feitos só de peças do Roblox, então você **não precisa enviar nenhum modelo
3D** para publicar.

> ⚠️ **Sobre copiar:** os donos de *Steal a Brainrot* já abriram processos contra cópias "quase
> idênticas". Este projeto usa o mesmo **gênero**, com nome, tema, arte e código **originais**. Não
> coloque nomes, imagens ou personagens de outros jogos nele.

---

## 2. O que já está pronto

**Mapa (gerado por código, ~1.850 peças)**
- 8 bases com paredes de vidro, laser de trava, placa com o nome do dono, 20 pedestais (10 liberados
  no começo), placas verdes de coleta, placa de trava e ponto de spawn.
- **Esteira Cósmica** de 320 studs com portais nas pontas e arco com o título.
- Loja de ferramentas, Índice de planetas, Loja (Robux), Altar de Rebirth, 3 placares globais, lobby
  com quadro de boas-vindas, postes de luz, asteroides e planetas gigantes no céu.
- Iluminação espacial: céu noturno estrelado, atmosfera roxa, bloom.

**Ciclo principal**
- 30 planetas em 8 raridades, construídos com peças, com rostinho, anéis, faixas, brilho e partículas.
- 4 mutações: **Ouro x1,5**, **Diamante x2**, **Arco-íris x3**, **Galáxia x5**.
- **Esteira:** um planeta sai do portal a cada 2 s. Compra com dinheiro (E) ou com Robux nos raros (F).
- **Base:** cada planeta rende $/s. O dinheiro acumula no pedestal e você pisa na placa verde para coletar.
- **Roubo:** segure E num planeta de uma base **destrancada** e corra até a sua (você fica 30% mais
  lento). Se levar bastão, for congelado, morrer, tocar no laser ou demorar mais de 90 s, o planeta
  volta voando para o dono.
- **Trava:** pise na placa vermelha para trancar a base por 60 s (+5 s por rebirth). Quando o jogador
  entra, a base já fica trancada por 30 s.
- **Vender:** o dono segura E no próprio planeta e recebe 50% do preço.
- **Depósito:** planetas que não cabem na base ficam guardados e entram sozinhos quando abre vaga.

**Progressão e retenção**
- **Rebirth:** zera dinheiro e planetas; em troca dá +0,5x de dinheiro, +2 vagas, +5 s de trava e
  libera ferramentas.
- **Índice:** cada planeta descoberto dá +1% de dinheiro e cada variante de mutação, +0,5%.
- **Recompensa diária** com sequência de 7 dias (Rare, Epic e Legendary nos dias 3, 5 e 7).
- **Presentes por tempo de jogo** (2, 5, 10, 15, 25, 40 e 60 min) para aumentar o tempo de sessão.
- **Ganhos offline:** 3 h normalmente, 12 h com passe.
- **Eventos cósmicos** a cada ~7 min, mudando a iluminação: Chuva de Meteoros, Erupção Solar,
  Supernova, Buraco Negro (renda x2) e Noite Galáctica.
- **Tutorial** com seta luminosa até a esteira e depois até a base.
- **Bônus de amigos** (+10% por amigo no servidor, até +50%) e **bônus de grupo** (+10%).
- Ao fazer 8 min de jogo, aparece o pedido para favoritar o jogo.
- Códigos, placares globais (mais dinheiro ganho, mais roubos, mais rebirths) e leaderstats.
- Anúncios para o servidor inteiro quando sai um planeta raro na esteira, quando alguém rouba um
  Lendário ou faz rebirth.

**Ferramentas:** Bastão Espacial (grátis), Bobina de Velocidade, Bobina de Gravidade, Raio
Congelante (Rebirth 1) e Capa de Invisibilidade (Rebirth 2).

**Monetização:** 6 passes, 7 produtos na loja e 4 produtos de "compra instantânea" na esteira (ver seção 4).

**Admin:** painel com "ADMIN ABUSE" (chuva de planetas raros + sorte x5), eventos locais ou em
**todos os servidores**, sorte do servidor, criar planetas e dinheiro de teste.

**Técnico**
- O servidor decide tudo (o cliente só pede); há limite de pedidos por segundo e checagem de distância.
- Salvamento com `UpdateAsync`, trava de sessão (dois servidores nunca gravam o mesmo jogador),
  autosave a cada 90 s, salvamento ao sair e ao fechar o servidor.
- Compras com Robux são processadas uma única vez, mesmo que o Roblox reenvie o recibo.
- A interface se ajusta sozinha a celular, tablet e PC.

---

## 3. Como abrir e testar

1. Abra **`build/StealAPlanet.rbxl`** no Roblox Studio.
2. Aperte **Play**. No Studio:
   - todas as compras com ID `0` saem **de graça** para você testar (`Config.TestPurchasesInStudio`);
   - o botão **⚙️ Admin** aparece para você;
   - sem "API Services" ligado, os dados são temporários (aparece um aviso amarelo no Output, e isso é normal).
3. Para testar o roubo: **Test → Clients and Servers → 2 Players**.

### Antes de publicar
1. **File → Publish to Roblox**.
2. **Game Settings → Places → Max Players = 8** (são 8 bases).
3. **Game Settings → Security → Enable Studio Access to API Services = ON** (para testar o salvamento no Studio).
4. Crie os passes e produtos (seção 4) e cole os IDs em `ReplicatedStorage > Shared > Config`.
5. Se tiver um grupo, coloque o ID em `Config.GroupId`.

---

## 4. Monetização (crie no Creator Dashboard e cole os IDs no `Config`)

**Passes** (`Config.GamePasses`)

| Chave | Item | Preço sugerido |
|---|---|---|
| VIP | x1,5 de dinheiro + tag [VIP] no chat | 299 |
| DoubleCash | 2x de dinheiro | 249 |
| AutoCollect | coleta automática | 149 |
| DoubleLock | trava dura o dobro | 129 |
| SuperSpeed | +8 de velocidade | 99 |
| OfflineEarnings | 12 h de ganhos offline | 99 |

**Produtos** (`Config.Products`)

| Chave | Item | Preço sugerido |
|---|---|---|
| CashSmall / Medium / Large / Huge | 10 min / 1 h / 6 h / 24 h da **sua** renda (o valor cresce junto com o jogador) | 19 / 79 / 249 / 699 |
| ServerLuck | sorte x2 para o servidor todo por 15 min (o tempo acumula e todo mundo vê quem comprou) | 99 |
| CosmicEvent | começa um evento cósmico na hora | 149 |
| RemoteLock | tranca a base de qualquer lugar | 25 |
| BuyLegendary / BuyMythic / BuyCosmic / BuySecret | botão **F** na esteira: compra aquele planeta raro com Robux | 79 / 199 / 499 / 999 |

Os produtos de **sorte do servidor** e de **evento** são os que mais vendem nesse gênero: um jogador
paga, o servidor inteiro ganha, e o nome de quem comprou aparece para todos.

---

## 5. Como deixar o jogo com a sua cara

- **Valores:** tudo fica em `Shared/Config.luau` (dinheiro inicial, trava, rebirth, eventos,
  ferramentas, recompensas e códigos).
- **Planetas:** `Shared/Planets.luau` (preço, renda, raridade e visual). Para adicionar um, basta
  copiar uma linha `add(...)`.
- **Modelos próprios:** crie a pasta `ReplicatedStorage/PlanetModels` e coloque um Model com o nome
  do id (por exemplo, `Earth`) e com PrimaryPart. Ele substitui o modelo feito de peças.
- **Editar o mapa:** o mapa já está no arquivo, em `Workspace > Map`, e pode ser editado à vontade
  (mantenha os nomes das peças das bases). Para gerar de novo, apague `Map` e rode no Command Bar:
  `require(game.ServerScriptService.Server.Services.MapBuilder).Build(workspace)`
- **Música:** `Config.Sounds.Music = "rbxassetid://..."`.
- **Códigos:** `Config.Codes` (chaves em MAIÚSCULAS).

---

## 6. Plano para crescer (o código não garante sucesso; a divulgação conta muito)

Ninguém consegue garantir que um jogo vai explodir. O que os sucessos do gênero têm em comum:

1. **Ícone e thumbnail:** um planeta fofo e enorme, um personagem correndo com ele na cabeça e um
   buraco negro raro brilhando. Faça 3 versões e use o teste A/B de thumbnails do Roblox.
2. **Título e descrição:** "Steal a Planet 🪐 [UPDATE 1]". Ponha as palavras que as pessoas buscam:
   *steal, planet, black hole, tycoon*.
3. **TikTok / YouTube Shorts todos os dias:** "roubei o BURACO NEGRO dele", "achei o TON 618
   secreto", "admin abuse". Os eventos e os anúncios de raros já foram pensados para render clipes.
4. **Admin abuse no fim de semana:** marque horário no Discord e na descrição e use o painel ⚙️. Isso
   lota servidores.
5. **Metas de likes → códigos novos:** "10K likes = código BLACKHOLE".
6. **Atualizações semanais:** novos planetas e mutações (é só mexer no `Planets.luau`), um evento
   novo e um rebirth novo.
7. **Anúncios patrocinados:** comece com pouco depois que o D1 (retenção no dia seguinte) passar de
   ~15%. Acompanhe no **Creator Dashboard → Analytics**: retenção D1/D7, tempo de sessão e conversão
   de pagantes.
8. **Tradução:** ligue a tradução automática (Localization). O texto está em inglês para alcançar o
   público global e o Roblox traduz para PT-BR, ES etc.

---

## 7. Estrutura do projeto (Rojo)

```
default.project.json        Projeto Rojo
src/shared/                 ReplicatedStorage.Shared   (Config, Planets, Mutations, Economy, PlanetModel, Net...)
src/server/Main.server.luau ServerScriptService.Server.Main
src/server/Services/        Data, Map, Plot, Belt, Steal, Tool, Event, Progression, Monetization, Leaderboard, Admin, Sync...
src/client/                 StarterPlayerScripts.Client (Controllers + UI)
tests/                      testes de lógica e de modelos (Lune)
tools/build.sh              testes, compilação e mapa embutido -> build/StealAPlanet.rbxl
```

Para trabalhar com Rojo: `rojo serve` + plugin do Rojo no Studio. Para gerar o `.rbxl`, rode
`./tools/build.sh` (precisa do `rojo` e do `lune`).

## 8. Verificação feita

- **Tipos:** todos os 35 arquivos (~8.300 linhas) estão em `--!strict` e passam no `luau-lsp analyze` com as
  definições atuais da API do Roblox (out/2026), com **0 erros**. Essa checagem pega nome de
  propriedade, Enum e método errados, inclusive APIs obsoletas.
- **Lógica:** `tests/run.luau` tem **770 testes passando** (sorteios, mutações, formatação,
  economia, validação de dados salvos, configuração e simulação de ritmo).
- **Modelos:** `tests/smoke.luau` monta os **150 modelos** de planeta (30 × 5 mutações) com
  instâncias reais e confere soldas, colisão e etiquetas.
- **Mapa:** é montado de verdade pelo `tools/bake-map.luau`, e o arquivo final é aberto de novo
  para conferir.

Simulação de ritmo (jogador ideal comprando sempre o melhor): 1º rebirth em ~10 min, 3º em ~40 min,
6º em ~3,5 h. Um jogador real leva mais ou menos o dobro.
