"""SDK lifecycle tests use a fake client only; no real TikTok room is queried."""
import asyncio
import unittest
from unittest.mock import patch

from adapters import tiktok_adapter as module
from adapters.tiktok_adapter import TikTokAdapterConfig, TikTokLiveAdapter
from server import LiveBridgeServer


class FakeClient:
    created = []

    def __init__(self, unique_id, **kwargs):
        self.unique_id = unique_id
        self.handlers = {}
        self.is_connected = False
        self.done = asyncio.Event()
        self.start_options = None
        self.closed_http = False
        self.room_id = 7700000000000000001
        client = self

        class _Web:
            async def close(self):
                client.closed_http = True

        self.web = _Web()
        FakeClient.created.append(self)

    def on(self, kind):
        def register(function):
            self.handlers[kind] = function
            return function
        return register

    async def start(self, **kwargs):
        self.start_options = kwargs
        self.is_connected = True
        await self.handlers[module.ConnectEvent if module.ConnectEvent is not None else 'connect'](None)
        return asyncio.create_task(self.done.wait())

    async def disconnect(self, close_client=False):
        # TikTokLive 7.x close_client=True leaks a never-awaited coroutine.
        assert close_client is False, "adapter must close the HTTP session explicitly"
        self.is_connected = False
        self.done.set()


async def until(predicate):
    for _ in range(100):
        if predicate():
            return
        await asyncio.sleep(0.01)
    raise AssertionError("fake SDK condition did not become true")


