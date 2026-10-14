@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose.ps1"
echo.
echo Saved to diagnose-output.txt in this folder.
pause
