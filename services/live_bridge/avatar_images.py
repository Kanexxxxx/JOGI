"""Ephemeral, anti-SSRF viewer avatar cache for transient HUD interaction cards.

Security & Privacy guarantees:
- Accepts ONLY official HTTPS CDN suffixes (TikTok / Kwai) with DNS-pinned public IP fetch.
- Zero redirects, zero cookies, max 512 KiB, max 2048x2048 source dimensions, strict PNG/JPEG/WebP header check.
- Bounded LRU (max 128 cached avatars) and automatic 6-hour TTL cleanup.
- Never persists user_id, display_name, or signed CDN URLs on disk; Godot fetches only opaque `/viewer-avatars/<sha256>`.
- Can be disabled completely via `LIVE_AVATARS_ENABLED=0`.
"""
from __future__ import annotations

import asyncio
from collections import OrderedDict
import hashlib
import http.client
import json
import os
import pathlib
import re
import time
from typing import Any
import urllib.error

from gift_images import fetch_pinned_cdn_bytes, image_info, safe_cdn_image_url

MAX_AVATAR_BYTES = 524_288  # 512 KiB
MAX_CACHE_AVATARS = 128
MAX_AVATAR_PIXELS = 2048
AVATAR_TTL_SECONDS = 21_600.0  # 6 hours ephemeral retention
AVATAR_RE = re.compile(r"^/viewer-avatars/([a-f0-9]{64})$")


def avatars_enabled_from_env() -> bool:
    raw = os.environ.get("LIVE_AVATARS_ENABLED", "1").strip().lower()
    return raw not in ("0", "false", "no", "off")


def safe_avatar_url(value: Any) -> str | None:
    return safe_cdn_image_url(value)


def safe_avatar_path(value: Any) -> str | None:
    return value if isinstance(value, str) and AVATAR_RE.fullmatch(value) else None


def extract_avatar_url(value: Any) -> str | None:
    """Extract official CDN avatar URL from SDK User / collector payload, ignoring untrusted hosts."""
    if value is None:
        return None
    if isinstance(value, str):
        return safe_avatar_url(value)
    candidates: list[Any] = []
    if isinstance(value, dict):
        for field in ("avatar_url", "avatarUrl", "headUrl", "profile_pic_url", "avatar_thumb", "avatar_medium", "avatar"):
            if field in value and value[field] is not None:
                candidates.append(value[field])
        if "url_list" in value or "urls" in value or "url" in value:
            candidates.append(value)
    else:
        for field in ("avatar_thumb", "avatar_medium", "avatar_large", "avatar_url", "avatar"):
            attr = getattr(value, field, None)
            if attr is not None:
                candidates.append(attr)
    for item in candidates[:6]:
        if isinstance(item, str):
            url = safe_avatar_url(item)
            if url:
                return url
        elif isinstance(item, dict):
            urls = item.get("url_list") or item.get("urls") or [item.get("url")]
            if isinstance(urls, (list, tuple)):
                for raw in urls[:6]:
                    url = safe_avatar_url(raw)
                    if url:
                        return url
        else:
            urls = getattr(item, "url_list", None) or getattr(item, "urls", None) or [getattr(item, "url", None)]
            if isinstance(urls, (list, tuple)):
                for raw in urls[:6]:
                    url = safe_avatar_url(raw)
                    if url:
                        return url
    return None


def download_avatar(url: str) -> tuple[bytes, dict[str, Any]]:
    data = fetch_pinned_cdn_bytes(
        url,
        max_bytes=MAX_AVATAR_BYTES,
        user_agent="JOGI-local-viewer-avatars/1.0",
        timeout=4.0,
    )
    mime, width, height = image_info(data, max_pixels=MAX_AVATAR_PIXELS)
    return data, {
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
        "content_type": mime,
        "width": width,
        "height": height,
        "downloaded_at_ms": int(time.time() * 1000),
    }


