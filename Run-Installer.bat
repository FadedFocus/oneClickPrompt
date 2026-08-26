@echo off
setlocal
title oneClickPrompt - Windows 11 Program Installer

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-App.ps1"
set "installer_exit_code=%ERRORLEVEL%"

if not "%installer_exit_code%"=="0" (
    echo.
    echo Installer exited with code %installer_exit_code%.
    pause
)

exit /b %installer_exit_code%
