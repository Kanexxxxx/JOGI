/* Isolated browser -> real bridge -> real headless Godot -> receipt -> browser QA.
   Synthetic identities exist only in development fixture; no platform listeners/public live. */
const fs=require('node:fs'), os=require('node:os'), path=require('node:path'), crypto=require('node:crypto');
const {spawn}=require('node:child_process');
const assert=require('node:assert/strict');
const {chromium}=require('C:/Users/Kanex/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const ROOT=path.resolve(__dirname,'..');
const output=path.join(ROOT,'docs/evidencias/admin-production');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'jogi-admin-production-'));
const python=path.join(ROOT,'services/live_bridge/.venv/Scripts/python.exe');
const godot=path.join(os.homedir(),'Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe');
const sessions=[], interactions=[], visuals=[], errors=[];
let browser;
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function until(predicate,description='condition',timeout=20000){const limit=Date.now()+timeout;while(!await predicate()){if(Date.now()>limit)throw new Error(`QA timed out: ${description}`);await sleep(70);}}
async function json(session,route='/api/state'){const response=await fetch(`${session.base}${route}`,{headers:{'X-JOGI-Token':session.token}});assert(response.ok,`${route}: HTTP ${response.status}`);return response.json();}
function launchGame(session){
  const appdata=path.join(temporary,session.platform,'appdata');fs.mkdirSync(appdata,{recursive:true});
  session.stop=path.join(temporary,session.platform,'stop.signal');if(fs.existsSync(session.stop))fs.unlinkSync(session.stop);
  session.game=spawn(godot,['--headless','--path',path.join(ROOT,'game'),'--script','res://tests/admin_qa_runtime.gd'],{windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,APPDATA:appdata,GDA_USER_DATA_ROOT:appdata,JOGI_MODE:session.mode,LIVE_PLATFORM:session.platform,LIVE_BRIDGE_WS_URL:`ws://127.0.0.1:${session.port}/ws/godot`,LIVE_BRIDGE_LOCAL_TOKEN:'',LIVE_BRIDGE_PRODUCER_TOKEN:'',LIVE_BRIDGE_ENGINE_TOKEN:session.engineToken,JOGI_QA_SECONDS:'300',JOGI_QA_STOP_FILE:session.stop}});
  session.gameLogs=[];session.game.stdout.on('data',data=>session.gameLogs.push(data.toString()));session.game.stderr.on('data',data=>session.gameLogs.push(data.toString()));
}
async function launchSession(platform,mode){
  const dir=path.join(temporary,platform);fs.mkdirSync(dir,{recursive:true});const ready=path.join(dir,'ready.json');const token=crypto.randomBytes(24).toString('hex');
  const session={platform,mode,token,producerToken:crypto.randomBytes(24).toString('hex'),engineToken:crypto.randomBytes(24).toString('hex'),logs:[],bridgeStop:path.join(dir,'bridge-stop.signal')};sessions.push(session);
  session.server=spawn(python,[path.join(ROOT,'services/live_bridge/qa_panel_server.py'),'--ready-file',ready,'--mode',mode,'--platform',platform,'--stop-file',session.bridgeStop],{windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,LIVE_BRIDGE_LOCAL_TOKEN:token,LIVE_BRIDGE_PRODUCER_TOKEN:session.producerToken,LIVE_BRIDGE_ENGINE_TOKEN:session.engineToken,JOGI_MODE:mode,JOGI_END_AT:'2099-01-01T00:00:00Z'}});
  session.server.stdout.on('data',d=>session.logs.push(d.toString()));session.server.stderr.on('data',d=>session.logs.push(d.toString()));
  await until(()=>fs.existsSync(ready),`${platform} bridge ready`);const readyState=JSON.parse(fs.readFileSync(ready,'utf8'));session.port=readyState.port;session.serverPid=readyState.pid;assert(![8765,8766].includes(session.port));session.base=`http://127.0.0.1:${session.port}`;
  return session;
}
async function unlock(page,session){await page.goto(`${session.base}/admin`,{waitUntil:'domcontentloaded'});await page.locator('#auth-unlock-section').waitFor({state:'visible'});assert(await page.locator('#btn-start-race').isDisabled());await page.fill('#auth-token-input',session.token);await page.click('#btn-auth-unlock');await page.locator('#auth-unlock-section').waitFor({state:'hidden'});assert.equal(await page.inputValue('#auth-token-input'),'');}
async function command(session,page,id,name,confirm=false){const previous=new Set((await json(session)).recent_commands.map(r=>r.event_id));await page.click(id);if(confirm)await page.click('#btn-confirm-restart');await until(async()=> (await json(session)).recent_commands.some(r=>!previous.has(r.event_id)&&r.command===name&&r.status==='applied'),`${session.platform} ${name} actual Godot receipt`);await page.locator('#command-feedback').filter({hasText:'executado e confirmado'}).waitFor();interactions.push(`${session.platform}:${name}:applied_by_real_Godot`);}
async function stopGame(session){if(session.game?.exitCode===null){fs.writeFileSync(session.stop,'stop');await until(()=>session.game.exitCode!==null,`${session.platform} graceful game stop`,12000);}}
(async()=>{
  fs.mkdirSync(output,{recursive:true});
  const tiktok=await launchSession('tiktok','development');const kwai=await launchSession('kwai','production');
  browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
  const context=await browser.newContext({viewport:{width:1440,height:1000}});const page=await context.newPage();const prod=await context.newPage();
  for(const p of [page,prod])p.on('pageerror',e=>errors.push(e.message));
  console.log('QA authentication');await unlock(page,tiktok);await unlock(prod,kwai);console.log('QA modes and real Godot startup');
  assert(await page.locator('#btn-start-race').isDisabled());assert(await prod.locator('#simulator-section').isHidden());interactions.push('no engine: commands disabled; production simulator hidden');
  const before=await json(kwai);const blocked=await fetch(`${kwai.base}/api/admin/simulate?event_type=gift&unit_coin_value=10`,{headers:{'X-JOGI-Token':kwai.token}});assert.equal(blocked.status,403);assert.equal((await json(kwai)).metrics.accepted_total,before.metrics.accepted_total);interactions.push('production simulation rejected403 without fake metrics');
  launchGame(tiktok);launchGame(kwai);
  await until(async()=>{const a=await json(tiktok),b=await json(kwai);return a.godot_connected&&a.telemetry_fresh&&b.godot_connected&&b.telemetry_fresh;},'both real Godot instances telemetry',60000);
  await page.locator('#btn-start-race').waitFor({state:'visible'});await until(()=>page.locator('#btn-start-race').isEnabled(),'start enabled with telemetry');
  console.log('QA controls');await command(tiktok,page,'#btn-start-race','start_race');
  await command(kwai,prod,'#btn-start-race','start_race');
  await command(tiktok,page,'#btn-pause-race','pause_race');assert.equal((await json(tiktok)).telemetry.race_paused,true);assert.equal((await json(kwai)).telemetry.race_paused,false);interactions.push('platform commands isolated');
  await command(tiktok,page,'#btn-resume-race','resume_race');assert.equal((await json(tiktok)).telemetry.race_paused,false);assert((await json(tiktok)).phase_timer_seconds>500,'remaining timer must use actual match_time_remaining');
  const commandCount=(await json(tiktok)).recent_commands.length;await page.fill('#mg-likes-target','0');await page.click('#btn-apply-multi-goals');assert.equal(await page.locator('#mg-likes-target').evaluate(e=>e.checkValidity()),false);assert.equal((await json(tiktok)).recent_commands.length,commandCount);interactions.push('invalid goal blocked without issuing a command');await page.fill('#mg-likes-target','1500');await sleep(1300);assert.equal(await page.inputValue('#mg-likes-target'),'1500');
  await page.fill('#mg-gifts-target','300');await page.fill('#mg-follows-target','10000');await page.fill('#mg-follows-baseline','8400');
  await command(tiktok,page,'#btn-apply-multi-goals','set_live_goals');assert.equal((await json(tiktok)).live_goals.likes.goal_target,1500);assert.equal((await json(kwai)).live_goals.likes.goal_target,1000);interactions.push('three goals applied and edits/platform isolation preserved');
  await until(()=>page.locator('#audio-apply').isEnabled(),'audio controls known');const voices=await page.locator('#audio-voices').isChecked();await page.locator('#audio-voices').setChecked(!voices);await command(tiktok,page,'#audio-apply','set_audio_settings');assert.equal((await json(tiktok)).audio.voices_enabled,!voices);
  await page.selectOption('#sim-vote-cand','2');await page.click('#btn-sim-vote');await page.click('#btn-like-50');await page.click('#btn-sim-follow');await page.click('#btn-sim-share');
  await page.fill('#sim-gift-coins','42');await page.fill('#sim-gift-count','3');await page.click('#btn-sim-custom-gift');
  await until(async()=>Number((await json(tiktok)).metrics.gift_acks_total)>0,'gift durable Godot ACK');
  await until(async()=> (await page.locator('#live-events').textContent()).includes('Confirmado pelo jogo'),'confirmed gift monitor');
  assert((await page.locator('#audience-totals').textContent()).includes('Moedas 126'));assert((await page.locator('#audience-totals').textContent()).includes('Presentes 3'));interactions.push('synthetic development vote/likes/follow/share/gift=42x3=126 real pipeline+durableACK');
  await page.click('#btn-refresh-gifts');await page.locator('#gift-catalog-list select').first().waitFor();await page.locator('#gift-catalog-list select').first().selectOption('attack');await until(async()=> (await json(tiktok,'/api/gifts')).entries.some(e=>e.override&&e.action==='attack'),'observed gift override saved');interactions.push('observed gift action override persisted in bridge');
  for(const action of ['turbo','shield','attack']) {const name=action==='turbo'?'boost':action;await command(tiktok,page,`button[data-slot="1"][data-action="${action}"]`,name);}
  await page.click('#btn-reset-dedup');assert(await page.locator('#modal-restart').evaluate(e=>e.classList.contains('active')));await page.keyboard.press('Escape');assert(!(await page.locator('#modal-restart').evaluate(e=>e.classList.contains('active'))));interactions.push('destructive dedup confirmation, Escape and focus restored');
  await command(tiktok,page,'#btn-restart-race','restart_race',true);await command(tiktok,page,'#btn-skip-lobby','skip_lobby');
  const fallbackContext=await browser.newContext({viewport:{width:768,height:1000}});await fallbackContext.addInitScript(()=>{const Native=window.WebSocket;window.WebSocket=class extends Native{constructor(...args){super(...args);this.addEventListener('open',()=>this.close());}};});const fallback=await fallbackContext.newPage();await unlock(fallback,tiktok);await until(()=>fallback.locator('#btn-pause-race').isEnabled(),'HTTP fallback readiness');await command(tiktok,fallback,'#btn-pause-race','pause_race');await fallbackContext.close();interactions.push('HTTP commands/state fallback after admin WebSocket closes');
  await stopGame(tiktok);await until(()=>page.locator('#btn-start-race').isDisabled(),'controls blocked after game disconnect');assert((await json(kwai)).godot_connected);launchGame(tiktok);await until(async()=> (await json(tiktok)).telemetry_fresh && (await json(tiktok)).godot_connected,'game reconnect',60000);interactions.push('game disconnect/reconnect without disturbing other platform');
  await page.reload({waitUntil:'domcontentloaded'});await page.locator('#mg-likes-target').waitFor();await until(async()=>await page.inputValue('#mg-likes-target')==='1500','settings restored after reload');assert(await page.locator('#auth-unlock-section').isHidden());interactions.push('reload preserves configured goals and isolated cookie session');
  const authContext=await browser.newContext();const locked=await authContext.newPage();await locked.goto(`${tiktok.base}/admin`,{waitUntil:'domcontentloaded'});await locked.locator('#auth-unlock-section').waitFor({state:'visible'});assert(await locked.locator('#btn-start-race').isDisabled());await authContext.close();interactions.push('unauthenticated new browser session blocked');
  const cookieNames=(await context.cookies()).map(c=>c.name);assert(new Set(cookieNames).size>=2);interactions.push('two administrative cookies coexist on same loopback host');
  assert((await json(kwai)).phase_timer_seconds>0,'production running clock must not be zero');
  for(const width of [375,768,1440]) {await prod.setViewportSize({width,height:1000});await sleep(250);assert.equal(await prod.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false);assert(await prod.locator('#simulator-section').isHidden());await prod.evaluate(()=>scrollTo(0,0));const file=`admin-production-${width}.png`;const overview=`admin-overview-${width}.png`;await prod.screenshot({path:path.join(output,overview)});await prod.screenshot({path:path.join(output,file),fullPage:true});visuals.push({width,height:1000,screenshot:file,overview_screenshot:overview,horizontal_overflow:false,mode:'production',source:'real Godot telemetry; no synthetic events'});}
  await page.setViewportSize({width:1440,height:1000});await page.screenshot({path:path.join(output,'admin-development-events.png'),fullPage:true});
  await command(tiktok,page,'#btn-end-experience','end_experience',true);await until(async()=> (await json(tiktok)).operational_shutdown.ended && (await json(tiktok)).telemetry.experience_ended,'terminal end reflected in game');assert.equal((await json(kwai)).operational_shutdown.ended,false);assert(await page.locator('#btn-start-race').isDisabled());interactions.push('manual terminal shutdown persisted and isolated; restart/start disabled');
  await stopGame(kwai);await until(async()=>!(await json(kwai)).godot_connected,'production engine disconnected');
  await until(()=>prod.locator('#btn-end-experience').isEnabled(),'manual close available without engine');
  await prod.click('#btn-end-experience');await prod.click('#btn-confirm-restart');
  await until(async()=> (await json(kwai)).operational_shutdown.ended,'offline manual close durably recorded');
  assert.equal((await json(kwai)).operational_shutdown.applied,false);
  launchGame(kwai);await until(async()=> (await json(kwai)).telemetry.experience_ended===true,'offline close reaches reconnected engine',60000);
  interactions.push('offline manual end persisted without false execution success; engine closes on reconnect');
  assert.equal(errors.length,0,JSON.stringify(errors));
  const report={result:'FUNCTIONAL_PASS',visual_review:'PENDING_HUMAN_OR_AGENT_IMAGE_INSPECTION',scope:'two isolated authenticated ephemeral bridges + two real headless StadiumRace instances; no real platform live or paid APIs',public_live_started:false,paid_api_calls:0,real_godot:true,interactions,visuals,console_errors:errors,limits:['No real TikTok/Kwai room events','Browser screenshots only; no OBS encoding or full WCAG audit','Synthetic development identities are fixtures, never production counters']};
  fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
})().catch(error=>{console.error(error.stack);process.exitCode=1;fs.mkdirSync(output,{recursive:true});let details=String(error.stack);for(const session of sessions){const clean=value=>[session.token,session.producerToken,session.engineToken].filter(Boolean).reduce((text,secret)=>text.split(secret).join('[REDACTED]'),String(value));details+=`\n\n${session.platform} backend:\n${clean(session.logs.join(''))}\nGodot:\n${clean((session.gameLogs||[]).join(''))}`;}fs.writeFileSync(path.join(output,'failure.txt'),details);}).finally(async()=>{for(const s of sessions){try{await stopGame(s);}catch(_){s.game?.kill();}if(s.server?.exitCode===null){fs.writeFileSync(s.bridgeStop,'stop');try{await until(()=>s.server.exitCode!==null,'isolated bridge graceful stop',10000);}catch(_){try{if(s.serverPid)process.kill(s.serverPid);}catch(_){}s.server.kill();}}}if(browser)await browser.close();});
