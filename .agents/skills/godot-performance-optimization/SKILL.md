---
name: godot-performance-optimization
description: >
  Expert blueprint for Godot 4.x performance profiling and optimization (60 FPS live broadcast
  target, frame drops, memory leaks, draw calls) using object pooling, MultiMeshInstance3D,
  VisibleOnScreenNotifier3D, staggered updates, and PhysicsServer3D.
---

# Godot Performance Optimization (4.x — 60 FPS Live Broadcast Target)

Ensure **Corrida dos Candidatos** maintains a locked 60 FPS during high-volume TikTok/Kwai gift and comment bursts.

## Core Optimization Rules

1. **Object Pooling for Gift Effects & Projectiles:**
   - Never `instantiate()` and `queue_free()` hundreds of particle/prop nodes during a gift storm. Pre-allocate a pool of reusable nodes and toggle `visible`, `process_mode`, and physics collision layers.
2. **Crowd & Confetti Rendering (`MultiMeshInstance3D`):**
   - Render stadium spectators and repetitive track props using `MultiMeshInstance3D` to batch thousands of meshes in a single draw call.
3. **Polycount & Texture Budgets for 3D Candidates (Tripo CLI):**
   - Hero Candidate Runners: `<= 15,000` triangles (`--for game-mobile` or `--for game-pc` reduced), max `2048x2048` PBR textures.
   - Track Props / Obstacles: `<= 3,000` triangles (`--for game-mobile`).
4. **Visibility Culling (`VisibleOnScreenNotifier3D`):**
   - Disable expensive animations or secondary VFX when off-screen using `screen_exited` / `screen_entered` signals.
5. **Event Queue Rate-Limiting (Anti-Spike):**
   - Cap visual/physics spawn processing from live stream queues to a maximum budget per frame (e.g., max 5 spawned physics events per physics tick; batch excess events into combo multipliers).
