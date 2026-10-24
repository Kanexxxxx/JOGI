"""Optional CDN image cache. No arbitrary hosts, redirects, credentials or P0 waits.

Names are URL hashes; provenance records include the actual byte SHA256. Files are
private local derived copies of metadata supplied by the platform, not an official
preloaded catalog. Missing/untrusted/oversized images simply keep the generic icon.
"""
from __future__ import annotations

import asyncio
import hashlib
import ipaddress
import json
import pathlib
import re
import socket
import struct
import time
from typing import Any
import urllib.error
import urllib.parse
import urllib.request

MAX_IMAGE_BYTES = 1_048_576
MAX_CACHE_IMAGES = 256
MAX_SOURCE_PIXELS = 4096
CDN_SUFFIXES = ("tiktokcdn.com", "tiktokcdn-us.com", "tiktokcdn-eu.com",
                "byteoversea.com", "ibytedtos.com", "byteimg.com", "kwimgs.com", "kwai.net")
ICON_RE = re.compile(r"^/gift-icons/([a-f0-9]{64})$")


def safe_gift_image_url(value: Any) -> str | None:
    if not isinstance(value, str) or not 1 <= len(value) <= 2048 or any(ord(c) < 33 for c in value):
        return None
    try:
        parts = urllib.parse.urlsplit(value)
        host = (parts.hostname or "").lower()
        if (parts.scheme != "https" or parts.port not in (None, 443) or parts.username
                or parts.password or parts.fragment or not parts.path.startswith("/")
                or not any(host == suffix or host.endswith("." + suffix) for suffix in CDN_SUFFIXES)):
            return None
    except ValueError:
        return None
    return value


def safe_icon_path(value: Any) -> str | None:
    return value if isinstance(value, str) and ICON_RE.fullmatch(value) else None


def extract_gift_image(value: Any) -> str | None:
    """Read SDK Image.url_list or equivalent public metadata, never arbitrary objects."""
    if isinstance(value, str):
        return safe_gift_image_url(value)
    if isinstance(value, dict):
        values = value.get("url_list") or value.get("urls") or [value.get("url")]
    else:
        values = getattr(value, "url_list", None) or getattr(value, "urls", None) or [getattr(value, "url", None)]
    if not isinstance(values, (list, tuple)):
        values = [values]
    return next((url for item in values[:8] if (url := safe_gift_image_url(item))), None)


def image_info(data: bytes) -> tuple[str, int, int]:
    if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24:
        width, height = struct.unpack(">II", data[16:24]); mime = "image/png"
    elif data.startswith(b"RIFF") and data[8:12] == b"WEBP" and len(data) >= 30:
        chunk = data[12:16]; mime = "image/webp"
        if chunk == b"VP8X":
            width = 1 + int.from_bytes(data[24:27], "little"); height = 1 + int.from_bytes(data[27:30], "little")
        elif chunk == b"VP8 " and data[23:26] == b"\x9d\x01\x2a":
            width, height = struct.unpack("<HH", data[26:30]); width &= 0x3fff; height &= 0x3fff
        elif chunk == b"VP8L" and data[20] == 0x2f:
            bits = int.from_bytes(data[21:25], "little"); width = (bits & 0x3fff) + 1; height = ((bits >> 14) & 0x3fff) + 1
        else:
            raise ValueError("Unsupported WebP dimensions")
    elif data.startswith(b"\xff\xd8"):
        mime = "image/jpeg"; cursor = 2; width = height = 0
        while cursor + 4 < len(data):
            if data[cursor] != 0xff: break
            marker = data[cursor + 1]; cursor += 2
            while marker == 0xff and cursor < len(data): marker = data[cursor]; cursor += 1
            if marker in (0xd8, 0xd9, 0x01) or 0xd0 <= marker <= 0xd7: continue
            size = int.from_bytes(data[cursor:cursor + 2], "big")
            if size < 2: break
            if marker in (0xc0, 0xc1, 0xc2) and cursor + 7 <= len(data):
                height, width = struct.unpack(">HH", data[cursor + 3:cursor + 7]); break
            cursor += size
    else:
        raise ValueError("Unsupported image signature")
    if not 0 < width <= MAX_SOURCE_PIXELS or not 0 < height <= MAX_SOURCE_PIXELS:
        raise ValueError("Image dimensions outside bounds")
    return mime, width, height


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> None:
        return None


