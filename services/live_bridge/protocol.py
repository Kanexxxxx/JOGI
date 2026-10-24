"""Contrato LiveEventEnvelope, Sanitizador Zero-Trust, Deduplicador LRU e Token Bucket."""

from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass
import hashlib
import math
import re
import time
from typing import Any
import unicodedata
from gift_images import safe_gift_image_url, safe_icon_path


SCHEMA_VERSION: str = "1.0"
MAX_DISPLAY_NAME_LEN: int = 24
MAX_USER_ID_LEN: int = 64
MAX_GIFT_NAME_LEN: int = 32
MAX_PACKET_BYTES: int = 8192
LRU_DEFAULT_CAPACITY: int = 10_000
LRU_DEFAULT_TTL_SECONDS: float = 900.0
TOKEN_BUCKET_DEFAULT_RATE: float = 40.0
TOKEN_BUCKET_DEFAULT_CAPACITY: float = 40.0

VALID_SOURCES: frozenset[str] = frozenset({"tiktok", "kwai", "simulator", "admin"})
VALID_EVENT_TYPES: frozenset[str] = frozenset(
    {"gift", "vote", "like_batch", "share", "follow", "admin_command", "system_status"}
)
VALID_PRIORITIES: frozenset[str] = frozenset({"P0", "P1", "P2"})
VALID_GIFT_TIERS: frozenset[str] = frozenset({"T1", "T2", "T3", "T4", "T5"})
VALID_ADMIN_COMMANDS: frozenset[str] = frozenset(
    {
        "restart_race",
        "start_race",
        "skip_lobby",
        "pause_race",
        "resume_race",
        "reset_dedup",
        "boost",
        "shield",
        "attack",
        "spawn_obstacle",
        "set_live_goal",
        "set_audio_settings",
    }
)
VALID_ACTION_IDS: frozenset[str] = frozenset(
    {
        "micro_boost",
        "vote_impulse",
        "share_frenzy",
        "audience_follow",
        "gift_t1_turbo",
        "gift_t2_shield_or_obstacle",
        "gift_t3_super_jato",
        "gift_t3_attack",
        "gift_t4_chaos_meteor",
        "gift_t4_super_rally",
        "attack_obstacle",
        "admin_restart",
        "admin_pause",
        "admin_resume",
        "admin_boost",
        "admin_shield",
        "admin_attack",
        "admin_set_live_goal",
        "admin_set_audio_settings",
        "bridge_connected",
        "bridge_reconnecting",
    }
)

ALLOWED_TOP_KEYS: frozenset[str] = frozenset(
    {
        "schema_version",
        "event_id",
        "source",
        "event_type",
        "timestamp_ms",
        "priority",
        "user",
        "payload",
    }
)
ALLOWED_USER_KEYS: frozenset[str] = frozenset({"user_id", "display_name"})
ALLOWED_PAYLOAD_KEYS: frozenset[str] = frozenset(
    {
        "candidate_slot",
        "target",
        "target_slot",
        "obstacle_type",
        "gift_tier",
        "gift_name",
        "coin_value",
        "unit_coin_value",
        "gift_id",
        "gift_image_url",
        "gift_icon_path",
        "boost_percent",
        "repeat_count",
        "like_count",
        "action_id",
        "boost_amount",
        "boost_duration",
        "status",
        "command",
        "goal_kind",
        "goal_target",
        "goal_label",
        "goal_gift_id",
        "voices_enabled",
        "sfx_enabled",
        "crowd_enabled",
        "memes_enabled",
    }
)

CANDIDATES: dict[int, dict[str, Any]] = {
    1: {
        "slot": 1,
        "id": "lula",
        "name": "Lula",
        "color": "#FF3B5C",
        "aliases": ("1", "#1", "13", "#13", "lula", "lulinha", "pt", "fazueli", "faz o l", "vermelho"),
    },
    2: {
        "slot": 2,
        "id": "bolsonaro",
        "name": "Flávio Bolsonaro",
        "color": "#FACC15",
        "aliases": ("2", "#2", "22", "#22", "flavio", "flávio", "bolsonaro", "mito", "bolso", "capitao", "capitão", "azul", "amarelo", "verde amarelo", "verde-amarelo", "verdeamarelo"),
    },
}

GIFT_TIER_CATALOG: dict[str, dict[str, Any]] = {
    "T1": {
        "gift_tier": "T1",
        "gift_name": "Rosa Impulso",
        "coin_value": 1,
        "action_id": "gift_t1_turbo",
        "priority": "P0",
        "boost_amount": 3.5,
        "boost_duration": 3.0,
    },
    "T2": {
        "gift_tier": "T2",
        "gift_name": "Rosquinha Blindada",
        "coin_value": 15,
        "action_id": "gift_t2_shield_or_obstacle",
        "priority": "P0",
        "boost_amount": 2.0,
        "boost_duration": 5.0,
    },
    "T3": {
        "gift_tier": "T3",
        "gift_name": "Pilha de Documentos",
        "coin_value": 100,
        "action_id": "gift_t3_attack",
        "priority": "P0",
        "boost_amount": 1.0,
        "boost_duration": 2.0,
    },
    "T4": {
        "gift_tier": "T4",
        "gift_name": "Super Comício",
        "coin_value": 1000,
        "action_id": "gift_t4_super_rally",
        "priority": "P0",
        "boost_amount": 7.5,
        "boost_duration": 5.0,
    },
}

