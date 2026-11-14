@echo off
rem Double-click to update the WoW_Forever addons. See update-addons.ps1 for details.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-addons.ps1" %*
echo.
pause
