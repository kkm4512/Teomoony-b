import sys
from svc_publish import env, ms_conn
cur = ms_conn(env()).cursor()
T = ["silver.land_char","silver.land_use_plan","silver.land_move_hist","silver.arch_permit","silver.bld_closed_title","silver.kapt_complex","silver.kapt_cost",
     "silver.academy","silver.childcare","silver.kindergarten","silver.kinder_info","silver.mois_pharmacy","silver.hira_inst","silver.school","silver.schoolinfo",
     "silver.school_zone","silver.subway_station","silver.bus_stop","silver.applyhome_pblanc","silver.redev_zone","silver.adm_boundary","silver.ned_aphus_price","silver.bld_gis"]
KEYS = ["pnu","sigungu_cd","sgg_cd","signgu_cd","bjd_code","lawd_cd","adm_cd","adm_cd_sgis","sido_cd","ctprvn_cd","adrcd_cd","atpt_ofcdc_sc_code","sigun_cd","ldong_cd","bjdong_cd"]
for t in T:
    cur.execute("SELECT name FROM sys.columns WHERE object_id = OBJECT_ID(%s)", (t,)); cols = [r[0] for r in cur.fetchall()]
    k = next((c for c in KEYS if c in cols), None)
    cur_f = " WHERE is_current = 1" if "is_current" in cols else ""
    if t == "silver.kapt_cost":
        q = "SELECT LEFT(k.bjd_code,2), COUNT(DISTINCT c.kapt_code) FROM silver.kapt_cost c JOIN silver.kapt_complex k ON k.kapt_code = c.kapt_code AND k.is_current = 1 GROUP BY LEFT(k.bjd_code,2)"
    elif not k:
        print(f"{t}: 키 칸 없음 · 칸 {cols[:12]}"); continue
    else:
        q = f"SELECT LEFT(CAST([{k}] AS VARCHAR(20)),2), COUNT(*) FROM {t} WITH (NOLOCK){cur_f} GROUP BY LEFT(CAST([{k}] AS VARCHAR(20)),2)"
    try:
        cur.execute(q); rows = sorted(cur.fetchall(), key=lambda r: str(r[0]))
        print(f"{t} [{k}] 시도 {len(rows)}: " + " ".join(f"{a}:{b:,}" for a, b in rows))
    except Exception as e: print(f"{t}: {str(e)[:120]}")
