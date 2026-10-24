"""Testes automatizados unitários e ponta a ponta (E2E) para services/live_bridge/."""

from __future__ import annotations

import asyncio
import json
import unittest

import websockets

from protocol import (
    GiftStreakTracker,
    LRUDeduplicator,
    ProtocolValidationError,
    TokenBucket,
    build_gift_envelope,
    build_vote_envelope,
    parse_vote_slot_from_comment,
    sanitize_display_name,
    validate_envelope,
)
from server import LiveBridgeServer, SecurityBindError, validate_bind_host
from simulator import MockLiveEventSimulator, SimulatorConfig


class TestLiveBridgeProtocolAndSecurity(unittest.TestCase):
    """Valida sanitização Zero-Trust, schema LiveEventEnvelope, deduplicação LRU e loopback."""

    def test_sanitize_display_name_strips_bbcode_bidi_and_truncates(self) -> None:
        malicious = "[color=red][wave]Torcedor\u202e\u200b\u0007_Malicioso_1234567890_ExtraLong[/wave][/color]"
        sanitized = sanitize_display_name(malicious)
        self.assertNotIn("[", sanitized)
        self.assertNotIn("]", sanitized)
        self.assertNotIn("\u202e", sanitized)
        self.assertNotIn("\u200b", sanitized)
        self.assertNotIn("\u0007", sanitized)
        self.assertLessEqual(len(sanitized), 24)
        self.assertTrue(sanitized.startswith("Torcedor_Malicioso"))

    def test_parse_vote_slot_extracts_only_valid_candidate_slots(self) -> None:
        self.assertEqual(parse_vote_slot_from_comment("Vai #1 agora!!"), 1)
        self.assertEqual(parse_vote_slot_from_comment("meu voto é 2"), 2)
        self.assertEqual(parse_vote_slot_from_comment("torcendo pro lula"), 1)
        self.assertEqual(parse_vote_slot_from_comment("vai bolsonaro"), 2)
        self.assertIsNone(parse_vote_slot_from_comment("comentário aleatório sem voto #9"))
        self.assertIsNone(parse_vote_slot_from_comment(""))

    def test_validate_envelope_rejects_malformed_and_unauthorized_admin(self) -> None:
        valid_vote = build_vote_envelope(
            user_id="user_01",
            display_name="Maria",
            candidate_slot=2,
            event_id="evt_valid_00001",
        )
        checked = validate_envelope(valid_vote)
        self.assertEqual(checked["payload"]["candidate_slot"], 2)

        # candidate_slot fora de 1..2
        invalid_slot = dict(valid_vote)
        invalid_slot["payload"] = dict(valid_vote["payload"], candidate_slot=3)
        with self.assertRaises(ProtocolValidationError):
            validate_envelope(invalid_slot)

        # admin_command vindo de source != 'admin' deve ser bloqueado ([ALTO-01])
        spoofed_admin = {
            "schema_version": "1.0",
            "event_id": "evt_spoof_admin_01",
            "source": "tiktok",
            "event_type": "admin_command",
            "timestamp_ms": 1760000000000,
            "priority": "P0",
            "user": {"user_id": "attk", "display_name": "Attacker"},
            "payload": {"command": "restart_race", "action_id": "admin_restart"},
        }
        with self.assertRaises(ProtocolValidationError):
            validate_envelope(spoofed_admin)

    def test_lru_deduplicator_drops_duplicates_and_evicts_oldest(self) -> None:
        dedup = LRUDeduplicator(max_size=3, ttl_seconds=60.0)
        self.assertFalse(dedup.is_duplicate("evt_aaaa0001", now_monotonic=10.0))
        self.assertTrue(dedup.is_duplicate("evt_aaaa0001", now_monotonic=11.0))
        self.assertEqual(dedup.duplicates_dropped, 1)

        self.assertFalse(dedup.is_duplicate("evt_aaaa0002", now_monotonic=12.0))
        self.assertFalse(dedup.is_duplicate("evt_aaaa0003", now_monotonic=13.0))
        self.assertFalse(dedup.is_duplicate("evt_aaaa0004", now_monotonic=14.0))
        self.assertEqual(len(dedup), 3)

    def test_token_bucket_enforces_40_msg_per_sec(self) -> None:
        bucket = TokenBucket(rate_per_sec=40.0, capacity=40.0)
        for _ in range(40):
            self.assertTrue(bucket.consume(1.0, now_monotonic=100.0))
        self.assertFalse(bucket.consume(1.0, now_monotonic=100.0))
        self.assertAlmostEqual(bucket.time_until_available(1.0, now_monotonic=100.0), 0.025, places=3)
        self.assertTrue(bucket.consume(1.0, now_monotonic=100.026))

    def test_gift_streak_tracker_prevents_combo_duplication(self) -> None:
        tracker = GiftStreakTracker(ttl_seconds=60.0)
        # Pacotes incrementais do combo (1 -> 3 -> 5) e pacote final (5, streaking=False)
        d1 = tracker.register_gift_packet(
            user_id="u1", gift_id="rose", streak_id="s1", repeat_count=1, streaking=True, now_monotonic=1.0
        )
        d2 = tracker.register_gift_packet(
            user_id="u1", gift_id="rose", streak_id="s1", repeat_count=3, streaking=True, now_monotonic=1.2
        )
        d3 = tracker.register_gift_packet(
            user_id="u1", gift_id="rose", streak_id="s1", repeat_count=5, streaking=True, now_monotonic=1.5
        )
        d_end = tracker.register_gift_packet(
            user_id="u1", gift_id="rose", streak_id="s1", repeat_count=5, streaking=False, now_monotonic=1.8
        )
        self.assertEqual((d1, d2, d3, d_end), (1, 2, 2, 0))
        self.assertEqual(d1 + d2 + d3 + d_end, 5)

    def test_validate_bind_host_blocks_external_interfaces(self) -> None:
        self.assertEqual(validate_bind_host("127.0.0.1"), "127.0.0.1")
        self.assertEqual(validate_bind_host("localhost"), "127.0.0.1")
        with self.assertRaises(SecurityBindError):
            validate_bind_host("0.0.0.0")
        with self.assertRaises(SecurityBindError):
            validate_bind_host("192.168.1.10")


