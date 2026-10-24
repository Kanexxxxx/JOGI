@echo off
setlocal
cd /d "%~dp0"
echo Abrindo navegador local dedicado do Coletor Kwai (modo visivel para login/verificacao de cookies)...
echo Feche a janela ou pressione Ctrl+C apos autenticar sua conta Kwai se necessario.
node "%~dp0tools\kwai_live_collector.cjs" --account "mentalista.." --bridge "http://127.0.0.1:8766" --webhook "http://127.0.0.1:8786/webhook/kwai" --headed
if errorlevel 1 pause
