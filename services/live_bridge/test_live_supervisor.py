"""Fake-process watchdog tests: failures are local to one supervised child."""
import importlib.util
from pathlib import Path
import sys
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from contextlib import nullcontext

TOOLS = Path(__file__).resolve().parents[2] / 'tools'
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
from live_supervisor import LiveSupervisor, ManagedChild, stay_awake
import run_live_instances


class FakeProcess:
    next_pid = 1
    def __init__(self):
        self.pid = FakeProcess.next_pid; FakeProcess.next_pid += 1
        self.code = None; self.terminated = False
    def poll(self): return self.code
    def terminate(self): self.terminated = True; self.code = 0
    def kill(self): self.code = -9
    def wait(self, timeout=5): return self.code


class SupervisorTests(unittest.TestCase):
    def test_mode_storage_is_separate_and_legacy_paid_pending_is_detected_read_only(self):
        production = run_live_instances.build_plan('tiktok', runtime_mode='production')
        development = run_live_instances.build_plan('tiktok', offline=True)
        self.assertNotEqual(production['state_dir'], development['state_dir'])
        self.assertEqual(production['godot_environment']['JOGI_MODE'], 'production')
        self.assertEqual(development['godot_environment']['JOGI_MODE'], 'development')
        with tempfile.TemporaryDirectory() as folder:
            production['legacy_state_dir'] = folder
            path = Path(folder) / 'gifts.sqlite3'
            with sqlite3.connect(path) as db:
                db.execute('CREATE TABLE gifts (completed_ms INTEGER)')
                db.executemany('INSERT INTO gifts VALUES (?)', [(None,), (100,)])
            db.close()
            before = path.read_bytes()
            self.assertEqual(run_live_instances.legacy_pending_gifts(production), 1)
            self.assertEqual(path.read_bytes(), before)

    def test_rejected_second_launcher_preserves_owner_status(self):
        with tempfile.TemporaryDirectory() as folder:
            plans = [run_live_instances.build_plan(platform, offline=True) for platform in ('tiktok', 'kwai')]
            for plan in plans:
                plan['state_dir'] = str(Path(folder) / plan['platform'])
            owner = Path(plans[0]['state_dir']) / 'watchdog_status.json'
            owner.parent.mkdir(parents=True)
            owner.write_text('existing owner status', encoding='utf-8')
            calls = 0
            def health(port):
                nonlocal calls
                if port == 8765:
                    return {'platform': 'tiktok'}
                calls += 1
                return None if calls == 1 else {'platform': 'kwai'}
            processes = []
            def spawn(*args, **kwargs):
                process = FakeProcess()
                processes.append(process)
                return process
            with patch.object(run_live_instances, 'health', side_effect=health), \
                 patch.object(run_live_instances.subprocess, 'Popen', side_effect=spawn), \
                 patch.object(run_live_instances, 'stay_awake', side_effect=lambda: nullcontext()), \
                 patch.object(run_live_instances.time, 'sleep', side_effect=KeyboardInterrupt):
                self.assertEqual(run_live_instances.launch(plans), 0)
            self.assertEqual(owner.read_text(encoding='utf-8'), 'existing owner status')
            self.assertEqual(len(processes), 2)
            self.assertTrue(all(process.terminated for process in processes))

    def test_failed_child_restarts_without_stopping_siblings(self):
        with tempfile.TemporaryDirectory() as folder:
            first = ManagedChild('tiktok', 'bridge', FakeProcess)
            other = ManagedChild('kwai', 'bridge', FakeProcess)
            same_game = ManagedChild('tiktok', 'game', FakeProcess)
            supervisor = LiveSupervisor([first, other, same_game], {'tiktok':Path(folder)/'tt','kwai':Path(folder)/'kw'})
            supervisor.step(0)
            first_pid, other_process = first.process.pid, other.process
            first.process.code = 1
            supervisor.step(.1); supervisor.step(1.2)
            self.assertNotEqual(first.process.pid, first_pid)
            self.assertIs(other.process, other_process)
            self.assertFalse(other_process.terminated)
            self.assertFalse(same_game.process.terminated)
            self.assertEqual(same_game.attempts,1)
            supervisor.shutdown()
            self.assertTrue(other_process.terminated)

    def test_six_restarts_then_attention_keeps_other_child_running(self):
        first, other = ManagedChild('tiktok','game',FakeProcess), ManagedChild('kwai','game',FakeProcess)
        first.tick(0); other.tick(0)
        now = 0
        for _ in range(7):
            first.process.code = 1
            now += .1; first.tick(now)
            now += 31; first.tick(now)
            if first.requires_attention: break
        self.assertTrue(first.requires_attention)
        self.assertEqual(len(first.restarts), 6)
        self.assertIsNone(first.process)
        self.assertIsNone(other.process.poll())
        self.assertFalse(other.process.terminated)
        other.stop()

    def test_backoff_cap_and_dependency(self):
        ready = False
        child = ManagedChild('tiktok','game',FakeProcess,ready=lambda:ready)
        child.tick(0); self.assertIsNone(child.process)
        ready = True; child.tick(0)
        child.failures = 99; child.process.code = 1; child.tick(1)
        self.assertEqual(child.next_start, 31)

    def test_awake_request_is_scoped_and_restored(self):
        class FakeKernel:
            calls = []
            def SetThreadExecutionState(self, value): self.calls.append(value); return 0x80000000
        kernel = FakeKernel()
        with stay_awake(kernel) as active:
            self.assertTrue(active)
        self.assertEqual(kernel.calls, [0x80000003,0x80000000])


if __name__ == '__main__': unittest.main()
