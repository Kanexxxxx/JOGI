"""Isolated two-process event load/recovery test. Uses synthetic consumers, not Godot.

The GPU/game path is tested separately by benchmark_dual_game.py --load-users.
Never connects to platform rooms or operator ports. No credentials enter reports.
"""
from __future__ import annotations

import argparse
import asyncio
from collections import Counter
from contextlib import closing
from datetime import datetime, timezone
import json
import hashlib
import os
from pathlib import Path
import random
import secrets
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/live_bridge'))
import websockets
from server import LiveBridgeServer
from protocol import build_gift_envelope, build_like_batch_envelope, build_vote_envelope
from benchmark_dual_game import process_metrics


def code_hashes() -> dict[str, str]:
    files = [ROOT / 'services/live_bridge' / name for name in
             ('server.py', 'protocol.py', 'outbox.py', 'operational_shutdown.py')]
    files.append(Path(__file__).resolve())
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}


async def worker(args: argparse.Namespace) -> None:
    bridge = LiveBridgeServer(port=0, platform=args.platform, account='isolated_load_fixture',
        runtime_mode='development', outbox_path=args.database,
        local_token=os.environ['JOGI_LOAD_TOKEN'], producer_token=os.environ['JOGI_LOAD_TOKEN'])
    await bridge.start()
    args.ready.write_text(json.dumps({'port': bridge.bound_port, 'pid': os.getpid()}), encoding='utf-8')
    try:
        await asyncio.Event().wait()
    finally:
        await bridge.stop()


async def until(predicate, timeout: float = 120) -> None:
    deadline = time.monotonic() + timeout
    while not predicate():
        if time.monotonic() >= deadline:
            raise TimeoutError('isolated load condition timed out')
        await asyncio.sleep(.05)


def state(port: int, token: str) -> dict:
    request = Request(f'http://127.0.0.1:{port}/api/state', headers={'X-JOGI-Token': token})
    with urlopen(request, timeout=5) as response:
        return json.load(response)


