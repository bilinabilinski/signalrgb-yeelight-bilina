@echo off
cd /d "%~dp0"
echo IMPORTANT: Close SignalRGB using Exit first.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Watch-SignalRGB.ps1" -Once
echo.
if errorlevel 1 echo TEST FAILED: See displayed error and white-restore.log.
pause
