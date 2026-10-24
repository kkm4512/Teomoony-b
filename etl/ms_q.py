#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ms_q - 적재DB 에 .sql 파일(GO 로 나눈 배치)을 돌리고 모든 결과 줄을 찍는다 (2026-10-25, 점검용 · 읽기만)
  py ms_q.py ..\\deploy\\sql\\zz_probe_cols.sql"""
import sys, re, time
sys.path.insert(0, __import__('os').path.dirname(__file__))
from svc_publish import env, ms_conn
ms = ms_conn(env()); cur = ms.cursor()
for i, b in enumerate(re.split(r'^\s*GO\s*$', open(sys.argv[1], encoding='utf-8').read(), flags=re.M | re.I)):
    if not b.strip(): continue
    t = time.time(); cur.execute(b)
    while True:
        if cur.description:
            print(f"-- 배치 {i+1} · " + " | ".join(d[0] for d in cur.description))
            for r in cur.fetchall(): print("  " + " | ".join("" if v is None else str(v) for v in r))
        if not cur.nextset(): break
    print(f"   ({time.time()-t:.1f}초)", flush=True)
