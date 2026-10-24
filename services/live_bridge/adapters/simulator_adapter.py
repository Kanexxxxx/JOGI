"""SimulatorAdapter — Adaptador simulador determinístico de eventos de live para testes e dev offline."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
import logging
import random
import time
from typing import Any

from .base import BaseLiveAdapter

try:
    from protocol import (
        build_attack_envelope,
        build_gift_envelope,
        build_follow_envelope,
        build_like_batch_envelope,
        build_share_envelope,
        build_vote_envelope,
        validate_envelope,
    )
except ImportError:
    from ..protocol import (
        build_attack_envelope,
        build_gift_envelope,
        build_follow_envelope,
        build_like_batch_envelope,
        build_share_envelope,
        build_vote_envelope,
        validate_envelope,
    )


logger = logging.getLogger("live_bridge.adapters.simulator")

SIMULATOR_PROFILES: dict[str, float] = {
    "calm": 2.0,          # 2 mensagens/s (~500ms)
    "typical_live": 15.0, # 15 mensagens/s (~66.7ms)
    "viral_storm": 100.0, # 100 mensagens/s (~10ms)
    "normal": 25.0,       # Perfil legado de compatibilidade
    "burst": 200.0,       # Perfil de estresse de curto prazo
    "chaos_fuzz": 40.0,   # Fuzzing de caracteres e tags
}

MOCK_VIEWERS: tuple[tuple[str, str], ...] = (
    ("usr_sim_01", "Torcedor_Lula"),
    ("usr_sim_02", "Capitao_Vence"),
    ("usr_sim_03", "Estrela_Vermelha"),
    ("usr_sim_04", "Verde_Amarelo_BR"),
    ("usr_sim_05", "Nordeste_Com_Lula"),
    ("usr_sim_06", "Mito_2026"),
    ("usr_sim_07", "Companheiro_Fiel"),
    ("usr_sim_08", "Patriota_Ativo"),
    ("usr_sim_09", "Lula_13_Na_Vea"),
    ("usr_sim_10", "Bolsonaro_22_BR"),
)

CHAOS_NAMES: tuple[str, ...] = (
    "[color=red][wave]HACKER_BBCODE[/wave][/color]",
    "Nome\u202eInvertido\u200bZeroWidth\u0007Beep",
    "   SuperLongUsernameQueUltrapassaVinteEQuatroCaracteresFacilmente   ",
    "<script>alert('xss')</script>Torcedor",
    "[img]https://evil.example/a.png[/img]Fã_Real",
)


@dataclass
class SimulatorAdapter(BaseLiveAdapter):
    """
    Adaptador 100% autônomo, offline e determinístico para testes e desenvolvimento.
    Permite emissão sob demanda de envelopes individuais, rajadas (`simulate_burst`),
    ou execução contínua com perfis de taxa ajustáveis (`calm`, `typical_live`, `viral_storm`).
    """

    adapter_name: str = "simulator"
    profile: str = "typical_live"
    seed: int = 42
    candidate_slot: int | None = None
    continuous: bool = False

    _rng: random.Random = field(default_factory=lambda: random.Random(42), init=False, repr=False)
    _sequence: int = field(default=0, init=False, repr=False)
    _base_timestamp_ms: int = field(default=1_760_000_000_000, init=False, repr=False)
    _loop_task: asyncio.Task[None] | None = field(default=None, init=False, repr=False)

    def __post_init__(self) -> None:
        if self.profile not in SIMULATOR_PROFILES:
            raise ValueError(
                f"Perfil inválido: {self.profile!r}. Opções válidas: {sorted(SIMULATOR_PROFILES)}"
            )
        self._rng = random.Random(self.seed)
        self._base_timestamp_ms = 1_760_000_000_000 + (self.seed * 1000)

    @property
    def rate_per_sec(self) -> float:
        return SIMULATOR_PROFILES.get(self.profile, 15.0)

    def set_profile(self, profile: str) -> None:
        """Altera o perfil de geração contínua em tempo de execução."""
        if profile not in SIMULATOR_PROFILES:
            raise ValueError(
                f"Perfil inválido: {profile!r}. Opções válidas: {sorted(SIMULATOR_PROFILES)}"
            )
        self.profile = profile

    def _pick_slot(self, override_slot: int | None = None) -> int:
        if override_slot is not None and 1 <= override_slot <= 2:
            return override_slot
        if self.candidate_slot is not None and 1 <= self.candidate_slot <= 2:
            return self.candidate_slot
        return self._rng.randint(1, 2)

    def _pick_viewer(self) -> tuple[str, str]:
        user_id, display_name = self._rng.choice(MOCK_VIEWERS)
        if self.profile == "chaos_fuzz" and self._rng.random() < 0.5:
            display_name = self._rng.choice(CHAOS_NAMES)
        return user_id, display_name

    def generate_envelope(
        self,
        event_type: str | None = None,
        candidate_slot: int | None = None,
        user_id: str | None = None,
        display_name: str | None = None,
        **kwargs: Any,
    ) -> dict[str, Any]:
        """
        Gera um envelope LiveEventEnvelope válido e estritamente formatado.
        Se event_type for None, escolhe deterministicamente conforme distribuição do perfil.
        """
        self._sequence += 1
        ts_ms = kwargs.get("timestamp_ms") or (
            self._base_timestamp_ms + (self._sequence * 50)
        )
        slot = self._pick_slot(candidate_slot)
        v_user_id, v_display_name = self._pick_viewer()
        uid = user_id or v_user_id
        name = display_name or v_display_name

        chosen_type = event_type
        if chosen_type is None:
            roll = self._rng.random()
            if roll < 0.45:
                chosen_type = "vote"
            elif roll < 0.75:
                chosen_type = "like_batch"
            elif roll < 0.85:
                chosen_type = "share"
            else:
                chosen_type = "gift"

        if chosen_type == "vote":
            repeat_count = kwargs.get("repeat_count", 1)
            return build_vote_envelope(
                user_id=uid,
                display_name=name,
                candidate_slot=slot,
                source="simulator",
                repeat_count=repeat_count,
                timestamp_ms=ts_ms,
                sequence=self._sequence,
            )

        if chosen_type == "like_batch":
            likes = kwargs.get("like_count") or self._rng.randint(5, 50)
            return build_like_batch_envelope(
                user_id=uid,
                display_name=name,
                like_count=likes,
                candidate_slot=slot,
                source="simulator",
                timestamp_ms=ts_ms,
                sequence=self._sequence,
            )

        if chosen_type == "share":
            return build_share_envelope(
                user_id=uid,
                display_name=name,
                candidate_slot=slot,
                source="simulator",
                timestamp_ms=ts_ms,
                sequence=self._sequence,
            )

        if chosen_type == "follow":
            return build_follow_envelope(user_id=uid, display_name=name,
                candidate_slot=slot, source="simulator", timestamp_ms=ts_ms, sequence=self._sequence)

        if chosen_type == "gift":
            tier = kwargs.get("gift_tier")
            if not tier:
                t_roll = self._rng.random()
                if t_roll < 0.50:
                    tier = "T1"
                elif t_roll < 0.80:
                    tier = "T2"
                elif t_roll < 0.95:
                    tier = "T3"
                else:
                    tier = "T4"
            if tier == "T3":
                target_slot = 2 if slot == 1 else 1
                return build_attack_envelope(
                    user_id=uid,
                    display_name=name,
                    candidate_slot=slot,
                    target_slot=target_slot,
                    obstacle_type=kwargs.get("obstacle_type", "pilha_documentos"),
                    source="simulator",
                    timestamp_ms=ts_ms,
                    sequence=self._sequence,
                )
            repeat_count = kwargs.get("repeat_count", 1)
            return build_gift_envelope(
                user_id=uid,
                display_name=name,
                candidate_slot=slot,
                gift_tier=tier,
                repeat_count=repeat_count,
                source="simulator",
                timestamp_ms=ts_ms,
                sequence=self._sequence,
            )

        raise ValueError(f"Tipo de evento não suportado no simulador: {chosen_type!r}")

    async def simulate_event(
        self,
        event_type: str = "vote",
        candidate_slot: int | None = None,
        user_id: str | None = None,
        display_name: str | None = None,
        **kwargs: Any,
    ) -> dict[str, Any]:
        """Gera e emite um evento individual sob demanda."""
        envelope = self.generate_envelope(
            event_type=event_type,
            candidate_slot=candidate_slot,
            user_id=user_id,
            display_name=display_name,
            **kwargs,
        )
        await self.emit_envelope(envelope)
        return envelope

    async def simulate_burst(
        self,
        count: int,
        candidate_slot: int | None = None,
        event_types: list[str] | None = None,
    ) -> list[dict[str, Any]]:
        """Gera e emite uma rajada de N eventos."""
        emitted: list[dict[str, Any]] = []
        for _ in range(max(1, count)):
            etype = None
            if event_types:
                etype = self._rng.choice(event_types)
            envelope = self.generate_envelope(
                event_type=etype,
                candidate_slot=candidate_slot,
            )
            await self.emit_envelope(envelope)
            emitted.append(envelope)
        return emitted

    async def _run_continuous_loop(self) -> None:
        """Loop contínuo de geração de eventos respeitando a cadência do perfil."""
        logger.info(
            "Iniciando loop contínuo do SimulatorAdapter (perfil: %s, %.1f msg/s).",
            self.profile,
            self.rate_per_sec,
        )
        try:
            while self._status == "running":
                interval = 1.0 / max(0.1, self.rate_per_sec)
                envelope = self.generate_envelope()
                await self.emit_envelope(envelope)
                await asyncio.sleep(interval)
        except asyncio.CancelledError:
            logger.debug("Loop contínuo do SimulatorAdapter cancelado.")
            raise
        except Exception as exc:
            self.record_error(exc)
            logger.exception("Erro inesperado no loop contínuo do SimulatorAdapter: %s", exc)

    async def start(self) -> None:
        """Inicia o adaptador do simulador e, se configurado, ativa o loop contínuo."""
        if self._status == "running":
            return
        self._started_at = time.time()
        self._status = "running"
        if self.continuous:
            self._loop_task = asyncio.create_task(self._run_continuous_loop())

    async def stop(self) -> None:
        """Encerra a execução do simulador."""
        if self._loop_task is not None and not self._loop_task.done():
            self._loop_task.cancel()
            try:
                await self._loop_task
            except asyncio.CancelledError:
                pass
            self._loop_task = None
        self._status = "stopped"

    def is_connected(self) -> bool:
        """O simulador offline é considerado conectado sempre que em estado 'running'."""
        return self._status == "running"

    def get_stats(self) -> dict[str, Any]:
        """Retorna telemetria detalhada do simulador."""
        return self.build_base_stats(
            extra_metadata={
                "profile": self.profile,
                "rate_per_sec": self.rate_per_sec,
                "seed": self.seed,
                "continuous": self.continuous,
                "sequence": self._sequence,
            }
        ).to_dict()
