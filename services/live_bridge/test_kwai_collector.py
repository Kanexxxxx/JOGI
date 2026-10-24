"""Tests for KwaiLiveAdapter loopback webhook, KwaiCollectorSettings, and Playwright kwai_live_collector.cjs."""
from __future__ import annotations

import asyncio
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

from adapters.kwai_adapter import KwaiAdapterConfig, KwaiLiveAdapter
from kwai_collector_settings import KwaiCollectorSettings, validate_kwai_live_url
from server import LiveBridgeServer


ROOT = Path(__file__).resolve().parents[2]
COLLECTOR_SCRIPT = ROOT / "tools" / "kwai_live_collector.cjs"


def _post_json(url: str, payload: dict, headers: dict[str, str] | None = None) -> tuple[int, dict]:
    raw = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=raw,
        method="POST",
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    with urllib.request.urlopen(req, timeout=4.0) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8"))


class _MockKwaiRoomHandler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        return

    def do_GET(self) -> None:  # noqa: N802
        if self.path.startswith("/api/vod/comments"):
            payload = {
                "data": {
                    "isLiving": False,
                    "comments": [
                        {"id": "vod_cmt_1", "user": {"id": "u_vod_1", "userName": "Gravado"}, "content": "13"}
                    ],
                    "gifts": [],
                }
            }
            raw = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return

        if self.path.startswith("/@mentalista.."):
            html = """<!doctype html>
<html lang="pt-BR">
<head><meta charset="utf-8"><title>Perfil Offline</title></head>
<body>
  <div class="comment-item" data-id="vod_dom_13">
    <span class="author-name">GravadoDOM:</span>
    <span class="msg-content">13</span>
  </div>
  <script>fetch('/api/vod/comments').catch(() => {});</script>
</body>
</html>""".encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)
            return

        if self.path.startswith("/api/live/feed"):
            payload = {
                "data": {
                    "isLiving": True,
                    "commentFeeds": [
                        {"id": "kw_feed_cmt_1", "user": {"id": "u_kw_1", "userName": "CarlaKwai"}, "content": "13"}
                    ],
                    "giftFeeds": [
                        {
                            "id": "kw_feed_gift_1",
                            "user": {"id": "u_kw_1", "userName": "CarlaKwai"},
                            "giftId": "kw_rose_9",
                            "giftName": "Rosa Kwai",
                            "coin_value": 5,
                            "repeat_count": 2,
                        }
                    ],
                    "followFeeds": [
                        {"id": "kw_feed_flw_1", "user": {"id": "u_kw_2", "userName": "MarcosKwai"}}
                    ],
                }
            }
            raw = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return

        html = """<!doctype html>
<html lang="pt-BR">
<head><meta charset="utf-8"><title>Mock Kwai Live</title></head>
<body data-jogi-live-active="true">
  <div class="chat-item" data-id="kw_dom_cmt_22">
    <span class="author-name">PedroKwai:</span>
    <span class="msg-content">22</span>
  </div>
  <script>
    fetch('/api/live/feed').catch(() => {});
  </script>
</body>
</html>""".encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html)))
        self.end_headers()
        self.wfile.write(html)


