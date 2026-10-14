@echo off
echo Stopping Antigravity IDE auto-clicker...
powershell -NoProfile -Command "$procs = @(Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*autoclick.ps1*' }); if ($procs.Count -gt 0) { $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }; Write-Host ('Stopped ' + $procs.Count + ' auto-clicker process(es).') } else { Write-Host 'No running auto-clicker process found.' }"
ping 127.0.0.1 -n 3 >nul
