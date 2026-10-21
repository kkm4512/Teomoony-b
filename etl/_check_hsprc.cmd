@echo off
rem _check_hsprc.cmd - one-off diagnostic written by Claude 2026-10-18.
rem Reports current hsprc row counts for sgg 11380 so --from-page can be computed.
rem Read-only. Safe to delete.
setlocal
set ROOT=%~dp0..
set OUT=%ROOT%\logs\hsprc_check.txt
for /f "tokens=1,* delims==" %%a in ('findstr /b "DB_PASSWORD=" "%ROOT%\.env"') do set PW=%%b
if "%PW%"=="" ( echo ERROR: DB_PASSWORD not found in .env> "%OUT%" & goto :done )
set SQLCMD=/opt/mssql-tools18/bin/sqlcmd
echo ==== hsprc rows by bjdong (sgg 11380) ====> "%OUT%"
docker exec teomoony-mssql %SQLCMD% -S localhost -U sa -P "%PW%" -C -No -I -d Teomoony -W -Q "SET NOCOUNT ON; SELECT bjdong_cd, rows_cur=COUNT(*), pk_cnt=COUNT(DISTINCT mgm_bldrgst_pk), page_done=COUNT(*)/100 FROM silver.bld_hsprc WHERE is_current=1 AND sigungu_cd='11380' GROUP BY bjdong_cd ORDER BY bjdong_cd;" >> "%OUT%" 2>&1
echo.>> "%OUT%"
echo ==== hsprc ingest_run history (sgg 11380) ====>> "%OUT%"
docker exec teomoony-mssql %SQLCMD% -S localhost -U sa -P "%PW%" -C -No -I -d Teomoony -W -Q "SET NOCOUNT ON; SELECT scope_key, run_mode, status, req_count, row_count, started_at, LEFT(ISNULL(err_msg,''),70) AS err FROM meta.ingest_run WHERE operation='getBrHsprcInfo' AND scope_key LIKE '11380/%%' ORDER BY scope_key, started_at;" >> "%OUT%" 2>&1
echo.>> "%OUT%"
echo ==== all axes row counts (sgg 11380) ====>> "%OUT%"
docker exec teomoony-mssql %SQLCMD% -S localhost -U sa -P "%PW%" -C -No -I -d Teomoony -W -Q "SET NOCOUNT ON; SELECT ax='hsprc', n=COUNT(*) FROM silver.bld_hsprc WHERE is_current=1 AND sigungu_cd='11380' UNION ALL SELECT 'expos', COUNT(*) FROM silver.bld_expos WHERE is_current=1 AND sigungu_cd='11380' UNION ALL SELECT 'flr', COUNT(*) FROM silver.bld_flr_outline WHERE is_current=1 AND sigungu_cd='11380';" >> "%OUT%" 2>&1
:done
endlocal
exit