def download_image(url: str) -> tuple[bytes, dict[str, Any]]:
    if not safe_gift_image_url(url): raise ValueError("Untrusted image URL")
    hostname = urllib.parse.urlsplit(url).hostname
    addresses = socket.getaddrinfo(hostname, 443, type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
        raise ValueError("Non-public CDN address")
    opener = urllib.request.build_opener(_NoRedirect(), urllib.request.ProxyHandler({}))
    request = urllib.request.Request(url, headers={"User-Agent": "JOGI-local-gift-icons/1.0", "Accept": "image/png,image/jpeg,image/webp"})
    with opener.open(request, timeout=5.0) as response:
        declared = response.headers.get("Content-Length")
        if declared and int(declared) > MAX_IMAGE_BYTES: raise ValueError("Image too large")
        data = response.read(MAX_IMAGE_BYTES + 1)
    if len(data) > MAX_IMAGE_BYTES: raise ValueError("Image too large")
    mime, width, height = image_info(data)
    return data, {"source_url": url, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                  "content_type": mime, "width": width, "height": height, "downloaded_at_ms": int(time.time() * 1000)}


class GiftImageCache:
    def __init__(self, directory: pathlib.Path | None) -> None:
        self.directory = directory
        self.ready: dict[str, dict[str, Any]] = {}
        self.pending: set[str] = set()
        self.attempted: set[str] = set()
        self.tasks: set[asyncio.Task[Any]] = set()
        self._last_download = 0.0
        self._lock: asyncio.Lock | None = None
        if directory is not None:
            directory.mkdir(parents=True, exist_ok=True)
            for manifest in sorted(directory.glob("*.json"))[:MAX_CACHE_IMAGES]:
                key = manifest.stem
                if not re.fullmatch("[a-f0-9]{64}", key): continue
                try:
                    metadata = json.loads(manifest.read_text("utf-8")); data = (directory / key).read_bytes()
                    if len(data) <= MAX_IMAGE_BYTES and hashlib.sha256(data).hexdigest() == metadata["sha256"]:
                        mime, _, _ = image_info(data)
                        if safe_gift_image_url(metadata.get("source_url")) and metadata.get("content_type") == mime:
                            self.ready[key] = metadata
                except (OSError, ValueError, KeyError, TypeError):
                    continue

    def request(self, url: Any) -> str | None:
        url = safe_gift_image_url(url)
        if not url or self.directory is None: return None
        key = hashlib.sha256(url.encode("utf-8")).hexdigest()
        if key in self.ready or key in self.pending: return "/gift-icons/" + key
        if key in self.attempted or len(self.attempted | self.ready.keys()) >= MAX_CACHE_IMAGES: return None
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            return None
        self.pending.add(key); self.attempted.add(key)
        task = loop.create_task(self._download(key, url)); self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)
        return "/gift-icons/" + key

    async def _download(self, key: str, url: str) -> None:
        if self._lock is None: self._lock = asyncio.Lock()
        try:
            async with self._lock:
                await asyncio.sleep(max(0.0, 0.5 - (time.monotonic() - self._last_download)))
                self._last_download = time.monotonic()
                data, metadata = await asyncio.to_thread(download_image, url)
                self._last_download = time.monotonic()
                if self.directory is None: return
                image_file = self.directory / key; temp_file = self.directory / (key + ".tmp")
                await asyncio.to_thread(temp_file.write_bytes, data); temp_file.replace(image_file)
                metadata_file = self.directory / (key + ".json")
                await asyncio.to_thread(metadata_file.write_text, json.dumps(metadata, ensure_ascii=False), "utf-8")
                self.ready[key] = metadata
        except (OSError, ValueError, urllib.error.URLError):
            pass
        finally:
            self.pending.discard(key)

    def get(self, path: str) -> tuple[bytes, str] | None:
        if not safe_icon_path(path) or self.directory is None: return None
        key = path.rsplit("/", 1)[1]; metadata = self.ready.get(key)
        if metadata is None: return None
        try:
            data = (self.directory / key).read_bytes()
            if len(data) <= MAX_IMAGE_BYTES and hashlib.sha256(data).hexdigest() == metadata["sha256"]:
                return data, metadata["content_type"]
        except OSError:
            pass
        return None

    async def stop(self) -> None:
        for task in tuple(self.tasks): task.cancel()
        if self.tasks: await asyncio.gather(*self.tasks, return_exceptions=True)
        self.tasks.clear()
        self.pending.clear()
