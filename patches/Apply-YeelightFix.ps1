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
$js = $js.Replace('export function Version() { return "1.0.0"; }','export function Version() { return "1.0.1-bilina"; }')
if (!$js.Contains('service.log("Initializing Plugin!");')) {throw "Initialize() changed; stopping."}
$js = $js.Replace('service.log("Initializing Plugin!");','service.log("[Bilina] Yeelight upstream-based fix v1.0.1 active");')
New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $DestinationDirectory "Yeelight.js"),$js,(New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $DestinationDirectory "Yeelight.qml"),$qml,(New-Object System.Text.UTF8Encoding($false)))
$components = Join-Path $SourceDirectory "Components"
if (Test-Path $components) {
    Copy-Item -LiteralPath $components -Destination (Join-Path $DestinationDirectory "Components") -Recurse -Force
}
Write-Host "PATCH OK: stable QML IDs, Link/Unlink, cache purge, UDP fallback." -ForegroundColor Green