_BIDI_AND_INVISIBLE_CHARS: frozenset[str] = frozenset(
    {
        "\u061c",
        "\u200b",
        "\u200c",
        "\u200d",
        "\u200e",
        "\u200f",
        "\u202a",
        "\u202b",
        "\u202c",
        "\u202d",
        "\u202e",
        "\u2060",
        "\u2061",
        "\u2062",
        "\u2063",
        "\u2064",
        "\u2066",
        "\u2067",
        "\u2068",
        "\u2069",
        "\ufeff",
    }
)

_BBCODE_TAG_RE: re.Pattern[str] = re.compile(r"\[/?[a-zA-Z0-9_=#:.,\s-]*\]")
_USER_ID_SAFE_RE: re.Pattern[str] = re.compile(r"[^a-zA-Z0-9_.:@-]+")
_EVENT_ID_SAFE_RE: re.Pattern[str] = re.compile(r"^[a-zA-Z0-9_.:-]{8,128}$")
_VOTE_NUMBER_RE: re.Pattern[str] = re.compile(r"(?<![\w#])#?(13|22|1|2)(?!\w)")


class ProtocolValidationError(ValueError):
    """Erro lançado quando um payload viola o contrato LiveEventEnvelope."""


def sanitize_display_name(raw_name: Any, max_len: int = MAX_DISPLAY_NAME_LEN) -> str:
    """
    Sanitiza o nome de exibição do usuário segundo as diretrizes Zero-Trust (SECURITY.md):
    1. Normalização Unicode NFKC.
    2. Remoção de tags BBCode/colchetes '[' e ']' e delimitadores HTML '<' e '>'.
    3. Remoção de caracteres de controle Unicode (categorias Cc, Cf, Cs, Co, Cn) e bidi overrides.
    4. Colapso de espaços repetidos e truncamento estrito em 24 caracteres.
    """
    if raw_name is None:
        return "Espectador"

    normalized: str = unicodedata.normalize("NFKC", str(raw_name))
    without_bbcode: str = _BBCODE_TAG_RE.sub("", normalized)
    cleaned_chars: list[str] = []

    for ch in without_bbcode:
        if ch in _BIDI_AND_INVISIBLE_CHARS:
            continue
        if ch in ("[", "]", "<", ">"):
            continue
        if ch in ("\r", "\n", "\t"):
            cleaned_chars.append(" ")
            continue
        category: str = unicodedata.category(ch)
        if category.startswith("C"):
            continue
        cleaned_chars.append(ch)

    collapsed: str = " ".join("".join(cleaned_chars).split()).strip()
    if not collapsed:
        return "Espectador"
    return collapsed[:max_len].strip() or "Espectador"


def sanitize_user_id(raw_user_id: Any) -> str:
    """Sanitiza identificadores de usuários externos."""
    if raw_user_id is None:
        return "anon_user"
    normalized: str = unicodedata.normalize("NFKC", str(raw_user_id)).strip()
    safe: str = _USER_ID_SAFE_RE.sub("_", normalized)[:MAX_USER_ID_LEN].strip("_")
    return safe if safe else "anon_user"


def parse_vote_slot_from_comment(raw_comment: Any) -> int | None:
    """
    Extrai torcida 13/22 (ou 1/2 legado), ignorando comentários sem escolha e ambiguidades.
    O texto livre do chat nunca é repassado ao Godot.
    """
    if not isinstance(raw_comment, str) or not raw_comment.strip():
        return None

    normalized: str = unicodedata.normalize("NFKC", raw_comment[:512]).lower().strip()
    found: set[int] = set()
    number_slots = {"1": 1, "13": 1, "2": 2, "22": 2}
    # A number in ordinary prose ("tenho 22 anos") is not automatically a vote.
    number_only = re.fullmatch(r"[\s#!,.?+\-]*(?:(?:13|22|1|2)[\s#!,.?+\-]*)+", normalized)
    for match in _VOTE_NUMBER_RE.finditer(normalized):
        prefix = normalized[max(0, match.start() - 32):match.start()]
        intent = re.search(r"\b(?:voto|votar|vai|bora|time|equipe|apoio|torcendo|torço)\b", prefix)
        if number_only or match.group(0).startswith("#") or intent:
            found.add(number_slots[match.group(1)])
    for slot, meta in CANDIDATES.items():
        for alias in meta["aliases"]:
            if alias.lstrip("#").isdigit():
                continue
            if re.search(rf"(?<!\w){re.escape(alias)}(?!\w)", normalized):
                found.add(slot)
    return next(iter(found)) if len(found) == 1 else None


def make_deterministic_event_id(
    source: str,
    event_type: str,
    user_id: str,
    candidate_slot: int | None,
    timestamp_ms: int,
    sequence: int = 0,
) -> str:
    """Gera um event_id determinístico e seguro."""
    raw_key: str = f"{source}:{event_type}:{user_id}:{candidate_slot}:{timestamp_ms}:{sequence}"
    digest: str = hashlib.sha256(raw_key.encode("utf-8")).hexdigest()[:16]
    return f"evt_{source[:3]}_{sequence:06d}_{digest}"


