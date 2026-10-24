"""Per-instance Kwai collector configuration with strict URL validation and atomic persistence."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any
import urllib.parse

ALLOWED_KWAI_DOMAINS: tuple[str, ...] = ("kwai.com",)


def validate_kwai_live_url(raw_url: Any) -> str:
    """Allow empty string (default @account profile) or strict HTTPS URL on kwai.com."""
    if raw_url is None:
        return ""
    value = str(raw_url).strip()
    if not value:
        return ""
    if len(value) > 240 or any(ord(ch) < 33 or ord(ch) == 127 for ch in value):
        raise ValueError("URL da live Kwai inválida ou longa demais.")
    parsed = urllib.parse.urlsplit(value)
    host = (parsed.hostname or "").lower()
    domain_ok = any(host == dom or host.endswith("." + dom) for dom in ALLOWED_KWAI_DOMAINS)
    if (
        parsed.scheme != "https"
        or not domain_ok
        or parsed.username
        or parsed.password
        or parsed.port not in (None, 443)
        or parsed.fragment
    ):
        raise ValueError("Apenas URLs HTTPS oficiais em kwai.com são permitidas.")
    return urllib.parse.urlunsplit(("https", host, parsed.path or "/", parsed.query, ""))


class KwaiCollectorSettings:
    def __init__(self, path: Path | None, default_account: str = "") -> None:
        self.path = path
        self.default_account = default_account.strip().lstrip("@")[:64]
        self.configured = False
        self.live_url = ""
        if path is not None and path.exists():
            raw = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                self.live_url = validate_kwai_live_url(raw.get("live_url", ""))
                self.configured = bool(self.live_url)

    @property
    def target_url(self) -> str:
        if self.live_url:
            return self.live_url
        if self.default_account:
            return f"https://www.kwai.com/@{self.default_account}"
        return ""

    @property
    def value(self) -> dict[str, Any]:
        return {
            "live_url": self.live_url,
            "target_url": self.target_url,
            "configured": self.configured,
        }

    def update(self, raw_url: Any) -> dict[str, Any]:
        clean_url = validate_kwai_live_url(raw_url)
        payload = {"live_url": clean_url}
        if self.path is not None:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temp = self.path.with_suffix(".tmp")
            with temp.open("w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp, self.path)
        self.live_url = clean_url
        self.configured = bool(clean_url)
        return self.value
