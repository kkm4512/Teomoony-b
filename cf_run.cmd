@echo off
rem Teomoony - run the Cloudflare tunnel in a window (test run).
rem   Close this window to stop the tunnel.
title Teomoony cloudflare tunnel
echo.
echo   https://teomoony.com  ^-^-^>  http://localhost:5173
echo   Close this window to stop.
echo.
"C:\Program Files (x86)\cloudflared\cloudflared.exe" tunnel run teomoony
pause