class TestLiveBridgeWebSocketEndToEnd(unittest.IsolatedAsyncioTestCase):
    """Valida a comunicação WebSocket real entre Simulador -> LiveBridgeServer -> Cliente Godot."""

    async def test_websocket_end_to_end_broadcast_and_deduplication(self) -> None:
        server = LiveBridgeServer(host="127.0.0.1", port=0, rate_limit_per_sec=200.0)
        await server.start()
        port = server.bound_port
        godot_url = f"ws://127.0.0.1:{port}/ws/godot"
        ingest_url = f"ws://127.0.0.1:{port}/ws/ingest"

        try:
            async with websockets.connect(godot_url, max_size=8192) as godot_ws:
                welcome_raw = await asyncio.wait_for(godot_ws.recv(), timeout=3.0)
                welcome = json.loads(welcome_raw)
                self.assertEqual(welcome["event_type"], "system_status")
                self.assertEqual(welcome["payload"]["status"], "CONNECTED")

                # 1. Envia lote determinístico via MockLiveEventSimulator
                sim = MockLiveEventSimulator(
                    SimulatorConfig(
                        seed=99,
                        mode="chaos_fuzz",
                        count=6,
                        candidate_slot=1,
                        ingest_url=ingest_url,
                    )
                )
                stats = await sim.stream_to_server()
                self.assertEqual(stats["sent"], 6)
                self.assertEqual(stats["accepted"], 6)

                received_envelopes = []
                for _ in range(6):
                    msg_raw = await asyncio.wait_for(godot_ws.recv(), timeout=3.0)
                    env = json.loads(msg_raw)
                    received_envelopes.append(env)
                    self.assertEqual(env["payload"]["candidate_slot"], 1)
                    self.assertNotIn("[", env["user"]["display_name"])
                    self.assertLessEqual(len(env["user"]["display_name"]), 24)

                # 2. Testa deduplicação reenviando o primeiro event_id
                dup_env = received_envelopes[0]
                async with websockets.connect(ingest_url, max_size=8192) as ingest_ws:
                    await ingest_ws.send(json.dumps(dup_env))
                    ack = json.loads(await asyncio.wait_for(ingest_ws.recv(), timeout=3.0))
                    self.assertEqual(ack["status"], "duplicate")

                    # 3. Testa rejeição de JSON malformado
                    await ingest_ws.send("{json_truncado_invalido")
                    err_ack = json.loads(await asyncio.wait_for(ingest_ws.recv(), timeout=3.0))
                    self.assertEqual(err_ack["status"], "error")
                    self.assertEqual(err_ack["code"], "INVALID_JSON")

                self.assertEqual(server.metrics["duplicates_dropped"], 1)
                self.assertEqual(server.metrics["invalid_rejected"], 1)
        finally:
            await server.stop()


