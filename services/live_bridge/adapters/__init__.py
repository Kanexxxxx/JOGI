"""Módulo de adaptadores de captura de eventos ao vivo para Corrida dos Candidatos."""

from __future__ import annotations

from .base import AdapterStats, BaseLiveAdapter, EventCallback
from .kwai_adapter import (
    DEFAULT_KWAI_WEBHOOK_HOST,
    DEFAULT_KWAI_WEBHOOK_PATH,
    DEFAULT_KWAI_WEBHOOK_PORT,
    KwaiAdapterConfig,
    KwaiLiveAdapter,
)
from .simulator_adapter import (
    SIMULATOR_PROFILES,
    SimulatorAdapter,
)
from .tiktok_adapter import (
    TIKTOK_AVAILABLE,
    TikTokAdapterConfig,
    TikTokLiveAdapter,
)

__all__ = [
    "AdapterStats",
    "BaseLiveAdapter",
    "EventCallback",
    "KwaiAdapterConfig",
    "KwaiLiveAdapter",
    "DEFAULT_KWAI_WEBHOOK_HOST",
    "DEFAULT_KWAI_WEBHOOK_PORT",
    "DEFAULT_KWAI_WEBHOOK_PATH",
    "SIMULATOR_PROFILES",
    "SimulatorAdapter",
    "TIKTOK_AVAILABLE",
    "TikTokAdapterConfig",
    "TikTokLiveAdapter",
]
