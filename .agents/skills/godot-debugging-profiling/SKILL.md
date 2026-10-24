---
name: godot-debugging-profiling
description: >
  Expert debugging workflows for Godot 4.x including structured logging (push_warning,
  push_error, assert), breakpoints, Godot Debugger (stack trace, remote debug), profiler
  (time profiler, memory monitor, orphan nodes), Performance.get_monitor(), and gda diag.
---

# Godot Debugging & Profiling (4.x)

Expert guidance for finding and fixing bugs and memory leaks in Godot 4.x and via `gda` CLI.

## Core Rules (NEVER Do)

- **NEVER use bare `print(value)` without context** — Always include subsystem prefix, e.g., `print("[RaceManager] Candidate finished: ", candidate_id)`.
- **NEVER leave per-frame `print()` in `_process` or `_physics_process`** — Causes severe I/O stalls during live streams.
- **NEVER ignore `push_warning()` or GDScript static type warnings** — Treat warnings as errors before commit.
- **NEVER use `assert()` for runtime external input validation** — `assert()` is stripped in release builds. Always validate external WebSocket/TikTok/Kwai payloads with explicit `if not condition: push_warning(...); return`.
- **NEVER rely on `OS.get_ticks_msec()` for micro-benchmarking** — Use `Time.get_ticks_usec()`.
- **NEVER leave orphan nodes after round resets** — Monitor `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)` after every match reset.

## Headless & Live Diagnostics with `gda`

```powershell
# Static validation of scripts and scenes
C:\Users\Kanex\.local\bin\gda.exe script validate res://scripts/race_manager.gd --json
C:\Users\Kanex\.local\bin\gda.exe scene validate res://scenes/main_arena.tscn --json

# Bounded runtime preflight check
C:\Users\Kanex\.local\bin\gda.exe scene preflight res://scenes/main_arena.tscn --json

# Live session error and performance inspection
C:\Users\Kanex\.local\bin\gda.exe diag errors --json
C:\Users\Kanex\.local\bin\gda.exe diag perf --json
```
