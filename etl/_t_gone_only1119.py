"""11-19 원천에만 있는 줄이 왜 적재DB 에 없나(읽기만): 한 묶음을 받아 빠진 줄과 적재DB 의 비슷한 줄을 견준다."""
import sys, os, collections
sys.path.insert(0, os.path.dirname(__file__))
from load_rtms import KINDS, ENV, fetch, load_env, 묶음키들, 키값
from svc_publish import env, ms_conn
cur = ms_conn(env()).cursor()
cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT TOP 3 trade_kind, sgg_cd, ym, 원천에만, 원천줄, 적재줄 FROM ops.rtms_gone_bundle WHERE run_id = 2 AND 원천에만 > 0 AND trade_kind = %s ORDER BY 원천에만 DESC", (sys.argv[1],))
key = load_env(ENV)["DATA_GO_KR_KEY"].strip()
for kind, sgg, ym, only, ns, nd in cur.fetchall():
    print(f"== {kind} {sgg} {ym} 원천에만 {only} · 원천 {ns} · 적재 {nd}")
    rows, st = fetch(KINDS[kind][0], key, sgg, ym)
    cur.execute("SELECT nat_key FROM silver.rtms_trade WITH (NOLOCK) WHERE sgg_cd = %s AND trade_kind = %s AND deal_ymd LIKE %s", (sgg, kind, ym + "%"))
    have = {bytes(r[0]) for r in cur.fetchall()}
    miss = [(r, b, n) for r, b, n, _ in 묶음키들(kind, sgg, rows) if n not in have]
    print("  빠진 줄", len(miss), "· 기본키는 있음", sum(1 for _, b, _ in miss if b in have))
    for r, b, n in miss[:3]:
        v = 키값(kind, sgg, r); print("  원천:", {k: v[k] for k in ("sgg_cd", "umd_nm", "jibun", "bld_nm", "deal_ymd", "deal_amount", "exclu_use_ar", "floor_no")})
        cur.execute("SELECT TOP 3 trade_sk, sgg_cd, umd_nm, jibun, bld_nm, deal_ymd, deal_amount, exclu_use_ar, floor_no, loaded_at FROM silver.rtms_trade WITH (NOLOCK) WHERE trade_kind = %s AND deal_ymd = %s AND deal_amount = %s",
                    (kind, v["deal_ymd"], v["deal_amount"]))
        for x in cur.fetchall(): print("     적재DB 비슷:", x)
