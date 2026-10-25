# -*- coding: utf-8 -*-
"""hub_latest_after - 대장 뼈대 적재(hl-hub-reg)가 끝나면 공동주택가격 · 전유공용면적 최신 한 달을 넣는다 (2026-10-25). DB 를 두 적재가 동시에 두드리지 않게."""
import os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); Q = os.path.join(HERE, "_queue")
while os.path.exists(os.path.join(Q, "hl-hub-reg-par.job")):
    time.sleep(120)
import sys as _s
for code in (_s.argv[1:] or ["0308", "0306"]):
    print(f"$ hub_latest.py --code {code}", flush=True)
    r = subprocess.run([sys.executable, os.path.join(HERE, "hub_latest.py"), "--code", code], cwd=HERE)
    if r.returncode: sys.exit(r.returncode)
