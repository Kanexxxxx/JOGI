"""Tests for simultaneous 3-goal persistence, anti-SSRF avatar cache, DNS pinning, and local/producer auth."""

from __future__ import annotations

import asyncio
import hashlib
import json
from pathlib import Path
import struct
import time
from typing import Any
from unittest.mock import patch
import urllib.error
import urllib.parse
import urllib.request
import zlib

import pytest
import websockets

import avatar_images
import gift_images
from adapters.kwai_adapter import KwaiAdapterConfig, KwaiLiveAdapter
from live_goal import LiveGoalSettings
from protocol import ProtocolValidationError, build_admin_command_envelope, build_gift_envelope, build_vote_envelope
from server import LiveBridgeServer


def _make_png(width: int = 32, height: int = 32) -> bytes:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(kind + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    raw = b"".join(b"\x00" + (b"\x10\x80\xf0\xff" * width) for _ in range(height))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


async def _http_get_or_post(req_or_url: str | urllib.request.Request) -> tuple[int, dict[str, str], bytes]:
    def _sync() -> tuple[int, dict[str, str], bytes]:
        try:
            with urllib.request.urlopen(req_or_url, timeout=3) as resp:
                return int(resp.status), dict(resp.headers.items()), resp.read()
        except urllib.error.HTTPError as err:
            return int(err.code), dict(err.headers.items()), err.read()

    return await asyncio.to_thread(_sync)


def test_dns_pinning_blocks_private_loopback_and_rebinding() -> None:
    for blocked_ip in ("127.0.0.1", "::1", "10.0.0.5", "192.168.1.10", "169.254.169.254", "224.0.0.1"):
        with patch(
            "gift_images.socket.getaddrinfo",
            return_value=[(2, 1, 6, "", (blocked_ip, 443))],
        ):
            with pytest.raises(ValueError, match="Non-public CDN address"):
                gift_images.resolve_verified_public_ip("p16-sign-va.tiktokcdn.com")

    png = _make_png(16, 16)
    captured_pinned: list[tuple[str, str]] = []

    class FakeResponse:
        status = 200

        def getheader(self, name: str) -> str | None:
            return str(len(png)) if name == "Content-Length" else None

        def read(self, _limit: int) -> bytes:
            return png

    class FakePinnedConn:
        def __init__(self, hostname: str, pinned_ip: str, *, timeout: float = 5.0) -> None:
            captured_pinned.append((hostname, pinned_ip))

        def request(self, method: str, path: str, headers: dict[str, str]) -> None:
            assert method == "GET"
            assert headers["Host"] == "p16-sign-va.tiktokcdn.com"

        def getresponse(self) -> FakeResponse:
            return FakeResponse()

        def close(self) -> None:
            pass

    with (
        patch("gift_images.socket.getaddrinfo", return_value=[(2, 1, 6, "", ("23.50.10.20", 443))]),
        patch("gift_images._PinnedHTTPSConnection", FakePinnedConn),
    ):
        body = gift_images.fetch_pinned_cdn_bytes(
            "https://p16-sign-va.tiktokcdn.com/avatar/user1.png",
            max_bytes=65536,
            user_agent="test-agent/1.0",
        )
    assert body == png
    assert captured_pinned == [("p16-sign-va.tiktokcdn.com", "23.50.10.20")]


@pytest.mark.asyncio
async def test_avatar_cache_privacy_bounds_ttl_and_disable_flag(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    assert avatar_images.safe_avatar_url("http://p16-sign-va.tiktokcdn.com/a.png") is None
    assert avatar_images.safe_avatar_url("https://evil.example.com/a.png") is None
    assert avatar_images.safe_avatar_url("https://user:pass@p16-sign-va.tiktokcdn.com/a.png") is None
    assert avatar_images.safe_avatar_url("https://p16-sign-va.tiktokcdn.com/a.png#frag") is None

    extracted = avatar_images.extract_avatar_url(
        {"avatar_thumb": {"url_list": ["https://evil.invalid/x.png", "https://p16-sign-va.tiktokcdn.com/u/pic.png"]}}
    )
    assert extracted == "https://p16-sign-va.tiktokcdn.com/u/pic.png"

    png = _make_png(48, 48)
    monkeypatch.setattr(
        avatar_images,
        "download_avatar",
        lambda _url: (
            png,
            {
                "sha256": hashlib.sha256(png).hexdigest(),
                "bytes": len(png),
                "content_type": "image/png",
                "width": 48,
                "height": 48,
                "downloaded_at_ms": int(time.time() * 1000),
            },
        ),
    )

    cache_dir = tmp_path / "viewer-avatars"
    cache = avatar_images.AvatarImageCache(cache_dir, enabled=True)
    path = cache.request("https://p16-sign-va.tiktokcdn.com/u/pic.png?x-expires=99999&sig=secret")
    assert path is not None and path.startswith("/viewer-avatars/")
    await asyncio.gather(*tuple(cache.tasks))

    served = cache.get(path)
    assert served == (png, "image/png")

    # Verify zero PII or signed source_url is stored in disk manifests
    manifests = list(cache_dir.glob("*.json"))
    assert len(manifests) == 1
    manifest_text = manifests[0].read_text(encoding="utf-8")
    assert "source_url" not in manifest_text
    assert "sig=secret" not in manifest_text

    # Verify TTL expiration purges stale entries on disk reload
    expired_meta = json.loads(manifest_text)
    expired_meta["downloaded_at_ms"] = int((time.time() - avatar_images.AVATAR_TTL_SECONDS - 60) * 1000)
    manifests[0].write_text(json.dumps(expired_meta), encoding="utf-8")
    reloaded = avatar_images.AvatarImageCache(cache_dir, enabled=True)
    assert reloaded.get(path) is None
    assert list(cache_dir.glob("*.json")) == []

    # Verify LIVE_AVATARS_ENABLED=0 disables avatar requests completely
    monkeypatch.setenv("LIVE_AVATARS_ENABLED", "0")
    disabled_cache = avatar_images.AvatarImageCache(cache_dir)
    assert disabled_cache.enabled is False
    assert disabled_cache.request("https://p16-sign-va.tiktokcdn.com/u/pic2.png") is None


def test_live_goal_settings_simultaneous_three_goals_and_legacy_compat(tmp_path: Path) -> None:
    goal_file = tmp_path / "live_goal.json"
    settings = LiveGoalSettings(goal_file)
    snap = settings.snapshot_goals()
    assert snap["likes"]["goal_target"] == 1000
    assert snap["gifts"]["goal_target"] == 500
    assert snap["follows"]["goal_target"] == 10000
    assert snap["follows"]["follower_baseline"] is None

    # Configure 3 simultaneous goals with manual follower baseline and specific gift ID
    env = build_admin_command_envelope(
        command="set_live_goals",
        live_goals={
            "likes": {"goal_kind": "likes", "goal_target": 2500, "goal_label": "Meta Curtidas"},
            "gifts": {
                "goal_kind": "gift_specific",
                "goal_target": 150,
                "goal_label": "Meta Rosas",
                "goal_gift_id": "5655",
            },
            "follows": {
                "goal_kind": "follows",
                "goal_target": 10000,
                "goal_label": "Rumo a 10K",
                "follower_baseline": 8420,
            },
        },
    )
    settings.update_goals(env)
    assert (tmp_path / "live_goals.json").exists()

    reloaded = LiveGoalSettings(goal_file)
    assert reloaded.multi_configured is True
    goals = reloaded.snapshot_goals()
    assert goals["likes"]["goal_target"] == 2500
    assert goals["gifts"]["goal_kind"] == "gift_specific"
    assert goals["gifts"]["goal_gift_id"] == "5655"
    assert goals["follows"]["goal_target"] == 10000
    assert goals["follows"]["follower_baseline"] == 8420
    assert goals["follows"]["baseline_updated_at"] is not None

    # Legacy set_live_goal updates its corresponding slot without wiping the other 2 goals
    legacy_env = build_admin_command_envelope(
        command="set_live_goal",
        goal_kind="coins",
        goal_target=5000,
        goal_label="Meta Moedas",
    )
    reloaded.update(legacy_env)
    merged = reloaded.snapshot_goals()
    assert merged["gifts"]["goal_kind"] == "coins"
    assert merged["gifts"]["goal_target"] == 5000
    assert merged["likes"]["goal_target"] == 2500
    assert merged["follows"]["follower_baseline"] == 8420

    # Invalid specific gift without ID fails validation
    with pytest.raises(ProtocolValidationError):
        build_admin_command_envelope(
            command="set_live_goals",
            live_goals={
                "likes": {"goal_kind": "likes", "goal_target": 100, "goal_label": "Likes"},
                "gifts": {"goal_kind": "gift_specific", "goal_target": 10, "goal_label": "Sem ID"},
                "follows": {"goal_kind": "follows", "goal_target": 10000, "goal_label": "10K"},
            },
        )


@pytest.mark.asyncio
async def test_avatar_url_stripped_before_godot_and_outbox(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    png = _make_png(32, 32)
    monkeypatch.setattr(
        avatar_images,
        "download_avatar",
        lambda _url: (
            png,
            {
                "sha256": hashlib.sha256(png).hexdigest(),
                "bytes": len(png),
                "content_type": "image/png",
                "width": 32,
                "height": 32,
                "downloaded_at_ms": int(time.time() * 1000),
            },
        ),
    )

    server = LiveBridgeServer(runtime_mode="development",
        host="127.0.0.1",
        port=0,
        platform="tiktok",
        outbox_path=tmp_path / "outbox.sqlite3",
    )
    await server.start()
    try:
        async with websockets.connect(f"ws://127.0.0.1:{server.bound_port}/ws/godot") as godot_ws:
            vote = build_vote_envelope(
                source="tiktok",
                candidate_slot=1,
                user_id="viewer_99",
                display_name="Maria Silva",
                avatar_url="https://p16-sign-va.tiktokcdn.com/tos-maliva-avt/maria.png?sig=private",
            )
            gift = build_gift_envelope(
                source="tiktok",
                candidate_slot=None,
                gift_name="Rosa",
                unit_coin_value=5,
                gift_id="5655",
                user_id="viewer_99",
                display_name="Maria Silva",
                avatar_url="https://p16-sign-va.tiktokcdn.com/tos-maliva-avt/maria.png?sig=private",
            )
            assert server.enqueue_envelope(vote) == "accepted"
            assert server.enqueue_envelope(gift) == "accepted"

            received: list[dict[str, Any]] = []
            deadline = time.monotonic() + 3.0
            while len(received) < 2 and time.monotonic() < deadline:
                raw = await asyncio.wait_for(godot_ws.recv(), timeout=2.0)
                pkt = json.loads(raw)
                if pkt.get("event_type") in ("vote", "gift"):
                    received.append(pkt)
                    if pkt["event_type"] == "gift":
                        await godot_ws.send(json.dumps({"type": "event_ack", "event_id": pkt["event_id"]}))

            assert len(received) == 2
            for pkt in received:
                assert "avatar_url" not in pkt["payload"]
                assert pkt["payload"]["avatar_icon_path"].startswith("/viewer-avatars/")
    finally:
        await server.stop()


@pytest.mark.asyncio
async def test_local_token_protects_admin_cookie_ws_and_producers(tmp_path: Path) -> None:
    server = LiveBridgeServer(runtime_mode="development",
        host="127.0.0.1",
        port=0,
        platform="tiktok",
        outbox_path=tmp_path / "outbox.sqlite3",
        local_token="op-secret-2026",
    )
    await server.start()
    port = server.bound_port
    base = f"http://127.0.0.1:{port}"
    try:
        # /health is reachable and advertises auth mode without leaking secret
        status, _, body = await _http_get_or_post(f"{base}/health")
        assert status == 200
        health = json.loads(body.decode("utf-8"))
        assert health["auth_mode"] == "local_token"
        assert "op-secret-2026" not in json.dumps(health)

        # Unauthenticated /api/state and POST /api/admin/command must return 401
        st_unauth, _, _ = await _http_get_or_post(f"{base}/api/state")
        assert st_unauth == 401

        cmd_req = urllib.request.Request(
            f"{base}/api/admin/command?command=pause_race",
            data=b"",
            headers={"Origin": base},
            method="POST",
        )
        cmd_unauth, _, _ = await _http_get_or_post(cmd_req)
        assert cmd_unauth == 401

        # Unauthenticated WebSockets must be rejected with HTTP 401
        for route in ("/ws/admin", "/ws/godot", "/ws/ingest"):
            with pytest.raises(Exception):
                async with websockets.connect(f"ws://127.0.0.1:{port}{route}"):
                    pass

        # Exchange X-JOGI-Token at GET /api/admin/session for HttpOnly cookie
        sess_req = urllib.request.Request(
            f"{base}/api/admin/session",
            headers={"X-JOGI-Token": "op-secret-2026", "Origin": base},
            method="GET",
        )
        sess_status, sess_headers, sess_raw = await _http_get_or_post(sess_req)
        assert sess_status == 200
        set_cookie = sess_headers.get("Set-Cookie") or sess_headers.get("set-cookie", "")
        sess_body = json.loads(sess_raw.decode("utf-8"))
        assert sess_body["authenticated"] is True
        assert "HttpOnly" in set_cookie and "SameSite=Strict" in set_cookie
        cookie_pair = set_cookie.split(";", 1)[0]

        # Cookie authorizes /api/state, /api/admin/command (set_live_goals), and /ws/admin
        state_req = urllib.request.Request(f"{base}/api/state", headers={"Cookie": cookie_pair})
        st_ok, _, st_raw = await _http_get_or_post(state_req)
        assert st_ok == 200
        state_json = json.loads(st_raw.decode("utf-8"))
        assert state_json["status"] == "ok"
        assert "live_goals" in state_json

        goals_dict = {
            "likes": {"goal_kind": "likes", "goal_target": 1500, "goal_label": "Curtidas"},
            "gifts": {"goal_kind": "gifts", "goal_target": 300, "goal_label": "Presentes"},
            "follows": {"goal_kind": "follows", "goal_target": 10000, "goal_label": "Seguidores"},
        }
        qs = urllib.parse.urlencode({"command": "set_live_goals", "live_goals": json.dumps(goals_dict)})
        goals_req = urllib.request.Request(
            f"{base}/api/admin/command?{qs}",
            data=b"",
            headers={"Origin": base, "Cookie": cookie_pair},
            method="POST",
        )
        goals_status, _, goals_raw = await _http_get_or_post(goals_req)
        assert goals_status == 200
        assert json.loads(goals_raw.decode("utf-8"))["status"] == "queued"

        # Producer channel /ws/godot connects with X-JOGI-Token and receives synced set_live_goals
        async with websockets.connect(
            f"ws://127.0.0.1:{port}/ws/godot",
            additional_headers={"X-JOGI-Token": "op-secret-2026"},
        ) as godot_ws:
            initial_cmds: list[str] = []
            for _ in range(3):
                try:
                    msg = json.loads(await asyncio.wait_for(godot_ws.recv(), timeout=1.0))
                    if msg.get("event_type") == "admin_command":
                        initial_cmds.append(msg["payload"]["command"])
                except asyncio.TimeoutError:
                    break
            assert "set_live_goals" in initial_cmds
    finally:
        await server.stop()


@pytest.mark.asyncio
async def test_producer_token_protects_godot_ingest_and_kwai_webhook_while_admin_stays_loopback(tmp_path: Path) -> None:
    server = LiveBridgeServer(runtime_mode="development",
        host="127.0.0.1",
        port=0,
        platform="kwai",
        outbox_path=tmp_path / "kwai_outbox.sqlite3",
        kwai_webhook_port=0,
        producer_token="ephemeral-prod-777",
    )
    await server.start()
    await server.start_live_listener()
    adapter = server._live_adapter
    try:
        # Loopback admin works without manual token prompt when only producer_token is active
        sess_code, _, sess_raw = await _http_get_or_post(f"http://127.0.0.1:{server.bound_port}/api/admin/session")
        assert sess_code == 200
        assert json.loads(sess_raw.decode("utf-8"))["authenticated"] is True
        st_code, _, st_raw = await _http_get_or_post(f"http://127.0.0.1:{server.bound_port}/api/state")
        assert st_code == 200
        state = json.loads(st_raw.decode("utf-8"))
        assert state["auth_mode"] == "producer_token"
        assert state["kwai_collector"]["webhook_auth_required"] is True

        # Unauthenticated /ws/godot and Kwai webhook POST are rejected
        with pytest.raises(Exception):
            async with websockets.connect(f"ws://127.0.0.1:{server.bound_port}/ws/godot"):
                pass

        unauth_webhook = urllib.request.Request(
            f"http://127.0.0.1:{adapter.bound_port}/webhook/kwai",
            data=json.dumps({"type": "comment", "user_id": "u1", "display_name": "Ana", "comment": "13"}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        wh_unauth_code, _, _ = await _http_get_or_post(unauth_webhook)
        assert wh_unauth_code == 401

        # Authenticated Kwai webhook + authenticated /ws/godot succeed end-to-end
        async with websockets.connect(
            f"ws://127.0.0.1:{server.bound_port}/ws/godot",
            additional_headers={"X-JOGI-Token": "ephemeral-prod-777"},
        ) as godot_ws:
            auth_webhook = urllib.request.Request(
                f"http://127.0.0.1:{adapter.bound_port}/webhook/kwai",
                data=json.dumps(
                    {
                        "type": "comment",
                        "event_id": "kw_evt_auth_1",
                        "user_id": "u1",
                        "display_name": "Ana",
                        "comment": "22",
                    }
                ).encode("utf-8"),
                headers={"Content-Type": "application/json", "X-JOGI-Token": "ephemeral-prod-777"},
                method="POST",
            )
            wh_ok_code, _, wh_ok_raw = await _http_get_or_post(auth_webhook)
            assert wh_ok_code == 200
            assert json.loads(wh_ok_raw.decode("utf-8"))["status"] == "ok"

            vote_seen = False
            deadline = time.monotonic() + 3.0
            while time.monotonic() < deadline and not vote_seen:
                pkt = json.loads(await asyncio.wait_for(godot_ws.recv(), timeout=2.0))
                if pkt.get("event_type") == "vote" and pkt["payload"]["candidate_slot"] == 2:
                    vote_seen = True
            assert vote_seen is True
    finally:
        await server.stop()
