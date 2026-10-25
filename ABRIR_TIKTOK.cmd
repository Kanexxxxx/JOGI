@echo off
setlocal
cd /d "%~dp0"
echo Sessao TikTok @nostalgiia.br local. Painel: http://127.0.0.1:8765/admin
echo Este atalho nao inicia a transmissao. Ctrl+C encerra a sessao local.
"%~dp0services\live_bridge\.venv\Scripts\python.exe" "%~dp0tools\run_live_instances.py" --platform tiktok --mode production
if errorlevel 1 pause
