---
name: godot-shaders
description: >
  Write Godot 4.x shaders in the Godot Shading Language: canvas_item shaders for 2D
  HUD effects and spatial shaders for 3D track/character materials, with vertex/fragment
  functions, uniforms (source_color, hint_range), TIME/UV animation (scrolling speed pads,
  finish line ribbons, boost aura/outline).
---

# Godot Shaders (4.x)

Write `canvas_item` (2D HUD) and `spatial` (3D Arena) `.gdshader` files in Godot 4.x.

## Core Patterns

### 1. 3D Speed Boost Pad (Scrolling Emission UV)

```glsl
shader_type spatial;

uniform vec4 pad_color : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform sampler2D arrow_mask : source_color;
uniform float scroll_speed : hint_range(0.1, 10.0) = 2.5;
uniform float emission_energy : hint_range(0.0, 8.0) = 3.0;

void fragment() {
	vec2 scrolled_uv = UV + vec2(0.0, TIME * scroll_speed);
	float mask = texture(arrow_mask, scrolled_uv).r;
	ALBEDO = pad_color.rgb * mask;
	EMISSION = pad_color.rgb * mask * emission_energy;
}
```
