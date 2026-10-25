# -*- coding: utf-8 -*-
"""gold_nation - 허브 대장으로 바꿔 끼운 뒤 **전국 시군구마다 단지 구성**(gold.usp_build_complexes) → 끝에 K-apt 연결 · 좌표 한 번 (2026-10-25)
  py gold_nation.py [--sido 11] [--workers 1]
  ★ 시군구 목록 = silver.bld_basis_outline 에 있는 시군구 전부(meta.load_target 아님 — 허브는 전국이다).
  ★ 끝낸 시군구는 _nation_gold_done.txt 에 적어 이어받는다. 교착이면 시군구마다 다시.
  ★ usp_refresh_complex_kapt · usp_refresh_complex_geo 는 전국 한 번씩(시군구마다 돌리면 같은 일을 250번 한다)."""
import argparse, os, sys, time
from svc_publish import env, ms_conn
HERE = os.path.dirname(os.path.abspath(__file__))
DONE = os.path.join(HERE, "_nation_gold_done.txt")
def log(*a): print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)
ap = argparse.ArgumentParser(); ap.add_argument("--sido", default=""); ap.add_argument("--retry", type=int, default=4)
ap.add_argument("--no-final", action="store_true"); a = ap.parse_args()
ms = ms_conn(env()); cur = ms.cursor()
cur.execute("SELECT DISTINCT sigungu_cd FROM silver.bld_basis_outline WHERE is_current = 1 AND sigungu_cd LIKE %s ORDER BY 1", (a.sido + "%",))
sggs = [r[0] for r in cur.fetchall() if r[0]]
done = set(open(DONE, encoding="utf-8").read().split()) if os.path.exists(DONE) else set()
todo = [s for s in sggs if s not in done]
log(f"시군구 {len(sggs)} · 끝낸 것 {len(sggs)-len(todo)} · 남은 것 {len(todo)}")
cur.execute("SELECT COUNT(*) FROM gold.complex"); n0 = cur.fetchone()[0]
t0 = time.time(); 실패 = []
for i, s in enumerate(todo, 1):
    for k in range(1, a.retry + 1):
        st = time.time()
        try:
            cur.execute("EXEC gold.usp_build_complexes @sigungu_cd=%s, @bjdong_cd=NULL", (s,))
            open(DONE, "a", encoding="utf-8").write(s + "\n")
            log(f"OK [{i}/{len(todo)}] {s} {time.time()-st:.0f}초"); break
        except Exception as ex:
            log(f"!! [{i}/{len(todo)}] {s} {k}/{a.retry}: {str(ex)[:200]}"); time.sleep(10 * k)
    else:
        실패.append(s)
cur.execute("SELECT COUNT(*) FROM gold.complex"); n1 = cur.fetchone()[0]
log(f"단지 구성 끝 {time.time()-t0:.0f}초 · 실패 {실패 or '없음'} · gold.complex {n0:,} → {n1:,}")
if not a.no_final and not 실패:
    for p in ("gold.usp_refresh_complex_kapt", "gold.usp_refresh_complex_geo"):
        st = time.time(); cur.execute(f"EXEC {p}")
        try: r = cur.fetchall()
        except Exception: r = None
        log(f"{p} {time.time()-st:.0f}초 {r[:1] if r else ''}")
