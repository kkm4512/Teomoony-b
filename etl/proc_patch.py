# -*- coding: utf-8 -*-
"""proc_patch - 지금 프로시저 정의(OBJECT_DEFINITION)에서 글자 하나를 바꿔 CREATE OR ALTER 로 다시 건다 (2026-10-27)
  py proc_patch.py gold.usp_match_complex_trade "TOP (20000)" "TOP (4000)"
  ★ 바꿀 글자가 정확히 한 번 있어야 한다(아니면 아무것도 안 한다)."""
import sys, re
from svc_publish import env, ms_conn
name, a, b = sys.argv[1:4]
cur = ms_conn(env()).cursor(); cur.execute("SELECT OBJECT_DEFINITION(OBJECT_ID(%s))", (name,)); d = cur.fetchone()[0]
n = d.count(a)
if n != 1: print(f"'{a}' 가 {n}번 — 안 바꿈"); sys.exit(1)
d = d.replace(a, b)
d = re.sub(r"^\s*CREATE\s+(OR\s+ALTER\s+)?PROCEDURE", "CREATE OR ALTER PROCEDURE", d, count=1, flags=re.I)
cur.execute(d); print(f"{name}: '{a}' → '{b}'")
