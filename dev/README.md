# Pasta de desenvolvimento

Nada aqui vai para o pacote nem para o pendrive: o `Build-Release.ps1` e o `Criar-Pendrive.ps1` copiam o app
sem esta pasta. Ela tem três scripts:

- `Build-Release.ps1`: gera o pacote de distribuição.
- `Test-Logic.ps1`: testa as regras do app sem abrir janela.
- `Criar-Pendrive.ps1`: cria o pendrive de recuperação (aberto pelo `Criar-Pendrive.cmd` da raiz do projeto).

## Gerar uma versão para distribuir

1. Abra o **Windows PowerShell** (o azul, 5.1; não precisa ser administrador) nesta pasta do projeto.
2. Rode:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\Build-Release.ps1
   ```

3. O script confere a sintaxe de todos os arquivos, roda o `Test-Logic.ps1` (e para se algum teste falhar),
   compila `bin\TISuite.Controls.dll` e cria `dist\TI-Suite-vX.Y.Z.zip` com o `manifest.sha256` dentro.

O manifesto confere só o código (`.ps1`, `.cs`, `.cmd` e `bin\`): editar ou apagar `README.md`, `CHANGELOG.md`
ou `portable.config` no pendrive não impede o app de abrir. Ele é gravado só no pacote; na pasta do projeto
não existe manifesto, então dá para editar e abrir o app sem `-SkipIntegrity` (um manifesto de build antigo
que tenha ficado na pasta é apagado pelo build).

A DLL faz o TI Suite abrir mais rápido, porque os controles visuais já vêm compilados. Ela tem um carimbo (`bin\TISuite.Controls.stamp`) com o hash do `src\Core\Controls.cs`: se você editar o `.cs` e esquecer de rodar o build, o app percebe e compila na hora, sem usar uma DLL velha.

## Testar as regras sem abrir a janela

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\Test-Logic.ps1
```

Confere a leitura do Wi-Fi (português e inglês), os planos de desinstalação, os perfis de aluno, as regras da Saúde do PC e a planilha do inventário. Não mexe no computador.

Para o teste completo da interface (janela, atalhos, tarefas em segundo plano, maximizar e fechar com tarefa):
`.\TI-Suite.ps1 -SelfTest`.

## Pendrive de recuperação (boot)

O `Criar-Pendrive.cmd` (raiz do projeto) abre o `dev\Criar-Pendrive.ps1`, que cria um pendrive que continua
funcionando com o Windows aberto (`Iniciar.cmd`) e também dá boot (BIOS e UEFI, com o Secure Boot ligado) num
Windows PE que abre o TI Suite sozinho em modo recuperação.

Precisa de:

- Windows 10 ou 11 e administrador (o `.cmd` pede o UAC e reabre com as mesmas opções);
- **Windows ADK** (marque só "Ferramentas de Implantação") e o **Complemento do Windows PE**, os dois da página
  oficial da Microsoft "Baixar e instalar o Windows ADK":
  https://learn.microsoft.com/pt-br/windows-hardware/get-started/adk-install
- pendrive de 8 GB ou mais. **Tudo nele é apagado**; os dados de campo do TI Suite que já estiverem nele
  (inventário, logs, laudos, relatórios, `wifi\`, backups, `reparo\` e `config.json`) são guardados antes e
  devolvidos no fim. Se não der para guardar, nada é apagado.

| Comando | O que faz |
|---|---|
| `Criar-Pendrive.cmd` | Lista os discos USB, pergunta o número, pede para digitar **APAGAR** e cria tudo (10 a 20 min) |
| `Criar-Pendrive.cmd -SomenteAtualizar` | Só recopia o app para a partição TI-SUITE (não formata e não precisa do ADK) |
| `Criar-Pendrive.cmd -SomenteISO` | Gera `dist\TI-Recuperacao.iso` (Windows PE + app) para testar numa máquina virtual |
| `-Disco 2` | Usa o disco 2 sem perguntar (a confirmação APAGAR continua) |
| `-SistemaArquivos exFAT` | Partição TI-SUITE em exFAT (padrão: NTFS) |
| `-Boot2023` | Boot assinado com a "Windows UEFI CA 2023" (MakeWinPEMedia /bootex) para PCs que já revogaram o certificado antigo; **não dá boot em PCs antigos sem a CA 2023**. Sem a opção, o boot é o compatível |
| `-Drivers <pasta>` | Drivers `.inf` para o Windows PE (ex.: Intel RST/VMD, para enxergar SSD NVMe). Padrão: `dev\drivers\`, se existir |
| `-Ajuda` | Ajuda completa |

O pendrive fica assim (tabela MBR):

- **TI-BOOT** (FAT32, 2 GB, ativa): o Windows PE do ADK com WMI, .NET, scripts, PowerShell, Storage, DISM,
  BitLocker e armazenamento avançado (e os pacotes pt-br), pt-BR, teclado ABNT2, fuso de Brasília, as fontes
  Segoe UI, Segoe MDL2 Assets e Consolas (copiadas deste Windows) e um `startnet.cmd` que acha a partição do TI
  Suite e abre o app com `-Recovery` (ao fechar: 1 abrir de novo, 2 prompt, 3 reiniciar, 4 desligar).
- **TI-SUITE** (NTFS ou exFAT, o resto): o app na raiz (sem `dev\`, `dist\`, `.git`, zips e dados da máquina),
  `bin\TISuite.Controls.dll` + carimbo compilados na hora (o Windows PE pode não ter o compilador C#),
  `portable.config`, `config.json` padrão, a pasta `reparo\` e o `LEIA-ME-PENDRIVE.txt` para o técnico.

Cada execução grava `dist\criar-pendrive-<data>.log`. A pasta de trabalho (`%TEMP%\TI-PE-<id>`, ou `C:\TI-PE-<id>`
quando o `%TEMP%` tem acento) é apagada no fim, mesmo com erro; a imagem montada é descartada e o registro
offline é descarregado. O pendrive só é apagado depois que o Windows PE estiver pronto, e o script confere
antes se ainda é o mesmo disco que foi confirmado.

Para testar sem pendrive: `-SomenteISO` e uma máquina virtual (Hyper-V geração 2 com o modelo de Secure Boot
"Microsoft Windows", ou VirtualBox com EFI). O ISO leva o app em mídia somente leitura; para testar os reparos,
conecte também um disco virtual com Windows instalado.
