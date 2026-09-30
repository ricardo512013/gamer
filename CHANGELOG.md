# Changelog

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
