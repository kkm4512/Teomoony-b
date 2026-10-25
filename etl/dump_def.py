# -*- coding: utf-8 -*-
"""dump_def - 저장 프로시저·뷰의 지금 정의를 파일로 (py dump_def.py gold.usp_build_complexes …) → ..\\logs\\def_<이름>.sql"""
import os, sys
from svc_publish import env, ms_conn
cur = ms_conn(env()).cursor()
for o in sys.argv[1:]:
    cur.execute("SELECT OBJECT_DEFINITION(OBJECT_ID(%s))", (o,)); d = cur.fetchone()[0]
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "logs", f"def_{o}.sql")
    open(p, "w", encoding="utf-8").write(d or ""); print(o, len(d or ""))
