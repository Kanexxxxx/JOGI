"""Testes unitários e de integração para os adaptadores de live (services/live_bridge/adapters/)."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
import json
import time
import unittest

from adapters import (
    BaseLiveAdapter,
    DEFAULT_KWAI_WEBHOOK_PORT,
    KwaiAdapterConfig,
    KwaiLiveAdapter,
    SIMULATOR_PROFILES,
    SimulatorAdapter,
    TikTokAdapterConfig,
    TikTokLiveAdapter,
)

try:
    from protocol import ProtocolValidationError, validate_envelope
except ImportError:
    from ..protocol import ProtocolValidationError, validate_envelope


@dataclass
class DummyAdapter(BaseLiveAdapter):
    """Adaptador concreto para testes da classe base BaseLiveAdapter."""

    adapter_name: str = "dummy"
    _connected: bool = False

    async def start(self) -> None:
        self._started_at = time.time()
        self._status = "running"
        self._connected = True

    async def stop(self) -> None:
        self._status = "stopped"
        self._connected = False

    def is_connected(self) -> bool:
        return self._connected

    def get_stats(self) -> dict[str, Any]:
        return self.build_base_stats().to_dict()


class TestBaseLiveAdapter(unittest.IsolatedAsyncioTestCase):
    """Testa contratos, emissão, telemetria e callbacks de BaseLiveAdapter."""

    async def test_callbacks_sync_and_async(self) -> None:
        adapter = DummyAdapter()
        received_sync: list[dict[str, Any]] = []
        received_async: list[dict[str, Any]] = []

        def sync_cb(env: dict[str, Any]) -> None:
            received_sync.append(env)

        async def async_cb(env: dict[str, Any]) -> None:
            received_async.append(env)

        adapter.on_event(sync_cb)
        adapter.on_event(async_cb)

        test_env = {"event_id": "evt_test_01", "type": "ping"}
        await adapter.emit_envelope(test_env)

        self.assertEqual(len(received_sync), 1)
        self.assertEqual(len(received_async), 1)
        self.assertEqual(adapter._events_emitted, 1)

        # Remoção de listener
        self.assertTrue(adapter.remove_event_listener(sync_cb))
        self.assertFalse(adapter.remove_event_listener(sync_cb))

        await adapter.emit_envelope(test_env)
        self.assertEqual(len(received_sync), 1)
        self.assertEqual(len(received_async), 2)

    async def test_queue_dispatch(self) -> None:
        queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=10)
        adapter = DummyAdapter(queue=queue)

        test_env = {"event_id": "evt_queue_01"}
        await adapter.emit_envelope(test_env)

        out = await queue.get()
        self.assertEqual(out["event_id"], "evt_queue_01")

    async def test_error_tracking_and_uptime(self) -> None:
        adapter = DummyAdapter()
        self.assertEqual(adapter.get_uptime_seconds(), 0.0)

        await adapter.start()
        self.assertGreaterEqual(adapter.get_uptime_seconds(), 0.0)

        adapter.record_error("Falha simulada de teste")
        stats = adapter.get_stats()
        self.assertEqual(stats["errors_count"], 1)
        self.assertEqual(stats["last_error"], "Falha simulada de teste")
        self.assertTrue(stats["is_connected"])

        await adapter.stop()
        self.assertFalse(adapter.is_connected())


class TestSimulatorAdapter(unittest.IsolatedAsyncioTestCase):
    """Testa o SimulatorAdapter determinístico em modos manual, rajada e contínuo."""

    def test_invalid_profile_raises_value_error(self) -> None:
        with self.assertRaises(ValueError):
            SimulatorAdapter(profile="perfil_inexistente")

    async def test_simulate_event_produces_strictly_valid_envelopes(self) -> None:
        sim = SimulatorAdapter(seed=123)
        await sim.start()

        # Voto explícito
        vote_env = await sim.simulate_event(event_type="vote", candidate_slot=1)
        validated_vote = validate_envelope(vote_env)
        self.assertEqual(validated_vote["event_type"], "vote")
        self.assertEqual(validated_vote["payload"]["candidate_slot"], 1)
        self.assertEqual(validated_vote["source"], "simulator")

        # Curtida
        like_env = await sim.simulate_event(event_type="like_batch", candidate_slot=2, like_count=42)
        validated_like = validate_envelope(like_env)
        self.assertEqual(validated_like["event_type"], "like_batch")
        self.assertEqual(validated_like["payload"]["like_count"], 42)

        # Presente T3 (Ataque Político ao adversário)
        gift_env = await sim.simulate_event(event_type="gift", candidate_slot=2, gift_tier="T3")
        validated_gift = validate_envelope(gift_env)
        self.assertEqual(validated_gift["event_type"], "gift")
        self.assertEqual(validated_gift["payload"]["gift_tier"], "T3")
        self.assertEqual(validated_gift["payload"]["action_id"], "gift_t3_attack")
        self.assertEqual(validated_gift["payload"]["target_slot"], 1)
        self.assertEqual(validated_gift["priority"], "P0")

        # Compartilhamento
        share_env = await sim.simulate_event(event_type="share", candidate_slot=1)
        validated_share = validate_envelope(share_env)
        self.assertEqual(validated_share["event_type"], "share")

        await sim.stop()

    async def test_simulate_burst_emits_requested_count(self) -> None:
        sim = SimulatorAdapter(seed=999)
        await sim.start()

        collected: list[dict[str, Any]] = []
        sim.on_event(lambda env: collected.append(env))

        burst = await sim.simulate_burst(count=15)
        self.assertEqual(len(burst), 15)
        self.assertEqual(len(collected), 15)

        for env in burst:
            validate_envelope(env)

        await sim.stop()

    async def test_deterministic_seed_produces_identical_sequences(self) -> None:
        sim1 = SimulatorAdapter(seed=42)
        sim2 = SimulatorAdapter(seed=42)

        seq1 = [sim1.generate_envelope() for _ in range(5)]
        seq2 = [sim2.generate_envelope() for _ in range(5)]

        for e1, e2 in zip(seq1, seq2):
            self.assertEqual(e1["event_type"], e2["event_type"])
            self.assertEqual(e1["payload"], e2["payload"])
            self.assertEqual(e1["user"], e2["user"])

    async def test_continuous_mode_lifecycle_and_rates(self) -> None:
        # Perfil viral_storm (100 msg/s) para testar rapidamente múltiplos disparos em ~60ms
        sim = SimulatorAdapter(profile="viral_storm", continuous=True, seed=777)
        received: list[dict[str, Any]] = []
        sim.on_event(lambda env: received.append(env))

        await sim.start()
        self.assertTrue(sim.is_connected())

        await asyncio.sleep(0.06)
        await sim.stop()

        self.assertFalse(sim.is_connected())
        self.assertGreater(len(received), 0)
        for env in received:
            validate_envelope(env)

        stats = sim.get_stats()
        self.assertEqual(stats["metadata"]["profile"], "viral_storm")
        self.assertEqual(stats["metadata"]["rate_per_sec"], 100.0)


class TestTikTokLiveAdapter(unittest.IsolatedAsyncioTestCase):
    """Testa inicialização segura, extração de votos e deduplicação do TikTokLiveAdapter."""

    async def test_initializes_disabled_when_missing_credentials_or_disabled(self) -> None:
        adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id=None))
        self.assertIn("DISABLED", adapter._status)
        self.assertFalse(adapter.is_connected())

        # start e stop não devem explodir
        await adapter.start()
        self.assertFalse(adapter.is_connected())
        await adapter.stop()

    async def test_handle_comment_event_extracts_vote_slot_and_ignores_non_votes(self) -> None:
        adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id="teste_live"))
        emitted: list[dict[str, Any]] = []
        adapter.on_event(lambda env: emitted.append(env))

        # Comentário válido com voto #2
        vote_event = {
            "comment": "Bora #2 rumo ao topo!!",
            "user": {"unique_id": "tt_user_1", "nickname": "Fã Coral"},
        }
        res = await adapter.handle_comment_event(vote_event)
        self.assertIsNotNone(res)
        self.assertEqual(len(emitted), 1)
        self.assertEqual(emitted[0]["event_type"], "vote")
        self.assertEqual(emitted[0]["payload"]["candidate_slot"], 2)
        self.assertEqual(emitted[0]["source"], "tiktok")

        # Comentário sem voto (deve ser ignorado sem emitir nada)
        chat_event = {
            "comment": "Live muito legal parabéns",
            "user": {"unique_id": "tt_user_2", "nickname": "Visitante"},
        }
        res2 = await adapter.handle_comment_event(chat_event)
        self.assertIsNone(res2)
        self.assertEqual(len(emitted), 1)

    async def test_handle_like_and_share_events(self) -> None:
        adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id="teste_live"))
        emitted: list[dict[str, Any]] = []
        adapter.on_event(lambda env: emitted.append(env))

        # Vota primeiro para registrar o candidato favorito
        await adapter.handle_comment_event({
            "comment": "#2",
            "user": {"unique_id": "tt_u3", "nickname": "BolsonaroFan"},
        })

        # Like deve ir para o candidato 2
        like_event = {"likes": 25, "user": {"unique_id": "tt_u3", "nickname": "BolsonaroFan"}}
        res_like = await adapter.handle_like_event(like_event)
        self.assertIsNotNone(res_like)
        self.assertEqual(res_like["event_type"], "like_batch")
        self.assertEqual(res_like["payload"]["like_count"], 25)
        self.assertEqual(res_like["payload"]["candidate_slot"], 2)

        # Share
        share_event = {"user": {"unique_id": "tt_u3", "nickname": "BolsonaroFan"}}
        res_share = await adapter.handle_share_event(share_event)
        self.assertIsNotNone(res_share)
        self.assertEqual(res_share["event_type"], "share")
        self.assertEqual(res_share["payload"]["candidate_slot"], 2)

    async def test_handle_gift_event_with_streak_deduplication(self) -> None:
        adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id="teste_live"))
        emitted: list[dict[str, Any]] = []
        adapter.on_event(lambda env: emitted.append(env))

        # Combo de rosas: 1 -> 3 -> 5
        g1 = {
            "user": {"unique_id": "donor_01", "nickname": "Doador_Top"},
            "gift": {
                "id": "gift_rose",
                "name": "Rosa",
                "repeat_count": 1,
                "streaking": True,
                "diamond_count": 1,
            },
            "streak_id": "streak_001",
        }
        res1 = await adapter.handle_gift_event(g1)
        self.assertIsNotNone(res1)
        self.assertEqual(res1["payload"]["repeat_count"], 1)

        g2 = {
            "user": {"unique_id": "donor_01", "nickname": "Doador_Top"},
            "gift": {
                "id": "gift_rose",
                "name": "Rosa",
                "repeat_count": 3,
                "streaking": True,
                "diamond_count": 1,
            },
            "streak_id": "streak_001",
        }
        res2 = await adapter.handle_gift_event(g2)
        self.assertIsNotNone(res2)
        self.assertEqual(res2["payload"]["repeat_count"], 2)  # delta = 3 - 1 = 2

        # Final do combo reenviando repeat_count=3 já processado
        g3 = {
            "user": {"unique_id": "donor_01", "nickname": "Doador_Top"},
            "gift": {
                "id": "gift_rose",
                "name": "Rosa",
                "repeat_count": 3,
                "streaking": False,
                "diamond_count": 1,
            },
            "streak_id": "streak_001",
        }
        res3 = await adapter.handle_gift_event(g3)
        self.assertIsNone(res3)  # delta = 0, duplicata descartada


class TestKwaiLiveAdapter(unittest.IsolatedAsyncioTestCase):
    """Testa o KwaiLiveAdapter passivo e o receptor de Webhook em loopback."""

    async def test_default_state_is_disabled_no_api(self) -> None:
        adapter = KwaiLiveAdapter()
        self.assertEqual(adapter._status, "DISABLED_NO_API")
        self.assertFalse(adapter.is_connected())

        # start não deve levantar exceções quando desativado
        await adapter.start()
        self.assertFalse(adapter.is_connected())
        await adapter.stop()

    async def test_ingest_raw_event_normalizes_to_kwai_source(self) -> None:
        adapter = KwaiLiveAdapter(config=KwaiAdapterConfig(enabled=True))
        emitted: list[dict[str, Any]] = []
        adapter.on_event(lambda env: emitted.append(env))

        # Comentário de voto
        raw_vote = {
            "type": "chat",
            "content": "Voto no #2 Bolsonaro!",
            "user_id": "kwai_usr_99",
            "display_name": "KwaiFan",
        }
        res_vote = await adapter.ingest_raw_event(raw_vote)
        self.assertIsNotNone(res_vote)
        self.assertEqual(res_vote["event_type"], "vote")
        self.assertEqual(res_vote["source"], "kwai")
        self.assertEqual(res_vote["payload"]["candidate_slot"], 2)

        # Presente com 150 moedas -> Tier T3
        raw_gift = {
            "type": "gift",
            "coins": 150,
            "repeat_count": 1,
            "user_id": "kwai_usr_99",
        }
        res_gift = await adapter.ingest_raw_event(raw_gift)
        self.assertIsNotNone(res_gift)
        self.assertEqual(res_gift["event_type"], "gift")
        self.assertEqual(res_gift["payload"]["gift_tier"], "T3")
        self.assertEqual(res_gift["payload"]["candidate_slot"], 2)  # Herdou o slot 2 do voto anterior

    async def test_webhook_http_server_in_loopback(self) -> None:
        # Usa porta efêmera para não conflitar
        test_port = 18766
        adapter = KwaiLiveAdapter(
            config=KwaiAdapterConfig(
                enabled=True,
                host="127.0.0.1",
                port=test_port,
                webhook_path="/webhook/kwai",
            )
        )
        emitted: list[dict[str, Any]] = []
        adapter.on_event(lambda env: emitted.append(env))

        await adapter.start()
        self.assertTrue(adapter.is_connected())

        # Dispara requisição HTTP POST assíncrona para o webhook local
        post_data = json.dumps({
            "type": "vote",
            "content": "#1",
            "user_id": "kwai_hook_user",
            "display_name": "HookTester",
        }).encode("utf-8")

        reader, writer = await asyncio.open_connection("127.0.0.1", test_port)
        http_req = (
            b"POST /webhook/kwai HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
            b"Content-Type: application/json\r\n"
            b"Content-Length: " + str(len(post_data)).encode("ascii") + b"\r\n"
            b"Connection: close\r\n\r\n" + post_data
        )
        writer.write(http_req)
        await writer.drain()

        resp_raw = await reader.read()
        writer.close()
        await writer.wait_closed()

        self.assertIn(b"200 OK", resp_raw)
        header_part, body_part = resp_raw.split(b"\r\n\r\n", 1)
        resp_body = json.loads(body_part.decode("utf-8"))
        self.assertTrue(resp_body["ingested"])
        self.assertEqual(resp_body["status"], "ok")

        self.assertEqual(len(emitted), 1)
        self.assertEqual(emitted[0]["event_type"], "vote")
        self.assertEqual(emitted[0]["payload"]["candidate_slot"], 1)

        await adapter.stop()
        self.assertFalse(adapter.is_connected())


if __name__ == "__main__":
    unittest.main()
