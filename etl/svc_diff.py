#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_diff - 한 단지 · 한 종류: 옛 경로 vs 서비스DB 본문의 다른 곳을 경로째 찍는다 (2026-10-25, 점검용)
  py svc_diff.py 524566 detail [jeonse]"""
import gzip, json, sys
import psycopg
from svc_publish import env, fetch, TIMING
from svc_compare import canon
cid, kind = int(sys.argv[1]), sys.argv[2]; 앞 = sys.argv[3] if len(sys.argv) > 3 else ""
e = env()
pg = psycopg.connect(host="127.0.0.1", port=15432, dbname="teomoony", user="teomoony", password=e["SVC_DB_PASSWORD"])
st, gz, at = pg.execute("SELECT status, body_gz, updated_at FROM svc.complex_json WHERE complex_id=%s AND kind=%s", (cid, kind)).fetchone()
new = json.loads(TIMING.sub("", gzip.decompress(gz).decode(), count=1)); s2, old = fetch(cid, kind); old = json.loads(TIMING.sub("", old, count=1))
print(f"{cid}/{kind} · 담은 때 {at} · 상태 {st}/{s2}")
n = 0
def walk(a, b, p):
    global n
    if n > 40: return
    if isinstance(a, dict) and isinstance(b, dict):
        for k in list(a) + [k for k in b if k not in a]:
            walk(a.get(k, "<없음>"), b.get(k, "<없음>"), f"{p}.{k}")
    elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b) and len(a) < 400:
        for i, (x, y) in enumerate(zip(a, b)): walk(x, y, f"{p}[{i}]")
    elif a != b:
        n += 1
        f = lambda v: json.dumps(v, ensure_ascii=False)[:240]
        print(f"  {p}\n     서비스DB {f(a)}\n     지금옛길 {f(b)}")
walk(new.get(앞) if 앞 else new, old.get(앞) if 앞 else old, 앞 or "$")
