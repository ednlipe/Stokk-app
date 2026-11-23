@echo off
rem STOKK - backup do banco. Dois cliques aqui (ou rode no terminal). Ver scripts\backup_banco.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup_banco.ps1" %*
echo.
pause
