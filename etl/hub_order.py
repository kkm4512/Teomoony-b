#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""hub_order - 허브 적재 순서 바꾸기 (2026-10-25 사장님 "파일에 있는 걸 적재DB 로 옮기고 그걸로 작업")
  건축물대장(03xx)을 먼저 넣고, 그다음 나머지 전부(--all 은 이미 넣은 달은 건너뛴다)."""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
# ★ 10-25: 전유공용면적(0306, 달마다 zip 3.3GB) · 공동주택가격(0308, 5.9GB — 풀면 수십 GB · 표로 100GB 넘을 수 있음)은 디스크를 사장님과 정한 뒤에.
#   그래서 여기서는 대장 뼈대만 먼저 넣고 끝낸다(나머지 --all 도 0306 · 0308 · 0409 를 품고 있어 자동으로 잇지 않는다).
for args in (["--all", "--cat", "건축물대장", "--only", "기본개요", "총괄표제부", "표제부", "층별개요", "부속지번", "전유부", "지역지구구역"],):
    print(f"$ load_hub.py {' '.join(args)}", flush=True)
    r = subprocess.run([sys.executable, os.path.join(HERE, "load_hub.py")] + args, cwd=HERE)
    if r.returncode != 0:
        print(f"!! load_hub {' '.join(args)} 종료코드 {r.returncode}", flush=True); sys.exit(r.returncode)
print("허브 순서 적재 끝", flush=True)
