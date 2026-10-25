"""Authenticated loopback webhook -> durable bridge -> real Godot, isolated data only."""
import asyncio,json,os,secrets,subprocess,sys,tempfile,time
from pathlib import Path
from urllib.request import Request,urlopen
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'services/live_bridge'))
from server import LiveBridgeServer
from adapters.kwai_adapter import KwaiLiveAdapter,KwaiAdapterConfig

async def until(fn,seconds=40):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        if fn():return
        await asyncio.sleep(.05)
    raise AssertionError('isolated Kwai condition timed out')

async def main():
    root=Path(tempfile.mkdtemp(prefix='jogi-kwai-events-'));token=secrets.token_urlsafe(32)
    bridge=LiveBridgeServer(port=0,platform='kwai',account='qa_kwai',runtime_mode='development',outbox_path=root/'gifts.sqlite3',producer_token=token)
    adapter=KwaiLiveAdapter(config=KwaiAdapterConfig(enabled=True,port=0,webhook_token=token,account='qa_kwai',team_store_path=str(root/'kwai_teams.sqlite3')))
    adapter.on_event(bridge._receive_adapter_event);adapter.set_durable_gift_sink(bridge._receive_adapter_event)
    await bridge.start();await adapter.start();game=None
    def send(packet):
        request=Request(f'http://127.0.0.1:{adapter.bound_port}/webhook/kwai',data=json.dumps(packet).encode(),headers={'Content-Type':'application/json','X-JOGI-Token':token})
        with urlopen(request,timeout=6) as response:return json.load(response)
    try:
        data=root/'appdata';data.mkdir()
        env={**os.environ,'APPDATA':str(data),'GDA_USER_DATA_ROOT':str(data),'LIVE_PLATFORM':'kwai','JOGI_MODE':'development','LIVE_BRIDGE_WS_URL':f'ws://127.0.0.1:{bridge.bound_port}/ws/godot','LIVE_BRIDGE_PRODUCER_TOKEN':token,'LIVE_BRIDGE_LOCAL_TOKEN':'','LIVE_BRIDGE_ENGINE_TOKEN':'','LIVE_AVATARS_ENABLED':'0','JOGI_END_AT':'2099-01-01T00:00:00Z'}
        exe=Path.home()/'Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe'
        with (root/'godot.log').open('wb') as log:
            game=subprocess.Popen([str(exe),'--headless','--path',str(ROOT/'game'),'--script','res://tests/admin_qa_runtime.gd','--','--asset-preview'],env=env,stdout=log,stderr=log,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            await until(lambda:bridge.godot_clients and bridge.latest_telemetry)
            for uid,choice in [('a','13'),('b','22')]:await asyncio.to_thread(send,dict(type='comment',event_id='choice'+uid,user_id=uid,display_name='Mesmo nome',comment=choice))
            packets=[]
            for uid in ['a','b','neutral']:
                for unit in ([1,10,100,1000] if uid!='neutral' else [1]):
                    packet=dict(type='gift',event_id=f'paid{uid}{unit}',user_id=uid,display_name='Mesmo nome',gift_id=f'fixture{unit}',gift_name='Presente de teste',unit_coin_value=unit)
                    result=await asyncio.to_thread(send,packet);assert result.get('ingested') is True
                    packets.append(packet)
            await until(lambda:bridge.metrics['gift_acks_total']==9 and bridge.outbox.pending_count()==0)
            await asyncio.to_thread(send,packets[0]);await asyncio.sleep(.4)
            assert bridge.metrics['gift_acks_total']==9
            rows=[json.loads(r[0]) for r in bridge.outbox.db.execute('SELECT envelope FROM gifts ORDER BY rowid')]
            assert [r['payload'].get('candidate_slot',0) for r in rows]==[1]*4+[2]*4+[0]
            await until(lambda:bridge.latest_telemetry.get('interaction_cards',{}).get('visible',0)>0)
            report=dict(result='PASS',scope='isolated webhook/backend/real headless Godot; no Kwai network',gifts=9,acks=9,duplicate_reapplied=False,frozen_slots=[r['payload'].get('candidate_slot',0) for r in rows],cards=bridge.latest_telemetry['interaction_cards'],external_events_verified=False)
    finally:
        if game and game.poll() is None:game.terminate();await asyncio.to_thread(game.wait,timeout=10)
        await adapter.stop();await bridge.stop();adapter._teams.db.close()
    output=ROOT/'docs/evidencias/producao/kwai-events-recovery-e2e.json';output.write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))

if __name__=='__main__':asyncio.run(main())
