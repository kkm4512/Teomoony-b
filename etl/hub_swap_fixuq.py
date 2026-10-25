# -*- coding: utf-8 -*-
"""hub_swap_fixuq - __hub 표에서 '하나뿐이어야 할 키'(uq_*) 색인이 겹침으로 못 만들어진 것 정리 (2026-10-25)
  ★ 허브 원본에는 우리 칸에 없는 칸(블록 · 로트 · 기타 지번 글자 등)이 있어, 우리 모양으로 줄이면 **똑같은 줄**이 여럿 나온다.
    → 우리 칸 전부(sk · row_hash 빼고)가 똑같은 줄만 하나 남긴다(보이는 것은 하나도 안 잃는다).
  ★ 그래도 키가 겹치면(우리 칸 값이 실제로 다른 줄) 지우지 않는다 — 같은 이름의 '하나뿐 아님' 색인으로 만들고 몇 개인지 적는다.
  py hub_swap_fixuq.py [표 …]"""
import sys, time
from svc_publish import env, ms_conn
def log(*a): print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)
ms = ms_conn(env()); cur = ms.cursor()
for t in sys.argv[1:]:
    cur.execute(f"""SELECT i.name, i.filter_definition,
          (SELECT STRING_AGG('[' + c.name + ']', ',') WITHIN GROUP (ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0)
          FROM sys.indexes i WHERE i.object_id = OBJECT_ID('silver.{t}') AND i.is_unique = 1 AND i.is_primary_key = 0
           AND NOT EXISTS (SELECT 1 FROM sys.indexes j WHERE j.object_id = OBJECT_ID('silver.{t}__hub') AND j.name = i.name)""")
    for nm, flt, kc in cur.fetchall():
        cur.execute(f"SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('silver.{t}__hub') AND c.is_identity = 0 AND c.name NOT IN ('row_hash') ORDER BY c.column_id")
        cols = [r[0] for r in cur.fetchall()]
        cur.execute(f"SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('silver.{t}__hub') AND c.is_identity = 1"); sk = cur.fetchone()[0]
        part = ", ".join(f"[{c}]" for c in cols)
        cur.execute(f"""WITH d AS (SELECT rn = ROW_NUMBER() OVER (PARTITION BY {part} ORDER BY [{sk}]) FROM silver.{t}__hub
                          WHERE EXISTS (SELECT 1 FROM (SELECT {kc} FROM silver.{t}__hub GROUP BY {kc} HAVING COUNT(*) > 1) k WHERE {' AND '.join(f"(k.{c} = silver.{t}__hub.{c} OR (k.{c} IS NULL AND silver.{t}__hub.{c} IS NULL))" for c in kc.split(','))}))
                        DELETE FROM d WHERE rn > 1""")
        log(f"{t}.{nm}: 우리 칸이 똑같은 줄 {cur.rowcount:,} 지움")
        cur.execute(f"SELECT COUNT(*), ISNULL(SUM(n), 0) FROM (SELECT n = COUNT(*) FROM silver.{t}__hub GROUP BY {kc} HAVING COUNT(*) > 1) d"); k, n = cur.fetchone()
        uq = k == 0
        cur.execute(f"CREATE {'UNIQUE ' if uq else ''}NONCLUSTERED INDEX [{nm}] ON silver.{t}__hub ({kc})" + (f" WHERE {flt}" if flt else "") + " WITH (DATA_COMPRESSION = PAGE, MAXDOP = 4)")
        log(f"{t}.{nm}: " + ("하나뿐 색인 만듦" if uq else f"값이 실제로 다른 겹침 {k:,}키 {n:,}줄 — 지우지 않고 '하나뿐 아님' 색인으로 만듦"))
