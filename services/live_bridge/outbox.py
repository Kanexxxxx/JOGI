"""Bounded SQLite gift outbox; accepted before send, completed only by consumer ACK."""

from __future__ import annotations

import json
from pathlib import Path
import sqlite3
import time
from typing import Any


class GiftOutbox:
    def __init__(self, path: Path | None, *, platform: str, capacity: int = 5000,
                 retained_limit: int = 50_000, retention_hours: float = 36.0) -> None:
        self.capacity = max(1, capacity)
        self.retained_limit = max(1, retained_limit)
        self.retention_ms = int(retention_hours * 3600 * 1000)
        self.path = path
        self._lock_file: Any = None
        self._closed = False
        self._completed_since_prune = 0
        if path is not None:
            path.parent.mkdir(parents=True, exist_ok=True)
            self._acquire_lock(path.with_suffix(path.suffix + ".lock"))
        try:
            self.db = sqlite3.connect(str(path) if path else ":memory:")
            self.db.execute("PRAGMA journal_mode=WAL")
            self.db.execute("PRAGMA synchronous=FULL")
            self.db.execute("PRAGMA busy_timeout=1000")
            self.db.execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            row = self.db.execute("SELECT value FROM metadata WHERE key='platform'").fetchone()
            if row is not None and row[0] != platform:
                raise ValueError("Outbox pertence a outra plataforma; use arquivos separados.")
            self.db.execute("INSERT OR IGNORE INTO metadata VALUES ('platform', ?)", (platform,))
            self.db.execute("""CREATE TABLE IF NOT EXISTS gifts (
                event_id TEXT PRIMARY KEY, envelope TEXT NOT NULL, created_ms INTEGER NOT NULL,
                completed_ms INTEGER, retry_ms INTEGER NOT NULL DEFAULT 0, attempts INTEGER NOT NULL DEFAULT 0
            )""")
            self.db.execute("CREATE INDEX IF NOT EXISTS pending_gifts ON gifts(completed_ms, retry_ms, created_ms)")
            self.db.execute("UPDATE gifts SET retry_ms=0 WHERE completed_ms IS NULL")
            self.db.commit()
            self.prune()
        except Exception:
            if hasattr(self, "db"):
                self.db.close()
            self._release_lock()
            raise

    def _acquire_lock(self, path: Path) -> None:
        self._lock_file = path.open("a+b")
        self._lock_file.seek(0, 2)
        if self._lock_file.tell() == 0:
            self._lock_file.write(b"0")
            self._lock_file.flush()
        self._lock_file.seek(0)
        try:
            import msvcrt
            msvcrt.locking(self._lock_file.fileno(), msvcrt.LK_NBLCK, 1)
        except ImportError:
            import fcntl
            fcntl.flock(self._lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            self._lock_file.close()
            self._lock_file = None
            raise RuntimeError("Outbox já está em uso por outra instância.") from exc

    def _release_lock(self) -> None:
        if self._lock_file is None:
            return
        try:
            self._lock_file.seek(0)
            try:
                import msvcrt
                msvcrt.locking(self._lock_file.fileno(), msvcrt.LK_UNLCK, 1)
            except ImportError:
                import fcntl
                fcntl.flock(self._lock_file.fileno(), fcntl.LOCK_UN)
        finally:
            self._lock_file.close()
            self._lock_file = None

    def pending_count(self) -> int:
        return int(self.db.execute("SELECT COUNT(*) FROM gifts WHERE completed_ms IS NULL").fetchone()[0])

    def contains(self, event_id: str) -> bool:
        return self.db.execute("SELECT 1 FROM gifts WHERE event_id=?", (event_id,)).fetchone() is not None

    def accept(self, envelope: dict[str, Any]) -> str:
        if self.contains(envelope["event_id"]):
            return "duplicate"
        if self.pending_count() >= self.capacity:
            return "busy"
        serialized = json.dumps(envelope, ensure_ascii=False, separators=(",", ":"))
        with self.db:
            self.db.execute("INSERT INTO gifts(event_id,envelope,created_ms) VALUES(?,?,?)",
                            (envelope["event_id"], serialized, int(time.time() * 1000)))
        return "accepted"

    def next_due(self, now_ms: int | None = None) -> dict[str, Any] | None:
        now = int(time.time() * 1000) if now_ms is None else now_ms
        row = self.db.execute("""SELECT envelope FROM gifts WHERE completed_ms IS NULL
            AND retry_ms<=? ORDER BY created_ms,rowid LIMIT 1""", (now,)).fetchone()
        return json.loads(row[0]) if row else None

    def mark_attempt(self, event_id: str, retry_seconds: float) -> None:
        with self.db:
            self.db.execute("UPDATE gifts SET attempts=attempts+1,retry_ms=? WHERE event_id=? AND completed_ms IS NULL",
                            (int(time.time() * 1000 + retry_seconds * 1000), event_id))

    def make_due(self, event_id: str | None = None) -> None:
        with self.db:
            if event_id:
                self.db.execute("UPDATE gifts SET retry_ms=0 WHERE event_id=? AND completed_ms IS NULL", (event_id,))
            else:
                self.db.execute("UPDATE gifts SET retry_ms=0 WHERE completed_ms IS NULL")

    def acknowledge(self, event_id: str) -> bool:
        with self.db:
            cursor = self.db.execute("UPDATE gifts SET completed_ms=? WHERE event_id=? AND completed_ms IS NULL AND attempts>0",
                                     (int(time.time() * 1000), event_id))
        acknowledged = bool(cursor.rowcount)
        if acknowledged:
            self._completed_since_prune += 1
            if self._completed_since_prune >= 100:
                self.prune()
                self._completed_since_prune = 0
        return acknowledged

    def prune(self) -> None:
        cutoff = int(time.time() * 1000) - self.retention_ms
        with self.db:
            self.db.execute("DELETE FROM gifts WHERE completed_ms IS NOT NULL AND completed_ms<?", (cutoff,))
            self.db.execute("""DELETE FROM gifts WHERE event_id IN (
                SELECT event_id FROM gifts WHERE completed_ms IS NOT NULL
                ORDER BY completed_ms DESC LIMIT -1 OFFSET ?
            )""", (self.retained_limit,))

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        try:
            self.db.close()
        finally:
            self._release_lock()
