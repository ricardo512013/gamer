@echo off
title TI Suite - Suporte Escolar
rem =====================================================================
rem  TI SUITE - Iniciador portatil (pendrive ou qualquer PC Windows 10/11).
rem  -STA e obrigatorio para WinForms.
rem  A elevacao (UAC) e feita pelo TI-Suite.ps1.
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
if errorlevel 1 pause
