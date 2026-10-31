@echo off
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required.
  pause
  exit /b 1
)
rem Compatibility launcher: its console exits immediately after starting the hidden GUI host.
start "" pwsh.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0CodexResumeScheduler.ps1"
exit /b
