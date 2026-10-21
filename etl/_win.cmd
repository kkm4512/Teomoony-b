@echo off
chcp 65001 > nul
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Project\Teomoony\etl\_win.ps1" > "C:\Project\Teomoony\etl\_win.out.txt" 2>&1
