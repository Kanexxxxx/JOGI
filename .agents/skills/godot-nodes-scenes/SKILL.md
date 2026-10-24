---
name: godot-nodes-scenes
description: >
  Structure a Godot 4.x project with the scene tree and node composition: build
  reusable scenes, instance PackedScenes at runtime, navigate the tree safely,
  and register autoload singletons. Use when designing .tscn scenes, deciding how
  to split nodes, spawning instances with instantiate(), wiring autoloads, or
  fixing "node not found"/freed-node errors in a Godot project.
---

# Godot Nodes & Scenes (4.x)

Compose games from nodes and scenes, instance them at runtime, and access the tree without crashing on freed or missing nodes.

## Core Workflow

1. **Model with composition.** Build small, single-purpose scenes (`CandidateRunner.tscn`, `ObstacleGate.tscn`, `TrackSegment.tscn`, `LiveToastHUD.tscn`) and compose larger scenes (`RaceArena.tscn`) from them. Favor composition over deep inheritance.
2. **Make a scene reusable** by giving its root a typed script and exposing `@export` configuration properties.
3. **Instance at runtime** with `preload`/`load` → `scene.instantiate()` → `add_child(instance)`.
4. **Access nodes safely.** Use `@onready var x: Node = $Path` for fixed children; use scene-unique names (`%NodeName`) for UI/HUD elements that may move inside containers; guard dynamic references with `is_instance_valid(node)`.
5. **Free nodes safely** with `queue_free()` at the end of the frame.
