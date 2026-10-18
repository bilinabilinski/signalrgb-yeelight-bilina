# Windows installer for the official Yeelight plugin with Bilina fixes.
# Downloads original sources directly from the SignalRGB GitLab project.
param([switch]$SkipProcessCheck)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchScript = Join-Path $scriptRoot "patches/Apply-YeelightFix.ps1"
if (!(Test-Path $patchScript)) { throw "Missing patches/Apply-YeelightFix.ps1. Extract the whole repository ZIP first." }
if (!$SkipProcessCheck) {
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'SignalRGB' }
    if ($running) { throw "Close SignalRGB completely, including its tray icon, then retry." }
}
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("YeelightBilina-" + [guid]::NewGuid().ToString("N"))
$archive = Join-Path $temp "upstream.zip"
$extracted = Join-Path $temp "source"
$build = Join-Path $temp "build"
New-Item -ItemType Directory -Path $extracted -Force | Out-Null
try {
    $url = "https://gitlab.com/signalrgb/yeelight/-/archive/main/yeelight-main.zip"
    Write-Host "Downloading ORIGINAL SignalRGB Yeelight from GitLab..."
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing -TimeoutSec 60
    Expand-Archive -LiteralPath $archive -DestinationPath $extracted -Force
    $source = Get-ChildItem $extracted -Directory | Where-Object {
        (Test-Path (Join-Path $_.FullName "Yeelight.js")) -and (Test-Path (Join-Path $_.FullName "Yeelight.qml"))
    } | Select-Object -First 1
    if (!$source) { throw "GitLab ZIP lacks the expected files. Upstream format may have changed." }
    & $patchScript -SourceDirectory $source.FullName -DestinationDirectory $build
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Patching failed." }
    $js = [System.IO.File]::ReadAllText((Join-Path $build "Yeelight.js"))
    $qml = [System.IO.File]::ReadAllText((Join-Path $build "Yeelight.qml"))
    if (!$js.Contains("[Bilina] Linked ") -or !$qml.Contains("discovery.link(root.device.id);")) {
        throw "Verification failed; original plugin has NOT been replaced."
    }
    $documents = [Environment]::GetFolderPath("MyDocuments")
    if (!$documents) { throw "Could not determine Windows Documents folder." }
    $plugins = Join-Path $documents "WhirlwindFX/Plugins"
    New-Item -ItemType Directory -Path $plugins -Force | Out-Null
    $target = Join-Path $plugins "YeelightBilina"
    if (Test-Path $target) {
        $backup = $target + ".backup-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Move-Item -LiteralPath $target -Destination $backup
        Write-Host "Backup created at: $backup"
    }
    Copy-Item -LiteralPath $build -Destination $target -Recurse -Force
    Write-Host "Installed Yeelight Bilina from original upstream into: $target" -ForegroundColor Green
    Write-Host "Disable the old separate Yeelight/ColorC extensions while testing this plugin." -ForegroundColor Yellow
    Write-Host "Look for [Bilina] Yeelight upstream-based fix v1.0.1 active in SignalRGB console."
} finally {
    if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
