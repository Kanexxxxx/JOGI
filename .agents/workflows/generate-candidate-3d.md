---
description: Generate, rig, and import a 3D candidate or prop using Tripo CLI with mandatory dry-run validation
---

# Generate 3D Asset with Tripo CLI (`generate-candidate-3d`)

1. Verify Tripo CLI health and authentication (0 credits):
   ```powershell
   C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd doctor
   ```
2. Run mandatory zero-credit `--dry-run --json` validation:
   ```powershell
   C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd make "<prompt or image path>" --for game-mobile --then rig --dry-run --json
   ```
3. Confirm `"valid": true` and review the planned steps and cost with the user or 3D Art Director.
4. Execute generation into `assets/models/candidates/<slug>/`:
   ```powershell
   C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd make "<prompt or image path>" --for game-mobile --then rig -o ./assets/models/candidates/<slug> --json --yes
   ```
5. Inspect the generated `preview.png` and import the `.glb` into Godot (`gda project scan --json`).
