---
name: godot-physics-3d
description: >
  Expert patterns for Godot 4.x 3D physics (Jolt/GodotPhysics3D), including CharacterBody3D,
  RigidBody3D, Area3D triggers, PhysicalBones/Ragdolls, Joint3D constraints, ShapeCast3D/RayCast3D
  optimizations, and collision layers/masks. Use for 3D character controllers, obstacle physics,
  ragdoll knockbacks, and trigger zones.
---

# Godot 3D Physics (4.x)

Expert guidance for high-performance 3D physics, collision matrices, obstacle interactions, and ragdolls.

## NEVER Do

- **NEVER move `PhysicsBody3D` nodes in `_process()`** — Use `_physics_process(delta)`. Moving bodies outside the physics step causes visual jitter and unreliable collision detection.
- **NEVER scale collision shapes directly** — Scaling `CollisionShape3D` nodes causes solver instability and inaccurate normals. Modify the `shape` resource dimensions (`radius`, `height`, `size`) instead.
- **NEVER modify `RigidBody3D` transforms directly during simulation** — Use `apply_central_impulse()`, `apply_force()`, or `_integrate_forces(state)`.
- **NEVER use `RigidBody3D` for primary lane/track runners** — Use `CharacterBody3D` with `move_and_slide()` for deterministic, responsive runner movement and obstacle pushback.
- **NEVER leave all objects on collision layer 1** — Define explicit bitmask layers (e.g., Layer 1: Track/Static, Layer 2: Candidates, Layer 3: Obstacles/Hazards, Layer 4: Pickups/Triggers).
- **NEVER use `PhysicsServer3D` RIDs without manual cleanup** — Call `PhysicsServer3D.free_rid()` when freeing server-managed bodies/shapes.

## Recommended Collision Matrix (Corrida dos Candidatos)

| Layer Bit | Name | Collides With (Mask) |
|---|---|---|
| 1 | `track_static` | Candidates (2), Dynamic Obstacles (3) |
| 2 | `candidates` | Track (1), Candidates (2), Obstacles (3), Triggers (4) |
| 3 | `obstacles` | Track (1), Candidates (2) |
| 4 | `triggers_finish` | Candidates (2) |

## Patterns

### 1. Configurar Layers e Masks via Código

```gdscript
func configure_candidate_collision(body: CharacterBody3D) -> void:
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_collision_layer_value(2, true) # Layer 2: candidates
	body.set_collision_mask_value(1, true)  # Collide with track
	body.set_collision_mask_value(2, true)  # Collide with other candidates
	body.set_collision_mask_value(3, true)  # Collide with obstacles
	body.set_collision_mask_value(4, true)  # Detect triggers/finish line
```
