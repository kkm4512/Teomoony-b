"""11-18 load_rtms 동늦게채움 찾기 시험(읽기만): 동 있는 줄의 값으로 load_rtms 와 같은 질의를 만들어 동 빈 옛 줄을 딱 하나 찾는지."""
import sys, os, decimal
sys.path.insert(0, os.path.dirname(__file__))
from svc_publish import env, ms_conn
cur = ms_conn(env()).cursor()
키칸 = ("umd_nm", "jibun", "bld_nm", "deal_ymd", "deal_amount", "deposit", "monthly_rent", "exclu_use_ar", "total_floor_ar", "floor_no")
def 같음(c): return f"({c} = %s OR ({c} IS NULL AND %s IS NULL))"
cur.execute("""SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT TOP (300) n.trade_sk, o.trade_sk, n.trade_kind, n.sgg_cd, """ + ", ".join("n." + c for c in 키칸) + """
FROM silver.rtms_trade n JOIN silver.rtms_trade o ON o.trade_kind = n.trade_kind AND o.sgg_cd = n.sgg_cd AND o.umd_nm = n.umd_nm AND o.deal_ymd = n.deal_ymd
 AND ISNULL(o.jibun,'') = ISNULL(n.jibun,'') AND ISNULL(o.bld_nm,'') = ISNULL(n.bld_nm,'') AND ISNULL(o.deal_amount,-1) = ISNULL(n.deal_amount,-1)
 AND ISNULL(o.deposit,-1) = ISNULL(n.deposit,-1) AND ISNULL(o.monthly_rent,-1) = ISNULL(n.monthly_rent,-1) AND ISNULL(o.exclu_use_ar,-1) = ISNULL(n.exclu_use_ar,-1)
 AND ISNULL(o.total_floor_ar,-1) = ISNULL(n.total_floor_ar,-1) AND ISNULL(o.floor_no,-9999) = ISNULL(n.floor_no,-9999)
WHERE ISNULL(n.bld_dong,'') <> '' AND ISNULL(o.bld_dong,'') = '' ORDER BY NEWID()""")
rows = cur.fetchall(); 맞음 = 틀림 = 0
for r in rows:
    nsk, osk, kind, sgg = r[:4]
    vals = dict(zip(키칸, [float(v) if isinstance(v, decimal.Decimal) else v for v in r[4:]]))
    cur.execute("SELECT TOP (2) trade_sk FROM silver.rtms_trade WHERE trade_kind = %s AND sgg_cd = %s "
                "AND ISNULL(bld_dong, '') = '' AND ISNULL(cdeal_type, '') = '' AND " + " AND ".join(같음(c) for c in 키칸),
                (kind, sgg) + tuple(v for c in 키칸 for v in (vals[c], vals[c])))
    f = [x[0] for x in cur.fetchall()]
    if f == [osk]: 맞음 += 1
    else:
        틀림 += 1
        if 틀림 <= 5: print("틀림", nsk, osk, f, vals)
print(f"시험 {len(rows)} · 맞음 {맞음} · 틀림 {틀림}")