class TikTokListenerTests(unittest.IsolatedAsyncioTestCase):
    async def test_sdk_lifetime_is_awaited_and_only_one_client_runs(self):
        FakeClient.created = []
        with patch.object(module, 'TikTokLiveClient', FakeClient), patch.object(module, 'TIKTOK_AVAILABLE', True):
            adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='nostalgiia.br'))
            await adapter.start()
            await until(adapter.is_connected)
            await asyncio.sleep(0.06)
            self.assertEqual(len(FakeClient.created), 1)
            self.assertEqual(FakeClient.created[0].unique_id, 'nostalgiia.br')
            self.assertEqual(FakeClient.created[0].start_options, {'fetch_room_info': True, 'fetch_gift_info': True})
            await adapter.stop()
            self.assertFalse(adapter.is_connected())
            self.assertTrue(FakeClient.created[0].closed_http)

    async def test_offline_room_is_waiting_room_and_retries_with_backoff(self):
        class UserOfflineError(Exception):
            pass
        class OfflineClient(FakeClient):
            async def start(self, **kwargs):
                raise UserOfflineError('test offline room')
        FakeClient.created = []
        with patch.object(module, 'TikTokLiveClient', OfflineClient), patch.object(module, 'TIKTOK_AVAILABLE', True), patch.object(module.random, 'uniform', return_value=0):
            adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='nostalgiia.br', base_backoff_sec=0.01, max_backoff_sec=0.02, offline_poll_sec=0.01))
            await adapter.start()
            await until(lambda: len(FakeClient.created) >= 2)
            self.assertTrue(FakeClient.created[0].closed_http)
            self.assertEqual(adapter.get_stats()['status'], 'waiting_room')
            self.assertFalse(adapter.is_connected())
            await adapter.stop()

    async def test_ambiguous_user_error_never_declares_profile_nonexistent(self):
        error_type = type('UserNotFoundError', (Exception,), {})
        adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='xinka_'))
        status, delay = adapter._classify_failure(error_type('ambiguous LIVE endpoint'))
        self.assertEqual(status, 'room_unavailable')
        self.assertGreaterEqual(delay, 300)
        self.assertEqual(adapter.get_stats()['metadata']['profile_existence'], 'not_determined_by_live_endpoint')

    async def test_rate_limit_blocks_sdk_fallback_and_honours_retry_after(self):
        import httpx
        adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='xinka_'))
        request = httpx.Request('GET', 'https://www.tiktok.com/api-live/user/room/')
        response = httpx.Response(429, headers={'Retry-After': '1800'}, request=request)
        with self.assertRaises(ConnectionError):
            await adapter._response_guard(response)
        # The SDK catches initial errors and tries API fallback: block BEFORE sending it.
        with self.assertRaises(ConnectionError):
            await adapter._request_guard(request)
        status, delay = adapter._classify_failure(ValueError('SDK might wrap HTTP as JSON error'))
        self.assertEqual((status, delay), ('rate_limited', 1800))

    async def test_sdk_signer_rate_limit_respects_its_cooldown(self):
        error_type = type('SignatureRateLimitError', (Exception,), {'retry_after': 3600})
        adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='xinka_'))
        self.assertEqual(adapter._classify_failure(error_type()), ('rate_limited', 3600))

    async def test_offline_block_and_network_errors_are_distinct(self):
        import httpx
        adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='xinka_'))
        offline_type = type('UserOfflineError', (Exception,), {})
        self.assertEqual(adapter._classify_failure(offline_type())[0], 'waiting_room')
        self.assertEqual(adapter._classify_failure(TimeoutError())[0], 'connection_error')
        response = httpx.Response(403, request=httpx.Request('GET','https://www.tiktok.com/'))
        with self.assertRaises(ConnectionError):
            await adapter._response_guard(response)
        self.assertEqual(adapter._classify_failure(ConnectionError())[0], 'access_blocked')

    async def test_sdk_http_hooks_are_configured_without_double_at_referer(self):
        from TikTokLive import TikTokLiveClient
        adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='@xinka_'))
        client = TikTokLiveClient(unique_id=adapter.config.unique_id, web_kwargs={
            'httpx_kwargs': {'event_hooks': {'request': [adapter._request_guard], 'response': [adapter._response_guard]}}})
        try:
            self.assertEqual(client.web.params['referer'], 'https://www.tiktok.com/@xinka_/live')
            self.assertIn(adapter._response_guard, client.web.httpx_client.event_hooks['response'])
        finally:
            await client.web.close()

    async def test_bridge_instantiates_configured_listener_and_receives_fake_event(self):
        with patch.object(module, 'TikTokLiveClient', FakeClient), patch.object(module, 'TIKTOK_AVAILABLE', True):
            server = LiveBridgeServer(runtime_mode="development", port=0, platform='tiktok', account='nostalgiia.br')
            await server.start()
            try:
                await server.start_live_listener()
                await until(lambda: server.platform_listener_state()['platform_events_connected'])
                event = {'user': {'unique_id': 'qa_fan', 'nickname': 'QA'}, 'comment': '22'}
                await server._live_adapter.handle_comment_event(event)
                self.assertEqual(server.p1_queue.get_nowait()['payload']['candidate_slot'], 2)
                self.assertEqual(server.platform_listener_state()['platform_events_status'], 'connected')
            finally:
                await server.stop()


    async def test_websocket_drop_reconnects_to_confirmed_room_without_rediscovery(self):
        FakeClient.created = []
        with patch.object(module, 'TikTokLiveClient', FakeClient), patch.object(module, 'TIKTOK_AVAILABLE', True), \
                patch.object(module.random, 'uniform', return_value=0):
            adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='xinka_', base_backoff_sec=0.01, max_backoff_sec=0.02))
            await adapter.start()
            await until(adapter.is_connected)
            FakeClient.created[0].done.set()  # server-side websocket close
            await until(lambda: len(FakeClient.created) >= 2 and FakeClient.created[1].start_options is not None)
            self.assertTrue(FakeClient.created[0].closed_http)
            self.assertEqual(FakeClient.created[1].start_options,
                             {'fetch_room_info': False, 'fetch_gift_info': True, 'room_id': 7700000000000000001})
            await until(adapter.is_connected)
            await adapter.stop()

    async def test_live_end_never_reuses_room_and_waits_offline_poll(self):
        FakeClient.created = []
        with patch.object(module, 'TikTokLiveClient', FakeClient), patch.object(module, 'TIKTOK_AVAILABLE', True), \
                patch.object(module.random, 'uniform', return_value=0):
            adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='xinka_', offline_poll_sec=0.05))
            await adapter.start()
            await until(adapter.is_connected)
            adapter._live_ended = True
            adapter._known_room_id = None
            FakeClient.created[0].done.set()
            await until(lambda: adapter.get_stats()['status'] == 'waiting_room')
            await until(lambda: len(FakeClient.created) >= 2 and FakeClient.created[1].start_options is not None)
            self.assertNotIn('room_id', FakeClient.created[1].start_options)
            await adapter.stop()

    async def test_rate_limited_cooldown_is_respected_before_any_client(self):
        import time as _time
        FakeClient.created = []
        with patch.object(module, 'TikTokLiveClient', FakeClient), patch.object(module, 'TIKTOK_AVAILABLE', True):
            adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='xinka_'))
            adapter._next_retry_at = _time.time() + 60
            adapter._known_room_id = 123
            await adapter.start()
            await asyncio.sleep(0.1)
            self.assertEqual(FakeClient.created, [])
            await adapter.stop()

    async def test_comment_votes_13_22_and_team_bound_gifts(self):
        import tempfile, os
        with tempfile.TemporaryDirectory() as tmp:
            adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='xinka_', team_store_path=os.path.join(tmp, 't.sqlite3')))
            sent = []
            adapter.on_event(lambda envelope: sent.append(envelope))
            def comment(uid, text, msg):
                return {'user': {'id': uid, 'nickname': 'F'+uid}, 'comment': text, 'msg_id': msg, 'timestamp_ms': 1_000 + msg}
            def gift(uid, msg, coins, repeat=1, streaking=False, group=None):
                return {'user': {'id': uid, 'nickname': 'F'+uid}, 'gift': {'id': 5655, 'name': 'Rosa', 'diamond_count': coins},
                        'repeat_count': repeat, 'streaking': streaking, 'group_id': group, 'msg_id': msg, 'timestamp_ms': 1_000 + msg}
            try:
                self.assertEqual((await adapter.handle_comment_event(comment('111', '13', 1)))['payload']['candidate_slot'], 1)
                self.assertEqual((await adapter.handle_comment_event(comment('222', '22', 2)))['payload']['candidate_slot'], 2)
                self.assertIsNone(await adapter.handle_comment_event(comment('222', '22', 2)))  # same packet replay
                await adapter.handle_gift_event(gift('111', 10, 1))
                await adapter.handle_gift_event(gift('222', 11, 10))
                await adapter.handle_gift_event(gift('333', 12, 149))  # no team chosen
                self.assertEqual((await adapter.handle_comment_event(comment('111', '22', 13)))['payload']['candidate_slot'], 2)
                await adapter.handle_gift_event(gift('111', 14, 1000))
                # combo 1 -> 3 -> 5 emits deltas only, final packet duplicate-safe
                await adapter.handle_gift_event(gift('222', 20, 1, repeat=1, streaking=True, group=77))
                await adapter.handle_gift_event(gift('222', 21, 1, repeat=3, streaking=True, group=77))
                await adapter.handle_gift_event(gift('222', 22, 1, repeat=5, streaking=False, group=77))
                await adapter.handle_gift_event(gift('222', 22, 1, repeat=5, streaking=False, group=77))
                gifts = [e for e in sent if e['event_type'] == 'gift']
                slots = [e['payload'].get('candidate_slot') for e in gifts]
                self.assertEqual(slots[:4], [1, 2, None, 2])
                self.assertEqual(sum(e['payload']['repeat_count'] for e in gifts[4:]), 5)
                self.assertEqual(adapter.get_stats()['metadata']['paid_pending'], 0)
            finally:
                await adapter.stop()

if __name__ == '__main__':
    unittest.main()
