"""Fake-process watchdog tests: failures are local to one supervised child."""
import importlib.util
import hashlib
from pathlib import Path
import sys
import sqlite3
import tempfile
import unittest
import os
import time
from unittest.mock import patch
from contextlib import nullcontext, contextmanager

TOOLS = Path(__file__).resolve().parents[2] / 'tools'
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
from live_supervisor import LiveSupervisor, ManagedChild, stay_awake
import run_live_instances


def test_account_scoped_paths_and_lifetime_launcher_lock(tmp_path, monkeypatch):
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path))
    plan = run_live_instances.build_plan("tiktok", runtime_mode="production")
    key = hashlib.sha256(b"xinka_").hexdigest()[:16]
    assert plan["account"] == "xinka_"
    assert Path(plan["state_dir"]) == tmp_path / "JOGI" / "live_bridge" / "tiktok" / "production" / "accounts" / key
    assert plan["godot_environment"]["LIVE_ACCOUNT"] == "xinka_"
    lock = run_live_instances.LauncherLock(Path(plan["state_dir"]))
    try:
        credential = Path(plan["state_dir"]) / "operator-token.key"
        credential.write_text("owner-fixture", encoding="utf-8")
        with unittest.TestCase().assertRaises(RuntimeError):
            run_live_instances.LauncherLock(Path(plan["state_dir"]))
        with patch.object(run_live_instances, "prepare_operator_credentials") as prepare:
            assert run_live_instances.launch([plan], bridge_only=True) == 1
        prepare.assert_not_called()
        assert credential.read_text(encoding="utf-8") == "owner-fixture"
    finally:
        lock.close()
    replacement = run_live_instances.LauncherLock(Path(plan["state_dir"]))
    replacement.close()


def test_both_legacy_layouts_are_checked_without_changes(tmp_path):
    plan = run_live_instances.build_plan("tiktok", runtime_mode="production")
    plan["legacy_state_dir"] = str(tmp_path)
    plan["legacy_mode_state_dir"] = str(tmp_path / "production")
    for folder in (tmp_path, tmp_path / "production"):
        folder.mkdir(exist_ok=True)
        with sqlite3.connect(folder / "gifts.sqlite3") as db:
            db.execute("CREATE TABLE gifts (completed_ms INTEGER)")
            db.executemany("INSERT INTO gifts VALUES (?)", [(None,), (100,)])
    assert run_live_instances.legacy_pending_gifts(plan) == 2


