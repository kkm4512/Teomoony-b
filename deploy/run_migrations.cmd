@echo off
REM ============================================================
REM  Teomoony - schema migration runner (batch)
REM
REM  ASCII ONLY on purpose. cmd.exe reads .cmd files using the OEM
REM  codepage (CP949 on Korean Windows). Non-ASCII comments saved as
REM  UTF-8 get mangled and break line parsing, so keep this file ASCII.
REM
REM  Usage (from PowerShell you must prefix with .\ )
REM    cd C:\Project\Teomoony\deploy
REM    .\run_migrations.cmd
REM    .\run_migrations.cmd sample
REM ============================================================
setlocal EnableDelayedExpansion

set CONTAINER=teomoony-mssql
rem ★ 평문을 여기 안 둔다. .env 가 유일한 출처다.
set "SAPW="
for /f "tokens=1,* delims==" %%a in ('findstr /b "DB_PASSWORD=" "%~dp0..\.env"') do set "SAPW=%%b"
if not defined SAPW (
  echo .env 에 DB_PASSWORD 가 없다.
  exit /b 1
)
set SQLCMD=/opt/mssql-tools18/bin/sqlcmd
rem ★ 목록을 직접 적지 않는다. ps1 과 같은 이유다(주석 참조).
set "SCRIPTS="
for /f "delims=" %%F in ('dir /b /on "%~dp0sql\*.sql"') do (
  echo %%F | findstr /r "^[0-8][0-9]_" >nul && set "SCRIPTS=!SCRIPTS! %%F"
)
if /i "%~1"=="sample" set "SCRIPTS=!SCRIPTS! 90_sample_probe.sql"

echo.
echo [1/3] checking container
docker inspect -f "{{.State.Running}}" %CONTAINER% 2>nul | findstr /i "true" >nul
if errorlevel 1 (
  echo   container is not running. run this first:  docker compose up -d
  exit /b 1
)
echo   running

echo [2/3] waiting for SQL Server
REM  The sa password contains '!' so delayed expansion must stay OFF,
REM  otherwise the '!' is eaten and auth fails. Hence a goto loop.
set TRIES=0
:waitloop
docker exec %CONTAINER% %SQLCMD% -S localhost -U sa -P "%SAPW%" -C -No -Q "SELECT 1" >nul 2>&1
if not errorlevel 1 goto ready
set /a TRIES+=1
if %TRIES% GEQ 60 (
  echo   cannot connect after 120s. check logs:
  echo     docker logs %CONTAINER%
  exit /b 1
)
timeout /t 2 /nobreak >nul
goto waitloop
:ready
echo   ready

echo [3/3] applying migrations
for %%F in (%SCRIPTS%) do call :apply "%%F"
if errorlevel 1 exit /b 1

echo.
echo done.
echo connect: localhost,11433  user=sa  db=Teomoony
echo.
endlocal
exit /b 0


:apply
set FNAME=%~1
if not exist "%~dp0sql\%FNAME%" (
  echo   missing script: %~dp0sql\%FNAME%
  exit /b 1
)
echo   -^> %FNAME%
docker cp "%~dp0sql\%FNAME%" %CONTAINER%:/tmp/%FNAME% >nul
REM  -I sets QUOTED_IDENTIFIER ON. sqlcmd defaults it OFF, which makes
REM  CREATE TABLE fail on PERSISTED computed columns and filtered indexes.
docker exec %CONTAINER% %SQLCMD% -S localhost -U sa -P "%SAPW%" -C -No -I -i /tmp/%FNAME%
if errorlevel 1 (
  echo   FAILED: %FNAME%
  exit /b 1
)
exit /b 0
