@echo off
setlocal
cd /d "%~dp0"
echo Sessao Kwai local. Painel: http://127.0.0.1:8766/admin
echo Falta conectar um coletor de eventos do Kwai. Nao inicia transmissao.
echo Ctrl+C encerra a sessao local.
"%~dp0services\live_bridge\.venv\Scripts\python.exe" "%~dp0tools\run_live_instances.py" --platform kwai
if errorlevel 1 pause
