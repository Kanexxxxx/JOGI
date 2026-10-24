"""Two authenticated local bridges + real GPU games. Never starts a platform broadcast.

Run with services/live_bridge/.venv/Scripts/python.exe. Default 620 real seconds,
common barrier after both renderers and WebSockets are ready. Runtime SQLite files
stay under LOCALAPPDATA, and generated tokens stay only in process memory/env.
"""
from __future__ import annotations

import argparse
import asyncio
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import json
import hashlib
import logging
import os
from pathlib import Path
import secrets
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'services/live_bridge'))
from server import LiveBridgeServer
from protocol import (build_follow_envelope, build_gift_envelope,
                      build_like_batch_envelope, build_vote_envelope)

# The console executable is a small forwarding wrapper; measure the real renderer.
GODOT = Path.home() / 'Downloads' / 'Godot_v4.7.2-stable_win64.exe' / 'Godot_v4.7.2-stable_win64.exe'
CHANNELS = ('tiktok', 'kwai')


def source_hashes() -> dict[str, str]:
    files = [*sorted((ROOT / 'game/scripts').glob('*.gd')),
             *sorted((ROOT / 'game/shaders').glob('*.gdshader')),
             ROOT / 'game/project.godot', ROOT / 'game/scenes/main/stadium_race.tscn',
             ROOT / 'tools/benchmark_game.gd', ROOT / 'tools/benchmark_dual_game.py']
    return {str(path.relative_to(ROOT)).replace('\\', '/'): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}


class FILETIME(ctypes.Structure):
    _fields_ = [('low', wintypes.DWORD), ('high', wintypes.DWORD)]


class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
    _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD)] + [
        (name, ctypes.c_size_t) for name in ('PeakWorkingSetSize', 'WorkingSetSize',
        'QuotaPeakPagedPoolUsage', 'QuotaPagedPoolUsage', 'QuotaPeakNonPagedPoolUsage',
        'QuotaNonPagedPoolUsage', 'PagefileUsage', 'PeakPagefileUsage', 'PrivateUsage')]


def process_metrics(pid: int) -> dict:
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(FILETIME)] * 4
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    psapi = ctypes.WinDLL('psapi', use_last_error=True)
    psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(PROCESS_MEMORY_COUNTERS_EX), wintypes.DWORD]
    handle = kernel.OpenProcess(0x1000 | 0x10, False, pid)
    if not handle:
        return {'pid': pid, 'available': False}
    try:
        created, exited, system, user = FILETIME(), FILETIME(), FILETIME(), FILETIME()
        okay = kernel.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited), ctypes.byref(system), ctypes.byref(user))
        memory = PROCESS_MEMORY_COUNTERS_EX()
        memory.cb = ctypes.sizeof(memory)
        mem_okay = psapi.GetProcessMemoryInfo(handle, ctypes.byref(memory), memory.cb)
        cpu = (((system.high << 32) | system.low) + ((user.high << 32) | user.low)) / 10000000 if okay else None
        return {'pid': pid, 'available': bool(okay and mem_okay), 'cpu_seconds': cpu,
                'working_set_bytes': memory.WorkingSetSize, 'private_bytes': memory.PrivateUsage,
                'peak_working_set_bytes': memory.PeakWorkingSetSize}
    finally:
        kernel.CloseHandle(handle)


