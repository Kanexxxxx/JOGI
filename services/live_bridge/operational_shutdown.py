"""Absolute, sticky end-of-experience state; never controls a streaming application."""
from __future__ import annotations

from datetime import datetime, timezone
import json
import os
import re
from pathlib import Path
import time
from typing import Callable, Any

DEFAULT_END_AT = "2026-10-26T07:00:00-03:00"


def normalize_end_at(raw: str) -> tuple[str, float]:
    if not isinstance(raw, str) or re.fullmatch(
            r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:Z|[+-][0-9]{2}:[0-9]{2})", raw) is None:
        raise ValueError("JOGI_END_AT deve ser YYYY-MM-DDTHH:MM:SS com Z ou offset ±HH:MM.")
    if not raw.endswith("Z") and (int(raw[-2:]) > 59 or int(raw[-5:-3]) > 14):
        raise ValueError("Offset de JOGI_END_AT inválido.")
    try:
        value = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except (TypeError, ValueError) as error:
        raise ValueError("JOGI_END_AT deve ser ISO 8601 com fuso explícito.") from error
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("JOGI_END_AT exige fuso explícito; Brasília usa -03:00.")
    if abs(value.utcoffset().total_seconds()) > 14 * 3600:
        raise ValueError("JOGI_END_AT admite offset de no máximo 14 horas.")
    return value.isoformat(), value.timestamp()


class OperationalShutdown:
    def __init__(self, path: Path | None = None, *, end_at: str | None = None,
                 now: Callable[[], float] = time.time) -> None:
        self.path, self.now = path, now
        self.end_at, self.deadline = normalize_end_at(end_at or os.environ.get("JOGI_END_AT", DEFAULT_END_AT))
        self.ended = False
        self.reason = ""
        self.ended_at: str | None = None
        if path is not None and path.exists():
            # A corrupted terminal marker is a startup error, never a silent reopening.
            saved = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(saved, dict) or not isinstance(saved.get("ended"), bool):
                raise ValueError("Estado de encerramento inválido; recuperação manual necessária.")
            self.ended = saved["ended"]
            self.reason = str(saved.get("reason", ""))[:32]
            self.ended_at = saved.get("ended_at")
        self.check_deadline()

    def end(self, reason: str = "manual") -> bool:
        if self.ended:
            return False
        state = {"end_at": self.end_at, "ended": True, "reason": reason,
                 "ended_at": datetime.fromtimestamp(self.now(), timezone.utc).isoformat()}
        if self.path is not None:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temp = self.path.with_suffix(".tmp")
            with temp.open("w", encoding="utf-8") as handle:
                json.dump(state, handle, ensure_ascii=False)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp, self.path)
        self.ended, self.reason, self.ended_at = True, reason, state["ended_at"]
        return True

    def check_deadline(self) -> bool:
        return self.end("deadline") if not self.ended and self.now() >= self.deadline else False

    def snapshot(self) -> dict[str, Any]:
        return {"end_at": self.end_at, "ended": self.ended, "reason": self.reason,
                "ended_at": self.ended_at, "time_zone": "America/Sao_Paulo"}
