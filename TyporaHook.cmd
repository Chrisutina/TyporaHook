@echo off
cd /d "%~dp0"
title TyporaHook
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\menu.ps1"
echo.
pause
