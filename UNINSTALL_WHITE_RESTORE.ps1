# Stop Yeelight Bilina white restoration and remove its auto-start shortcut.
$ErrorActionPreference = "Stop"
$folder = Join-Path $env:LOCALAPPDATA "YeelightBilina"
$startup = [Environment]::GetFolderPath("Startup")
$link = Join-Path $startup "Yeelight Bilina White Restore.lnk"
if (Test-Path $folder) {
    [System.IO.File]::WriteAllText((Join-Path $folder "stop-white-restore.flag"),"stop")
}
if (Test-Path $link) { Remove-Item -LiteralPath $link -Force }
Write-Host "Automatic white restoration disabled. Running watcher stops within 2 seconds." -ForegroundColor Green
Write-Host "Previous config and logs are left in $folder for diagnostics."
