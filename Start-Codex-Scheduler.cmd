@echo off
if not exist "%~dp0Start-Codex-Scheduler.vbs" (
  echo Scheduler launcher missing. Extract the complete release ZIP.
  pause
  exit /b 1
)
wscript.exe "%~dp0Start-Codex-Scheduler.vbs"
exit /b
