"""MockLiveEventSimulator — Gerador determinístico de eventos para Corrida dos Candidatos."""

from __future__ import annotations

import argparse
import asyncio
from dataclasses import dataclass
import json
import logging
import random
import time
from typing import Any

import websockets

from protocol import (
    build_attack_envelope,
    build_gift_envelope,
    build_like_batch_envelope,
    build_share_envelope,
    build_vote_envelope,
)


logger = logging.getLogger("live_bridge.simulator")

MODE_RATES_PER_SEC: dict[str, float] = {
    "calm": 5.0,
    "normal": 25.0,
    "viral": 100.0,
    "burst": 200.0,
    "chaos_fuzz": 40.0,
}

MOCK_VIEWERS: tuple[tuple[str, str], ...] = (
    ("usr_101", "Torcedor_Lula"),
    ("usr_102", "Capitao_Vence"),
    ("usr_103", "Estrela_Vermelha"),
    ("usr_104", "Verde_Amarelo_BR"),
    ("usr_105", "Nordeste_Com_Lula"),
    ("usr_106", "Mito_2026"),
    ("usr_107", "Companheiro_Fiel"),
    ("usr_108", "Patriota_Ativo"),
    ("usr_109", "Lula_13_Na_Vea"),
    ("usr_110", "Bolsonaro_22_BR"),
)

CHAOS_FUZZ_NAMES: tuple[str, ...] = (
    "[color=red][wave]HACKER_BBCODE[/wave][/color]",
    "Nome\u202eInvertido\u200bZeroWidth\u0007Beep",
    "   SuperLongUsernameQueUltrapassaVinteEQuatroCaracteresFacilmente   ",
    "<script>alert('xss')</script>Torcedor",
    "[img]https://evil.example/a.png[/img]Fã_Real",
)


@dataclass
class SimulatorConfig:
    seed: int = 42
    mode: str = "normal"
    count: int = 30
    candidate_slot: int | None = None
    ingest_url: str = "ws://127.0.0.1:8765/ws/ingest"


