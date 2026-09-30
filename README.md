# TI Suite — Suporte Escolar

Painel portátil para a equipe de TI cuidar dos computadores da escola: limpeza e perfis de alunos,
saúde do PC, inventário, programas, contas locais e rede. Roda direto do pendrive, sem instalar nada.

## Como usar (qualquer PC)

1. Copie a pasta inteira para o pendrive.
2. No computador, abra `Iniciar.cmd`.
3. Aceite o aviso do Windows (UAC): o TI Suite precisa de administrador para mexer em perfis, contas, programas e rede.

Se abrir sem elevação, o selo **Sem elevação** na barra lateral reabre o app como administrador.

### Requisitos

- Windows 10 ou 11 com o Windows PowerShell 5.1 (já vem no Windows).
- Nada para instalar. A versão empacotada traz os controles visuais pré-compilados em `bin\` e abre mais rápido.

### Sem pendrive (instalado na máquina)

Apague o arquivo `portable.config`. A configuração, os logs e o inventário passam a ficar em `%LOCALAPPDATA%\TI-Suite`.

## Áreas

| Atalho | Área | Para que serve |
|---|---|---|
| Ctrl+1 | Início | Disco, memória, identificação do equipamento, rede e atalhos |
| Ctrl+2 | Saúde do PC | Windows (ativação, atualizações, reinício pendente), discos, antivírus e firewall, relógio e bateria |
| Ctrl+3 | Manutenção | Perfis de alunos (RM), limpeza profunda e manutenção completa em um passo |
| Ctrl+4 | Programas | Lista e desinstala programas, sem janelas quando o fabricante permite |
| Ctrl+5 | Contas | Senhas, desbloqueio, ativar/desativar, administradores e senha padrão em lote |
| Ctrl+6 | Rede | Adaptadores, Wi-Fi, teste de conexão (DNS, internet, portal de login e proxy) e reparo |
| Ctrl+7 | Inventário | Registra o computador numa planilha única no pendrive |

### Saúde do PC

Uma verificação (10 a 30 segundos) e cada cartão mostra um selo: **Em ordem**, **Atenção** ou **Crítico**.
O resumo no topo lista só o que precisa de ação. **Salvar laudo** gera um `.txt` para anexar ao chamado.

- **Discos:** saúde informada pelo Windows, previsão de falha (SMART), temperatura, desgaste de SSD e espaço livre.
- **Windows:** versão, ativação (OEM, varejo, KMS ou MAK), última atualização instalada e reinício pendente.
- **Proteção:** antivírus ativo e atualizado, proteção em tempo real do Defender e firewall nos três perfis.
- **Data e hora:** compara o relógio com a internet. **Acertar relógio** sincroniza pelo Windows e, se não resolver,
  ajusta pelo horário da internet quando duas fontes concordam. O fuso não é alterado.
- **Bateria (notebooks):** carga, capacidade em relação à original e ciclos.

### Inventário

Coleta fabricante, modelo, número de série, processador, memória, discos, sistema, MACs (cabo e Wi-Fi) e IP.
O técnico preenche patrimônio, local e observação e clica em **Registrar no inventário**.

- Arquivo: `inventario\inventario.csv` na pasta do app (modo portátil). Abre direto no Excel em português.
- O mesmo computador nunca é duplicado: registrar de novo atualiza a linha (pelo número de série ou, sem série, pelo nome).
- Se o Excel estiver com a planilha aberta, feche-a antes de registrar.

## Atalhos

| Tecla | Ação |
|---|---|
| Ctrl+1 a Ctrl+7 | Trocar de área |
| Ctrl+R ou F5 | Atualizar a área aberta |
| Ctrl+F | Buscar ferramenta (funciona com ou sem acento) |
| Ctrl+L | Limpar o console |
| Ctrl+E | Exportar o console |
| F12 | Mostrar ou ocultar o console |

Nas janelas de confirmação de ações que apagam dados, o foco começa em **Cancelar** e o Enter não confirma sozinho.

## Dicas de uso no laboratório

- **Troca de turma:** Manutenção > Executar manutenção completa (remove perfis de alunos e limpa caches e Lixeira).
- **Perfis em uso** (aluno conectado) nunca são removidos. Perfis de contas administradoras ficam fora da lista.
- **Senha padrão em lote** altera só contas numéricas (RM) ativas. Administradores e a conta em uso nunca são alterados.
  Se o app não conseguir ler o grupo Administradores, a operação é bloqueada.
- A senha padrão fica só na memória durante a sessão; nunca é gravada no pendrive.
- **Conta bloqueada** por senhas erradas aparece como "Bloqueada" em Contas: use **Ativar / desbloquear**.

## Auditoria

Toda ação administrativa vai para `logs\audit.csv` (data, computador, operador, ação, resultado).
Senhas nunca são registradas. Erros inesperados ficam em `logs\exceptions.log`.

## Tela com zoom (125% / 150%)

Por padrão o Windows escala a janela inteira: o layout fica igual em qualquer notebook, com o texto um pouco mais suave.
Para texto nítido, ligue **Texto nítido em telas com zoom** em Configurações (vale na próxima abertura; pode desalinhar o layout).

## Distribuição e integridade

Para gerar o pacote de distribuição, rode no Windows PowerShell:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\Build-Release.ps1
```

O build confere a sintaxe, compila `bin\TISuite.Controls.dll`, grava o `manifest.sha256` e cria `dist\TI-Suite-vX.Y.Z.zip`
sem a pasta `dev\`. Ao abrir, o TI Suite confere os arquivos com o manifesto antes de pedir o UAC.
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
inventario\               planilha do inventário (modo portátil)
logs\                     auditoria e erros (modo portátil)
dev\                      build, testes e scripts de desenvolvimento
```
