@echo off
rem _run_exar_targets.cmd - Claude 2026-10-18. Registers exar for Jangwi + Susaek.
rem Read-mostly: one UPDATE + one MERGE on meta.load_target, then prints the plan.
setlocal
cd /d "%~dp0"
title Teomoony - exar targets
set OUT=..\logs\exar_targets.txt
for /f "tokens=1,* delims==" %%a in ('findstr /b "DB_PASSWORD=" "..\.env"') do set PW=%%b
docker cp "..\deploy\sql\32_exar_targets.sql" teomoony-mssql:/tmp/32.sql
docker exec teomoony-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "%PW%" -C -No -I -d Teomoony -W -i /tmp/32.sql > "%OUT%" 2>&1
type "%OUT%"
echo.
pause
