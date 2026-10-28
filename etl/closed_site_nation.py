# -*- coding: utf-8 -*-
"""closed_site_nation - 폐쇄대장 전국판(380/381 · closed_swap) 뒤 철거 단지(gold.closed_site)를 시군구마다 다시 묶는다 (2026-10-29)
  ★ 묶는 규칙은 302 gold.usp_build_closed_site 그대로(같은 대지 + 같은 말소일 · 지금 단지는 같은 필지에 하나일 때만). 끝낸 시군구는 _closed_site_done.txt"""
import os, sys, time
from svc_publish import env, ms_conn
HERE = os.path.dirname(os.path.abspath(__file__)); DONE = os.path.join(HERE, "_closed_site_done.txt")
def log(*a): print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)
cur = ms_conn(env()).cursor()
cur.execute("SELECT DISTINCT sigungu_cd FROM silver.bld_closed_title WHERE sigungu_cd IS NOT NULL UNION SELECT DISTINCT sigungu_cd FROM silver.bld_closed_recap WHERE sigungu_cd IS NOT NULL")
sggs = sorted(r[0] for r in cur.fetchall())
done = set(open(DONE).read().split()) if os.path.exists(DONE) else set()
cur.execute("SELECT COUNT(*) FROM gold.closed_site"); n0 = cur.fetchone()[0]
todo = [s for s in sggs if s not in done]; log(f"시군구 {len(sggs)} · 남은 {len(todo)} · 지금 closed_site {n0:,}")
bad = []
for i, s in enumerate(todo, 1):
    for k in range(3):
        try:
            st = time.time(); cur.execute("EXEC gold.usp_build_closed_site @sgg = %s", (s,)); r = cur.fetchall()
            open(DONE, "a").write(s + "\n"); log(f"OK [{i}/{len(todo)}] {s} {r[-1] if r else ''} · {time.time()-st:.0f}초"); break
        except Exception as e:
            log(f"!! {s} {k+1}/3 {str(e)[:200]}"); time.sleep(10)
            try: cur = ms_conn(env()).cursor()          # 10-29: 연결이 끊기면(KILL 등) 다시 붙는다 — 안 그러면 남은 시군구가 줄줄이 실패
            except Exception as e2: log(f"   다시 붙기 실패 {str(e2)[:120]}")
    else: bad.append(s)
cur.execute("SELECT COUNT(*) FROM gold.closed_site"); log(f"끝 closed_site {n0:,} → {cur.fetchone()[0]:,} · 실패 {bad or '없음'}")
sys.exit(1 if bad else 0)
