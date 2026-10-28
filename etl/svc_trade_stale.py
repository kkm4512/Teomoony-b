#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_trade_stale - 서비스DB 에 담긴 단지 상세(detail)의 실거래 수가 적재DB 와 다른 단지를 찾는다 (2026-10-28 사장님 "실거래 있다고 뜨는데 없어")
  py svc_trade_stale.py            찾기만 — logs/svc_trade_stale_ids.txt 에 번호
  py svc_trade_stale.py --fix      찾은 단지 상세를 다시 발행(svc_publish --mode ids --kinds detail)
★ 왜: 10-27 전국 실거래 다시 잇기(match_complex_id 만 바뀜, loaded_at 그대로)는 매시 발행의 '바뀐 단지'(loaded_at 기준)에 안 잡혔다.
  지도 마커는 매시 통째로 다시 만들어 새 값(2.27억)인데, 상세는 잇기 전에 담긴 것(실거래 0)이 그대로 나갔다(김제 대방아파트 6402309).
★ 비교: 상세 '거래목록' 의 종류별(전월세 · 월세냐) '전체'(분양권 뺀 수)를 더한 것 = 적재DB COUNT(*) WHERE match_complex_id = 단지.
  (서버 _q_trades 와 같은 기준 — 취소 포함 · 분양권은 따로.) 값을 고치지 않는다. 다르면 지금 서버 응답으로 다시 담을 뿐."""
import gzip, json, os, subprocess, sys, time
from svc_publish import env, ms_conn, pg_conn
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "logs", "svc_trade_stale_ids.txt")
def log(*a): print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)
e = env(); ms = ms_conn(e); pg = pg_conn(e)
t0 = time.time()
cur = ms.cursor()
cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT match_complex_id, COUNT_BIG(*) FROM silver.rtms_trade WHERE match_complex_id IS NOT NULL GROUP BY match_complex_id")
real = {r[0]: int(r[1]) for r in cur.fetchall()}
log(f"적재DB 실거래 이어진 단지 {len(real):,} · {time.time()-t0:.0f}초")
stale = []; n = bad = 0; zero_but = 0; 예 = []
with pg.cursor(name="scan") as c:
    c.itersize = 2000
    c.execute("SELECT complex_id, body_gz FROM svc.complex_json WHERE kind = 'detail' AND status = 200")
    for cid, gz in c:
        n += 1
        try:
            d = json.loads(gzip.decompress(gz))
            seen = {}
            for x in d.get("거래목록") or []:
                if x.get("분양권") is None: seen[(x.get("전월세"), x.get("월세냐"))] = int(x.get("전체") or 0)
            have = sum(seen.values())
        except Exception:
            bad += 1; stale.append(cid); continue
        want = real.get(cid, 0)
        if have != want:
            stale.append(cid)
            if have == 0: zero_but += 1
            if len(예) < 8: 예.append(f"{cid}: 담긴 {have} · 지금 {want}")
        if n % 200000 == 0: log(f"  {n:,} 봄 · 다름 {len(stale):,}")
pg.commit()
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w").write("\n".join(map(str, stale)) + ("\n" if stale else ""))
log(f"상세 {n:,} 봄 · 실거래 수 다름 {len(stale):,}(그중 담긴 0 · 지금 있음 {zero_but:,}) · 못 읽음 {bad} · {time.time()-t0:.0f}초")
for s in 예: log("  예 " + s)
if "--fix" in sys.argv and stale:
    log("다시 발행 시작 — svc_publish --mode ids --kinds detail --ids-file")
    r = subprocess.run([sys.executable, os.path.join(HERE, "svc_publish.py"), "--mode", "ids", "--kinds", "detail", "--workers", "6", "--ids-file", OUT])
    sys.exit(r.returncode)
