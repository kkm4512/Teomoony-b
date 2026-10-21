@echo off
rem Teomoony - run the Seoul RTMS load in its own window (ASCII + CRLF).
rem   Safe to run beside the building-register load:
rem     * different API service (RTMSDataSvc*) -> separate daily quota
rem     * different table (silver.rtms_trade)  -> no lock contention
rem   Deadlock 1205 happened when 20 threads hit ONE table. This is another one.
rem   Keep it modest (6 threads) - the public site shares this machine.
title teomoony RTMS seoul
cd /d C:\Project\Teomoony\etl
python rtms_seoul.py --workers 6 --from 200601 --to 202610
echo.
echo   done. close this window.
pause
