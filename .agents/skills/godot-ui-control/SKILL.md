---
name: godot-ui-control
description: >
  Build Godot 4.x user interfaces and 9:16 vertical broadcast HUDs with Control nodes:
  anchors and offsets for responsive layout, Container nodes (VBox/HBox/Grid/Margin)
  for automatic arrangement, Theme resources for consistent styling, and safe-zone
  positioning for TikTok/Kwai live overlays.
---

# Godot UI / Control Nodes (4.x)

Lay out responsive HUDs and menus with `Control` anchors, `Container` nodes, and a unified `Theme` resource.

## Core Workflow for 9:16 Vertical Live Broadcast (1080x1920)

1. **Respect TikTok/Kwai Mobile Safe Zones:**
   - Top 15% (`0–280px`): Host header & viewer counter (keep clear or use compact top leaderboard).
   - Bottom 35% (`1250–1920px`): Live chat comments and gift tray (do NOT place critical race action or unreadable text here).
   - Right edge (`920–1080px`, `y: 700–1400px`): Like/Share/Gift buttons.
   - **Primary HUD Action Zone**: `y: 260–1220px` (central 3D viewport + side leaderboard + center-top gift alert banners).
2. **Use Containers (`MarginContainer`, `VBoxContainer`, `HBoxContainer`, `PanelContainer`)** instead of hardcoded pixel coordinates.
3. **Note on `gda` CLI**: When `gda scene create` creates a `Control` root, set `anchor_right = 1.0` and `anchor_bottom = 1.0` via `gda node set` so it fills the viewport.
