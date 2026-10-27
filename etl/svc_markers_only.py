# -*- coding: utf-8 -*-
"""svc_markers_only - 지도 마커(+ 동네 단지 수 svc.area_cnt)만 다시 발행 (2026-10-27)
  hourly 가 도는 중이면 기다렸다가 한다(둘이 같은 표를 바꿔 끼우지 않게). --now: 안 기다림(hourly 가 이미 마커를 지나 층을 만드는 중일 때)."""
import os, time
import svc_publish as s
Q = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_queue")
import sys
while "--now" not in sys.argv and any(j.startswith("sp-") and j.endswith(".job") for j in os.listdir(Q)):
    time.sleep(20)
e = s.env(); ms = s.ms_conn(e); pg = s.pg_conn(e)
s.publish_markers(ms, pg)
with pg.cursor() as c:
    c.execute("SELECT kind, count(*), sum(n) FROM svc.area_cnt GROUP BY kind ORDER BY kind")
    for r in c.fetchall(): print("  ", r, flush=True)