async def run(args: argparse.Namespace) -> int:
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    report = {'scope': 'two real bridge processes; authenticated WebSockets; synthetic durable consumer fixtures',
        'godot_included': False, 'public_live': False, 'paid_api_calls': 0,
        'identities_per_platform': args.users, 'result': 'failed', 'platforms': {},
        'source_hashes_at_start': code_hashes()}
    output = ROOT / 'docs/evidencias/load' / f'load-{stamp}.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='jogi-process-load-') as directory:
        temporary = Path(directory)
        processes, records, tokens, ledgers, consumer_tasks, logs = {}, {}, {}, {}, [], []
        hold_ack = asyncio.Event()
        deliveries: Counter = Counter()
        free_deliveries = {channel: Counter() for channel in ('tiktok', 'kwai')}
        resource_samples = []
        monitoring = True

        async def monitor() -> None:
            previous = {}
            while monitoring:
                sample = {'elapsed': time.monotonic() - started, 'processes': {}}
                for channel, record in list(records.items()):
                    metrics = process_metrics(record['pid'])
                    before = previous.get(record['pid'])
                    now = time.monotonic()
                    if metrics.get('available') and metrics.get('cpu_seconds') is not None:
                        if before:
                            metrics['cpu_host_capacity_percent'] = ((metrics['cpu_seconds'] - before[1]) /
                                max(.001, now - before[0]) * 100 / (os.cpu_count() or 1))
                        previous[record['pid']] = (now, metrics['cpu_seconds'])
                    sample['processes'][channel] = metrics
                resource_samples.append(sample)
                await asyncio.sleep(.5)

        async def launch(channel: str, generation: int) -> dict:
            ready = temporary / f'{channel}-{generation}.json'
            environment = os.environ.copy()
            environment.update(JOGI_LOAD_TOKEN=tokens[channel], JOGI_MODE='development',
                JOGI_END_AT='2099-01-01T00:00:00Z', LIVE_PLATFORM=channel,
                LIVE_BRIDGE_LOCAL_TOKEN='', LIVE_BRIDGE_PRODUCER_TOKEN='')
            log = (temporary / f'{channel}-{generation}.log').open('wb')
            logs.append(log)
            process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--worker',
                '--platform', channel, '--ready', str(ready), '--database',
                str(temporary / channel / 'gifts.sqlite3')], env=environment, stdout=log, stderr=log,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            processes[channel] = process
            await until(lambda: ready.exists() or process.poll() is not None, 20)
            if not ready.exists():
                raise RuntimeError('isolated worker failed before ready')
            record = json.loads(ready.read_text())
            if record['port'] in (8765, 8766):
                raise RuntimeError('ephemeral port collided with an operator port')
            records[channel] = record
            return record

        async def terminate(channel: str) -> None:
            process = processes[channel]
            if process.poll() is None:
                # Only the PID returned by THIS worker's private ready file.
                os.kill(records[channel]['pid'], signal.SIGTERM)
                await asyncio.to_thread(process.wait, 10)

        async def consume(channel: str, withhold: bool = False) -> None:
            record = records[channel]
            async with websockets.connect(f'ws://127.0.0.1:{record["port"]}/ws/godot',
                    additional_headers={'X-JOGI-Token': tokens[channel]}) as ws:
                async for raw in ws:
                    event = json.loads(raw)
                    if event.get('event_type') != 'gift':
                        if event.get('event_type') in ('vote', 'like_batch', 'share', 'follow'):
                            free_deliveries[channel][event['event_type']] += 1
                        continue
                    deliveries[channel] += 1
                    with ledgers[channel]:
                        ledgers[channel].execute('INSERT OR IGNORE INTO applied VALUES(?,?)',
                            (event['event_id'], event['payload']['coin_value']))
                    if withhold:
                        hold_ack.set()  # emulate durable application then socket loss before ACK
                        return
                    await ws.send(json.dumps({'type': 'event_ack', 'event_id': event['event_id']}))

        async def produce(channel: str) -> dict:
            packets, gift_coins = [], 0
            now = int(time.time() * 1000)
            for index in range(args.users):
                shared = dict(user_id=f'fixture_{channel}_{index}', display_name=f'TESTE {index}',
                    source='simulator', candidate_slot=index % 2 + 1, timestamp_ms=now - index % 19 * 100)
                packets += [build_vote_envelope(**shared, event_id=f'load_vote_{channel}_{index}'),
                    build_like_batch_envelope(**shared, like_count=10, event_id=f'load_like_{channel}_{index}')]
                if index < args.gifts:
                    gift = build_gift_envelope(**shared, repeat_count=index % 5 + 1,
                        unit_coin_value=index % 4 + 1, gift_name='PRESENTE TESTE', gift_id='fixture_gift',
                        event_id=f'load_gift_{channel}_{index}')
                    packets += [gift, gift]
                    gift_coins += gift['payload']['coin_value']
            random.Random(52).shuffle(packets)
            receipts: Counter = Counter()
            async with websockets.connect(f'ws://127.0.0.1:{records[channel]["port"]}/ws/ingest',
                    additional_headers={'X-JOGI-Token': tokens[channel]}) as ws:
                for event in packets:
                    await ws.send(json.dumps(event))
                    receipt = json.loads(await asyncio.wait_for(ws.recv(), 10))
                    receipts[receipt.get('status', 'missing')] += 1
            return {'submitted_packets': len(packets), 'unique_gifts_expected': args.gifts,
                    'gift_coins_expected': gift_coins, 'receipts': dict(receipts)}

        def pending(channel: str) -> int:
            with closing(sqlite3.connect(temporary / channel / 'gifts.sqlite3')) as database:
                return database.execute('SELECT COUNT(*) FROM gifts WHERE completed_ms IS NULL').fetchone()[0]

        try:
            for channel in ('tiktok', 'kwai'):
                tokens[channel] = secrets.token_urlsafe(32)
                ledgers[channel] = sqlite3.connect(temporary / f'{channel}-consumer.sqlite3')
                ledgers[channel].execute('CREATE TABLE applied(event_id TEXT PRIMARY KEY,coins INTEGER NOT NULL)')
                await launch(channel, 1)
                consumer_tasks.append(asyncio.create_task(consume(channel, channel == 'tiktok')))
            monitor_task = asyncio.create_task(monitor())
            await asyncio.sleep(.2)
            produced = await asyncio.gather(produce('tiktok'), produce('kwai'))
            await asyncio.wait_for(hold_ack.wait(), 15)
            kwai_pid = records['kwai']['pid']
            kwai_before = await asyncio.to_thread(state, records['kwai']['port'], tokens['kwai'])
            tiktok_before = await asyncio.to_thread(state, records['tiktok']['port'], tokens['tiktok'])
            pending_before = pending('tiktok')
            await terminate('tiktok')
            await launch('tiktok', 2)
            consumer_tasks.append(asyncio.create_task(consume('tiktok')))
            await until(lambda: all(pending(channel) == 0 for channel in ('tiktok', 'kwai')))
            drain_deadline = time.monotonic() + 120
            while True:
                snapshots = await asyncio.gather(*(asyncio.to_thread(state, records[channel]['port'], tokens[channel])
                                                  for channel in ('tiktok', 'kwai')))
                if all(not any(snapshot['queue_sizes'].values()) for snapshot in snapshots):
                    break
                if time.monotonic() >= drain_deadline:
                    raise TimeoutError('free queues did not drain')
                await asyncio.sleep(.25)
            for channel, generated in zip(('tiktok', 'kwai'), produced):
                count, coins = ledgers[channel].execute('SELECT COUNT(*),SUM(coins) FROM applied').fetchone()
                snapshot = await asyncio.to_thread(state, records[channel]['port'], tokens[channel])
                report['platforms'][channel] = {**generated, 'durably_applied_unique': count,
                    'durably_applied_coins': coins, 'transport_gift_deliveries': deliveries[channel],
                    'pending_gifts': pending(channel), 'metrics': snapshot.get('metrics', {}),
                    'free_events_delivered': dict(free_deliveries[channel]),
                    'queue_sizes_at_end': snapshot['queue_sizes'],
                    'ledger_integrity': ledgers[channel].execute('PRAGMA integrity_check').fetchone()[0]}
            kwai_after = await asyncio.to_thread(state, records['kwai']['port'], tokens['kwai'])
            report['recovery'] = {'tiktok_process_restarted': True, 'pending_at_crash': pending_before,
                'kwai_same_process': records['kwai']['pid'] == kwai_pid,
                'kwai_available_before_and_after': bool(kwai_before) and bool(kwai_after),
                'tiktok_volatile_free_events_at_crash': sum(tiktok_before['queue_sizes'].values()),
                'tiktok_metrics_before_restart': tiktok_before['metrics'],
                'applied_before_lost_ack_replayed_without_double_counting': deliveries['tiktok'] == args.gifts + 1}
            report['checks'] = {
                'paid_exactly_once_in_durable_fixture': all(row['durably_applied_unique'] == args.gifts
                    and row['durably_applied_coins'] == row['gift_coins_expected']
                    and row['pending_gifts'] == 0 and row['ledger_integrity'] == 'ok'
                    and row['receipts'].get('duplicate') == args.gifts
                    and set(row['receipts']) <= {'accepted', 'duplicate'} for row in report['platforms'].values()),
                'restart_recovery_and_other_platform_survived': all(report['recovery'][key] for key in
                    ('kwai_same_process', 'kwai_available_before_and_after', 'applied_before_lost_ack_replayed_without_double_counting')),
                'uninterrupted_platform_all_free_events_drained': sum(free_deliveries['kwai'].values()) == args.users * 2,
                'sources_unchanged': code_hashes() == report['source_hashes_at_start'],
            }
            report['result'] = 'passed' if all(report['checks'].values()) else 'failed'
        except Exception as error:
            report['error'] = type(error).__name__ + ': ' + str(error)
        finally:
            monitoring = False
            if 'monitor_task' in locals():
                await monitor_task
            for task in consumer_tasks:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*consumer_tasks, return_exceptions=True)
            for channel in processes:
                await terminate(channel)
            for database in ledgers.values():
                database.close()
            for log in logs:
                log.close()
            report['duration_seconds'] = time.monotonic() - started
            report['resource_summary'] = {channel: {
                'peak_working_set_mib': max((sample['processes'].get(channel, {}).get('working_set_bytes', 0)
                    for sample in resource_samples), default=0) / 1048576,
                'peak_cpu_host_capacity_percent': max((sample['processes'].get(channel, {}).get('cpu_host_capacity_percent', 0)
                    for sample in resource_samples), default=0),
            } for channel in ('tiktok', 'kwai')}
            report['limits'] = ['Consumer fixtures are not game execution or real platform homologation.',
                'Free event queues may shed under burst; inspect metrics. Paid rows are asserted independently.',
                'Free events already queued in RAM may be lost on bridge process crash; the report counts this separately.',
                'A short isolated test does not certify 42 hours.']
            output.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({'result': report['result'], 'report': str(output.relative_to(ROOT)),
                      'checks': report.get('checks'), 'error': report.get('error')}))
    return int(report['result'] != 'passed')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--users', type=int, default=1000)
    parser.add_argument('--gifts', type=int, default=300)
    parser.add_argument('--worker', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--platform', choices=('tiktok', 'kwai'))
    parser.add_argument('--ready', type=Path)
    parser.add_argument('--database', type=Path)
    args = parser.parse_args()
    if args.worker:
        asyncio.run(worker(args))
        return 0
    if not 1 <= args.users <= 10000 or not 1 <= args.gifts <= args.users:
        parser.error('users must be 1..10000; gifts must be 1..users')
    return asyncio.run(run(args))


if __name__ == '__main__':
    raise SystemExit(main())