def _is_strict_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def validate_envelope(data: Any, *, sanitize: bool = True) -> dict[str, Any]:
    """
    Valida estritamente um dicionário contra o contrato LiveEventEnvelope v1.0.
    Retorna uma nova cópia normalizada e sanitizada ou levanta ProtocolValidationError.
    """
    if not isinstance(data, dict):
        raise ProtocolValidationError("O envelope deve ser um objeto JSON (dict).")

    missing_keys = ALLOWED_TOP_KEYS - data.keys()
    if missing_keys:
        raise ProtocolValidationError(f"Campos obrigatórios ausentes no envelope: {sorted(missing_keys)}")

    extra_top_keys = data.keys() - ALLOWED_TOP_KEYS
    if extra_top_keys:
        raise ProtocolValidationError(f"Campos desconhecidos no topo do envelope: {sorted(extra_top_keys)}")

    if data.get("schema_version") != SCHEMA_VERSION:
        raise ProtocolValidationError(
            f"schema_version inválido: esperado '{SCHEMA_VERSION}', recebido {data.get('schema_version')!r}"
        )

    event_id = data.get("event_id")
    if not isinstance(event_id, str) or not _EVENT_ID_SAFE_RE.match(event_id):
        raise ProtocolValidationError(
            f"event_id inválido (deve ter 8..128 chars alfanuméricos/seguros): {event_id!r}"
        )

    source = data.get("source")
    if not isinstance(source, str) or source not in VALID_SOURCES:
        raise ProtocolValidationError(f"source inválido: {source!r}")

    event_type = data.get("event_type")
    if not isinstance(event_type, str) or event_type not in VALID_EVENT_TYPES:
        raise ProtocolValidationError(f"event_type inválido: {event_type!r}")

    if event_type == "admin_command" and source != "admin":
        raise ProtocolValidationError("admin_command exige source == 'admin'.")

    timestamp_ms = data.get("timestamp_ms")
    if not _is_strict_int(timestamp_ms) or timestamp_ms < 0:
        raise ProtocolValidationError(f"timestamp_ms deve ser inteiro >= 0: {timestamp_ms!r}")

    priority = data.get("priority")
    if not isinstance(priority, str) or priority not in VALID_PRIORITIES:
        raise ProtocolValidationError(f"priority inválido (esperado P0, P1 ou P2): {priority!r}")

    user_raw = data.get("user")
    if not isinstance(user_raw, dict):
        raise ProtocolValidationError("Campo 'user' deve ser um objeto JSON.")
    if set(user_raw.keys()) != ALLOWED_USER_KEYS:
        raise ProtocolValidationError(
            f"Campo 'user' deve conter exatamente {sorted(ALLOWED_USER_KEYS)}, recebido {sorted(user_raw.keys())}"
        )
    if not isinstance(user_raw.get("user_id"), str) or not user_raw["user_id"].strip():
        raise ProtocolValidationError("user.user_id deve ser uma string não vazia.")
    if not isinstance(user_raw.get("display_name"), str):
        raise ProtocolValidationError("user.display_name deve ser uma string.")

    if sanitize:
        clean_user_id = sanitize_user_id(user_raw["user_id"])
        clean_display_name = sanitize_display_name(user_raw["display_name"])
    else:
        clean_user_id = user_raw["user_id"]
        clean_display_name = user_raw["display_name"]
        if len(clean_display_name) > MAX_DISPLAY_NAME_LEN:
            raise ProtocolValidationError("user.display_name excede 24 caracteres.")

    payload_raw = data.get("payload")
    if not isinstance(payload_raw, dict):
        raise ProtocolValidationError("Campo 'payload' deve ser um objeto JSON.")

    extra_payload_keys = payload_raw.keys() - ALLOWED_PAYLOAD_KEYS
    if extra_payload_keys:
        raise ProtocolValidationError(
            f"Campos não permitidos em 'payload': {sorted(extra_payload_keys)}"
        )

    clean_payload: dict[str, Any] = {}

    target_val = payload_raw.get("target")
    if target_val is not None:
        if isinstance(target_val, str):
            t_lower = target_val.strip().lower()
            if t_lower in ("lula", "1", "#1", "13", "#13"):
                clean_payload["candidate_slot"] = 1
                clean_payload["target"] = "lula"
            elif t_lower in ("bolsonaro", "flavio", "flávio", "flavio bolsonaro", "2", "#2", "22", "#22"):
                clean_payload["candidate_slot"] = 2
                clean_payload["target"] = "bolsonaro"
            else:
                raise ProtocolValidationError(f"target inválido: {target_val!r}. Esperado 'lula' ou 'bolsonaro'.")
        elif _is_strict_int(target_val) and target_val in (1, 2):
            clean_payload["candidate_slot"] = target_val
            clean_payload["target"] = "lula" if target_val == 1 else "bolsonaro"
        else:
            raise ProtocolValidationError(f"target inválido: {target_val!r}. Esperado 'lula' (1) ou 'bolsonaro' (2).")

    if "candidate_slot" in payload_raw and payload_raw["candidate_slot"] is not None:
        slot = payload_raw["candidate_slot"]
        if not _is_strict_int(slot) or not (1 <= slot <= 2):
            raise ProtocolValidationError(f"candidate_slot deve ser 1 (Lula) ou 2 (Bolsonaro): {slot!r}")
        if "candidate_slot" in clean_payload and clean_payload["candidate_slot"] != slot:
            raise ProtocolValidationError("payload.target e candidate_slot apontam para equipes diferentes.")
        clean_payload["candidate_slot"] = slot
        if "target" not in clean_payload:
            clean_payload["target"] = "lula" if slot == 1 else "bolsonaro"
    elif "candidate_slot" not in clean_payload and event_type == "vote":
        raise ProtocolValidationError(f"event_type '{event_type}' exige payload.candidate_slot (1=Lula, 2=Bolsonaro) ou payload.target.")

    if "target_slot" in payload_raw and payload_raw["target_slot"] is not None:
        tslot = payload_raw["target_slot"]
        if not _is_strict_int(tslot) or not (1 <= tslot <= 2):
            raise ProtocolValidationError(f"target_slot deve ser 1 (Lula) ou 2 (Bolsonaro): {tslot!r}")
        clean_payload["target_slot"] = tslot

    if "obstacle_type" in payload_raw and payload_raw["obstacle_type"] is not None:
        clean_payload["obstacle_type"] = sanitize_display_name(payload_raw["obstacle_type"], max_len=32)

    if "command" in payload_raw and payload_raw["command"] is not None:
        cmd = payload_raw["command"]
        if not isinstance(cmd, str) or cmd not in VALID_ADMIN_COMMANDS:
            raise ProtocolValidationError(f"payload.command inválido: {cmd!r}")
        clean_payload["command"] = cmd
    elif event_type == "admin_command" and "action_id" not in payload_raw:
        raise ProtocolValidationError("admin_command exige payload.command ou payload.action_id válido.")

    if "action_id" in payload_raw and payload_raw["action_id"] is not None:
        action_id = payload_raw["action_id"]
        if not isinstance(action_id, str) or action_id not in VALID_ACTION_IDS:
            raise ProtocolValidationError(f"payload.action_id inválido: {action_id!r}")
        clean_payload["action_id"] = action_id
    elif event_type != "admin_command":
        raise ProtocolValidationError("payload.action_id é obrigatório.")

    if "gift_tier" in payload_raw and payload_raw["gift_tier"] is not None:
        tier = payload_raw["gift_tier"]
        if not isinstance(tier, str) or tier not in VALID_GIFT_TIERS:
            raise ProtocolValidationError(f"payload.gift_tier inválido: {tier!r}")
        clean_payload["gift_tier"] = tier
    elif event_type == "gift":
        raise ProtocolValidationError("event_type 'gift' exige payload.gift_tier ('T1'..'T4').")

    if "gift_name" in payload_raw and payload_raw["gift_name"] is not None:
        if not isinstance(payload_raw["gift_name"], str):
            raise ProtocolValidationError("payload.gift_name deve ser string.")
        clean_payload["gift_name"] = sanitize_display_name(
            payload_raw["gift_name"], max_len=MAX_GIFT_NAME_LEN
        )

    if "coin_value" in payload_raw and payload_raw["coin_value"] is not None:
        cv = payload_raw["coin_value"]
        if not _is_strict_int(cv) or not (0 <= cv <= 100_000_000):
            raise ProtocolValidationError(f"payload.coin_value fora do intervalo 0..100000000: {cv!r}")
        clean_payload["coin_value"] = cv

    if "repeat_count" in payload_raw and payload_raw["repeat_count"] is not None:
        rc = payload_raw["repeat_count"]
        if not _is_strict_int(rc) or not (1 <= rc <= 1_000):
            raise ProtocolValidationError(f"payload.repeat_count fora do intervalo 1..1000: {rc!r}")
        clean_payload["repeat_count"] = rc

    if payload_raw.get("gift_id") is not None:
        gift_id = payload_raw["gift_id"]
        if event_type != "gift" or not isinstance(gift_id, str) or not gift_id.strip() or len(gift_id) > 64:
            raise ProtocolValidationError("gift_id exige presente e texto não vazio de até 64 caracteres.")
        clean_payload["gift_id"] = sanitize_display_name(gift_id, max_len=64)
    if payload_raw.get("unit_coin_value") is not None:
        unit_value = payload_raw["unit_coin_value"]
        if event_type != "gift" or not _is_strict_int(unit_value) or not 0 <= unit_value <= 100_000:
            raise ProtocolValidationError("unit_coin_value exige presente e inteiro 0..100000.")
        total = unit_value * clean_payload.get("repeat_count", 1)
        if "coin_value" in clean_payload and clean_payload["coin_value"] != total:
            raise ProtocolValidationError("coin_value deve ser unit_coin_value multiplicado pelo delta, uma vez.")
        clean_payload.update(unit_coin_value=unit_value, coin_value=total)

    if event_type == "gift":
        image_url = safe_gift_image_url(payload_raw.get("gift_image_url"))
        if image_url:
            clean_payload["gift_image_url"] = image_url
        icon_path = safe_icon_path(payload_raw.get("gift_icon_path"))
        if icon_path:
            clean_payload["gift_icon_path"] = icon_path
        percent = payload_raw.get("boost_percent")
        if percent is not None:
            if isinstance(percent, bool) or not isinstance(percent, (int, float)) or not math.isfinite(percent) or not 0 <= percent <= 200:
                raise ProtocolValidationError("boost_percent deve ser número entre 0 e 200.")
            clean_payload["boost_percent"] = round(float(percent), 3)

    if "like_count" in payload_raw and payload_raw["like_count"] is not None:
        lc = payload_raw["like_count"]
        if not _is_strict_int(lc) or not (1 <= lc <= 50_000):
            raise ProtocolValidationError(f"payload.like_count fora do intervalo 1..50000: {lc!r}")
        clean_payload["like_count"] = lc

    if "boost_amount" in payload_raw and payload_raw["boost_amount"] is not None:
        ba = payload_raw["boost_amount"]
        if isinstance(ba, bool) or not isinstance(ba, (int, float)) or not (0.0 <= float(ba) <= 50.0):
            raise ProtocolValidationError(f"payload.boost_amount inválido: {ba!r}")
        clean_payload["boost_amount"] = round(min(float(ba), 24.0 if event_type == "gift" else 1.5 if event_type == "vote" else 50.0), 3)

    if "boost_duration" in payload_raw and payload_raw["boost_duration"] is not None:
        bd = payload_raw["boost_duration"]
        if isinstance(bd, bool) or not isinstance(bd, (int, float)) or not (0.0 if event_type == "gift" else 0.1) <= float(bd) <= 30.0:
            raise ProtocolValidationError(f"payload.boost_duration inválido: {bd!r}")
        clean_payload["boost_duration"] = round(min(float(bd), 1.0 if event_type == "vote" else 30.0), 3)

    if "status" in payload_raw and payload_raw["status"] is not None:
        if not isinstance(payload_raw["status"], str) or len(payload_raw["status"]) > 64:
            raise ProtocolValidationError("payload.status inválido.")
        clean_payload["status"] = sanitize_display_name(payload_raw["status"], max_len=64)

    if payload_raw.get("command") == "set_live_goal":
        if payload_raw.get("goal_kind") not in ("likes", "follows", "gifts", "coins", "gift_specific"):
            raise ProtocolValidationError("goal_kind deve ser likes, follows, gifts, coins ou gift_specific.")
        target = payload_raw.get("goal_target")
        if not _is_strict_int(target) or not 1 <= target <= 1_000_000_000:
            raise ProtocolValidationError("goal_target deve ser inteiro entre 1 e 1000000000.")
        label = payload_raw.get("goal_label", "Meta da live")
        if not isinstance(label, str):
            raise ProtocolValidationError("goal_label deve ser texto.")
        clean_payload.update(goal_kind=payload_raw["goal_kind"], goal_target=target,
                             goal_label=sanitize_display_name(label, max_len=40))
        if payload_raw["goal_kind"] == "gift_specific":
            gift_id = payload_raw.get("goal_gift_id")
            if not isinstance(gift_id, str) or not 1 <= len(gift_id) <= 64 or sanitize_display_name(gift_id, max_len=64) != gift_id:
                raise ProtocolValidationError("Meta de presente específico exige goal_gift_id de 1 a 64 caracteres sem controles.")
            clean_payload["goal_gift_id"] = gift_id
    elif any(key in payload_raw for key in ("goal_kind", "goal_target", "goal_label", "goal_gift_id")):
        raise ProtocolValidationError("Campos de meta exigem command=set_live_goal.")
    audio_keys = ("voices_enabled", "sfx_enabled", "crowd_enabled", "memes_enabled")
    if payload_raw.get("command") == "set_audio_settings":
        for key in audio_keys:
            if not isinstance(payload_raw.get(key), bool):
                raise ProtocolValidationError(f"{key} deve ser booleano explícito.")
            clean_payload[key] = payload_raw[key]
    elif any(key in payload_raw for key in audio_keys):
        raise ProtocolValidationError("Campos de áudio exigem command=set_audio_settings.")

    return {
        "schema_version": SCHEMA_VERSION,
        "event_id": event_id,
        "source": source,
        "event_type": event_type,
        "timestamp_ms": timestamp_ms,
        "priority": priority,
        "user": {
            "user_id": clean_user_id,
            "display_name": clean_display_name,
        },
        "payload": clean_payload,
    }


