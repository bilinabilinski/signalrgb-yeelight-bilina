// Tests the ACTUAL modified upstream JavaScript with SignalRGB service mocks.
const fs = require("node:fs");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const path = require("node:path");
const dir = process.argv[2] || "build";
const js = fs.readFileSync(path.join(dir, "Yeelight.js"), "utf8");
const qml = fs.readFileSync(path.join(dir, "Yeelight.qml"), "utf8");
assert.match(qml, /discovery\.link\(root\.device\.id\)/);
assert.match(qml, /discovery\.unlink\(root\.device\.id\)/);
assert.doesNotMatch(qml, /discovery\.link\(root\.device\);/);
assert.match(js, /Yeelight upstream-based fix v1\.0\.3 active/);
assert.match(js, /this\.cacheMap\.clear\(\)/);
assert.match(js, /value\?\.port \?\? 55444/);

const map = new Map();
const log = [];
const stored = new Map();
const service = {
  controllers: [],
  log: msg => log.push(String(msg)),
  getController: id => map.get(String(id)),
  addController: item => map.set(String(item.id), item),
  updateController: item => map.set(String(item.id), item),
  announceController: item => {item.announced = true;},
  suppressController: item => {item.announced = false;},
  saveSetting: (group, key, value) => stored.set(group + "/" + key, value),
  getSetting: (group,key) => stored.get(group + "/" + key),
  removeSetting: (group,key) => stored.delete(group + "/" + key)
};
const context = {service, console, Date, Map, JSON, Math, String};
vm.createContext(context);
const runnable = js.replace(/^import udp from "@SignalRGB\/udp";\s*/m, "").replaceAll("export function ","function ");
vm.runInContext(runnable + "\nthis.DiscoveryService = DiscoveryService;", context, {filename: "Yeelight.js"});
const discovery = new context.DiscoveryService();
context.discovery = discovery;
discovery.Initialize();

const devices = [
  ["7c:c2:94:59:b6:51", "192.168.1.149"],
  ["58:b6:23:c2:87:d6", "192.168.1.150"],
  ["7c:c2:94:59:f7:41", "192.168.1.153"],
];
for (const [id, ip] of devices) {
  discovery.CreateControllerDevice({
    id, ip, model: "colorc", name: "colorc",
    paired: false, port: 55444,
    supportsPerLED: false, supportsBackgroundRGB: false,
    supportsSegments: false, supportsStandardRGB: true,
  });
  assert(map.has(id));
  discovery.link(id); // QML passes primitive ID (not QObject)
  assert.equal(map.get(id).paired, true, "Link must pair " + id);
  assert.equal(map.get(id).announced, true);
  discovery.unlink(id);
  assert.equal(map.get(id).paired, false);
  assert.equal(map.get(id).announced, false);
  discovery.link({id}); // legacy cached object must still work
  assert.equal(map.get(id).paired, true);
}
discovery.link(undefined);
discovery.unlink(undefined);
discovery.link("does-not-exist");
assert(log.some(line => line.includes("missing device id")));
assert(log.some(line => line.includes("Controller not found")));
// Cache must be cleared in memory too, not only in persistent settings.
assert.equal(discovery.cache.cacheMap.size, 3);
discovery.cache.PurgeCache();
assert.equal(discovery.cache.cacheMap.size, 0);
assert.equal(stored.has("ipCache/cache"), false);
// Test the real Shutdown() path with device protocol calls intercepted.
const packets = [];
context.device = {log: message => log.push(String(message))};
context._sentPackets = packets;
context.controller = {model: "colorc", ip: "192.168.1.149"};
context.TurnOffOnShutdown = false; // existing old setting must not prevent restoration
vm.runInContext('Yeelight.setToken("test-token"); Yeelight.sendPacket = function(packet) { _sentPackets.push(String(packet)); };', context);

for (const [id, ip] of devices) {
  packets.length = 0;
  context.controller = {model: "colorc", ip};
  vm.runInContext("Shutdown(false);", context);
  assert.equal(packets.length, 3, "must send power, brightness, white to " + id);
  assert.match(packets[0], /"method":"set_power"/);
  assert.match(packets[0], /"params":\["on","sudden"\]/);
  assert.match(packets[1], /"method":"set_bright"/);
  assert.match(packets[1], /"params":\[100,"sudden",0\]/);
  assert.match(packets[2], /"method":"set_rgb"/);
  assert.match(packets[2], /"params":\[16777215,"sudden",0\]/);
}
// Models other than colorc retain original default behavior (no exit packet).
packets.length = 0;
context.controller = {model: "color"};
vm.runInContext("Shutdown(false);", context);
assert.equal(packets.length, 0);
// True black: zero RGB MUST power down colorc, never dim to 1%.
// Test all three actual colorc models, repeated black, nonblack restoration,
// cached frame deduplication and a second black frame.
for (const [id, ip] of devices) {
  packets.length = 0;
  context.controller = {model: "colorc", ip};
  vm.runInContext('lastData=0; lightOff=false; sendColors("#000000");', context);
  assert.deepEqual(packets.map(p=>JSON.parse(p).method), ["set_power"],
    "First black must physically turn off " + id);
  assert.deepEqual(JSON.parse(packets[0]).params, ["off", "sudden"]);
  vm.runInContext('sendColors("#000000");', context);
  assert.equal(packets.length, 1, "Repeated black must not flood on/off packets");
  vm.runInContext('sendColors("#FF0000");', context);
  assert.deepEqual(packets.map(p=>JSON.parse(p).method),
    ["set_power", "set_power", "set_bright", "set_rgb"]);
  assert.deepEqual(JSON.parse(packets[1]).params, ["on", "sudden"]);
  assert.deepEqual(JSON.parse(packets[2]).params, [100,"sudden",0]);
  assert.deepEqual(JSON.parse(packets[3]).params, [16711680,"sudden",0]);
  vm.runInContext('sendColors("#FF0000");', context);
  assert.equal(packets.length, 4, "Repeated red frame must be deduplicated");
  vm.runInContext('sendColors("#000000");', context);
  assert.equal(packets.length, 5, "Second black after red must turn off");
  assert.deepEqual(JSON.parse(packets[4]).params, ["off", "sudden"]);
}
// Existing behavior for another Yeelight model must remain unchanged.
packets.length = 0;
context.controller = {model: "color"};
vm.runInContext('lastData=-1; lightOff=false; sendColors("#000000");', context);
assert.deepEqual(packets.map(p=>JSON.parse(p).method),["set_bright", "set_rgb"]);
assert.deepEqual(JSON.parse(packets[0]).params, [1, "sudden", 0]);
// System suspend now also means true black for colorc.
packets.length = 0;
context.controller = {model: "colorc"};
vm.runInContext('lastData=16711680; lightOff=false; Shutdown(true);', context);
assert.deepEqual(JSON.parse(packets[packets.length - 1]).params, ["off", "sudden"]);
console.log("PASS: syntax, 3 Link/Unlink bulbs, cache, white restore, true black on all colorc, unchanged other models.");
