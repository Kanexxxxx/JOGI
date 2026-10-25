import unittest
from adapters.kwai_adapter import KwaiLiveAdapter,KwaiAdapterConfig
class DiagnosticsTests(unittest.IsolatedAsyncioTestCase):
 async def test_observed_filtered_duplicate_and_vote(self):
  a=KwaiLiveAdapter(config=KwaiAdapterConfig(enabled=True))
  await a.ingest_raw_event({'type':'comment','event_id':'a','user_id':'fixture','comment':'hello'})
  await a.ingest_raw_event({'type':'comment','event_id':'b','user_id':'fixture','comment':'13'})
  await a.ingest_raw_event({'type':'comment','event_id':'b','user_id':'fixture','comment':'13'})
  m=a.get_stats()['metadata']['ingestion']
  self.assertEqual(m['observed_by_type']['comment'],3)
  self.assertEqual(m['valid_votes'],1)
  self.assertEqual(m['ignored_non_vote_comments'],1)
  self.assertEqual(m['duplicates_dropped'],1)
 async def test_heartbeat_restricts_untrusted_diagnostics(self):
  a=KwaiLiveAdapter(config=KwaiAdapterConfig(enabled=True))
  await a.ingest_raw_event({'type':'collector_status','status':'waiting_room','diagnostics':{'cookies':'secret','comments_observed':5,'room_detected':'fake','final_path':'/live/share?token=secret'}})
  d=a.get_stats()['metadata']['diagnostics']
  self.assertNotIn('cookies',d)
  self.assertEqual(d['room_detected'],'unknown')
  self.assertEqual(d['comments_observed'],5)
  self.assertEqual(d['final_path'],'/live/share')
