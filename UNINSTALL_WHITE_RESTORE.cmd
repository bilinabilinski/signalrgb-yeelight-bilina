@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UNINSTALL_WHITE_RESTORE.ps1"
echo.
pause
