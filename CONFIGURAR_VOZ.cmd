@echo off
setlocal
cd /d "%~dp0"
title Configurar voz da corrida
echo A chave sera digitada somente neste terminal, com entrada oculta.
echo Nenhum credito sera gasto nesta configuracao.
py tools\elevenlabs_audio.py configure
if errorlevel 1 goto done
echo.
echo Consultando permissao e saldo, sem gerar audio...
py tools\elevenlabs_audio.py status
:done
echo.
pause
endlocal