def build_vote_envelope(
    *,
    user_id: str,
    display_name: str,
    candidate_slot: int,
    source: str = "simulator",
    repeat_count: int = 1,
    timestamp_ms: int | None = None,
    event_id: str | None = None,
    sequence: int = 0,
    boost_allowed: bool = True,
) -> dict[str, Any]:
    """Constrói voto para equipe 1=Lula (13) ou 2=Flávio (22)."""
    ts = timestamp_ms if timestamp_ms is not None else int(time.time() * 1000)
    eid = event_id or make_deterministic_event_id(source, "vote", user_id, candidate_slot, ts, sequence)
    return validate_envelope(
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": eid,
            "source": source,
            "event_type": "vote",
            "timestamp_ms": ts,
            "priority": "P1",
            "user": {"user_id": user_id, "display_name": display_name},
            "payload": {
                "candidate_slot": candidate_slot,
                "action_id": "vote_impulse",
                "repeat_count": max(1, min(repeat_count, 1000)),
                "boost_amount": 1.1 if boost_allowed else 0.0,
                "boost_duration": 1.0,
            },
        }
    )


def build_like_batch_envelope(
    *,
    user_id: str,
    display_name: str,
    like_count: int,
    candidate_slot: int | None = None,
    source: str = "simulator",
    timestamp_ms: int | None = None,
    event_id: str | None = None,
    sequence: int = 0,
) -> dict[str, Any]:
    """Constrói um envelope validado de lote de curtidas (like_batch)."""
    ts = timestamp_ms if timestamp_ms is not None else int(time.time() * 1000)
    slot = candidate_slot if candidate_slot in CANDIDATES else None
    eid = event_id or make_deterministic_event_id(source, "like_batch", user_id, slot, ts, sequence)
    payload: dict[str, Any] = {
        "candidate_slot": slot,
        "action_id": "micro_boost",
        "like_count": max(1, min(like_count, 50_000)),
        "boost_amount": 0.9,
        "boost_duration": 1.5,
    }
    return validate_envelope(
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": eid,
            "source": source,
            "event_type": "like_batch",
            "timestamp_ms": ts,
            "priority": "P2",
            "user": {"user_id": user_id, "display_name": display_name},
            "payload": payload,
        }
    )


