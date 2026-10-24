"""BaseLiveAdapter — Contrato base abstrato e ciclo de vida para conectores de live."""

from __future__ import annotations

from abc import ABC, abstractmethod
import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
import inspect
import logging
import time
from typing import Any


logger = logging.getLogger("live_bridge.adapters.base")

EventCallback = Callable[[dict[str, Any]], Awaitable[None] | None]


@dataclass
class AdapterStats:
    """Métricas operacionais e telemetria de um adaptador de live."""

    adapter_name: str
    status: str
    is_connected: bool
    events_emitted: int = 0
    errors_count: int = 0
    started_at: float | None = None
    uptime_seconds: float = 0.0
    last_event_timestamp: float | None = None
    last_error: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "adapter_name": self.adapter_name,
            "status": self.status,
            "is_connected": self.is_connected,
            "events_emitted": self.events_emitted,
            "errors_count": self.errors_count,
            "started_at": self.started_at,
            "uptime_seconds": round(self.uptime_seconds, 2),
            "last_event_timestamp": self.last_event_timestamp,
            "last_error": self.last_error,
            "metadata": dict(self.metadata),
        }


@dataclass
class BaseLiveAdapter(ABC):
    """
    Classe base abstrata para todos os adaptadores de captura de eventos ao vivo.
    Garante o desacoplamento entre fontes externas (TikTok, Kwai, Simulador)
    e a fila prioritária do servidor WebSocket do LiveBridge.
    """

    adapter_name: str = "base"
    queue: asyncio.Queue[dict[str, Any]] | None = None
    _callbacks: list[EventCallback] = field(default_factory=list, init=False, repr=False)
    _events_emitted: int = field(default=0, init=False, repr=False)
    _errors_count: int = field(default=0, init=False, repr=False)
    _started_at: float | None = field(default=None, init=False, repr=False)
    _last_event_timestamp: float | None = field(default=None, init=False, repr=False)
    _last_error: str | None = field(default=None, init=False, repr=False)
    _status: str = field(default="idle", init=False)

    @abstractmethod
    async def start(self) -> None:
        """Inicia o ciclo de vida do adaptador (conexão, workers e loops assíncronos)."""
        raise NotImplementedError

    @abstractmethod
    async def stop(self) -> None:
        """Encerra o adaptador e limpa recursos, cancelando tarefas em segundo plano."""
        raise NotImplementedError

    @abstractmethod
    def is_connected(self) -> bool:
        """Retorna True se o adaptador estiver ativamente conectado e pronto para receber eventos."""
        raise NotImplementedError

    @abstractmethod
    def get_stats(self) -> dict[str, Any]:
        """Retorna um dicionário com estatísticas de telemetria do adaptador."""
        raise NotImplementedError

    def on_event(self, callback: EventCallback) -> None:
        """Registra uma função de callback (síncrona ou assíncrona) para receber envelopes emitidos."""
        if callback not in self._callbacks:
            self._callbacks.append(callback)

    def remove_event_listener(self, callback: EventCallback) -> bool:
        """Remove um callback registrado. Retorna True se encontrado e removido."""
        if callback in self._callbacks:
            self._callbacks.remove(callback)
            return True
        return False

    async def emit_envelope(self, envelope: dict[str, Any]) -> None:
        """
        Emite um envelope validado para a fila assíncrona configurada e/ou
        para todos os ouvintes registrados.
        """
        self._events_emitted += 1
        self._last_event_timestamp = time.time()

        # Envia para fila assíncrona se fornecida
        if self.queue is not None:
            try:
                self.queue.put_nowait(envelope)
            except asyncio.QueueFull:
                logger.warning(
                    "Fila do adaptador %s está cheia; aguardando espaço para emitir envelope %s.",
                    self.adapter_name,
                    envelope.get("event_id"),
                )
                try:
                    await asyncio.wait_for(self.queue.put(envelope), timeout=2.0)
                except asyncio.TimeoutError:
                    self.record_error(
                        f"Timeout ao enfileirar envelope {envelope.get('event_id')} em {self.adapter_name}"
                    )

        # Dispara callbacks registrados de forma segura
        for cb in list(self._callbacks):
            try:
                if inspect.iscoroutinefunction(cb):
                    await cb(envelope)
                else:
                    res = cb(envelope)
                    if inspect.isawaitable(res):
                        await res
            except Exception as exc:
                self.record_error(exc)
                logger.exception(
                    "Erro ao executar callback no adaptador %s para envelope %s: %s",
                    self.adapter_name,
                    envelope.get("event_id"),
                    exc,
                )

    def record_error(self, error: Exception | str) -> None:
        """Registra a ocorrência de um erro na telemetria interna do adaptador."""
        self._errors_count += 1
        self._last_error = str(error)

    def get_uptime_seconds(self) -> float:
        """Retorna o tempo de atividade em segundos desde a inicialização."""
        if self._started_at is None:
            return 0.0
        return max(0.0, time.time() - self._started_at)

    def build_base_stats(self, extra_metadata: dict[str, Any] | None = None) -> AdapterStats:
        """Auxiliar para construir o objeto AdapterStats com as métricas da classe base."""
        meta = dict(extra_metadata or {})
        return AdapterStats(
            adapter_name=self.adapter_name,
            status=self._status,
            is_connected=self.is_connected(),
            events_emitted=self._events_emitted,
            errors_count=self._errors_count,
            started_at=self._started_at,
            uptime_seconds=self.get_uptime_seconds(),
            last_event_timestamp=self._last_event_timestamp,
            last_error=self._last_error,
            metadata=meta,
        )
