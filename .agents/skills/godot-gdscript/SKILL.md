---
name: godot-gdscript
description: >
  Write idiomatic GDScript for Godot 4.x: static typing, the node lifecycle
  (_ready/_process/_physics_process), @export/@onready/@tool annotations,
  signals, and await for asynchronous flow. Use when editing .gd scripts in a
  Godot project (project.godot), writing or debugging GDScript, or porting 3.x
  GDScript to 4.x.
---

# Godot GDScript (4.x)

Write correct, statically typed GDScript and use the node lifecycle and signal system the way the engine intends. Targets **Godot 4.x** (GDScript 2.0).

## When to use

- Use when writing or fixing `.gd` files: declaring variables, functions, classes, using `@export`/`@onready`, connecting signals, or awaiting coroutines/signals.
- Use when porting Godot 3.x scripts to 4.x and the script no longer parses.

**When *not* to use:** scene/node structure and instancing questions → `godot-nodes-scenes`; signal *architecture*/decoupling patterns → `godot-signals-groups`.

## Core workflow

1. **Type everything you can.** GDScript 2.0 supports static types (`var hp: int = 10`, `func add(a: int, b: int) -> int:`). Types catch errors at parse time and speed up the VM. Use `:=` for inferred types.
2. **Use the lifecycle callbacks for their purpose:** `_ready()` once when the node and its children enter the tree; `_process(delta)` every rendered frame; `_physics_process(delta)` on the fixed physics tick (use it for movement/physics).
3. **Grab node references with `@onready`**, not in `_init()` — children do not exist until the node enters the tree.
4. **Expose tunables with `@export`** so designers edit them in the Inspector.
5. **React to events with signals + `await`**, not polling, where it reads cleanly.
6. **Run and read errors.** Fix the first parse/type error first (later ones are often cascades).

## Patterns

### 1. A typed script with lifecycle, @export, and @onready

```gdscript
extends Node3D
class_name CandidateRunner

@export var base_speed: float = 8.0
@export_range(0.0, 20.0, 0.5) var boost_multiplier: float = 1.5
@onready var anim_tree: AnimationTree = $AnimationTree

func _ready() -> void:
	anim_tree.active = true

func _physics_process(delta: float) -> void:
	global_position.z -= base_speed * delta
```

### 2. Typed signals and async `await`

```gdscript
signal boost_activated(candidate_id: StringName, duration: float)

func apply_boost(candidate_id: StringName, duration: float) -> void:
	boost_activated.emit(candidate_id, duration)
	await get_tree().create_timer(duration).timeout
```
