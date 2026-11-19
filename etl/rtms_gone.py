#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rtms_gone - 원천(국토부 API)에서 **사라진** 실거래 줄 찾기 (2026-11-19 · DQM 'D' · 사장님 "ㄱㄱ")
  가격 정정 전 옛 줄 · 철회된 신고처럼 적재DB 에는 있는데 지금 원천 묶음(종목 × 시군구 × 계약월)에는 없는 줄.
  원천을 다시 받아 load_rtms 와 **같은 순번 키**(load_rtms.묶음키들)로 대조한다. 읽기만 — 결과는 ops 표에만 쓴다.
    ops.rtms_gone_run(한 번 돌 때 한 줄) · ops.rtms_gone_bundle(묶음마다 건수) · ops.rtms_gone_cand(사라진 줄 trade_sk)
  격리(적재 표에서 빼기)는 이 결과를 보고 SQL 로 따로 한다(420).
  py rtms_gone.py [--from 200601] [--to 이번달] [--sgg ...] [--kind ...] [--workers 12]
  ★ 받기가 OK 가 아닌 묶음은 대조하지 않는다(일부만 받은 묶음으로 '사라졌다' 고 하지 않는다)."""
import argparse, collections, os, sys, threading, time
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from load_rtms import KINDS, ENV, fetch, load_env, months, 묶음키들
from svc_publish import env as svc_env, ms_conn

ap = argparse.ArgumentParser()
ap.add_argument("--from", dest="ym_from", default="200601"); ap.add_argument("--to", dest="ym_to", default=time.strftime("%Y%m"))
ap.add_argument("--sgg", nargs="*"); ap.add_argument("--kind", action="append"); ap.add_argument("--workers", type=int, default=12)
a = ap.parse_args()
key = load_env(ENV).get("DATA_GO_KR_KEY", "").strip()
if not key: sys.exit("DATA_GO_KR_KEY 없음")
if not a.sgg:
    from _targets import 대상시군구
    a.sgg = 대상시군구()
kinds = a.kind or sorted(KINDS)
ms = months(a.ym_from, a.ym_to)
E = svc_env(); c0 = ms_conn(E).cursor()
c0.execute("""IF OBJECT_ID('ops.rtms_gone_run') IS NULL CREATE TABLE ops.rtms_gone_run (run_id INT IDENTITY PRIMARY KEY, 시작 DATETIME2 DEFAULT SYSDATETIME(), 끝 DATETIME2 NULL, 범위 NVARCHAR(400), 메모 NVARCHAR(400) NULL);
IF OBJECT_ID('ops.rtms_gone_bundle') IS NULL CREATE TABLE ops.rtms_gone_bundle (run_id INT, trade_kind VARCHAR(20), sgg_cd CHAR(5), ym CHAR(6), 상태 NVARCHAR(100), 원천줄 INT, 적재줄 INT, 원천에만 INT, 적재에만 INT);
IF OBJECT_ID('ops.rtms_gone_cand') IS NULL CREATE TABLE ops.rtms_gone_cand (run_id INT, trade_sk BIGINT, trade_kind VARCHAR(20), sgg_cd CHAR(5), ym CHAR(6));
IF COL_LENGTH('ops.rtms_gone_cand', 'nat_key') IS NULL ALTER TABLE ops.rtms_gone_cand ADD nat_key BINARY(32) NULL;""")
# ★ nat_key 도 적는다 — 격리(420)는 그 사이 적재가 키를 바꾼 줄(동 늦게 채움 등)을 건너뛴다.
c0.execute("INSERT ops.rtms_gone_run (범위) OUTPUT inserted.run_id VALUES (%s)", (f"{ms[0]}~{ms[-1]} · 시군구 {len(a.sgg)} · 종목 {len(kinds)}",))
RUN = c0.fetchone()[0]
print(f"[{time.strftime('%H:%M:%S')}] run {RUN} · {ms[0]}~{ms[-1]} · 시군구 {len(a.sgg)} · 종목 {len(kinds)} · 스레드 {a.workers}", flush=True)
lock = threading.Lock(); 합 = collections.Counter(); 셈 = {"n": 0}
일 = [(s, k) for s in a.sgg for k in kinds]


def one(u):
    sgg, kind = u; t = time.time()
    cur = ms_conn(E).cursor()
    cur.execute("SELECT trade_sk, nat_key, LEFT(deal_ymd, 6) FROM silver.rtms_trade WITH (NOLOCK) WHERE sgg_cd = %s AND trade_kind = %s", (sgg, kind))
    db = collections.defaultdict(dict)
    for sk, nk, ym in cur.fetchall():
        if ym: db[ym][bytes(nk)] = sk
    c = collections.Counter(); 묶음줄 = []; 후보 = []
    for ym in ms:
        rows, st = fetch(KINDS[kind][0], key, sgg, ym)
        d = db.get(ym, {})
        if st != "OK":
            c["받기실패"] += 1; 묶음줄.append((RUN, kind, sgg, ym, st[:100], len(rows), len(d), None, None)); continue
        src = {nat for _, _, nat, _ in 묶음키들(kind, sgg, rows)}
        gone = [sk for nk, sk in d.items() if nk not in src]
        only = sum(1 for nk in src if nk not in d)
        c["원천줄"] += len(rows); c["적재줄"] += len(d); c["적재에만"] += len(gone); c["원천에만"] += only
        if rows or d: 묶음줄.append((RUN, kind, sgg, ym, "OK", len(rows), len(d), only, len(gone)))
        후보 += [(RUN, sk, kind, sgg, ym, nk) for nk, sk in d.items() if nk not in src]
    for i in range(0, len(묶음줄), 150):
        cur.executemany("INSERT ops.rtms_gone_bundle VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)", 묶음줄[i:i+150])
    for i in range(0, len(후보), 300):
        cur.executemany("INSERT ops.rtms_gone_cand (run_id, trade_sk, trade_kind, sgg_cd, ym, nat_key) VALUES (%s,%s,%s,%s,%s,%s)", 후보[i:i+300])
    with lock:
        셈["n"] += 1; 합.update(c)
        print(f"  [{time.strftime('%H:%M:%S')}] [{셈['n']}/{len(일)}] {sgg} {kind:14s} 원천 {c['원천줄']:,} · 적재 {c['적재줄']:,} · 적재에만 {c['적재에만']:,} · 원천에만 {c['원천에만']:,}"
              + (f" · 받기실패 {c['받기실패']}" if c["받기실패"] else "") + f" · {time.time()-t:.0f}초", flush=True)


with ThreadPoolExecutor(max_workers=a.workers) as ex:
    for f in [ex.submit(one, u) for u in 일]:
        try: f.result()
        except Exception as e:
            print("  !! 조각 실패:", repr(e)[:300], flush=True); 합["조각실패"] += 1
c0.execute("UPDATE ops.rtms_gone_run SET 끝 = SYSDATETIME(), 메모 = %s WHERE run_id = %s", (str(dict(합)), RUN))
print(f"[{time.strftime('%H:%M:%S')}] 끝 run {RUN} · {dict(합)}", flush=True)
sys.exit(1 if 합["조각실패"] or 합["받기실패"] else 0)
