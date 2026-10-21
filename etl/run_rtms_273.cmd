@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
REM 273 rtms covering index + v_lawd_map (2026-10-21)
echo  273 rtms covering index ... started %date% %time% > "%~dp0..\logs\rtms_273.log"
py apply_sql.py 273_rtms_lawd_cover.sql >> "%~dp0..\logs\rtms_273.log" 2>&1
echo  exit %errorlevel%  %date% %time% >> "%~dp0..\logs\rtms_273.log"
echo  done. you can close this window.
