"""Aggregate ingestion diagnostics: SDK objects and local fixtures only, no network."""
import json
import unittest
from unittest.mock import patch
import httpx
from adapters import tiktok_adapter as module
from adapters.tiktok_adapter import TikTokAdapterConfig, TikTokLiveAdapter


class IngestionTests(unittest.IsolatedAsyncioTestCase):
    def adapter(self):
        return TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='qa_local'))

    async def test_comments_distinguish_nonvote_vote_duplicate_without_retaining_text(self):
        adapter = self.adapter()
        emitted = []
        adapter.on_event(emitted.append)
        await adapter.handle_comment_event({'comment': 'JOGI-PRIVATE-MARKER', 'msg_id': 'normal'})
        await adapter.handle_comment_event({'content': '13', 'msg_id': 'vote'})
        await adapter.handle_comment_event({'content': '13', 'msg_id': 'vote'})
        await adapter.handle_comment_event({'comment': '22', 'msg_id': 'other_vote'})
        stats = adapter.get_stats()['metadata']['ingestion']
        self.assertEqual(stats['comments_observed'], 4)
        self.assertEqual(stats['ignored_non_vote_comments'], 1)
        self.assertEqual(stats['valid_votes'], 2)  # unique valid votes after replay filtering
        self.assertEqual(stats['duplicates_dropped'], 1)
        self.assertEqual(stats['envelopes_emitted'], 2)
        self.assertEqual([e['payload']['candidate_slot'] for e in emitted], [1, 2])
        self.assertNotIn('JOGI-PRIVATE-MARKER', json.dumps(adapter.get_stats()))
        self.assertNotIn('comment', emitted[0]['payload'])

    async def test_installed_sdk_comment_content_is_recognized(self):
        if not module.TIKTOK_AVAILABLE:
            self.skipTest('SDK not installed')
        adapter = self.adapter()
        result = await adapter.handle_comment_event(module.CommentEvent(content='22'))
        self.assertEqual(result['payload']['candidate_slot'], 2)
        self.assertEqual(adapter.get_stats()['metadata']['ingestion']['comments_observed'], 1)

    async def test_raw_types_are_counted_before_normalization(self):
        adapter = self.adapter()
        for kind in ['like', 'follow', 'share']:
            await getattr(adapter, 'handle_' + kind + '_event')({'msg_id': kind, 'count': 3})
        stats = adapter.get_stats()['metadata']['ingestion']
        self.assertEqual(stats['observed_by_type'], {'like': 1, 'follow': 1, 'share': 1})
        self.assertIsNotNone(stats['last_raw_event_at'])
        self.assertEqual(stats['delivery_confirmation'], 'see_backend_and_godot_metrics')

    async def test_http_categories_never_store_query_or_full_url(self):
        adapter = self.adapter()
        response = httpx.Response(429, request=httpx.Request('GET', 'https://www.tiktok.com/api-live/user/room/?private=do-not-record'))
        with self.assertRaises(ConnectionError):
            await adapter._response_guard(response)
        stats = adapter.get_stats()['metadata']
        self.assertEqual(stats['last_http_endpoint'], 'room_discovery')
        self.assertNotIn('do-not-record', json.dumps(stats))

    async def test_connected_room_is_known_and_error_messages_redacted(self):
        adapter = self.adapter()
        adapter._handler_error('comment', ValueError('private user content'))
        self.assertEqual(adapter.get_stats()['metadata']['ingestion']['parser_errors'], 1)
        self.assertNotIn('private user content', json.dumps(adapter.get_stats()))
        adapter._status = 'waiting_room'
        self.assertEqual(adapter.get_stats()['metadata']['ingestion']['room_detected'], 'no')
        adapter._status = 'rate_limited'
        self.assertEqual(adapter.get_stats()['metadata']['ingestion']['room_detected'], 'unknown')


if __name__ == '__main__':
    unittest.main()
