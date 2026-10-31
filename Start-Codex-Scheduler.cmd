@echo off
setlocal
if not exist "%~dp0CodexScheduler.exe" (
  echo CodexScheduler.exe missing. Download the versioned release ZIP, not the source ZIP.
  pause
  exit /b 1
)
start "" "%~dp0CodexScheduler.exe"
exit /b
