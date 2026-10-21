@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
REM 275-276 admin dong boundary (SGIS) load + link to MOIS code (2026-10-21)
set LOG="%~dp0..\logs\adm_275.log"
echo  275 adm boundary ... started %date% %time% > %LOG%
py apply_sql.py 275_adm_boundary.sql >> %LOG% 2>&1
if errorlevel 1 goto end
py load_adm_boundary.py 2025 >> %LOG% 2>&1
if errorlevel 1 goto end
py apply_sql.py 276_adm_map.sql >> %LOG% 2>&1
:end
echo  exit %errorlevel%  %date% %time% >> %LOG%
echo  done. you can close this window.
