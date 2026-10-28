#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_dirty_sql - 적재DB 질의가 낸 단지 번호를 서비스DB '상세 다시' 표(svc.detail_dirty)에 적는다 (2026-10-28)
  py svc_dirty_sql.py "SELECT complex_id FROM gold.kapt_pnu_link" "K-apt 넷째 길 377"
  ★ 값은 안 고친다 — 다음 발행이 지금 서버 응답으로 다시 담는다. 실거래 바뀜 표시('마커 실거래 칸 바뀜')는 덮지 않는다."""
import sys
from svc_publish import env, ms_conn, pg_conn
q, why = sys.argv[1], sys.argv[2]
e = env(); cur = ms_conn(e).cursor(); cur.execute(q); ids = sorted({r[0] for r in cur.fetchall() if r[0]})
pg = pg_conn(e)
with pg.cursor() as c:
    c.execute("CREATE TABLE IF NOT EXISTS svc.detail_dirty (complex_id int PRIMARY KEY, why text NOT NULL, at timestamptz NOT NULL DEFAULT now())")
    c.execute("INSERT INTO svc.detail_dirty (complex_id, why) SELECT x, %s FROM unnest(%s::int[]) x ON CONFLICT (complex_id) DO NOTHING", (why, ids or [0])); n = c.rowcount
    c.execute("DELETE FROM svc.resp_cache WHERE complex_id = ANY(%s)", (ids or [0],))
pg.commit(); print(f"{why}: 단지 {len(ids):,} · 상세 다시 표에 새로 {n:,}")
