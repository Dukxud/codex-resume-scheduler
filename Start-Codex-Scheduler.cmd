@echo off
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required.
  pause
  exit /b 1
)
if exist "%~dp0Start-Codex-Scheduler.vbs" (
  wscript.exe "%~dp0Start-Codex-Scheduler.vbs"
  exit /b
)
start "" pwsh.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0CodexResumeScheduler.ps1"
exit /b
