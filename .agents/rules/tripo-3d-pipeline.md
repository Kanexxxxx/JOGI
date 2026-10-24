# Tripo 3D Asset Pipeline Rules

1. **Zero-Credit Dry Run First**: Always run `C:\Users\Kanex\AppData\Roaming\npm\tripo.cmd make ... --dry-run --json` and verify `"valid": true` before executing any credit-consuming 3D generation command.
2. **No Keys in Chat**: Never ask the user to paste `TRIPO_API_KEY` (`tsk_...`) in chat. Always use `tripo.cmd login --region ov` (or `cn`) or local terminal environment variables.
3. **Asset Budgets & Naming**:
   - Candidate 3D avatars: `--for game-mobile` (or `--for game-pc` decimated to `<= 15,000` faces), humanoid T-pose rig (`--then rig`), exported as `.glb` to `res://assets/models/candidates/<candidate_slug>/`.
   - Obstacles & Props: `--for game-mobile`, `<= 3,000` faces, exported as `.glb` to `res://assets/models/props/`.
   - Preserve generated `preview.png` and `task.json` metadata alongside source assets for reproducibility and auditability.
