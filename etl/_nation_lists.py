from svc_publish import env, ms_conn
cur = ms_conn(env()).cursor()
# 법정 시군구(일반구 포함) — 법정동 코드 앞 5자리 · 지금 쓰는 것 · 시도 줄(xx000) 빼고
cur.execute("""SELECT DISTINCT LEFT(lawd_cd, 5) FROM meta.lawd_code WHERE ISNULL(is_abolished, 0) = 0 AND RIGHT(LEFT(lawd_cd, 5), 3) <> '000' ORDER BY 1""")
sgg = [r[0] for r in cur.fetchall()]
open("_export/nation_sgg.txt", "w").write(" ".join(sgg) + "\n")
# 시 단위(일반구는 시로) — 어린이집
si = sorted({(s[:4] + "0") if s[-1] != "0" and (s[:4] + "0") not in ("") else s for s in sgg})
open("_export/nation_si.txt", "w").write(" ".join(si) + "\n")
# K-apt 단지가 있는 시군구
cur.execute("SELECT DISTINCT LEFT(bjd_code, 5) FROM silver.kapt_complex WHERE is_current = 1 AND bjd_code IS NOT NULL ORDER BY 1")
ks = [r[0] for r in cur.fetchall()]
open("_export/nation_kapt_sgg.txt", "w").write(" ".join(ks) + "\n")
print(len(sgg), len(si), len(ks))
