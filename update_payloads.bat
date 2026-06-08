@echo off
chcp 65001 >nul

echo.
echo ============================================================
echo  PS5 Payload Updater
echo ============================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update_payloads.ps1"

echo.
pause
