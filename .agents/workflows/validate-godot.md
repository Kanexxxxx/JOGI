---
description: Validate all GDScript files, Godot scenes, and run headless preflight checks via gda CLI
---

# Validate Godot Project (`validate-godot`)

1. Scan project `class_name` registrations:
   ```powershell
   C:\Users\Kanex\.local\bin\gda.exe project scan --project C:\Users\Kanex\OneDrive\Desktop\JOGI --json
   ```
2. Validate modified `.gd` scripts:
   ```powershell
   C:\Users\Kanex\.local\bin\gda.exe script validate res://path/to/script.gd --project C:\Users\Kanex\OneDrive\Desktop\JOGI --json
   ```
3. Validate modified `.tscn` scenes:
   ```powershell
   C:\Users\Kanex\.local\bin\gda.exe scene validate res://path/to/scene.tscn --project C:\Users\Kanex\OneDrive\Desktop\JOGI --json
   ```
4. Run bounded scene preflight boot test:
   ```powershell
   C:\Users\Kanex\.local\bin\gda.exe scene preflight res://path/to/scene.tscn --project C:\Users\Kanex\OneDrive\Desktop\JOGI --json
   ```
5. Confirm `valid: true` and `started: true` with zero engine script errors before committing.