def build_share_envelope(
    *,
    user_id: str,
    display_name: str,
    candidate_slot: int | None = None,
    source: str = "simulator",
    timestamp_ms: int | None = None,
    event_id: str | None = None,
    sequence: int = 0,
) -> dict[str, Any]:
    """Constrói um envelope validado de compartilhamento (share)."""
    ts = timestamp_ms if timestamp_ms is not None else int(time.time() * 1000)
    eid = event_id or make_deterministic_event_id(source, "share", user_id, candidate_slot, ts, sequence)
    return validate_envelope(
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": eid,
            "source": source,
            "event_type": "share",
            "timestamp_ms": ts,
            "priority": "P1",
            "user": {"user_id": user_id, "display_name": display_name},
            "payload": {
                "candidate_slot": candidate_slot,
                "action_id": "share_frenzy",
                "repeat_count": 1,
                "boost_amount": 2.4,
                "boost_duration": 3.0,
            },
        }
    )


def gift_tier_for_unit_coins(unit_coins: int) -> str:
    """Game effect brackets, independent of any platform gift catalog pricing."""
    return "T4" if unit_coins >= 1000 else "T3" if unit_coins >= 100 else "T2" if unit_coins >= 10 else "T1"


def gift_boost_for_total_coins(total_coins: int) -> tuple[float, float, float]:
    """Deterministic game brackets, base speed 12 m/s; never currency or revenue."""
    for threshold, percent, duration in ((30000, 200, 10), (10000, 150, 10),
            (1000, 70, 8), (100, 35, 5), (10, 15, 4), (1, 5, 3)):
        if total_coins >= threshold:
            return round(12.0 * percent / 100.0, 3), float(duration), float(percent)
    return 0.0, 0.0, 0.0


