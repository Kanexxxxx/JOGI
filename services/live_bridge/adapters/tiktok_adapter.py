"""TikTokLiveAdapter â€” Conector assÃ­ncrono para transmissÃµes do TikTok LIVE."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
import logging
import math
import random
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any

from .base import BaseLiveAdapter
from .normalization import ViewerContext, bounded_int, read_field
from gift_images import extract_gift_image
from avatar_images import extract_avatar_url

try:
    from protocol import (
        GiftStreakTracker,
        build_gift_envelope,
        build_follow_envelope,
        build_like_batch_envelope,
        build_share_envelope,
        build_vote_envelope,
        parse_vote_slot_from_comment,
        gift_tier_for_unit_coins,
    )
except ImportError:
    from ..protocol import (
        GiftStreakTracker,
        build_gift_envelope,
        build_follow_envelope,
        build_like_batch_envelope,
        build_share_envelope,
        build_vote_envelope,
        parse_vote_slot_from_comment,
        gift_tier_for_unit_coins,
    )

# Import dinÃ¢mico e seguro da biblioteca TikTokLive
try:
    from TikTokLive import TikTokLiveClient  # type: ignore[import-untyped]
    from TikTokLive.events import (  # type: ignore[import-untyped]
        CommentEvent,
        ConnectEvent,
        DisconnectEvent,
        FollowEvent,
        GiftEvent,
        LikeEvent,
        ShareEvent,
    )

    TIKTOK_AVAILABLE: bool = True
except ImportError:
    TIKTOK_AVAILABLE = False
    TikTokLiveClient = None
    CommentEvent = None
    FollowEvent = None
    ConnectEvent = None
    DisconnectEvent = None
    GiftEvent = None
    LikeEvent = None
    ShareEvent = None


logger = logging.getLogger("live_bridge.adapters.tiktok")


@dataclass
class TikTokAdapterConfig:
    """ConfiguraÃ§Ãµes de conexÃ£o para o TikTok LIVE."""

    unique_id: str | None = None  # @username pÃºblico da live
    enabled: bool = True
    auto_reconnect: bool = True
    base_backoff_sec: float = 15.0
    max_backoff_sec: float = 300.0
    offline_poll_sec: float = 120.0
    ambiguous_poll_sec: float = 300.0
    rate_limit_cooldown_sec: float = 900.0
    default_candidate_slot: int | None = None  # Neutral until viewer chooses 13/22.


@dataclass
class TikTokLiveAdapter(BaseLiveAdapter):
    """
    Adaptador para ingestÃ£o de eventos em tempo real do TikTok LIVE.
    - Captura torcida 13/22 (e #1/#2 legado), curtidas, presentes e compartilhamentos.
    - Se a biblioteca nÃ£o estiver instalada ou o @username nÃ£o for fornecido, inicializa com seguranÃ§a em modo DESATIVADO.
    - ReconexÃ£o resiliente com backoff exponencial + full jitter.
    - Zero credenciais sensÃ­veis ou cookies versionados no cÃ³digo.
    """

    adapter_name: str = "tiktok"
    config: TikTokAdapterConfig = field(default_factory=TikTokAdapterConfig)

    _client: Any = field(default=None, init=False, repr=False)
    _streak_tracker: GiftStreakTracker = field(default_factory=GiftStreakTracker, init=False, repr=False)
    _viewers: ViewerContext = field(default_factory=ViewerContext, init=False, repr=False)
    _worker_task: asyncio.Task[None] | None = field(default=None, init=False, repr=False)
    _reconnect_attempts: int = field(default=0, init=False, repr=False)
    _running: bool = field(default=False, init=False, repr=False)

    _http_status: int | None = field(default=None, init=False, repr=False)
    _retry_after: float = field(default=0.0, init=False, repr=False)
    _next_retry_at: float | None = field(default=None, init=False, repr=False)
    _last_error_kind: str | None = field(default=None, init=False, repr=False)

    async def _request_guard(self, request: Any) -> None:
        # SDK fallback must not issue a second network request after a block.
        if self._http_status in (429, 401, 403):
            raise ConnectionError("TikTok request suppressed after HTTP block")

    async def _response_guard(self, response: Any) -> None:
        status = int(response.status_code)
        if status in (429, 401, 403):
            self._http_status = status
            value = response.headers.get("Retry-After", "")
            try:
                self._retry_after = max(0.0, float(value))
            except (ValueError, TypeError):
                try:
                    self._retry_after = max(0.0, (parsedate_to_datetime(value) - datetime.now(timezone.utc)).total_seconds())
                except (ValueError, TypeError, OverflowError):
                    self._retry_after = 0.0
            if not math.isfinite(self._retry_after):
                self._retry_after = 0.0
            raise ConnectionError("TikTok HTTP request blocked")
        if status >= 400:
            response.raise_for_status()

    def _classify_failure(self, error: Exception) -> tuple[str, float]:
        kind = type(error).__name__
        self._last_error_kind = kind
        status = self._http_status
        if status is None:
            status = getattr(getattr(error, "response", None), "status_code", None)
        if status == 429 or kind in ("RateLimitError", "TooManyRequestsError", "SignatureRateLimitError"):
            retry_after = self._retry_after
            try:
                sdk_retry = float(getattr(error, "retry_after", 0.0))
                if math.isfinite(sdk_retry):
                    retry_after = max(retry_after, sdk_retry)
            except (ValueError, TypeError, OverflowError, KeyError):
                pass
            return "rate_limited", max(self.config.rate_limit_cooldown_sec, retry_after)
        if status in (401, 403) or kind in ("AgeRestrictedError", "CaptchaError"):
            return "access_blocked", self.config.rate_limit_cooldown_sec
        if kind == "UserOfflineError":
            return "waiting_room", self.config.offline_poll_sec
        if kind in ("UserNotFoundError", "FailedParseRoomIdError", "FailedResolveUserId", "JSONDecodeError"):
            # The LIVE endpoint does not authoritatively establish profile existence.
            return "room_unavailable", self.config.ambiguous_poll_sec
        return "connection_error", min(self.config.max_backoff_sec, self.config.base_backoff_sec * (2 ** min(self._reconnect_attempts, 6)))

    def __post_init__(self) -> None:
        clean_user = (self.config.unique_id or "").strip().lstrip("@")
        if not TIKTOK_AVAILABLE:
            self._status = "DISABLED_NO_LIB"
            logger.info(
                "TikTokLiveAdapter: biblioteca 'TikTokLive' nÃ£o instalada. "
                "Operando em modo DESATIVADO seguro (DISABLED_NO_LIB)."
            )
        elif not clean_user or not self.config.enabled:
            self._status = "DISABLED_NO_ACCOUNT"
            logger.info(
                "TikTokLiveAdapter: nenhum @username informado ou adaptador desativado. "
                "Operando em modo DESATIVADO seguro (DISABLED_NO_ACCOUNT)."
            )
        else:
            self.config.unique_id = clean_user
            self._status = "configured"

    @property
    def is_available(self) -> bool:
        """Indica se a biblioteca de terceiros estÃ¡ disponÃ­vel no ambiente."""
        return TIKTOK_AVAILABLE

    def is_connected(self) -> bool:
        """Retorna True se estiver conectado Ã  transmissÃ£o ao vivo."""
        if not TIKTOK_AVAILABLE or self._client is None:
            return False
        # TikTokLiveClient possui propriedade is_connected
        return bool(getattr(self._client, "is_connected", False) and self._status == "connected")

    def _extract_user_info(self, event: Any) -> tuple[str, str]:
        """Extrai user_id e display_name de eventos brutos do TikTok com fallbacks seguros."""
        user = read_field(event, "user")
        user_id = str(read_field(user, "id") or read_field(user, "user_id")
                      or read_field(user, "unique_id") or read_field(event, "user_id") or "anon_tiktok")[:128]
        nickname = str(read_field(user, "nickname") or read_field(event, "display_name") or user_id)[:256]
        return user_id, nickname

    def _extract_user_avatar(self, event: Any) -> str | None:
        return extract_avatar_url(read_field(event, "user") or read_field(event, "avatar_url"))

    async def handle_comment_event(self, event: Any) -> dict[str, Any] | None:
        """
        Processa comentÃ¡rios pÃºblicos da live.
        Extrai exclusivamente a intenÃ§Ã£o de torcida 13/22 via Zero-Trust.
        O texto livre do chat NUNCA Ã© repassado ao Godot.
        """
        comment_text: str = ""
        if isinstance(event, dict):
            comment_text = str(event.get("comment") or "")
        else:
            comment_text = str(getattr(event, "comment", "") or "")

        slot = parse_vote_slot_from_comment(comment_text)
        if slot is None or not (1 <= slot <= 2):
            return None

        user_id, display_name = self._extract_user_info(event)
        identity = self._viewers.identity(event, "tiktok", "vote")
        if identity is None:
            return None
        if user_id != "anon_tiktok":
            self._viewers.choose(user_id, slot)

        envelope = build_vote_envelope(
            user_id=user_id,
            display_name=display_name,
            candidate_slot=slot,
            source="tiktok",
            repeat_count=1,
            boost_allowed=self._viewers.allow_vote_boost(user_id),
            avatar_url=self._extract_user_avatar(event),
            **identity,
        )
        await self.emit_envelope(envelope)
        return envelope

    async def handle_like_event(self, event: Any) -> dict[str, Any] | None:
        """Processa lotes de curtidas do TikTok LIVE."""
        user_id, display_name = self._extract_user_info(event)
        identity = self._viewers.identity(event, "tiktok", "like_batch")
        if identity is None:
            return None
        likes = bounded_int(read_field(event, "count") or read_field(event, "likes"), 1, 50_000)
        slot = self._viewers.team(user_id, self.config.default_candidate_slot)
        envelope = build_like_batch_envelope(
            user_id=user_id,
            display_name=display_name,
            like_count=max(1, min(likes, 50_000)),
            candidate_slot=slot,
            source="tiktok",
            avatar_url=self._extract_user_avatar(event),
            **identity,
        )
        await self.emit_envelope(envelope)
        return envelope

    async def handle_gift_event(self, event: Any) -> dict[str, Any] | None:
        """
        Processa presentes do TikTok LIVE com deduplicaÃ§Ã£o de streaks.
        Evita contagem duplicada em combos progressivos (1 -> 3 -> 5) emitindo apenas os novos deltas.
        """
        user_id, display_name = self._extract_user_info(event)

        identity = self._viewers.identity(event, "tiktok", "gift")
        if identity is None:
            return None
        gift = read_field(event, "gift")
        raw_gift_id = read_field(event, "gift_id") or read_field(gift, "id")
        gift_id = str(raw_gift_id or "gift_default")[:128]
        gift_name = str(read_field(gift, "name") or read_field(event, "gift_name") or "Presente")
        gift_image_url = extract_gift_image(read_field(gift, "image") or read_field(event, "gift_image_url"))
        # Current SDK has cumulative count and streaking on GiftEvent, not static Gift.
        repeat_count = max(1, bounded_int(read_field(event, "repeat_count", read_field(gift, "repeat_count", 1)), 1, 1_000_000_000))
        streaking = bool(read_field(event, "streaking", read_field(gift, "streaking", False)))
        diamond_count = bounded_int(read_field(gift, "diamond_count", read_field(event, "diamond_count")), 0)
        streak_value = read_field(event, "streak_id") or read_field(event, "group_id")
        streak_id = str(streak_value)[:128] if streak_value else None
        streakable = bool(read_field(gift, "streakable", False) or read_field(gift, "type") == 1
                          or streaking or repeat_count > 1 or streak_id)

        delta = self._streak_tracker.register_gift_packet(
            user_id=user_id,
            gift_id=gift_id,
            streak_id=streak_id,
            repeat_count=repeat_count,
            streaking=streaking,
            streakable=streakable,
        )

        if delta <= 0:
            logger.debug(
                "Presente descartado pelo GiftStreakTracker (combo jÃ¡ contabilizado): user=%s gift=%s delta=%d",
                user_id,
                gift_id,
                delta,
            )
            return None

        # Mapeamento de presentes por valor em diamantes para tiers T1..T4
        tier = gift_tier_for_unit_coins(diamond_count)

        slot = self._viewers.team(user_id, self.config.default_candidate_slot)
        # Each wire envelope is bounded to 1000 gifts; a large cumulative delta
        # is emitted in chunks, preserving the total without truncating the combo.
        envelope: dict[str, Any] | None = None
        for part_index, start in enumerate(range(0, delta, 1000)):
            part_identity = dict(identity)
            if identity.get("event_id"):
                part_identity["event_id"] = f"{identity['event_id']}_{part_index}"
            part_identity["sequence"] = identity["sequence"] * 1_000_000 + part_index
            envelope = build_gift_envelope(
                user_id=user_id, display_name=display_name, candidate_slot=slot,
                gift_tier=tier, repeat_count=min(1000, delta - start), source="tiktok",
                gift_name=gift_name, unit_coin_value=diamond_count, **part_identity,
                gift_id=gift_id[:64] if raw_gift_id else None,
                gift_image_url=gift_image_url,
                avatar_url=self._extract_user_avatar(event),
            )
            await self.emit_envelope(envelope)
        return envelope

    async def handle_share_event(self, event: Any) -> dict[str, Any] | None:
        """Processa compartilhamento da live pelo espectador."""
        user_id, display_name = self._extract_user_info(event)
        identity = self._viewers.identity(event, "tiktok", "share")
        if identity is None:
            return None
        slot = self._viewers.team(user_id, self.config.default_candidate_slot)

        envelope = build_share_envelope(
            user_id=user_id,
            display_name=display_name,
            candidate_slot=slot,
            source="tiktok",
            avatar_url=self._extract_user_avatar(event),
            **identity,
        )
        await self.emit_envelope(envelope)
        return envelope

    async def handle_follow_event(self, event: Any) -> dict[str, Any] | None:
        user_id, display_name = self._extract_user_info(event)
        identity = self._viewers.identity(event, "tiktok", "follow")
        if identity is None:
            return None
        envelope = build_follow_envelope(user_id=user_id, display_name=display_name,
            candidate_slot=self._viewers.team(user_id, self.config.default_candidate_slot),
            source="tiktok", avatar_url=self._extract_user_avatar(event), **identity)
        await self.emit_envelope(envelope)
        return envelope

    def _setup_event_handlers(self, client: Any) -> None:
        """Registra os ouvintes no cliente do TikTokLive."""
        if client is None:
            return

        @client.on(ConnectEvent if ConnectEvent is not None else "connect")
        async def _on_connect(event: Any) -> None:
            self._status = "connected"
            self._reconnect_attempts = 0

        @client.on(DisconnectEvent if DisconnectEvent is not None else "disconnect")
        async def _on_disconnect(event: Any) -> None:
            self._status = "reconnecting"

        @client.on(CommentEvent if CommentEvent is not None else "comment")
        async def _on_comment(event: Any) -> None:
            try:
                await self.handle_comment_event(event)
            except Exception as exc:
                self.record_error(exc)
                logger.error("Erro ao tratar comment no TikTokLiveAdapter: %s", exc)

        @client.on(LikeEvent if LikeEvent is not None else "like")
        async def _on_like(event: Any) -> None:
            try:
                await self.handle_like_event(event)
            except Exception as exc:
                self.record_error(exc)
                logger.error("Erro ao tratar like no TikTokLiveAdapter: %s", exc)

        @client.on(GiftEvent if GiftEvent is not None else "gift")
        async def _on_gift(event: Any) -> None:
            try:
                await self.handle_gift_event(event)
            except Exception as exc:
                self.record_error(exc)
                logger.error("Erro ao tratar gift no TikTokLiveAdapter: %s", exc)

        @client.on(ShareEvent if ShareEvent is not None else "share")
        async def _on_share(event: Any) -> None:
            try:
                await self.handle_share_event(event)
            except Exception as exc:
                self.record_error(exc)
                logger.error("Erro ao tratar share no TikTokLiveAdapter: %s", exc)

        @client.on(FollowEvent if FollowEvent is not None else "follow")
        async def _on_follow(event: Any) -> None:
            try:
                await self.handle_follow_event(event)
            except Exception as exc:
                self.record_error(exc)
                logger.error("Erro ao tratar follow no TikTokLiveAdapter: %s", exc)

    async def _connection_loop(self) -> None:
        """Loop de conexÃ£o e reconexÃ£o automÃ¡tica com backoff exponencial + full jitter."""
        while self._running:
            try:
                self._status = "connecting"
                logger.info(
                    "Conectando ao TikTok LIVE para @%s...",
                    self.config.unique_id,
                )
                self._http_status = None
                self._retry_after = 0.0
                self._next_retry_at = None
                self._client = TikTokLiveClient(unique_id=self.config.unique_id, web_kwargs={"httpx_kwargs": {"event_hooks": {"request": [self._request_guard], "response": [self._response_guard]}}})
                self._setup_event_handlers(self._client)

                # SDK start returns its websocket lifetime task. Await both levels,
                # otherwise a new client would be created repeatedly while one is live.
                if hasattr(self._client, "start"):
                    lifetime = await self._client.start(fetch_room_info=True, fetch_gift_info=True)
                    if isinstance(lifetime, asyncio.Future):
                        await lifetime
                else:
                    while self._running and getattr(self._client, "is_connected", True):
                        await asyncio.sleep(1.0)
                if self._running:
                    raise ConnectionError("Public live connection ended")

            except asyncio.CancelledError:
                break
            except Exception as exc:
                error_kind = type(exc).__name__
                self._status, minimum_delay = self._classify_failure(exc)
                if self._status != "waiting_room":
                    self.record_error(f"{error_kind}: {self._status}; existÃªncia do perfil nÃ£o determinada pelo endpoint LIVE.")
                if self._client is not None and hasattr(self._client, "disconnect"):
                    try:
                        await self._client.disconnect(close_client=True)
                    except Exception:
                        logger.debug("Cliente TikTok jÃ¡ desconectado apÃ³s falha.")
                if not self.config.auto_reconnect or not self._running:
                    logger.warning("ConexÃ£o com TikTok encerrada e reconexÃ£o desativada.")
                    break

                self._reconnect_attempts += 1
                backoff = max(0.0, minimum_delay) + random.uniform(0.0, 0.5)
                self._next_retry_at = time.time() + backoff

                logger.warning(
                    "Queda no TikTok LIVE (@%s). Tentativa %d de reconexÃ£o em %.1fs: %s",
                    self.config.unique_id,
                    self._reconnect_attempts,
                    backoff,
                    error_kind,
                )
                await asyncio.sleep(backoff)

    async def start(self) -> None:
        """Inicia a conexÃ£o assÃ­ncrona com o TikTok LIVE se configurado e habilitado."""
        if not TIKTOK_AVAILABLE:
            logger.warning("TikTokLiveAdapter: biblioteca ausente. start() ignorado com seguranÃ§a.")
            return

        clean_user = (self.config.unique_id or "").strip().lstrip("@")
        if not clean_user or not self.config.enabled:
            logger.warning("TikTokLiveAdapter: conta pÃºblica ausente ou escuta desativada. start() ignorado.")
            return

        if self._running:
            return

        self._running = True
        self._started_at = time.time()
        self._worker_task = asyncio.create_task(self._connection_loop())

    async def stop(self) -> None:
        """Desconecta do TikTok LIVE e cancela tarefas pendentes de rede."""
        self._running = False
        if self._client is not None and hasattr(self._client, "disconnect"):
            try:
                await self._client.disconnect(close_client=True)
            except Exception as exc:
                logger.debug("ExceÃ§Ã£o ao desconectar client TikTok: %s", exc)

        if self._worker_task is not None and not self._worker_task.done():
            self._worker_task.cancel()
            try:
                await self._worker_task
            except asyncio.CancelledError:
                pass
            self._worker_task = None

        self._status = "stopped"
        logger.info("TikTokLiveAdapter encerrado.")

    def get_stats(self) -> dict[str, Any]:
        """Retorna telemetria e estado de conexÃ£o do adaptador TikTok."""
        return self.build_base_stats(
            extra_metadata={
                "unique_id": self.config.unique_id,
                "reconnect_attempts": self._reconnect_attempts,
                "tiktok_library_available": TIKTOK_AVAILABLE,
                "last_http_status": self._http_status,
                "last_error_kind": self._last_error_kind,
                "next_retry_at": self._next_retry_at,
                "profile_existence": "not_determined_by_live_endpoint",
            }
        ).to_dict()
