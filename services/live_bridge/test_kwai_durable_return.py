"""Return-audit regressions: browser cookies and paid collector acceptance."""
import asyncio
import json
from http.cookiejar import CookieJar
from urllib.request import build_opener, HTTPCookieProcessor, Request

import pytest
from server import LiveBridgeServer


@pytest.mark.asyncio
async def test_operator_cookies_coexist_for_two_platforms() -> None:
    first = LiveBridgeServer(runtime_mode="development", port=0, platform='tiktok', local_token='operator-fixture-token')
    second = LiveBridgeServer(runtime_mode="development", port=0, platform='kwai', local_token='operator-fixture-token')
    await first.start()
    await second.start()
    jar = CookieJar()
    opener = build_opener(HTTPCookieProcessor(jar))

    def login(port: int) -> None:
        request = Request(f'http://127.0.0.1:{port}/api/admin/session', headers={'X-JOGI-Token': 'operator-fixture-token'})
        with opener.open(request, timeout=3) as response:
            assert response.status == 200

    def read_state(port: int) -> dict:
        with opener.open(f'http://127.0.0.1:{port}/api/state', timeout=3) as response:
            return json.load(response)

    try:
        await asyncio.to_thread(login, first.bound_port)
        await asyncio.to_thread(login, second.bound_port)
        assert len(list(jar)) == 2
        assert (await asyncio.to_thread(read_state, first.bound_port))['platform'] == 'tiktok'
        assert (await asyncio.to_thread(read_state, second.bound_port))['platform'] == 'kwai'
    finally:
        await first.stop()
        await second.stop()


async def post(adapter, body: dict, token: str = 'producer-fixture-token') -> tuple[int, dict]:
    payload = json.dumps(body).encode()
    reader, writer = await asyncio.open_connection('127.0.0.1', adapter.bound_port)
    writer.write((f'POST /webhook/kwai HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: {len(payload)}\r\nX-JOGI-Token: {token}\r\nConnection: close\r\n\r\n').encode() + payload)
    await writer.drain()
    response = await asyncio.wait_for(reader.read(), 5)
    writer.close()
    await writer.wait_closed()
    header, content = response.split(b'\r\n\r\n', 1)
    return int(header.split(b' ')[1]), json.loads(content)


@pytest.mark.asyncio
async def test_kwai_retries_same_id_after_failure_and_only_acks_durable_storage(tmp_path) -> None:
    bridge = LiveBridgeServer(runtime_mode="development", port=0, platform='kwai', kwai_webhook_port=0,
                              producer_token='producer-fixture-token', outbox_path=tmp_path / 'gifts.sqlite3')
    await bridge.start()
    await bridge.start_live_listener()
    adapter = bridge._live_adapter
    attempts = 0

    async def sink(envelope):
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise OSError('fixture disk failure')
        return await bridge._receive_adapter_event(envelope)

    adapter.set_durable_gift_sink(sink)
    raw = {'type': 'gift', 'event_id': 'raw_paid_retry_probe', 'user_id': 'u', 'gift_id': 'rose', 'coins': 5, 'repeat_count': 2}
    try:
        unauthorized, _ = await post(adapter, raw, token='wrong-fixture-token')
        assert unauthorized == 401
        status, response = await post(adapter, raw)
        assert status == 503 and response['status'] == 'busy'
        assert bridge.outbox.pending_count() == 0
        status, accepted = await post(adapter, raw)
        assert status == 200 and accepted['acknowledged'] is True
        assert accepted['raw_event_id'] == raw['event_id']
        assert accepted['delivery_status'] == 'accepted'
        status, repeated = await post(adapter, raw)
        assert status == 200 and repeated['delivery_status'] == 'duplicate'
        assert repeated['event_id'] == accepted['event_id']
        assert bridge.outbox.pending_count() == 1
        assert bridge.outbox.next_due()['payload']['coin_value'] == 10
    finally:
        await bridge.stop()