class MockLiveEventSimulator:
    """
    Simulador determinístico capaz de gerar envelopes `LiveEventEnvelope` idênticos
    aos conectores de produção (votos #1..#6, like_batch, share e presentes T1..T4).
    """

    def __init__(self, config: SimulatorConfig | None = None) -> None:
        self.config: SimulatorConfig = config or SimulatorConfig()
        if self.config.mode not in MODE_RATES_PER_SEC:
            raise ValueError(
                f"Modo inválido: {self.config.mode!r}. Escolha entre {sorted(MODE_RATES_PER_SEC)}"
            )
        self._rng: random.Random = random.Random(self.config.seed)
        self._sequence: int = 0
        self._base_timestamp_ms: int = 1_760_000_000_000 + (self.config.seed * 1000)

    def _pick_candidate_slot(self) -> int:
        if self.config.candidate_slot is not None and 1 <= self.config.candidate_slot <= 2:
            return self.config.candidate_slot
        return self._rng.randint(1, 2)

    def _pick_viewer(self) -> tuple[str, str]:
        user_id, display_name = self._rng.choice(MOCK_VIEWERS)
        if self.config.mode == "chaos_fuzz" and self._rng.random() < 0.5:
            display_name = self._rng.choice(CHAOS_FUZZ_NAMES)
        return user_id, display_name

    def next_event(self) -> dict[str, Any]:
        """Gera o próximo envelope determinístico de acordo com a semente e o modo configurado."""
        self._sequence += 1
        ts_ms: int = self._base_timestamp_ms + (self._sequence * 50)
        slot: int = self._pick_candidate_slot()
        user_id, display_name = self._pick_viewer()

        roll: float = self._rng.random()
        if roll < 0.45:
            return build_vote_envelope(
                user_id=user_id,
                display_name=display_name,
                candidate_slot=slot,
                source="simulator",
                repeat_count=1,
                timestamp_ms=ts_ms,
                sequence=self._sequence,
            )
        if roll < 0.72:
            likes: int = self._rng.randint(5, 45)
            return build_like_batch_envelope(
                user_id=user_id,
                display_name=display_name,
                like_count=likes,
                candidate_slot=slot,
                source="simulator",
                timestamp_ms=ts_ms,
                sequence=self._sequence,
            )
        if roll < 0.82:
            return build_share_envelope(
                user_id=user_id,
                display_name=display_name,
                candidate_slot=slot,
                source="simulator",
                timestamp_ms=ts_ms,
                sequence=self._sequence,
            )

        tier_roll: float = self._rng.random()
        if tier_roll < 0.50:
            tier = "T1"
        elif tier_roll < 0.80:
            tier = "T2"
        elif tier_roll < 0.95:
            tier = "T3"
        else:
            tier = "T4"

        if tier == "T3":
            # T3 é Ataque Político com obstáculos (pilha de documentos/processos) na raia do oponente
            target_slot = 2 if slot == 1 else 1
            return build_attack_envelope(
                user_id=user_id,
                display_name=display_name,
                candidate_slot=slot,
                target_slot=target_slot,
                obstacle_type="pilha_documentos",
                source="simulator",
                timestamp_ms=ts_ms,
                sequence=self._sequence,
            )

        return build_gift_envelope(
            user_id=user_id,
            display_name=display_name,
            candidate_slot=slot,
            gift_tier=tier,
            repeat_count=1,
            source="simulator",
            timestamp_ms=ts_ms,
            sequence=self._sequence,
        )

    def generate_batch(self, count: int | None = None) -> list[dict[str, Any]]:
        """Gera uma lista determinística de envelopes para testes ou replay."""
        total: int = count if count is not None else self.config.count
        return [self.next_event() for _ in range(total)]

    async def stream_to_server(self) -> dict[str, int]:
        """Conecta em ws://127.0.0.1:8765/ws/ingest e dispara os eventos gerados."""
        rate: float = MODE_RATES_PER_SEC[self.config.mode]
        interval: float = 0.0 if self.config.mode == "burst" else (1.0 / rate)
        stats: dict[str, int] = {"sent": 0, "accepted": 0, "duplicate": 0, "error": 0}

        async with websockets.connect(self.config.ingest_url, max_size=8192) as ws:
            for _ in range(self.config.count):
                envelope = self.next_event()
                await ws.send(json.dumps(envelope, ensure_ascii=False))
                stats["sent"] += 1
                raw_ack = await ws.recv()
                ack = json.loads(raw_ack)
                status = str(ack.get("status", "error"))
                stats[status] = stats.get(status, 0) + 1
                if interval > 0.0:
                    await asyncio.sleep(interval)

        return stats


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Simulador de Eventos Local (MockLiveEventSimulator) para Corrida dos Candidatos."
    )
    parser.add_argument("--seed", type=int, default=42, help="Semente determinística (padrão: 42).")
    parser.add_argument(
        "--mode",
        choices=sorted(MODE_RATES_PER_SEC.keys()),
        default="normal",
        help="Perfil de tráfego da simulação.",
    )
    parser.add_argument("--count", type=int, default=25, help="Quantidade de eventos a enviar.")
    parser.add_argument(
        "--candidate",
        type=int,
        choices=[1, 2],
        default=None,
        help="Forçar todos os eventos para um candidato específico (1: Lula, 2: Bolsonaro).",
    )
    parser.add_argument(
        "--url",
        default="ws://127.0.0.1:8765/ws/ingest",
        help="URL WebSocket de ingestão do LiveBridge.",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    cfg = SimulatorConfig(
        seed=args.seed,
        mode=args.mode,
        count=args.count,
        candidate_slot=args.candidate,
        ingest_url=args.url,
    )
    sim = MockLiveEventSimulator(cfg)
    start_ts = time.perf_counter()
    summary = asyncio.run(sim.stream_to_server())
    elapsed = time.perf_counter() - start_ts
    logger.info("Simulação concluída em %.2fs: %s", elapsed, summary)


if __name__ == "__main__":
    main()
