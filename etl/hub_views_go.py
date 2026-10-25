# -*- coding: utf-8 -*-
"""hub_views_go - 353_hub_views.sql 적용 → hub_compare 시군구 셋 (2026-10-25)
  py hub_views_go.py [시군구 …]   (기본 11305 11680 41135)"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
py = sys.executable
def run(*a):
    print("\n$ " + " ".join(a), flush=True)
    return subprocess.call([py, *a], cwd=HERE)
if run("ms_q.py", os.path.join("..", "deploy", "sql", "353_hub_views.sql")) != 0:
    sys.exit("뷰 적용 실패")
for s in (sys.argv[1:] or ["11305", "11680", "41135"]):
    run("hub_compare.py", s)
