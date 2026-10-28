# -*- coding: utf-8 -*-
"""pms_swap - 인허가 표를 허브(전국)로 바꿔 끼운다 (2026-10-28) — hub_swap.py 와 같은 방법(__hub 를 만들고 색인 · 대조 · 이름 바꾸기 · API 표는 _api 로 남김)
  py pms_swap.py build | check | swap | back
  ★ check: 줄 수(허브 ≥ API) · 색인 수 · **값 대조**(API 와 허브에 다 있는 허가 PK 2만 개를 골라 칸별로 견줌) — 어긋남이 0.5% 넘으면 바꿔 끼우지 않는다."""
import os, subprocess, sys, time
from svc_publish import env, ms_conn
import hub_swap as H
TABLES = ["arch_permit", "arch_permit_dong"]
KEY = {"arch_permit": "mgm_pmsrgst_pk", "arch_permit_dong": "mgm_dong_ouln_pk"}
CMP = {"arch_permit": ["pnu", "plat_plc", "main_purps_nm", "hhld_cnt", "tot_area", "arch_pms_day", "use_apr_day", "arch_gb_nm"],
       "arch_permit_dong": ["pnu", "mgm_pmsrgst_pk", "main_purps_nm", "hhld_cnt", "tot_area", "strct_nm"]}
log = H.log
ms = ms_conn(env()); ms.autocommit(True); cur = ms.cursor(); op = sys.argv[1]
if op == "build":
    if subprocess.call([sys.executable, "ms_q.py", os.path.join("..", "deploy", "sql", "379_hub_views_pms.sql")], cwd=os.path.dirname(os.path.abspath(__file__))) != 0: sys.exit("뷰 실패")
    for t in TABLES: H.build(cur, t)
    op = "check"
if op == "check":
    bad = []
    for t in TABLES:
        k = KEY[t]
        cur.execute(f"""SELECT (SELECT COUNT_BIG(*) FROM silver.{t} WHERE is_current = 1), (SELECT COUNT_BIG(*) FROM silver.{t}__hub),
                               (SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('silver.{t}') AND type > 0),
                               (SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('silver.{t}__hub') AND type > 0)""")
        a, b, i1, i2 = cur.fetchone()
        diff = " + ".join(f"SUM(CASE WHEN ISNULL(CAST(a.[{c}] AS NVARCHAR(400)), N'~') <> ISNULL(CAST(h.[{c}] AS NVARCHAR(400)), N'~') THEN 1 ELSE 0 END)" for c in CMP[t])
        per = ", ".join(f"[{c}] = SUM(CASE WHEN ISNULL(CAST(a.[{c}] AS NVARCHAR(400)), N'~') <> ISNULL(CAST(h.[{c}] AS NVARCHAR(400)), N'~') THEN 1 ELSE 0 END)" for c in CMP[t])
        cur.execute(f"""SELECT 짝 = COUNT(*), 다른칸 = {diff}, 다른줄 = SUM(CASE WHEN {' OR '.join(f"ISNULL(CAST(a.[{c}] AS NVARCHAR(400)), N'~') <> ISNULL(CAST(h.[{c}] AS NVARCHAR(400)), N'~')" for c in CMP[t])} THEN 1 ELSE 0 END), {per}
                         FROM (SELECT TOP 20000 * FROM silver.{t} WHERE is_current = 1 ORDER BY NEWID()) a JOIN silver.{t}__hub h ON h.[{k}] = a.[{k}]""")
        r = cur.fetchone(); 칸 = ", ".join(f"{c} {v}" for c, v in zip(CMP[t], r[3:]))
        log(f"{t}: 지금(API) {a:,} · 허브 {b:,} · 색인 {i1}/{i2} · 값 대조 짝 {r[0]:,} 중 다른 줄 {r[2]:,} ({칸})")
        if i1 != i2 or b < a or not r[0] or r[2] > 0.005 * r[0]: bad.append(t)
    if bad: sys.exit("✘ 바꿔 끼우기 전에 볼 것: " + ", ".join(bad))
    log("대조 통과")
elif op in ("swap", "back"):
    H.TABLES = TABLES; H.swap(cur, back=(op == "back"))
