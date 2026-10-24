"""Production boundaries, honest command receipts, sticky absolute shutdown."""
import asyncio
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen

import pytest
import websockets

from operational_shutdown import OperationalShutdown, normalize_end_at
from protocol import build_admin_command_envelope, build_gift_envelope, build_vote_envelope
from server import LiveBridgeServer


def test_production_is_default_and_real_unknown_gift_is_not_priced(monkeypatch):
    monkeypatch.delenv("JOGI_MODE", raising=False)
    bridge = LiveBridgeServer(port=0)
    try:
        assert bridge.runtime_mode == "production" and not bridge.simulation_allowed
        fake = build_gift_envelope(user_id="fixture", display_name="Fixture", candidate_slot=1)
        assert bridge.enqueue_envelope(fake) == "rejected_production"
        real = build_gift_envelope(user_id="viewer", display_name="Viewer", candidate_slot=None,
                                   source="tiktok", gift_tier="T4")
        assert real["payload"]["coin_value"] == 0
        assert real["payload"]["gift_name"] == "Presente"
        assert bridge.enqueue_envelope(real) == "accepted"
    finally:
        bridge.outbox.close()


def test_deadline_requires_timezone_and_is_sticky_across_restart(tmp_path):
    for invalid in ("2026-10-26T07:00:00", "2026-10-26T07:00-03:00", "2026-10-26 07:00:00-03:00",
                    "2026-10-26T07:00:00.123-03:00", "2026-10-26T07:00:00+12:99",
                    "2026-10-26T07:00:00+14:01", "2026-10-26T07:00:00+15:00", "2026-02-30T07:00:00Z"):
        with pytest.raises(ValueError):
            normalize_end_at(invalid)
    _, cutoff = normalize_end_at("2026-10-26T07:00:00-03:00")
    clock = [cutoff - 1]
    path = tmp_path / "operational_shutdown.json"
    state = OperationalShutdown(path, now=lambda: clock[0])
    assert not state.ended
    clock[0] = cutoff
    assert state.check_deadline()
    assert state.ended and state.reason == "deadline"
    restored = OperationalShutdown(path, end_at="2030-01-01T00:00:00Z", now=lambda: cutoff - 100)
    assert restored.ended
    assert not restored.end("manual")


@pytest.mark.asyncio
async def test_production_blocks_both_simulation_routes_and_offline_race_command():
    bridge = LiveBridgeServer(port=0, runtime_mode="production")
    await bridge.start()
    try:
        def request():
            with pytest.raises(HTTPError) as failure:
                urlopen(f"http://127.0.0.1:{bridge.bound_port}/api/admin/simulate?event_type=gift", timeout=3)
            assert failure.value.code == 403
        await asyncio.to_thread(request)
        async with websockets.connect(f"ws://127.0.0.1:{bridge.bound_port}/ws/admin") as admin:
            await admin.recv()
            await admin.send(json.dumps({"type": "simulate_event", "event_type": "gift"}))
            result = json.loads(await admin.recv())
            assert result["status"] == "rejected"
        assert bridge.enqueue_envelope(build_admin_command_envelope(command="start_race")) == "godot_unavailable"
        assert bridge.outbox.pending_count() == 0
    finally:
        await bridge.stop()


@pytest.mark.asyncio
async def test_command_requires_correlated_godot_result_never_queue_success():
    bridge = LiveBridgeServer(port=0, runtime_mode="production", local_token="operator-fixture",
                             producer_token="producer-fixture")
    await bridge.start()
    try:
        base = f"ws://127.0.0.1:{bridge.bound_port}"
        async with websockets.connect(base + "/ws/godot", additional_headers={"X-JOGI-Token": "producer-fixture"}) as game:
            await game.recv()
            async with websockets.connect(base + "/ws/admin", additional_headers={"X-JOGI-Token": "operator-fixture"}) as admin:
                await admin.recv()
                await admin.send(json.dumps({"type": "admin_command", "command": "pause_race"}))
                receipt = json.loads(await admin.recv())
                assert receipt["status"] == "queued" and receipt["event_id"]
                command = json.loads(await game.recv())
                assert command["event_id"] == receipt["event_id"]
                await game.send(json.dumps({"type": "command_result", "event_id": command["event_id"],
                                            "command": "restart_race", "status": "applied"}))
                await asyncio.sleep(.03)
                assert bridge.recent_commands[command["event_id"]]["status"] == "queued"
                await game.send(json.dumps({"type": "command_result", "event_id": command["event_id"],
                                            "command": "pause_race", "status": "applied"}))
                for _ in range(10):
                    packet = json.loads(await asyncio.wait_for(admin.recv(), timeout=2))
                    if packet.get("type") == "command_result":
                        break
                assert packet["status"] == "applied"
                assert bridge.recent_commands[command["event_id"]]["status"] == "applied"
    finally:
        await bridge.stop()


@pytest.mark.asyncio
async def test_manual_end_retains_paid_events_durably_and_rejects_restart(tmp_path):
    path = tmp_path / "gifts.sqlite3"
    bridge = LiveBridgeServer(port=0, platform="tiktok", runtime_mode="production", outbox_path=path)
    end = build_admin_command_envelope(command="end_experience", event_id="evt_manual_end_fixture")
    assert bridge.enqueue_envelope(end) == "accepted"
    gift = build_gift_envelope(user_id="viewer", display_name="Viewer", source="tiktok", candidate_slot=1,
                               unit_coin_value=5, repeat_count=2, event_id="evt_after_close_fixture")
    assert bridge.enqueue_envelope(gift) == "accepted"
    assert bridge.enqueue_envelope(gift) == "duplicate"
    assert bridge.outbox.pending_count() == 1
    assert bridge._pop_next_priority_envelope()["payload"]["command"] == "end_experience"
    assert bridge._pop_next_priority_envelope() is None
    assert bridge.recent_events[gift["event_id"]]["processing_status"] == "duplicate"
    await bridge.stop()
    restored = LiveBridgeServer(port=0, platform="tiktok", runtime_mode="production", outbox_path=path)
    try:
        assert restored.operational_shutdown.ended
        assert restored.outbox.pending_count() == 1
        assert restored._pop_next_priority_envelope() is None
        assert restored.enqueue_envelope(build_vote_envelope(user_id="v", display_name="V",
            source="tiktok", candidate_slot=1)) == "closed"
    finally:
        await restored.stop()


