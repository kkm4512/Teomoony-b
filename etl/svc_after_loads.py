#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_after_loads - 무거운 적재(허브 · 파일럿)가 끝나면 남은 단지 전부 발행(sp-full-rest-par)을 건다 (2026-10-25, 사장님 "1번 ㄱㄱ")
  적재DB 를 오래 붙잡는 적재가 _queue 에 남아 있는 동안은 5분마다 보기만 한다. 관리비 이력(ci-kaptcost)은 API 속도로 도는 것이라 기다리지 않는다."""
import os, time, datetime
Q = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_queue")
무거움 = ("hl-hub", "pb-pilot")
print(f"기다림 — {' · '.join(무거움)} 이 끝나면 sp-full-rest-par", flush=True)
while True:
    남음 = sorted(j for j in os.listdir(Q) if j.endswith(".job") and j.startswith(무거움))
    if not 남음:
        open(os.path.join(Q, "sp-full-rest-par.job"), "w").close()
        print(f"[{datetime.datetime.now():%m-%d %H:%M}] 무거운 적재 끝 → sp-full-rest-par.job 놓음", flush=True); break
    time.sleep(300)
