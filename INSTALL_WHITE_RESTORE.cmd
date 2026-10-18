@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL_WHITE_RESTORE.ps1"
echo.
if errorlevel 1 echo INSTALLATION FAILED: Please send a screenshot.
pause
