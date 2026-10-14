@echo off
title Antigravity IDE Auto-Click Monitor
echo ==============================================================
echo Antigravity IDE Auto-Click Live Monitor
echo ==============================================================
echo Starting auto-clicker in foreground (Ctrl+C to stop)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0autoclick.ps1"
pause
