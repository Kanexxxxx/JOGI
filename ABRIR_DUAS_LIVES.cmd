@echo off
setlocal
cd /d "%~dp0"
echo Duas sessoes locais independentes. Este atalho nao inicia transmissoes.
echo TikTok: http://127.0.0.1:8765/admin
echo Kwai:   http://127.0.0.1:8766/admin - coletor de eventos pendente
echo Ctrl+C encerra os processos criados por este atalho.
"%~dp0services\live_bridge\.venv\Scripts\python.exe" "%~dp0tools\run_live_instances.py" --both
if errorlevel 1 pause
