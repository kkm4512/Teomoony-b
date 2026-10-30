# -*- coding: utf-8 -*-
"""건축인허가 부가 원문(평형 · 층별 · 철거멸실 · 대수선 · 가설 · 주차장) — 건축HUB 대용량 전국 파일 (2026-10-30 사장님 "ㄱㄱ+")
   왜: 기본개요 · 동별개요만 화면에 쓰고 나머지는 받아만 두고 있었다. 공사 중 건물의 평형 · 층 구성 · 계획 주차, 대수선 · 철거 이력을 단지 상세에 잇는다.
   받는 것: 건축인허가 층별개요(0103) · 호별개요(0104) · 대수선(0105) · 철거멸실관리대장(0107) · 가설건축물(0108) · 주차장(0110) · 전유공용면적(0112)
   넣는 곳: hub.t01xx (load_hub.py — 원문 칸 그대로 · 처음월/마지막월 버전) → 파생표 gold.pms_unit_type · pms_floor_use · pms_demolish (386)
   ★ 대수선 · 가설 · 주차장은 원문 표를 바로 읽는다(관리_허가대장_PK 색인이 이미 있다).
   ★ 매달 hub_month.py 가 끝에 부른다. --skip-fetch: 받기 · 넣기 없이 파생표만 다시."""
import subprocess, sys
PY = sys.executable
이름들 = ["층별개요", "호별개요", "대수선", "철거멸실관리대장", "가설건축물", "주차장", "전유공용면적"]
steps = []
if "--skip-fetch" not in sys.argv:
    steps += [[PY, "hub_bulk.py", "--cat", "건축인허가", "--only", *이름들, "--workers", "3"],
              [PY, "load_hub.py", "--all", "--cat", "건축인허가", "--only", *이름들]]
steps += [[PY, "ms_q.py", r"..\deploy\sql\386_pms_extra.sql"]]
for step in steps:
    print("▶", " ".join(step[1:]), flush=True)
    r = subprocess.run(step)
    if r.returncode: print("✖ 멈춤", r.returncode, flush=True); sys.exit(r.returncode)
from svc_publish import env, ms_conn
cur = ms_conn(env()).cursor(); cur.execute("EXEC gold.usp_refresh_pms_extra"); print("pms_extra:", cur.fetchall(), flush=True)
print("✔ 끝", flush=True)
