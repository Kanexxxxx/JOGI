---
name: godot-audio
description: >
  Play and mix audio in Godot 4.x: AudioStreamPlayer (2D/3D variants), audio buses
  (Master, Music, SFX, Announcer, Crowd) with compressor/ducking effects, db/linear volume,
  and polyphonic live stream gift sound cues without clipping.
---

# Godot Audio (4.x)

Play SFX, crowd reactions, announcer voice lines, and music routed through dedicated audio buses with sidechain ducking and polyphony management.

## Core Workflow for Live Broadcast Games

1. **Dedicated Audio Bus Layout (`default_bus_layout.tres`):**
   - `Master`: Limiter (`AudioEffectLimiter` ceiling at `-1.0 dB`) to prevent stream clipping during gift storms.
   - `Announcer`: High priority voice/narrator alerts.
   - `SFX_Gifts`: Gift alerts and power-up sounds (`AudioStreamPolyphonic` or capped pool max 6 concurrent).
   - `SFX_Arena`: Footsteps, impacts, obstacles (`AudioStreamPlayer3D`).
   - `Music`: Background race music (ducked `-6 dB` when `Announcer` or major gift fanfare plays).
2. **Always convert linear volume (`0.0..1.0`) with `linear_to_db()`**.
3. **Prevent Gift Spam Audio Clipping**: Coalesce identical SFX triggered within `<80ms` and vary `pitch_scale` (`randf_range(0.95, 1.05)`).
