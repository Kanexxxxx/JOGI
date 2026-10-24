@echo off
setlocal
cd /d "%~dp0"
set "NODE_EXE=node"
where node >nul 2>nul
if errorlevel 1 (
  if exist "C:\Program Files\nodejs\node.exe" set "NODE_EXE=C:\Program Files\nodejs\node.exe"
)
echo Abrindo navegador local dedicado do Coletor Kwai (modo visivel para login/verificacao de cookies)...
echo O coletor em segundo plano cede o perfil automaticamente enquanto esta janela estiver aberta.
echo Feche a janela do navegador ou pressione Ctrl+C apos concluir o login para retomar a coleta automatica.
"%NODE_EXE%" "%~dp0tools\kwai_live_collector.cjs" --account "mentalista.." --bridge "http://127.0.0.1:8766" --webhook "http://127.0.0.1:8786/webhook/kwai" --headed
if errorlevel 1 pause
