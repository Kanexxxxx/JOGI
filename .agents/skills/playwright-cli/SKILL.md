---
name: playwright-cli
description: >
  Automate browser interactions, inspect DOM snapshots, capture screenshots, and run
  reproducible E2E tests for the Corrida dos Candidatos web administration panel using
  playwright-cli or npx playwright.
---

# Browser Automation with `playwright-cli`

Origin: `https://github.com/microsoft/playwright-cli/blob/main/skills/playwright-cli/SKILL.md`.

## Role in Antigravity Environment

- Antigravity provides native `read_url_content` and `search_web` tools for static documentation and web research.
- Use `playwright-cli` (or `npx.cmd playwright`) specifically when testing the local **Admin & Live Telemetry Panel**, capturing reproducible multi-viewport screenshots (`1440x900`, `390x844`), inspecting browser console errors, or running automated E2E UI verification.

## Core Commands

```powershell
# Open URL and inspect accessibility snapshot
playwright-cli open http://localhost:3000
playwright-cli snapshot

# Interact with elements by snapshot ref
playwright-cli click e5
playwright-cli fill e8 "Candidato A" --submit

# Capture high-resolution screenshot & check console warnings/errors
playwright-cli resize 1440 900
playwright-cli screenshot --filename=admin-panel-desktop.png
playwright-cli console warning
playwright-cli close
```
