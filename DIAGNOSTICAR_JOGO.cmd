@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0services\live_bridge\.venv\Scripts\python.exe" (
 echo Python do projeto ausente. Consulte INICIAR_JOGO.md.
 pause
 exit /b 1
)
"%~dp0services\live_bridge\.venv\Scripts\python.exe" "%~dp0tools\diagnose_startup.py"
pause
