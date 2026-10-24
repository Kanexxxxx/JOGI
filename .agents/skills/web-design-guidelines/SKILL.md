---
name: web-design-guidelines
description: >
  Review and build web UI code (such as the Corrida dos Candidatos Live Admin & Control Panel)
  for compliance with Vercel Web Interface Guidelines: accessibility, keyboard navigation,
  focus states, tabular numbers, responsive layouts, form usability, and performance.
metadata:
  author: vercel
  version: "1.0.0"
---

# Vercel Web Interface Guidelines

Origin: `https://github.com/vercel-labs/agent-skills/tree/main/skills/web-design-guidelines`.

## Core Compliance Checklist for Admin & Telemetry Web Panel

1. **Accessibility & Keyboard Interaction:**
   - Every interactive control (Emergency Pause, Force Next Race, Simulate Gift, Reset Queue, Mute Audio) MUST have an explicit accessible label (`aria-label` for icon-only buttons) and visible `:focus-visible` ring.
   - Interactive elements must use semantic `<button>` or `<a>` tags, never `<div onClick>`.
2. **Typography & Live Numbers:**
   - Use `font-variant-numeric: tabular-nums` on all live counters, FPS readouts, WebSocket latency indicators, gift queues, and timers so digits never jitter horizontally during rapid updates.
   - Prevent layout shifts when labels or usernames overflow (`text-overflow: ellipsis`, `overflow: hidden`, `white-space: nowrap`, `min-width: 0` inside flex/grid items).
3. **Forms, Controls & Destructive Actions:**
   - Destructive or live-interrupting actions (e.g., "Abort Current Race", "Disconnect Live Stream") require confirmation or clear visual separation from routine controls.
   - Disable submit/trigger buttons while an async operation is in-flight to prevent duplicate commands.
4. **Performance & Motion:**
   - Respect `prefers-reduced-motion: reduce`.
   - Animate only `transform` and `opacity`; never animate layout properties (`width`, `height`, `top`, `left`).
