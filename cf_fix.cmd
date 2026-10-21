@echo off
rem Teomoony - elevate and run cf_fix.ps1 (UAC prompt).
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Project\Teomoony\cf_fix.ps1"
