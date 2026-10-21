@echo off
rem _run_exar.cmd - Claude 2026-10-18.
rem Loads expos-pubuse-area for the targets registered in 32_exar_targets.sql
rem   = Jangwi-dong (11290/13800) + Susaek-dong (11380/10100) only.
rem --grp area  : nothing else runs. --skip-build : this axis is not used to build complexes.
rem Expected ~1,650 calls, well under the daily cap.
setlocal
cd /d "%~dp0"
title Teomoony - expos area load
py run_plan.py plan
echo.
echo ==== starting load (grp=area) ====
py run_plan.py go --grp area --retry --workers 2 --skip-build
echo.
echo ==== finished. exit code %ERRORLEVEL% ====
pause