class KwaiCollectorTests(unittest.IsolatedAsyncioTestCase):
    def test_kwai_url_allowlist_blocks_ssrf_and_accepts_kwai_https(self) -> None:
        self.assertEqual(validate_kwai_live_url(""), "")
        self.assertEqual(
            validate_kwai_live_url("https://www.kwai.com/@mentalista.."),
            "https://www.kwai.com/@mentalista..",
        )
        self.assertEqual(
            validate_kwai_live_url("https://live.kwai.com/u/mentalista?source=share"),
            "https://live.kwai.com/u/mentalista?source=share",
        )
        for forbidden in (
            "http://www.kwai.com/@mentalista..",
            "file:///C:/Windows/System32/drivers/etc/hosts",
            "https://evil.com/@mentalista..",
            "https://kwai.com.evil.com/live",
            "https://user:pass@www.kwai.com/live",
            "https://www.kwai.com:8443/live",
            "https://www.kwai.com/live#frag",
        ):
            with self.assertRaises(ValueError):
                validate_kwai_live_url(forbidden)

        with tempfile.TemporaryDirectory() as folder:
            cfg_path = Path(folder) / "kwai_collector.json"
            settings = KwaiCollectorSettings(cfg_path, default_account="@mentalista..")
            self.assertEqual(settings.target_url, "https://www.kwai.com/@mentalista..")
            settings.update("https://www.kwai.com/live/room123")
            reloaded = KwaiCollectorSettings(cfg_path, default_account="@mentalista..")
            self.assertTrue(reloaded.configured)
            self.assertEqual(reloaded.target_url, "https://www.kwai.com/live/room123")

    async def test_bridge_kwai_listener_honest_status_and_ttl(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            server = LiveBridgeServer(
                port=0,
                platform="kwai",
                account="mentalista..",
                outbox_path=Path(folder) / "gifts.sqlite3",
                kwai_webhook_port=0,
            )
            await server.start()
            try:
                self.assertEqual(server.platform_listener_state()["platform_events_status"], "kwai_requires_collector")
                await server.start_live_listener()
                state = server.platform_listener_state()
                self.assertEqual(state["platform_events_status"], "webhook_listening")
                self.assertFalse(state["platform_events_connected"])
                webhook_url = state["kwai_collector"]["webhook_url"]

                # Waiting room heartbeat does NOT fake connected=True
                code, body = await asyncio.to_thread(
                    _post_json,
                    webhook_url,
                    {"type": "collector_status", "status": "waiting_room", "detail": "Aguardando sala"},
                )
                self.assertEqual(code, 200)
                self.assertFalse(body["ingested"])
                self.assertFalse(server.platform_listener_state()["platform_events_connected"])
                self.assertEqual(server.platform_listener_state()["platform_events_status"], "waiting_room")

                # Active live room heartbeat turns connected=True
                await asyncio.to_thread(
                    _post_json,
                    webhook_url,
                    {"type": "collector_status", "status": "connected", "detail": "Sala ativa"},
                )
                self.assertTrue(server.platform_listener_state()["platform_events_connected"])
                self.assertEqual(server.platform_listener_state()["platform_events_status"], "connected")

                # Cross-origin POST is rejected with 403
                with self.assertRaises(urllib.error.HTTPError) as ctx:
                    await asyncio.to_thread(
                        _post_json,
                        webhook_url,
                        {"type": "comment", "user_id": "x", "comment": "13"},
                        {"Origin": "https://evil.example"},
                    )
                self.assertEqual(ctx.exception.code, 403)

                # TTL expiry returns status to webhook_listening
                server._live_adapter.config.collector_ttl_sec = 0.05
                server._live_adapter._collector_seen_at -= 2.0
                self.assertFalse(server.platform_listener_state()["platform_events_connected"])
                self.assertEqual(server.platform_listener_state()["platform_events_status"], "webhook_listening")

                # Admin HTTP endpoint sets AND resets (blank ?live_url=) custom Kwai URL + serves CSP header on /admin
                base = f"http://127.0.0.1:{server.bound_port}"
                set_res = await asyncio.to_thread(
                    lambda: json.loads(
                        urllib.request.urlopen(
                            f"{base}/api/admin/kwai-collector?live_url=https%3A%2F%2Fwww.kwai.com%2Flive%2Fsala99",
                            timeout=4.0,
                        ).read().decode("utf-8")
                    )
                )
                self.assertTrue(set_res["kwai_collector"]["configured"])
                self.assertEqual(set_res["kwai_collector"]["target_url"], "https://www.kwai.com/live/sala99")

                reset_res = await asyncio.to_thread(
                    lambda: json.loads(
                        urllib.request.urlopen(f"{base}/api/admin/kwai-collector?live_url=", timeout=4.0)
                        .read()
                        .decode("utf-8")
                    )
                )
                self.assertFalse(reset_res["kwai_collector"]["configured"])
                self.assertEqual(reset_res["kwai_collector"]["live_url"], "")
                self.assertEqual(reset_res["kwai_collector"]["target_url"], "https://www.kwai.com/@mentalista..")

                csp_hdr = await asyncio.to_thread(
                    lambda: urllib.request.urlopen(f"{base}/admin", timeout=4.0).headers.get("Content-Security-Policy")
                )
                self.assertIsNotNone(csp_hdr)
                self.assertIn("default-src 'self'", csp_hdr)
            finally:
                await server.stop()

    async def test_playwright_collector_forwards_dom_and_json_events_to_kwai_bridge(self) -> None:
        node_bin = shutil.which("node")
        if not node_bin or not COLLECTOR_SCRIPT.is_file():
            self.skipTest("Node ou kwai_live_collector.cjs indisponível")

        mock_http = HTTPServer(("127.0.0.1", 0), _MockKwaiRoomHandler)
        mock_port = mock_http.server_address[1]
        mock_thread = threading.Thread(target=mock_http.serve_forever, daemon=True)
        mock_thread.start()

        try:
            with tempfile.TemporaryDirectory() as folder:
                tmp_path = Path(folder)
                server = LiveBridgeServer(
                    port=0,
                    platform="kwai",
                    account="mentalista..",
                    outbox_path=tmp_path / "gifts.sqlite3",
                    kwai_webhook_port=0,
                )
                await server.start()
                try:
                    await server.start_live_listener()
                    webhook_url = server.platform_listener_state()["kwai_collector"]["webhook_url"]
                    bridge_url = f"http://127.0.0.1:{server.bound_port}"
                    profile_dir = tmp_path / "profile"

                    proc = await asyncio.to_thread(
                        subprocess.run,
                        [
                            node_bin,
                            str(COLLECTOR_SCRIPT),
                            "--bridge", bridge_url,
                            "--webhook", webhook_url,
                            "--live-url", f"http://127.0.0.1:{mock_port}/live/mentalista",
                            "--profile-dir", str(profile_dir),
                            "--allow-local-test-url",
                            "--once",
                        ],
                        capture_output=True,
                        text=True,
                        timeout=30,
                    )
                    self.assertEqual(proc.returncode, 0, msg=proc.stderr)

                    # Collector must mark room connected, enqueue durable gift in outbox, and enqueue votes/follow in p1_queue
                    state = server.platform_listener_state()
                    self.assertTrue(state["platform_events_connected"])
                    self.assertEqual(state["platform_events_status"], "connected")
                    self.assertEqual(server.outbox.pending_count(), 1)

                    queued = []
                    while not server.p1_queue.empty():
                        queued.append(server.p1_queue.get_nowait())
                    event_types = {item["event_type"] for item in queued}
                    vote_slots = {item["payload"].get("candidate_slot") for item in queued if item["event_type"] == "vote"}
                    self.assertIn("vote", event_types)
                    self.assertIn("follow", event_types)
                    self.assertEqual(vote_slots, {1, 2})

                    # Offline profile with VOD comments + DOM comment-item must stay waiting_room and enqueue zero events
                    offline_proc = await asyncio.to_thread(
                        subprocess.run,
                        [
                            node_bin,
                            str(COLLECTOR_SCRIPT),
                            "--bridge", bridge_url,
                            "--webhook", webhook_url,
                            "--live-url", f"http://127.0.0.1:{mock_port}/@mentalista..",
                            "--profile-dir", str(profile_dir),
                            "--allow-local-test-url",
                            "--once",
                        ],
                        capture_output=True,
                        text=True,
                        timeout=30,
                    )
                    self.assertEqual(offline_proc.returncode, 0, msg=offline_proc.stderr)
                    offline_state = server.platform_listener_state()
                    self.assertFalse(offline_state["platform_events_connected"])
                    self.assertEqual(offline_state["platform_events_status"], "waiting_room")
                    self.assertTrue(server.p1_queue.empty())

                    # Active headed_login.lock yields cleanly without launching/crashing Chromium
                    lock_file = profile_dir.parent / "headed_login.lock"
                    import os
                    lock_file.write_text(json.dumps({"pid": os.getpid(), "started_at": 1}), encoding="utf-8")
                    try:
                        yield_proc = await asyncio.to_thread(
                            subprocess.run,
                            [
                                node_bin,
                                str(COLLECTOR_SCRIPT),
                                "--bridge", bridge_url,
                                "--webhook", webhook_url,
                                "--live-url", f"http://127.0.0.1:{mock_port}/live/mentalista",
                                "--profile-dir", str(profile_dir),
                                "--allow-local-test-url",
                                "--once",
                            ],
                            capture_output=True,
                            text=True,
                            timeout=15,
                        )
                        self.assertEqual(yield_proc.returncode, 0, msg=yield_proc.stderr)
                        self.assertFalse(server.platform_listener_state()["platform_events_connected"])
                        self.assertEqual(server.platform_listener_state()["platform_events_status"], "waiting_room")
                    finally:
                        lock_file.unlink(missing_ok=True)
                finally:
                    await server.stop()
        finally:
            mock_http.shutdown()
            mock_http.server_close()


if __name__ == "__main__":
    unittest.main()
