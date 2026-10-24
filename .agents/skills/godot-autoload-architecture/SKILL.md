---
name: godot-autoload-architecture
description: >
  Expert patterns for Godot 4.x AutoLoad (singleton) architecture including global
  event buses (LiveEventBus), match orchestration (GameManager), audio controllers,
  initialization order, and anti-patterns to avoid.
---

# Godot AutoLoad Architecture (4.x)

AutoLoads provide globally accessible services at the root of the SceneTree. Keep them lean, decoupled, and strictly scoped.

## Core Rules (NEVER Do)

- **NEVER access other AutoLoads inside `_init()`** — Use `_ready()` and respect autoload registration order in `project.godot`.
- **NEVER store scene-local node references permanently in an AutoLoad** — When scenes reload or change, stale references become freed instances.
- **NEVER create circular dependencies between AutoLoads** — Communicate via typed signals on `LiveEventBus`.
- **NEVER manually free an AutoLoad node.**

## Recommended AutoLoads for Corrida dos Candidatos

1. `LiveEventBus`: Pure typed signal router for incoming live stream events (`comment_vote`, `gift_boost`, `like_wave`, `share_trigger`) and match events (`match_state_changed`, `candidate_eliminated`, `race_finished`).
2. `GameConfig`: Loads and validates `.tres` / JSON configuration (candidates roster, gift-to-action mapping, timer durations).
3. `MatchOrchestrator`: High-level automated loop controller (Lobby -> Countdown -> Race -> Podium -> Auto-Restart for 24/7 unattended live streams).
4. `AudioDirector`: Manages Master/Music/Announcer/SFX buses, ducking, and polyphonic rate-limiting.
