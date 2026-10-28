#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_merge_sync - 적재DB 에서 단지를 묶은 뒤(287/331/374) 서비스DB 를 맞춘다 (2026-10-28)
  py svc_merge_sync.py 373      근거가 '373' 으로 시작하는 묶음만
  ① 흡수된 조각의 미리 만든 응답(svc.complex_json · svc.resp_cache) 지움 — 파생 캐시다. 그 주소는 적재DB 경로(301 → 남는 단지)가 답한다.
  ② 남는 단지를 '상세 다시' 표(svc.detail_dirty)에 적음 — 동 수 · 세대 · 실거래가 바뀌었다."""
import sys
from svc_publish import env, ms_conn, pg_conn
key = sys.argv[1] if len(sys.argv) > 1 else "373"
e = env(); cur = ms_conn(e).cursor()
cur.execute("SELECT old_id, new_id FROM ops.complex_merged WHERE 근거 LIKE %s", (key + "%",))
rows = cur.fetchall(); olds = [r[0] for r in rows]; news = sorted({r[1] for r in rows})
pg = pg_conn(e)
with pg.cursor() as c:
    c.execute("DELETE FROM svc.complex_json WHERE complex_id = ANY(%s)", (olds or [0],)); a = c.rowcount
    c.execute("DELETE FROM svc.resp_cache WHERE complex_id = ANY(%s)", (olds + news or [0],)); b = c.rowcount
    c.execute("CREATE TABLE IF NOT EXISTS svc.detail_dirty (complex_id int PRIMARY KEY, why text NOT NULL, at timestamptz NOT NULL DEFAULT now())")
    c.execute("""INSERT INTO svc.detail_dirty (complex_id, why) SELECT x, '마커 실거래 칸 바뀜' FROM unnest(%s::int[]) x
                 ON CONFLICT (complex_id) DO UPDATE SET why = EXCLUDED.why, at = now()""", (news or [0],)); d = c.rowcount
pg.commit()
print(f"묶음 {key}: 흡수 {len(olds):,} · 남는 단지 {len(news):,} — 흡수 조각 응답 지움 {a:,} · 지나며 담긴 응답 지움 {b:,} · 상세 다시 표 {d:,}(먼저 처리)")
