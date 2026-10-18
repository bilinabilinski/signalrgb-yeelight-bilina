# Yeelight Bilina: restores real white light after SignalRGB exits.
# Independent TCP control, so it does NOT rely on SignalRGB's Shutdown() callback.
# Supported: Windows PowerShell 5.1+, Yeelight LAN TCP port 55443.
param(
    [switch]$Watch,
    [switch]$Once,
    [switch]$SimulateWindowsShutdown,
    [string]$ConfigFile = "",
    [string]$IpCsv = "",
    [int]$Port = 55443,
    [string]$LogFile = ""
)
$ErrorActionPreference = "Stop"
$root = Join-Path $env:LOCALAPPDATA "YeelightBilina"
if (!(Test-Path $root)) { New-Item -Path $root -ItemType Directory -Force | Out-Null }
if (!$LogFile) { $LogFile = Join-Path $root "white-restore.log" }
if (!$ConfigFile) { $ConfigFile = Join-Path $root "white-restore.json" }
$defaults = @("192.168.1.149","192.168.1.150","192.168.1.153")
$kelvin = 4000
$brightness = 100
$ips = $defaults
if (Test-Path -LiteralPath $ConfigFile) {
    $cfg = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
    if ($null -ne $cfg.ips -and @($cfg.ips).Count -gt 0) { $ips = @($cfg.ips) }
    if ($null -ne $cfg.kelvin) { $kelvin = [int]$cfg.kelvin }
    if ($null -ne $cfg.brightness) { $brightness = [int]$cfg.brightness }
}
if ($IpCsv) { $ips = @($IpCsv.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
if ($kelvin -lt 2700 -or $kelvin -gt 6500) { throw "Kelvin must be between 2700 and 6500." }
if ($brightness -lt 1 -or $brightness -gt 100) { throw "Brightness must be between 1 and 100." }
if ($Port -lt 1 -or $Port -gt 65535) { throw "Invalid TCP port." }
foreach ($ip in $ips) {
    $parsed = $null
    if (![System.Net.IPAddress]::TryParse([string]$ip,[ref]$parsed) -or
        $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw ("Only IPv4 addresses are accepted: " + [string]$ip)
    }
}
function Log-Message([string]$message) {
    $line = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " " + $message
    if ($Once) { Write-Host $line }
    try {
        if (Test-Path $LogFile) {
            if ((Get-Item $LogFile).Length -gt 262144) {
                Move-Item -Path $LogFile -Destination ($LogFile + ".old") -Force
            }
        }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch {
        if ($Once) { Write-Warning ("Cannot write log: " + $_.Exception.Message) }
    }
}
function Send-White([string]$ip) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $tcp.BeginConnect($ip,$Port,$null,$null)
        if (!$async.AsyncWaitHandle.WaitOne(2200)) { throw "TCP connect timeout" }
        $tcp.EndConnect($async)
        $tcp.ReceiveTimeout = 2200
        $tcp.SendTimeout = 2200
        $net = $tcp.GetStream()
        $net.ReadTimeout = 2200
        $net.WriteTimeout = 2200
        $enc = New-Object System.Text.UTF8Encoding($false)
        $writer = New-Object System.IO.StreamWriter($net,$enc,1024,$true)
        $reader = New-Object System.IO.StreamReader($net,[System.Text.Encoding]::UTF8,$false,1024,$true)
        $writer.NewLine = ([string][char]13 + [char]10)
        $commands = @(
            @{ id=1; method="set_power"; params=@("on","sudden",0) },
            @{ id=2; method="set_ct_abx"; params=@($kelvin,"smooth",300) },
            @{ id=3; method="set_bright"; params=@($brightness,"smooth",300) }
        )
        foreach ($cmd in $commands) {
            $request = ConvertTo-Json -InputObject $cmd -Compress -Depth 4
            $writer.WriteLine($request)
            $writer.Flush()
            $response = $reader.ReadLine()
            if (!$response) { throw ("No response to " + $cmd.method) }
            $obj = $response | ConvertFrom-Json
            if ($null -ne $obj.error) {
                throw ($cmd.method + " returned error: " + ($obj.error | ConvertTo-Json -Compress))
            }
            if ([int]$obj.id -ne [int]$cmd.id -or $null -eq $obj.result) {
                throw ("Unexpected response for " + $cmd.method + ": " + $response)
            }
        }
        Log-Message ("OK " + $ip + " - power on, " + $kelvin + " K, " + $brightness + "%.")
        return $true
    } catch {
        Log-Message ("FAILED " + $ip + ": " + $_.Exception.Message)
        return $false
    } finally {
        if ($null -ne $tcp) { $tcp.Close() }
    }
}
function SignalRGB-Running() {
    return (@(Get-Process -Name "SignalRGB" -ErrorAction SilentlyContinue).Count -gt 0)
}
function Restore-All {
    $pending = @($ips)
    $maxAttempts = if ($Once) { 2 } else { 9 }
    for ($attempt=1; $attempt -le $maxAttempts; $attempt++) {
        if ($Watch -and (SignalRGB-Running)) {
            Log-Message "SignalRGB restarted; cancelled pending restoration."
            return $false
        }
        $failed = @()
        foreach ($ip in $pending) {
            if (!(Send-White ([string]$ip))) { $failed += $ip }
        }
        if ($failed.Count -eq 0) { return $true }
        $pending = $failed
        if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 5 }
    }
    Log-Message ("White restore incomplete for: " + ($pending -join ", "))
    return $false
}
if ($Once) {
    Log-Message "Manual white-restore test started."
    if (Restore-All) { exit 0 } else { exit 1 }
}
if (!$Watch -and !$SimulateWindowsShutdown) { throw "Specify -Once, -Watch or -SimulateWindowsShutdown." }
# Windows does NOT guarantee SignalRGB.exe exits before it terminates this watcher.
# Register for the session-ending notification before entering the polling loop.
$shutdownCode = Join-Path $PSScriptRoot "YeelightWindowsShutdown.cs"
if (!(Test-Path -LiteralPath $shutdownCode)) {
    throw "Windows shutdown handler missing: YeelightWindowsShutdown.cs. Reinstall WHITE RESTORE."
}
Add-Type -Path $shutdownCode -ReferencedAssemblies @("System.dll","System.Core.dll") -ErrorAction Stop
[YeelightBilina.WindowsShutdownWhite]::Register([string[]]$ips,$kelvin,$brightness,$Port,$LogFile)
if ($SimulateWindowsShutdown) {
    Log-Message "Simulating Windows shutdown event (does NOT turn off Windows)."
    if ([YeelightBilina.WindowsShutdownWhite]::SimulateForTest()) {
        Log-Message "SIMULATED_WINDOWS_SHUTDOWN_OK"
        Write-Host "OK: Shutdown event path restored white on all bulbs." -ForegroundColor Green
        exit 0
    }
    Log-Message "SIMULATED_WINDOWS_SHUTDOWN_FAILED"
    Write-Host "FAILED: Check $LogFile" -ForegroundColor Red
    exit 1
}
$mutex = New-Object System.Threading.Mutex($false, "Local\YeelightBilina_WhiteRestore")
$acquired = $false
try {
    try { $acquired = $mutex.WaitOne(0,$false) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (!$acquired) { exit 0 }
    Log-Message "Watcher started. Listening for SignalRGB exit AND Windows shutdown/logoff."
    $wasRunning = SignalRGB-Running
    while (!(Test-Path (Join-Path $root "stop-white-restore.flag"))) {
        Start-Sleep -Seconds 2
        $isRunning = SignalRGB-Running
        if ($wasRunning -and !$isRunning) {
            Log-Message "SignalRGB stopped. Waiting 3 seconds for UDP streaming to end."
            Start-Sleep -Seconds 3
            if (!(SignalRGB-Running)) { $null = Restore-All }
        }
        $wasRunning = $isRunning
    }
    Log-Message "Watcher stopped by request."
} finally {
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
