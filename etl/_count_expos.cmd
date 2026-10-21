@echo off
rem _count_expos.cmd - Claude 2026-10-18. Read-only sizing query.
setlocal
cd /d "%~dp0"
title Teomoony - expos sizing
set OUT=..\logs\expos_size.txt
for /f "tokens=1,* delims==" %%a in ('findstr /b "DB_PASSWORD=" "..\.env"') do set PW=%%b
docker exec teomoony-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "%PW%" -C -No -I -d Teomoony -W -Q "SET NOCOUNT ON; SELECT sigungu_cd, ho_cnt=COUNT(*), lawd_cnt=COUNT(DISTINCT bjdong_cd) FROM silver.bld_expos WHERE is_current=1 GROUP BY sigungu_cd ORDER BY sigungu_cd; SELECT tot_ho=COUNT(*) FROM silver.bld_expos WHERE is_current=1;" > "%OUT%" 2>&1
type "%OUT%"
echo.
pause
