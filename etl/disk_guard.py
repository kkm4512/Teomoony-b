# -*- coding: utf-8 -*-
"""disk_guard - C 드라이브 남은 공간 지키기 (2026-10-26 새벽 C 가 가득 차 DB(Docker)가 멈추고, 다시 켤 때 데이터 디스크를 포맷하려 들었다)
  1분마다 본다. 남은 공간이 --stop GB 아래로 내려가면 무거운 쓰기(허브 표 만들기 · 필지 · 실거래)를 멈추고 기록한다.
  ★ Docker 디스크 파일(docker_data.vhdx)은 한 번 커지면 줄지 않는다 — 안에서 지운 자리는 다시 쓰지만, C 의 빈 공간은 돌아오지 않는다.
  py disk_guard.py [--stop 25] [--warn 50]"""
import argparse, shutil, subprocess, time
ap = argparse.ArgumentParser(); ap.add_argument("--stop", type=float, default=25); ap.add_argument("--warn", type=float, default=50); a = ap.parse_args()
HEAVY = "hub_swap|load_cadastral|nation_lawd|rtms_nation|load_rtms"
last = None
print(f"[{time.strftime('%m-%d %H:%M')}] 디스크 지킴이 시작 — {a.stop}GB 아래면 무거운 쓰기를 멈춘다", flush=True)
while True:
    free = shutil.disk_usage("C:\\").free / 2**30
    lv = "stop" if free < a.stop else "warn" if free < a.warn else "ok"
    if lv != last or lv != "ok" and int(time.time()) % 600 < 60:
        print(f"[{time.strftime('%m-%d %H:%M')}] C 남은 {free:.1f}GB · {lv}", flush=True)
    if lv == "stop":
        r = subprocess.run(["powershell", "-NoProfile", "-Command",
                            f"$p = Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object {{ $_.CommandLine -match '{HEAVY}' }}; "
                            "($p | ForEach-Object { $_.ProcessId.ToString() + ' ' + $_.CommandLine.Substring(0, [math]::Min(80, $_.CommandLine.Length)) }); $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        print(f"   !! 멈춤: {r.stdout.strip()[:600] or '없음'}", flush=True)
    last = lv
    time.sleep(60)
