@echo off
setlocal
cd /d "%~dp0"
node "%~dp0tools\open_admin_panels.cjs"
if errorlevel 1 pause
