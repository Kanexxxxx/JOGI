"use strict";
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const os=require('node:os');const path=require('node:path');
const handoff=require('./kwai_profile_handoff.cjs');
function fixture(t){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'jogi-handoff-test-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));return path.join(dir,'headed_login.lock');}
test('only one live owner can request login; another request is preserved',t=>{const file=fixture(t);const request=handoff.claim(file);assert.throws(()=>handoff.claim(file),/Outro login/);assert.deepEqual(handoff.read(file),request);handoff.release(file,{pid:process.pid,nonce:'wrong'});assert.deepEqual(handoff.read(file),request);handoff.release(file,request);assert.equal(fs.existsSync(file),false);});
test('waits for explicit release from active collector before granting profile',async t=>{const file=fixture(t);const request=handoff.claim(file);const owner=handoff.claim(file+'.owner');let waits=0;await handoff.waitForRelease(file,request,{sleep:async()=>{waits++;assert.equal(waits,1);assert.equal(handoff.acknowledge(file,request),true);}});assert.equal(waits,1);assert.deepEqual(handoff.read(file+'.owner'),owner);});
test('stale acknowledgement cannot release a different login request',async t=>{const file=fixture(t);const request=handoff.claim(file);handoff.claim(file+'.owner');fs.writeFileSync(file+'.released',JSON.stringify({...request,nonce:'old'}));await assert.rejects(handoff.waitForRelease(file,request,{timeoutMs:10,pollMs:1}),/nÃ£o confirmou/);assert.deepEqual(handoff.read(file),request);});
test('handoff does not modify cookies or the durable gift queue',async t=>{const file=fixture(t);const queue=path.join(path.dirname(file),'collector_gifts.sqlite3');const cookies=path.join(path.dirname(file),'Cookies');fs.writeFileSync(queue,'paid rows fixture');fs.writeFileSync(cookies,'existing session');const before=fs.readFileSync(queue);const request=handoff.claim(file);handoff.claim(file+'.owner');handoff.acknowledge(file,request);await handoff.waitForRelease(file,request);handoff.release(file,request);assert.deepEqual(fs.readFileSync(queue),before);assert.equal(fs.readFileSync(cookies,'utf8'),'existing session');});
test('login opens only the browser and never opens or pumps paid queue',async t=>{
 const {EventEmitter}=require('node:events');const {runLoginBrowser}=require('./kwai_live_collector.cjs');
 const file=fixture(t);const dir=path.dirname(file);const queue=path.join(dir,'collector_gifts.sqlite3');
 fs.writeFileSync(queue,'existing paid data - must never be opened by login');const before=fs.readFileSync(queue);
 const oldClaim=handoff.claim;handoff.claim=(target)=>{const request=oldClaim(target);if(target===file){oldClaim(file+'.owner');handoff.acknowledge(file,request);}return request;};t.after(()=>{handoff.claim=oldClaim;});
 let launches=0;const context=new EventEmitter();context.close=async()=>context.emit('close');
 context.pages=()=>[{goto:async url=>{assert.equal(url,'https://www.kwai.com/');queueMicrotask(()=>context.emit('close'));}}];
 await runLoginBrowser({profileDir:path.join(dir,'browser_profile')},{launchPersistentContext:async(profile,options)=>{launches++;assert.equal(options.headless,false);return context;}},undefined,file);
 assert.equal(launches,1);assert.deepEqual(fs.readFileSync(queue),before);assert.equal(fs.existsSync(file),false);
});

test('old collector without owner acknowledgement never opens profile',async t=>{const file=fixture(t);const request=handoff.claim(file);await assert.rejects(handoff.waitForRelease(file,request),/não confirmou/);assert.deepEqual(handoff.read(file),request);});
