"""Isolated fixtures, no platform requests or production events."""
import time
import pytest
from adapters.kwai_adapter import KwaiLiveAdapter, KwaiAdapterConfig, KwaiDeliveryUnavailable

def adapter(path):
    return KwaiLiveAdapter(config=KwaiAdapterConfig(enabled=True, account='qa_kwai', team_store_path=str(path)))

def comment(uid, slot, eid, at):
    return dict(type='comment',user_id=uid,display_name='Nome igual',comment=str(slot),event_id=eid,timestamp_ms=at)

def gift(uid,eid,at):
    return dict(type='gift',user_id=uid,display_name='Nome igual',gift_id='fixture',gift_name='Teste isolado',unit_coin_value=1,event_id=eid,timestamp_ms=at)

@pytest.mark.asyncio
async def test_persistent_teams_late_gift_anonymous_and_homonyms(tmp_path):
    path=tmp_path/'kwai_teams.sqlite3';now=int(time.time()*1000);first=adapter(path)
    await first.ingest_raw_event(comment('a',13,'c1',now-3000))
    await first.ingest_raw_event(comment('b',22,'c2',now-2500))
    await first.ingest_raw_event(comment('a',22,'c3',now-1000))
    first._teams.db.close();second=adapter(path)
    try:
        for uid,at,expected in [('a',now-2000,1),('a',now,2),('b',now,2),('anon_kwai',now,0),('unknown',now,0)]:
            event=await second.ingest_raw_event(gift(uid,f'g{uid}{at}',at))
            assert event['payload'].get('candidate_slot',0)==expected
    finally: second._teams.db.close()

@pytest.mark.asyncio
async def test_paid_retry_freezes_team_across_switch_and_restart(tmp_path):
    path=tmp_path/'kwai_teams.sqlite3';now=int(time.time()*1000);first=adapter(path)
    await first.ingest_raw_event(comment('a',13,'c1',now-100))
    async def busy(event):return 'busy'
    first.set_durable_gift_sink(busy);packet=gift('a','paid-event',now)
    with pytest.raises(KwaiDeliveryUnavailable):await first.ingest_raw_event(packet)
    assert len(first._teams.pending_gifts())==1
    await first.ingest_raw_event(comment('a',22,'c2',now+100));first._teams.db.close()
    second=adapter(path);accepted=[]
    async def sink(event):accepted.append(event);return 'accepted'
    second.set_durable_gift_sink(sink)
    try:
        packet.pop('timestamp_ms');event=await second.ingest_raw_event(packet)
        assert event['payload']['candidate_slot']==1
        assert len(accepted)==1 and second._teams.pending_gifts()==[]
    finally:second._teams.db.close()
