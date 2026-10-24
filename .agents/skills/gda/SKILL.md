---
name: gda
description: Use the gda CLI to build, inspect, validate, and export Godot projects without opening the editor, or to inspect and control a running game through gda-daemon. Use when an agent builds or modifies a Godot game, or the user asks for gda or Godot automation.
---

# gda (Godot Agent CLI & Live Daemon)

`gda` is an agent-facing CLI for Godot (`aigengame/godot-agent`). Use headless operations to create and inspect scenes, nodes, scripts, resources, shaders, themes, and project settings; validate or run scripts and scenes; and export artifacts. Use live operations to inspect a running game, inject input, capture the viewport, and read diagnostics or performance data.
- **Headless operations**: Support Godot 4.4+.
- **Live operations (`gda-daemon`)**: Support Godot 4.6+.
- **Cross-platform**: Supports Windows, macOS, and Linux.

## Configure and Discover

- Set `GDA_GODOT` to the Godot executable, or pass `--godot PATH` after the command. On Windows, prefer Godot's `*_console.exe` binary.
- Pass `--project DIR`, set `GDA_PROJECT`, or run inside the project directory containing `project.godot`.
- Use `gda --version --json` to identify the installed CLI and `gda info --json` to verify the Godot engine executable.
- Discover commands and schemas dynamically:
  - `gda --help`
  - `gda <group> --help`
  - `gda <group> <command> --schema`
  - `gda schema`
- Always pass `--json` on automation commands (e.g., `gda scene validate res://main.tscn --project . --json`). Read the single JSON object on `stdout`; engine output goes to `stderr`.

### Critical Result Verification Table

An exit code of `0` does NOT always mean the check passed. Always inspect the JSON fields below:

| Operation | JSON Field to Verify |
| --- | --- |
| `scene validate`, `script validate` | `valid` (`false` means validation failed) |
| `scene preflight` | `status` and `started` |
| `script run`, `export smoke` | `exit_status` and `diagnostics` (use `--strict` to fail on leaks/errors) |
| `game set` | `verified` (`false` means read-back differed) |

## Headless Workflow

1. **Create Project**: `gda project create DIR --name "Corrida dos Candidatos" --json`
2. **Scan Class Names**: `gda project scan --json` (mandatory on fresh checkouts or after adding/renaming/deleting a `class_name` script).
3. **Author Scenes/Nodes/Scripts**:
   - Use `scene`, `node`, `script`, and `resource` subcommands.
   - Use `script attach` to bind a script to a node (do not use `node set --property script`).
   - Create any `preload("res://...")` assets *before* attaching a script that references them.
4. **Validate**:
   - `gda script validate res://path/to/script.gd --json`
   - `gda scene validate res://path/to/scene.tscn --json`
   - `gda scene preflight res://path/to/scene.tscn --json` (boots scene for a bounded interval to catch runtime `_ready()` failures).

## Live Workflow (`gda-daemon`)

- Start/manage session with `gda engine start --json`, `gda engine status --json`, `gda engine stop --json`.
- Inspect live tree & properties: `gda game tree --json`, `gda game get --json`, `gda game set --json`.
- Capture screenshots & diagnostics: `gda game screenshot --json`, `gda diag errors --json`, `gda diag perf --json`.
