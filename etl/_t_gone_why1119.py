"""11-19 사라진 줄과 원천에만 있는 줄이 짝으로 보이는 묶음에서 무엇이 바뀌었나(읽기만)"""
import sys, os, collections
sys.path.insert(0, os.path.dirname(__file__))
from load_rtms import KINDS, ENV, fetch, load_env, 묶음키들, 키값
from svc_publish import env, ms_conn
cur = ms_conn(env()).cursor(); key = load_env(ENV)["DATA_GO_KR_KEY"].strip()
for kind, sgg, ym in [("APT_RENT", "11230", "202502"), ("APT_TRADE_DEV", "11350", "202608")]:
    rows, st = fetch(KINDS[kind][0], key, sgg, ym)
    src = {n: (r, 키값(kind, sgg, r)) for r, b, n, _ in 묶음키들(kind, sgg, rows)}
    cur.execute("SELECT nat_key, umd_nm, jibun, bld_nm, bld_dong, deal_ymd, deal_amount, deposit, monthly_rent, exclu_use_ar, total_floor_ar, floor_no FROM silver.rtms_trade WITH (NOLOCK) WHERE sgg_cd = %s AND trade_kind = %s AND deal_ymd LIKE %s", (sgg, kind, ym + "%"))
    db = {bytes(r[0]): r[1:] for r in cur.fetchall()}
    gone = [v for k, v in db.items() if k not in src]; only = [v for k, v in src.items() if k not in db]
    print(f"== {kind} {sgg} {ym} 사라짐 {len(gone)} · 원천에만 {len(only)}")
    cols = ("umd_nm", "jibun", "bld_nm", "bld_dong", "deal_ymd", "deal_amount", "deposit", "monthly_rent", "exclu_use_ar", "total_floor_ar", "floor_no")
    바뀜 = collections.Counter(); 예 = 0
    for g in gone:
        gd = dict(zip(cols, g))
        for r, v in only:
            same = [c for c in cols if str(v[c] if v[c] is not None else "") == str(gd[c] if gd[c] is not None else "") or (c in ("exclu_use_ar","total_floor_ar") and v[c] is not None and gd[c] is not None and float(v[c]) == float(gd[c]))]
            if len(same) >= len(cols) - 2:
                d = tuple(c for c in cols if c not in same); 바뀜[d] += 1
                if 예 < 3: print("   예:", {c: (gd[c], v[c]) for c in d}); 예 += 1
                break
    print("   바뀐 칸:", 바뀜.most_common(5))
