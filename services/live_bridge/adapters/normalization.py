"""Helpers for untrusted connector dictionaries and SDK event objects."""

from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass, field
import hashlib
import time
from typing import Any


def read_field(value: Any, name: str, default: Any = None) -> Any:
    return value.get(name, default) if isinstance(value, dict) else getattr(value, name, default)


def bounded_int(value: Any, default: int = 0, maximum: int = 100_000) -> int:
    if isinstance(value, bool):
        return default
    try:
        return max(0, min(int(value), maximum))
    except (ValueError, TypeError, OverflowError):
        return default


def raw_packet_id(event: Any) -> str | None:
    common = read_field(event, "common")
    value = (read_field(event, "event_id") or read_field(event, "msg_id")
             or read_field(event, "message_id") or read_field(common, "msg_id"))
    return str(value)[:256] if value else None


@dataclass
class ViewerContext:
    """Bounded per-platform team memory and raw-packet replay cache, without credentials."""

    max_users: int = 10_000
    ttl_seconds: float = 32 * 3600.0
    _teams: OrderedDict[str, tuple[int, float]] = field(default_factory=OrderedDict)
    _packets: OrderedDict[str, float] = field(default_factory=OrderedDict)
    _sequence: int = 0
    _last_vote_boost: OrderedDict[str, float] = field(default_factory=OrderedDict)

    def choose(self, user_id: str, slot: int) -> None:
        self._teams[user_id] = (slot, time.monotonic())
        self._teams.move_to_end(user_id)
        while len(self._teams) > self.max_users:
            self._teams.popitem(last=False)

    def team(self, user_id: str, fallback: int | None = None) -> int | None:
        value = self._teams.get(user_id)
        if value and time.monotonic() - value[1] <= self.ttl_seconds:
            return value[0]
        self._teams.pop(user_id, None)
        return fallback if fallback in (1, 2) else None

    def allow_vote_boost(self, user_id: str, now: float | None = None) -> bool:
        current = time.monotonic() if now is None else now
        previous = self._last_vote_boost.get(user_id)
        if previous is not None and current - previous < 2.0:
            return False
        self._last_vote_boost[user_id] = current
        self._last_vote_boost.move_to_end(user_id)
        while len(self._last_vote_boost) > self.max_users:
            self._last_vote_boost.popitem(last=False)
        return True

    def identity(self, event: Any, source: str, kind: str) -> dict[str, Any] | None:
        packet = raw_packet_id(event)
        now = time.monotonic()
        while self._packets and now - next(iter(self._packets.values())) > 900.0:
            self._packets.popitem(last=False)
        if packet:
            key = f"{source}:{kind}:{packet}"
            if key in self._packets:
                return None
            self._packets[key] = now
            while len(self._packets) > self.max_users:
                self._packets.popitem(last=False)
            event_id = "evt_" + source + "_" + hashlib.sha256(key.encode()).hexdigest()[:32]
        else:
            event_id = None
        self._sequence += 1
        return {"sequence": self._sequence, "event_id": event_id}
