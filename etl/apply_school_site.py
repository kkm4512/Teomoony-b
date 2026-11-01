# -*- coding: utf-8 -*-
"""apply_school_site - 401(학교 · 유치원이 든 단지) 적용 · 매일 다시(cl-school-site-par) — 2026-11-01
  python apply_school_site.py            표 · 프로시저 · 일정(401) 적용 + 계산 + 자동완성 학교 · 유치원 층 다시 담기
  python apply_school_site.py --run      계산 + 층 다시 담기만(매일)"""
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from svc_publish import env, ms_conn
SQL = os.path.join(HERE, "..", "deploy", "sql")
cur = ms_conn(env()).cursor()
파일 = "401_school_site_run.sql" if "--run" in sys.argv else "401_complex_school_site.sql"
for b in re.split(r"^\s*GO\s*$", open(os.path.join(SQL, 파일), encoding="utf-8").read(), flags=re.M | re.I):
    if not b.strip(): continue
    cur.execute(b)
    while True:
        if cur.description:
            for r in cur.fetchall(): print("   ", r, flush=True)
        if not cur.nextset(): break
r = subprocess.run([sys.executable, os.path.join(HERE, "svc_layers.py"), "--only", "sg_school,sg_kinder", "--force", "sg_school,sg_kinder"])
sys.exit(r.returncode)