def build_follow_envelope(
    *, user_id: str, display_name: str, candidate_slot: int | None = None,
    source: str = "simulator", timestamp_ms: int | None = None,
    event_id: str | None = None, sequence: int = 0,
) -> dict[str, Any]:
    ts = timestamp_ms if timestamp_ms is not None else int(time.time() * 1000)
    return validate_envelope({
        "schema_version": SCHEMA_VERSION,
        "event_id": event_id or make_deterministic_event_id(source, "follow", user_id, candidate_slot, ts, sequence),
        "source": source, "event_type": "follow", "timestamp_ms": ts, "priority": "P1",
        "user": {"user_id": user_id, "display_name": display_name},
        "payload": {"candidate_slot": candidate_slot, "action_id": "audience_follow", "repeat_count": 1},
    })


def build_gift_envelope(
    *,
    user_id: str,
    display_name: str,
    candidate_slot: int | None,
    gift_tier: str = "T1",
    repeat_count: int = 1,
    source: str = "simulator",
    timestamp_ms: int | None = None,
    event_id: str | None = None,
    sequence: int = 0,
    unit_coin_value: int | None = None,
    gift_name: str | None = None,
    gift_id: str | None = None,
    gift_image_url: str | None = None,
) -> dict[str, Any]:
    """Constrói um envelope validado de presente (T1 a T4) com prioridade P0."""
    if gift_tier not in GIFT_TIER_CATALOG:
        raise ProtocolValidationError(f"gift_tier inválido: {gift_tier!r}")
    spec = GIFT_TIER_CATALOG[gift_tier]
    count = max(1, min(int(repeat_count), 1000))
    unit_value = spec["coin_value"] if unit_coin_value is None else unit_coin_value
    if not _is_strict_int(unit_value) or not (0 <= unit_value <= 100_000):
        raise ProtocolValidationError("unit_coin_value deve ser inteiro em 0..100000.")
    gift_tier = gift_tier_for_unit_coins(unit_value)
    spec = GIFT_TIER_CATALOG[gift_tier]
    total_coins = unit_value * count
    gift_boost, gift_duration, gift_percent = gift_boost_for_total_coins(total_coins)
    ts = timestamp_ms if timestamp_ms is not None else int(time.time() * 1000)
    eid = event_id or make_deterministic_event_id(source, f"gift_{gift_tier}", user_id, candidate_slot, ts, sequence)
    return validate_envelope(
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": eid,
            "source": source,
            "event_type": "gift",
            "timestamp_ms": ts,
            "priority": spec["priority"],
            "user": {"user_id": user_id, "display_name": display_name},
            "payload": {
                "candidate_slot": candidate_slot,
                "gift_tier": gift_tier,
                "gift_name": gift_name if gift_name is not None else spec["gift_name"],
                "gift_id": gift_id,
                "gift_image_url": gift_image_url,
                "unit_coin_value": unit_value,
                "coin_value": total_coins,
                "repeat_count": count,
                "action_id": spec["action_id"],
                "boost_amount": gift_boost,
                "boost_duration": gift_duration,
                "boost_percent": gift_percent,
            },
        }
    )


