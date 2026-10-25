"use strict";
// Real Chromium profile handoff, loopback fixture only; no account cookies or paid API.
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),http=require('node:http'),{spawn}=require('node:child_process'),assert=require('node:assert/strict');
const handoff=require('./kwai_profile_handoff.cjs');
const {chromium}=require(path.join(os.homedir(),'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'));
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,ms=45000){const end=Date.now()+ms;while(Date.now()<end){if(await fn())return;await sleep(200);}throw new Error('Handoff fixture timed out');}
(async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'jogi-handoff-browser-')),profile=path.join(dir,'browser_profile'),lock=path.join(dir,'headed_login.lock');
 let count=0,child,context,failedNav=false,hangNext=false,lastStatus='';const server=http.createServer((req,res)=>{if(req.method==='POST'){let body='';req.on('data',b=>body+=b);req.on('end',()=>{try{lastStatus=JSON.parse(body).status||lastStatus;}catch{}});}res.setHeader('Content-Type','application/json');if(req.url==='/fixture'){count++;if(failedNav)res.statusCode=503;res.setHeader('Content-Type','text/html');const hang=hangNext;hangNext=false;res.end('<html><body>Offline local fixture</body>'+(hang?'<script>document.querySelector=()=>{while(true){}};</script>':'')+'</html>');}else res.end('{}');});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
 try{
  child=spawn(process.execPath,[path.join(__dirname,'kwai_live_collector.cjs'),'--account','qa_local','--bridge',base,'--webhook',base+'/hook','--live-url',base+'/fixture','--allow-local-test-url','--profile-dir',profile,'--heartbeat-ms','500'],{stdio:['ignore','pipe','pipe'],windowsHide:true});
  let errors='';child.stderr.on('data',b=>{errors+=b.toString();});
  await until(()=>count>0&&handoff.read(lock+'.owner')?.pid===child.pid);
  for(let cycle=0;cycle<2;cycle++){
   const request=handoff.claim(lock);await handoff.waitForRelease(lock,request);
   const dirs=fs.readdirSync(path.join(process.env.LOCALAPPDATA,'ms-playwright')).filter(x=>x.startsWith('chromium-')).sort().reverse();
   const exe=dirs.map(x=>path.join(process.env.LOCALAPPDATA,'ms-playwright',x,'chrome-win64','chrome.exe')).find(x=>fs.existsSync(x));
   context=await chromium.launchPersistentContext(profile,{headless:true,executablePath:exe});
   await context.addCookies([{name:'jogi_fixture',value:'preserved',url:base}]);
   const cookies=await context.cookies(base);assert.ok(cookies.some(x=>x.name==='jogi_fixture'));
   await context.close();context=null;const previous=count;handoff.release(lock,request);
   await until(()=>count>previous);assert.equal(child.exitCode,null);
  }
  failedNav=true;let maintenance=handoff.claim(lock);await handoff.waitForRelease(lock,maintenance);handoff.release(lock,maintenance);
  await until(()=>lastStatus==='error');
  failedNav=false;maintenance=handoff.claim(lock);await handoff.waitForRelease(lock,maintenance);handoff.release(lock,maintenance);
  await until(()=>lastStatus==='waiting_room');
  const {execFileSync}=require('node:child_process');
  let browserPid=0;await until(()=>{browserPid=Number(execFileSync('powershell.exe',['-NoProfile','-Command',`Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq ${child.pid} -and $_.Name -eq 'chrome.exe' } | Select-Object -First 1 -ExpandProperty ProcessId`],{encoding:'utf8',windowsHide:true}).trim());return browserPid>0;});
  assert.ok(browserPid>0);const beforeCrash=count;process.kill(browserPid);
  await until(()=>count>beforeCrash);assert.equal(child.exitCode,null);
  hangNext=true;maintenance=handoff.claim(lock);await handoff.waitForRelease(lock,maintenance);handoff.release(lock,maintenance);
  await until(()=>lastStatus==='error');const beforeRecovery=count;
  await until(()=>count>beforeRecovery&&lastStatus==='waiting_room',60000);assert.equal(child.exitCode,null);
  console.log(JSON.stringify({renderer_hang_recovered:true,result:'PASS',cycles:2,real_chromium:true,same_collector_pid:true,chromium_crash_recovered:true,http503_distinguished_from_offline:true,public_live:false,external_requests:false,profile:dir}));
 }finally{
  if(context)await context.close();
  if(child&&child.exitCode===null){const req=handoff.claim(lock);try{await handoff.waitForRelease(lock,req);child.kill();await new Promise(r=>child.once('exit',r));}finally{handoff.release(lock,req);}}
await new Promise(r=>server.close(r));
 }
})().catch(e=>{console.error(e.message);process.exitCode=1;});
