# -*- coding: utf-8 -*-
"""norm_e2e - 지금 사이트(5173) vs 개발판(5174 · 주변 상가 · 학교 = 시험DB) 단지 상세 실제 응답 비교 (2026-10-27)
  같은 단지를 번갈아 연다(?_t=1 — 서비스DB · 서버 캐시를 건너뛰고 상세를 새로 만든다). 시간 · 결과(칸별) 대조.
  py norm_e2e.py [개수=200]"""
import sys, json, time, random, statistics, urllib.request
from svc_publish import env, ms_conn
N = int(sys.argv[1]) if len(sys.argv) > 1 else 200
# py norm_e2e.py 200 5174 → 같은 서버에서 매칭 테이블(?_t=1) vs 적재DB(?_t=1&_nm=0) — 같은 코드끼리 대조
SELF = int(sys.argv[2]) if len(sys.argv) > 2 else 0
ms = ms_conn(env()).cursor()
ms.execute(f"""SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
  SELECT TOP {N//2} complex_id FROM gold.complex WHERE merged_into IS NULL AND is_active = 1 AND centroid_lat IS NOT NULL AND ISNULL(hhld_cnt_sum,0) < 20 AND sigungu_cd LIKE '11%' ORDER BY NEWID();
  SELECT TOP {N//2} complex_id FROM gold.complex WHERE merged_into IS NULL AND is_active = 1 AND centroid_lat IS NOT NULL AND ISNULL(hhld_cnt_sum,0) < 20 AND sigungu_cd NOT LIKE '11%' ORDER BY NEWID();""")
ids = [r[0] for r in ms.fetchall()]; ms.nextset(); ids += [r[0] for r in ms.fetchall()]
random.seed(3); random.shuffle(ids)
KEYS = ["poi", "poiSum", "poiBrand", "poiLife", "schoolZone", "schoolGroups", "schools", "schoolList", "scope", "kinders", "academy", "subways", "busStops", "busList", "busRoutes", "kinderLoaded", "schoolZoneLoaded", "공시적재"]
def 열기(port, cid):
    a = time.perf_counter()
    u = f"http://127.0.0.1:{SELF}/api/complexes/{cid}?_t=1" + ("&_nm=0" if port == 5173 else "") if SELF else f"http://127.0.0.1:{port}/api/complexes/{cid}?_t=1"
    with urllib.request.urlopen(u, timeout=180) as r: b = r.read()
    return (time.perf_counter() - a) * 1000, json.loads(b)
t1, t2, 다름, 순서만, 예, 나머지다름, 나머지칸 = [], [], {}, {}, [], 0, {}
for i, cid in enumerate(ids):
    try:
        if i % 2: (a1, j1), (a2, j2) = 열기(5173, cid), 열기(5174, cid)
        else: (a2, j2), (a1, j1) = 열기(5174, cid), 열기(5173, cid)
    except Exception as e:
        print("  실패", cid, e, flush=True); continue
    t1.append(a1); t2.append(a2)
    for k in KEYS:
        x, y = j1.get(k), j2.get(k)
        if x != y:
            if isinstance(x, list) and isinstance(y, list) and sorted(map(json.dumps, x)) == sorted(map(json.dumps, y)): 순서만[k] = 순서만.get(k, 0) + 1
            else:
                다름[k] = 다름.get(k, 0) + 1
                if len(예) < 8: 예.append((cid, k, json.dumps(x, ensure_ascii=False)[:300], json.dumps(y, ensure_ascii=False)[:300]))
    j1.pop("_timing", None); j2.pop("_timing", None)
    dk = [k for k in set(j1) | set(j2) if k not in KEYS and j1.get(k) != j2.get(k)]
    if dk:
        나머지다름 += 1
        for k in dk: 나머지칸[k] = 나머지칸.get(k, 0) + 1
    if (i + 1) % 50 == 0: print(f"  {i+1}/{len(ids)} · 지금 중간 {statistics.median(t1):.0f}ms · 개발 중간 {statistics.median(t2):.0f}ms", flush=True)
def 요약(x): x = sorted(x); return f"중간 {x[len(x)//2]:.0f} · 95% {x[int(len(x)*.95)]:.0f} · 최대 {x[-1]:.0f} ms"
print(("적재DB 질의(_nm=0)" if SELF else "지금 사이트(5173)") + " 상세 전체:", 요약(t1)); print(("매칭 테이블(nm)   " if SELF else "개발판(5174)     ") + " 상세 전체:", 요약(t2))
print("바꾼 칸 결과 다름:", 다름 or "없음", "· 순서만 다름:", 순서만 or "없음", "· 안 바꾼 칸이 다른 단지(그 사이 바뀐 것 등):", 나머지다름, 나머지칸)
for e in 예: print("   ", e)