def gpu_metrics() -> dict:
    try:
        proc = subprocess.run([r'C:\WINDOWS\system32\nvidia-smi.exe', '--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu',
                               '--format=csv,noheader,nounits'], capture_output=True, text=True, timeout=4,
                              creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if proc.returncode != 0:
            return {'available': False}
        name, utilization, used, total, temperature = [part.strip() for part in proc.stdout.splitlines()[0].split(',')]
        return {'available': True, 'name': name, 'utilization_percent_total': int(utilization),
                'memory_used_mib_total': int(used), 'memory_total_mib': int(total), 'temperature_c': float(temperature)}
    except (OSError, subprocess.TimeoutExpired, ValueError, IndexError):
        return {'available': False}


def hardware() -> dict:
    command = "$p=Get-CimInstance Win32_Processor; $c=Get-CimInstance Win32_ComputerSystem; [pscustomobject]@{cpu=$p.Name;logical_processors=$c.NumberOfLogicalProcessors;ram_bytes=$c.TotalPhysicalMemory}|ConvertTo-Json -Compress"
    try:
        proc = subprocess.run(['powershell', '-NoProfile', '-Command', command], capture_output=True,
                              text=True, timeout=10, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        return json.loads(proc.stdout) if proc.returncode == 0 else {}
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return {}


async def run(args: argparse.Namespace) -> int:
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output = ROOT / 'docs/evidencias/benchmark' / f'dual-{stamp}'
    output.mkdir(parents=True, exist_ok=False)
    runtime = Path(os.environ['LOCALAPPDATA']) / 'JOGI' / 'benchmarks' / stamp
    runtime.mkdir(parents=True, exist_ok=False)
    bridges, games, handles, tokens, renderer_pids = {}, {}, [], {}, {}
    samples, generated = [], {channel: 0 for channel in CHANNELS}
    started = None
    previous_cpu = {}
    result = {'scope': 'isolated authenticated loopback bridges; simulated audience; real Vulkan games',
              'public_live_started': False, 'paid_api_calls': 0, 'obs_encoding_included': False,
              'duration_requested_seconds': args.seconds, 'hardware': await asyncio.to_thread(hardware),
              'output_directory': str(output.relative_to(ROOT)), 'samples': samples}
    result['git_head'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    result['git_dirty_at_start'] = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip())
    result['source_hashes_at_start'] = source_hashes()
    try:
        for channel in CHANNELS:
            tokens[channel] = secrets.token_urlsafe(32)
            bridge = LiveBridgeServer(port=0, platform=channel, account='benchmark_local',
                outbox_path=runtime / channel / 'gifts.sqlite3',
                local_token=secrets.token_urlsafe(32), producer_token=tokens[channel], rate_limit_per_sec=100)
            await bridge.start()
            bridges[channel] = bridge
            env = os.environ.copy()
            # Explicit per-child values override any real user configuration.
            env.update(LIVE_PLATFORM=channel, LIVE_BRIDGE_WS_URL=f'ws://127.0.0.1:{bridge.bound_port}/ws/godot',
                       LIVE_BRIDGE_PRODUCER_TOKEN=tokens[channel], LIVE_BRIDGE_LOCAL_TOKEN='',
                       JOGI_BENCH_OUTPUT=str(output), JOGI_BENCH_SECONDS=str(args.seconds),
                       JOGI_BENCH_ID=stamp, LIVE_AVATARS_ENABLED='0')
            log = (output / f'{channel}-godot.log').open('wb')
            handles.append(log)
            games[channel] = subprocess.Popen([str(GODOT), '--path', str(ROOT / 'game'),
                '--script', str(ROOT / 'tools/benchmark_game.gd'), '--', '--asset-preview'],
                cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        deadline = time.monotonic() + 90
        while not all((output / f'{channel}-ready.json').exists() and bridges[channel].godot_clients for channel in CHANNELS):
            if any(game.poll() is not None for game in games.values()):
                raise RuntimeError('game_exited_before_barrier')
            if time.monotonic() >= deadline:
                raise RuntimeError('render_or_authenticated_websocket_startup_timeout')
            await asyncio.sleep(.1)
        renderer_pids = {channel: int(json.loads((output / f'{channel}-ready.json').read_text())['pid']) for channel in CHANNELS}
        result['renderer_pids'] = renderer_pids
        result['launcher_pids'] = {channel: game.pid for channel, game in games.items()}
        started = time.monotonic()
        result['started_utc'] = datetime.now(timezone.utc).isoformat()
        (output / 'start.signal').write_text('Start both isolated test renderers', encoding='ascii')
        print(f'BENCHMARK_STARTED {output.relative_to(ROOT)} {args.seconds}s', flush=True)
        next_event, next_sample, next_progress, step = 1.0, 0.0, 30.0, 0
        while any(game.poll() is None for game in games.values()):
            elapsed = time.monotonic() - started
            if elapsed > args.seconds + 25:
                raise RuntimeError('game_finish_timeout')
            if elapsed < args.seconds - .5 and any(game.poll() is not None for game in games.values()):
                raise RuntimeError('game_exited_during_common_render_interval')
            if elapsed >= next_event and elapsed < args.seconds - 2:
                step += 1
                for channel, bridge in bridges.items():
                    slot = (step + (1 if channel == 'kwai' else 0)) % 2 + 1
                    common = {'user_id': f'qa_{channel}_{step % 7}', 'display_name': f'Teste {channel} {step % 7}',
                              'candidate_slot': slot, 'source': 'simulator'}
                    tier = ('T1', 'T2', 'T3', 'T4')[step % 4]
                    coins = {'T1': 1, 'T2': 15, 'T3': 100, 'T4': 1000}[tier]
                    if step % 11 == 0:
                        tier, coins = 'T4', 30000
                    events = [build_vote_envelope(**common, event_id=f'bench_vote_{channel}_{step:06d}'),
                              build_gift_envelope(**common, gift_tier=tier, unit_coin_value=coins,
                                  gift_id=f'qa_{tier}', gift_name=f'Presente TESTE {tier}', event_id=f'bench_gift_{channel}_{step:06d}'),
                              build_like_batch_envelope(**common, like_count=50, event_id=f'bench_likes_{channel}_{step:06d}')]
                    if step % 4 == 0:
                        events.append(build_follow_envelope(**common, event_id=f'bench_follow_{channel}_{step:06d}'))
                    for event in events:
                        bridge.enqueue_envelope(event)
                    generated[channel] += len(events)
                next_event += 8
            if elapsed >= next_sample:
                row = {'elapsed': round(elapsed, 3), 'games': {}, 'gpu': await asyncio.to_thread(gpu_metrics), 'bridges': {}}
                now = time.monotonic()
                for channel, game in games.items():
                    metrics = process_metrics(renderer_pids[channel])
                    old = previous_cpu.get(channel)
                    if old and metrics['cpu_seconds'] is not None:
                        core_percent = (metrics['cpu_seconds'] - old[1]) / max(now - old[0], .001) * 100
                        metrics['cpu_percent_one_core_scale'] = round(core_percent, 2)
                        metrics['cpu_percent_host_capacity'] = round(core_percent / (os.cpu_count() or 1), 2)
                    if metrics['cpu_seconds'] is not None:
                        previous_cpu[channel] = (now, metrics['cpu_seconds'])
                    row['games'][channel] = metrics
                    bridge = bridges[channel]
                    row['bridges'][channel] = {'connected_godot': len(bridge.godot_clients),
                        'pending_gifts': bridge.outbox.pending_count(), 'gift_acks': bridge.metrics['gift_acks_total'],
                        'sqlite_spool_bytes': sum(path.stat().st_size for path in (runtime / channel).glob('gifts.sqlite3*') if path.is_file()),
                        'round': bridge.latest_telemetry.get('current_round'),
                        'state': bridge.latest_telemetry.get('state_name')}
                samples.append(row)
                (output / 'progress.json').write_text(json.dumps({'elapsed': elapsed, 'sample': row}, indent=2), encoding='utf-8')
                next_sample += 5
            if elapsed >= next_progress:
                print(f'BENCHMARK_PROGRESS {int(elapsed)}s tiktok={games["tiktok"].poll()} kwai={games["kwai"].poll()}', flush=True)
                next_progress += 30
            await asyncio.sleep(.1)
        result['duration_wall_seconds'] = time.monotonic() - started
        result['exit_codes'] = {channel: game.returncode for channel, game in games.items()}
        result['generated_events'] = generated
        result['bridges_final'] = {channel: {'pending_gifts': bridge.outbox.pending_count(),
            'gift_acks_total': bridge.metrics['gift_acks_total'],
            'connected_godot': len(bridge.godot_clients)} for channel, bridge in bridges.items()}
        result['engines'] = {channel: json.loads((output / f'{channel}-engine.json').read_text()) for channel in CHANNELS}
        result['minimum_simultaneous_engine_duration'] = min(engine['duration_seconds'] for engine in result['engines'].values())
        result['common_render_interval_seconds'] = min(engine['finished_unix'] for engine in result['engines'].values()) - max(engine['started_unix'] for engine in result['engines'].values())
        result['engine_errors'] = {channel: [line for line in (output / f'{channel}-godot.log').read_text(encoding='utf-8', errors='replace').splitlines()
            if any(marker in line for marker in ('SCRIPT ERROR:', 'ERROR:', 'CrashHandlerException'))] for channel in CHANNELS}
        result['quality_checks'] = {
            'both_exit_zero': all(code == 0 for code in result['exit_codes'].values()),
            'both_render_1080x1920': all(engine['viewport_width'] == 1080 and engine['viewport_height'] == 1920 for engine in result['engines'].values()),
            'no_engine_errors': not any(result['engine_errors'].values()),
            'paid_simulation_acked_both': all(item['gift_acks_total'] > 0 and item['pending_gifts'] == 0 for item in result['bridges_final'].values()),
            'no_rejected_events': all(engine['rejected_events'] == 0 for engine in result['engines'].values()),
            'private_checkpoints_saved': all(engine['final_snapshot_saved'] and not engine['persistence_error'] for engine in result['engines'].values()),
        }
        result['performance_target_met'] = all(engine['fps_mean'] >= 59 and engine['p95_frame_ms'] <= 18.5 for engine in result['engines'].values())
        result['ten_minutes_simultaneous_verified'] = result['common_render_interval_seconds'] >= 600
        summaries = {}
        for channel in CHANNELS:
            measurements = [row['games'][channel] for row in samples if row['games'][channel].get('available')]
            cpu = [item['cpu_percent_host_capacity'] for item in measurements if 'cpu_percent_host_capacity' in item]
            engine_samples = result['engines'][channel]['samples']
            summaries[channel] = {
                'cpu_host_capacity_mean_percent': statistics.mean(cpu) if cpu else None,
                'cpu_host_capacity_peak_percent': max(cpu) if cpu else None,
                'working_set_peak_mib': max((item['working_set_bytes'] for item in measurements), default=0) / 1048576,
                'private_bytes_peak_mib': max((item['private_bytes'] for item in measurements), default=0) / 1048576,
                'node_count_min': min(item['nodes'] for item in engine_samples),
                'node_count_max': max(item['nodes'] for item in engine_samples),
                'orphan_nodes_max': max(item['orphans'] for item in engine_samples),
                'renderer_memory_peak_mib': max(item['renderer_memory_bytes'] for item in engine_samples) / 1048576,
            }
        result['metric_summary'] = summaries
        result['result'] = 'passed' if all(result['quality_checks'].values()) else 'failed'
        result['limits'] = ['A 10-minute result does not certify 42 hours.',
                            'GPU utilization/VRAM from nvidia-smi includes all applications on the GPU.',
                            'No OBS encoding or platform event source is included.',
                            'Synthetic events, generated tokens and databases are separate from user sessions.']
        print('BENCHMARK_FINISHED ' + json.dumps({'result': result['result'], 'output': str(output.relative_to(ROOT)),
            'fps': {channel: item['fps_mean'] for channel, item in result['engines'].items()}}), flush=True)
        return 0 if result['result'] == 'passed' else 1
    except Exception as error:
        result.update(result='failed', error=type(error).__name__ + ': ' + str(error))
        print('BENCHMARK_FAILED ' + result['error'], flush=True)
        return 1
    finally:
        # Only processes created in this invocation are terminated.
        for game in games.values():
            if game.poll() is None:
                game.terminate()
                try:
                    await asyncio.to_thread(game.wait, 5)
                except subprocess.TimeoutExpired:
                    game.kill()
                    await asyncio.to_thread(game.wait, 5)
        for bridge in bridges.values():
            await bridge.stop()
        for handle in handles:
            handle.close()
        result['finished_utc'] = datetime.now(timezone.utc).isoformat()
        result['source_hashes_at_finish'] = source_hashes()
        result['sources_changed_during_test'] = [path for path, digest in result['source_hashes_at_start'].items()
                                               if result['source_hashes_at_finish'].get(path) != digest]
        (output / 'report.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, default=620.0)
    args = parser.parse_args()
    if not 5 <= args.seconds <= 660:
        parser.error('--seconds must be between 5 and 660')
    logging.basicConfig(level=logging.WARNING)
    return asyncio.run(run(args))


if __name__ == '__main__':
    raise SystemExit(main())
