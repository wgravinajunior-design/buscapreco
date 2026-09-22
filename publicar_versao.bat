@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0publicar_versao.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERRO] Ocorreu uma falha no processo de publicacao.
    pause
    exit /b %ERRORLEVEL%
)
pause
