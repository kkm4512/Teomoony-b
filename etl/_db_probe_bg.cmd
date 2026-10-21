@echo off
rem Teomoony - run tools/db_probe.js in its own window (ASCII + CRLF).
rem   Why: the watcher queue is serial. A 36-hour load blocks every diagnostic
rem   query behind it. "start" lets the queue move on at once.
rem   ! Keep its own log - a window that closes on error tells you nothing.
title teomoony db probe
cd /d C:\Project\Teomoony-f
node tools\db_probe.js > "C:\Project\Teomoony\logs\_db_bg.log" 2>&1
echo exit=%errorlevel% >> "C:\Project\Teomoony\logs\_db_bg.log"
