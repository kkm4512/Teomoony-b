@echo off
rem _run_exar_probe.cmd - written by Claude 2026-10-18.
rem  1) apply deploy/sql/31_expos_area.sql  (schema + op catalog)
rem  2) probe ONE jibun, ONE page, to read totalCount for expos-pubuse-area
rem Runs in its own window - independent of the job watcher.
rem Output: ..\logs\exar_probe.txt   (also shown here)
setlocal
cd /d "%~dp0"
title Teomoony - expos area probe
set OUT=..\logs\exar_probe.txt
for /f "tokens=1,* delims==" %%a in ('findstr /b "DB_PASSWORD=" "..\.env"') do set PW=%%b
if "%PW%"=="" ( echo ERROR: DB_PASSWORD not found & pause & exit /b 1 )

echo === 1/2  migration 31_expos_area.sql ===
echo === 1/2  migration 31_expos_area.sql ===> "%OUT%"
docker cp "..\deploy\sql\31_expos_area.sql" teomoony-mssql:/tmp/31.sql
docker exec teomoony-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "%PW%" -C -No -I -d Teomoony -W -i /tmp/31.sql >> "%OUT%" 2>&1
type "%OUT%"

echo.
echo === 2/2  probe : 11290/10300 bun 0636, 1 page ===
echo.>> "%OUT%"
echo === 2/2  probe : 11290/10300 bun 0636, 1 page ===>> "%OUT%"
py teomoony_ingest.py load --op getBrExposPubuseAreaInfo --sigungu 11290 --bjdong 10300 --bun 0636 --max-pages 1 >> "%OUT%" 2>&1
echo.
echo ---- tail ----
powershell -NoProfile -Command "Get-Content -Tail 25 -Encoding UTF8 '%OUT%'"
echo.
echo ==== done. output in logs\exar_probe.txt ====
pause
