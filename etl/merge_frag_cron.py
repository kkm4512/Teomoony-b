#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""merge_frag_cron - 대장 조각 묶기(정책 2-1 · 373/374)를 수집 일정에서 돌린다 (2026-10-28 사장님 "스케줄 로직에 포함돼야 해")
  py merge_frag_cron.py       (수집 일정 '단지 조각 묶기' · 건축물대장 월 갱신 다음 날)
  ① gold.usp_plan_merge_frag — 계획 다시(대장 칸만) ② 새로 묶을 것이 없으면 종료코드 3(건너뜀)
  ③ 374 적용(287 · 331 과 같은 방법 — 지우지 않음 · 기록) ④ 서비스DB 맞춤(이번에 묶은 것만) ⑤ AI 요약표(z-askattr-par) 걸기"""
import os, subprocess, sys, time
from svc_publish import env, ms_conn
HERE = os.path.dirname(os.path.abspath(__file__))
def log(*a): print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)
cur = ms_conn(env()).cursor()
cur.execute("SELECT CONVERT(VARCHAR(19), SYSDATETIME(), 120)"); since = cur.fetchone()[0]   # 적재DB 시각(UTC) — ops.complex_merged.at 과 같은 시계
cur.execute("EXEC gold.usp_plan_merge_frag"); r = cur.fetchone()
log("계획: 덩어리 {:,} · 조각 {:,} · 흡수될 조각 {:,} · 묶음 {:,} · 보류 {:,}".format(*r[:5]))
cur.execute("""SELECT COUNT(*) FROM ops.complex_merge_plan_frag p
                 JOIN gold.complex c ON c.complex_id = p.complex_id AND c.merged_into IS NULL AND c.is_active = 1
                 JOIN gold.complex s ON s.complex_id = p.남을코드 AND s.merged_into IS NULL AND s.is_active = 1
                WHERE p.판정 = N'묶음' AND p.complex_id <> p.남을코드""")
n = cur.fetchone()[0]
if n == 0: log("새로 묶을 조각 없음"); sys.exit(3)
log(f"새로 묶을 조각 {n:,} — 374 적용")
r = subprocess.run([sys.executable, os.path.join(HERE, "ms_q.py"), os.path.join(HERE, "..", "deploy", "sql", "374_merge_frag_apply.sql")], cwd=HERE)
if r.returncode != 0: sys.exit(f"374 적용 실패(종료코드 {r.returncode})")
r = subprocess.run([sys.executable, os.path.join(HERE, "svc_merge_sync.py"), "373", since], cwd=HERE)
if r.returncode != 0: sys.exit(f"서비스DB 맞추기 실패(종료코드 {r.returncode}) — 적재DB 는 묶였음 · svc_merge_sync.py 373 {since} 다시")
open(os.path.join(HERE, "_queue", "z-askattr-par.job"), "w", encoding="utf-8").write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} merge_frag_cron\n")
log("끝 — AI 요약표(z-askattr-par) 걸었음")
