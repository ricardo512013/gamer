# TI Suite — Suporte Escolar

Painel portátil para a equipe de TI cuidar dos computadores da escola: limpeza e perfis de usuários,
saúde do PC, inventário, programas, contas locais e rede. Roda direto do pendrive, sem instalar nada.

## Como usar (qualquer PC)

1. Copie a pasta inteira para o pendrive.
2. No computador, abra `Iniciar.cmd`.
3. Aceite o aviso do Windows (UAC): o TI Suite precisa de administrador para mexer em perfis, contas, programas e rede.

Se abrir sem elevação, o selo **Sem elevação** na barra lateral reabre o app como administrador.
Se o UAC for recusado, dá para abrir só para consulta. Abrir de novo com o app já aberto traz a janela existente.
Aberto de uma unidade de rede, o app se reabre pelo caminho de rede; pendrive protegido ou cheio gera aviso, e o
`Iniciar.cmd` explica quando a política do computador bloqueia scripts.

### Requisitos

- Windows 10 ou 11 com o Windows PowerShell 5.1 (já vem no Windows).
- Nada para instalar. A versão empacotada traz os controles visuais pré-compilados em `bin\` e abre mais rápido.

### Sem pendrive (instalado na máquina)

Apague o arquivo `portable.config`. A configuração, os logs e o inventário passam a ficar em `%LOCALAPPDATA%\TI-Suite`.

## Áreas

| Atalho | Área | Para que serve |
|---|---|---|
| Ctrl+1 | Início | Disco, memória, identificação do equipamento, rede e **Copiar resumo** para o chamado |
| Ctrl+2 | Saúde do PC | Windows e atualizações, discos, estabilidade, antivírus, firewall e BitLocker, relógio e fuso, bateria |
| Ctrl+3 | Manutenção | Perfis de usuários (com caixas para marcar), limpeza profunda e manutenção completa em um passo |
| Ctrl+4 | Programas | Lista e desinstala programas, sem janelas quando o fabricante permite |
| Ctrl+5 | Contas | Senhas, desbloqueio, ativar/desativar, administradores e senha padrão em lote |
| Ctrl+6 | Rede | Adaptadores, Wi-Fi, teste de conexão (DNS, internet, portal de login e proxy) e reparo |
| Ctrl+7 | Inventário | Registra o computador numa planilha única no pendrive |

### Saúde do PC

Uma verificação (10 a 30 segundos) e cada cartão mostra um selo: **Em ordem**, **Atenção**, **Crítico** ou **Parcial**
(sem administrador, SMART, capacidade da bateria e BitLocker ficam de fora e o resumo avisa). O resumo no topo lista só
o que precisa de ação. **Salvar laudo** gera um `.txt` com fabricante, modelo, série e patrimônio (do inventário) e
marca [X] crítico e [!] atenção; no modo portátil sugere a pasta `laudos\` do pendrive.

- **Windows:** versão, ativação (OEM, varejo, KMS ou MAK; ignora licenças ESU), última atualização, Windows Update
  desativado ou pausado e reinício pendente.
- **Discos:** saúde, SMART, temperatura (limite por tipo: HD, SSD, NVMe), desgaste, horas de uso, erros de leitura e
  espaço livre em todas as unidades fixas (no disco do sistema, alerta abaixo de 10 GB).
- **Estabilidade:** desligamentos inesperados e telas azuis nos últimos 30 dias.
- **Proteção:** antivírus e definições, proteção em tempo real, firewall (política efetiva, serviço e firewall de
  outros fabricantes) e BitLocker no disco do sistema.
- **Data e hora:** relógio comparado com a internet, fuso horário e fonte de horário. **Acertar relógio** sincroniza
  pelo Windows e, fora do domínio, ajusta pela internet quando duas fontes concordam; em PC de domínio só sincroniza
  com o controlador de domínio. **Usar fuso de Brasília** aparece quando o fuso está fora do Brasil.
- **Bateria (notebooks):** carga, capacidade em relação à original e ciclos.

### Perfis de usuários (Manutenção)

A lista mostra os perfis do computador com uma caixa em cada linha. Todo perfil que pode ser apagado já vem
**marcado**: desmarque (clique na caixa ou use Espaço) os que quiser manter e clique em **Apagar marcados**.
**Marcar todos**, **Desmarcar todos** e **Sem uso há...** (marca só os parados há mais de X dias) ajudam em listas grandes.

Nunca podem ser apagados (aparecem com cadeado e o motivo):

- **Público**, **Default** e os perfis do sistema;
- **contas locais** deste computador (ex.: Administrador, Professor, TI);
- **administradores**: membros do grupo Administradores, diretos ou por grupo do domínio (ex.: Domain Admins);
- o perfil **em uso** (usuário conectado) e o da conta que está rodando o TI Suite.

Na dúvida, o perfil fica protegido. Para saber se uma conta do domínio é administradora, o TI Suite pergunta ao
servidor do domínio e, sem resposta, usa o que o Windows guardou do último login daquele usuário. Na hora de apagar,
tudo é conferido de novo. A **Manutenção completa** apaga os perfis marcados na lista e faz a limpeza profunda.

### Inventário

Coleta fabricante, modelo, número de série, UUID, processador, memória, discos, sistema, MACs (cabo e Wi-Fi) e IP.
O técnico preenche patrimônio, local (o campo sugere os locais já usados) e observação e clica em **Registrar no inventário**.

- Arquivo: `inventario\inventario.csv` na pasta do app (modo portátil). Abre direto no Excel em português.
- O mesmo computador nunca é duplicado. Ele é reconhecido pelo número de série; em PC montado ("To be filled by O.E.M."),
  pela série da placa-mãe, pelo UUID ou pelo MAC; por último, pelo nome. Renomear não duplica, e PCs diferentes com o
  mesmo nome não se sobrescrevem.
- Antes de cada gravação, uma cópia vai para `inventario\backup\` (ficam as 10 últimas).
- Se a planilha não puder ser lida (cabeçalho apagado, pendrive removido...), o app avisa e não grava nada até
  **Atualizar** funcionar. Colunas acrescentadas na planilha (ex.: "Situação") são mantidas.
- Avisa antes de apagar patrimônio, local ou observação já salvos, quando o patrimônio já está em outro PC e quando o
  hardware mudou desde o último registro.
- Patrimônio, série e IP vão como texto para o Excel (`="000123"`), para os zeros à esquerda não sumirem.
- O Excel pode ficar aberto para consulta, mas feche-o antes de registrar ou remover.

### Rede

- Adaptadores com MAC e placa, conectados primeiro; alerta de IP automático 169.254 e falta de gateway.
  **Ativar adaptador**, **Reiniciar adaptador**, **Renovar IP**, **Limpar cache de DNS** e **Redefinir pilha de rede**
  (exige reiniciar o PC).
- **Testar conexão** confere cada servidor DNS, a internet, portal de login e proxy, e termina com uma conclusão em
  linguagem simples.
- **Redes Wi-Fi da escola:** crie a pasta `wifi` ao lado do `TI-Suite.ps1` e coloque nela os perfis `.xml` exportados de
  um computador já configurado (`netsh wlan export profile name="ESCOLA" folder=.`). Em **Rede > Wi-Fi > Importar da
  pasta wifi**, cada arquivo vira uma rede salva para todos os usuários. Um perfil exportado com `key=clear` traz a
  senha em texto puro: guarde o pendrive com cuidado (a pasta `wifi` nunca entra no pacote do build).
  **Esquecer rede** apaga uma rede salva (útil quando a senha mudou). No Windows 11 24H2, a leitura do Wi-Fi exige a
  Localização ligada (Configurações > Privacidade e segurança > Localização).

### Contas

- **Redefinir senha:** digite a senha em "Nova senha" e "Repita a senha"; **Aplicar senha** só libera quando as duas
  são iguais. Senhas novas (nova conta, senha padrão) também são digitadas duas vezes.
- **Remover senha:** só em contas que não são administradoras. A conta passa a entrar sem senha, só no teclado do
  computador (o Windows não aceita conta sem senha pela rede).
- **Exigir troca de senha no próximo login** vale para a senha padrão em lote e para contas criadas pelo TI Suite.
  Com essa opção, a senha deixa de ser "nunca expira" e passa a seguir a validade do Windows.

### Limpeza profunda

- Nunca segue pontos de junção ou links: um link dentro de uma pasta limpa é apagado como link, e uma pasta com link
  no caminho fica de fora.
- Esvazia a Lixeira de todas as contas em todas as unidades fixas (só com o item Lixeira incluído).
- Em "Itens recentes", apaga só os atalhos recentes, sem mexer no que está fixado no Acesso rápido ou nas listas de atalhos.

## Tabelas

- Clique no cabeçalho para ordenar (tamanhos e datas ordenam pelo valor real).
- **Botão direito:** copiar linhas, copiar a lista inteira ou exportar para o Excel (`.csv`).
- **Duplo clique** num valor dos cartões (série, MAC, IP...) copia para a área de transferência.

## Atalhos

| Tecla | Ação |
|---|---|
| Ctrl+1 a Ctrl+7 | Trocar de área |
| Ctrl+R ou F5 | Atualizar a área aberta |
| Ctrl+F | Buscar ferramenta (funciona com ou sem acento) |
| Ctrl+L | Limpar o console |
| Ctrl+E | Exportar o console |
| F12 | Mostrar ou ocultar o console |
| F1 | Mostrar os atalhos |
| Setas na barra lateral | Trocar de área (Enter abre) |

Nas janelas de confirmação de ações que apagam dados, o foco começa em **Cancelar** e o Enter não confirma sozinho.

## Dicas de uso no laboratório

- **Troca de turma:** Manutenção > confira os perfis marcados > Executar manutenção completa (apaga os perfis marcados e limpa caches e Lixeira).
- **Perfis protegidos** (Público, contas locais, administradores e quem está conectado) nunca são apagados.
- **Senha padrão em lote** altera só contas numéricas (RM) ativas. Administradores e a conta em uso nunca são alterados.
  Se o app não conseguir ler o grupo Administradores, a operação é bloqueada.
- A senha padrão fica só na memória durante a sessão; nunca é gravada no pendrive.
- **Conta bloqueada** por senhas erradas aparece como "Bloqueada" em Contas: use **Ativar / desbloquear**.

## Console e auditoria

Toda ação administrativa vai para `logs\audit.csv` (data, computador, operador, ação, resultado e detalhe: ações de
perfis e contas registram quais contas). Senhas nunca são registradas. Uma falha relatada pela tarefa conta como erro
(ERRO na auditoria e aviso vermelho); fechar o app no meio de uma ação administrativa grava INTERROMPIDA. Se o
`audit.csv` estiver aberto no Excel, a linha fica guardada e é gravada assim que o arquivo for liberado, ou ao fechar o
app (em `audit-pendente-*.csv`, se continuar bloqueado). Erros inesperados aparecem no console e ficam em `logs\exceptions.log`.

O console mostra as últimas 3000 linhas. Tudo, inclusive os detalhes técnicos, é salvo sozinho em
`logs\console-AAAA-MM-DD-<PC>.txt` (um arquivo por dia e por computador); Ctrl+L só limpa a tela. O chip **Detalhes**
mostra as mensagens técnicas e o botão **Logs** abre a pasta com a auditoria e os consoles salvos.

## Configurações

As mudanças valem ao clicar em **Salvar** (ou Enter); Esc descarta. A janela mostra o operador (quem roda o TI Suite) e
a sessão (quem está conectado ao Windows), onde ficam configuração, logs e inventário, e tem o botão **Abrir pasta de
logs**. O TI Suite lembra se a janela estava maximizada e a altura do console.

## Tela com zoom (125% / 150%)

Por padrão o Windows escala a janela inteira: o layout fica igual em qualquer notebook, com o texto um pouco mais suave.
Para texto nítido, ligue **Texto nítido em telas com zoom** em Configurações (vale na próxima abertura; pode desalinhar o layout).

## Distribuição e integridade

Para gerar o pacote de distribuição, rode no Windows PowerShell:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\Build-Release.ps1
```

