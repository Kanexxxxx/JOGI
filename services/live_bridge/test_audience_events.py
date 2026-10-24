"""Interaction contract: teams, neutral events and real gift delta accounting."""

from __future__ import annotations

import asyncio
import json
from types import SimpleNamespace
import unittest

import websockets

from adapters.kwai_adapter import KwaiLiveAdapter
from adapters.normalization import ViewerContext
from adapters.tiktok_adapter import TikTokLiveAdapter
from protocol import GiftStreakTracker, build_gift_envelope, parse_vote_slot_from_comment
from server import LiveBridgeServer


class AudienceContractTests(unittest.TestCase):
    def test_team_aliases_and_non_vote_numbers(self) -> None:
        for comment in ("13", "#13!!!", "Bora 13", "13 13 13", "Lula", "#1"):
            with self.subTest(comment=comment):
                self.assertEqual(parse_vote_slot_from_comment(comment), 1)
        for comment in ("22", "#22", "Vai 22", "Flávio", "flavio", "verde-amarelo", "verde amarelo", "verdeamarelo", "#2"):
            with self.subTest(comment=comment):
                self.assertEqual(parse_vote_slot_from_comment(comment), 2)
        for comment in ("tenho 22 anos", "comprei 13 rosas", "13:22", "#123", "123", "legal", "Lula ou Flávio?", "#13 #22", "cpt123"):
            with self.subTest(comment=comment):
                self.assertIsNone(parse_vote_slot_from_comment(comment))

    def test_gift_total_is_unit_times_bounded_delta_once(self) -> None:
        env = build_gift_envelope(user_id="u", display_name="João", candidate_slot=None,
                                  repeat_count=3, gift_tier="T3", unit_coin_value=150,
                                  gift_name="[b]Rosa real[/b]")
        self.assertEqual(env["payload"]["coin_value"], 450)
        self.assertEqual(env["payload"]["repeat_count"], 3)
        self.assertEqual(env["payload"]["gift_name"], "Rosa real")
        self.assertNotIn("candidate_slot", env["payload"])
        unknown = build_gift_envelope(user_id="u", display_name="u", candidate_slot=None,
                                      unit_coin_value=0, gift_tier="T4")
        self.assertEqual(unknown["payload"]["coin_value"], 0)
        maximum = build_gift_envelope(user_id="u", display_name="u", candidate_slot=1,
                                      unit_coin_value=100_000, repeat_count=1000, gift_tier="T4")
        self.assertEqual(maximum["payload"]["coin_value"], 100_000_000)

    def test_team_memory_is_bounded_and_neutral_by_default(self) -> None:
        context = ViewerContext(max_users=2)
        self.assertIsNone(context.team("visitor"))
        context.choose("a", 1)
        context.choose("b", 2)
        context.choose("c", 2)
        self.assertIsNone(context.team("a"))
        self.assertEqual(context.team("b"), 2)

    def test_streak_restarts_after_close_and_explicit_ids_stay_deduplicated(self) -> None:
        tracker = GiftStreakTracker()
        values = []
        for count, active in ((1, True), (3, True), (3, False), (3, False), (1, True), (2, False)):
            values.append(tracker.register_gift_packet(user_id="u", gift_id="r", streak_id=None,
                                                       repeat_count=count, streaking=active))
        self.assertEqual(values, [1, 2, 0, 0, 1, 1])
        self.assertEqual(tracker.register_gift_packet(user_id="u", gift_id="r", streak_id="one",
                                                       repeat_count=5, streaking=False), 5)
        self.assertEqual(tracker.register_gift_packet(user_id="u", gift_id="r", streak_id="one",
                                                       repeat_count=5, streaking=False), 0)
        self.assertEqual(tracker.register_gift_packet(user_id="u", gift_id="r", streak_id="two",
                                                       repeat_count=5, streaking=False), 5)


