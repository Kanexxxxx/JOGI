---
name: godot-resources
description: >
  Design data-driven Godot 4.x games with custom Resource classes: define typed
  data with class_name + @export, save/load .tres/.res files, instance and duplicate
  resources, and load on demand with ResourceLoader. Use when modeling candidate profiles,
  live gift action tables, obstacle definitions, or race configs as .tres data in Godot.
---

# Godot Resources (4.x)

Model game data as reusable, Inspector-editable `Resource` objects (`.tres`) instead of hard-coded dictionaries.

## Core Workflow

1. **Subclass `Resource`** with `class_name` and `@export` properties (e.g., `CandidateProfileResource`, `GiftEffectResource`, `TrackThemeResource`).
2. **Save instances as `.tres`** (text-based, Git diff-friendly) under `res://data/candidates/` or `res://data/gifts/`.
3. **Duplicate shared resources before runtime mutation** (`var runtime_stats := base_profile.duplicate()`), since `Resource` references are shared across instances by default.

## Pattern: Candidate Profile Resource

```gdscript
extends Resource
class_name CandidateProfileResource

@export var candidate_id: StringName = &""
@export var display_name: String = ""
@export var vote_keyword: String = ""
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.BLACK
@export var mesh_scene: PackedScene
@export var victory_slogan: String = ""
```
