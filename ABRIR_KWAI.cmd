@echo off
setlocal
cd /d "%~dp0"
echo Sessao Kwai local. Painel: http://127.0.0.1:8766/admin
echo Receptor local e coletor Kwai serao iniciados. Confirme a conexao real no painel.
echo Se o Kwai solicitar login/verificacao na primeira vez, use ABRIR_NAVEGADOR_KWAI.cmd.
echo Ctrl+C encerra a sessao local.
"%~dp0services\live_bridge\.venv\Scripts\python.exe" "%~dp0tools\run_live_instances.py" --platform kwai --mode production
if errorlevel 1 pause