def build_admin_command_envelope(
    *,
    command: str,
    candidate_slot: int | None = None,
    boost_amount: float = 5.0,
    boost_duration: float = 3.5,
    user_id: str = "admin_console",
    display_name: str = "ADMIN",
    timestamp_ms: int | None = None,
    event_id: str | None = None,
    sequence: int = 0,
    goal_kind: str | None = None,
    goal_target: int | None = None,
    goal_label: str = "Meta da live",
    goal_gift_id: str | None = None,
    voices_enabled: bool | None = None,
    sfx_enabled: bool | None = None,
    crowd_enabled: bool | None = None,
    memes_enabled: bool | None = None,
) -> dict[str, Any]:
    """Constrói um envelope validado de comando administrativo (P0) com source='admin'."""
    if command not in VALID_ADMIN_COMMANDS:
        raise ProtocolValidationError(f"command inválido: {command!r}")
    ts = timestamp_ms if timestamp_ms is not None else int(time.time() * 1000)
    identity_kind = f"cmd_{command}"
    if command == "set_live_goal":
        identity_kind += f":{goal_kind}:{goal_target}:{goal_label}:{goal_gift_id}"
    if command == "set_audio_settings":
        identity_kind += f":{voices_enabled}:{sfx_enabled}:{crowd_enabled}:{memes_enabled}"
    eid = event_id or make_deterministic_event_id("admin", identity_kind, user_id, candidate_slot, ts, sequence)
    
    payload: dict[str, Any] = {"command": command}
    if candidate_slot is not None:
        if not (1 <= candidate_slot <= 2):
            raise ProtocolValidationError(f"candidate_slot deve ser 1 (Lula) ou 2 (Bolsonaro): {candidate_slot!r}")
        payload["candidate_slot"] = candidate_slot
        if command in ("boost", "turbo"):
            payload["action_id"] = "admin_boost"
            payload["boost_amount"] = round(float(boost_amount), 3)
            payload["boost_duration"] = round(float(boost_duration), 3)
        elif command == "shield":
            payload["action_id"] = "admin_shield"
            payload["boost_amount"] = 2.0
            payload["boost_duration"] = round(float(boost_duration), 3)
        elif command in ("attack", "spawn_obstacle"):
            payload["action_id"] = "admin_attack"
            payload["target_slot"] = 2 if candidate_slot == 1 else 1
            payload["obstacle_type"] = "pilha_documentos"
        else:
            payload["action_id"] = "admin_restart" if "restart" in command else "bridge_connected"
    else:
        payload["action_id"] = "admin_restart" if "restart" in command else "bridge_connected"

    if command == "set_live_goal":
        payload.update(action_id="admin_set_live_goal", goal_kind=goal_kind,
                       goal_target=goal_target, goal_label=goal_label, goal_gift_id=goal_gift_id)
    if command == "set_audio_settings":
        payload.update(action_id="admin_set_audio_settings", voices_enabled=voices_enabled,
                       sfx_enabled=sfx_enabled, crowd_enabled=crowd_enabled, memes_enabled=memes_enabled)

    return validate_envelope(
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": eid,
            "source": "admin",
            "event_type": "admin_command",
            "timestamp_ms": ts,
            "priority": "P0",
            "user": {"user_id": user_id, "display_name": display_name},
            "payload": payload,
        }
    )


def build_attack_envelope(
    *,
    user_id: str,
    display_name: str,
    candidate_slot: int = 1,
    target_slot: int | None = None,
    obstacle_type: str = "pilha_documentos",
    source: str = "simulator",
    timestamp_ms: int | None = None,
    event_id: str | None = None,
    sequence: int = 0,
) -> dict[str, Any]:
    """Constrói um envelope validado de ataque político com obstáculo na raia adversária."""
    ts = timestamp_ms if timestamp_ms is not None else int(time.time() * 1000)
    eid = event_id or make_deterministic_event_id(source, "attack", user_id, candidate_slot, ts, sequence)
    actual_target = target_slot if target_slot in (1, 2) else (2 if candidate_slot == 1 else 1)
    return validate_envelope(
        {
            "schema_version": SCHEMA_VERSION,
            "event_id": eid,
            "source": source,
            "event_type": "gift",
            "timestamp_ms": ts,
            "priority": "P0",
            "user": {"user_id": user_id, "display_name": display_name},
            "payload": {
                "candidate_slot": candidate_slot,
                "target_slot": actual_target,
                "gift_tier": "T3",
                "gift_name": "Pilha de Documentos",
                "coin_value": 100,
                "repeat_count": 1,
                "action_id": "gift_t3_attack",
                "obstacle_type": obstacle_type,
                "boost_amount": 1.0,
                "boost_duration": 2.0,
            },
        }
    )


