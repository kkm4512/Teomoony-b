@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
REM 271 spatial index - building_footprint, cadastral_parcel (2026-10-21)
echo  271 spatial index ... started %date% %time% > "%~dp0..\logs\spidx_271.log"
py apply_sql.py 271_spidx_geom.sql >> "%~dp0..\logs\spidx_271.log" 2>&1
echo  exit %errorlevel%  %date% %time% >> "%~dp0..\logs\spidx_271.log"
echo  done. you can close this window.
