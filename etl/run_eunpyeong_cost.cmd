@echo off
chcp 65001 >nul
REM 은평구 관리비 3개월 적재 - 더블클릭으로 실행
REM 끝나면 카카오톡으로 결과가 옵니다 (약 50분)
cd /d "%~dp0"
echo.
echo  은평구 관리비 적재를 시작합니다. 약 50분 걸리고,
echo  끝나면 카카오톡으로 결과가 옵니다. 이 창은 닫지 마세요.
echo.
py run_plan.py go --steps cost --sgg 11380 --from 202510 --to 202512
echo.
echo  끝났습니다. 아무 키나 누르면 창이 닫힙니다.
pause >nul