class ConnectorAudienceTests(unittest.IsolatedAsyncioTestCase):
    async def test_tiktok_current_sdk_cumulative_fields_and_real_price(self) -> None:
        adapter = TikTokLiveAdapter()
        user = SimpleNamespace(id=1234, unique_id="same_fan", nickname="[wave]Maria\u202e[/wave]")
        await adapter.handle_comment_event(SimpleNamespace(user=user, comment="22"))
        gift = SimpleNamespace(id=99, name="Rosa", type=1, diamond_count=15)
        emitted = []
        for index, (count, active) in enumerate(((1, True), (3, True), (5, True), (5, False), (5, False))):
            event = SimpleNamespace(user=user, gift=gift, repeat_count=count, streaking=active,
                                    group_id="combo-A", common=SimpleNamespace(msg_id=100 + index))
            envelope = await adapter.handle_gift_event(event)
            if envelope:
                emitted.append(envelope)
        self.assertEqual([e["payload"]["repeat_count"] for e in emitted], [1, 2, 2])
        self.assertEqual(sum(e["payload"]["coin_value"] for e in emitted), 75)
        self.assertTrue(all(e["payload"]["candidate_slot"] == 2 for e in emitted))
        self.assertTrue(all(e["user"] == {"user_id": "1234", "display_name": "Maria"} for e in emitted))

    async def test_neutral_tiktok_is_visible_without_giving_lula_an_effect(self) -> None:
        adapter = TikTokLiveAdapter()
        user = {"unique_id": "visitor", "nickname": "Visitante"}
        events = [await adapter.handle_like_event({"user": user, "count": 30}),
                  await adapter.handle_share_event({"user": user}),
                  await adapter.handle_gift_event({"user": user, "gift": {"id": 8, "name": "Objeto"}})]
        self.assertEqual(events[0]["payload"]["like_count"], 30)
        self.assertEqual(events[2]["payload"]["coin_value"], 0)
        for event in events:
            self.assertNotIn("candidate_slot", event["payload"])
            self.assertNotIn("target", event["payload"])
        self.assertIsNone(await adapter.handle_comment_event({"user": user, "comment": "eu tenho 22 anos"}))

    async def test_independent_non_streak_gifts_and_packet_replays(self) -> None:
        adapter = TikTokLiveAdapter()
        event = {"event_id": "raw-one", "user": {"unique_id": "u"},
                 "gift": {"id": 9, "type": 2, "diamond_count": 100}}
        first = await adapter.handle_gift_event(event)
        self.assertIsNone(await adapter.handle_gift_event(event))
        second = await adapter.handle_gift_event(dict(event, event_id="raw-two"))
        self.assertEqual(first["payload"]["coin_value"] + second["payload"]["coin_value"], 200)
        self.assertNotEqual(first["event_id"], second["event_id"])

    async def test_large_combo_deltas_are_split_without_losing_gifts(self) -> None:
        adapter = TikTokLiveAdapter()
        emitted = []
        adapter.on_event(lambda env: emitted.append(env))
        for count, active in ((500, True), (3000, True), (3000, False)):
            await adapter.handle_gift_event({"user": {"unique_id": "large"}, "streak_id": "large-combo",
                "repeat_count": count, "streaking": active,
                "gift": {"id": "rose", "diamond_count": 2}})
        self.assertEqual([e["payload"]["repeat_count"] for e in emitted], [500, 1000, 1000, 500])
        self.assertEqual(sum(e["payload"]["coin_value"] for e in emitted), 6000)
        self.assertEqual(len({e["event_id"] for e in emitted}), 4)

    async def test_kwai_neutral_then_team_and_replayed_gift(self) -> None:
        adapter = KwaiLiveAdapter()
        neutral = await adapter.ingest_raw_event({"type": "like", "user_id": "k1", "count": 8})
        self.assertNotIn("candidate_slot", neutral["payload"])
        self.assertIsNone(await adapter.ingest_raw_event({"type": "chat", "content": "boa live", "user_id": "k1"}))
        await adapter.ingest_raw_event({"type": "chat", "content": "13", "user_id": "k1"})
        raw = {"type": "gift", "user_id": "k1", "gift_name": "Diamante", "coins": 150,
               "count": 3, "event_id": "kwai-one"}
        gift = await adapter.ingest_raw_event(raw)
        self.assertEqual(gift["payload"]["candidate_slot"], 1)
        self.assertEqual(gift["payload"]["coin_value"], 450)
        self.assertIsNone(await adapter.ingest_raw_event(raw))

    async def test_real_loopback_adapter_gifts_keep_delta_and_sanitized_names(self) -> None:
        server = LiveBridgeServer(port=0, rate_limit_per_sec=200)
        adapter = TikTokLiveAdapter()
        adapter.on_event(lambda env: server.enqueue_envelope(env))
        await server.start()
        try:
            async with websockets.connect(f"ws://127.0.0.1:{server.bound_port}/ws/godot") as ws:
                await asyncio.wait_for(ws.recv(), 3)
                user = {"unique_id": "u", "nickname": "[b]Fã\u202e[/b]"}
                await adapter.handle_comment_event({"comment": "22", "user": user})
                await asyncio.wait_for(ws.recv(), 3)
                for count, active in ((1, True), (3, True), (3, False)):
                    await adapter.handle_gift_event({"user": user, "streak_id": "real-combo",
                        "gift": {"id": 1, "name": "Rosa", "repeat_count": count,
                                 "streaking": active, "diamond_count": 15}})
                forwarded = [json.loads(await asyncio.wait_for(ws.recv(), 3)) for _ in range(2)]
                self.assertEqual(sum(e["payload"]["coin_value"] for e in forwarded), 45)
                self.assertEqual([e["payload"]["repeat_count"] for e in forwarded], [1, 2])
                self.assertTrue(all(e["user"]["display_name"] == "Fã" for e in forwarded))
                self.assertEqual(server.metrics["accepted_total"], 3)
        finally:
            await server.stop()

    async def test_ingest_shorthands_remember_choice_and_real_coin_price(self) -> None:
        server = LiveBridgeServer(port=0)
        neutral = server.normalize_incoming_payload({"type": "gift", "source": "tiktok", "user_id": "a"})
        self.assertNotIn("candidate_slot", neutral["payload"])
        self.assertEqual(neutral["payload"]["coin_value"], 0)
        server.normalize_incoming_payload({"type": "comment", "source": "tiktok", "user_id": "a", "comment": "#22"})
        chosen = server.normalize_incoming_payload({"type": "gift", "source": "tiktok", "user_id": "a",
                                                    "coin_value": 42, "repeat_count": 3, "gift_name": "Objeto real"})
        self.assertEqual(chosen["payload"]["candidate_slot"], 2)
        self.assertEqual(chosen["payload"]["coin_value"], 126)


if __name__ == "__main__":
    unittest.main()
