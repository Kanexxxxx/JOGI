"""Isolated SDK-shaped comment -> bridge -> real Godot -> HUD test; no LIVE/network SDK."""
from __future__ import annotations
import asyncio,json,os,secrets,subprocess,sys,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'services/live_bridge'))
from server import LiveBridgeServer
from adapters.tiktok_adapter import TikTokLiveAdapter,TikTokAdapterConfig,CommentEvent
from TikTokLiveProto.v3.webcast.shared.message import CommonMessageData
GODOT=Path.home()/'Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe'

async def until(fn,seconds=45):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  if fn():return
  await asyncio.sleep(.05)
 raise AssertionError('isolated integration condition timed out')

def vote_count(bridge,slot):
 votes=bridge.latest_telemetry.get('audience',{}).get('session',{}).get('votes',{})
 return int(votes[slot]) if isinstance(votes,list) and len(votes)>slot else int(votes.get(str(slot),votes.get(slot,0))) if isinstance(votes,dict) else -1

async def main():
 runtime=Path(tempfile.mkdtemp(prefix='jogi-tiktok-cards-e2e-'))
 token=secrets.token_urlsafe(32)
 bridge=LiveBridgeServer(port=0,platform='tiktok',account='qa_cards_local',runtime_mode='development',outbox_path=runtime/'gifts.sqlite3',local_token=secrets.token_urlsafe(32),producer_token=token,engine_token='')
 game=None
 report={'scope':'isolated SDK CommentEvent -> authenticated real bridge/Godot -> HUD telemetry','public_live':False,'external_sdk_requests':False,'synthetic_production_events':False}
 await bridge.start()
 try:
  env=os.environ.copy();env.update(APPDATA=str(runtime/'appdata'),GDA_USER_DATA_ROOT=str(runtime/'appdata'),LIVE_PLATFORM='tiktok',JOGI_MODE='development',LIVE_BRIDGE_WS_URL=f'ws://127.0.0.1:{bridge.bound_port}/ws/godot',LIVE_BRIDGE_PRODUCER_TOKEN=token,LIVE_BRIDGE_LOCAL_TOKEN='',LIVE_BRIDGE_ENGINE_TOKEN='',LIVE_AVATARS_ENABLED='0',JOGI_END_AT='2099-01-01T00:00:00Z')
  (runtime/'appdata').mkdir()
  with (runtime/'godot.log').open('wb') as log:
   game=subprocess.Popen([str(GODOT),'--headless','--path',str(ROOT/'game'),'--script','res://tests/admin_qa_runtime.gd','--','--asset-preview'],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
   await until(lambda:bool(bridge.godot_clients) and bool(bridge.latest_telemetry))
   adapter=TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='qa_cards_local'))
   results=[]
   async def deliver(event):
    results.append(bridge.enqueue_envelope(event))
   adapter.on_event(deliver)
   one=CommentEvent(content='13',common=CommonMessageData(msg_id=10001))
   two=CommentEvent(content='22',common=CommonMessageData(msg_id=10002))
   await adapter.handle_comment_event(one)
   await adapter.handle_comment_event(two)
   replay_result=await adapter.handle_comment_event(one)
   assert replay_result is None, "SDK replay must not emit another envelope"
   await until(lambda:vote_count(bridge,1)==1 and vote_count(bridge,2)==1 and bridge.latest_telemetry.get('interaction_cards',{}).get('visible')==2,10)
   first=json.loads(json.dumps(bridge.latest_telemetry))
   await asyncio.sleep(1.2)
   assert vote_count(bridge,1)==1 and vote_count(bridge,2)==1,'SDK duplicate changed vote ledger'
   assert bridge.latest_telemetry['interaction_cards']['visible']==2,'cards did not stay visible'
   assert results==['accepted','accepted'],results
   report.update(result='PASS',backend_receipts=results,sdk_input_events=3,sdk_duplicates_dropped=1,godot_votes={'13':vote_count(bridge,1),'22':vote_count(bridge,2)},interaction_cards=first['interaction_cards'],authenticated_godot_connected=True,real_sdk_event_class=type(one).__name__,limits='Headless HUD scene telemetry, no raster capture; no real platform spectator. No per-vote ACK exists; Godot audience ledger is observed.')
 finally:
  if game and game.poll() is None:
   game.terminate()
   try:await asyncio.to_thread(game.wait,timeout=10)
   except subprocess.TimeoutExpired:game.kill();await asyncio.to_thread(game.wait)
  await bridge.stop()
 output=ROOT/'docs/evidencias/producao/tiktok-cards-sdk-e2e.json';output.write_text(json.dumps(report,indent=2),encoding='utf-8')
 print(json.dumps(report))

if __name__=='__main__':asyncio.run(main())