class AvatarImageCache:
    def __init__(self, directory: pathlib.Path | None, *, enabled: bool | None = None) -> None:
        self.directory = directory
        self.enabled = avatars_enabled_from_env() if enabled is None else bool(enabled)
        self.ready: OrderedDict[str, dict[str, Any]] = OrderedDict()
        self.memory_blobs: dict[str, bytes] = {}
        self.pending: set[str] = set()
        self.failed_until: OrderedDict[str, float] = OrderedDict()
        self.tasks: set[asyncio.Task[Any]] = set()
        self._last_download = 0.0
        self._lock: asyncio.Lock | None = None
        if self.directory is not None and self.enabled:
            self.directory.mkdir(parents=True, exist_ok=True)
            self._load_and_prune_disk()

    def _is_expired(self, metadata: dict[str, Any], now_ms: int) -> bool:
        downloaded_ms = int(metadata.get("downloaded_at_ms", 0))
        return downloaded_ms <= 0 or (now_ms - downloaded_ms) > int(AVATAR_TTL_SECONDS * 1000)

    def _remove_disk_entry(self, key: str) -> None:
        if self.directory is None:
            return
        for suffix in ("", ".json", ".tmp"):
            try:
                (self.directory / f"{key}{suffix}").unlink(missing_ok=True)
            except OSError:
                pass

    def _load_and_prune_disk(self) -> None:
        if self.directory is None:
            return
        now_ms = int(time.time() * 1000)
        for manifest in sorted(self.directory.glob("*.json")):
            key = manifest.stem
            if not re.fullmatch("[a-f0-9]{64}", key):
                continue
            try:
                metadata = json.loads(manifest.read_text("utf-8"))
                if self._is_expired(metadata, now_ms):
                    self._remove_disk_entry(key)
                    continue
                data = (self.directory / key).read_bytes()
                if len(data) <= MAX_AVATAR_BYTES and hashlib.sha256(data).hexdigest() == metadata["sha256"]:
                    mime, _, _ = image_info(data, max_pixels=MAX_AVATAR_PIXELS)
                    if metadata.get("content_type") == mime:
                        self.ready[key] = metadata
                        continue
            except (OSError, ValueError, KeyError, TypeError):
                pass
            self._remove_disk_entry(key)
        self._enforce_bounds()

    def _enforce_bounds(self) -> None:
        while len(self.ready) > MAX_CACHE_AVATARS:
            evicted_key, _ = self.ready.popitem(last=False)
            self.memory_blobs.pop(evicted_key, None)
            self._remove_disk_entry(evicted_key)
        while len(self.failed_until) > MAX_CACHE_AVATARS * 2:
            self.failed_until.popitem(last=False)

    def request(self, url: Any) -> str | None:
        if not self.enabled:
            return None
        clean_url = safe_avatar_url(url)
        if not clean_url:
            return None
        key = hashlib.sha256(clean_url.encode("utf-8")).hexdigest()
        now = time.monotonic()
        if key in self.ready:
            now_ms = int(time.time() * 1000)
            if not self._is_expired(self.ready[key], now_ms):
                self.ready.move_to_end(key)
                return "/viewer-avatars/" + key
            self.ready.pop(key, None)
            self.memory_blobs.pop(key, None)
            self._remove_disk_entry(key)
        if key in self.pending:
            return "/viewer-avatars/" + key
        retry_after = self.failed_until.get(key, 0.0)
        if retry_after > now or len(self.pending) >= 32:
            return None
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            return None
        self.pending.add(key)
        task = loop.create_task(self._download(key, clean_url))
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)
        return "/viewer-avatars/" + key

    async def _download(self, key: str, url: str) -> None:
        if self._lock is None:
            self._lock = asyncio.Lock()
        try:
            async with self._lock:
                await asyncio.sleep(max(0.0, 0.25 - (time.monotonic() - self._last_download)))
                self._last_download = time.monotonic()
                data, metadata = await asyncio.to_thread(download_avatar, url)
                self._last_download = time.monotonic()
                if not self.enabled:
                    return
                if self.directory is not None:
                    image_file = self.directory / key
                    temp_file = self.directory / (key + ".tmp")
                    await asyncio.to_thread(temp_file.write_bytes, data)
                    temp_file.replace(image_file)
                    metadata_file = self.directory / (key + ".json")
                    await asyncio.to_thread(metadata_file.write_text, json.dumps(metadata, ensure_ascii=False), "utf-8")
                else:
                    self.memory_blobs[key] = data
                self.ready[key] = metadata
                self.ready.move_to_end(key)
                self.failed_until.pop(key, None)
                self._enforce_bounds()
        except (OSError, ValueError, urllib.error.URLError, http.client.HTTPException):
            self.failed_until[key] = time.monotonic() + 120.0
            self._enforce_bounds()
        finally:
            self.pending.discard(key)

    def get(self, path: str) -> tuple[bytes, str] | None:
        if not self.enabled or not safe_avatar_path(path):
            return None
        key = path.rsplit("/", 1)[1]
        metadata = self.ready.get(key)
        if metadata is None:
            return None
        if self._is_expired(metadata, int(time.time() * 1000)):
            self.ready.pop(key, None)
            self.memory_blobs.pop(key, None)
            self._remove_disk_entry(key)
            return None
        try:
            data = self.memory_blobs[key] if self.directory is None else (self.directory / key).read_bytes()
            if len(data) <= MAX_AVATAR_BYTES and hashlib.sha256(data).hexdigest() == metadata["sha256"]:
                self.ready.move_to_end(key)
                return data, metadata["content_type"]
        except (OSError, KeyError):
            pass
        return None

    def stats(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "ready": len(self.ready),
            "pending": len(self.pending),
            "max_avatars": MAX_CACHE_AVATARS,
            "ttl_seconds": int(AVATAR_TTL_SECONDS),
        }

    async def stop(self) -> None:
        for task in tuple(self.tasks):
            task.cancel()
        if self.tasks:
            await asyncio.gather(*self.tasks, return_exceptions=True)
        self.tasks.clear()
        self.pending.clear()