@contextmanager
def temporary_directory_retry():
    """Windows scanners can briefly retain a just-replaced/deleted key file."""
    directory = tempfile.TemporaryDirectory()
    assert Path(directory.name).resolve().parent == Path(tempfile.gettempdir()).resolve()
    try:
        yield directory.name
    finally:
        for attempt in range(10):
            try:
                directory.cleanup()
                break
            except OSError:
                if attempt == 9:
                    raise
                time.sleep(.05)


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
    def test_operator_bootstrap_is_local_atomic_rotated_and_owner_cleaned(self):
        with temporary_directory_retry() as folder:
            plan = {'runtime_mode':'production', 'state_dir':str(Path(folder) / 'private')}
            token, key_file = run_live_instances.prepare_operator_credentials(plan,
                {'LIVE_BRIDGE_LOCAL_TOKEN':'change_me_local_random_token'}, port_free=True)
            self.assertTrue(token and key_file.is_file())
            self.assertFalse(key_file.resolve().is_relative_to(run_live_instances.ROOT.resolve()))
            self.assertTrue(key_file.read_text().strip() == token)
            self.assertFalse(list(key_file.parent.glob('*.tmp')))
            rotated, same_file = run_live_instances.prepare_operator_credentials(plan, {}, port_free=True)
            self.assertTrue(rotated != token and same_file == key_file)
            run_live_instances.cleanup_operator_credentials(key_file, token)
            self.assertTrue(key_file.is_file(), 'old launcher must not remove replacement token')
            run_live_instances.cleanup_operator_credentials(key_file, rotated)
            self.assertFalse(key_file.exists())

    def test_operator_bootstrap_preserves_manual_or_occupied_credentials(self):
        with tempfile.TemporaryDirectory() as folder:
            plan = {'runtime_mode':'production', 'state_dir':folder}
            key_file = Path(folder) / 'operator-token.key'
            key_file.write_text('owner-fixture')
            token, generated = run_live_instances.prepare_operator_credentials(plan, {}, port_free=False)
            self.assertFalse(token)
            self.assertIsNone(generated)
            self.assertEqual(key_file.read_text(), 'owner-fixture')
            key_file.write_bytes(b'\xff\x00operator-changed')
            run_live_instances.cleanup_operator_credentials(key_file, 'old-fixture')
            self.assertEqual(key_file.read_bytes(), b'\xff\x00operator-changed')
            token, generated = run_live_instances.prepare_operator_credentials(plan,
                {'LIVE_BRIDGE_LOCAL_TOKEN':'manual-fixture'}, port_free=True)
            self.assertEqual(token, 'manual-fixture')
            self.assertIsNone(generated)
            self.assertEqual(key_file.read_bytes(), b'\xff\x00operator-changed')

    def test_operator_bootstrap_refuses_repository_and_preserves_previous_on_write_failure(self):
        with self.assertRaisesRegex(RuntimeError, 'fora'):
            run_live_instances.prepare_operator_credentials({'runtime_mode':'production',
                'state_dir':str(run_live_instances.ROOT / 'must-not-write-credentials')}, {}, port_free=True)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'operator-token.key'
            path.write_text('previous-fixture')
            with patch.object(run_live_instances.os, 'replace', side_effect=OSError('fixture')):
                with self.assertRaisesRegex(RuntimeError, 'credencial'):
                    run_live_instances.prepare_operator_credentials({'runtime_mode':'production',
                        'state_dir':folder}, {}, port_free=True)
            self.assertEqual(path.read_text(), 'previous-fixture')
            self.assertFalse(list(Path(folder).glob('*.tmp')))

    def test_production_launcher_bootstraps_admin_without_logging_secret_and_cleans_owned_file(self):
        with tempfile.TemporaryDirectory() as folder:
            plan = run_live_instances.build_plan('tiktok', runtime_mode='production')
            plan['state_dir'] = str(Path(folder) / 'production')
            plan['legacy_state_dir'] = str(Path(folder) / 'legacy')
            key_file = Path(plan['state_dir']) / 'operator-token.key'
            calls = 0
            def health(port):
                nonlocal calls
                calls += 1
                return None if calls == 1 else {'platform':'tiktok'}
            spawned = []
            def spawn(command, **kwargs):
                spawned.append(dict(kwargs['env']))
                if len(spawned) == 1:
                    self.assertTrue(key_file.read_text().strip() == kwargs['env']['LIVE_BRIDGE_LOCAL_TOKEN'])
                return FakeProcess()
            with patch.dict(os.environ, {'LIVE_BRIDGE_LOCAL_TOKEN':'change_me_local_random_token'}), \
                 patch.object(run_live_instances, 'health', side_effect=health), \
                 patch.object(run_live_instances, 'port_available', return_value=True), \
                 patch.object(run_live_instances.subprocess, 'Popen', side_effect=spawn), \
                 patch.object(run_live_instances, 'stay_awake', side_effect=lambda: nullcontext()), \
                 patch.object(run_live_instances.time, 'sleep', side_effect=KeyboardInterrupt), \
                 patch('builtins.print') as printed:
                self.assertEqual(run_live_instances.launch([plan]), 0)
            self.assertEqual(len(spawned), 2)
            secret = spawned[0]['LIVE_BRIDGE_LOCAL_TOKEN']
            self.assertTrue(secret != spawned[0]['LIVE_BRIDGE_ENGINE_TOKEN'] != spawned[0]['LIVE_BRIDGE_PRODUCER_TOKEN'])
            self.assertNotIn('LIVE_BRIDGE_LOCAL_TOKEN', spawned[1])
            rendered = '\n'.join(str(arg) for call in printed.call_args_list for arg in call.args)
            self.assertFalse(secret in rendered)
            self.assertTrue(str(key_file) in rendered)
            self.assertFalse(key_file.exists())

    def test_occupied_port_without_health_does_not_replace_operator_key_or_spawn(self):
        with tempfile.TemporaryDirectory() as folder:
            plan = run_live_instances.build_plan('tiktok', runtime_mode='production')
            plan['state_dir'] = folder
            path = Path(folder) / 'operator-token.key'
            path.write_text('existing-owner-fixture')
            with patch.dict(os.environ, {'LIVE_BRIDGE_LOCAL_TOKEN':''}), \
                 patch.object(run_live_instances, 'health', return_value=None), \
                 patch.object(run_live_instances, 'port_available', return_value=False), \
                 patch.object(run_live_instances.subprocess, 'Popen') as spawn, \
                 patch.object(run_live_instances, 'stay_awake', side_effect=lambda: nullcontext()), \
                 patch.object(run_live_instances.time, 'sleep', side_effect=KeyboardInterrupt):
                self.assertEqual(run_live_instances.launch([plan]), 0)
            spawn.assert_not_called()
            self.assertEqual(path.read_text(), 'existing-owner-fixture')

    def test_launcher_passes_separate_engine_and_producer_capabilities(self):
        with tempfile.TemporaryDirectory() as folder:
            plan = run_live_instances.build_plan('kwai', runtime_mode='production')
            plan['state_dir'] = str(Path(folder) / 'production')
            plan['legacy_state_dir'] = str(Path(folder) / 'legacy')
            calls = 0
            def health(port):
                nonlocal calls
                calls += 1
                return None if calls == 1 else {'platform':'kwai', 'platform_events_status':'connected'}
            spawned = []
            def spawn(command, **kwargs):
                spawned.append((command, dict(kwargs['env'])))
                return FakeProcess()
            with patch.dict(os.environ, {'LIVE_BRIDGE_LOCAL_TOKEN':'operator-fixture',
                    'LIVE_BRIDGE_ENGINE_TOKEN':'inherited-engine', 'LIVE_BRIDGE_PRODUCER_TOKEN':'inherited-producer'}), \
                 patch.object(run_live_instances, 'health', side_effect=health), \
                 patch.object(run_live_instances, 'port_available', return_value=True), \
                 patch.object(run_live_instances.subprocess, 'Popen', side_effect=spawn), \
                 patch.object(run_live_instances, 'stay_awake', side_effect=lambda: nullcontext()), \
                 patch.object(run_live_instances.time, 'sleep', side_effect=KeyboardInterrupt):
                self.assertEqual(run_live_instances.launch([plan]), 0)
            self.assertEqual(len(spawned), 3)
            bridge, game, collector = [entry[1] for entry in spawned]
            self.assertNotEqual(bridge['LIVE_BRIDGE_ENGINE_TOKEN'], bridge['LIVE_BRIDGE_PRODUCER_TOKEN'])
            self.assertEqual(bridge['LIVE_BRIDGE_LOCAL_TOKEN'], 'operator-fixture')
            self.assertEqual(game['LIVE_BRIDGE_ENGINE_TOKEN'], bridge['LIVE_BRIDGE_ENGINE_TOKEN'])
            self.assertNotIn('LIVE_BRIDGE_PRODUCER_TOKEN', game)
            self.assertNotIn('LIVE_BRIDGE_LOCAL_TOKEN', game)
            self.assertEqual(collector['LIVE_BRIDGE_PRODUCER_TOKEN'], bridge['LIVE_BRIDGE_PRODUCER_TOKEN'])
            self.assertNotIn('LIVE_BRIDGE_ENGINE_TOKEN', collector)
            self.assertNotIn('LIVE_BRIDGE_LOCAL_TOKEN', collector)

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
                 patch.object(run_live_instances, 'port_available', return_value=True), \
                 patch.object(run_live_instances.subprocess, 'Popen', side_effect=spawn), \
                 patch.object(run_live_instances, 'stay_awake', side_effect=lambda: nullcontext()), \
                 patch.object(run_live_instances.time, 'sleep', side_effect=KeyboardInterrupt):
                self.assertEqual(run_live_instances.launch(plans), 0)
            self.assertEqual(owner.read_text(encoding='utf-8'), 'existing owner status')
            self.assertEqual(len(processes), 2)
            self.assertTrue(all(process.terminated for process in processes))

    def test_failed_child_restarts_without_stopping_siblings(self):
        with temporary_directory_retry() as folder:
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