@pytest.mark.asyncio
async def test_absolute_scheduler_reaches_terminal_and_reports_timeout(tmp_path):
    _, deadline = normalize_end_at("2026-10-26T07:00:00-03:00")
    clock = [deadline - 1]
    bridge = LiveBridgeServer(port=0, runtime_mode="production", outbox_path=tmp_path / "gifts.sqlite3",
                             wall_clock=lambda: clock[0])
    await bridge.start()
    try:
        clock[0] = deadline + 1
        await asyncio.sleep(.6)
        assert bridge.operational_shutdown.ended
        command = next(iter(bridge.recent_commands.values()))
        command["queued_monotonic"] -= 20
        assert bridge._command_snapshot()[0]["status"] == "timeout"
        state = bridge._build_admin_state_payload()
        assert state["operational_shutdown"]["ended"]
        assert not state["operational_shutdown"]["applied"]
    finally:
        await bridge.stop()


@pytest.mark.asyncio
async def test_kwai_explicit_unit_price_precedes_total_including_zero():
    from adapters.kwai_adapter import KwaiLiveAdapter, KwaiAdapterConfig
    adapter = KwaiLiveAdapter(config=KwaiAdapterConfig(enabled=True))
    for unit, total, identity in ((5, 10, "packet-unit-five"), (0, 10, "packet-unit-zero")):
        envelope = await adapter.ingest_raw_event({"type": "gift", "user_id": "viewer",
            "event_id": identity, "display_name": "Viewer", "unit_coin_value": unit,
            "coin_value": total, "repeat_count": 2, "gift_id": "fixture"})
        assert envelope["payload"]["unit_coin_value"] == unit
        assert envelope["payload"]["coin_value"] == unit * 2


def test_disconnected_snapshot_does_not_fabricate_race_metrics():
    bridge = LiveBridgeServer(port=0, runtime_mode="production")
    try:
        state = bridge._build_admin_state_payload()
        assert state["race_state"] == "AGUARDANDO_JOGO"
        assert state["phase_timer_seconds"] == 0
        assert all(c["position"] is None and c["speed_mps"] == 0 for c in state["candidates"])
    finally:
        bridge.outbox.close()


def test_real_game_timer_uses_canonical_match_time_remaining():
    import time
    bridge = LiveBridgeServer(port=0, runtime_mode="production")
    try:
        bridge.godot_clients.add(object())
        bridge._telemetry_received_at = time.monotonic()
        bridge.latest_telemetry = {"match_time_remaining": 569.0, "match_timer_remaining": 0.0}
        assert bridge._build_admin_state_payload()["phase_timer_seconds"] == 569.0
    finally:
        bridge.outbox.close()


@pytest.mark.asyncio
async def test_offline_settings_replay_preserves_latest_request_correlation():
    bridge = LiveBridgeServer(port=0, runtime_mode="production", producer_token="producer-fixture")
    first = build_admin_command_envelope(command="set_live_goal", goal_kind="likes", goal_target=100,
                                         event_id="evt_setting_superseded")
    latest = build_admin_command_envelope(command="set_live_goal", goal_kind="likes", goal_target=200,
                                          event_id="evt_setting_latest_req")
    assert bridge.enqueue_envelope(first) == bridge.enqueue_envelope(latest) == "accepted"
    await bridge.start()
    try:
        async with websockets.connect(f"ws://127.0.0.1:{bridge.bound_port}/ws/godot",
            additional_headers={"X-JOGI-Token": "producer-fixture"}) as game:
            await game.recv()
            replay = json.loads(await game.recv())
            assert replay["event_id"] == latest["event_id"]
            assert bridge.recent_commands[first["event_id"]]["status"] == "rejected"
            await game.send(json.dumps({"type": "command_result", "event_id": replay["event_id"],
                                       "command": "set_live_goal", "status": "applied"}))
            await asyncio.sleep(.03)
            assert bridge.recent_commands[latest["event_id"]]["status"] == "applied"
    finally:
        await bridge.stop()


@pytest.mark.asyncio
async def test_post_close_capacity_rejection_is_not_reported_as_durable():
    bridge = LiveBridgeServer(port=0, platform="tiktok", runtime_mode="production", gift_capacity=1)
    try:
        bridge.enqueue_envelope(build_admin_command_envelope(command="end_experience"))
        first = build_gift_envelope(user_id="v", display_name="V", source="tiktok", candidate_slot=None,
                                    event_id="evt_post_close_first")
        second = build_gift_envelope(user_id="w", display_name="W", source="tiktok", candidate_slot=None,
                                     event_id="evt_post_close_second")
        assert bridge.enqueue_envelope(first) == "accepted"
        assert bridge.recent_events[first["event_id"]]["processing_status"] == "after_close_pending"
        assert bridge.enqueue_envelope(second) == "busy"
        assert bridge.recent_events[second["event_id"]]["processing_status"] == "busy"
        assert bridge.outbox.pending_count() == 1
    finally:
        await bridge.stop()
