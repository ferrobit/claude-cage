@echo off
rem Double-click launcher for Windows: runs claude-cage.ps1 next to this file.
rem Arguments are passed on, e.g. "claude-cage.cmd chromium".
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-cage.ps1" %*
if errorlevel 1 pause
