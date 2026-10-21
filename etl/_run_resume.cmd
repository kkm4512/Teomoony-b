@echo off
rem _run_resume.cmd - written by Claude 2026-10-18.
rem Runs: py run_plan.py go --retry --workers 4   (with the new auto --from-page resume)
rem Output goes to ..\logs\ as usual. Safe to delete after use.
cd /d "%~dp0"
title Teomoony - hsprc resume
py run_plan.py go --retry --workers 4
echo.
echo ==== finished. exit code %ERRORLEVEL% ====
pause
