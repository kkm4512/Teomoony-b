@echo off
rem Teomoony - cloudflared login (ASCII + CRLF only).
rem   Opens a browser window. Pick teomoony.com and authorize.
rem   The cert lands in %USERPROFILE%\.cloudflared\cert.pem
title cloudflared login
echo.
echo   A browser window will open.
echo   Choose teomoony.com and click Authorize.
echo.
"C:\Program Files (x86)\cloudflared\cloudflared.exe" tunnel login
echo.
pause
