"""Per-process supervision for local live sessions, with bounded restart windows."""
from __future__ import annotations

from collections import deque
from contextlib import contextmanager
from dataclasses import dataclass, field
import json
import os
from pathlib import Path
import subprocess
import time
from typing import Any, Callable


@dataclass
class ManagedChild:
    platform: str
    kind: str
    spawn: Callable[[], Any]
    ready: Callable[[], bool] = lambda: True
    process: Any = None
    attempts: int = 0
    failures: int = 0
    next_start: float = 0
    started_at: float = 0
    requires_attention: bool = False
    last_exit: str | int | None = None
    restarts: deque[float] = field(default_factory=deque)

    def tick(self, now: float) -> bool:
        while self.restarts and now - self.restarts[0] >= 600:
            self.restarts.popleft()
        if self.process is not None:
            code = self.process.poll()
            if code is None:
                if now - self.started_at >= 60:
                    self.failures = 0
                return False
            self.last_exit = code
            self.process = None
            self.failures += 1
            self.next_start = now + min(30, 2 ** min(self.failures - 1, 5))
            return True
        if self.requires_attention or now < self.next_start or not self.ready():
            return False
        if self.attempts:
            if len(self.restarts) >= 6:
                self.requires_attention = True
                return True
            self.restarts.append(now)
        self.attempts += 1
        try:
            self.process = self.spawn()
            self.started_at = now
        except OSError as error:
            self.last_exit = type(error).__name__
            self.failures += 1
            self.next_start = now + min(30, 2 ** min(self.failures - 1, 5))
        return True

    def snapshot(self, now: float) -> dict[str, Any]:
        return {"kind": self.kind, "state": "needs_attention" if self.requires_attention else "running" if self.process is not None else "waiting_restart_or_dependency",
                "pid": getattr(self.process, "pid", None), "attempts": self.attempts,
                "restarts_last_10min": len(self.restarts), "last_exit": self.last_exit,
                "retry_in_seconds": max(0, round(self.next_start - now, 1))}

    def stop(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.process = None


class LiveSupervisor:
    def __init__(self, children: list[ManagedChild], state_dirs: dict[str, Path]) -> None:
        self.children = children
        self.state_dirs = state_dirs
        self._last_publish = -100.0

    def step(self, now: float) -> None:
        changed = False
        for child in self.children:
            try:
                child_changed = child.tick(now)
            except Exception as error:
                child.requires_attention = True
                child.last_exit = type(error).__name__
                child_changed = True
            if child_changed:
                changed = True
                item = child.snapshot(now)
                print(f"{child.platform}/{child.kind}: {item['state']} · tentativa {child.attempts} · último resultado {child.last_exit}", flush=True)
        if changed or now - self._last_publish >= 10:
            self.publish(now)
            self._last_publish = now

    def publish(self, now: float, *, stopped: bool = False) -> None:
        for platform, directory in self.state_dirs.items():
            try:
                directory.mkdir(parents=True, exist_ok=True)
                payload = {"platform": platform, "updated_ms": int(time.time() * 1000), "launcher_stopped": stopped,
                           "children": [child.snapshot(now) for child in self.children if child.platform == platform]}
                temp = directory / "watchdog_status.tmp"
                temp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
                os.replace(temp, directory / "watchdog_status.json")
            except OSError:
                print(f"{platform}: não foi possível gravar status do watchdog; demais processos preservados.", flush=True)

    def shutdown(self) -> None:
        for child in reversed(self.children):
            try:
                child.stop()
            except OSError:
                print(f"{child.platform}/{child.kind}: encerramento precisa de verificação manual.", flush=True)
        self.publish(time.monotonic(), stopped=True)


@contextmanager
def stay_awake(kernel: Any = None):
    """Thread-scoped Windows request, always restored when launcher exits normally."""
    if kernel is None and os.name != "nt":
        yield False
        return
    if kernel is None:
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.SetThreadExecutionState.argtypes = [wintypes.DWORD]
        kernel.SetThreadExecutionState.restype = wintypes.DWORD
    previous = kernel.SetThreadExecutionState(0x80000003)
    try:
        yield bool(previous)
    finally:
        kernel.SetThreadExecutionState(previous or 0x80000000)
