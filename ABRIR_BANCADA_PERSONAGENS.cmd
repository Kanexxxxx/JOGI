@echo off
setlocal
set "GODOT_EXE=C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT_EXE%" (
  echo Godot nao encontrado no caminho configurado.
  pause
  exit /b 1
)
"%GODOT_EXE%" --path "%~dp0game" res://scenes/characters/character_preview.tscn -- --asset-preview
endlocal
