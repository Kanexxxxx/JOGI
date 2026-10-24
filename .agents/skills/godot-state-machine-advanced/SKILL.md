---
name: godot-state-machine-advanced
description: >
  Expert blueprint for hierarchical finite state machines (HSM) and pushdown automata
  for complex AI, race lifecycle, and character behaviors in Godot 4.x. Covers state stacks,
  sub-states, transition validation, and state context passing. Use when implementing race states
  (Lobby, Countdown, Racing, PhotoFinish, Podium) or candidate runner AI states.
---

# Advanced State Machines (Godot 4.x)

Hierarchical states, state stacks, and context passing define deterministic behavior management for both match flow and 3D runners.

## Core Rules (NEVER Do)

- **NEVER forget to propagate `_physics_process(delta)` to the active state** — The state machine delegator must explicitly update its active child state every physics tick.
- **NEVER use deep nesting (>3 levels)** — Keep hierarchy flat (e.g., `MatchStateMachine` -> `RacingState`, and per-runner `RunnerStateMachine` -> `Running`, `Boosted`, `Stumble`, `Ragdoll`, `Finished`).
- **NEVER call `enter()` without calling `exit()` on the previous state** — Skipping `exit()` leaves timers, tweens, or particle emitters active and causes leaks.
- **NEVER mutate `current_state` directly from external nodes** — Always request transitions through `transition_to(state_name: StringName, msg: Dictionary = {})` with transition guard validation.

## Pattern: Typed Node-Based State Machine

```gdscript
extends Node
class_name StateMachine

signal state_changed(from_state: StringName, to_state: StringName)

@export var initial_state: State
var current_state: State
var states: Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is State:
			states[child.name] = child
			child.state_machine = self
	if initial_state:
		current_state = initial_state
		current_state.enter({})

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

func transition_to(target_name: StringName, context: Dictionary = {}) -> void:
	if not states.has(target_name):
		push_error("StateMachine: Unknown state %s" % target_name)
		return
	var next_state: State = states[target_name]
	if current_state == next_state:
		return
	var prev_name: StringName = current_state.name if current_state else &""
	if current_state:
		current_state.exit()
	current_state = next_state
	current_state.enter(context)
	state_changed.emit(prev_name, target_name)
```
