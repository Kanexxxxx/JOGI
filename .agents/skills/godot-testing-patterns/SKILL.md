---
name: godot-testing-patterns
description: >
  Expert blueprint for automated testing in Godot 4.x using headless test scripts,
  gda script run / scene preflight, GUT (Godot Unit Test), signal assertions,
  mock live stream event injection, and orphan node leak checks.
---

# Godot Testing Patterns (4.x)

Automated validation of game logic, state machines, physics collisions, and simulated TikTok/Kwai live events.

## Core Rules (NEVER Do)

- **NEVER test private implementation details** — Test public methods, state transitions, and emitted signals.
- **NEVER share mutable state between tests** — Reset autoload/match state before each test case.
- **NEVER test random outcomes without seeding** — Call `seed(12345)` or use a dedicated `RandomNumberGenerator` with a fixed `seed` for deterministic race simulations.
- **NEVER skip cleanup** — Free instantiated nodes after each test and verify zero orphan nodes (`Performance.OBJECT_ORPHAN_NODE_COUNT == 0`).
- **NEVER depend on live TikTok/Kwai network connections in unit/integration tests** — Always inject deterministic mock events via `MockLiveEventProvider`.

## Headless Test Execution via `gda`

```powershell
# Validate script syntax & static types
C:\Users\Kanex\.local\bin\gda.exe script validate res://tests/test_race_state_machine.gd --json

# Run a headless SceneTree test script with strict exit code & leak checking
C:\Users\Kanex\.local\bin\gda.exe script run res://tests/test_race_state_machine.gd --strict --json
```
