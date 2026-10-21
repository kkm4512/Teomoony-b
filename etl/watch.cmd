@echo off
rem ============================================================
rem  watch.cmd - Teomoony job watcher (Claude, 2026-10-18)
rem
rem  Double-click once and LEAVE THIS WINDOW OPEN.
rem  It polls etl\_queue\ every 10s and runs ONLY the job names
rem  whitelisted in _job_runner.py. Close the window to stop
rem  accepting work - this window is the gate.
rem
rem  Allowed: go-retry, go, plan, rematch, sql.<name>, stop
rem  Logs   : ..\logs\job_<timestamp>_<name>.log
rem ============================================================
cd /d "%~dp0"
title Teomoony job watcher - keep open
py _job_runner.py
:tail
rem --- 아래는 원격 재시작용이다 (2026-10-18). 파일 맨 아래 설명 참고. ---
if not exist "_queue\_restart.flag" goto fin
del "_queue\_restart.flag" >nul 2>&1
echo.
echo ==== restarting watcher - reloading _job_runner.py ====
echo.
py _job_runner.py
goto tail

:fin
echo.
echo ==== watcher stopped. press any key to close. ====
pause >nul

rem ============================================================
rem  원격 재시작 (2026-10-18)
rem
rem  _job_runner.py 를 고쳐도 적용하려면 이 창을 껐다 켜야 했다.
rem  그런데 Claude 는 이 PC 의 창을 띄우지 못한다(탐색기가 앞으로 안 나온다).
rem  그래서 **파일 두 개로** 재시작한다 - 클릭도 타이핑도 필요 없다:
rem
rem    1) _queue\_restart.flag  를 만든다
rem    2) _queue\stop.job       을 만든다
rem
rem  runner 가 stop 을 보고 끝나면, 위 :tail 이 flag 를 보고 **지운 뒤**
rem  py 를 다시 띄운다. 새 프로세스라 바뀐 코드가 올라간다.
rem  flag 를 지우고 돌기 때문에 무한 루프가 되지 않는다.
rem
rem  ★ 문지기 성질은 그대로다. 이 창을 닫으면 아무것도 안 돈다.
rem    flag 는 "같은 창이 같은 스크립트를 다시 띄우는 것" 만 허용한다 -
rem    무엇을 실행할지는 여전히 _job_runner.py 의 JOBS 가 정한다.
rem  ★ flag 없이 끝나면 예전처럼 pause 에서 멈춘다.
rem ============================================================
