@echo off
setlocal
cd /d "%~dp0"
set "LIVE_PLATFORM="
set "LIVE_BRIDGE_WS_URL="
set "GODOT_JOGI=C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_JOGI%" (
  echo Godot nao encontrado. Consulte INICIAR_JOGO.md.
  pause
  exit /b 1
)
"%GODOT_JOGI%" --path "%~dp0game" res://scenes/main/stadium_race.tscn -- --asset-preview
if errorlevel 1 pause
