---
name: godot-3d-essentials
description: >
  Set up a Godot 4.x 3D scene: Node3D transforms, Camera3D, lighting
  (DirectionalLight3D/OmniLight3D), WorldEnvironment for sky/ambient/tonemap/post,
  MeshInstance3D materials, and GridMap/Modular track segments for 3D levels. Use when building
  a 3D scene in a Godot project, placing cameras/lights, configuring environment and
  post-processing, or working with Node3D/.tscn 3D content.
---

# Godot 3D Essentials (4.x)

Assemble a working 3D scene: transforms, camera, lights, environment/post, materials, and modular 3D track blockouts. Targets **Godot 4.x**.

## When to use

- Use when starting or fixing a 3D scene: positioning a `Camera3D`, adding lights, setting up a `WorldEnvironment` (sky, ambient, tonemap, glow/SSAO), assigning materials, or building 3D race tracks.

**When *not* to use:** writing spatial shaders → `godot-shaders`; 3D physics bodies and raycasts → `godot-physics-3d`; character animation blending → `godot-animation`.

## Core workflow

1. **Everything 3D is a `Node3D`** with a `Transform3D` (position, rotation basis, scale). Move with `global_position`, rotate with `rotate_y(angle)` or `look_at(target)`.
2. **Add a `Camera3D`.** Mark it `current` (or call `make_current()`); set `fov`, `near`, `far`. Parent it to a rig/pivot for broadcast race tracking cameras.
3. **Light the scene.** A `DirectionalLight3D` is the sun; `OmniLight3D`/`SpotLight3D` are local. Enable shadows carefully for live-stream performance.
4. **Add a `WorldEnvironment`** with an `Environment` resource: background (sky/color), ambient light, tonemap (`TONE_MAPPER_ACES` or `FILMIC`), and post-processing.
5. **Give meshes materials** (`StandardMaterial3D` or `ShaderMaterial`) on `MeshInstance3D`.

## Patterns

### 1. Broadcast Race Follow Camera (smoothed leader tracking)

```gdscript
extends Camera3D

@export var target: Node3D
@export var offset: Vector3 = Vector3(0.0, 5.5, 9.0)
@export var smooth: float = 6.0

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var desired: Vector3 = target.global_position + offset
	global_position = global_position.lerp(desired, smooth * delta)
	look_at(target.global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP)
```
