"""Local isolation, durable gift delivery and browser-origin security checks."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import websockets
from websockets.exceptions import ConnectionClosed, InvalidStatus

from outbox import GiftOutbox
from protocol import build_gift_envelope, build_vote_envelope
from server import LiveBridgeServer, is_allowed_origin


def gift(event_id: str, source: str = "tiktok") -> dict:
    return build_gift_envelope(user_id="donor", display_name="[b]Maria[/b]", candidate_slot=2,
        event_id=event_id, unit_coin_value=15, repeat_count=3, gift_name="Rosa", source=source)


async def wait_until(predicate, timeout: float = 1.0) -> None:
    end = time.monotonic() + timeout
    while not predicate():
        if time.monotonic() > end:
            raise AssertionError("condition did not become true")
        await asyncio.sleep(0.01)


class OutboxTests(unittest.TestCase):
    def test_full_queue_never_drops_accepted_gift_and_restart_keeps_ids(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "gifts.sqlite3"
            store = GiftOutbox(path, platform="tiktok", capacity=1)
            one, two = gift("evt_gift_one"), gift("evt_gift_two")
            self.assertEqual(store.accept(one), "accepted")
            self.assertEqual(store.accept(two), "busy")
            self.assertEqual(store.next_due()["event_id"], "evt_gift_one")
            self.assertFalse(store.acknowledge("evt_gift_one"))  # not yet sent
            store.mark_attempt("evt_gift_one", 5)
            self.assertTrue(store.acknowledge("evt_gift_one"))
            self.assertEqual(store.accept(two), "accepted")
            store.close()
            reopened = GiftOutbox(path, platform="tiktok", capacity=1)
            self.assertEqual(reopened.accept(one), "duplicate")
            self.assertEqual(reopened.next_due()["event_id"], "evt_gift_two")
            self.assertEqual(reopened.db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
            reopened.close()

    def test_platform_mismatch_and_concurrent_file_use_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "gifts.sqlite3"
            store = GiftOutbox(path, platform="tiktok")
            with self.assertRaises((RuntimeError, OSError)):
                GiftOutbox(path, platform="tiktok")
            store.close()
            with self.assertRaises(ValueError):
                GiftOutbox(path, platform="kwai")

    def test_retained_completed_rows_bounded_but_pending_never_pruned(self) -> None:
        store = GiftOutbox(None, platform="local", retained_limit=2)
        for index in range(5):
            event_id = f"evt_complete_{index}"
            store.accept(gift(event_id))
            store.mark_attempt(event_id, 1)
            store.acknowledge(event_id)
        store.accept(gift("evt_still_pending"))
        store.prune()
        completed = store.db.execute("SELECT count(*) FROM gifts WHERE completed_ms IS NOT NULL").fetchone()[0]
        self.assertEqual(completed, 2)
        self.assertTrue(store.contains("evt_still_pending"))
        store.close()

    def test_origin_policy(self) -> None:
        for allowed in (None, "http://localhost:8765", "http://127.0.0.1:8765"):
            self.assertTrue(is_allowed_origin(allowed, 8765))
        for denied in ("null", "https://evil.example", "http://localhost.evil:8765", "http://localhost:8766",
                       "https://localhost:8765", "file://", "http://a@localhost:8765", "http://localhost:bad"):
            self.assertFalse(is_allowed_origin(denied, 8765))

    def test_committed_gift_survives_abrupt_process_exit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "crash.sqlite3"
            code = (
                "import os,sys; from pathlib import Path; from outbox import GiftOutbox; "
                "from protocol import build_gift_envelope; "
                "store=GiftOutbox(Path(sys.argv[1]),platform='tiktok'); "
                "event=build_gift_envelope(user_id='u',display_name='U',candidate_slot=1,event_id='evt_crash_safe'); "
                "assert store.accept(event)=='accepted'; os._exit(29)"
            )
            result = subprocess.run([sys.executable, "-c", code, str(path)],
                cwd=Path(__file__).resolve().parent, capture_output=True, text=True, timeout=10,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            self.assertEqual(result.returncode, 29, result.stderr)
            reopened = GiftOutbox(path, platform="tiktok")
            self.assertEqual(reopened.next_due()["event_id"], "evt_crash_safe")
            self.assertEqual(reopened.db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
            reopened.close()


class ReliableServerTests(unittest.IsolatedAsyncioTestCase):
    async def test_offline_retention_reconnect_and_ack(self) -> None:
        server = LiveBridgeServer(runtime_mode="development", port=0, platform="tiktok", ack_retry_seconds=0.2)
        await server.start()
        url = f"ws://127.0.0.1:{server.bound_port}/ws/godot"
        try:
            self.assertEqual(server.enqueue_envelope(gift("evt_offline_gift")), "accepted")
            server.enqueue_envelope(build_vote_envelope(user_id="v", display_name="v", candidate_slot=1))
            await asyncio.sleep(0.05)
            self.assertEqual(server.outbox.pending_count(), 1)
            self.assertEqual(server.p1_queue.qsize(), 1)
            self.assertEqual(server.metrics["dispatched_to_godot"], 0)
            async with websockets.connect(url) as ws:
                self.assertEqual(json.loads(await ws.recv())["event_type"], "system_status")
                delivered = json.loads(await ws.recv())
                self.assertEqual(delivered["event_id"], "evt_offline_gift")
                self.assertEqual(server.outbox.pending_count(), 1)  # sent != applied/ACK
            await wait_until(lambda: not server.godot_clients)
            async with websockets.connect(url) as ws:
                await ws.recv()
                replay = json.loads(await ws.recv())
                self.assertEqual(replay["event_id"], "evt_offline_gift")
                await ws.send(json.dumps({"type": "event_ack", "event_id": replay["event_id"]}))
                await wait_until(lambda: server.outbox.pending_count() == 0)
                self.assertEqual(server.metrics["gift_acks_total"], 1)
                self.assertEqual(server.enqueue_envelope(gift("evt_offline_gift")), "duplicate")
        finally:
            await server.stop()

    async def test_unacknowledged_gift_survives_server_restart(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "gifts.sqlite3"
            first = LiveBridgeServer(runtime_mode="development", port=0, platform="kwai", outbox_path=path)
            await first.start()
            first.enqueue_envelope(gift("evt_restart_gift", "kwai"))
            await first.stop()
            second = LiveBridgeServer(runtime_mode="development", port=0, platform="kwai", outbox_path=path)
            await second.start()
            try:
                async with websockets.connect(f"ws://127.0.0.1:{second.bound_port}/ws/godot") as ws:
                    await ws.recv()
                    replay = json.loads(await ws.recv())
                    self.assertEqual(replay["event_id"], "evt_restart_gift")
                    await ws.send(json.dumps({"type": "event_ack", "event_id": replay["event_id"]}))
                    await wait_until(lambda: second.outbox.pending_count() == 0)
            finally:
                await second.stop()

    async def test_busy_is_explicit_and_retry_after_ack_is_accepted(self) -> None:
        server = LiveBridgeServer(runtime_mode="development", port=0, platform="tiktok", gift_capacity=1)
        await server.start()
        try:
            self.assertEqual(server.ingest_raw_json(json.dumps(gift("evt_capacity_one")))["status"], "accepted")
            self.assertEqual(server.ingest_raw_json(json.dumps(gift("evt_capacity_two")))["status"], "busy")
            self.assertEqual(server.outbox.next_due()["event_id"], "evt_capacity_one")
            async with websockets.connect(f"ws://127.0.0.1:{server.bound_port}/ws/godot") as ws:
                await ws.recv()
                delivered = json.loads(await ws.recv())
                await ws.send(json.dumps({"type": "event_ack", "event_id": delivered["event_id"]}))
                await wait_until(lambda: server.outbox.pending_count() == 0)
                self.assertEqual(server.ingest_raw_json(json.dumps(gift("evt_capacity_two")))["status"], "accepted")
        finally:
            await server.stop()

    async def test_two_platforms_have_independent_delivery_and_reject_cross_source(self) -> None:
        tt, kw = LiveBridgeServer(runtime_mode="development", port=0, platform="tiktok"), LiveBridgeServer(runtime_mode="development", port=0, platform="kwai")
        await tt.start()
        await kw.start()
        try:
            async with websockets.connect(f"ws://127.0.0.1:{tt.bound_port}/ws/godot") as t_ws, \
                       websockets.connect(f"ws://127.0.0.1:{kw.bound_port}/ws/godot") as k_ws:
                await t_ws.recv()
                await k_ws.recv()
                self.assertEqual(tt.enqueue_envelope(gift("evt_wrong_channel", "kwai")), "rejected_platform")
                tt.enqueue_envelope(gift("evt_tiktok_only"))
                kw.enqueue_envelope(gift("evt_kwai_only", "kwai"))
                t_gift, k_gift = json.loads(await t_ws.recv()), json.loads(await k_ws.recv())
                self.assertEqual(t_gift["event_id"], "evt_tiktok_only")
                self.assertEqual(k_gift["event_id"], "evt_kwai_only")
                self.assertFalse(tt.outbox.contains("evt_kwai_only"))
                self.assertFalse(kw.outbox.contains("evt_tiktok_only"))
                self.assertEqual(tt._build_admin_state_payload()["platform"], "tiktok")
                self.assertEqual(kw._build_admin_state_payload()["platform"], "kwai")
        finally:
            await tt.stop()
            await kw.stop()

    async def test_only_one_game_consumer_and_stale_telemetry_not_current(self) -> None:
        server = LiveBridgeServer(runtime_mode="development", port=0)
        await server.start()
        url = f"ws://127.0.0.1:{server.bound_port}/ws/godot"
        try:
            async with websockets.connect(url) as first:
                await first.recv()
                async with websockets.connect(url) as second:
                    with self.assertRaises(ConnectionClosed):
                        await second.recv()
                self.assertEqual(len(server.godot_clients), 1)
                await first.send(json.dumps({"type": "telemetry", "state_name": "RACING", "runners": []}))
                await wait_until(lambda: server._telemetry_received_at is not None)
                self.assertTrue(server._build_admin_state_payload()["telemetry_fresh"])
                server._telemetry_received_at = time.monotonic() - 10
                stale = server._build_admin_state_payload()
                self.assertFalse(stale["telemetry_fresh"])
                self.assertEqual(stale["telemetry"], {})
            await wait_until(lambda: not server.godot_clients)
            self.assertEqual(server.latest_telemetry, {})
        finally:
            await server.stop()

    async def test_ws_origin_policy_before_upgrade_and_originless_collector(self) -> None:
        server = LiveBridgeServer(runtime_mode="development", port=0)
        await server.start()
        try:
            for route in ("ingest", "admin", "godot"):
                with self.subTest(route=route):
                    with self.assertRaises(InvalidStatus) as result:
                        async with websockets.connect(f"ws://127.0.0.1:{server.bound_port}/ws/{route}", origin="https://evil.example"):
                            pass
                    self.assertEqual(result.exception.response.status_code, 403)
            for origin in (None, f"http://127.0.0.1:{server.bound_port}", f"http://localhost:{server.bound_port}"):
                async with websockets.connect(f"ws://127.0.0.1:{server.bound_port}/ws/ingest", origin=origin) as ws:
                    await ws.send(json.dumps({"type": "ping"}))
                    self.assertEqual(json.loads(await ws.recv())["status"], "pong")
            request = Request(f"http://127.0.0.1:{server.bound_port}/api/admin/command?command=start_race",
                              headers={"Sec-Fetch-Site": "cross-site"})
            with self.assertRaises(HTTPError) as failure:
                await asyncio.to_thread(urlopen, request)
            self.assertEqual(failure.exception.code, 403)
        finally:
            await server.stop()


class LauncherTests(unittest.TestCase):
    def test_both_launcher_check_sets_separate_process_environments(self) -> None:
        root = Path(__file__).resolve().parents[2]
        result = subprocess.run([sys.executable, str(root / "tools" / "run_live_instances.py"), "--both", "--check"],
                                capture_output=True, text=True, check=True)
        plan = json.loads(result.stdout)
        self.assertTrue(plan["valid"])
        self.assertFalse(plan["processes_started"])
        tt, kw = plan["plans"]
        self.assertNotEqual(tt["state_dir"], kw["state_dir"])
        self.assertEqual(tt["godot_environment"]["LIVE_BRIDGE_WS_URL"], "ws://127.0.0.1:8765/ws/godot")
        self.assertEqual(kw["godot_environment"]["LIVE_BRIDGE_WS_URL"], "ws://127.0.0.1:8766/ws/godot")


if __name__ == "__main__":
    unittest.main()
