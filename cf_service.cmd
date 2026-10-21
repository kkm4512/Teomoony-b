@echo off
rem Teomoony - install cloudflared as a Windows service (needs admin).
rem   Elevates itself via PowerShell Start-Process -Verb RunAs (UAC prompt).
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo   Asking for administrator rights...
  powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
chcp 65001 > nul
set CF="C:\Program Files (x86)\cloudflared\cloudflared.exe"
echo [install service]
%CF% service install
echo.
echo [start]
sc start cloudflared
echo.
echo [state]
sc query cloudflared
echo.
pause
