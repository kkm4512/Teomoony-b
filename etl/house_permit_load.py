# -*- coding: utf-8 -*-
"""주택인허가(주택법 사업계획승인) — 건축HUB 대용량 전국 파일 (2026-10-30 사장님 "ㄱㄱ")
   왜: 30세대+ 아파트는 건축허가가 아니라 **주택건설사업계획승인**을 받는다 — 우리 건축인허가 표에는 안 들어온다.
       공고(청약홈) 전 단계의 아파트(예: 부산 동구 초량동 659 호반써밋초량 251세대, 분양 2026.11 예정)를 공식 자료로 알 수 있는 길.
   받는 것: 주택인허가 기본개요(0201) · 동별개요(0202) · 대지위치(0215) — 목록에 있는 달 전부(최근 3개월)
   넣는 곳: hub.t0201 · hub.t0202 · hub.t0215 (load_hub.py — 원문 칸 그대로 · 처음월/마지막월 버전) → gold.house_plan(384)
   ★ 이미 넣은 달은 건너뛴다(load_hub) — 매달 hub_month.py 가 끝에 부른다."""
import subprocess, sys
PY = sys.executable
# 10-30 사장님 "123 ㄱㄱ"(승인 단지 상세): 행위개요(총사업비 · 단지명) · 관리공동형별개요(사업주체 · 전용면적별 세대) · 호별개요(평형) · 주차장 · 부대시설 · 복리분양시설
이름들 = ["기본개요", "동별개요", "대지위치", "행위개요", "관리공동형별개요", "호별개요", "주차장", "부대시설", "복리분양시설"]
for step in ([PY, "hub_bulk.py", "--cat", "주택인허가", "--only", *이름들, "--workers", "3"],
             [PY, "load_hub.py", "--all", "--cat", "주택인허가", "--only", *이름들]):
    print("▶", " ".join(step[1:]), flush=True)
    r = subprocess.run(step)
    if r.returncode: print("✖ 멈춤", r.returncode, flush=True); sys.exit(r.returncode)
# 상세용 색인(385 — 없을 때만 만든다)
subprocess.run([PY, "ms_q.py", r"..\deploy\sql\385_hub_house_idx.sql"])
# 지도 '승인' 핀 표(gold.house_plan, deploy/sql/384) 다시 — 파생표
from svc_publish import env, ms_conn
cur = ms_conn(env()).cursor(); cur.execute("EXEC gold.usp_refresh_house_plan"); print("house_plan:", cur.fetchall(), flush=True)
print("✔ 끝", flush=True)
