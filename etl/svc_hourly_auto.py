# -*- coding: utf-8 -*-
"""svc_hourly_auto - 매시 발행(svc_publish hourly). 전체 발행(sp-full*)이 큐에 있으면 밀린 것은 그쪽이 담으니 --backlog 0 (svc_cron 과 같은 규칙 · 2026-10-28)"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__)); Q = os.path.join(HERE, "_queue")
full = any(j.startswith("sp-full") and j.endswith(".job") for j in os.listdir(Q))
argv = [sys.executable, os.path.join(HERE, "svc_publish.py"), "--mode", "hourly"] + (["--backlog", "0", "--workers", "3"] if full else ["--workers", "4"])
print("전체 발행 도는 중 → 밀린 것 0" if full else "전체 발행 없음 → 밀린 것도 담음", flush=True)
sys.exit(subprocess.run(argv, cwd=HERE).returncode)
