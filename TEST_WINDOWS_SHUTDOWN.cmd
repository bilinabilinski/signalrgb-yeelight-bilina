@echo off
cd /d "%~dp0"
echo This is a safe simulation. It WILL NOT shut down Windows.
echo Close SignalRGB with Exit before running this test.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Watch-SignalRGB.ps1" -SimulateWindowsShutdown
echo.
if errorlevel 1 (
 echo TEST FAILED. Open %%LOCALAPPDATA%%\YeelightBilina\white-restore.log
) else (
 echo TEST OK. White was acknowledged by all configured bulbs.
)
pause
