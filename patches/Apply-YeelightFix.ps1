# Applies small, checked changes to the ORIGINAL SignalRGB Yeelight sources.
param(
    [Parameter(Mandatory=$true)][string]$SourceDirectory,
    [Parameter(Mandatory=$true)][string]$DestinationDirectory
)
$ErrorActionPreference = "Stop"
$jsPath = Join-Path $SourceDirectory "Yeelight.js"
$qmlPath = Join-Path $SourceDirectory "Yeelight.qml"
if (!(Test-Path -LiteralPath $jsPath) -or !(Test-Path -LiteralPath $qmlPath)) {
    throw "Original Yeelight.js / Yeelight.qml missing."
}
$js = [regex]::Replace([System.IO.File]::ReadAllText($jsPath), '\r\n?', [string][char]10)
$qml = [regex]::Replace([System.IO.File]::ReadAllText($qmlPath), '\r\n?', [string][char]10)
$oldLink = '(?s)[ \t]*this\.link = function\(controllerObj\)\s*\{.*?(?=[ \t]*this\.unlink = function\(controllerObj\))'
$oldUnlink = '(?s)[ \t]*this\.unlink = function\(controllerObj\)\s*\{.*?(?=[ \t]*this\.cacheControllerInfo = function\(value\))'
if ([regex]::Matches($js,$oldLink).Count -ne 1) { throw "Upstream link() changed; stopping." }
if ([regex]::Matches($js,$oldUnlink).Count -ne 1) { throw "Upstream unlink() changed; stopping." }
if (!$qml.Contains("discovery.link(root.device);") -or !$qml.Contains("discovery.unlink(root.device);")) {
    throw "Upstream QML changed; stopping."
}
$newLink = @'
    // SignalRGB's QML bridge receives a primitive stable ID, not a QObject.
    // Objects remain accepted for the upstream startup cache loader.
    this.resolveController = function(controllerRef) {
        const id = (typeof controllerRef === "string" || typeof controllerRef === "number")
            ? controllerRef : (controllerRef && controllerRef.id);
        if (id === undefined || id === null || id === "") {
            service.log("[Bilina] Link/Unlink ignored: missing device id");
            return undefined;
        }
        let resolvedId = id;
        let cached = this.cache.Get(id);
        if (cached === undefined) {
            for (const [key, value] of this.cache.Entries()) {
                if (String(key) === String(id) || (value && String(value.id) === String(id))) {
                    resolvedId = key;
                    cached = value;
                    break;
                }
            }
        }
        let current = service.getController(resolvedId);
        if (current === undefined && cached !== undefined) {
            this.CreateControllerDevice(cached);
            current = service.getController(resolvedId);
        }
        if (current === undefined) {
            service.log("[Bilina] Controller not found for id " + String(id));
        }
        return current;
    };

    this.link = function(controllerRef) {
        const current = this.resolveController(controllerRef);
        if (current === undefined) { return; }
        try {
            service.log("[Bilina] Linking " + String(current.id) + " at " + String(current.ip));
            current.paired = true;
            current.updateWithValue(current);
            service.announceController(current);
            this.cacheControllerInfo(current);
            service.log("[Bilina] Linked " + String(current.id));
        } catch (error) {
            service.log("[Bilina] Link error: " + String(error));
        }
    };

'@
$newUnlink = @'
    this.unlink = function(controllerRef) {
        const current = this.resolveController(controllerRef);
        if (current === undefined) { return; }
        try {
            service.log("[Bilina] Unlinking " + String(current.id));
            // Discovery sockets are keyed by IP address, not controller ID.
            const socket = this.getSocket(current.ip);
            if (socket) {
                socket.stop();
                this.activeSockets.delete(current.ip);
            }
            current.paired = false;
            current.updateWithValue(current);
            service.suppressController(current);
            this.cacheControllerInfo(current);
            service.log("[Bilina] Unlinked " + String(current.id));
        } catch (error) {
            service.log("[Bilina] Unlink error: " + String(error));
        }
    };

'@
$js = [regex]::Replace($js,$oldLink,[System.Text.RegularExpressions.MatchEvaluator]{param($m) $newLink},1)
$js = [regex]::Replace($js,$oldUnlink,[System.Text.RegularExpressions.MatchEvaluator]{param($m) $newUnlink},1)
$qml = $qml.Replace("discovery.link(root.device);","discovery.link(root.device.id);")
$qml = $qml.Replace("discovery.unlink(root.device);","discovery.unlink(root.device.id);")
$purgeRegex = 'PurgeCache\(\)\s*\{\s*service\.removeSetting'
if ([regex]::Matches($js,$purgeRegex).Count -ne 1) {throw "PurgeCache() changed; stopping."}
$js = [regex]::Replace($js,$purgeRegex,'PurgeCache() {' + [char]10 + '        this.cacheMap.clear();' + [char]10 + '        service.removeSetting',1)
$js = $js.Replace("value?.port ?? 55544","value?.port ?? 55444")
$createOld = 'discovery.CreateControllerDevice(discovery.cache.GetByIP(this.ipToConnectTo));'
$createNew = @'
const cached = discovery.cache.GetByIP(this.ipToConnectTo);
                if (cached !== undefined) {
                    discovery.CreateControllerDevice(cached);
                } else {
                    this.log("[Bilina] IP responded but no cached controller: " + this.ipToConnectTo);
                }
