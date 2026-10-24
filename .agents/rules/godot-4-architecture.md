# Godot 4.x & GDScript 2.0 Architecture Rules (Corrida dos Candidatos)

1. **Strict Static Typing**: Every `.gd` script MUST use explicit types (`var speed: float = 8.0`, `func apply_boost(amount: float) -> void:`). Untyped variables and untyped function signatures are forbidden.
2. **Signal Up, Call Down**: Child scenes never hold direct references to parent or sibling scenes. Use typed signals for upward notifications and `LiveEventBus` autoload for cross-subsystem live events.
3. **Physics vs Render Separation**: All `CharacterBody3D`, `RigidBody3D`, and raycast/shapecast logic MUST run inside `_physics_process(delta)`. Visual UI tweens and camera smoothing belong in `_process(delta)` or `Tween`.
4. **Headless Validation First**: After creating or modifying any `.gd` script or `.tscn` scene, validate it with `C:\Users\Kanex\.local\bin\gda.exe script validate` and `gda.exe scene validate` (plus `gda.exe project scan --json` whenever `class_name` changes).
5. **60 FPS Live Broadcast Budget**:
   - Target resolution: `1080x1920` (9:16 vertical portrait) at locked 60 FPS.
   - Use object pooling for gift/obstacle spawns; never `instantiate()` unbounded nodes during gift storms.
   - Verify `Performance.OBJECT_ORPHAN_NODE_COUNT == 0` on match reset.
