---
name: design-taste-frontend
description: >
  Art direction and anti-slop frontend design skill (from Leonxlnx/taste-skill v2).
  Enforces intentional visual hierarchy, bold typography, cohesive palettes, and zero
  generic AI card/pill clutter when designing web interfaces, broadcast overlays, or
  companion promotional pages for Corrida dos Candidatos.
---

# Design Taste Frontend (tasteskill v2 — Adapted for Project)

Origin: `https://github.com/Leonxlnx/taste-skill` (`skills/taste-skill/SKILL.md`).

## Purpose in Corrida dos Candidatos

Guides art direction, typographic contrast, color blocking, and layout discipline for:
1. Broadcast overlays and promotional landing pages.
2. Visual hierarchy of the companion Admin & Telemetry Panel (paired with `DESIGN.md` and `web-design-guidelines`).

## Core Rules

1. **Subject-Driven Concept, Never Generic SaaS Clichés:**
   - Avoid generic AI tells: centered gradient headlines with tiny pill badges above them, 3-column icon card rows, nested cards-inside-cards, and meaningless decorative sparklines.
2. **Typographic Authority & Readability at a Glance:**
   - Headlines fit in 2 lines or fewer (~32 characters max).
   - High-contrast numeric tabular figures (`font-variant-numeric: tabular-nums`) for live vote counters, timers, and rankings.
3. **Intentional Color Proportions:**
   - Follow the project's `DESIGN.md` broadcast palette: deep arena dark ground, high-visibility candidate signature colors, and unmistakable semantic status signals.
4. **Look-and-Fix Visual Verification:**
   - Always inspect rendered interfaces at real viewport dimensions (e.g., `1080x1920` for 9:16 broadcast HUD, `1440x900` and `390x844` for Admin Web Panel) using Playwright or `gda game screenshot` before declaring UI work complete.
