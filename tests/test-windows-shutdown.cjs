// Windows regression test for the REAL session-ending handler path.
// Does not shut Windows down; both events are simulated in process.
const cp = require("node:child_process");
const net = require("node:net");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const assert = require("node:assert/strict");
async function main(){
  if(process.platform!=="win32") throw new Error("Windows only");
  const messages=[];
  const server=net.createServer(socket=>{
    let buffer="";
    socket.on("data",data=>{
      buffer+=data.toString("utf8");
      for(;;){
        const idx=buffer.indexOf("\n");
        if(idx<0)break;
        const line=buffer.slice(0,idx).trim();
        buffer=buffer.slice(idx+1);
        if(!line)continue;
        const cmd=JSON.parse(line);
        messages.push(cmd);
        socket.write(JSON.stringify({id:cmd.id,result:["ok"]})+"\r\n");
      }
    });
  });
  await new Promise((resolve,reject)=>{server.once("error",reject);server.listen(0,"127.0.0.1",resolve);});
  const log=path.join(os.tmpdir(),"bilina-session-"+process.pid+".log");
  try {
    const processPS=cp.spawn("powershell.exe",[
      "-NoProfile","-ExecutionPolicy","Bypass","-File",path.resolve("Watch-SignalRGB.ps1"),
      "-SimulateWindowsShutdown","-IpCsv","127.0.0.1","-Port",String(server.address().port),"-LogFile",log
    ],{stdio:["ignore","pipe","pipe"]});
    let out="",err="";
    processPS.stdout.on("data",d=>out+=d.toString());
    processPS.stderr.on("data",d=>err+=d.toString());
    const exitCode=await new Promise((resolve,reject)=>{processPS.on("close",resolve);processPS.on("error",reject);});
    assert.equal(exitCode,0,"PowerShell error:\n"+out+"\n"+err);
    assert.equal(messages.length,6,"Two session phases each send three commands: "+JSON.stringify(messages));
    assert.deepEqual(messages.map(x=>x.method),
      ["set_power","set_ct_abx","set_bright","set_power","set_ct_abx","set_bright"]);
    assert.deepEqual(messages[1].params,[4000,"smooth",300]);
    const logfile=fs.readFileSync(log,"utf8");
    assert.match(logfile,/SIMULATED_WINDOWS_SHUTDOWN_OK/);
    assert.match(logfile,/WINDOWS_SHUTDOWN_LISTENER_REGISTERED/);
    assert.match(logfile,/SIMULATED_WINDOWS_SESSION_ENDING OK/);
    assert.match(logfile,/SIMULATED_WINDOWS_SESSION_ENDED OK/);
    console.log("PASS: Windows SessionEnding and SessionEnded handlers send native-white TCP commands.");
  }finally{
    server.close();
    try{fs.unlinkSync(log)}catch{}
  }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
