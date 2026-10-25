import tempfile,time,unittest
from pathlib import Path
from adapters.tiktok_adapter import TikTokLiveAdapter,TikTokAdapterConfig

class TeamTests(unittest.IsolatedAsyncioTestCase):
 def adapter(self,path=None):
  return TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id="qa",team_store_path=str(path) if path else None))
 def comment(self,uid,slot,packet,at=None):
  return {"user":{"id":uid,"nickname":"Mesmo nome"},"msg_id":packet,"content":str(slot),"timestamp_ms":at or int(time.time()*1000)}
 def gift(self,uid,packet,at=None,coins=1):
  return {"user":{"id":uid,"nickname":"Mesmo nome"},"msg_id":packet,"timestamp_ms":at or int(time.time()*1000),"gift_id":"rose_fixture","gift":{"name":"Fixture","diamond_count":coins},"repeat_count":1}
 async def test_two_equal_names_separate_teams_switch_and_duplicate(self):
  a=self.adapter();await a.handle_comment_event(self.comment("uid1",13,"c1"));await a.handle_comment_event(self.comment("uid2",22,"c2"))
  self.assertEqual((await a.handle_gift_event(self.gift("uid1","g1")))["payload"]["candidate_slot"],1)
  self.assertEqual((await a.handle_gift_event(self.gift("uid2","g2")))["payload"]["candidate_slot"],2)
  self.assertIsNone(await a.handle_gift_event(self.gift("uid2","g2")))
  await a.handle_comment_event(self.comment("uid1",22,"c3"))
  self.assertEqual((await a.handle_gift_event(self.gift("uid1","g3")))["payload"]["candidate_slot"],2)
 async def test_neutral_and_missing_stable_id_never_inherit_handle(self):
  a=self.adapter();await a.handle_comment_event({"user":{"unique_id":"same","nickname":"Same"},"comment":"13","msg_id":"c1"})
  for uid in [None,"another"]:
   event=self.gift(uid,"g"+str(uid));event["user"]["unique_id"]="same"
   self.assertNotIn("candidate_slot",(await a.handle_gift_event(event))["payload"])
 async def test_restart_and_event_time_freezes_team(self):
  with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
   path=Path(tmp)/"teams.sqlite3";a=self.adapter(path);now=int(time.time()*1000)
   await a.handle_comment_event(self.comment("u",13,"c1",now-3000));await a.handle_comment_event(self.comment("u",22,"c2",now-1000))
   b=self.adapter(path)
   old=await b.handle_gift_event(self.gift("u","old",now-2000));future=await b.handle_gift_event(self.gift("u","new",now))
   self.assertEqual(old["payload"]["candidate_slot"],1);self.assertEqual(future["payload"]["candidate_slot"],2)
   self.assertEqual(old["payload"]["candidate_slot"],1)
   a._teams.db.close();b._teams.db.close()

 async def test_paid_callback_failure_is_retained_and_retry_is_exact(self):
  a=self.adapter();await a.handle_comment_event(self.comment("u",13,"c1"))
  async def fail(event):raise OSError("fixture unavailable")
  a.on_event(fail)
  with self.assertRaises(OSError):await a.handle_gift_event(self.gift("u","g1"))
  pending=a._teams.pending_gifts();self.assertEqual(len(pending),1)
  a.remove_event_listener(fail);seen=[];a.on_event(seen.append)
  await a._drain_paid_pending();self.assertEqual(seen,pending);self.assertEqual(a._teams.pending_gifts(),[])
  await a.handle_gift_event(self.gift("u","g1"));self.assertEqual(len(seen),1)
 async def test_combo_delta_survives_reconnection(self):
  with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
   path=Path(tmp)/"teams.sqlite3";a=self.adapter(path);a.on_event(lambda event:None)
   event=self.gift("u","combo1");event.update(repeat_count=3,streaking=True,group_id="group1");event['gift']['type']=1
   first=await a.handle_gift_event(event);a._teams.db.close()
   b=self.adapter(path);b.on_event(lambda event:None)
   event.update(msg_id="combo2",repeat_count=5)
   second=await b.handle_gift_event(event)
   self.assertEqual(first['payload']['repeat_count'],3);self.assertEqual(second['payload']['repeat_count'],2)
   b._teams.db.close()

 async def test_coarse_timestamp_switch_is_neutral_when_order_is_ambiguous(self):
  a=self.adapter();now=int(time.time())*1000
  a._teams.choose("u",1,now,"choice-a");a._teams.choose("u",2,now,"choice-b")
  self.assertIsNone(a._teams.team("u",now,coarse=True))
  self.assertEqual(a._teams.team("u",now+1000,coarse=True),2)
