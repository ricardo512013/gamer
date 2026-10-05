@echo off
title TI Suite - Criar pendrive de recuperacao
rem =====================================================================
rem  TI SUITE - Cria o pendrive de recuperacao (Windows PE + TI Suite).
rem  Funciona so na pasta de codigo-fonte (precisa de dev\Criar-Pendrive.ps1)
rem  e num PC com o Windows ADK + complemento Windows PE.
rem  Exemplos:
rem    Criar-Pendrive.cmd                     cria o pendrive (APAGA tudo nele)
rem    Criar-Pendrive.cmd -SomenteAtualizar   so recopia o app (nao formata)
rem    Criar-Pendrive.cmd -SomenteISO         gera dist\TI-Recuperacao.iso
rem    Criar-Pendrive.cmd -Ajuda              mostra todas as opcoes
rem  Sem administrador, pede o UAC e reabre com as mesmas opcoes.
rem  Este arquivo nao vai para o pacote do Build-Release.
rem =====================================================================
if not exist "%~dp0dev\Criar-Pendrive.ps1" goto semdev

rem fltmc so funciona como administrador
fltmc >nul 2>&1
if errorlevel 1 goto elevar

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev\Criar-Pendrive.ps1" %*
set "TIERR=%errorlevel%"
echo.
pause
exit /b %TIERR%

:elevar
echo Pedindo permissao de administrador (UAC)...
set "TI_PEN_SELF=%~f0"
set "TI_PEN_ARGS=%*"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$q = [char]34; $a = '/c ' + $q + $q + $env:TI_PEN_SELF + $q + ' ' + $env:TI_PEN_ARGS + $q; try { Start-Process -FilePath $env:ComSpec -ArgumentList $a -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
if errorlevel 1 goto semuac
exit /b 0

:semuac
echo.
echo O Windows nao liberou o modo administrador: o UAC foi recusado.
echo Clique com o botao direito no Criar-Pendrive.cmd e escolha "Executar como administrador".
pause
exit /b 1

:semdev
echo.
echo Este atalho precisa da pasta de codigo-fonte do TI Suite, a que tem a pasta dev\.
echo O pacote de distribuicao (zip) e o pendrive nao trazem a pasta dev\: abra o
echo Criar-Pendrive.cmd que esta na pasta do projeto.
pause
exit /b 1
