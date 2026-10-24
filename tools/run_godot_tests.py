"""Run actual SceneTree test scripts through GDA; live WS test uses its Python E2E runner."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GDA = Path(r'C:\Users\Kanex\.local\bin\gda.exe')
GODOT = Path(r'C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/evidencias/godot-suite-return.json')
    args = parser.parse_args()
    results = []
    for path in sorted((ROOT / 'game/tests').glob('test_*.gd')):
        if path.name == 'test_live_bridge_e2e.gd':
            continue
        if not path.read_text(encoding='utf-8').startswith('extends SceneTree'):
            continue
        started = time.monotonic()
        isolated_data = tempfile.TemporaryDirectory(prefix='jogi-godot-test-')
        environment = os.environ.copy()
        environment.update(JOGI_MODE='development', JOGI_END_AT='2099-01-01T00:00:00Z',
                           GDA_USER_DATA_ROOT=isolated_data.name,
                           LIVE_BRIDGE_WS_URL='ws://127.0.0.1:9/ws/godot',
                           LIVE_BRIDGE_LOCAL_TOKEN='', LIVE_BRIDGE_PRODUCER_TOKEN='')
        command = [str(GDA), '--user-data-root', isolated_data.name,
                   'script', 'run', 'res://tests/' + path.name, '--strict', '--json',
                   '--project', str(ROOT / 'game'), '--godot', str(GODOT)]
        try:
            process = subprocess.run(command, capture_output=True, timeout=90, env=environment)
            stdout = process.stdout.decode('utf-8', errors='replace')
            stderr = process.stderr.decode('utf-8', errors='replace')
            try:
                payload = json.loads(stdout)
            except json.JSONDecodeError:
                payload = {'raw_stdout': stdout, 'launcher_stderr': stderr}
            result = {'script': path.name, 'exit_code': process.returncode,
                      'seconds': round(time.monotonic() - started, 3), 'gda': payload}
        except subprocess.TimeoutExpired:
            result = {'script': path.name, 'exit_code': 124, 'seconds': 90, 'error': 'timeout'}
        finally:
            isolated_data.cleanup()
        results.append(result)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({'results': results, 'passed': sum(r['exit_code'] == 0 for r in results),
            'failed': sum(r['exit_code'] != 0 for r in results), 'excluded': {'test_live_bridge_e2e.gd': 'requires Python bridge runner; executed separately'}},
            ensure_ascii=False, indent=2), encoding='utf-8')
        print(f"{path.name}: {'PASS' if result['exit_code'] == 0 else 'FAIL'} ({result['seconds']} s)", flush=True)
    return int(any(row['exit_code'] != 0 for row in results))


if __name__ == '__main__':
    raise SystemExit(main())
