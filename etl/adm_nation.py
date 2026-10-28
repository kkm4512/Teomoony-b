# -*- coding: utf-8 -*-
"""행정동 경계 전국 (2026-10-29, 사장님 "남은것도 너가해")
   1) load_adm_boundary.py 2025 nation  — data/adm_boundary_sgis_2025_nation.geojson(3,559동) → silver.adm_boundary(2025 를 지우고 다시)
   2) 276 — 상가 위치 다수결로 행안부 행정동 코드 잇기   3) 284 — 갈림 내역
   4) svc_layers --only adm (--force adm) — 서비스 DB 층
   하나라도 실패하면 거기서 멈춘다."""
import subprocess, sys
PY = sys.executable
for step in ([PY, "load_adm_boundary.py", "2025", "nation"],
             [PY, "ms_q.py", r"..\deploy\sql\276_adm_map.sql"],
             [PY, "ms_q.py", r"..\deploy\sql\284_adm_split.sql"],
             [PY, "svc_layers.py", "--only", "adm", "--force", "adm"]):
    print("▶", " ".join(step[1:]), flush=True)
    r = subprocess.run(step)
    if r.returncode: print("✖ 멈춤", r.returncode, flush=True); sys.exit(r.returncode)
print("✔ 끝", flush=True)
