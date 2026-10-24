---
name: tripo-cli
description: >
  Official Tripo 3D AI CLI (tripo-cli v0.7.0) skill for generating, texturing, rigging,
  retargeting animations, and converting production-ready 3D assets (.glb, .fbx) from text
  prompts or images using `tripo make`. Includes zero-credit `--dry-run --json` validation.
---

# Tripo CLI Skill (`tripo-cli` v0.7.0)

You can generate production-ready 3D assets for **Corrida dos Candidatos** with the `tripo` CLI (`C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd`).
One command turns a text prompt or an image into local files: a 3D model (`.glb`/`.fbx`), a `preview.png` render, and a `task.json` record.

## Mandatory Safety & Credit Rules

1. **NEVER ask the user to paste an API key (`tsk_...`) or password in chat.**
   - Always use `tripo.cmd login --region ov` (or `cn` if specified) for browser device login, or instruct the user to set `$env:TRIPO_API_KEY` locally in their terminal.
2. **Always validate before spending credits using `--dry-run --json`:**
   - Adding `--dry-run --json` prints the complete execution plan (`model`, `steps[].payload`, `warnings`, `errors`, `valid`) with **zero network calls and zero credits spent**.
3. **PowerShell Invocation on Windows:**
   - Invoke `C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd` (or `tripo.cmd`) to avoid PowerShell `.ps1` ExecutionPolicy blocks.

## Install & Auth

```powershell
npm.cmd install -g tripo-cli
# Browser device login (international site: ov)
C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd login --region ov

# Zero-credit health, auth, network, and balance check
C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd doctor
```

## Behavior Rules

1. **`tripo make` is synchronous and blocking.** It prints a plan card on `stderr`, submits, polls, downloads artifacts, and prints a single final JSON object on `stdout` when `--json` is passed.
2. **Validate before spending (`--dry-run --json`).** Verify `valid: true` in the dry-run JSON before running live generation.
3. **Model selection:** The CLI auto-selects `tripo-v3.1` (high fidelity) or `tripo-p1` (low-poly, face budget `<= 20000`).
4. **Exit codes:**
   - `0`: Success
   - `2`: Usage / parameter validation error
   - `3`: Auth error (run `tripo.cmd login --region ov` or `tripo.cmd doctor`)
   - `4`: Insufficient credits (`tripo.cmd topup` / `tripo.cmd balance`)
   - `5`: Content policy
   - `6`: Task failed (credits auto-refunded; if timeout, use `tripo.cmd task watch <id>`)
   - `7`: Network error (check `tripo.cmd balance` before re-running)
   - `8`: Not found
   - `9`: Rate limit (retry with backoff)

## Core Recipes for Corrida dos Candidatos

```powershell
# 1. Zero-credit dry-run validation for a 3D candidate runner + auto-rig
C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd make "stylized 3D caricature candidate runner in suit, T-pose" --for game-mobile --then rig --dry-run --json

# 2. Generate low-poly mobile/live-stream 3D runner + auto-rig
C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd make "stylized 3D caricature candidate runner in suit, T-pose" --for game-mobile --then rig -o ./assets/models/candidates --json --yes

# 3. Generate from approved concept image + rig + animation retarget
C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd make ./concepts/candidato_01.png --for game-pc --then rig,retarget -o ./assets/models/candidates --json --yes
```

- `--for` scenario presets: `game-mobile`, `game-pc`, `film`, `print`, `ar-web`, `anim`, `toy`
- `--then` chain steps: `refine`, `texture`, `convert`, `import`, `rig-check`, `rig`, `retarget`, `segment`, `complete`, `decimate`, `uv`, `smartsegment`
- Built-in MCP server mode: `tripo.cmd mcp` (exposes `tripo_make`, `tripo_task_get`, `tripo_task_wait`, `tripo_balance`, `tripo_history`)
