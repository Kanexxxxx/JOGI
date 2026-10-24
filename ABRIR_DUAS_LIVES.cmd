@echo off
setlocal
cd /d "%~dp0"
echo Duas sessoes locais independentes. Este atalho nao inicia transmissoes.
echo TikTok: http://127.0.0.1:8765/admin  (conta @nostalgiia.br)
echo Kwai:   http://127.0.0.1:8766/admin  (conta @mentalista.. + webhook :8786 + coletor local)
echo Ctrl+C encerra os processos criados por este atalho.
"%~dp0services\live_bridge\.venv\Scripts\python.exe" "%~dp0tools\run_live_instances.py" --both --mode production
if errorlevel 1 pause
