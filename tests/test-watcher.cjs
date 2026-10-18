// Windows end-to-end: simulate SignalRGB.exe exiting, then verify native TCP white.
const assert = require("node:assert/strict");
const cp = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const net = require("node:net");
const delay = ms => new Promise(resolve=>setTimeout(resolve,ms));
async function main(){
  if(process.platform!=="win32") throw new Error("Windows-only test");
  const base=fs.mkdtempSync(path.join(os.tmpdir(),"YeelightWatch-"));
  const fakePath=path.join(base,"SignalRGB.exe");
  fs.copyFileSync(process.execPath,fakePath);
  const flag=path.join(process.env.LOCALAPPDATA,"YeelightBilina","stop-white-restore.flag");
  fs.mkdirSync(path.dirname(flag),{recursive:true});
  try{fs.unlinkSync(flag)}catch{}
  const packets=[];
  const server=net.createServer(socket=>{
    let str="";
    socket.on("data",d=>{
      str+=d.toString("utf8");
      let idx;
      while((idx=str.indexOf("\n"))>=0){
        const line=str.slice(0,idx).trim();str=str.slice(idx+1);
        if(!line)continue;
        const cmd=JSON.parse(line);
        packets.push(cmd);
        socket.write(JSON.stringify({id:cmd.id,result:["ok"]})+"\r\n");
      }
    });
  });
  await new Promise((resolve,reject)=>{server.once("error",reject);server.listen(0,"127.0.0.1",resolve);});
  let fake,watcher;
  let stdout="",stderr="";
  const logfile=path.join(base,"watch.log");
  try{
    fake=cp.spawn(fakePath,["-e","setInterval(function(){},1000)"],{stdio:"ignore"});
    await delay(1000);
    assert.equal(fake.exitCode,null);
    watcher=cp.spawn("powershell.exe",[
      "-NoProfile","-ExecutionPolicy","Bypass","-File",path.resolve("Watch-SignalRGB.ps1"),
      "-Watch","-IpCsv","127.0.0.1","-Port",String(server.address().port),"-LogFile",logfile
    ],{stdio:["ignore","pipe","pipe"]});
    watcher.stdout.on("data",d=>stdout+=d.toString());
    watcher.stderr.on("data",d=>stderr+=d.toString());
    await delay(3000);
    assert.equal(watcher.exitCode,null,"Watcher exited early: "+stderr);
    fake.kill();
    fake=undefined;
    for(let n=0;n<25&&packets.length<3;n++) await delay(1000);
    assert.equal(packets.length,3,
      "Watcher did not restore after exit. stderr: "+stderr+
      " stdout: "+stdout+" log: "+(fs.existsSync(logfile)?fs.readFileSync(logfile,"utf8"):"none"));
    assert.deepEqual(packets.map(x=>x.method),["set_power","set_ct_abx","set_bright"]);
    console.log("PASS: running SignalRGB.exe -> exit -> watchdog restores 4000K white automatically.");
  }finally{
    if(fake)fake.kill();
    fs.writeFileSync(flag,"stop");
    await delay(2500);
    if(watcher&&watcher.exitCode===null)watcher.kill();
    server.close();
    try{fs.unlinkSync(flag)}catch{}
    fs.rmSync(base,{recursive:true,force:true});
  }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
