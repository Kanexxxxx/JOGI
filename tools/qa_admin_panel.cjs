/* Reproducible Browser QA against an ephemeral bridge; telemetry consumer is an explicit test fixture. */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawn} = require('node:child_process');
const assert = require('node:assert/strict');
const {chromium} = require('C:/Users/Kanex/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const ROOT = path.resolve(__dirname, '..');
const output = path.join(ROOT, 'services/live_bridge/qa-panel');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'jogi-panel-qa-'));
const readyFile = path.join(temporary, 'ready.json');
const python = path.join(ROOT, 'services/live_bridge/.venv/Scripts/python.exe');
const server = spawn(python, [path.join(ROOT, 'services/live_bridge/qa_panel_server.py'), '--ready-file', readyFile], {windowsHide: true, stdio: ['ignore','pipe','pipe']});
let browser, consumer; const backendLogs = [];
server.stderr.on('data', d => backendLogs.push(d.toString()));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate, timeout=10000) { const end=Date.now()+timeout; while(!await predicate()) { if(Date.now()>end) throw new Error('QA condition timed out'); await sleep(40); } }
(async () => {
  fs.mkdirSync(output,{recursive:true});
  await until(() => fs.existsSync(readyFile));
  const {port} = JSON.parse(fs.readFileSync(readyFile,'utf8'));
  const base=`http://127.0.0.1:${port}`;
  const installed = path.join(process.env.LOCALAPPDATA,'ms-playwright');
  const chromiumDir = fs.readdirSync(installed).filter(n=>/^chromium-\d+$/.test(n)).sort((a,b)=>Number(b.split('-')[1])-Number(a.split('-')[1]))[0];
  browser=await chromium.launch({headless:true, executablePath:path.join(installed,chromiumDir,'chrome-win64/chrome.exe')});
  const context=await browser.newContext({viewport:{width:1440,height:1000}});
  const page=await context.newPage(); const errors=[], failed=[], interactions=[], visuals=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{if(message.type()==='error') errors.push(message.text());});
  page.on('response',response=>{if(response.status()>=400) failed.push({url:response.url(),status:response.status()});});
  await page.addInitScript(() => { window.__qaVitals={cls:0,lcp:null};
    try {new PerformanceObserver(list=>{for(const item of list.getEntries()) if(!item.hadRecentInput) window.__qaVitals.cls+=item.value;}).observe({type:'layout-shift',buffered:true});
      new PerformanceObserver(list=>{for(const item of list.getEntries()) window.__qaVitals.lcp=item.startTime;}).observe({type:'largest-contentful-paint',buffered:true});} catch(_) {}
  });
  await page.goto(`${base}/admin`,{waitUntil:'networkidle'});
  await page.locator('#text-backend-status').filter({hasText:'TIKTOK'}).waitFor();
  const initialRace=await page.locator('#race-state-badge').textContent();
  await page.click('#btn-start-race'); await sleep(250);
  assert.equal(await page.locator('#race-state-badge').textContent(), initialRace, 'Offline controls must not invent a race state');
  interactions.push('Start without Godot queues request; no invented race state');
  const packets=[];
  consumer=new WebSocket(`ws://127.0.0.1:${port}/ws/godot`);
  consumer.addEventListener('message', event=>{const value=JSON.parse(event.data);packets.push(value);if(value.event_type==='gift')consumer.send(JSON.stringify({type:'event_ack',event_id:value.event_id}));});
  await until(()=>consumer.readyState===WebSocket.OPEN);
  await until(()=>packets.some(p=>p.payload?.command==='start_race'));
  for(const [id,command] of [['btn-pause-race','pause_race'],['btn-resume-race','resume_race'],['btn-skip-lobby','skip_lobby']]) {
    await page.click(`#${id}`); await until(()=>packets.some(p=>p.payload?.command===command)); interactions.push(command);
  }
  await page.click('#btn-restart-race'); await page.click('#btn-confirm-restart');
  await until(()=>packets.some(p=>p.payload?.command==='restart_race')); interactions.push('restart modal');
  await page.selectOption('#goal-kind','follows'); await page.fill('#goal-target','250'); await page.fill('#goal-label','Torcida Brasil');
  await page.fill('#goal-target','0'); await page.locator('#goal-form button').click();
  assert.equal(await page.locator('#goal-target').evaluate(e=>e.checkValidity()),false);
  assert(!packets.some(p=>p.payload?.command==='set_live_goal'&&p.payload.goal_target===0));
  interactions.push('invalid goal blocked by form validation'); await page.keyboard.press('Escape'); await page.fill('#goal-target','250');
  await page.locator('#goal-form button').click();
  await until(()=>packets.some(p=>p.payload?.command==='set_live_goal'&&p.payload.goal_target===250)); interactions.push('goal via WS');
  await page.fill('#mg-likes-target','1500');
  await page.fill('#mg-gifts-target','300');
  await page.fill('#mg-follows-target','10000');
  await page.fill('#mg-follows-baseline','8400');
  await page.click('#btn-apply-multi-goals');
  await until(()=>packets.some(p=>p.payload?.command==='set_live_goals'&&p.payload.live_goals?.follows?.goal_target===10000&&p.payload.live_goals?.follows?.follower_baseline===8400));
  interactions.push('simultaneous 3-goals (likes + gifts + 10k follows with manual baseline) via WS');
  await page.selectOption('#sim-vote-cand','2'); await page.click('#btn-sim-vote');
  await until(()=>packets.some(p=>p.event_type==='vote'&&p.payload.candidate_slot===2)); interactions.push('vote');
  await page.click('#btn-like-50'); await page.click('#btn-sim-share'); await page.click('#btn-sim-follow');
  await until(()=>['like_batch','share','follow'].every(kind=>packets.some(p=>p.event_type===kind))); interactions.push('likes, share, follow');
  await page.fill('#sim-gift-coins','42'); await page.fill('#sim-gift-count','3'); await page.click('#btn-sim-custom-gift');
  await until(()=>packets.some(p=>p.event_type==='gift'&&p.payload.coin_value===126&&p.payload.repeat_count===3)); interactions.push('real-value gift 42x3=126 once');
  await page.click('#btn-refresh-gifts');
  await page.locator('#gift-catalog-list select').first().waitFor();
  await page.locator('#gift-catalog-list select').first().selectOption('attack');
  await until(async()=> (await (await fetch(`${base}/api/gifts`)).json()).entries.some(e=>e.action==='attack'&&e.override));
  await page.click('#btn-sim-custom-gift');
  await until(()=>packets.some(p=>p.event_type==='gift'&&p.payload.coin_value===126&&p.payload.gift_tier==='T3'&&p.payload.action_id==='gift_t3_attack'));
  interactions.push('catalog ID/action override applied to next gift, value unchanged');
  for(const action of ['turbo','shield','attack']) { await page.locator(`button[data-slot="1"][data-action="${action}"]`).click(); }
  await until(()=>['boost','shield','attack'].every(command=>packets.some(p=>p.payload?.command===command))); interactions.push('candidate controls');
  // Explicit seeded QA telemetry verifies frontend mapping. This is not a real game or live.
  const fixture={type:'telemetry',state_name:'RACING',match_timer_remaining:599,race_elapsed_time:1,
    runners:[{candidate_id:1,name:'Lula',progress_m:12,current_speed:12,rank:2},{candidate_id:2,name:'Flávio',progress_m:15,current_speed:15,rank:1}],
    audience:{session:{votes:[0,5,6],coins:[6,20,30],likes:[0,50,20],shares:[0,1,2],gifts:[1,2,3],follows:[0,1,2]},top_supporters:[{display_name:'QA Pessoa',team:2,coins:30}]},
    live_goal:{goal_kind:'follows',goal_target:250,goal_label:'Torcida Brasil',value:3,progress:0.012},audio:{voice_status:'Fixture de QA; áudio não executado',voices_ready:false}};
  consumer.send(JSON.stringify(fixture));
  await until(async()=> (await page.locator('#audience-totals').textContent()).includes('Presentes 6'));
  const totals=await page.locator('#audience-totals').textContent();assert(totals.includes('Moedas 56'));assert(totals.includes('Seguidores 3'));interactions.push('gift count/coin count mapped separately from telemetry');
  await page.locator('#goal-progress-text').filter({hasText:'3 / 250'}).waitFor();
  await page.locator('#mg-follows-progress').filter({hasText:'8.403 / 10.000'}).waitFor();
  // Force only the admin socket offline in a new browser context to exercise supported HTTP fallback.
  const fallback=await browser.newContext({viewport:{width:1440,height:1000}});
  await fallback.addInitScript(()=>{const Native=window.WebSocket;window.WebSocket=class extends Native {constructor(url,...rest){super(url,...rest);this.addEventListener('open',()=>this.close());}};});
  const fallbackPage=await fallback.newPage();await fallbackPage.goto(`${base}/admin`,{waitUntil:'networkidle'});await sleep(100);
  await fallbackPage.selectOption('#goal-kind','coins');await fallbackPage.fill('#goal-target','500');await fallbackPage.fill('#goal-label','Meta HTTP');await fallbackPage.locator('#goal-form button').click();
  await until(()=>packets.some(p=>p.payload?.command==='set_live_goal'&&p.payload.goal_target===500&&p.payload.goal_kind==='coins'));interactions.push('HTTP fallback sets actual goal');
  await fallbackPage.click('#btn-sim-follow');await sleep(150);interactions.push('HTTP follow receipt');
  await fallback.close();
  const vitals=await page.evaluate(()=>window.__qaVitals);
  const labelAudit=await page.evaluate(()=>Array.from(document.querySelector('body').querySelectorAll('input,select,button')).filter(e=>!e.disabled&&!e.closest('[hidden]')).filter(e=>!(e.getAttribute('aria-label')||e.labels?.length||e.textContent.trim())).map(e=>e.id||e.tagName));
  for(const width of [375,768,1440]) {
    await page.setViewportSize({width,height:1000});await sleep(150);
    const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth+1);
    const file=`admin-${width}.png`;await page.screenshot({path:path.join(output,file),fullPage:true});visuals.push({width,overflow,screenshot:file});
  }
  assert.equal(errors.length,0,JSON.stringify(errors));assert.equal(failed.length,0,JSON.stringify(failed));assert.equal(labelAudit.length,0,JSON.stringify(labelAudit));
  assert.equal(visuals.some(v=>v.overflow),false,JSON.stringify(visuals));
  const report={result:visuals.some(v=>v.overflow)?'SHIP_WITH_FIXES':'FUNCTIONAL_PASS',verdict:'INCONCLUSIVE',verdict_reason:'Functional checks passed; no approved visual baseline and no full WCAG audit.',scope:'ephemeral loopback; test consumer/seeded telemetry; no actual platform live',
    interactions,console_errors:errors,network_errors:failed,visuals,visual_regression:'INCONCLUSIVE: no approved screenshot baseline',
    accessibility:{audit:'DOM label/name checks only, not full WCAG/axe',missing_labels:labelAudit},web_vitals:{...vitals,inp:'not measured'},packets_received:packets.length};
  fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
})().catch(error=>{console.error(error.stack);process.exitCode=1;fs.mkdirSync(output,{recursive:true});fs.writeFileSync(path.join(output,'failure.txt'),`${error.stack}\n${backendLogs.join('')}`);}).finally(async()=>{try{consumer?.close();}catch(_){}if(browser)await browser.close();server.kill();});
