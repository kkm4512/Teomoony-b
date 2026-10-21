@echo off
chcp 65001 >nul
setlocal
REM ============================================================
REM  2026-10-18 아침 — README "내일 바로 할 것"
REM   1) 은평 주택가격 3개 법정동 (응암·신사·진관) — 한도가 풀렸을 때
REM   2) 102 축별 적재량 / 103 인허가 확인(5절이 아파트 0건을 가른다)
REM  결과는 전부 logs\ 로 떨어진다 — 이 창은 가려져서 안 보인다.
REM ============================================================
cd /d "%~dp0"

for /f "tokens=1,* delims==" %%a in ('findstr /b "DB_PASSWORD=" "%~dp0..\.env"') do set "DBPW=%%b"
if "%DBPW%"=="" (echo  .env 에서 DB_PASSWORD 를 못 읽었습니다 & pause & exit /b 1)

echo.
echo  [1/3] 은평 주택가격 재시도 (약 12분). 끝나면 카톡이 옵니다.
py run_plan.py go --retry --workers 4 --skip-build

echo.
echo  [2/3] 축별 적재량 (102)
docker cp "%~dp0..\deploy\sql\102_coverage.sql" teomoony-mssql:/tmp/102.sql >nul
docker exec teomoony-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "%DBPW%" ^
  -C -No -I -d Teomoony -W -i /tmp/102.sql > "%~dp0..\logs\out_102.txt" 2>&1
echo      -> logs\out_102.txt

echo.
echo  [3/3] 인허가 확인 (103)
docker cp "%~dp0..\deploy\sql\103_pms_check.sql" teomoony-mssql:/tmp/103.sql >nul
docker exec teomoony-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "%DBPW%" ^
  -C -No -I -d Teomoony -W -i /tmp/103.sql > "%~dp0..\logs\out_103.txt" 2>&1
echo      -> logs\out_103.txt

echo.
echo  끝났습니다. 아무 키나 누르면 창이 닫힙니다.
pause >nul
