#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_compare_sugg - 자동완성: 옛 경로(_x=1) vs 서비스DB 길(_svc=1) 대조 (2026-10-25, 2단계 둘째 묶음)
  py svc_compare_sugg.py --n 120
★ 검색어는 서비스DB 의 이름들에서 무작위로 뽑는다(단지 이름 조각 · 동 · 역 · 학교 · 상가 앞부분 · 주소+번지 · 닫힌 대장 · 청약 · 옛 행정동 · 단지 번호 …).
★ 'ms'(걸린 시간)만 빼고 **순서까지** 같아야 같음."""
import argparse, json, random, time, urllib.parse, urllib.request
import psycopg
from svc_publish import env
WEB = "http://127.0.0.1:5173"

def get(u):
    t = time.time()
    r = urllib.request.urlopen(urllib.request.Request(WEB + u, headers={"Accept-Encoding": "identity"}), timeout=120)
    return r.status, r.headers.get("X-Svc"), json.loads(r.read().decode("utf-8")), int((time.time() - t) * 1000)

def 조각(s, rnd):
    s = (s or "").strip()
    if len(s) < 2: return None
    k = rnd.randint(2, min(5, len(s))); i = rnd.randint(0, len(s) - k)
    return s[i:i + k].strip() or None

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--n", type=int, default=100); ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--path", default="/api/suggest", help="/api/complexes = 목록 검색")
    a = ap.parse_args(); rnd = random.Random(a.seed or None)
    e = env(); pg = psycopg.connect(host="127.0.0.1", port=15432, dbname="teomoony", user="teomoony", password=e["SVC_DB_PASSWORD"], autocommit=True)
    pick = lambda sql, n: [r[0] for r in pg.execute(sql + f" ORDER BY random() LIMIT {n}").fetchall() if r[0]]
    m = max(4, a.n // 12)
    qs = ["래미안", "자이", "푸르지오", "힐스테이트", "아이파크", "은평", "드림아트빌라", "용신동", "서교동 445-4", "송파대로 345", "가락동 479", "1", "103835",
          "올림픽파크 포레온", "서울 마포구 서교동", "스타벅스", "파리바게뜨", "강남역", "신길제2구역", "abc", "APT"]
    qs += [조각(x, rnd) for x in pick("SELECT complex_nm FROM svc.lyr_sg_complex WHERE nm_ns IS NOT NULL", m * 2)]
    qs += pick("SELECT emd_nm FROM svc.lyr_sg_lawd", m) + pick("SELECT sgg_nm FROM svc.lyr_sg_sgg", m // 2 + 1)
    qs += pick("SELECT sttn_nm FROM svc.lyr_sg_subway", m // 2 + 1) + [조각(x, rnd) for x in pick("SELECT school_nm FROM svc.lyr_sg_school", m // 2 + 1)]
    qs += [(x or "")[:rnd.randint(2, 4)] for x in pick("SELECT bizes_nm FROM svc.lyr_sg_semas", m // 2 + 1)]
    qs += [" ".join(x.split()[-2:]) for x in pick("SELECT rep_plat_plc FROM svc.lyr_sg_complex WHERE rep_plat_plc ~ '[0-9]'", m)]
    qs += [조각(x, rnd) for x in pick('SELECT "이름" FROM svc.lyr_sg_closed WHERE "이름" IS NOT NULL', m // 2 + 1)]
    qs += [조각(x, rnd) for x in pick("SELECT house_nm FROM svc.lyr_sg_applyhome", m // 2 + 1)]
    qs += pick('SELECT "행정동명" FROM svc.lyr_sg_hdong_old', m // 2 + 1) + pick("SELECT zone_nm FROM svc.lyr_sg_redev", m // 2 + 1)
    qs += [str(x) for x in pick("SELECT complex_id FROM svc.lyr_sg_complex", 3)]
    qs = [q for q in dict.fromkeys(q for q in qs if q and len(q.strip()) >= 2)][: a.n + 21]
    if a.path != "/api/suggest": qs = ["", "은평", "용신동", "신당동"] + qs   # 목록 검색: 빈 검색(전체 목록) · 옛 행정동도
    같음 = 다름 = 못 = 0; 옛 = 새 = 0; 칸 = {}; 보기 = []
    for q in qs:
        u = a.path + "?q=" + urllib.parse.quote(q) + ("&recap=1" if a.path != "/api/suggest" and rnd.random() < 0.15 else "")
        try:
            s1, x1, o, m1 = get(u + "&_x=1"); s2, x2, n, m2 = get(u + "&_svc=1")
        except Exception as ex:
            못 += 1; 보기.append(f"못 받음 {q!r}: {ex}"); continue
        옛 += m1; 새 += m2
        if x2 != "hit": 못 += 1; 보기.append(f"서비스DB 길 아님 {q!r} X-Svc={x2}"); continue
        o.pop("ms", None); n.pop("ms", None)
        if s1 == s2 and o == n: 같음 += 1; continue
        다름 += 1
        if a.path != "/api/suggest":   # 목록 검색: 최상위 키별로
            og = {k: v for k, v in o.items()}; ng = {k: v for k, v in n.items()}
        else:
            og = {g["종류"]: g for g in o.get("묶음", [])}; ng = {g["종류"]: g for g in n.get("묶음", [])}
        다른묶음 = [k for k in dict.fromkeys(list(og) + list(ng)) if og.get(k) != ng.get(k)]
        if a.path == "/api/suggest" and {k: v for k, v in o.items() if k != "묶음"} != {k: v for k, v in n.items() if k != "묶음"}: 다른묶음.append("(묶음 밖)")
        for k in 다른묶음: 칸[k] = 칸.get(k, 0) + 1
        k0 = 다른묶음[0] if 다른묶음 else ""
        js = lambda v: json.dumps(v, ensure_ascii=False)[:600]
        보기.append(f"{q!r} · {다른묶음}\n      옛 {js(og.get(k0))}\n      새 {js(ng.get(k0))}")
    k = max(1, len(qs) - 못)
    print(f"{a.path} 대조 {len(qs)}개 · 같음 {같음} · 다름 {다름} · 못 {못} · 평균 옛 {옛 // k:,}ms → 새 {새 // k:,}ms")
    if 칸: print("다른 묶음:", ", ".join(f"{k} {v}" for k, v in sorted(칸.items(), key=lambda x: -x[1])))
    for x in 보기[:25]: print("  " + x)

if __name__ == "__main__":
    main()
