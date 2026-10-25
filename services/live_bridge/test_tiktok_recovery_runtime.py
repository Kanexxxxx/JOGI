"""Recovery contracts; fixtures never use production sessions or platform requests."""
import json
from pathlib import Path
import sqlite3
import sys
import ctypes
import unittest
from unittest.mock import patch
from unittest.mock import MagicMock

TOOLS = Path(__file__).resolve().parents[2] / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import backup_tiktok_session as backup
import windows_visible_game as visible


def test_backup_includes_committed_wal_and_preserves_source(tmp_path):
    source = tmp_path / "source.sqlite3"
    connection = sqlite3.connect(source)
    try:
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA wal_autocheckpoint=0")
        connection.execute("CREATE TABLE gifts (event_id TEXT, completed_ms INTEGER)")
        connection.executemany("INSERT INTO gifts VALUES (?,?)", [("pending", None), ("acked", 100)])
        connection.commit()
        assert Path(str(source) + "-wal").is_file()
        result = backup.backup_sqlite(source, tmp_path / "backup.sqlite3")
        assert result["integrity"] == "ok" and result["pending_gifts"] == 1
        assert connection.execute("SELECT COUNT(*) FROM gifts").fetchone()[0] == 2
    finally:
        connection.close()


def test_session_backup_preserves_checkpoint_journal_and_private_key(tmp_path):
    state, game = tmp_path / "state", tmp_path / "game"
    state.mkdir(); game.mkdir()
    key = state / "operator-token.key"
    key.write_text("fixture-local-only", encoding="utf-8")
    (game / "snapshot.json").write_text(json.dumps({"channel": "tiktok", "schema_version": 1,
        "state": {"journal_cursor": 0, "match": {"current_round": 17, "race_paused": True}}}), encoding="utf-8")
    (game / "gifts.jsonl").write_text('{"event_id":"fixture"}\n', encoding="utf-8")
    result = backup.backup_session(state, game, tmp_path / "backup")
    assert result["checkpoint"]["current_round"] == 17
    assert (tmp_path / "backup/backend/operator-token.key").read_bytes() == key.read_bytes()
    assert "fixture-local-only" not in json.dumps(result)
    assert (tmp_path / "backup/game/gifts.jsonl").read_bytes() == (game / "gifts.jsonl").read_bytes()


def test_backup_rejects_cursor_outside_record_boundary(tmp_path):
    (tmp_path / "gifts.jsonl").write_bytes(b'{"event_id":"fixture"}\n')
    for cursor in (7, 1000, -1, True):
        (tmp_path / "snapshot.json").write_text(json.dumps({"channel": "tiktok", "schema_version": 1,
            "state": {"journal_cursor": cursor}}), encoding="utf-8")
        with unittest.TestCase().assertRaises(RuntimeError):
            backup.validate_checkpoint_journal(tmp_path)


def test_visible_runtime_refuses_headless():
    with unittest.TestCase().assertRaises(ValueError):
        visible.spawn_tiktok_game(["godot.exe", "--headless"], cwd=".", env={})


def test_visible_spawn_uses_explicit_interactive_process():
    with patch.object(visible.os, "name", "nt"), patch.object(visible, "InteractiveGameProcess") as spawn:
        visible.spawn_tiktok_game(["godot.exe", "--windowed"], cwd="C:/fixture", env={"LIVE_ACCOUNT": "xinka_"})
        spawn.assert_called_once_with(["godot.exe", "--windowed"], cwd="C:/fixture", env={"LIVE_ACCOUNT": "xinka_"})


def test_native_startup_accepts_pathlib_and_selects_visible_desktop():
    kernel = MagicMock()
    def create(exe, command, sa, ta, inherit, flags, environment, cwd, startup_ptr, process_ptr):
        assert isinstance(exe, str) and isinstance(cwd, str)
        startup = ctypes.cast(startup_ptr, ctypes.POINTER(visible._StartupInfo)).contents
        assert startup.lpDesktop == "winsta0\\default"
        assert startup.dwFlags == 1 and startup.wShowWindow == 1
        assert inherit is False and flags == 0x400
        info = ctypes.cast(process_ptr, ctypes.POINTER(visible._ProcessInfo)).contents
        info.dwProcessId, info.hProcess, info.hThread = 123, 456, 789
        return True
    kernel.CreateProcessW.side_effect = create
    with patch.object(visible.os, "name", "nt"), patch.object(visible.ctypes, "WinDLL", return_value=kernel):
        child = visible.InteractiveGameProcess([Path("godot.exe")], cwd=Path("."), env={"FIXTURE": "ação"})
        assert child.pid == 123
        kernel.CloseHandle.assert_called_once_with(789)
