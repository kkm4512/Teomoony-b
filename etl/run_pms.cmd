@echo off
chcp 65001 >nul
setlocal
REM ============================================================
REM  건축인허가(ArchPms) - 종로 11110 / 은평 11380 / 장위동 11290-13800
REM  더블클릭으로 실행. 끝나면 카카오톡으로 결과가 옵니다.
REM ============================================================
cd /d "%~dp0"

for /f "tokens=1,* delims==" %%a in ('findstr /b "DB_PASSWORD=" "%~dp0..\.env"') do set "DBPW=%%b"
if "%DBPW%"=="" (echo  .env 에서 DB_PASSWORD 를 못 읽었습니다 & pause & exit /b 1)

echo.
echo  [1/4] op 카탈로그에 인허가 2종을 등록합니다
docker cp "%~dp0..\deploy\sql\30_load_target.sql" teomoony-mssql:/tmp/30.sql >nul
docker exec teomoony-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "%DBPW%" ^
  -C -No -I -d Teomoony -i /tmp/30.sql
if errorlevel 1 (echo  마이그레이션 실패 & pause & exit /b 1)

echo.
echo  [2/4] 목표에 pms 를 더합니다 (비고/우선순위는 그대로)
py run_plan.py add --sgg 11110 --ops base,ext,pms
py run_plan.py add --sgg 11380 --ops base,ext,pms
py run_plan.py add --sgg 11290 --bjdong 13800 --ops base,ext,pms

echo.
echo  [3/4] 남은 일
py run_plan.py plan

echo.
echo  [4/5] 인허가만 돌립니다 (--grp pms). 끝나면 카톡이 옵니다.
REM 인허가는 단지 구성(gold.complex)에 안 쓰인다 - build 는 건너뛴다
py run_plan.py go --grp pms --workers 4 --skip-build --retry

echo.
echo  [5/5] 2차 패스 - 동별개요(pmsdong)는 기본개요(pms)를 선행으로 기다립니다.
REM go 는 계획을 **시작할 때 한 번만** 센다. 1차에서 pms 가 들어가며
REM 선행이 풀린 pmsdong 은 1차 계획에 없었다. 그래서 한 번 더 돈다.
py run_plan.py go --grp pms --workers 4 --skip-build --retry

echo.
echo  끝났습니다. 아무 키나 누르면 창이 닫힙니다.
pause >nul
