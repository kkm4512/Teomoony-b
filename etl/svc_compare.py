#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_compare - 옛 경로(적재DB 를 바로 읽는 서버 응답) vs 서비스DB 에 담긴 응답 대조 (2026-10-24)
  py svc_compare.py --random 300 --top 100            무작위 300 + 수도권 큰 단지 100
  py svc_compare.py --serve 20                        화면 길(물음표 없는 주소)이 서비스DB 에서 나가는지(X-Svc) · 같은 값인지
★ 다르면 어느 칸(최상위 키)이 다른지 적는다. 발행 뒤에 적재가 바뀐 경우(최근 거래 · 관리비)는 '시차' 로 따로 센다."""
import argparse, gzip, json, random, re, sys, time, urllib.request
import psycopg
from svc_publish import env, fetch, TIMING, WEB

def norm(t):
    return json.loads(TIMING.sub("", t, count=1))

def diffkeys(a, b, p=""):
    if type(a) != type(b): return [p or "(전체)"]
    if isinstance(a, dict):
        out = []
        for k in set(a) | set(b):
            if a.get(k) != b.get(k): out.append(f"{p}.{k}" if p else k)
        return out
    if isinstance(a, list): return [] if a == b else [p or "(목록)"]
    return [] if a == b else [p or "(값)"]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--random", type=int, default=300); ap.add_argument("--top", type=int, default=100)
    ap.add_argument("--serve", type=int, default=0)
    a = ap.parse_args()
    e = env()
    pg = psycopg.connect(host="127.0.0.1", port=15432, dbname="teomoony", user="teomoony", password=e["SVC_DB_PASSWORD"])
    c = pg.cursor()
    c.execute("SELECT DISTINCT j.complex_id FROM svc.complex_json j WHERE j.kind = 'detail'")
    have = [r[0] for r in c.fetchall()]
    c.execute("""SELECT l.complex_id FROM svc.complex_list l JOIN svc.complex_json j ON j.complex_id = l.complex_id AND j.kind = 'detail'
                 WHERE left(l.sgg_cd,2) IN ('11','28','41') ORDER BY l.hhld DESC LIMIT %s""", (a.top,))
    top = [r[0] for r in c.fetchall()]
    pick = sorted(set(random.sample(have, min(a.random, len(have))) + top))
    print(f"서비스DB 에 담긴 단지 {len(have):,} 중 대조 {len(pick)}(무작위 {min(a.random, len(have))} + 수도권 큰 단지 {len(top)})", flush=True)
    c.execute("SELECT complex_id, kind, status, body_gz FROM svc.complex_json WHERE complex_id = ANY(%s)", (pick,))
    rows = c.fetchall()
    same = diff = err = 0; 칸 = {}; 보기 = []
    t0 = time.time()
    for cid, kind, st, gz in rows:
        new = gzip.decompress(gz).decode("utf-8")
        s2, old = fetch(cid, kind)
        if s2 is None: err += 1; continue
        if kind == "detail": old = TIMING.sub("", old, count=1)
        if s2 == st and old == new: same += 1; continue
        try: ks = diffkeys(json.loads(old), json.loads(new))
        except Exception: ks = ["(JSON)"]
        if s2 != st: ks = [f"상태 {st}→{s2}"] + ks
        diff += 1
        for k in ks: 칸[f"{kind}:{k}"] = 칸.get(f"{kind}:{k}", 0) + 1
        if len(보기) < 15: 보기.append(f"{cid}/{kind}: {', '.join(ks[:6])}")
    print(f"\n대조 {len(rows):,}건(단지×종류) · 같음 {same:,} · 다름 {diff:,} · 못 받음 {err} · {time.time()-t0:.0f}초")
    if 칸:
        print("다른 칸(많은 순):")
        for k, n in sorted(칸.items(), key=lambda x: -x[1])[:25]: print(f"  {n:5,}  {k}")
        print("보기:"); [print("  " + x) for x in 보기]
    if a.serve:
        ok = bad = 0
        for cid in pick[: a.serve]:
            r = urllib.request.urlopen(urllib.request.Request(f"{WEB}/api/complexes/{cid}", headers={"Accept-Encoding": "identity"}), timeout=60)
            x = r.headers.get("X-Svc"); body = r.read().decode("utf-8")
            c.execute("SELECT body_gz FROM svc.complex_json WHERE complex_id = %s AND kind = 'detail'", (cid,))
            same_ = gzip.decompress(c.fetchone()[0]).decode("utf-8") == body
            if x in ("hit", "redis") and same_: ok += 1
            else: bad += 1; print(f"  화면 길 {cid}: X-Svc={x} 같음={same_}")
        print(f"화면 길: 서비스DB 에서 나감 {ok} / 아님 {bad}")
    sys.exit(0)

if __name__ == "__main__":
    main()
