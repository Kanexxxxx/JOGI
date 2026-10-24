---
name: godot-signals-groups
description: >
  Build event-driven, decoupled Godot 4.x gameplay with signals and node groups:
  declare and emit custom typed signals, connect with Callables (incl. bind/one-shot),
  and broadcast to many nodes via groups and call_group. Use when wiring node
  communication in a Godot project, routing live stream gift/like/comment events,
  or decoupling HUD from 3D race entities.
---

# Godot Signals & Groups (4.x)

Decouple nodes with the observer pattern (signals) and act on categories of nodes (groups) without hard-coding scene paths.

## Core Workflow

1. **Signal Up, Call Down.** A child scene emits a signal upward (`signal finished_lap(candidate_id: StringName)`); the parent or coordinator connects to it (`runner.finished_lap.connect(_on_runner_finished_lap)`).
2. **EventBus Autoload for Cross-System Events.** For live stream interactions (`gift_received`, `comment_vote_registered`, `like_burst_triggered`), emit typed signals from a dedicated `LiveEventBus` autoload so HUD overlays, audio managers, and arena spawners react independently.
3. **Connect with Godot 4 Callables:**
   ```gdscript
   LiveEventBus.gift_received.connect(_on_gift_received)
   ```
4. **Disconnect or guard long-lived listeners** when scenes unload.
5. **Use Groups (`"candidates"`, `"dynamic_obstacles"`)** to broadcast arena-wide effects (e.g. `get_tree().call_group("candidates", "apply_earthquake_stumble", 1.5)`).