class TestLiveBridgeAdminAndHttp(unittest.IsolatedAsyncioTestCase):
    """Valida o servidor unificado (HTTP + WebSocket) em 127.0.0.1:8765."""

    async def test_admin_static_http_and_api_state_serving(self) -> None:
        import urllib.request
        server = LiveBridgeServer(host="127.0.0.1", port=0)
        await server.start()
        port = server.bound_port

        try:
            # 1. GET /admin deve retornar 200 OK com HTML e cabeçalhos corretos
            res_admin = await asyncio.to_thread(urllib.request.urlopen, f"http://127.0.0.1:{port}/admin")
            self.assertEqual(res_admin.status, 200)
            self.assertIn("text/html", res_admin.headers.get("Content-Type", ""))
            html_body = res_admin.read().decode("utf-8")
            self.assertIn("Corrida dos Candidatos", html_body)

            # 2. GET /admin/styles.css deve retornar 200 OK com CSS
            res_css = await asyncio.to_thread(urllib.request.urlopen, f"http://127.0.0.1:{port}/admin/styles.css")
            self.assertEqual(res_css.status, 200)
            self.assertIn("text/css", res_css.headers.get("Content-Type", ""))

            # 3. GET /admin/app.js deve retornar 200 OK com JS
            res_js = await asyncio.to_thread(urllib.request.urlopen, f"http://127.0.0.1:{port}/admin/app.js")
            self.assertEqual(res_js.status, 200)
            self.assertIn("javascript", res_js.headers.get("Content-Type", ""))

            # 4. GET /health
            res_health = await asyncio.to_thread(urllib.request.urlopen, f"http://127.0.0.1:{port}/health")
            self.assertEqual(res_health.status, 200)
            health_json = json.loads(res_health.read().decode("utf-8"))
            self.assertEqual(health_json["status"], "ok")
            self.assertEqual(health_json["bound_port"], port)

            # 5. GET /api/state
            res_state = await asyncio.to_thread(urllib.request.urlopen, f"http://127.0.0.1:{port}/api/state")
            self.assertEqual(res_state.status, 200)
            state_json = json.loads(res_state.read().decode("utf-8"))
            self.assertEqual(state_json["status"], "ok")
            self.assertIn("race_state", state_json)
            self.assertEqual(len(state_json["candidates"]), 2)

            # 6. GET /api/admin/command?command=start_race
            res_cmd = await asyncio.to_thread(urllib.request.urlopen, f"http://127.0.0.1:{port}/api/admin/command?command=start_race")
            self.assertEqual(res_cmd.status, 200)
            cmd_json = json.loads(res_cmd.read().decode("utf-8"))
            self.assertEqual(cmd_json["status"], "ok")
            self.assertEqual(cmd_json["command"], "start_race")

            # 7. GET /api/admin/simulate?event_type=vote&slot=2&count=3
            res_sim = await asyncio.to_thread(urllib.request.urlopen, f"http://127.0.0.1:{port}/api/admin/simulate?event_type=vote&slot=2&count=3")
            self.assertEqual(res_sim.status, 200)
            sim_json = json.loads(res_sim.read().decode("utf-8"))
            self.assertEqual(sim_json["status"], "accepted")

        finally:
            await server.stop()

    async def test_security_rejections_host_and_origin(self) -> None:
        import urllib.request
        from urllib.error import HTTPError
        server = LiveBridgeServer(host="127.0.0.1", port=0)
        await server.start()
        port = server.bound_port

        try:
            # 1. Host externo não-loopback deve ser rejeitado com 403 Forbidden
            req_bad_host = urllib.request.Request(f"http://127.0.0.1:{port}/admin", headers={"Host": "malicious-site.com"})
            with self.assertRaises(HTTPError) as ctx:
                await asyncio.to_thread(urllib.request.urlopen, req_bad_host)
            self.assertEqual(ctx.exception.code, 403)

            # 2. Origin externa não autorizada (anti-CSRF/CSWSH) deve ser rejeitada com 403 Forbidden
            req_bad_origin = urllib.request.Request(f"http://127.0.0.1:{port}/api/state", headers={"Origin": "http://evil-attacker.com"})
            with self.assertRaises(HTTPError) as ctx2:
                await asyncio.to_thread(urllib.request.urlopen, req_bad_origin)
            self.assertEqual(ctx2.exception.code, 403)

        finally:
            await server.stop()

    async def test_security_unauthorized_source_admin_rejected_on_ingest(self) -> None:
        """Verifica que clientes em /ws/ingest NÃO podem forjar source='admin'."""
        server = LiveBridgeServer(host="127.0.0.1", port=0)
        await server.start()
        port = server.bound_port
        ingest_url = f"ws://127.0.0.1:{port}/ws/ingest"

        try:
            async with websockets.connect(ingest_url) as ws:
                spoofed = {
                    "source": "admin",
                    "event_type": "admin_command",
                    "payload": {"command": "restart_race"}
                }
                await ws.send(json.dumps(spoofed))
                reply_raw = await asyncio.wait_for(ws.recv(), timeout=3.0)
                reply = json.loads(reply_raw)
                self.assertEqual(reply["status"], "error")
                self.assertEqual(reply["code"], "UNAUTHORIZED_SOURCE")
            self.assertEqual(server.metrics["invalid_rejected"], 1)
        finally:
            await server.stop()

    async def test_admin_websocket_command_and_telemetry_flow(self) -> None:
        """Verifica fluxo completo de comando Admin -> Godot e telemetria Godot -> Admin."""
        server = LiveBridgeServer(host="127.0.0.1", port=0)
        await server.start()
        port = server.bound_port
        godot_url = f"ws://127.0.0.1:{port}/ws/godot"
        admin_url = f"ws://127.0.0.1:{port}/ws/admin"

        try:
            async with websockets.connect(godot_url) as godot_ws:
                # Descarta welcome do Godot
                await godot_ws.recv()

                async with websockets.connect(admin_url) as admin_ws:
                    # Admin recebe estado inicial
                    init_raw = await asyncio.wait_for(admin_ws.recv(), timeout=3.0)
                    init_msg = json.loads(init_raw)
                    self.assertEqual(init_msg["type"], "state_update")
                    self.assertTrue(init_msg["godot_connected"])

                    # 1. Admin envia comando restart_race
                    cmd_msg = {"type": "admin_command", "command": "restart_race"}
                    await admin_ws.send(json.dumps(cmd_msg))

                    # Admin recebe ack
                    ack_raw = await asyncio.wait_for(admin_ws.recv(), timeout=3.0)
                    ack = json.loads(ack_raw)
                    self.assertEqual(ack["status"], "ok")
                    self.assertEqual(ack["command"], "restart_race")

                    # Godot recebe o comando despachado
                    godot_rx_raw = await asyncio.wait_for(godot_ws.recv(), timeout=3.0)
                    godot_rx = json.loads(godot_rx_raw)
                    self.assertEqual(godot_rx["event_type"], "admin_command")
                    self.assertEqual(godot_rx["source"], "admin")
                    self.assertEqual(godot_rx["payload"]["command"], "restart_race")

                    # 2. Godot emite frame de telemetria
                    telemetry_frame = {
                        "type": "telemetry",
                        "current_state": 2,
                        "state_name": "RACING",
                        "race_elapsed_time": 8.75,
                        "winner_id": 0,
                        "match_events_count": 12,
                        "runners": [
                            {
                                "candidate_id": 1,
                                "name": "CORAL",
                                "rank": 1,
                                "progress_m": 45.2,
                                "progress_ratio": 0.452,
                                "current_speed": 13.5,
                                "lobby_votes": 10,
                                "is_finished": False,
                                "has_shield": False,
                                "is_boosted": True,
                                "is_stumbled": False,
                            }
                        ]
                    }
                    await godot_ws.send(json.dumps(telemetry_frame))

                    # 3. Admin recebe state_update com a nova telemetria
                    admin_telemetry_raw = await asyncio.wait_for(admin_ws.recv(), timeout=3.0)
                    admin_telemetry = json.loads(admin_telemetry_raw)
                    # Pode ser o telemetry_event do comando ou o state_update
                    if admin_telemetry.get("type") == "telemetry_event":
                        admin_telemetry_raw = await asyncio.wait_for(admin_ws.recv(), timeout=3.0)
                        admin_telemetry = json.loads(admin_telemetry_raw)

                    self.assertEqual(admin_telemetry["type"], "state_update")
                    self.assertEqual(admin_telemetry["race_state"], "RACING")
                    self.assertAlmostEqual(admin_telemetry["race_timer_seconds"], 8.8, places=1)
                    self.assertEqual(admin_telemetry["candidates"][0]["slot"], 1)
                    self.assertTrue(admin_telemetry["candidates"][0]["status"]["turbo"])

        finally:
            await server.stop()


if __name__ == "__main__":
    unittest.main(verbosity=2)
