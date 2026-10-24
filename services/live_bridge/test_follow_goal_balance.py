"""Followers, vote cooldown, price brackets and per-platform live goal controls."""
from __future__ import annotations

import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import urlopen

import websockets

from adapters.kwai_adapter import KwaiLiveAdapter
from adapters.normalization import ViewerContext
from adapters.tiktok_adapter import TikTokLiveAdapter
from protocol import (ProtocolValidationError, build_admin_command_envelope, build_follow_envelope,
                      build_gift_envelope, gift_tier_for_unit_coins, validate_envelope)
from server import LiveBridgeServer


class BalanceContractTests(unittest.TestCase):
    def test_brackets_and_big_gift_value_not_capped_with_effect(self) -> None:
        for coins, tier in ((1, 'T1'), (9, 'T1'), (10, 'T2'), (99, 'T2'), (100, 'T3'), (999, 'T3'), (1000, 'T4')):
            self.assertEqual(gift_tier_for_unit_coins(coins), tier)
        big = build_gift_envelope(user_id='u', display_name='u', candidate_slot=1,
                                  unit_coin_value=100000, repeat_count=1000, gift_tier='T4')
        self.assertEqual(big['payload']['coin_value'], 100000000)
        self.assertEqual(big['payload']['boost_amount'], 24)
        self.assertGreater(big['payload']['boost_amount'], 1.5)
        small = build_gift_envelope(user_id='u', display_name='u', candidate_slot=1, unit_coin_value=1)
        self.assertEqual(small['payload']['boost_amount'], .6)
        self.assertLess(small['payload']['boost_amount'], big['payload']['boost_amount'])

    def test_cooldown_is_per_user_with_two_second_boundary(self) -> None:
        context = ViewerContext()
        self.assertTrue(context.allow_vote_boost('a', 10))
        self.assertFalse(context.allow_vote_boost('a', 11.999))
        self.assertTrue(context.allow_vote_boost('b', 11))
        self.assertTrue(context.allow_vote_boost('a', 12))

    def test_follow_uses_existing_fields_without_team_bias(self) -> None:
        follow = build_follow_envelope(user_id='new', display_name='[b]Maria[/b]')
        self.assertEqual(follow['event_type'], 'follow')
        self.assertEqual(follow['payload'], {'action_id': 'audience_follow', 'repeat_count': 1})
        self.assertEqual(follow['user']['display_name'], 'Maria')
        validate_envelope(follow)

    def test_goal_validation_and_sanitization(self) -> None:
        good = build_admin_command_envelope(command='set_live_goal', goal_kind='follows', goal_target=250,
                                            goal_label='[b]Torcida\u202e[/b]')
        self.assertEqual(good['payload']['goal_label'], 'Torcida')
        for kind, target in (('money', 5), ('likes', 0), ('likes', True), ('coins', 1000000001)):
            with self.assertRaises(ProtocolValidationError):
                build_admin_command_envelope(command='set_live_goal', goal_kind=kind, goal_target=target)


class FollowAndGoalTests(unittest.IsolatedAsyncioTestCase):
    async def test_tiktok_follow_dedup_and_comments_count_without_repeat_boost(self) -> None:
        adapter = TikTokLiveAdapter()
        user = {'unique_id': 'f1', 'nickname': 'Visitante'}
        first = await adapter.handle_comment_event({'user': user, 'comment': '13'})
        second = await adapter.handle_comment_event({'user': user, 'comment': '22'})
        self.assertEqual(first['payload']['boost_amount'], 1.1)
        self.assertEqual(second['payload']['boost_amount'], 0)
        self.assertEqual(second['payload']['candidate_slot'], 2)
        self.assertEqual(second['payload']['repeat_count'], 1)
        follow = await adapter.handle_follow_event({'user': user, 'event_id': 'raw-follow'})
        self.assertEqual(follow['payload']['candidate_slot'], 2)
        self.assertIsNone(await adapter.handle_follow_event({'user': user, 'event_id': 'raw-follow'}))

    async def test_kwai_follow_and_unit_price_1000_has_t4(self) -> None:
        adapter = KwaiLiveAdapter()
        follow = await adapter.ingest_raw_event({'type': 'follow', 'user_id': 'k'})
        self.assertEqual(follow['event_type'], 'follow')
        self.assertNotIn('candidate_slot', follow['payload'])
        gift = await adapter.ingest_raw_event({'type': 'gift', 'user_id': 'k', 'coins': 1000, 'count': 2})
        self.assertEqual(gift['payload']['gift_tier'], 'T4')
        self.assertEqual(gift['payload']['coin_value'], 2000)

    async def test_goal_persist_restart_and_send_only_latest_after_welcome(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'gifts.sqlite3'
            first = LiveBridgeServer(runtime_mode="development", port=0, platform='tiktok', outbox_path=path)
            for target in (25, 50):
                envelope = build_admin_command_envelope(command='set_live_goal', goal_kind='follows',
                    goal_target=target, goal_label='Seguidores', event_id=f'evt_goal_{target}')
                self.assertEqual(first.enqueue_envelope(envelope), 'accepted')
            await first.stop()
            second = LiveBridgeServer(runtime_mode="development", port=0, platform='tiktok', outbox_path=path)
            await second.start()
            try:
                self.assertEqual(second.live_goal.value['goal_target'], 50)
                async with websockets.connect(f'ws://127.0.0.1:{second.bound_port}/ws/godot') as ws:
                    self.assertEqual(json.loads(await ws.recv())['event_type'], 'system_status')
                    goal = json.loads(await ws.recv())
                    self.assertEqual(goal['payload']['command'], 'set_live_goal')
                    self.assertEqual(goal['payload']['goal_target'], 50)
            finally:
                await second.stop()

    async def test_http_fallback_goal_follow_and_price_gift(self) -> None:
        server = LiveBridgeServer(runtime_mode="development", port=0, platform='kwai')
        await server.start()
        base = f'http://127.0.0.1:{server.bound_port}'
        async def request(path):
            response = await asyncio.to_thread(urlopen, base + path)
            return json.loads(response.read())
        try:
            ack = await request('/api/admin/command?' + urlencode({'command': 'set_live_goal',
                'goal_kind': 'coins', 'goal_target': 1234, 'goal_label': 'Meta Brasil'}))
            self.assertEqual(ack['status'], 'queued')
            self.assertEqual(server.live_goal.value['goal_target'], 1234)
            with self.assertRaises(HTTPError):
                await request('/api/admin/command?command=set_live_goal&goal_kind=coins&goal_target=0')
            self.assertEqual((await request('/api/admin/simulate?event_type=follow&slot=2'))['status'], 'accepted')
            self.assertEqual((await request('/api/admin/simulate?event_type=gift&slot=2&unit_coin_value=42&count=3'))['status'], 'accepted')
            gift = server.outbox.next_due()
            self.assertEqual(gift['payload']['coin_value'], 126)
        finally:
            await server.stop()


if __name__ == '__main__':
    unittest.main()
