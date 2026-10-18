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
assert.match(js, /Yeelight upstream-based fix v1\.0\.1 active/);
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
console.log("PASS: syntax parsed, 3 devices, Link/Unlink, cached object, missing device, clear cache.");
