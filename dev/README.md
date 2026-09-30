# Pasta de desenvolvimento

Nada aqui vai para o pendrive: o `Build-Release.ps1` monta o pacote sem esta pasta.

## Gerar uma versão para distribuir

1. Abra o **Windows PowerShell** (o azul, 5.1; não precisa ser administrador) nesta pasta do projeto.
2. Rode:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\Build-Release.ps1
   ```

3. O script confere a sintaxe de todos os arquivos, compila `bin\TISuite.Controls.dll`, grava o `manifest.sha256` e cria `dist\TI-Suite-vX.Y.Z.zip`.

A DLL faz o TI Suite abrir mais rápido, porque os controles visuais já vêm compilados. Ela tem um carimbo (`bin\TISuite.Controls.stamp`) com o hash do `src\Core\Controls.cs`: se você editar o `.cs` e esquecer de rodar o build, o app percebe e compila na hora, sem usar uma DLL velha.

## Testar as regras sem abrir a janela

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\Test-Logic.ps1
```

Confere a leitura do Wi-Fi (português e inglês), os planos de desinstalação, os perfis de aluno, as regras da Saúde do PC e a planilha do inventário. Não mexe no computador.

Para o teste completo da interface: `.\TI-Suite.ps1 -SelfTest`.

## Scripts de depuração antigos

- `_repro*.ps1`: reprodução de bugs visuais (barra de rolagem, layout)
- `_stripwin.ps1`, `_wfp.ps1`: análise de janelas filhas
- `_verify3.ps1`, `_runs.ps1`: captura de tela e análise de pixels
- `_inspect*.ps1`, `_enum*.ps1`: árvore de controles e barras de rolagem
- `_diag.ps1`, `_realrun.ps1`, `_snap.ps1`: diagnóstico de inicialização e de processos
- `_check*.ps1`, `_parse.ps1`, `check-syntax.ps1`: verificações de sintaxe antigas
- `_kill.ps1`: encerra processos do TI Suite (cuidado)