class LRUDeduplicator:
    """
    Cache LRU idempotente em memória com capacidade máxima (10.000 chaves) e TTL (15 min).
    Descarta silenciosamente pacotes duplicados reenviados em reconexões de WebSocket.
    """

    def __init__(
        self,
        max_size: int = LRU_DEFAULT_CAPACITY,
        ttl_seconds: float = LRU_DEFAULT_TTL_SECONDS,
    ) -> None:
        if max_size <= 0:
            raise ValueError("max_size deve ser > 0")
        self.max_size: int = max_size
        self.ttl_seconds: float = ttl_seconds
        self._store: OrderedDict[str, float] = OrderedDict()
        self.duplicates_dropped: int = 0

    def __len__(self) -> int:
        return len(self._store)

    def _evict_expired(self, now: float) -> None:
        cutoff: float = now - self.ttl_seconds
        while self._store:
            oldest_key, oldest_ts = next(iter(self._store.items()))
            if oldest_ts < cutoff:
                self._store.popitem(last=False)
            else:
                break

    def is_duplicate(self, event_id: str, now_monotonic: float | None = None) -> bool:
        """Retorna True se o event_id já foi visto dentro do TTL; caso contrário registra e retorna False."""
        now: float = time.monotonic() if now_monotonic is None else now_monotonic
        self._evict_expired(now)

        if event_id in self._store:
            self._store[event_id] = now
            self._store.move_to_end(event_id)
            self.duplicates_dropped += 1
            return True

        self._store[event_id] = now
        if len(self._store) > self.max_size:
            self._store.popitem(last=False)
        return False

    def forget(self, event_id: str) -> None:
        """Undo an admission that failed before the event was queued/persisted."""
        self._store.pop(event_id, None)


class TokenBucket:
    """
    Limitador de taxa Token Bucket para garantir no máximo 40 mensagens/segundo ao Godot.
    """

    def __init__(
        self,
        rate_per_sec: float = TOKEN_BUCKET_DEFAULT_RATE,
        capacity: float = TOKEN_BUCKET_DEFAULT_CAPACITY,
    ) -> None:
        self.rate_per_sec: float = float(rate_per_sec)
        self.capacity: float = float(capacity)
        self.tokens: float = float(capacity)
        self._last_refill: float = time.monotonic()

    def _refill(self, now: float) -> None:
        elapsed: float = max(0.0, now - self._last_refill)
        self._last_refill = now
        self.tokens = min(self.capacity, self.tokens + elapsed * self.rate_per_sec)

    def consume(self, amount: float = 1.0, now_monotonic: float | None = None) -> bool:
        now: float = time.monotonic() if now_monotonic is None else now_monotonic
        self._refill(now)
        if self.tokens >= amount:
            self.tokens -= amount
            return True
        return False

    def time_until_available(self, amount: float = 1.0, now_monotonic: float | None = None) -> float:
        now: float = time.monotonic() if now_monotonic is None else now_monotonic
        self._refill(now)
        if self.tokens >= amount:
            return 0.0
        deficit: float = amount - self.tokens
        return deficit / self.rate_per_sec


@dataclass
class GiftStreakTracker:
    """
    Rastreador de combos (streaking) para presentes do TikTok LIVE.
    Garante que combos incrementais emitam apenas o delta positivo e não dupliquem no pacote final.
    """

    ttl_seconds: float = 60.0
    max_size: int = 10_000

    def __post_init__(self) -> None:
        self._streaks: OrderedDict[str, tuple[int, float, bool]] = OrderedDict()

    def register_gift_packet(
        self,
        *,
        user_id: str,
        gift_id: str,
        streak_id: str | None,
        repeat_count: int,
        streaking: bool,
        streakable: bool = True,
        now_monotonic: float | None = None,
    ) -> int:
        """Retorna o delta de presentes novos a emitir (0 se for duplicata/fechamento de combo já contado)."""
        now: float = time.monotonic() if now_monotonic is None else now_monotonic
        while self._streaks and now - next(iter(self._streaks.values()))[1] > self.ttl_seconds:
            self._streaks.popitem(last=False)
        count = max(1, min(int(repeat_count), 1_000_000_000))
        if not streakable:
            # Distinct non-combo gifts are deduplicated by their upstream message ID.
            return count
        key = f"{user_id}:{gift_id}:{streak_id or 'implicit'}"
        last_count, _, closed = self._streaks.get(key, (0, now, False))
        # Without a platform combo ID, a new rising streak after closure starts again.
        if not streak_id and closed and streaking and count <= last_count:
            last_count = 0
        delta = max(0, count - last_count)
        self._streaks[key] = (max(last_count, count), now, not streaking)
        self._streaks.move_to_end(key)
        while len(self._streaks) > self.max_size:
            self._streaks.popitem(last=False)
        return delta
