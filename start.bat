@echo off
setlocal enabledelayedexpansion

rem ==============================================================
# Antigravity IDE Auto-Clicker Launcher
rem ==============================================================
rem Optional: specify exact executable path if not standard
set "AGPATH="

rem Pass 1: look for the Antigravity IDE executable
if not defined AGPATH (
  for %%P in (
    "%LOCALAPPDATA%\Programs\Antigravity IDE\Antigravity IDE.exe"
    "%ProgramFiles%\Antigravity IDE\Antigravity IDE.exe"
    "%ProgramFiles%\Google\Antigravity IDE\Antigravity IDE.exe"
    "%LOCALAPPDATA%\Programs\Antigravity-IDE\Antigravity IDE.exe"
  ) do if not defined AGPATH if exist %%P set "AGPATH=%%~P"
)

rem Pass 2: fall back to Antigravity.exe
if not defined AGPATH (
  for %%P in (
    "%LOCALAPPDATA%\Programs\Antigravity\Antigravity.exe"
    "%ProgramFiles%\Google\Antigravity\Antigravity.exe"
    "%ProgramFiles%\Antigravity\Antigravity.exe"
  ) do if not defined AGPATH if exist %%P set "AGPATH=%%~P"
)

if not defined AGPATH (
  echo [ERROR] Could not find Antigravity IDE executable.
  echo Edit start.bat and set AGPATH to the full path of "Antigravity IDE.exe".
  pause
  exit /b 1
)

echo [INFO] Found Antigravity IDE: "%AGPATH%"

rem Check if remote debugging port 9333 is already active
powershell -NoProfile -Command "$tcp = New-Object Net.Sockets.TcpClient; $t = $tcp.BeginConnect('127.0.0.1', 9333, $null, $null); if ($t.AsyncWaitHandle.WaitOne(300, $false)) { $tcp.EndConnect($t); exit 0 } else { exit 1 }" >nul 2>&1
if %ERRORLEVEL% equ 0 (
  echo [INFO] Remote debugging port 9333 is already open!
  goto :START_AUTOCLICK
)

rem Check if Antigravity IDE process is running without debugging port
tasklist /FI "IMAGENAME eq Antigravity IDE.exe" 2>NUL | find /I /N "Antigravity IDE.exe" >NUL
if %ERRORLEVEL% equ 0 (
  echo.
  echo ==============================================================
  echo [WARNING] Antigravity IDE is currently running without port 9333!
  echo Chromium/Electron only enables remote debugging on initial launch.
  echo ==============================================================
  echo.
  echo To enable auto-click, please choose:
  echo   [1] Restart Antigravity IDE now with remote debugging enabled
  echo   [2] Cancel (I will manually close Antigravity IDE first)
  echo.
  set /p "CHOICE=Enter choice [1 or 2]: "
  if "!CHOICE!"=="1" (
    echo Closing existing Antigravity IDE processes...
    taskkill /F /IM "Antigravity IDE.exe" >nul 2>&1
    ping 127.0.0.1 -n 3 >nul
  ) else (
    echo Please save your work, close Antigravity IDE, and re-run start.bat.
    pause
    exit /b 0
  )
)

echo [INFO] Launching Antigravity IDE with --remote-debugging-port=9333...
start "" "%AGPATH%" --remote-debugging-port=9333

echo [INFO] Waiting for remote debugging port 9333 to initialize...
set /a ATTEMPTS=0
:WAIT_PORT
set /a ATTEMPTS+=1
powershell -NoProfile -Command "$tcp = New-Object Net.Sockets.TcpClient; $t = $tcp.BeginConnect('127.0.0.1', 9333, $null, $null); if ($t.AsyncWaitHandle.WaitOne(400, $false)) { $tcp.EndConnect($t); exit 0 } else { exit 1 }" >nul 2>&1
if %ERRORLEVEL% equ 0 goto :START_AUTOCLICK
if %ATTEMPTS% geq 20 (
  echo [WARNING] Timed out waiting for port 9333. Starting auto-clicker anyway...
  goto :START_AUTOCLICK
)
ping 127.0.0.1 -n 2 >nul
goto :WAIT_PORT

:START_AUTOCLICK
rem Stop any previous autoclick.ps1 instance first
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*autoclick.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1

echo [INFO] Starting auto-clicker in background...
start "" powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0autoclick.ps1"

echo.
echo ==============================================================
echo [SUCCESS] Auto-clicker is now active!
echo - Watches and automatically clicks "Submit ↵", "Allow", "Proceed", etc.
echo - Real-time activity is logged to: autoclick.log
echo - Run stop.bat anytime to turn off auto-click.
echo ==============================================================
ping 127.0.0.1 -n 4 >nul
exit /b 0
