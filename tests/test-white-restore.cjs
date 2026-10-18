// Windows integration test: real PowerShell TCP client vs a fake Yeelight device.
const assert = require("node:assert/strict");
const net = require("node:net");
const cp = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

async function run() {
  const observed = [];
  const server = net.createServer(socket => {
    let buffer = "";
    socket.on("data", data => {
      buffer += data.toString("utf8");
      for (;;) {
        const idx = buffer.indexOf("\n");
        if (idx < 0) break;
        const line = buffer.slice(0, idx).trim();
        buffer = buffer.slice(idx + 1);
        if (!line) continue;
        const cmd = JSON.parse(line);
        observed.push(cmd);
        socket.write(JSON.stringify({id: cmd.id, result: ["ok"]}) + "\r\n");
      }
    });
  });
  await new Promise((resolve,reject) => {
    server.on("error",reject);
    server.listen(0,"127.0.0.1",resolve);
  });
  const port = server.address().port;
  const logfile = path.join(os.tmpdir(), "Yeelight-test-" + process.pid + ".log");
  try {
    const child = cp.spawn("powershell.exe", [
      "-NoProfile","-ExecutionPolicy","Bypass","-File",
      path.resolve("Watch-SignalRGB.ps1"),
      "-Once","-IpCsv","127.0.0.1",
      "-Port",String(port),"-LogFile",logfile
    ], {stdio:["ignore","pipe","pipe"]});
    let stdout = "", stderr = "";
    child.stdout.on("data", d => stdout += d.toString());
    child.stderr.on("data", d => stderr += d.toString());
    const exitCode = await new Promise((resolve,reject) => {
      child.on("close",resolve);
      child.on("error",reject);
    });
    assert.equal(exitCode,0,"Restore script failed:\n" + stdout + "\n" + stderr);
    assert.equal(observed.length,3,"Expected three TCP commands:\n" + JSON.stringify(observed));
    assert.deepEqual(observed.map(x=>x.method),["set_power","set_ct_abx","set_bright"]);
    assert.deepEqual(observed[0].params,["on","sudden",0]);
    assert.deepEqual(observed[1].params,[4000,"smooth",300]);
    assert.deepEqual(observed[2].params,[100,"smooth",300]);
    assert.match(stdout,/OK 127\.0\.0\.1/);
    console.log("PASS: Windows PowerShell connects over TCP and restores native 4000K white.");
  } finally {
    server.close();
    try {fs.unlinkSync(logfile)} catch {}
  }
}
run().catch(e=>{console.error(e);process.exitCode=1;});
