# Pasta de desenvolvimento

Nada aqui vai para o pendrive: o `Build-Release.ps1` monta o pacote sem esta pasta.
Ela tem só dois scripts:

- `Build-Release.ps1`: gera o pacote de distribuição.
- `Test-Logic.ps1`: testa as regras do app sem abrir janela.

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
