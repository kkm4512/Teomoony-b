# -*- coding: utf-8 -*-
"""hub_compare - 우리 대장 표(silver, API 로 받은 것) vs 허브 뷰(hubv) — 같은 시군구에서 칸마다 몇 줄이 다른지 (2026-10-25)
  py hub_compare.py 11305 [표 …]      (기본 9표 전부 · 시군구 하나만 — 공시가격 3,700만 줄 전체 비교는 무겁다)"""
import sys, time
from svc_publish import env, ms_conn
KEYS = {"bld_basis_outline": ["mgm_bldrgst_pk"], "bld_title": ["mgm_bldrgst_pk"], "bld_recap_title": ["mgm_bldrgst_pk"],
        "bld_atch_jibun": ["mgm_bldrgst_pk", "atch_pnu"], "bld_expos": ["mgm_bldrgst_pk"], "bld_jijigu": ["mgm_bldrgst_pk", "jijigu_gb_cd", "jijigu_cd"],
        "bld_flr_outline": ["mgm_bldrgst_pk", "flr_gb_cd", "flr_no", "main_purps_cd", "strct_cd", "main_atch_gb_cd"],
        "bld_expos_pubuse_area": ["mgm_bldrgst_pk", "expos_pubuse_gb_cd", "main_atch_gb_cd", "flr_gb_cd", "flr_no", "main_purps_cd", "strct_cd"],
        "bld_hsprc": ["mgm_bldrgst_pk", "std_day", "crtn_day"]}
SKIP = {"row_hash", "src_run_id", "valid_from", "valid_to", "is_current", "basis_sk", "bld_title_sk", "recap_sk", "atch_sk", "expos_sk", "jijigu_sk", "flr_sk", "hsprc_sk", "bldg_id"}
sgg = sys.argv[1]; only = sys.argv[2:] or list(KEYS)
ms = ms_conn(env()); cur = ms.cursor()
for t in only:
    t0 = time.time()
    cur.execute("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='silver' AND TABLE_NAME=%s", (t,)); sc = {r[0] for r in cur.fetchall()}
    cur.execute("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='hubv' AND TABLE_NAME=%s", (t,)); hc = {r[0] for r in cur.fetchall()}
    cols = sorted((sc & hc) - SKIP - set(KEYS[t]))
    # 시군구 거르기: 표에 sigungu_cd 가 없으면(층별개요) 표제부 PK 로
    flt = (f"s.sigungu_cd = '{sgg}'" if "sigungu_cd" in sc else
           f"EXISTS (SELECT 1 FROM silver.bld_title b WHERE b.is_current = 1 AND b.sigungu_cd = '{sgg}' AND b.mgm_bldrgst_pk = s.mgm_bldrgst_pk)")
    on = " AND ".join(f"(h.[{k}] = s.[{k}] OR (h.[{k}] IS NULL AND s.[{k}] IS NULL))" for k in KEYS[t])
    diffs = ",\n  ".join(f"SUM(CASE WHEN h.[{KEYS[t][0]}] IS NOT NULL AND NOT (h.[{c}] = s.[{c}] OR (h.[{c}] IS NULL AND s.[{c}] IS NULL)) THEN 1 ELSE 0 END) AS [{c}]" for c in cols)
    sql = f"""SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 우리 = COUNT(*), 허브에있음 = SUM(CASE WHEN h.[{KEYS[t][0]}] IS NOT NULL THEN 1 ELSE 0 END),
  {diffs}
  FROM silver.{t} s OUTER APPLY (SELECT TOP 1 * FROM hubv.{t} h WHERE {on}) h
 WHERE s.is_current = 1 AND {flt}"""
    try:
        cur.execute(sql); r = cur.fetchone(); names = [d[0] for d in cur.description]
    except Exception as ex:
        print(f"{t}: 실패 {str(ex)[:300]}", flush=True); continue
    d = {n: v for n, v in zip(names, r)}
    다른칸 = {n: v for n, v in d.items() if n not in ("우리", "허브에있음") and v}
    print(f"{t}: 우리 {d['우리']:,} · 허브에 있음 {d['허브에있음']:,} · 칸 {len(cols)}개 중 다른 칸 {len(다른칸)}  {다른칸 if 다른칸 else ''} · {time.time()-t0:.0f}초", flush=True)
    # 허브에만 있는 줄
    cur.execute(f"""SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT COUNT(*) FROM hubv.{t} h WHERE {"h.sigungu_cd = '" + sgg + "'" if "sigungu_cd" in hc else "1 = 0"}
  AND NOT EXISTS (SELECT 1 FROM silver.{t} s WHERE s.is_current = 1 AND {on})""")
    print(f"   허브에만 {cur.fetchone()[0]:,}", flush=True)
