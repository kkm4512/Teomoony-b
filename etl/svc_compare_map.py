#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_compare_map - 지도 층: 옛 경로(_x=1) vs 서비스DB 길(_svc=1) 대조 (2026-10-25, 2단계)
  py svc_compare_map.py --n 30
★ 같은 bbox 를 두 길로 받아 값이 같은지 본다. 목록 순서는 옛 경로도 정해 두지 않은 곳이 있어(필지 · 건물 · 행정동) 집합으로 비교.
★ 상한에 걸려 잘린 응답(필지 · 건물 3000)은 옛 경로가 '어느 3000' 인지 정하지 않으므로 건수 · 잘림만 비교한다.
★ 줄 순서까지 같아야 하는 곳(신축 · 닫힌 핀 · 법정동 — ORDER BY 가 있다)은 순서도 본다."""
import argparse, json, random, time, urllib.request
from svc_compare import canon
WEB = "http://127.0.0.1:5173"
# 층: (경로, bbox 한 변 범위(도), 순서도 보나, 목록 키)
층들 = [("/api/parcels", (0.003, 0.02), False, "features"), ("/api/buildings", (0.003, 0.02), False, "features"),
        ("/api/lawds", (0.03, 0.4), True, "features"), ("/api/adms", (0.03, 0.4), False, "features"),
        ("/api/closed/pins", (0.01, 0.2), True, "핀"), ("/api/newbuilds", (0.02, 0.5), True, "markers")]

def get(u):
    t = time.time()
    r = urllib.request.urlopen(urllib.request.Request(WEB + u, headers={"Accept-Encoding": "identity"}), timeout=120)
    return r.status, r.headers.get("X-Svc"), json.loads(r.read().decode("utf-8")), int((time.time() - t) * 1000)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--n", type=int, default=20); ap.add_argument("--only", default="")
    a = ap.parse_args(); random.seed()
    합 = {}
    for 경로, (s0, s1), 순서, 키 in 층들:
        if a.only and 경로 not in a.only.split(","): continue
        같음 = 다름 = 잘림 = 못 = 0; 옛ms = 새ms = 0; 보기 = []
        for i in range(a.n):
            s = random.uniform(s0, s1)
            cx, cy = random.uniform(126.75, 127.25), random.uniform(37.35, 37.70)   # 수도권(서울 · 경기 남부 · 인천 동쪽)
            bb = f"{cx - s:.9f},{cy - s * 0.8:.9f},{cx + s:.9f},{cy + s * 0.8:.9f}"
            if 경로 == "/api/newbuilds" and i == 0: q = ""   # 전국 목록(bbox 없음)도 한 번
            else: q = f"bbox={bb}"
            try:
                st1, x1, old, m1 = get(f"{경로}?{q}&_x=1" if q else f"{경로}?_x=1")
                st2, x2, new, m2 = get(f"{경로}?{q}&_svc=1" if q else f"{경로}?_svc=1")
            except Exception as e:
                못 += 1; 보기.append(f"못 받음 {q}: {e}"); continue
            옛ms += m1; 새ms += m2
            if x2 != "hit": 못 += 1; 보기.append(f"서비스DB 길 아님(X-Svc={x2}) {q}"); continue
            if st1 != st2: 다름 += 1; 보기.append(f"상태 {st1}/{st2} {q}"); continue
            if isinstance(old, dict) and old.get("잘림"):
                잘림 += 1
                if not (new.get("잘림") and len(old[키]) == len(new[키])): 다름 += 1; 보기.append(f"잘림 건수 {len(old[키])}/{len(new[키])} {q}")
                continue
            if 순서 and old == new: 같음 += 1; continue
            if not 순서 and canon(old) == canon(new): 같음 += 1; continue
            다름 += 1
            o, n = old.get(키, []), new.get(키, [])
            js = lambda v: json.dumps(v, ensure_ascii=False, sort_keys=True)
            so, sn = {js(v) for v in o}, {js(v) for v in n}
            보기.append(f"{q} · 옛 {len(o)} 새 {len(n)} · 옛에만 {len(so - sn)} 새에만 {len(sn - so)}" + (" · 순서만 다름" if so == sn else "")
                        + ("" if so == sn else f" · 예) 옛 {(sorted(so - sn) or [''])[0][:300]} | 새 {(sorted(sn - so) or [''])[0][:300]}"))
        k = max(1, a.n - 못)
        print(f"{경로:<18} 같음 {같음} · 다름 {다름} · 잘림(건수만) {잘림} · 못 {못} · 평균 옛 {옛ms // k:,}ms → 새 {새ms // k:,}ms", flush=True)
        for x in 보기[:6]: print("    " + x, flush=True)

if __name__ == "__main__":
    main()
