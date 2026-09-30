@echo off
title TI Suite - Suporte Escolar
rem =====================================================================
rem  TI SUITE - Iniciador portatil (pendrive ou qualquer PC Windows 10/11).
rem  -STA e obrigatorio para WinForms.
rem  A elevacao (UAC) e feita pelo TI-Suite.ps1.
rem  Codigos do TI-Suite.ps1: 0 = normal; 1 = erro ja explicado na tela;
rem  3 = a politica do computador bloqueia scripts do PowerShell.
rem =====================================================================
cd /d "%~dp0"
if exist "%~dp0portable.config" (
    echo [PORTATIL] Modo pendrive: config, logs e inventario ficam nesta pasta.
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell nao encontrado. Este computador precisa do Windows 10 ou 11.
    pause
    exit /b 1
)
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0TI-Suite.ps1" %*
set "TIERR=%errorlevel%"
if "%TIERR%"=="0" exit /b 0
if "%TIERR%"=="3" goto politica

rem O script nem chegou a rodar? Confere a politica de execucao (GPO) e o modo restrito.
powershell.exe -NoProfile -Command "if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { exit 3 }; $p = @((Get-ExecutionPolicy -Scope MachinePolicy), (Get-ExecutionPolicy -Scope UserPolicy)) -join ' '; if ($p -match 'AllSigned|Restricted') { exit 3 }; if ($p -match 'RemoteSigned') { exit 4 }; exit 0" >nul 2>&1
if errorlevel 4 goto assinatura
if errorlevel 3 goto politica

echo.
echo O TI Suite fechou com erro (codigo %TIERR%).
echo Se houver detalhes, eles estao em crash.log e exceptions.log:
echo   modo pendrive: pasta logs ao lado deste arquivo
echo   modo instalado: %LOCALAPPDATA%\TI-Suite
pause
exit /b %TIERR%

:politica
echo.
echo A politica deste computador (GPO, AppLocker ou WDAC) bloqueia scripts do PowerShell.
echo Peca ao responsavel pela rede uma excecao para a pasta do TI Suite:
echo   %~dp0
pause
exit /b 3

:assinatura
echo.
echo A politica deste computador so aceita scripts da internet se forem assinados (RemoteSigned).
echo Se o TI Suite veio num .zip baixado: clique com o botao direito no .zip, Propriedades,
echo marque "Desbloquear", extraia de novo e abra outra vez. Se nao resolver, peca ao
echo responsavel pela rede uma excecao para a pasta do TI Suite.
pause
exit /b 1
