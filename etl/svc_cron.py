#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_cron - 서비스DB 발행을 1시간마다 건다 (2026-10-24, 사장님 "적재DB → 서비스DB 는 1시간에 한 번")
  뒷줄(-bg)에서 계속 돈다. 매시 05분에 _queue/sp-hourly-par.job 을 놓는다 — 이미 놓여 있거나 돌고 있으면 건너뛴다.
  전체 발행(sp-full*)이 돌고 있으면 밀린 것은 그쪽이 담으니 '바뀐 것만'(sp-hourly0-par)을 건다.
  ★ 감시기(_job_runner) 를 다시 띄우지 않고 돌리려고 따로 둔 것이다(감시기 재시작은 모든 줄이 빌 때만 된다)."""
import os, time, datetime
HERE = os.path.dirname(os.path.abspath(__file__))
Q = os.path.join(HERE, "_queue")
print("svc_cron 시작 — 매시 05분 발행", flush=True)
while True:
    n = datetime.datetime.now()
    nxt = (n.replace(minute=5, second=0, microsecond=0) + (datetime.timedelta(hours=1) if n.minute >= 5 else datetime.timedelta()))
    time.sleep(max(5, (nxt - n).total_seconds()))
    jobs = set(os.listdir(Q))
    if any(j.startswith("sp-hourly") and j.endswith(".job") for j in jobs):
        print(f"[{datetime.datetime.now():%m-%d %H:%M}] 지난 발행이 아직 — 건너뜀", flush=True); continue
    name = "sp-hourly0-par.job" if any(j.startswith("sp-full") and j.endswith(".job") for j in jobs) else "sp-hourly-par.job"
    open(os.path.join(Q, name), "w").close()
    print(f"[{datetime.datetime.now():%m-%d %H:%M}] {name} 놓음", flush=True)
