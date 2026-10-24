---
name: godot-animation
description: >
  Animate in Godot 4.x three ways: AnimationPlayer for keyframed clips (incl. call
  and signal tracks), AnimationTree with state machines and blend spaces for 3D
  character animation, and Tween for short procedural/UI tweens via create_tween().
  Use when working with AnimationPlayer/AnimationTree nodes, blending 3D candidate
  runner animations (idle, run, boost, stumble, victory), or code-driven UI Tweens.
---

# Godot Animation (4.x)

Choose and drive the right animation tool: `AnimationPlayer` (clips), `AnimationTree` (blending/state machines for 3D rigged characters), or `Tween` (short procedural UI/camera moves).

## Core Workflow

1. **Pick the tool:**
   - `AnimationPlayer`: Author/store keyframed clips imported from `.glb` (Tripo/Mixamo/Blender).
   - `AnimationTree`: Blend and transition between clips at runtime (`AnimationNodeStateMachine` or `AnimationNodeBlendSpace1D`). Set `active = true` and assign `anim_player`.
   - `Tween`: Fire-and-forget procedural interpolation (`create_tween()`) for HUD popups, gift banners, and podium camera reveals.
2. **Drive `AnimationTree` transitions from code:**
   ```gdscript
   @onready var anim_tree: AnimationTree = $AnimationTree
   @onready var playback: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")

   func set_motion_state(state_name: StringName) -> void:
       playback.travel(state_name)
   ```
3. **Procedural UI Tween (Gift Toast / Boost Banner):**
   ```gdscript
   func pop_banner(control: Control) -> void:
       control.scale = Vector2(0.7, 0.7)
       var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
       tween.tween_property(control, "scale", Vector2.ONE, 0.25)
   ```
