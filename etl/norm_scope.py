# -*- coding: utf-8 -*-
"""norm_scope - 개발판 시험: 단지 상세의 '이 법정동에 그 자료를 받았나'(scope) 를 법정동 한 줄짜리 표로 (2026-10-27)
  지금은 단지를 열 때마다 수천만 줄 표에 EXISTS 를 다시 묻는다(중간 1.26초 — 상세에서 가장 느린 질의). 같은 법정동이면 답이 같다.
  ★ 값 = 지금 질의와 같은 뜻(is_current · pnu 앞 10자리 = 법정동 · kapt bjd_code · 관리비는 시군구 · 층별은 표제부의 법정동). 적재가 끝날 때마다 다시 만든다(시험).
  시험 DB teomoony_test 의 lawd_scope · complex_lawd 에만 쓴다. 적재DB 는 읽기만."""
import time
from svc_publish import env, ms_conn
from norm_test import pgc
E = env(); t = pgc("teomoony_test"); ms = ms_conn(E).cursor()
def q(sql):
    a = time.time(); ms.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; " + sql)
    while ms.description is None and ms.nextset(): pass
    r = ms.fetchall(); return r, time.time() - a
축 = {
 "필지": "SELECT DISTINCT LEFT(pnu, 10) FROM silver.cadastral_parcel WHERE is_current = 1",
 "건물": "SELECT DISTINCT LEFT(pnu, 10) FROM silver.building_footprint WHERE is_current = 1",
 "인허가": "SELECT DISTINCT LEFT(pnu, 10) FROM silver.arch_permit WHERE is_current = 1",
 "kapt": "SELECT DISTINCT bjd_code FROM silver.kapt_complex WHERE is_current = 1",
 "주택가격": "SELECT DISTINCT LEFT(pnu, 10) FROM silver.bld_hsprc WHERE is_current = 1",
 "전유부": "SELECT DISTINCT LEFT(pnu, 10) FROM silver.bld_expos WHERE is_current = 1",
 "층별": "SELECT DISTINCT t2.sigungu_cd + t2.bjdong_cd FROM silver.bld_flr_outline f JOIN silver.bld_title t2 ON t2.mgm_bldrgst_pk = f.mgm_bldrgst_pk AND t2.is_current = 1 WHERE f.is_current = 1",
}
있음 = {}
for k, sql in 축.items():
    r, s = q(sql); 있음[k] = {x[0] for x in r if x[0]}; print(f"  {k}: 법정동 {len(있음[k]):,} · {s:.0f}초", flush=True)
r, s = q("SELECT DISTINCT LEFT(k2.bjd_code, 5) FROM silver.kapt_cost kc JOIN silver.kapt_complex k2 ON k2.kapt_code = kc.kapt_code AND k2.is_current = 1")
관리비구 = {x[0] for x in r if x[0]}; print(f"  관리비구: 시군구 {len(관리비구)} · {s:.0f}초", flush=True)
r, s = q("SELECT complex_id, sigungu_cd + bjdong_cd FROM gold.complex WHERE sigungu_cd IS NOT NULL AND bjdong_cd IS NOT NULL")
t.execute("DROP TABLE IF EXISTS complex_lawd"); t.execute("CREATE TABLE complex_lawd (complex_id int PRIMARY KEY, lawd text)")
with t.cursor() as c, c.copy("COPY complex_lawd FROM STDIN") as cp:
    for x in r: cp.write_row(x)
lawds = {x[1] for x in r}
print(f"  complex_lawd: {len(r):,} · 법정동 {len(lawds):,} · {s:.0f}초", flush=True)
t.execute("DROP TABLE IF EXISTS lawd_scope")
t.execute('CREATE TABLE lawd_scope (lawd text PRIMARY KEY, "필지" int, "건물" int, "인허가" int, kapt int, "관리비구" int, "주택가격" int, "전유부" int, "층별" int)')
with t.cursor() as c, c.copy("COPY lawd_scope FROM STDIN") as cp:
    for L in lawds:
        cp.write_row([L] + [1 if L in 있음[k] else 0 for k in ("필지", "건물", "인허가", "kapt")] + [1 if L[:5] in 관리비구 else 0]
                     + [1 if L in 있음[k] else 0 for k in ("주택가격", "전유부", "층별")])
print("  lawd_scope 끝", flush=True)
