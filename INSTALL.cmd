@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL.ps1"
echo.
if errorlevel 1 echo ERROR: Installation failed. Copy the error message.
pause
