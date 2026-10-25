"""Account-local team history; no nicknames, credentials or chat text."""
from __future__ import annotations
import json
import sqlite3
import time
from pathlib import Path
from typing import Any
from .normalization import read_field


def stable_user_id(event: Any) -> str | None:
    user = read_field(event, "user")
    value = (read_field(user, "id") or read_field(user, "user_id") or read_field(user, "sec_uid") or read_field(event, "user_id"))
    if value is None or isinstance(value, bool):
        return None
    clean = str(value).strip()
    if not clean or clean in ("0", "None", "anon_tiktok", "anon_kwai") or len(clean) > 128 or any(ord(c) < 33 for c in clean):
        return None
    return clean


def event_time_ms(event: Any) -> int:
    common = read_field(event, "common")
    value = read_field(event, "timestamp_ms") or read_field(common, "create_time")
    try:
        stamp = int(value or 0)
        if 0 < stamp < 100_000_000_000:
            stamp *= 1000
        if 1_500_000_000_000 <= stamp <= int(time.time()*1000)+300_000:
            return stamp
    except (ValueError, TypeError, OverflowError):
        pass
    return int(time.time()*1000)


class TikTokTeams:
    def __init__(self, path: str | Path | None = None, *, account: str = "") -> None:
        if path:
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(path) if path else ":memory:")
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.execute("PRAGMA busy_timeout=1000")
        self.db.execute("CREATE TABLE IF NOT EXISTS owner(account TEXT NOT NULL)")
        stored=self.db.execute("SELECT account FROM owner LIMIT 1").fetchone()
        if stored and stored[0] != account:
            self.db.close()
            raise ValueError("Team store belongs to a different account")
        if not stored:
            self.db.execute("INSERT INTO owner VALUES(?)", (account,))
        self.db.execute("CREATE TABLE IF NOT EXISTS teams(user_id TEXT NOT NULL, at_ms INTEGER NOT NULL, packet TEXT NOT NULL UNIQUE, slot INTEGER NOT NULL CHECK(slot IN(1,2)))")
        self.db.execute("CREATE INDEX IF NOT EXISTS team_age ON teams(at_ms)")
        self.db.execute("CREATE INDEX IF NOT EXISTS team_time ON teams(user_id,at_ms)")
        self.db.execute("CREATE TABLE IF NOT EXISTS gift_pending(event_id TEXT PRIMARY KEY,envelope TEXT NOT NULL)")
        self.db.execute("CREATE TABLE IF NOT EXISTS gift_tracker(key TEXT PRIMARY KEY,state TEXT NOT NULL)")
        self.db.commit()

    def choose(self, user_id: str, slot: int, at_ms: int, packet: str) -> None:
        with self.db:
            self.db.execute("INSERT OR IGNORE INTO teams VALUES(?,?,?,?)", (user_id,at_ms,packet,slot))
            self.db.execute("DELETE FROM teams WHERE at_ms < ?", (int(time.time()*1000)-48*3600*1000,))

    def team(self, user_id: str | None, at_ms: int, *, coarse: bool = False) -> int | None:
        if not user_id:
            return None
        if coarse:
            choices=self.db.execute("SELECT COUNT(DISTINCT slot) FROM teams WHERE user_id=? AND at_ms=?", (user_id,at_ms)).fetchone()[0]
            if choices > 1:
                return None  # Second-resolution timestamps cannot order a same-second switch safely.
        row=self.db.execute("SELECT slot FROM teams WHERE user_id=? AND at_ms<=? ORDER BY at_ms DESC,rowid DESC LIMIT 1",(user_id,at_ms)).fetchone()
        return int(row[0]) if row else None

    def stage_gifts(self, envelopes: list[dict], tracker: dict) -> None:
        with self.db:
            for envelope in envelopes:
                self.db.execute("INSERT OR IGNORE INTO gift_pending VALUES(?,?)", (envelope["event_id"],json.dumps(envelope)))
            self.db.execute("INSERT OR REPLACE INTO gift_tracker VALUES('state',?)", (json.dumps(tracker),))

    def pending_gifts(self) -> list[dict]:
        return [json.loads(row[0]) for row in self.db.execute("SELECT envelope FROM gift_pending ORDER BY rowid")]

    def acknowledge_gift(self, event_id: str) -> None:
        with self.db:
            self.db.execute("DELETE FROM gift_pending WHERE event_id=?", (event_id,))

    def tracker_state(self) -> dict:
        row=self.db.execute("SELECT state FROM gift_tracker WHERE key='state'").fetchone()
        return json.loads(row[0]) if row else {}

    def save_collector_state(self, state: dict) -> None:
        with self.db:
            self.db.execute("INSERT OR REPLACE INTO gift_tracker VALUES('collector',?)", (json.dumps(state),))

    def collector_state(self) -> dict:
        row=self.db.execute("SELECT state FROM gift_tracker WHERE key='collector'").fetchone()
        return json.loads(row[0]) if row else {}
