"""Consistent local TikTok backup. No PowerShell -c quoting or credential output."""
from __future__ import annotations
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3


def validate_checkpoint_journal(directory: Path) -> dict:
    checkpoint = json.loads((directory / "snapshot.json").read_text(encoding="utf-8"))
    if checkpoint.get("channel") != "tiktok" or checkpoint.get("schema_version") != 1 or not isinstance(checkpoint.get("state"), dict):
        raise RuntimeError("Invalid TikTok checkpoint")
    saved = checkpoint["state"]
    cursor = saved.get("journal_cursor")
    journal = directory / "gifts.jsonl"
    data = journal.read_bytes() if journal.exists() else b""
    if type(cursor) is not int or cursor < 0 or cursor > len(data) or (cursor > 0 and data[cursor - 1] != 10):
        raise RuntimeError("Checkpoint cursor is not a journal record boundary")
    if data and not data.endswith(b"\n"):
        raise RuntimeError("Incomplete gift journal record")
    for line in data.splitlines():
        if line.strip():
            json.loads(line)
    return saved


def backup_sqlite(source: Path, destination: Path) -> dict:
    destination.parent.mkdir(parents=True, exist_ok=True)
    # SQLite's backup API includes committed WAL pages in a coherent destination.
    with closing(sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True, timeout=10)) as src:
        with closing(sqlite3.connect(destination)) as dst:
            src.backup(dst, pages=256, sleep=.05)
            check = dst.execute("PRAGMA integrity_check").fetchall()
            if check != [("ok",)]:
                raise RuntimeError("SQLite backup integrity check failed")
            tables = [row[0] for row in dst.execute("SELECT name FROM sqlite_master WHERE type='table'")]
            pending = dst.execute("SELECT COUNT(*) FROM gifts WHERE completed_ms IS NULL").fetchone()[0] if "gifts" in tables else None
    return {"integrity": "ok", "tables": len(tables), "pending_gifts": pending,
            "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}


def backup_session(state: Path, game: Path, target: Path) -> dict:
    if not state.is_dir() or not game.is_dir():
        raise RuntimeError("Missing state or game directory; no process may be stopped")
    target.mkdir(parents=True, exist_ok=False)
    report = {"schema": 1, "sqlite": {}, "files": {}, "checkpoint": {}}
    for label, source in (("backend", state), ("game", game)):
        for file in sorted(source.rglob("*")):
            if not file.is_file():
                continue
            if file.is_symlink() or not file.resolve().is_relative_to(source.resolve()):
                raise RuntimeError("Unexpected link in session backup")
            relative = Path(label) / file.relative_to(source)
            destination = target / relative
            if file.name.endswith(("-wal", "-shm", ".lock")) or file.suffix == ".tmp":
                continue  # Never restore an old WAL on top of a SQLite API backup.
            destination.parent.mkdir(parents=True, exist_ok=True)
            if file.suffix in (".sqlite3", ".sqlite", ".db"):
                report["sqlite"][str(relative)] = backup_sqlite(file, destination)
            else:
                before = file.read_bytes()
                destination.write_bytes(before)
                if before != file.read_bytes():
                    raise RuntimeError("Session file changed during backup; keep processes running and retry after pausing")
                report["files"][str(relative)] = hashlib.sha256(before).hexdigest()
    saved = validate_checkpoint_journal(target / "game")
    # Cross-file consistency matters: no checkpoint/journal may change after its copy.
    for name in ("snapshot.json", "gifts.jsonl"):
        original, copied = game / name, target / "game" / name
        if original.exists() != copied.exists() or (original.exists() and original.read_bytes() != copied.read_bytes()):
            raise RuntimeError("Checkpoint/journal changed across backup; pause and retry")
    report["checkpoint"] = {key: saved.get("match", {}).get(key) for key in
                            ("current_round", "cycle_number", "match_time_remaining", "race_paused")}
    report["checkpoint"]["journal_cursor"] = saved.get("journal_cursor")
    (target / "manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--game", required=True, type=Path)
    parser.add_argument("--target", required=True, type=Path)
    args = parser.parse_args()
    result = backup_session(args.state, args.game, args.target)
    print(json.dumps({"backup": str(args.target), "sqlite": result["sqlite"], "checkpoint": result["checkpoint"]}))
