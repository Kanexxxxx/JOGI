"""Servidor WebSocket e HTTP Local (127.0.0.1:8765) para Corrida dos Candidatos.

Oferece na MESMA porta 8765:
- Painel Web Administrativo em http://127.0.0.1:8765/admin
- Canal WebSocket administrativo em ws://127.0.0.1:8765/ws/admin (streaming de telemetria e comandos autorizados)
- Canal WebSocket do motor Godot 4 em ws://127.0.0.1:8765/ws/godot (recebe eventos e emite telemetria)
- Canal WebSocket de ingestão em ws://127.0.0.1:8765/ws/ingest (Zero-Trust, bloqueia spoofing de source='admin')
- Endpoints HTTP REST: /health, /api/state, /api/admin/command, /api/admin/simulate
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import pathlib
import sqlite3
import time
from typing import Any
import urllib.parse

import websockets
from websockets.http11 import Headers, Response
from adapters.normalization import ViewerContext, bounded_int
from outbox import GiftOutbox
from live_goal import LiveGoalSettings
from gift_catalog import GiftCatalog
from gift_images import GiftImageCache
from audio_settings import AudioSettings, AUDIO_KEYS
from kwai_collector_settings import KwaiCollectorSettings

from protocol import (
    CANDIDATES,
    LRUDeduplicator,
    MAX_PACKET_BYTES,
    ProtocolValidationError,
    SCHEMA_VERSION,
    TokenBucket,
    VALID_ADMIN_COMMANDS,
    build_admin_command_envelope,
    build_attack_envelope,
    build_gift_envelope,
    build_follow_envelope,
    build_like_batch_envelope,
    build_share_envelope,
    build_vote_envelope,
    parse_vote_slot_from_comment,
    gift_tier_for_unit_coins,
    validate_envelope,
)


logger = logging.getLogger("live_bridge.server")

DEFAULT_HOST: str = "127.0.0.1"
DEFAULT_PORT: int = 8765
ALLOWED_LOOPBACK_HOSTS: frozenset[str] = frozenset({"127.0.0.1", "localhost"})


class SecurityBindError(PermissionError):
    """Erro lançado ao tentar vincular o servidor fora do loopback local (127.0.0.1)."""


def validate_bind_host(host: str) -> str:
    """
    Garante que o LiveBridge escute exclusivamente em loopback (127.0.0.1).
    Qualquer tentativa de bind em 0.0.0.0, :: ou IP de rede externa é bloqueada.
    """
    normalized: str = str(host).strip().lower()
    if normalized not in ALLOWED_LOOPBACK_HOSTS:
        raise SecurityBindError(
            f"Proibido fazer bind em {host!r}. O LiveBridge aceita exclusivamente '127.0.0.1'."
        )
    return "127.0.0.1"


def is_allowed_origin(origin: str | None, port: int) -> bool:
    """Native collectors omit Origin; browsers must originate from this local panel."""
    if origin is None:
        return True
    try:
        parsed = urllib.parse.urlsplit(origin)
        return bool(parsed.scheme == "http" and parsed.hostname in ALLOWED_LOOPBACK_HOSTS
                    and (parsed.port or 80) == port and not parsed.username and not parsed.password
                    and not parsed.path and not parsed.query and not parsed.fragment)
    except ValueError:
        return False


def _extract_ws_path(ws: Any, *args: Any) -> str:
    """Extrai o caminho da rota WebSocket de forma compatível com websockets v11..v17+."""
    if args and isinstance(args[0], str) and args[0]:
        return args[0].split("?", 1)[0]
    req = getattr(ws, "request", None)
    if req is not None and hasattr(req, "path") and isinstance(req.path, str):
        return req.path.split("?", 1)[0]
    path = getattr(ws, "path", None)
    if isinstance(path, str) and path:
        return path.split("?", 1)[0]
    return "/ws/godot"


class LiveBridgeServer:
    """
    Servidor intermediário local unificado (HTTP + WebSocket) em 127.0.0.1:8765:
    - Serve o painel web administrativo em `/admin`
    - Gerencia conexões WebSocket em `/ws/godot`, `/ws/admin` e `/ws/ingest`
    - Validação Zero-Trust, deduplicação LRU (10.000 chaves), filas P0/P1/P2 e Token Bucket (40 msg/s)
    - Streaming de telemetria em tempo real do Godot para o painel de controle
    """

    def __init__(
        self,
        host: str = DEFAULT_HOST,
        port: int = DEFAULT_PORT,
        *,
        rate_limit_per_sec: float = 40.0,
        dedup_capacity: int = 10_000,
        platform: str = "local",
        account: str = "",
        outbox_path: pathlib.Path | None = None,
        gift_capacity: int = 5000,
        ack_retry_seconds: float = 5.0,
        kwai_webhook_port: int = 8786,
    ) -> None:
        if platform not in ("local", "tiktok", "kwai"):
            raise ValueError("platform deve ser local, tiktok ou kwai.")
        self.host: str = validate_bind_host(host)
        self.port: int = int(port)
        self.platform = platform
        self.account = account.strip().lstrip("@")[:64]
        self.kwai_webhook_port = int(kwai_webhook_port)
        self.ack_retry_seconds = max(0.05, ack_retry_seconds)
        self.outbox = GiftOutbox(outbox_path, platform=platform, capacity=gift_capacity)
        try:
            self.gift_catalog = GiftCatalog(self.outbox.db)
            self.live_goal = LiveGoalSettings(outbox_path.parent / "live_goal.json" if outbox_path else None)
            self.gift_images = GiftImageCache(outbox_path.parent / "gift-icons" if outbox_path else None)
            self.audio_settings = AudioSettings(outbox_path.parent / "audio_settings.json" if outbox_path else None)
            self.kwai_collector = KwaiCollectorSettings(
                outbox_path.parent / "kwai_collector.json" if outbox_path else None,
                default_account=self.account,
            )
        except Exception:
            self.outbox.close()
            raise
        self._telemetry_received_at: float | None = None
        self._godot_available = asyncio.Event()
        self._live_adapter: Any = None
        self.deduplicator: LRUDeduplicator = LRUDeduplicator(max_size=dedup_capacity)
        self.token_bucket: TokenBucket = TokenBucket(
            rate_per_sec=rate_limit_per_sec,
            capacity=rate_limit_per_sec,
        )

        self.godot_clients: set[Any] = set()
        self.ingest_clients: set[Any] = set()
        self.admin_clients: set[Any] = set()

        self.latest_telemetry: dict[str, Any] = {}
        self._admin_dir: pathlib.Path = pathlib.Path(__file__).parent / "admin"

        self.p0_queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=500)
        self.p1_queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=1000)
        self.p2_queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=1000)

        self._queue_notify: asyncio.Event = asyncio.Event()
        self._server: Any = None
        self._dispatch_task: asyncio.Task[None] | None = None
        self._running: bool = False
        self._seq: int = 0
        self._ingest_viewers: dict[str, ViewerContext] = {
            source: ViewerContext() for source in ("tiktok", "kwai", "simulator")
        }

        self.metrics: dict[str, int] = {
            "received_total": 0,
            "accepted_total": 0,
            "duplicates_dropped": 0,
            "invalid_rejected": 0,
            "p2_shed_dropped": 0,
            "dispatched_to_godot": 0,
            "gift_acks_total": 0,
            "gift_busy_rejected": 0,
            "storage_errors": 0,
            "platform_rejected": 0,
            "p1_shed_dropped": 0,
            "adapter_backpressure_pending": 0,
        }

    def platform_listener_state(self) -> dict[str, Any]:
        kwai_meta: dict[str, Any] = {}
        if self.platform == "kwai":
            webhook_port = (
                int(getattr(self._live_adapter, "bound_port", self.kwai_webhook_port))
                if self._live_adapter is not None
                else self.kwai_webhook_port
            )
            adapter_extra = (
                self._live_adapter.get_stats().get("extra_metadata", {})
                if self._live_adapter is not None
                else {}
            )
            kwai_meta = {
                "kwai_collector": {
                    **self.kwai_collector.value,
                    "webhook_url": f"http://127.0.0.1:{webhook_port}/webhook/kwai",
                    "webhook_port": webhook_port,
                    "webhook_listening": bool(adapter_extra.get("webhook_listening", False)),
                    "collector_detail": str(adapter_extra.get("collector_detail", "")),
                    "collector_live_url": str(adapter_extra.get("collector_live_url", "")),
                    "collector_age_seconds": adapter_extra.get("collector_age_seconds"),
                    "collector_events_forwarded": int(adapter_extra.get("collector_events_forwarded", 0)),
                }
            }
        if self._live_adapter is not None:
            stats = self._live_adapter.get_stats()
            return {
                "platform_events_connected": self._live_adapter.is_connected(),
                "platform_events_status": stats["status"],
                **kwai_meta,
            }
        return {
            "platform_events_connected": False,
            "platform_events_status": "kwai_requires_collector" if self.platform == "kwai" else "not_started",
            **kwai_meta,
        }

    async def _receive_adapter_event(self, envelope: dict[str, Any]) -> None:
        self.metrics["adapter_backpressure_pending"] += 1
        try:
            while self._running:
                outcome = self.enqueue_envelope(envelope)
                if outcome in ("accepted", "duplicate"):
                    return
                if outcome != "busy":
                    raise ProtocolValidationError(f"Evento do coletor recusado: {outcome}.")
                await asyncio.sleep(0.25)
        finally:
            self.metrics["adapter_backpressure_pending"] -= 1

    async def start_live_listener(self) -> None:
        if self.platform == "kwai":
            if self._live_adapter is not None:
                return
            from adapters.kwai_adapter import KwaiAdapterConfig, KwaiLiveAdapter
            self._live_adapter = KwaiLiveAdapter(
                config=KwaiAdapterConfig(
                    enabled=True,
                    host="127.0.0.1",
                    port=self.kwai_webhook_port,
                    require_collector_room=True,
                )
            )
            self._live_adapter.on_event(self._receive_adapter_event)
            await self._live_adapter.start()
            return
        if self.platform != "tiktok" or not self.account:
            raise ValueError("Escuta pública automática disponível somente para TikTok com --account ou Kwai.")
        if self._live_adapter is not None:
            return
        from adapters.tiktok_adapter import TikTokAdapterConfig, TikTokLiveAdapter
        self._live_adapter = TikTokLiveAdapter(config=TikTokAdapterConfig(unique_id=self.account))
        if not self._live_adapter.is_available:
            self._live_adapter = None
            raise RuntimeError("SDK TikTokLive ausente. Execute uv sync --extra tiktok neste projeto.")
        self._live_adapter.on_event(self._receive_adapter_event)
        await self._live_adapter.start()

    @property
    def bound_port(self) -> int:
        if self._server is not None and getattr(self._server, "sockets", None):
            for sock in self._server.sockets:
                sockname = sock.getsockname()
                if isinstance(sockname, tuple) and len(sockname) >= 2:
                    return int(sockname[1])
        return self.port

    async def start(self) -> None:
        """Inicia o servidor unificado HTTP + WebSocket em 127.0.0.1 e a task de despacho."""
        validate_bind_host(self.host)
        self._running = True
        try:
            self._server = await websockets.serve(
                self._handle_client, self.host, self.port,
                max_size=MAX_PACKET_BYTES, ping_interval=10.0, ping_timeout=20.0,
                process_request=self._process_http_or_ws_request,
            )
        except Exception:
            self._running = False
            self.outbox.close()
            raise
        self._dispatch_task = asyncio.create_task(self._dispatch_loop())
        logger.info(
            "LiveBridgeServer unificado escutando em ws://%s:%d e http://%s:%d/admin",
            self.host,
            self.bound_port,
            self.host,
            self.bound_port,
        )

    async def stop(self) -> None:
        """Encerra graciosamente as tasks e conexões abertas."""
        self._running = False
        if self._live_adapter is not None:
            await self._live_adapter.stop()
        self._queue_notify.set()
        if self._dispatch_task is not None:
            self._dispatch_task.cancel()
            try:
                await self._dispatch_task
            except asyncio.CancelledError:
                pass
            self._dispatch_task = None

        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None
        await self.gift_images.stop()
        self.outbox.close()

    def _get_fallback_candidates(self) -> list[dict[str, Any]]:
        colors = {
            1: "#FF3B5C",
            2: "#FACC15",
        }
        out = []
        for slot in (1, 2):
            meta = CANDIDATES.get(slot, {})
            name = meta.get("name", "Lula" if slot == 1 else "Flávio Bolsonaro")
            out.append(
                {
                    "slot": slot,
                    "id": "lula" if slot == 1 else "bolsonaro",
                    "name": name,
                    "color": colors.get(slot, "#FFFFFF"),
                    "position": slot,
                    "distance_meters": 0.0,
                    "progress_pct": 0.0,
                    "speed_mps": 12.0,
                    "votes": 0,
                    "status": {"turbo": False, "shield": False, "stumble": False},
                }
            )
        return out

    def _build_admin_state_payload(self) -> dict[str, Any]:
        """Gera o snapshot completo do estado para o painel web admin (conforme CONTRACT.md)."""
        telemetry_age = (time.monotonic() - self._telemetry_received_at
                         if self._telemetry_received_at is not None else None)
        telemetry_fresh = bool(self.godot_clients and telemetry_age is not None and telemetry_age <= 5.0)
        raw = self.latest_telemetry if telemetry_fresh else {}
        runners = raw.get("runners", [])
        colors = {
            1: "#FF3B5C",
            2: "#FACC15",
        }
        candidates = []
        if runners:
            for r in runners:
                slot = int(r.get("candidate_id", 1))
                if slot not in (1, 2):
                    continue
                cand_id = "lula" if slot == 1 else "bolsonaro"
                cand_name = "Lula" if slot == 1 else "Flávio Bolsonaro"
                candidates.append(
                    {
                        "slot": slot,
                        "id": cand_id,
                        "name": r.get("name", cand_name),
                        "color": colors.get(slot, "#FFFFFF"),
                        "position": int(r.get("rank", slot)),
                        "distance_meters": round(float(r.get("progress_m", 0.0)), 1),
                        "progress_pct": round(float(r.get("progress_ratio", 0.0)) * 100.0, 1),
                        "speed_mps": round(float(r.get("current_speed", 12.0)), 1),
                        "votes": int(r.get("lobby_votes", 0)),
                        "status": {
                            "turbo": bool(r.get("is_boosted", False)),
                            "shield": bool(r.get("has_shield", False)),
                            "stumble": bool(r.get("is_stumbled", False)),
                        },
                    }
                )
        else:
            candidates = self._get_fallback_candidates()

        c1 = next((c for c in candidates if c["slot"] == 1), None)
        c2 = next((c for c in candidates if c["slot"] == 2), None)
        advantage_leader = "Empate"
        advantage_meters = 0.0
        if c1 and c2:
            d1 = float(c1["distance_meters"])
            d2 = float(c2["distance_meters"])
            diff = round(d1 - d2, 1)
            if diff > 0.5:
                advantage_leader = "Lula"
                advantage_meters = diff
            elif diff < -0.5:
                advantage_leader = "Flávio Bolsonaro"
                advantage_meters = abs(diff)

        state_name = str(raw.get("state_name", "LOBBY_VOTACAO"))
        elapsed = round(float(raw.get("race_elapsed_time", 0.0)), 1)
        phase_timer = round(float(raw.get("match_timer_remaining", raw.get("state_timer", raw.get("phase_timer_seconds", 300.0)))), 1)
        goal = dict(self.live_goal.value)
        reported_goal = raw.get("live_goal", {})
        goal_applied = False
        if isinstance(reported_goal, dict) and reported_goal:
            if not self.live_goal.configured or all(reported_goal.get(key) == value for key, value in goal.items()):
                goal.update(reported_goal)
                goal_applied = True
        reported_audio = raw.get("audio", {})
        audio_applied = (isinstance(reported_audio, dict)
                         and all(isinstance(reported_audio.get(key), bool) for key in AUDIO_KEYS)
                         and (not self.audio_settings.configured or all(reported_audio[key] == self.audio_settings.value[key] for key in AUDIO_KEYS)))

        return {
            "status": "ok",
            "platform": self.platform,
            "account": self.account,
            **self.platform_listener_state(),
            "telemetry_fresh": telemetry_fresh,
            "telemetry_age_seconds": round(telemetry_age, 2) if telemetry_age is not None else None,
            "gift_delivery": "at_least_once_ack",
            "dispatch_online": bool(self._dispatch_task and not self._dispatch_task.done()),
            "pending_gifts": self.outbox.pending_count(),
            "queue_sizes": {"p0_admin": self.p0_queue.qsize(), "p1": self.p1_queue.qsize(), "p2": self.p2_queue.qsize()},
            "live_goal": goal,
            "live_goal_applied": goal_applied,
            "audience": raw.get("audience", {}),
            "audio": raw.get("audio", {}),
            "audio_settings_applied": audio_applied,
            "audio_settings_requested": dict(self.audio_settings.value) if self.audio_settings.configured else None,
            "gift_catalog_count": self.gift_catalog.listing(limit=1)["total"],
            "timestamp_ms": int(time.time() * 1000),
            "race_state": state_name,
            "phase_timer_seconds": phase_timer,
            "race_timer_seconds": elapsed,
            "advantage_leader": advantage_leader,
            "advantage_meters": advantage_meters,
            "backend_online": True,
            "godot_connected": len(self.godot_clients) > 0,
            "godot_client_count": len(self.godot_clients),
            "metrics": dict(self.metrics),
            "candidates": candidates,
            "performance": raw.get("performance", {}) if isinstance(raw.get("performance"), dict) else {},
            "telemetry": raw,
        }

    def _process_http_or_ws_request(self, connection: Any, request: Any) -> Response | None:
        """
        Intercepta requisições HTTP na mesma porta 8765 do WebSocket:
        - Valida Host e Origin (proteção Zero-Trust contra CSRF e CSWSH)
        - Serve /admin (HTML, CSS, JS) e REST endpoints
        - Retorna None para rotas /ws/* para permitir o upgrade do WebSocket
        """
        # 1. Validação estrita de Host
        host_hdr = str(request.headers.get("Host", "")).split(":")[0].strip().lower()
        if host_hdr and host_hdr not in ALLOWED_LOOPBACK_HOSTS:
            logger.warning("Bloqueio de segurança: Host inválido %r", host_hdr)
            return Response(
                403,
                "Forbidden",
                Headers([("Content-Type", "text/plain; charset=utf-8"), ("Connection", "close")]),
                b"Forbidden: Host must be loopback (127.0.0.1)",
            )

        # 2. Validação estrita de Origin (anti-CSWSH / anti-CSRF)
        origin_hdr = request.headers.get("Origin")
        sec_fetch_site = str(request.headers.get("Sec-Fetch-Site", "")).strip().lower()
        if not is_allowed_origin(origin_hdr, self.bound_port) or sec_fetch_site == "cross-site":
            logger.warning("Bloqueio de segurança: Origin/site não autorizado.")
            return Response(
                403, "Forbidden",
                Headers([("Content-Type", "text/plain; charset=utf-8"), ("Connection", "close")]),
                b"Forbidden: Cross-Origin request not permitted",
            )

        cors_headers = [
            ("Access-Control-Allow-Origin", origin_hdr or f"http://127.0.0.1:{self.bound_port}"),
            ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type, Authorization"),
        ]

        if request.method == "OPTIONS":
            return Response(204, "No Content", Headers(cors_headers), b"")

        raw_path = request.path or "/admin"
        path_only = raw_path.split("?", 1)[0]
        query_str = raw_path.split("?", 1)[1] if "?" in raw_path else ""
        query_params = urllib.parse.parse_qs(query_str)
        if path_only.startswith("/gift-icons/"):
            icon = self.gift_images.get(path_only)
            if icon is None:
                return Response(404, "Not Found", Headers(cors_headers + [("Cache-Control", "no-store")]), b"")
            content, content_type = icon
            return Response(200, "OK", Headers(cors_headers + [("Content-Type", content_type),
                ("Content-Length", str(len(content))), ("X-Content-Type-Options", "nosniff"),
                ("Cache-Control", "private, max-age=86400")]), content)
        if path_only == "/favicon.ico":
            return Response(204, "No Content", Headers(cors_headers), b"")

        # Rotas WebSocket: passam adiante para o handshake
        if path_only.startswith("/ws/") or path_only in ("/ws/godot", "/ws/admin", "/ws/ingest"):
            return None

        # Rota de raiz: redireciona / atende /admin
        if path_only in ("/", "/admin", "/admin/", "/admin/index.html"):
            index_file = self._admin_dir / "index.html"
            if not index_file.exists():
                return Response(
                    404,
                    "Not Found",
                    Headers(cors_headers + [("Content-Type", "text/plain; charset=utf-8")]),
                    b"Arquivo admin/index.html nao encontrado.",
                )
            content = index_file.read_bytes()
            headers = Headers(
                cors_headers
                + [
                    ("Content-Type", "text/html; charset=utf-8"),
                    ("Content-Length", str(len(content))),
                    ("Cache-Control", "no-cache"),
                    ("X-Frame-Options", "DENY"),
                    (
                        "Content-Security-Policy",
                        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws://127.0.0.1:* ws://localhost:*; frame-ancestors 'none'",
                    ),
                ]
            )
            return Response(200, "OK", headers, content)

        if path_only == "/admin/styles.css":
            css_file = self._admin_dir / "styles.css"
            if not css_file.exists():
                return Response(
                    404,
                    "Not Found",
                    Headers(cors_headers + [("Content-Type", "text/plain; charset=utf-8")]),
                    b"Arquivo admin/styles.css nao encontrado.",
                )
            content = css_file.read_bytes()
            headers = Headers(
                cors_headers
                + [
                    ("Content-Type", "text/css; charset=utf-8"),
                    ("Content-Length", str(len(content))),
                ]
            )
            return Response(200, "OK", headers, content)

        if path_only == "/admin/app.js":
            js_file = self._admin_dir / "app.js"
            if not js_file.exists():
                return Response(
                    404,
                    "Not Found",
                    Headers(cors_headers + [("Content-Type", "text/plain; charset=utf-8")]),
                    b"Arquivo admin/app.js nao encontrado.",
                )
            content = js_file.read_bytes()
            headers = Headers(
                cors_headers
                + [
                    ("Content-Type", "application/javascript; charset=utf-8"),
                    ("Content-Length", str(len(content))),
                ]
            )
            return Response(200, "OK", headers, content)

        if path_only == "/health":
            health_data = {
                "status": "ok",
                "bound_host": self.host,
                "bound_port": self.bound_port,
                "godot_connected": len(self.godot_clients) > 0,
                "admin_clients": len(self.admin_clients),
                "ingest_clients": len(self.ingest_clients),
                "platform": self.platform,
                "account": self.account,
                "pending_gifts": self.outbox.pending_count(),
                "gift_delivery": "at_least_once_ack",
                "dispatch_online": bool(self._dispatch_task and not self._dispatch_task.done()),
                **self.platform_listener_state(),
            }
            body = json.dumps(health_data).encode("utf-8")
            headers = Headers(
                cors_headers
                + [
                    ("Content-Type", "application/json; charset=utf-8"),
                    ("Content-Length", str(len(body))),
                ]
            )
            return Response(200, "OK", headers, body)

        if path_only == "/api/state":
            state_data = self._build_admin_state_payload()
            body = json.dumps(state_data, ensure_ascii=False).encode("utf-8")
            headers = Headers(
                cors_headers
                + [
                    ("Content-Type", "application/json; charset=utf-8"),
                    ("Content-Length", str(len(body))),
                ]
            )
            return Response(200, "OK", headers, body)

        if path_only in ("/api/kwai-collector", "/api/admin/kwai-collector"):
            status_code = 200
            try:
                raw_query_params = urllib.parse.parse_qs(query_str, keep_blank_values=True)
                if path_only == "/api/admin/kwai-collector" and "live_url" in raw_query_params:
                    self.kwai_collector.update(raw_query_params.get("live_url", [""])[0])
                result = {
                    "status": "ok",
                    "platform": self.platform,
                    "account": self.account,
                    **self.platform_listener_state(),
                }
            except (ValueError, OSError) as exc:
                status_code = 400
                result = {"status": "error", "message": str(exc)}
            body = json.dumps(result, ensure_ascii=False).encode("utf-8")
            return Response(
                status_code,
                "OK" if status_code == 200 else "Bad Request",
                Headers(cors_headers + [("Content-Type", "application/json; charset=utf-8"), ("Cache-Control", "no-store")]),
                body,
            )

        if path_only in ("/api/gifts", "/api/admin/gift"):
            status_code = 200
            try:
                if path_only == "/api/admin/gift":
                    self.gift_catalog.set_action(query_params.get("source", [self.platform])[0],
                        query_params.get("gift_id", [""])[0], query_params.get("action", [""])[0])
                result = {"status":"ok", "platform":self.platform,
                    **self.gift_catalog.listing(int(query_params.get("limit", [200])[0]), int(query_params.get("offset", [0])[0]))}
            except (ValueError, TypeError):
                status_code = 400; result = {"status":"error","message":"Parâmetros do catálogo inválidos."}
            except LookupError:
                status_code = 404; result = {"status":"error","message":"Presente ainda não observado nesta fonte."}
            body = json.dumps(result, ensure_ascii=False).encode("utf-8")
            return Response(status_code, "OK" if status_code == 200 else "Bad Request", Headers(cors_headers + [("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")]), body)

        if path_only == "/api/admin/command":
            cmd = (
                query_params.get("command", [None])[0]
                or query_params.get("cmd", [None])[0]
                or ""
            ).strip()
            slot_val = query_params.get(
                "candidate_slot", [query_params.get("slot", [None])[0]]
            )[0]
            slot = int(slot_val) if slot_val and slot_val.isdigit() else None
            if cmd == "candidate_turbo":
                cmd = "boost"
            elif cmd == "candidate_shield":
                cmd = "shield"

            if not cmd or cmd not in VALID_ADMIN_COMMANDS:
                err_body = json.dumps(
                    {"status": "error", "message": f"Comando administrativo invalido: {cmd!r}"}
                ).encode("utf-8")
                return Response(
                    400,
                    "Bad Request",
                    Headers(
                        cors_headers
                        + [
                            ("Content-Type", "application/json; charset=utf-8"),
                            ("Content-Length", str(len(err_body))),
                        ]
                    ),
                    err_body,
                )

            goal_options = {}
            if cmd == "set_live_goal":
                try:
                    goal_options = {"goal_kind": query_params.get("goal_kind", ["likes"])[0],
                                    "goal_target": int(query_params.get("goal_target", [0])[0]),
                                    "goal_label": query_params.get("goal_label", ["Meta da live"])[0],
                                    "goal_gift_id": query_params.get("goal_gift_id", [None])[0]}
                    env = build_admin_command_envelope(command=cmd, **goal_options)
                except (ProtocolValidationError, ValueError, TypeError):
                    body = b'{"status":"error","message":"Meta invalida."}'
                    return Response(400, "Bad Request", Headers(cors_headers + [("Content-Type", "application/json")]), body)
            elif cmd == "set_audio_settings":
                try:
                    options = {key: {"true": True, "false": False}[query_params.get(key, [""])[0]] for key in AUDIO_KEYS}
                    env = build_admin_command_envelope(command=cmd, **options)
                except (KeyError, ProtocolValidationError, ValueError, TypeError):
                    return Response(400, "Bad Request", Headers(cors_headers + [("Content-Type", "application/json")]), b'{"status":"error","message":"Audio switches require true/false."}')
            else:
                env = build_admin_command_envelope(command=cmd, candidate_slot=slot)
            outcome = self.enqueue_envelope(env)
            ok_body = json.dumps(
                {
                    "status": "ok" if outcome in ("accepted", "duplicate") else outcome,
                    "command": cmd,
                    "event_id": env["event_id"],
                    "message": "Comando enfileirado." if outcome == "accepted" else f"Resultado do envio: {outcome}.",
                }
            ).encode("utf-8")
            return Response(
                200,
                "OK",
                Headers(
                    cors_headers
                    + [
                        ("Content-Type", "application/json; charset=utf-8"),
                        ("Content-Length", str(len(ok_body))),
                    ]
                ),
                ok_body,
            )

        if path_only == "/api/admin/simulate":
            evt_type = (
                query_params.get("event_type", [query_params.get("type", [None])[0]])[0]
                or "vote"
            ).strip()
            slot_val = query_params.get("candidate_slot", [query_params.get("slot", [1])[0]])[0]
            if isinstance(slot_val, str):
                s_str = slot_val.strip().lower()
                if s_str in ("lula", "1", "#1"):
                    slot = 1
                elif s_str in ("bolsonaro", "2", "#2"):
                    slot = 2
                elif s_str.isdigit():
                    slot = 2 if int(s_str) == 2 else 1
                else:
                    slot = 1
            else:
                slot = 1

            count_val = query_params.get("count", [1])[0]
            count = int(count_val) if count_val and str(count_val).isdigit() else 1
            outcome = "accepted"

            if evt_type == "burst":
                burst_count = max(1, min(count, 40))
                for i in range(burst_count):
                    s = (i % 2) + 1
                    env = build_vote_envelope(
                        user_id=f"sim_burst_{i}",
                        display_name=f"Torcedor {'Lula' if s == 1 else 'Flávio'}",
                        candidate_slot=s,
                        source="simulator",
                    )
                    self.enqueue_envelope(env)
                res_body = json.dumps(
                    {"status": "accepted", "event_type": "burst", "count": burst_count}
                ).encode("utf-8")
            elif evt_type in ("like", "like_batch"):
                env = build_like_batch_envelope(
                    user_id="sim_liker",
                    display_name="Torcedor",
                    candidate_slot=slot,
                    like_count=max(1, count),
                    source="simulator",
                )
                self.enqueue_envelope(env)
                res_body = json.dumps({"status": "accepted", "event_id": env["event_id"]}).encode(
                    "utf-8"
                )
            elif evt_type in ("attack", "attack_obstacle"):
                target_slot = 2 if slot == 1 else 1
                obs_type = query_params.get("obstacle_type", ["pilha_documentos"])[0]
                env = build_attack_envelope(
                    user_id="sim_attacker",
                    display_name="Torcedor",
                    candidate_slot=slot,
                    target_slot=target_slot,
                    obstacle_type=obs_type,
                    source="simulator",
                )
                outcome = self.enqueue_envelope(env)
                res_body = json.dumps(
                    {"status": outcome, "event_id": env["event_id"], "target_slot": target_slot}
                ).encode("utf-8")
            elif evt_type == "gift":
                unit_value = bounded_int(query_params["unit_coin_value"][0]) if "unit_coin_value" in query_params else None
                tier = (query_params.get("gift_tier", [None])[0] or gift_tier_for_unit_coins(unit_value or 0)).upper()
                env = build_gift_envelope(
                    user_id="sim_gifter",
                    display_name="Torcedor",
                    candidate_slot=slot,
                    gift_tier=tier,
                    unit_coin_value=unit_value,
                    repeat_count=max(1, min(count, 1000)),
                    gift_id=query_params.get("gift_id", [f"sim_{tier}_{unit_value or 0}"])[0],
                    source="simulator",
                )
                outcome = self.enqueue_envelope(env)
                res_body = json.dumps({"status": outcome, "event_id": env["event_id"]}).encode(
                    "utf-8"
                )
            elif evt_type == "share":
                env = build_share_envelope(
                    user_id="sim_sharer",
                    display_name="Torcedor",
                    candidate_slot=slot,
                    source="simulator",
                )
                self.enqueue_envelope(env)
                res_body = json.dumps({"status": "accepted", "event_id": env["event_id"]}).encode(
                    "utf-8"
                )
            elif evt_type == "follow":
                env = build_follow_envelope(user_id=f"sim_follow_{self._seq}", display_name="Novo seguidor",
                    candidate_slot=slot, source="simulator", sequence=self._seq)
                self._seq += 1
                outcome = self.enqueue_envelope(env)
                res_body = json.dumps({"status": outcome, "event_id": env["event_id"]}).encode("utf-8")
            else:
                env = build_vote_envelope(
                    user_id="sim_voter",
                    display_name="Torcedor",
                    candidate_slot=slot,
                    repeat_count=max(1, count),
                    source="simulator",
                )
                self.enqueue_envelope(env)
                res_body = json.dumps({"status": "accepted", "event_id": env["event_id"]}).encode(
                    "utf-8"
                )

            return Response(
                200,
                "OK",
                Headers(
                    cors_headers
                    + [
                        ("Content-Type", "application/json; charset=utf-8"),
                        ("Content-Length", str(len(res_body))),
                    ]
                ),
                res_body,
            )

        # Rota HTTP desconhecida
        not_found_body = b"Not Found"
        return Response(
            404,
            "Not Found",
            Headers(
                cors_headers
                + [
                    ("Content-Type", "text/plain; charset=utf-8"),
                    ("Content-Length", str(len(not_found_body))),
                ]
            ),
            not_found_body,
        )

    def normalize_incoming_payload(self, raw_data: dict[str, Any]) -> dict[str, Any]:
        """
        Aceita tanto um LiveEventEnvelope completo quanto atalhos brutos de eventos
        e retorna sempre um LiveEventEnvelope validado e sanitizado.
        """
        if "schema_version" in raw_data and "event_type" in raw_data and "payload" in raw_data:
            env = validate_envelope(raw_data, sanitize=True)
            if env["event_type"] == "vote":
                viewers = self._ingest_viewers.get(env["source"])
                if viewers:
                    viewers.choose(env["user"]["user_id"], env["payload"]["candidate_slot"])
                    allowed = viewers.allow_vote_boost(env["user"]["user_id"])
                    env["payload"]["boost_amount"] = min(1.1, env["payload"].get("boost_amount", 1.1)) if allowed else 0.0
                    env["payload"]["boost_duration"] = 1.0
            return env

        self._seq += 1
        shorthand_type = str(raw_data.get("type") or raw_data.get("event_type") or "").lower()
        source = str(raw_data.get("source") or "simulator").lower()
        user_id = str(raw_data.get("user_id") or "anon_user")
        display_name = str(raw_data.get("display_name") or raw_data.get("username") or "Espectador")
        viewers = self._ingest_viewers.get(source)
        raw_slot = raw_data.get("candidate_slot")
        selected_slot = int(raw_slot) if isinstance(raw_slot, int) and not isinstance(raw_slot, bool) else None
        if selected_slot is None and viewers:
            selected_slot = viewers.team(user_id)
        event_id = raw_data.get("event_id")
        ts = raw_data.get("timestamp_ms")
        timestamp_ms = (
            int(ts)
            if isinstance(ts, int) and not isinstance(ts, bool)
            else int(time.time() * 1000)
        )

        if shorthand_type in ("comment", "vote"):
            slot = raw_data.get("candidate_slot")
            if slot is None and "comment" in raw_data:
                slot = parse_vote_slot_from_comment(raw_data.get("comment"))
            if slot is None:
                raise ProtocolValidationError("Comentario nao contem torcida valida (13/22 ou #1/#2).")
            if viewers and user_id != "anon_user" and int(slot) in (1, 2):
                viewers.choose(user_id, int(slot))
            return build_vote_envelope(
                user_id=user_id,
                display_name=display_name,
                candidate_slot=int(slot),
                source=source,
                repeat_count=int(raw_data.get("repeat_count", 1)),
                timestamp_ms=timestamp_ms,
                event_id=event_id,
                sequence=self._seq,
                boost_allowed=viewers.allow_vote_boost(user_id) if viewers else True,
            )

        if shorthand_type in ("like", "like_batch"):
            return build_like_batch_envelope(
                user_id=user_id,
                display_name=display_name,
                like_count=int(raw_data.get("like_count", 10)),
                candidate_slot=selected_slot,
                source=source,
                timestamp_ms=timestamp_ms,
                event_id=event_id,
                sequence=self._seq,
            )

        if shorthand_type == "share":
            return build_share_envelope(
                user_id=user_id,
                display_name=display_name,
                candidate_slot=selected_slot,
                source=source,
                timestamp_ms=timestamp_ms,
                event_id=event_id,
                sequence=self._seq,
            )

        if shorthand_type == "gift":
            real_unit_coins = bounded_int(raw_data.get("unit_coin_value", raw_data.get("coin_value")), 0)
            return build_gift_envelope(
                user_id=user_id,
                display_name=display_name,
                candidate_slot=selected_slot,
                gift_tier=str(raw_data.get("gift_tier") or gift_tier_for_unit_coins(real_unit_coins)),
                repeat_count=int(raw_data.get("repeat_count", 1)),
                source=source,
                timestamp_ms=timestamp_ms,
                event_id=event_id,
                sequence=self._seq,
                unit_coin_value=(bounded_int(raw_data.get("unit_coin_value", raw_data.get("coin_value")), 0)
                                 if source in ("tiktok", "kwai") or "unit_coin_value" in raw_data or "coin_value" in raw_data else None),
                gift_name=raw_data.get("gift_name"),
                gift_id=str(raw_data["gift_id"]) if raw_data.get("gift_id") is not None else None,
                gift_image_url=raw_data.get("gift_image_url"),
            )

        if shorthand_type == "follow":
            return build_follow_envelope(user_id=user_id, display_name=display_name,
                candidate_slot=selected_slot, source=source, timestamp_ms=timestamp_ms,
                event_id=event_id, sequence=self._seq)

        raise ProtocolValidationError(
            "Formato de mensagem desconhecido ou campos obrigatorios ausentes."
        )

    def enqueue_envelope(self, envelope: dict[str, Any]) -> str:
        """
        Submete um envelope validado ao deduplicador LRU e às filas P0/P1/P2.
        Retorna 'accepted', 'duplicate' ou 'shed'.
        """
        event_id: str = envelope["event_id"]
        if self.platform != "local" and envelope["source"] not in (self.platform, "admin", "simulator"):
            self.metrics["platform_rejected"] += 1
            return "rejected_platform"
        if envelope["event_type"] == "gift":
            try:
                envelope = self.gift_catalog.apply(envelope)
                # Scheduling optional artwork never blocks the durable gift route.
                icon_path = self.gift_images.request(envelope["payload"].get("gift_image_url"))
                if icon_path:
                    envelope = {**envelope, "payload": {**envelope["payload"], "gift_icon_path": icon_path}}
                outcome = self.outbox.accept(envelope)
            except sqlite3.Error:
                self.metrics["storage_errors"] += 1
                logger.error("Outbox indisponível; presente não aceito. Produtor deve repetir o mesmo event_id.")
                return "busy"
            if outcome == "duplicate":
                self.metrics["duplicates_dropped"] += 1
            elif outcome == "busy":
                self.metrics["gift_busy_rejected"] += 1
            else:
                try:
                    self.gift_catalog.observe(envelope)
                except sqlite3.Error:
                    self.metrics["storage_errors"] += 1
                    logger.error("Presente durável aceito; metadados do catálogo não puderam ser atualizados.")
                self.metrics["accepted_total"] += 1
                self._queue_notify.set()
            return outcome
        if envelope["priority"] == "P0" and self.p0_queue.full():
            return "busy"
        if self.deduplicator.is_duplicate(event_id):
            self.metrics["duplicates_dropped"] += 1
            return "duplicate"

        if envelope["event_type"] == "admin_command" and envelope["payload"].get("command") == "set_live_goal":
            try:
                self.live_goal.update(envelope)
            except OSError:
                self.metrics["storage_errors"] += 1
                self.deduplicator.forget(event_id)
                return "busy"
        if envelope["event_type"] == "admin_command" and envelope["payload"].get("command") == "set_audio_settings":
            try:
                self.audio_settings.update(envelope)
            except OSError:
                self.metrics["storage_errors"] += 1
                self.deduplicator.forget(event_id)
                return "busy"

        priority: str = envelope["priority"]
        if priority == "P0":
            if self.p0_queue.full():
                return "busy"
            self.p0_queue.put_nowait(envelope)
        elif priority == "P1":
            if self.p1_queue.full():
                try:
                    self.p1_queue.get_nowait()
                    self.metrics["p1_shed_dropped"] += 1
                except asyncio.QueueEmpty:
                    pass
            self.p1_queue.put_nowait(envelope)
        else:
            if self.p2_queue.full():
                try:
                    self.p2_queue.get_nowait()
                    self.metrics["p2_shed_dropped"] += 1
                except asyncio.QueueEmpty:
                    pass
            self.p2_queue.put_nowait(envelope)

        self.metrics["accepted_total"] += 1
        self._queue_notify.set()
        return "accepted"

    def ingest_raw_json(self, raw_text: str) -> dict[str, Any]:
        """Processa uma mensagem JSON recebida na rota de ingestão e retorna o recibo."""
        self.metrics["received_total"] += 1
        if len(raw_text.encode("utf-8", errors="replace")) > MAX_PACKET_BYTES:
            self.metrics["invalid_rejected"] += 1
            return {
                "status": "error",
                "code": "OVERSIZED_PACKET",
                "message": "Pacote excede 8192 bytes.",
            }
        try:
            parsed = json.loads(raw_text)
        except json.JSONDecodeError as exc:
            self.metrics["invalid_rejected"] += 1
            return {"status": "error", "code": "INVALID_JSON", "message": str(exc)}

        if not isinstance(parsed, dict):
            self.metrics["invalid_rejected"] += 1
            return {"status": "error", "code": "INVALID_TYPE", "message": "Esperado objeto JSON."}

        if parsed.get("type") == "ping":
            return {"status": "pong", "metrics": dict(self.metrics)}

        try:
            envelope = self.normalize_incoming_payload(parsed)
        except (ProtocolValidationError, KeyError, TypeError, ValueError) as exc:
            self.metrics["invalid_rejected"] += 1
            return {"status": "error", "code": "VALIDATION_ERROR", "message": str(exc)}

        outcome = self.enqueue_envelope(envelope)
        return {
            "status": outcome,
            "event_id": envelope["event_id"],
            "priority": envelope["priority"],
            "sanitized_display_name": envelope["user"]["display_name"],
        }

    async def _handle_client(self, ws: Any, *args: Any) -> None:
        path: str = _extract_ws_path(ws, *args)
        if path.startswith("/ws/admin"):
            await self._handle_admin_client(ws)
        elif path.startswith("/ws/ingest"):
            await self._handle_ingest_client(ws)
        elif path in ("/ws/godot", "/"):
            await self._handle_godot_client(ws)
        else:
            await ws.close(code=1008, reason=f"Rota desconhecida: {path}")

    async def broadcast_to_admin(self, data: dict[str, Any]) -> None:
        """Transmite dados para todos os clientes conectados em /ws/admin."""
        if not self.admin_clients:
            return
        serialized: str = json.dumps(data, ensure_ascii=False)
        dead: list[Any] = []
        for client in list(self.admin_clients):
            try:
                await asyncio.wait_for(client.send(serialized), timeout=1.0)
            except Exception:
                dead.append(client)
        for d in dead:
            self.admin_clients.discard(d)

    async def _handle_admin_client(self, ws: Any) -> None:
        """Gerencia conexão do painel web de controle em /ws/admin."""
        self.admin_clients.add(ws)
        logger.info("Cliente Admin conectado (%d ativos)", len(self.admin_clients))
        try:
            # Envia estado inicial imediatamente
            welcome_state = {"type": "state_update", **self._build_admin_state_payload()}
            await ws.send(json.dumps(welcome_state, ensure_ascii=False))

            async for raw_message in ws:
                if isinstance(raw_message, bytes):
                    raw_message = raw_message.decode("utf-8", errors="replace")
                try:
                    data = json.loads(raw_message)
                except json.JSONDecodeError:
                    await ws.send(
                        json.dumps({"type": "command_ack", "status": "error", "message": "JSON invalido"})
                    )
                    continue

                if not isinstance(data, dict):
                    continue

                msg_type = str(data.get("type", "")).strip()

                if msg_type == "ping":
                    pong_res = {
                        "type": "pong",
                        "timestamp_ms": int(time.time() * 1000),
                        "metrics": dict(self.metrics),
                    }
                    await ws.send(json.dumps(pong_res, ensure_ascii=False))

                elif msg_type == "get_state":
                    st = {"type": "state_update", **self._build_admin_state_payload()}
                    await ws.send(json.dumps(st, ensure_ascii=False))

                elif msg_type == "admin_command":
                    cmd = str(data.get("command", "")).strip()
                    params = data.get("params", {})
                    if not isinstance(params, dict):
                        await ws.send(json.dumps({"type": "command_ack", "status": "error", "message": "Parâmetros do comando devem ser objeto."}))
                        continue
                    slot = params.get("candidate_slot") if isinstance(params, dict) else None
                    if slot is not None:
                        try:
                            slot = int(slot)
                        except (ValueError, TypeError):
                            slot = None
                    if cmd == "candidate_turbo":
                        cmd = "boost"
                    elif cmd == "candidate_shield":
                        cmd = "shield"

                    if cmd in VALID_ADMIN_COMMANDS:
                        try:
                            goal_options = {}
                            if cmd == "set_live_goal":
                                goal_options = {key: params.get(key) for key in ("goal_kind", "goal_target", "goal_label", "goal_gift_id")}
                            elif cmd == "set_audio_settings":
                                goal_options = {key: params.get(key) for key in AUDIO_KEYS}
                            env = build_admin_command_envelope(command=cmd, candidate_slot=slot, **goal_options)
                        except (ProtocolValidationError, TypeError, ValueError):
                            await ws.send(json.dumps({"type": "command_ack", "status": "error", "message": "Parâmetros do comando inválidos."}))
                            continue
                        outcome = self.enqueue_envelope(env)
                        ack = {
                            "type": "command_ack",
                            "command": cmd,
                            "status": "ok" if outcome in ("accepted", "duplicate") else outcome,
                            "message": f"Comando '{cmd}': {outcome}.",
                        }
                        await ws.send(json.dumps(ack, ensure_ascii=False))
                        await self.broadcast_to_admin(
                            {
                                "type": "telemetry_event",
                                "source": "admin",
                                "action": f"Comando Admin: {cmd}",
                                "timestamp_ms": int(time.time() * 1000),
                            }
                        )
                        if cmd == "set_live_goal":
                            await self.broadcast_to_admin({"type": "state_update", **self._build_admin_state_payload()})
                    else:
                        ack = {
                            "type": "command_ack",
                            "command": cmd,
                            "status": "error",
                            "message": f"Comando desconhecido: '{cmd}'",
                        }
                        await ws.send(json.dumps(ack, ensure_ascii=False))

                elif msg_type == "candidate_action":
                    action = str(data.get("action", "")).strip().lower()
                    slot = int(data.get("candidate_slot", 1))
                    if action in ("turbo", "boost"):
                        cmd = "boost"
                    elif action == "shield":
                        cmd = "shield"
                    elif action in ("attack", "obstacle", "papelada"):
                        cmd = "attack"
                    else:
                        cmd = "boost"
                    env = build_admin_command_envelope(command=cmd, candidate_slot=slot)
                    outcome = self.enqueue_envelope(env)
                    ack = {
                        "type": "command_ack",
                        "command": cmd,
                        "status": "ok" if outcome in ("accepted", "duplicate") else outcome,
                        "message": f"Ação '{action}' para {'Lula' if slot == 1 else 'Flávio'}: {outcome}.",
                    }
                    await ws.send(json.dumps(ack, ensure_ascii=False))

                elif msg_type == "simulate_event":
                    outcome = "accepted"
                    evt_type = str(data.get("event_type", "vote")).strip().lower()
                    evt_data = data.get("data", {}) if isinstance(data.get("data"), dict) else {}
                    slot = int(evt_data.get("candidate_slot", 1))
                    slot = 2 if slot == 2 else 1
                    count = int(evt_data.get("count", 1))

                    if evt_type == "burst":
                        for i in range(min(count, 40)):
                            s = (i % 2) + 1
                            env = build_vote_envelope(
                                user_id=f"sim_burst_{i}",
                                display_name=f"Torcedor {'Lula' if s == 1 else 'Flávio'}",
                                candidate_slot=s,
                                source="simulator",
                            )
                            self.enqueue_envelope(env)
                    elif evt_type in ("like", "like_batch"):
                        env = build_like_batch_envelope(
                            user_id=str(evt_data.get("user_id", "sim_user")),
                            display_name=str(evt_data.get("display_name", "Torcedor")),
                            candidate_slot=slot,
                            like_count=count,
                            source="simulator",
                        )
                        self.enqueue_envelope(env)
                    elif evt_type in ("attack", "attack_obstacle"):
                        target_slot = 2 if slot == 1 else 1
                        obs_type = str(evt_data.get("obstacle_type", "pilha_documentos"))
                        env = build_attack_envelope(
                            user_id=str(evt_data.get("user_id", "sim_attacker")),
                            display_name=str(evt_data.get("display_name", "Torcedor")),
                            candidate_slot=slot,
                            target_slot=target_slot,
                            obstacle_type=obs_type,
                            source="simulator",
                        )
                        outcome = self.enqueue_envelope(env)
                    elif evt_type == "gift":
                        unit_value = bounded_int(evt_data.get("unit_coin_value")) if "unit_coin_value" in evt_data else None
                        tier = str(evt_data.get("gift_tier") or gift_tier_for_unit_coins(unit_value or 0)).upper()
                        env = build_gift_envelope(
                            user_id=str(evt_data.get("user_id", "sim_user")),
                            display_name=str(evt_data.get("display_name", "Torcedor")),
                            candidate_slot=slot,
                            gift_tier=tier,
                            source="simulator",
                            unit_coin_value=unit_value,
                            repeat_count=max(1, min(count, 1000)),
                            gift_id=str(evt_data.get("gift_id") or f"sim_{tier}_{unit_value or 0}"),
                        )
                        outcome = self.enqueue_envelope(env)
                    elif evt_type == "share":
                        env = build_share_envelope(
                            user_id=str(evt_data.get("user_id", "sim_user")),
                            display_name=str(evt_data.get("display_name", "Torcedor")),
                            candidate_slot=slot,
                            source="simulator",
                        )
                        self.enqueue_envelope(env)
                    elif evt_type == "follow":
                        env = build_follow_envelope(user_id=str(evt_data.get("user_id", "sim_follow")),
                            display_name=str(evt_data.get("display_name", "Novo seguidor")),
                            candidate_slot=slot, source="simulator")
                        outcome = self.enqueue_envelope(env)
                    else:
                        env = build_vote_envelope(
                            user_id=str(evt_data.get("user_id", "sim_user")),
                            display_name=str(evt_data.get("display_name", "Torcedor")),
                            candidate_slot=slot,
                            repeat_count=count,
                            source="simulator",
                        )
                        self.enqueue_envelope(env)

                    ack = {
                        "type": "command_ack",
                        "status": "ok" if outcome in ("accepted", "duplicate") else outcome,
                        "message": f"Simulação de {evt_type}: {outcome}.",
                    }
                    await ws.send(json.dumps(ack, ensure_ascii=False))

        except websockets.ConnectionClosed:
            pass
        finally:
            self.admin_clients.discard(ws)
            logger.info("Cliente Admin desconectado (%d ativos)", len(self.admin_clients))

    async def _handle_godot_client(self, ws: Any) -> None:
        if self.godot_clients:
            await ws.close(code=1013, reason="Esta instância já tem um consumidor Godot; use outra porta/plataforma.")
            return
        self.godot_clients.add(ws)
        logger.info("Cliente Godot conectado (%d ativos)", len(self.godot_clients))
        try:
            welcome_envelope = {
                "schema_version": SCHEMA_VERSION,
                "event_id": f"evt_sys_welcome_{int(time.time() * 1000)}",
                "source": "admin",
                "event_type": "system_status",
                "timestamp_ms": int(time.time() * 1000),
                "priority": "P0",
                "user": {"user_id": "live_bridge", "display_name": "LiveBridge"},
                "payload": {
                    "action_id": "bridge_connected",
                    "status": "CONNECTED",
                },
            }
            await ws.send(json.dumps(welcome_envelope, ensure_ascii=False))
            if self.live_goal.configured:
                # Send only the latest saved setting. Old offline settings must not
                # overwrite it after reconnect; unrelated commands retain their order.
                retained = []
                while not self.p0_queue.empty():
                    pending = self.p0_queue.get_nowait()
                    if pending["payload"].get("command") != "set_live_goal":
                        retained.append(pending)
                for pending in retained:
                    self.p0_queue.put_nowait(pending)
                await ws.send(json.dumps(self.live_goal.envelope(), ensure_ascii=False))
            if self.audio_settings.configured:
                retained = []
                while not self.p0_queue.empty():
                    pending = self.p0_queue.get_nowait()
                    if pending["payload"].get("command") != "set_audio_settings":
                        retained.append(pending)
                for pending in retained:
                    self.p0_queue.put_nowait(pending)
                await ws.send(json.dumps(self.audio_settings.envelope(), ensure_ascii=False))
            self.outbox.make_due()
            self._godot_available.set()
            self._queue_notify.set()
            # Notifica os clientes admin sobre a conexao do Godot
            await self.broadcast_to_admin(
                {"type": "state_update", **self._build_admin_state_payload()}
            )

            async for raw_message in ws:
                if isinstance(raw_message, bytes):
                    raw_message = raw_message.decode("utf-8", errors="replace")

                # Verifica se é um frame de telemetria emitido pelo Godot
                try:
                    parsed = json.loads(raw_message)
                    if isinstance(parsed, dict) and parsed.get("type") == "event_ack":
                        event_id = parsed.get("event_id")
                        if isinstance(event_id, str) and len(event_id) <= 128:
                            if self.outbox.acknowledge(event_id):
                                self.metrics["gift_acks_total"] += 1
                            self._queue_notify.set()
                        continue
                    if isinstance(parsed, dict) and parsed.get("type") == "telemetry":
                        self.latest_telemetry = parsed
                        self._telemetry_received_at = time.monotonic()
                        st = {"type": "state_update", **self._build_admin_state_payload()}
                        await self.broadcast_to_admin(st)
                        continue
                except json.JSONDecodeError:
                    pass

                ack = self.ingest_raw_json(raw_message)
                if ack.get("status") == "pong":
                    await ws.send(json.dumps(ack, ensure_ascii=False))
        except websockets.ConnectionClosed:
            pass
        finally:
            self.godot_clients.discard(ws)
            if not self.godot_clients:
                self._godot_available.clear()
                self.latest_telemetry = {}
                self._telemetry_received_at = None
            logger.info("Cliente Godot desconectado (%d ativos)", len(self.godot_clients))
            await self.broadcast_to_admin(
                {"type": "state_update", **self._build_admin_state_payload()}
            )

    async def _handle_ingest_client(self, ws: Any) -> None:
        """
        Gerencia clientes externos de ingestão (simuladores ou scrapers de live).
        Regra Zero-Trust [ALTO-01]: Bloqueia qualquer tentativa de spoofing de source='admin'
        ou event_type='admin_command'. Clientes externos jamais podem se auto-autorizar.
        """
        self.ingest_clients.add(ws)
        try:
            async for raw_message in ws:
                if isinstance(raw_message, bytes):
                    raw_message = raw_message.decode("utf-8", errors="replace")

                # Auditoria de segurança pré-parse
                try:
                    probe = json.loads(raw_message)
                    if isinstance(probe, dict):
                        source_claim = str(probe.get("source", "")).lower()
                        type_claim = str(probe.get("event_type", probe.get("type", ""))).lower()
                        if source_claim == "admin" or type_claim == "admin_command":
                            self.metrics["invalid_rejected"] += 1
                            logger.warning(
                                "Tentativa de spoofing administrativo rejeitada em /ws/ingest.",
                            )
                            err_resp = {
                                "status": "error",
                                "code": "UNAUTHORIZED_SOURCE",
                                "message": "Clientes em /ws/ingest nao podem emitir source='admin'.",
                            }
                            await ws.send(json.dumps(err_resp, ensure_ascii=False))
                            continue
                except json.JSONDecodeError:
                    pass

                ack = self.ingest_raw_json(raw_message)
                await ws.send(json.dumps(ack, ensure_ascii=False))
        except websockets.ConnectionClosed:
            pass
        finally:
            self.ingest_clients.discard(ws)

    def _pop_next_priority_envelope(self) -> dict[str, Any] | None:
        if not self.p0_queue.empty():
            return self.p0_queue.get_nowait()
        gift = self.outbox.next_due()
        if gift is not None:
            return gift
        for q in (self.p1_queue, self.p2_queue):
            if not q.empty():
                try:
                    return q.get_nowait()
                except asyncio.QueueEmpty:
                    continue
        return None

    async def _dispatch_loop(self) -> None:
        """Despacha somente com consumidor; presentes permanecem no journal até ACK."""
        while self._running:
            if not self._godot_available.is_set():
                await self._godot_available.wait()
                continue
            try:
                envelope = self._pop_next_priority_envelope()
            except sqlite3.Error:
                self.metrics["storage_errors"] += 1
                logger.error("Falha ao ler outbox; despacho de presentes suspenso até o armazenamento recuperar.")
                await asyncio.sleep(1.0)
                continue
            if envelope is None:
                self._queue_notify.clear()
                try:
                    await asyncio.wait_for(self._queue_notify.wait(), timeout=min(self.ack_retry_seconds, 1.0))
                except asyncio.TimeoutError:
                    pass
                continue

            wait_time = self.token_bucket.time_until_available(1.0)
            if wait_time > 0.0:
                await asyncio.sleep(wait_time)
            self.token_bucket.consume(1.0)

            is_gift = envelope["event_type"] == "gift"
            if is_gift:
                try:
                    self.outbox.mark_attempt(envelope["event_id"], self.ack_retry_seconds)
                except sqlite3.Error:
                    self.metrics["storage_errors"] += 1
                    logger.error("Falha ao atualizar outbox; presente permanece pendente.")
                    await asyncio.sleep(1.0)
                    continue
            sent = await self._broadcast_to_godot(envelope)
            if not sent:
                if is_gift:
                    self.outbox.make_due(envelope["event_id"])
                else:
                    queue = {"P0": self.p0_queue, "P1": self.p1_queue, "P2": self.p2_queue}[envelope["priority"]]
                    if not queue.full():
                        queue.put_nowait(envelope)
                if not self.godot_clients:
                    self._godot_available.clear()

    async def _broadcast_to_godot(self, envelope: dict[str, Any]) -> bool:
        if not self.godot_clients:
            return False
        serialized: str = json.dumps(envelope, ensure_ascii=False)
        dead_clients: list[Any] = []
        delivered = False
        for client in list(self.godot_clients):
            try:
                await asyncio.wait_for(client.send(serialized), timeout=2.0)
                self.metrics["dispatched_to_godot"] += 1
                delivered = True
            except Exception:
                dead_clients.append(client)
        for dead in dead_clients:
            self.godot_clients.discard(dead)
        return delivered


async def run_server_forever(host: str = DEFAULT_HOST, port: int = DEFAULT_PORT, *,
                             platform: str = "local", account: str = "",
                             state_dir: pathlib.Path | None = None, listen_live: bool = False,
                             kwai_webhook_port: int = 8786) -> None:
    if state_dir is None:
        state_dir = pathlib.Path(os.environ.get("LOCALAPPDATA", str(pathlib.Path.home() / ".local"))) / "JOGI" / "live_bridge" / platform
    server = LiveBridgeServer(host=host, port=port, platform=platform, account=account,
                              outbox_path=state_dir / "gifts.sqlite3", kwai_webhook_port=kwai_webhook_port)
    await server.start()
    stop_event = asyncio.Event()
    try:
        if listen_live:
            await server.start_live_listener()
        await stop_event.wait()
    except asyncio.CancelledError:
        pass
    finally:
        await server.stop()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Servidor Unificado (HTTP + WebSocket) LiveBridge para Corrida dos Candidatos."
    )
    parser.add_argument(
        "--host",
        default=DEFAULT_HOST,
        help="Endereco de bind (restrito exclusivamente a 127.0.0.1).",
    )
    parser.add_argument(
        "--port", type=int, default=None, help="Porta TCP local (TikTok/local:8765; Kwai:8766)."
    )
    parser.add_argument("--platform", choices=("local", "tiktok", "kwai"), default="local")
    parser.add_argument("--account", default="", help="Identificador público da conta; não autentica nem abre live.")
    parser.add_argument("--state-dir", type=pathlib.Path, default=None,
                        help="Diretório local exclusivo da outbox; padrão LOCALAPPDATA/JOGI/live_bridge/<platform>.")
    parser.add_argument("--listen-live", action="store_true", help="Ativar escuta local da plataforma (TikTok Live SDK ou receptor Webhook Kwai); não inicia transmissão.")
    parser.add_argument("--kwai-webhook-port", type=int, default=8786, help="Porta TCP loopback do receptor KwaiLiveAdapter (padrão 8786).")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    port = args.port if args.port is not None else (8766 if args.platform == "kwai" else DEFAULT_PORT)
    try:
        asyncio.run(run_server_forever(host=args.host, port=port, platform=args.platform,
                                       account=args.account, state_dir=args.state_dir, listen_live=args.listen_live,
                                       kwai_webhook_port=args.kwai_webhook_port))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
