# Changelog

## 1.5.2

### Correções
- **Criar-Pendrive.cmd falhava no particionamento** ("Nenhum volume foi selecionado", código 0x80070057) em pendrives
  USB mais lentos: o `format` do diskpart vinha antes de o volume aparecer. Agora o diskpart cria as duas partições,
  dá `rescan` e só então formata cada uma (com seleção explícita); se mesmo assim falhar, o particionamento cai para os
  comandos de disco do PowerShell (`Format-Volume`). As etapas anteriores (compilar, montar o Windows PE, gerar o ISO)
  já estavam funcionando.

## 1.5.1

### Correções
- **Criar-Pendrive.cmd travava em "Compilando os controles visuais"** em PCs com antivírus/EDR que seguram
  `powershell.exe -EncodedCommand` (padrão vigiado por segurança). Agora o criador reaproveita a
  `bin\TISuite.Controls.dll` quando ela já existe e confere com o `Controls.cs` e, quando precisa compilar, faz no
  próprio processo (igual ao `dev\Build-Release.ps1`), sem abrir outro PowerShell. Dica: rodar antes o
  `dev\Build-Release.ps1` deixa a DLL pronta e o criador nem compila.

## 1.5.0

### Pendrive de recuperação (dá boot)
- **`Criar-Pendrive.cmd`** (na pasta de código-fonte) cria um pendrive com duas partições: **TI-BOOT** (Windows PE do
  Windows ADK, em pt-BR, teclado ABNT2, com PowerShell, WMI, DISM e BitLocker; boot BIOS e UEFI, Secure Boot pode ficar
  ligado) e **TI-SUITE** (o app e os dados). No boot, o TI Suite abre sozinho em modo recuperação; ao fechar, um menu
  oferece abrir de novo, prompt, reiniciar ou desligar. Os dados de campo do pendrive antigo são guardados e devolvidos.
  Opções: `-SomenteAtualizar` (recopia o app sem formatar), `-SomenteISO` (gera um ISO para máquina virtual),
  `-Boot2023` (boot assinado com a Windows UEFI CA 2023), `-Drivers` (ex.: Intel RST/VMD). O mesmo pendrive continua
  funcionando com o Windows aberto (`Iniciar.cmd`).

