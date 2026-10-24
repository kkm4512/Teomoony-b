#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_compare_misc - 지금 위치 지역 · 내 위치 주변 · 청약 핀: 옛 경로(_x=1) vs 서비스DB 길(_svc=1) (2026-10-25)
  py svc_compare_misc.py --n 30"""
import argparse, json, random, time, urllib.request
WEB = "http://127.0.0.1:5173"
def get(u):
    t = time.time()
    r = urllib.request.urlopen(urllib.request.Request(WEB + u, headers={"Accept-Encoding": "identity"}), timeout=120)
    return r.status, r.headers.get("X-Svc"), json.loads(r.read().decode("utf-8")), int((time.time() - t) * 1000)
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--n", type=int, default=30); a = ap.parse_args()
    rnd = random.Random()
    pt = lambda: (rnd.uniform(37.40, 37.70), rnd.uniform(126.80, 127.20))
    묶음 = []
    for _ in range(a.n):
        y, x = pt(); 묶음.append(("지역", f"/api/areas/here?lat={y:.6f}&lng={x:.6f}"))
    for i in range(a.n):
        y, x = pt(); r = rnd.choice([300, 1000, 1000, 3000]); 묶음.append(("주변", f"/api/complexes/near?lat={y:.7f}&lng={x:.7f}&r={r}&limit={rnd.choice([30, 100])}"))
    for i in range(a.n // 2):
        y, x = pt(); s = rnd.uniform(0.02, 0.3); 묶음.append(("청약", f"/api/applyhome/pins?bbox={x - s:.6f},{y - s * .8:.6f},{x + s:.6f},{y + s * .8:.6f}"))
    묶음.append(("청약", "/api/applyhome/pins?bbox=124,33,132,39.5"))
    셈 = {}
    for k, u in 묶음:
        c = 셈.setdefault(k, {"같음": 0, "다름": 0, "못": 0, "옛": 0, "새": 0, "보기": []})
        try:
            s1, _, o, m1 = get(u + "&_x=1"); s2, x2, n, m2 = get(u + "&_svc=1")
        except Exception as ex:
            c["못"] += 1; c["보기"].append(f"못 {u}: {ex}"); continue
        c["옛"] += m1; c["새"] += m2
        if x2 != "hit": c["못"] += 1; c["보기"].append(f"서비스DB 길 아님 {u}"); continue
        if s1 == s2 and o == n: c["같음"] += 1; continue
        c["다름"] += 1
        js = lambda v: json.dumps(v, ensure_ascii=False)
        if k == "주변":
            od = {(d["complex_id"], d.get("lawd_nm")): d for d in o.get("단지", [])}; nd = {(d["complex_id"], d.get("lawd_nm")): d for d in n.get("단지", [])}
            거리차 = [(i, od[i]["거리m"], nd[i]["거리m"]) for i in od if i in nd and od[i]["거리m"] != nd[i]["거리m"]]
            c["보기"].append(f"{u} · 옛 {len(od)} 새 {len(nd)} · 옛에만 {len(set(od) - set(nd))} 새에만 {len(set(nd) - set(od))} · 거리 다름 {거리차[:5]}")
        else:
            c["보기"].append(f"{u}\n      옛 {js(o)[:400]}\n      새 {js(n)[:400]}")
    for k, c in 셈.items():
        m = max(1, c["같음"] + c["다름"])
        print(f"{k}: 같음 {c['같음']} · 다름 {c['다름']} · 못 {c['못']} · 평균 옛 {c['옛'] // m:,}ms → 새 {c['새'] // m:,}ms")
        for x in c["보기"][:8]: print("   " + x)
if __name__ == "__main__":
    main()
