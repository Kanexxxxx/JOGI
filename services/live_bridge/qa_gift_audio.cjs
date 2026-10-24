/* Focused browser QA, ephemeral loopback only. All platform events/telemetry are fixtures. */
const fs=require('node:fs'), os=require('node:os'), path=require('node:path'), assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
const {chromium}=require('C:/Users/Kanex/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const ROOT=path.resolve(__dirname,'../..'), output=path.join(__dirname,'qa-panel');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'jogi-gift-audio-qa-')), ready=path.join(temp,'ready.json');
const server=spawn(path.join(__dirname,'.venv/Scripts/python.exe'),[path.join(__dirname,'qa_panel_server.py'),'--ready-file',ready],{windowsHide:true,stdio:['ignore','ignore','pipe']});
const logs=[];server.stderr.on('data',d=>logs.push(d.toString()));
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,timeout=10000){const end=Date.now()+timeout;while(!await fn()){if(Date.now()>end)throw Error('QA condition timed out');await sleep(40);}}
let browser,consumer,ingest,pulse;
(async()=>{
  await until(()=>fs.existsSync(ready));const {port}=JSON.parse(fs.readFileSync(ready));const base=`http://127.0.0.1:${port}`;
  const installed=path.join(process.env.LOCALAPPDATA,'ms-playwright');const dir=fs.readdirSync(installed).filter(n=>/^chromium-\d+$/.test(n)).sort((a,b)=>Number(b.split('-')[1])-Number(a.split('-')[1]))[0];
  browser=await chromium.launch({headless:true,executablePath:path.join(installed,dir,'chrome-win64/chrome.exe')});
  const page=await browser.newPage({viewport:{width:1440,height:1000}}), errors=[],network=[],journeys=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});page.on('response',r=>{if(r.status()>=400)network.push({url:r.url(),status:r.status()});});
  await page.goto(base+'/admin',{waitUntil:'networkidle'});
  assert(await page.locator('#audio-apply').isDisabled());assert(await page.locator('#audio-voices').isDisabled());assert(await page.locator('#goal-gift-wrap').isHidden());
  journeys.push('Audio controls disabled without actual game telemetry; gift selector hidden for ordinary goal');
  const packets=[],fixture={type:'telemetry',state_name:'RACING',match_timer_remaining:599,race_elapsed_time:1,
    runners:[{candidate_id:1,name:'Lula',progress_m:12,current_speed:12,rank:1},{candidate_id:2,name:'Flávio',progress_m:10,current_speed:12,rank:2}],
    audio:{voice_status:'QA fixture, no sound generated',voices_enabled:true,sfx_enabled:true,crowd_enabled:true,memes_enabled:false}};
  consumer=new WebSocket(`ws://127.0.0.1:${port}/ws/godot`);
  consumer.addEventListener('message',event=>{
    const packet=JSON.parse(event.data);packets.push(packet);
    if(packet.event_type==='gift')consumer.send(JSON.stringify({type:'event_ack',event_id:packet.event_id}));
    if(packet.payload?.command==='set_audio_settings')for(const key of ['voices_enabled','sfx_enabled','crowd_enabled','memes_enabled'])fixture.audio[key]=packet.payload[key];
    if(packet.payload?.command==='set_live_goal')fixture.live_goal={...packet.payload,value:3,progress:.03};
    if(consumer.readyState===WebSocket.OPEN)consumer.send(JSON.stringify(fixture));
  });
  await until(()=>consumer.readyState===WebSocket.OPEN);pulse=setInterval(()=>{if(consumer.readyState===WebSocket.OPEN)consumer.send(JSON.stringify(fixture));},300);
  await until(async()=>!await page.locator('#audio-apply').isDisabled());
  assert(await page.locator('#audio-voices').isChecked());assert(!await page.locator('#audio-memes').isChecked());
  journeys.push('Audio checkboxes reflect explicitly seeded telemetry, never an invented enabled state');
  ingest=new WebSocket(`ws://127.0.0.1:${port}/ws/ingest`);await until(()=>ingest.readyState===WebSocket.OPEN);
  for(const id of ['5655','9999']){
    ingest.send(JSON.stringify({schema_version:'1.0',event_id:'evt_qa_gift_'+id,source:'tiktok',event_type:'gift',timestamp_ms:Date.now(),priority:'P0',user:{user_id:'qa',display_name:'QA Fixture'},payload:{candidate_slot:1,gift_tier:'T1',gift_name:'Rosa de teste',gift_id:id,unit_coin_value:1,coin_value:1,repeat_count:1,action_id:'gift_t1_turbo',boost_amount:.6,boost_duration:3,boost_percent:5}}));
  }
  await until(()=>packets.filter(p=>p.event_type==='gift').length===2);
  await page.click('#btn-refresh-gifts');await page.locator('#goal-gift-id option[value="5655"]').waitFor({state:'attached'});
  assert.equal(await page.locator('#goal-gift-id option').count(),3);
  await page.selectOption('#goal-kind','gift_specific');assert(await page.locator('#goal-gift-wrap').isVisible());
  await page.selectOption('#goal-gift-id','5655');await page.fill('#goal-target','100');await page.fill('#goal-label','Meta de rosas');await page.locator('#goal-form button').click();
  await until(()=>packets.some(p=>p.payload?.command==='set_live_goal'&&p.payload.goal_gift_id==='5655'));
  await page.locator('#goal-progress-text').filter({hasText:'3 / 100'}).waitFor();
  journeys.push('Specific goal uses the selected exact observed ID despite duplicate gift names, with confirmed progress');
  await page.uncheck('#audio-voices');await page.uncheck('#audio-crowd');await page.check('#audio-memes');await page.click('#audio-apply');
  await until(()=>packets.some(p=>p.payload?.command==='set_audio_settings'&&p.payload.voices_enabled===false&&p.payload.sfx_enabled===true&&p.payload.crowd_enabled===false&&p.payload.memes_enabled===true));
  await page.locator('#audio-confirmation').filter({hasText:'confirmado'}).waitFor();
  journeys.push('All four independent audio flags delivered by WebSocket and confirmed by telemetry fixture');
  const fallback=await browser.newContext({viewport:{width:375,height:1000}});
  await fallback.addInitScript(()=>{const Native=window.WebSocket;window.WebSocket=class extends Native{constructor(url,...rest){super(url,...rest);this.addEventListener('open',()=>this.close());}};});
  const second=await fallback.newPage();await second.goto(base+'/admin',{waitUntil:'networkidle'});await until(async()=>!await second.locator('#audio-apply').isDisabled());
  await second.check('#audio-voices');await second.uncheck('#audio-memes');await second.click('#audio-apply');
  await until(()=>packets.some(p=>p.payload?.command==='set_audio_settings'&&p.payload.voices_enabled===true&&p.payload.memes_enabled===false));
  journeys.push('HTTP fallback transmits strict boolean audio switches without an admin WebSocket');
  const views=[];
  for(const width of [375,768,1440]){
    await page.setViewportSize({width,height:1000});await page.locator('#goal-form').scrollIntoViewIfNeeded();await sleep(100);
    const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);assert(!overflow);
    const screenshot=`gift-audio-${width}.png`;await page.screenshot({path:path.join(output,screenshot),fullPage:true});views.push({width,overflow,screenshot});
  }
  assert.deepEqual(errors,[]);assert.deepEqual(network,[]);
  const report={result:'FUNCTIONAL_PASS',scope:'Ephemeral local bridge; fixture telemetry and synthetic events only; no actual live, audio playback, or platform purchase',journeys,views,console_errors:errors,network_errors:network,visual_baseline:'Not compared; functional responsive inspection only'};
  fs.writeFileSync(path.join(output,'gift-audio-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));await fallback.close();
})().catch(error=>{console.error(error.stack);process.exitCode=1;fs.writeFileSync(path.join(output,'gift-audio-failure.txt'),error.stack+'\n'+logs.join(''));}).finally(async()=>{clearInterval(pulse);consumer?.close();ingest?.close();if(browser)await browser.close();server.kill();});
