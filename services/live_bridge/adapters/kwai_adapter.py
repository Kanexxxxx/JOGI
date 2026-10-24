"""KwaiLiveAdapter — Adaptador passivo local (Webhook/Loopback) para transmissões do Kwai LIVE."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
import json
import logging
import time
import urllib.parse
from typing import Any

from .base import BaseLiveAdapter
from .normalization import ViewerContext, bounded_int
from gift_images import extract_gift_image

try:
    from protocol import (
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
        build_gift_envelope,
        build_follow_envelope,
        build_like_batch_envelope,
        build_share_envelope,
        build_vote_envelope,
        parse_vote_slot_from_comment,
        gift_tier_for_unit_coins,
    )


logger = logging.getLogger("live_bridge.adapters.kwai")

DEFAULT_KWAI_WEBHOOK_HOST: str = "127.0.0.1"
DEFAULT_KWAI_WEBHOOK_PORT: int = 8786
DEFAULT_KWAI_WEBHOOK_PATH: str = "/webhook/kwai"
MAX_WEBHOOK_BODY_BYTES: int = 65_536


@dataclass
class KwaiAdapterConfig:
    """
    Configurações do KwaiLiveAdapter.

    NOTA ARQUITETURAL:
    Nenhum coletor de eventos do Kwai Brasil está conectado/autorizado neste projeto.
    Por padrão, o adaptador é mantido DESATIVADO (`enabled=False`, status `DISABLED_NO_API`).
    Quando ativado, ele expõe um endpoint HTTP Webhook loopback local estrito (127.0.0.1)
    para ingestão passiva de eventos vindos de uma extensão de navegador de transmissão ou OCR local.
    """

    enabled: bool = False
    host: str = DEFAULT_KWAI_WEBHOOK_HOST
    port: int = DEFAULT_KWAI_WEBHOOK_PORT
    webhook_path: str = DEFAULT_KWAI_WEBHOOK_PATH
    default_candidate_slot: int | None = None


@dataclass
class KwaiLiveAdapter(BaseLiveAdapter):
    """
    Adaptador passivo para transmissões do Kwai LIVE.
    Recebe eventos de chat, curtidas, presentes e compartilhamentos através de um
    Webhook HTTP loopback local seguro (`http://127.0.0.1:8786/webhook/kwai`).
    """

    adapter_name: str = "kwai"
    config: KwaiAdapterConfig = field(default_factory=KwaiAdapterConfig)

    _server: asyncio.Server | None = field(default=None, init=False, repr=False)
    _viewers: ViewerContext = field(default_factory=ViewerContext, init=False, repr=False)

    def __post_init__(self) -> None:
        if not self.config.enabled:
            self._status = "DISABLED_NO_API"
            logger.info(
                "KwaiLiveAdapter: nenhum coletor de eventos Kwai Brasil está configurado. "
                "Operando em modo DESATIVADO seguro (status: DISABLED_NO_API). "
                "Para ingestão via webhook local, habilite config.enabled=True."
            )
        else:
            self._status = "configured"

    def is_connected(self) -> bool:
        """Retorna True quando o servidor webhook local estiver ativo e escutando."""
        return self._server is not None and self._server.is_serving() and self._status == "listening"

    async def ingest_raw_event(self, raw_data: dict[str, Any]) -> dict[str, Any] | None:
        """
        Normaliza e valida eventos brutos do Kwai recebidos via Webhook/Bridge,
        convertendo-os estritamente para o contrato LiveEventEnvelope v1.0.
        """
        if not isinstance(raw_data, dict):
            logger.warning("KwaiLiveAdapter: payload bruto inválido (esperado dict).")
            return None

        event_type = str(raw_data.get("type") or raw_data.get("event_type") or "").strip().lower()
        user_info = raw_data.get("user") if isinstance(raw_data.get("user"), dict) else {}
        user_id = str(raw_data.get("user_id") or user_info.get("id") or user_info.get("user_id") or "anon_kwai")[:128]
        display_name = str(
            raw_data.get("display_name")
            or raw_data.get("username")
            or user_info.get("name")
            or user_info.get("display_name")
            or "Espectador Kwai"
        )[:256]
        identity = self._viewers.identity(raw_data, "kwai", event_type)
        if identity is None:
            return None
        slot = self._viewers.team(user_id, self.config.default_candidate_slot)

        envelope: dict[str, Any] | None = None

        if event_type in ("comment", "chat", "vote"):
            comment_text = str(raw_data.get("content") or raw_data.get("comment") or raw_data.get("text") or "")
            slot = parse_vote_slot_from_comment(comment_text)
            if slot is not None and 1 <= slot <= 2:
                if user_id != "anon_kwai":
                    self._viewers.choose(user_id, slot)
                envelope = build_vote_envelope(
                    user_id=user_id,
                    display_name=display_name,
                    candidate_slot=slot,
                    source="kwai",
                    repeat_count=1,
                    boost_allowed=self._viewers.allow_vote_boost(user_id),
                    **identity,
                )

        elif event_type in ("like", "like_batch", "heart"):
            likes = bounded_int(raw_data.get("like_count") or raw_data.get("count"), 1, 50_000)
            envelope = build_like_batch_envelope(
                user_id=user_id,
                display_name=display_name,
                like_count=max(1, min(likes, 50_000)),
                candidate_slot=slot,
                source="kwai",
                **identity,
            )

        elif event_type in ("gift", "present"):
            # Kwai webhook contract: coin_value/coins/price is UNIT price; count is delta.
            coin_val = bounded_int(raw_data.get("coin_value") or raw_data.get("coins") or raw_data.get("price"), 0)
            repeat = max(1, bounded_int(raw_data.get("repeat_count") or raw_data.get("count"), 1, 1000))
            tier_req = raw_data.get("gift_tier")

            if tier_req in ("T1", "T2", "T3", "T4"):
                tier = str(tier_req)
            else:
                tier = gift_tier_for_unit_coins(coin_val)

            envelope = build_gift_envelope(
                user_id=user_id,
                display_name=display_name,
                candidate_slot=slot,
                gift_tier=tier,
                repeat_count=max(1, repeat),
                source="kwai",
                unit_coin_value=coin_val,
                gift_name=str(raw_data.get("gift_name") or "Presente Kwai"),
                gift_id=str(raw_data["gift_id"])[:64] if raw_data.get("gift_id") is not None else None,
                gift_image_url=extract_gift_image(raw_data.get("gift_image_url") or raw_data.get("gift_image")),
                **identity,
            )

        elif event_type in ("share", "forward"):
            envelope = build_share_envelope(
                user_id=user_id,
                display_name=display_name,
                candidate_slot=slot,
                source="kwai",
                **identity,
            )

        elif event_type in ("follow", "new_follower"):
            envelope = build_follow_envelope(user_id=user_id, display_name=display_name,
                candidate_slot=slot, source="kwai", **identity)

        else:
            logger.debug("KwaiLiveAdapter: tipo de evento ignorado ou não suportado: %s", event_type)
            return None

        if envelope is not None:
            await self.emit_envelope(envelope)

        return envelope

    async def _handle_http_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        """Trata requisições HTTP POST no endpoint de webhook loopback."""
        try:
            request_line = await asyncio.wait_for(reader.readline(), timeout=5.0)
            if not request_line:
                writer.close()
                await writer.wait_closed()
                return

            line_str = request_line.decode("latin1", errors="replace").strip()
            parts = line_str.split()
            if len(parts) < 2 or parts[0].upper() != "POST":
                # Responde 405 Method Not Allowed
                body_bytes = b'{"error":"Method Not Allowed"}'
                response = (
                    b"HTTP/1.1 405 Method Not Allowed\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Content-Length: " + str(len(body_bytes)).encode("ascii") + b"\r\n"
                    b"Connection: close\r\n\r\n" + body_bytes
                )
                writer.write(response)
                await writer.drain()
                writer.close()
                await writer.wait_closed()
                return

            path = parts[1].split("?", 1)[0]
            if path != self.config.webhook_path:
                body_bytes = b'{"error":"Not Found"}'
                response = (
                    b"HTTP/1.1 404 Not Found\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Content-Length: " + str(len(body_bytes)).encode("ascii") + b"\r\n"
                    b"Connection: close\r\n\r\n" + body_bytes
                )
                writer.write(response)
                await writer.drain()
                writer.close()
                await writer.wait_closed()
                return

            # Lê cabeçalhos para extrair Content-Length
            content_length = 0
            origin: str | None = None
            fetch_site = ""
            host = ""
            header_bytes = 0
            while True:
                header_line = await asyncio.wait_for(reader.readline(), timeout=5.0)
                header_bytes += len(header_line)
                if header_bytes > 8192:
                    raise ValueError("Cabeçalhos do webhook excedem 8192 bytes.")
                if not header_line or header_line in (b"\r\n", b"\n"):
                    break
                header_decoded = header_line.decode("latin1", errors="replace").strip()
                if header_decoded.lower().startswith("origin:"):
                    origin = header_decoded.split(":", 1)[1].strip()
                if header_decoded.lower().startswith("host:"):
                    host = header_decoded.split(":", 1)[1].strip().split(":", 1)[0].lower()
                if header_decoded.lower().startswith("sec-fetch-site:"):
                    fetch_site = header_decoded.split(":", 1)[1].strip().lower()
                if header_decoded.lower().startswith("content-length:"):
                    try:
                        content_length = int(header_decoded.split(":", 1)[1].strip())
                    except ValueError:
                        content_length = 0

            origin_allowed = origin is None
            if origin is not None:
                try:
                    parsed_origin = urllib.parse.urlsplit(origin)
                    origin_allowed = bool(parsed_origin.scheme == "http" and parsed_origin.hostname in ("127.0.0.1", "localhost")
                        and (parsed_origin.port or 80) == self.config.port and not parsed_origin.username
                        and not parsed_origin.password and not parsed_origin.path and not parsed_origin.query and not parsed_origin.fragment)
                except ValueError:
                    origin_allowed = False
            if not origin_allowed or fetch_site == "cross-site" or (host and host not in ("127.0.0.1", "localhost")):
                writer.write(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                await writer.drain()
                return

            if content_length <= 0 or content_length > MAX_WEBHOOK_BODY_BYTES:
                body_bytes = b'{"error":"Bad Request or payload too large"}'
                response = (
                    b"HTTP/1.1 400 Bad Request\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Content-Length: " + str(len(body_bytes)).encode("ascii") + b"\r\n"
                    b"Connection: close\r\n\r\n" + body_bytes
                )
                writer.write(response)
                await writer.drain()
                writer.close()
                await writer.wait_closed()
                return

            body_raw = await asyncio.wait_for(reader.readexactly(content_length), timeout=5.0)
            parsed_data = json.loads(body_raw.decode("utf-8", errors="replace"))

            emitted_envelope = await self.ingest_raw_event(parsed_data)

            resp_payload = {
                "status": "ok",
                "ingested": emitted_envelope is not None,
                "event_id": emitted_envelope.get("event_id") if emitted_envelope else None,
            }
            body_bytes = json.dumps(resp_payload).encode("utf-8")
            response = (
                b"HTTP/1.1 200 OK\r\n"
                b"Content-Type: application/json\r\n"
                b"Content-Length: " + str(len(body_bytes)).encode("ascii") + b"\r\n"
                b"Connection: close\r\n\r\n" + body_bytes
            )
            writer.write(response)
            await writer.drain()

        except Exception as exc:
            self.record_error(exc)
            logger.error("Erro ao processar requisição webhook do Kwai: %s", exc)
            try:
                err_bytes = b'{"error":"Internal Server Error"}'
                writer.write(
                    b"HTTP/1.1 500 Internal Server Error\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Content-Length: " + str(len(err_bytes)).encode("ascii") + b"\r\n"
                    b"Connection: close\r\n\r\n" + err_bytes
                )
                await writer.drain()
            except Exception:
                pass
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def start(self) -> None:
        """Inicia o servidor de webhook loopback se o adaptador estiver habilitado."""
        if not self.config.enabled:
            logger.info(
                "KwaiLiveAdapter está desativado (status: %s). start() ignorado com segurança.",
                self._status,
            )
            return

        if self._server is not None and self._server.is_serving():
            return

        # Garante vínculo estrito em loopback
        bind_host = "127.0.0.1" if self.config.host in ("127.0.0.1", "localhost") else "127.0.0.1"

        try:
            self._server = await asyncio.start_server(
                self._handle_http_client,
                host=bind_host,
                port=self.config.port,
            )
            self._status = "listening"
            self._started_at = time.time()
            logger.info(
                "KwaiLiveAdapter: servidor webhook escutando em http://%s:%d%s",
                bind_host,
                self.config.port,
                self.config.webhook_path,
            )
        except Exception as exc:
            self.record_error(exc)
            self._status = "error"
            logger.error("Falha ao iniciar servidor webhook loopback do Kwai: %s", exc)
            raise

    async def stop(self) -> None:
        """Encerra o servidor webhook loopback."""
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None
        self._status = "stopped"
        logger.info("KwaiLiveAdapter encerrado.")

    def get_stats(self) -> dict[str, Any]:
        """Retorna telemetria do adaptador Kwai."""
        return self.build_base_stats(
            extra_metadata={
                "enabled": self.config.enabled,
                "webhook_port": self.config.port,
                "webhook_path": self.config.webhook_path,
                "disclaimer": "Receptor passivo loopback; coletor de eventos Kwai Brasil não integrado.",
            }
        ).to_dict()