O build confere a sintaxe, roda os testes das regras (e para se algum falhar), compila `bin\TISuite.Controls.dll` e cria
`dist\TI-Suite-vX.Y.Z.zip` sem a pasta `dev\` e sem dados de campo (logs, inventário, laudos, relatórios e `wifi\`),
com o `manifest.sha256` dentro do pacote. Ao abrir, o TI Suite confere o código (`.ps1`, `.cs`, `.cmd` e `bin\`) com o
manifesto antes de pedir o UAC; apagar `portable.config`, README ou CHANGELOG não trava a abertura.
O manifesto detecta pendrive corrompido e alteração casual; para proteção forte, use BitLocker To Go.

Para conferir tudo sem mexer no computador: `.\TI-Suite.ps1 -SelfTest` (interface) e `.\dev\Test-Logic.ps1` (regras).

## Estrutura

```
Iniciar.cmd               abre o app (modo STA)
TI-Suite.ps1              entrada: integridade, UAC e carregamento
portable.config           presença = modo portátil
config.json               preferências (sem senhas)
bin\                      DLL dos controles, gerada pelo build
src\Core\Controls.cs      controles visuais (C#)
src\Core\00-05*.ps1       tema, diálogos, console, tarefas em segundo plano e janela principal
src\Workspaces\*.ps1      uma área por arquivo
inventario\               planilha do inventário e cópias de segurança (modo portátil)
logs\                     auditoria, consoles salvos e erros (modo portátil)
laudos\                   laudos da Saúde do PC (modo portátil)
relatorios\               relatórios do Início (modo portátil)
wifi\                     perfis de Wi-Fi para importar (você cria; nunca vai para o pacote)
dev\                      build (Build-Release.ps1) e testes das regras (Test-Logic.ps1)
```
