@echo off
rem Docker data disk compaction - asks for administrator (UAC) once, then runs compact_docker_disk.ps1
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File C:\Project\Teomoony\etl\compact_docker_disk.ps1'"