### Modo recuperação (nova área, só no boot ou com `-Recovery`)
- Repara o Windows 10/11 do disco **sem reinstalar**. **Reparo automático** encadeia chkdsk, recriação da inicialização,
  desfazer atualização pendente, SFC e DISM, e gera laudo. Separados: **Reparar inicialização** (bcdboot, com cópia do
  BCD antes), **Verificar disco** (chkdsk /f ou /r), **Reparar arquivos do sistema** (SFC e DISM offline, com a imagem
  opcional em `reparo\`), **Desfazer atualização** (pendente ou recente), **Remover driver** de terceiros e **Modo de
  segurança**.
- **Programas (remoção offline):** remove, pelo pendrive, o programa que não sai com o PC ligado — apaga a pasta, os
  atalhos e a entrada na lista do Windows do disco. Runtimes essenciais e antivírus ficam protegidos.
- **Destravar BitLocker** pela chave de recuperação (nunca gravada), saúde do disco antes de reparar, aviso de hibernação
  (Inicialização rápida) e laudo em `laudos\`. O Windows em execução nunca é alterado.
- Núcleo compartilhado `src\Core\06-Windows.ps1` (acha as instalações do Windows nos discos, lê o registro offline, lista
  usuários e volumes de destino), usado pela Recuperação e pelo Backup.

### Backup de usuários (nova área)
- Copia **a pasta inteira de cada usuário** (`C:\Users\<nome>`) para um HD externo ou pendrive, com o Windows aberto
  (Ctrl+8) ou no boot (Ctrl+2, quando o Windows não inicia). Usa robocopy (sem seguir junções; modo de backup como
  administrador), um usuário por vez, com percentual pelo que já foi gravado.
- Origem: o próprio PC ou outro Windows dos discos (no boot, escolha na lista; BitLocker travado avisa para destravar).
  Usuários vêm desmarcados, com tamanho e último uso. Destino em tabela, com aviso de mesmo disco físico, FAT32 e
  pendrive do TI Suite. Não começa se não couber com 5% de folga.
- "Pular temporários e caches" (ligado): Temp, INetCache e caches do Chrome, Edge e Firefox ficam de fora. Cada pasta
  recebe um `LEIA-ME.txt`; Cancelar marca a pasta como INCOMPLETA; resumo por usuário no card e no console; auditoria
  com os usuários e o destino.

### Programas
- A lista agora tem **caixas para marcar**: marque vários e use **Desinstalar marcados** para removê-los de uma vez,
  numa única tarefa. O filtro continua e o contador mostra quantos estão marcados.
- Antes de cada programa, o TI Suite **fecha as janelas, encerra os processos e para os serviços daquele programa** (só
  dentro da pasta de instalação dele) para evitar o aviso de "aplicativo está aberto". Nunca toca em nada fora da pasta
  do programa, nem no Windows/System32/WindowsApps.
- Resumo por programa no fim (Desinstalado / Não desinstalado com o motivo / Cancelado); se algum pedir reinício, aparece
  **Reiniciar agora** (com confirmação, nunca sozinho).
- Ficam **fora do lote** (com cadeado e o motivo): runtimes essenciais (Visual C++, .NET, Windows App Runtime, WebView2)
  e antivírus/segurança. Continuam podendo ser desinstalados **um a um pelo duplo clique**.

### Interface e geral
- `Register-TIWorkspace -Modes Normal|Recovery|Both`: cada área diz em que modo aparece; atalhos Ctrl+1..N conforme as
  áreas do modo. Nova entrada `-Recovery` (ou automático no Windows PE), com título, marca e selo próprios, janela que
  cabe em 1024x768 e 800x600, sem depender de barra de tarefas nem de DWM. No Windows PE: sem UAC (já é administrador),
  sempre portátil, integridade conferida, Logs no Bloco de notas, Exportar e laudos direto nas pastas do pendrive.
- Exportar a lista de uma tabela para `.csv` passa a funcionar também no modo recuperação (grava em `relatorios\`).
- Novos ajudantes `Select-TISaveFile` e `Open-TIFile`, que funcionam no Windows e no Windows PE.
- Build: roda os testes antes de empacotar; `backup\`, `Backup-TI\`, `reparo\`, `wifi\` e o `Criar-Pendrive.cmd` ficam
  fora do pacote.

## 1.4.0

### Perfis de usuários (Manutenção)
- A lista agora mostra **todos os perfis** do computador, não só os numéricos (RM), com uma **caixa para marcar** em
  cada linha. Tudo que pode ser apagado já vem marcado; desmarque o que quiser manter e clique em **Apagar marcados**.
  **Marcar todos**, **Desmarcar todos** e **Sem uso há...** (agora só marca, não apaga) ajudam em listas grandes.
- **Nunca são apagados** (aparecem com cadeado e o motivo): Público, Default e perfis do sistema; **contas locais**
  deste computador; **administradores** (diretos, por grupo do domínio como Domain Admins, ou quando o grupo
  Administradores inclui todos os usuários); o perfil **em uso** e o da conta que está rodando o TI Suite.
  Na dúvida (não deu para confirmar se a conta é administradora), o perfil fica protegido.
- Para saber se uma conta do domínio é administradora, o TI Suite consulta o servidor do domínio (uma consulta por grupo)
  e, sem resposta ou com o app aberto numa conta local, usa o que o Windows guardou do último login do usuário.
  Na hora de apagar, tudo é conferido de novo.
- "Último uso" vem do último login/logoff guardado pelo Windows (o antigo mudava quando o antivírus lia a pasta)
  e mostra há quantos dias; o tamanho não segue mais pontos de junção.
- **Manutenção completa** apaga os perfis **marcados** na lista (respeita o que você desmarcou) e mostra quais antes
  de confirmar. A auditoria registra quais perfis foram apagados.
- Falha ao ler os perfis aparece como erro (antes parecia "nenhum perfil"); cancelar a leitura não deixa a manutenção
  presa para abrir depois.

### Interface (todas as áreas)
- Barras de rolagem escuras de verdade (o tema escuro nunca era aplicado) e visíveis nas tabelas (antes sumiam:
  listas longas sem barra e colunas do Inventário fora de alcance).
- Tabelas com colunas proporcionais à largura, ordenação certa por tamanho, data e tempo (antes "1,5 GB" vinha antes de
  "900 KB") e ordenação mantida ao atualizar. **Botão direito** em qualquer tabela: copiar linhas, copiar a lista ou
  exportar para o Excel (.csv).
- Cards crescem para caber o conteúdo (linhas do Wi-Fi e rodapé das tabelas eram cortados); cards de meia largura em
  duas colunas quando cabe. **Duplo clique** num valor (série, MAC, IP...) copia.
- Botões nunca cortam o texto; Enter aciona o botão com foco; setas navegam na barra lateral; anel de foco visível.
- Janela sem moldura agora redimensiona pelas bordas, tem sombra, maximiza sem cobrir a barra de tarefas, minimiza pelo
  ícone da barra de tarefas e cabe em telas 1366x768. Progresso na barra de tarefas e aviso piscando quando uma tarefa
  termina com a janela em segundo plano.
- Menus e textos apagados com mais contraste; botões Ghost sem clarão ao passar o mouse; interruptor desabilitado
  com aparência de desabilitado; animações que ficavam rodando para sempre (CPU acordada) foram paradas.
- Configurações: valor "false" entre aspas no config.json não liga mais a opção; falha ao gravar (pendrive protegido)
  é avisada.
- Janela: F1 mostra os atalhos; aviso de ocupado mostra percentual e última mensagem; janela maximizada e altura do
  console lembradas; uma janela por vez; UAC recusado oferece modo consulta; unidade de rede mapeada reabre pelo caminho
  de rede; aviso de pendrive protegido ou cheio; Iniciar.cmd explica política que bloqueia scripts.
- Diálogos: senha nova digitada duas vezes; erros de preenchimento aparecem no próprio diálogo; botões com o texto
  inteiro; sem vão abaixo dos botões; listas longas sem barra horizontal. Avisos (toasts) com tempo pelo tamanho do
  texto, pausam com o mouse, fecham com clique, não somem sob um aviso de erro e aparecem perto da janela.
- Console salvo sozinho em `logs\` (um arquivo por dia e por PC), chip **Detalhes**, botão **Logs**, limite de 3000
  linhas, não pula para o fim nem desfaz a seleção enquanto a tarefa roda; contador conta só o que aparece.

### Início, Rede e Programas
- Início: **Copiar resumo** (série, modelo, Windows, IP, MAC, usuário) para o chamado; versão do Windows (24H2) com
  build, usuário realmente conectado e operador; disco com limite em GB e outras unidades; alerta de IP 169.254,
  conflito de IP e falta de gateway; aviso da Inicialização rápida; relatório em `relatorios\` no modo portátil;
  série "To be filled by O.E.M." não aparece mais. Card "Ações rápidas" removido (os atalhos ficam na barra lateral).
- Rede: conclusão do teste em linguagem simples; teste de cada servidor DNS; proxy com senha (407) detectado; colunas
  MAC e Placa, conectadas primeiro, estados em português; **Ativar adaptador**; **Redefinir pilha de rede**; Wi-Fi com
  ponto de acesso (BSSID), perfil e aviso de Localização do Windows 11 24H2; importar redes da pasta `wifi` e
  **Esquecer rede**; leitura dos adaptadores mais rápida.
- Programas: colunas "Instalado em" e "Para" (máquina/usuário); filtro sem acento que não trava com "["; contador certo
  com 1 resultado; Enter no filtro seleciona o primeiro; lista usa a altura da janela; códigos do desinstalador explicados.

### Saúde do PC
- Novo cartão **Estabilidade**: desligamentos inesperados e telas azuis dos últimos 30 dias.
- BitLocker no disco do sistema, firewall de outros fabricantes e serviço do firewall; firewall lido pela política efetiva (GPO).
- Windows Update desativado, pausado ou desligado por política; temperatura por tipo de disco, horas de uso e erros de
  leitura; espaço livre em todas as unidades fixas com limite em GB.
- Fuso horário conferido, com botão **Usar fuso de Brasília**; PC de domínio só sincroniza com o controlador de domínio.
- Sem administrador, a verificação aparece como **Parcial** em vez de "Em ordem".
- Laudo com identificação do equipamento e patrimônio, marcas [X]/[!] e pasta `laudos\` no pendrive.

### Inventário
- Cópia de segurança automática antes de cada gravação (`inventario\backup\`, 10 últimas).
- PC montado reconhecido pela série da placa-mãe, UUID (nova coluna) ou MAC; aviso de hardware alterado e de patrimônio
  repetido; sugestões no campo Local; filtro na lista, lista mais alta e seleção da linha do PC depois de registrar.

### Correções
- **Grave:** planilha do inventário com título ou "sep=;" no topo era lida como vazia e o registro seguinte apagava os
  outros PCs. Agora o cabeçalho é procurado e, sem ele, nada é gravado. Com o Excel aberto, a lista aparecia vazia e o
  registro podia apagar patrimônio, local e observação.
- **Grave:** a limpeza profunda podia seguir pontos de junção ou links dentro dos perfis e apagar arquivos fora deles.
- **Grave:** apagar o `portable.config` (como o README manda para o modo instalado) impedia o app de abrir.
- "Remover senha" não removia nada e informava sucesso; conta administradora não pode mais ficar sem senha.
- "Reiniciar adaptador" podia deixar a placa de rede desativada; "Renovar IP" informava sucesso com IP 169.254.
- "Acertar relógio" mostrava "concluída" e gravava OK na auditoria sem acertar nada, e não corrigia até 2 min.
- Falhas relatadas pela tarefa (programa que não saiu, perfil que não apagou...) não contavam como erro: a auditoria
  gravava OK e o aviso saía verde.
- Maximizar quebrava a janela; a janela não cabia em 1366x768; a barra lateral e os interruptores falhavam quando o
  script era aberto num PowerShell já aberto; pasta com colchetes no nome desligava o modo portátil.
- Auditoria de administrador, senha, ativar/desativar e criação de conta passou a dizer qual conta; a auditoria não se
  perde com o `audit.csv` aberto no Excel.
- "Exigir troca de senha no próximo login" não valia para contas criadas pelo TI Suite nem na senha em lote.
- Lixeira esvaziava só a de quem abriu o app; "Itens recentes" apagava os fixados do Acesso rápido; Windows Update
  podia ficar parado se a limpeza fosse cancelada.
- Inventário: colunas extras sumiam; MAC do Bluetooth/USB e IP de placa virtual; Excel convertia patrimônio/série/IP e
  duplicava PCs; "Coletando..." eterno; textos "no pendrive" no modo instalado.
- Saúde: Windows Server com aviso de fim de suporte do Windows 10; licença ESU lida como ativação; "hoje" para ontem;
  desgaste alto descrito como "com falha"; Defender desatualizado contado duas vezes; resumo cortado.
- Programas: contador " de N programas" sem o número; desinstalação que não removeu terminava em verde.
- Enter não funcionava em botões com foco nem na senha das Configurações; "&" sumia dos textos; texto de exemplo
  ficava sobre o cursor ao entrar com Tab.

### Removido
- Opções "Não pedir confirmação em ações repetidas" (ações perigosas sempre pedem confirmação) e "Limpar o console ao
  iniciar" (não tinha efeito); configuração fantasma KeepGridSort.
- 39 scripts de depuração antigos em `dev\` (com caminhos da máquina do desenvolvedor) e código sem uso.

## 1.3.0

### Novidades
- **Saúde do PC**: discos (saúde, SMART, temperatura, desgaste, espaço livre), Windows (ativação, última atualização,
  reinício pendente), antivírus/Defender e firewall, relógio comparado com a internet e bateria. Selo de estado por cartão,
  resumo do que precisa de ação, laudo em `.txt` e botão **Acertar relógio**.
- **Inventário**: coleta modelo, série, processador, memória, discos, sistema, MACs e IP; técnico informa patrimônio,
  local e observação. Planilha única `inventario\inventario.csv` (`;` e UTF-8 com BOM, abre certo no Excel), sem duplicar PCs.
- Controles visuais pré-compilados em `bin\TISuite.Controls.dll` pelo build (abre mais rápido); sem a DLL, compila na hora.
- Selo **Sem elevação** reabre o app como administrador. Atalhos Ctrl+1 a Ctrl+7, F5 e F12. Busca sem depender de acento.
- Rede: teste de DNS e de acesso à internet, com aviso de portal de login e de proxy.
- `dev\Test-Logic.ps1` testa as regras sem abrir a janela; o build para se houver erro de sintaxe.

### Correções
- Senha padrão em lote alterava contas de administrador; agora ficam de fora, junto com a conta em uso, e a operação
  é bloqueada se o grupo Administradores não puder ser lido.
- "Ativar / desbloquear" não desbloqueava contas bloqueadas por senha errada; agora desbloqueia, e a lista mostra "Bloqueada".
- Administradores lidos também quando o grupo tem conta de domínio apagada (SID órfão).
- Perfis de aluno com sufixo (`12345.000`, `12345.ESCOLA`) passaram a ser encontrados.
- Programas: componentes do sistema e atualizações não aparecem mais; desinstalador de tipo desconhecido abre a própria
  janela (antes rodava escondido com `/S` e travava); NSIS detectado pelo executável; confere se o programa saiu do registro.
- Wi-Fi: leitura em português e inglês, sem confundir "Tipo de rede" com "Tipo de rádio" e resistente a acentos quebrados.
- Ao terminar uma tarefa que dispara outra (ex.: remover perfis e listar de novo), a segunda perdia o resultado e a lista
  não atualizava.
- Cancelar não congela mais a janela e não conta como erro; a auditoria registra "CANCELADA".
- Erros fatais passaram a ser gravados no `exceptions.log` (o registro falhava em silêncio).
- Arquivos em UTF-8 com BOM: o PowerShell 5.1 lia alguns em ANSI e mostrava texto quebrado (ex.: "Â·" no Início).

### Interface
- Interruptor ficava preso do lado errado a partir do segundo clique.
- Enter não funcionava nas caixas de texto (senha, nova conta, dias); nas confirmações perigosas, o Enter confirmava
  mesmo com o foco em Cancelar. "Não pedir de novo" era gravado mesmo ao cancelar.
- Contas: o contador ficava escondido atrás de "Senha padrão (lote)" e "Remover administrador" saía cortado; botões agora
  ficam em faixas que quebram linha sozinhas, em todas as áreas.
- Cards esticados tinham a linha divisória curta; descrições longas atravessavam a divisória.
- Valores longos eram cortados no meio; agora terminam em reticências e mostram o texto inteiro ao passar o mouse.
- Texto de exemplo da busca nascia fora da caixa, com fundo de outra cor, e não focava o campo ao clicar.
- Texto dos botões levemente fora do centro; aviso de "processando" descentralizado quando o nome da tarefa mudava.
- Ctrl+R não recarregava nada; marca e busca da barra lateral com ordem fixa; tabelas sem linha pré-selecionada.
- Barra de disco/memória fica amarela ou vermelha quando falta espaço; dicas ao passar o mouse no tema escuro;
  diálogos com borda visível; mensagens longas rolam dentro da janela; console com etiquetas em português.
- Manutenção completa sempre pede confirmação (apaga perfis); descrição da limpeza profunda corrigida (não usa mais Prefetch).
- Acentuação e textos revisados em toda a interface.

## 1.2.0
### Seguranca
- Senha padrao da escola nao e mais gravada no `config.json` (fica so em memoria); config antigo com senha e limpo ao iniciar.
- Senha padrao em lote mostra a lista de contas afetadas antes de aplicar; opcao "Exigir troca de senha no proximo login".
- Verificacao de integridade (`manifest.sha256`) antes do UAC; `dev\Build-Release.ps1` gera o pacote sem `dev\`.
- Trilha de auditoria `audit.csv` para toda acao administrativa.

### Correcoes
- Lixeira so e esvaziada quando o item "Esvaziar Lixeira" esta incluido (antes esvaziava sempre).
- Espaco liberado passou a ser o realmente liberado (antes somava o tamanho do scan mesmo com falha).
- Desinstalacao: detecta MSI/Inno/NSIS, aceita caminho sem aspas e encerra desinstaladores presos apos 10 min.
- Limpeza de Chrome/Edge cobre todos os perfis (Profile 1, 2...); Prefetch removido da limpeza.
- Windows Update: o servico e parado durante a limpeza de `SoftwareDistribution\Download` e religado ao final.
- `$home` (variavel somente-leitura do PowerShell) deixou de ser sobrescrito na varredura.
- Confirmacao de remocao de perfis mostra a data do ultimo uso.

### Interface
- Modo de escala (DPI) padrao "compat": layout identico em notebooks com zoom 125%/150%; opcao "Texto nitido".
- Tabelas: linhas alternadas, ultima coluna preenche o espaco, estado vazio com mensagem, scrollbar escura (melhor esforco).
