# -*- coding: utf-8 -*-
"""_mois_vm - 행안부 약국을 **쪽 단위로 나눠** 받는다(2026-10-22). 한 번에 ~150초씩 여러 번 불러 이어 받는다.
  python3 _mois_vm.py fetch     빠진 쪽만 병렬로 받는다(쪽마다 _mois_raw/코드_쪽.json)
  python3 _mois_vm.py sql 파일  다 모였으면(코드별 totalCount 와 건수 일치) SQL 파일로
★ 원문 파일은 받은 그대로. 다 안 모인 코드가 하나라도 있으면 SQL 을 만들지 않는다."""
import json, os, sys, time, math
from concurrent.futures import ThreadPoolExecutor, as_completed
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import load_mois_pharmacy as M
RAW = os.path.join(HERE, "_mois_raw"); os.makedirs(RAW, exist_ok=True)
e = M.env(); key = e.get("DATA_GO_KR_KEY", "")

def fn(c, p): return os.path.join(RAW, f"{c}_{p:03d}.json")

def one(c, p):
    tot, rows = M.get(key, p, c)
    json.dump({"tot": tot, "rows": rows}, open(fn(c, p) + ".tmp", "w", encoding="utf-8"), ensure_ascii=False)
    os.replace(fn(c, p) + ".tmp", fn(c, p)); return c, p, tot, len(rows)

def totals():
    t = {}
    for c in M.CODES:
        if os.path.exists(fn(c, 1)): t[c] = json.load(open(fn(c, 1), encoding="utf-8"))["tot"]
    return t

if sys.argv[1] == "fetch":
    t0 = time.time(); budget = float(sys.argv[2]) if len(sys.argv) > 2 else 140
    with ThreadPoolExecutor(26) as ex:
        for f in as_completed([ex.submit(one, c, 1) for c in M.CODES if c not in totals()]):
            try: f.result()
            except Exception as x: print("!", x)
    t = totals(); todo = [(c, p) for c, n in t.items() for p in range(2, math.ceil(n / 100) + 1) if not os.path.exists(fn(c, p))]
    print("남은 쪽", len(todo), "· 시간", round(time.time() - t0), flush=True)
    with ThreadPoolExecutor(30) as ex:
        fs = [ex.submit(one, c, p) for c, p in todo[:int(sys.argv[3]) if len(sys.argv) > 3 else 60]]
        for f in as_completed(fs):
            try: f.result()
            except Exception as x: print("!", x)
    t = totals(); left = [(c, p) for c, n in t.items() for p in range(1, math.ceil(n / 100) + 1) if not os.path.exists(fn(c, p))]
    print("코드", len(t), "/", len(M.CODES), "· 남은 쪽", len(left), "· 총", sum(t.values()), "· 시간", round(time.time() - t0))
elif sys.argv[1] == "sql":
    t = totals(); keep = []
    assert len(t) == len(M.CODES), "page1 빠짐"
    for c, n in t.items():
        rows = []
        for p in range(1, math.ceil(n / 100) + 1): rows += json.load(open(fn(c, p), encoding="utf-8"))["rows"]
        ids = {x.get("MNG_NO") for x in rows}
        if len(rows) != n or len(ids) != n: sys.exit(f"{c}: 받은 {len(rows)} (고유 {len(ids)}) ≠ {n} — 만들지 않음")
        keep += rows   # ★ 개방자치단체코드로 이미 서울·안양만 — 주소 글자로 거르면 '서울시 광진구'·'상계9동 649' 같은 옛 표기 2천 건이 빠진다
    print("서울·안양", len(keep)); M.emit(keep, e, sys.argv[2])