'@
if (!$js.Contains($createOld)) {throw "UDP cache lookup changed; stopping."}
$js = $js.Replace($createOld,$createNew)

# True black for GU10 W1 Color: brightness=1 never produces absolute darkness.
# Insert a small model-specific branch into the native upstream renderer.
# Keep existing RGB handling unchanged for every other Yeelight model.
$renderAnchor = 'const RGBData = grabColors(overrideColor);'
if ([regex]::Matches($js, [regex]::Escape($renderAnchor)).Count -ne 1) {
    throw "Upstream single-zone RGB renderer changed; refusing to change black handling."
}
$blackHandling = @'

        // Bilina: colorc supports true black via power-off (1% brightness is not black).
        if (controller && String(controller.model).trim().toLowerCase() === "colorc") {
            if (RGBData === 0) {
                if (!lightOff) {
                    Yeelight.setDevicePower(false);
                    lightOff = true;
                    lastData = 0;
                }
                return;
            }

            if (lightOff) {
                // Recover from black even if the new RGB equals the previous cached value.
                Yeelight.setDevicePower(true);
                Yeelight.setDeviceBrightness(100);
                lightOff = false;
                lastData = -1;
            }

            if (lastData !== RGBData) {
                Yeelight.setRGB(RGBData);
                lastData = RGBData;
            }
            return;
        }
'@
$js = $js.Replace($renderAnchor, $renderAnchor + $blackHandling)


# The original Yeelight Shutdown() does nothing on normal SignalRGB exit unless
# 'TurnOffOnShutdown' is enabled. For GU10 W1 Color ('colorc'), restore white.
# Keep the original sleep/shutdown behaviour and all other Yeelight models intact.
$shutdownPattern = '(?s)export function Shutdown\(SystemSuspending\)\s*\{\s*if\s*\(SystemSuspending\)\s*\{\s*sendColors\("#000000"\);\s*\}\s*else if\s*\(TurnOffOnShutdown\)\s*\{\s*sendColors\(shutdownColor\);\s*\}\s*\}'
$whiteShutdown = @'
export function Shutdown(SystemSuspending) {
	if (SystemSuspending) {
		sendColors("#000000");
		return;
	}

	// GU10 W1 Color, model colorc. No other devices are changed.
	if (controller && String(controller.model).trim().toLowerCase() === "colorc") {
		if (!Yeelight.getIsTokenActive()) {
			device.log("[Bilina] Cannot restore white: UDP token not active");
			return;
		}
		// Restore power and brightness even when the last animated frame was dark.
		Yeelight.setDevicePower(true);
		Yeelight.setDeviceBrightness(100);
		lightOff = false;
		lastData = -1; // force a final packet, including when the last frame was white
		sendColors("#FFFFFF");
		device.log("[Bilina] Restored colorc to white on SignalRGB exit");
		return;
	}

	// Preserve upstream behaviour for all other supported models.
	if (TurnOffOnShutdown) {
		sendColors(shutdownColor);
	}
}
'@
if ([regex]::Matches($js, $shutdownPattern).Count -ne 1) {
    throw "Upstream Shutdown() changed; refusing to modify unknown code."
}
$js = [regex]::Replace($js, $shutdownPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $whiteShutdown }, 1)

$js = $js.Replace('export function Name() { return "Yeelight"; }','export function Name() { return "Yeelight Bilina"; }')
$js = $js.Replace('export function Version() { return "1.0.0"; }','export function Version() { return "1.0.3-bilina"; }')
if (!$js.Contains('service.log("Initializing Plugin!");')) {throw "Initialize() changed; stopping."}
$js = $js.Replace('service.log("Initializing Plugin!");','service.log("[Bilina] Yeelight upstream-based fix v1.0.3 active");')
New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $DestinationDirectory "Yeelight.js"),$js,(New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $DestinationDirectory "Yeelight.qml"),$qml,(New-Object System.Text.UTF8Encoding($false)))
$components = Join-Path $SourceDirectory "Components"
if (Test-Path $components) {
    Copy-Item -LiteralPath $components -Destination (Join-Path $DestinationDirectory "Components") -Recurse -Force
}
Write-Host "PATCH OK: stable QML IDs, Link/Unlink, cache purge, UDP fallback, true black for colorc, white restore on exit." -ForegroundColor Green
