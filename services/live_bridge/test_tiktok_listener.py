"""SDK lifecycle tests use a fake client only; no real TikTok room is queried."""
import asyncio
import unittest
from unittest.mock import patch

from adapters import tiktok_adapter as module
from adapters.tiktok_adapter import TikTokAdapterConfig, TikTokLiveAdapter
from server import LiveBridgeServer


class FakeClient:
    created = []

    def __init__(self, unique_id):
        self.unique_id = unique_id
        self.handlers = {}
        self.is_connected = False
        self.done = asyncio.Event()
        self.start_options = None
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

    async def disconnect(self):
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
            self.assertEqual(FakeClient.created[0].unique_id, '@nostalgiia.br')
            self.assertEqual(FakeClient.created[0].start_options, {'fetch_room_info': True, 'fetch_gift_info': True})
            await adapter.stop()
            self.assertFalse(adapter.is_connected())

    async def test_offline_room_is_waiting_room_and_retries_with_backoff(self):
        class UserOfflineError(Exception):
            pass
        class OfflineClient(FakeClient):
            async def start(self, **kwargs):
                raise UserOfflineError('test offline room')
        FakeClient.created = []
        with patch.object(module, 'TikTokLiveClient', OfflineClient), patch.object(module, 'TIKTOK_AVAILABLE', True), patch.object(module.random, 'uniform', return_value=0):
            adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id='nostalgiia.br', base_backoff_sec=0.01, max_backoff_sec=0.02))
            await adapter.start()
            await until(lambda: len(FakeClient.created) >= 2)
            self.assertEqual(adapter.get_stats()['status'], 'waiting_room')
            self.assertFalse(adapter.is_connected())
            await adapter.stop()

    async def test_bridge_instantiates_configured_listener_and_receives_fake_event(self):
        with patch.object(module, 'TikTokLiveClient', FakeClient), patch.object(module, 'TIKTOK_AVAILABLE', True):
            server = LiveBridgeServer(port=0, platform='tiktok', account='nostalgiia.br')
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


if __name__ == '__main__':
    unittest.main()
