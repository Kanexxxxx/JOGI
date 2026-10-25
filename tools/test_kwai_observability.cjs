'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {CollectorDiagnostics,normalizeFeedPayload,installDomObserver}=require('./kwai_live_collector.cjs');
const {chooseLiveLink}=require('./kwai_live_collector.cjs');
test('discovery only follows a unique real live anchor',()=>{
 const base='https://www.kwai.com/@mentalista..';
 assert.equal(chooseLiveLink([{href:'/live/real-room',owner:'mentalista..',liveBadge:true}],base),'https://www.kwai.com/live/real-room');
 assert.equal(chooseLiveLink([{href:'/live/wrong',owner:'outra-conta',liveBadge:true}],base),null);
 for(const links of [[{href:'https://evil.invalid/live/id',liveBadge:true}],[{href:'/live/share',liveBadge:true}],[{href:'/live/id'}],[{href:'/live/a',liveBadge:true},{href:'/live/b',liveBadge:true}]])assert.equal(chooseLiveLink(links,base),null);
});
test('normalization preserves source clock without inventing a user ID',()=>{
 const result=normalizeFeedPayload({commentFeeds:[{id:'a',comment:'13',display_name:'Same',timestamp_ms:1792890000123},{id:'b',comment:'22',display_name:'Same',time:1792890000}]}).events;
 assert.equal(result[0].timestamp_ms,1792890000123);assert.equal(result[0].timestamp_precision,'milliseconds');assert.equal(result[1].timestamp_ms,1792890000000);assert.equal(result[1].timestamp_precision,'seconds');assert.equal(result[0].user_id,'anon_kwai');
});
test('diagnostics distinguish observed comments, votes and nonvotes without retaining private text',()=>{
 const d=new CollectorDiagnostics();d.observe({type:'comment',comment:'JOGI-TESTE-01',user_id:'private-id',display_name:'Private User'});d.observe({type:'comment',comment:'13'});d.observe({type:'comment',comment:'22'});d.observe({type:'gift'});
 const state=d.snapshot({forwarded:1,pending:2});assert.equal(state.comments_observed,3);assert.equal(state.votes_valid,2);assert.equal(state.comments_non_vote,1);assert.equal(state.gifts_identified,1);assert.equal(state.gifts_backend_confirmed,1);assert.equal(state.gifts_pending,2);assert.equal(state.feed_connected,false);assert.equal(state.room_detected,'unknown');assert.doesNotMatch(JSON.stringify(state),/private-id|Private User|JOGI-TESTE/);
});
test('parser reports rejected event candidates separately from absent data',()=>{
 const parsed=normalizeFeedPayload({events:[{type:'unknown',secret:'no logs'},{type:'comment',comment:''},{type:'comment',comment:'13',id:'c1'}]},{trustedLiveSource:true});assert.equal(parsed.events.length,1);assert.equal(parsed.rejected,2);
 const absent=normalizeFeedPayload({data:{title:'not a feed'}});assert.equal(absent.events.length,0);assert.equal(absent.rejected,0);
});
test('DOM repeated valid messages from different elements keep unique IDs while rescanning deduplicates the same elements',()=>{
 const emitted=[];let mutate;const node=()=>({dataset:{},textContent:'Viewer 13',querySelector:q=>({textContent:q.includes('name')?'Viewer':'13'})});const elements=[node(),node()];
 const doc={readyState:'complete',documentElement:{},querySelector:()=>null,querySelectorAll:q=>q==='video'?[{readyState:3,ended:false,videoWidth:100}]:q.includes('chat-item')?elements:[]};
 const sandbox={document:doc,window:{location:{href:'https://www.kwai.com/live/fixture'},__jogiKwaiEmit:x=>emitted.push(x)},MutationObserver:class{constructor(fn){mutate=fn;}observe(){}}};
 vm.runInNewContext('('+installDomObserver.toString()+')()',sandbox);assert.equal(emitted.length,2);assert.notEqual(emitted[0].id,emitted[1].id);assert.equal(emitted[0].__jogiUnstableDomId,true);assert.equal(emitted[0].comment,'13');mutate([]);assert.equal(emitted.length,2);const native=node();native.dataset.id='platform-message-1';elements.push(native);mutate([]);assert.equal(emitted.length,3);assert.equal(emitted[2].id,'platform-message-1');assert.equal(emitted[2].__jogiUnstableDomId,false);
});

test('HTTP success is distinct from backend ingestion and intentional nonvote filtering',async t=>{
 const http=require('node:http');const {postEventWebhook}=require('./kwai_live_collector.cjs');
 const server=http.createServer((req,res)=>{res.setHeader('Content-Type','application/json');res.end(JSON.stringify({status:'ok',ingested:req.url==='/accepted'}));});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>new Promise(r=>server.close(r)));const base='http://127.0.0.1:'+server.address().port;
 assert.equal((await postEventWebhook(base+'/accepted',{type:'comment',comment:'13'})).ingested,true);
 const filtered=await postEventWebhook(base+'/ignored',{type:'comment',comment:'hello'});assert.equal(filtered.transport_ok,true);assert.equal(filtered.ingested,false);
});
