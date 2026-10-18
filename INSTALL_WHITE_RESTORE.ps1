# Installs a small background watcher via the current user's Startup folder.
# It runs only under the signed-in user, requires no administrator rights.
param([switch]$SkipStart)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $here "Watch-SignalRGB.ps1"
if (!(Test-Path $source)) { throw "Extract the whole GitHub ZIP, including Watch-SignalRGB.ps1." }
$csSource = Join-Path $here "YeelightWindowsShutdown.cs"
if (!(Test-Path $csSource)) { throw "Extract whole ZIP: YeelightWindowsShutdown.cs is missing." }
$dest = Join-Path $env:LOCALAPPDATA "YeelightBilina"
New-Item -Path $dest -ItemType Directory -Force | Out-Null
# Ask a previously installed watcher to quit gracefully before overwriting its files.
$flag = Join-Path $dest "stop-white-restore.flag"
[System.IO.File]::WriteAllText($flag, "stop")
Start-Sleep -Seconds 3
Copy-Item -LiteralPath $source -Destination (Join-Path $dest "Watch-SignalRGB.ps1") -Force
Copy-Item -LiteralPath $csSource -Destination (Join-Path $dest "YeelightWindowsShutdown.cs") -Force
$conf = Join-Path $dest "white-restore.json"
if (!(Test-Path $conf)) {
    $config = @{ips=@("192.168.1.149","192.168.1.150","192.168.1.153"); kelvin=4000; brightness=100}
    $json = ConvertTo-Json -InputObject $config -Depth 4
    [System.IO.File]::WriteAllText($conf,$json,(New-Object System.Text.UTF8Encoding($false)))
}
$flag = Join-Path $dest "stop-white-restore.flag"
if (Test-Path $flag) { Remove-Item -LiteralPath $flag -Force }
$startup = [Environment]::GetFolderPath("Startup")
if (!$startup) { throw "Cannot locate Windows Startup folder." }
$shortcutPath = Join-Path $startup "Yeelight Bilina White Restore.lnk"
$psPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $psPath
$shortcut.Arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $dest "Watch-SignalRGB.ps1") + '" -Watch')
$shortcut.WorkingDirectory = $dest
$shortcut.WindowStyle = 7
$shortcut.Description = "Return Yeelight colorc bulbs to white after SignalRGB exits."
$shortcut.Save()
# Start immediately; the mutex in the watcher prevents simultaneous instances.
if (!$SkipStart) { Start-Process -FilePath $psPath -WindowStyle Hidden -ArgumentList $shortcut.Arguments }
Write-Host "Installed Yeelight white restoration watcher." -ForegroundColor Green
Write-Host "Startup shortcut: $shortcutPath"
Write-Host "Config (edit Kelvin/brightness if desired): $conf"
Write-Host "Logs: $(Join-Path $dest 'white-restore.log')"
Write-Host "It restores white on SignalRGB exit AND on Windows shutdown/logoff."
