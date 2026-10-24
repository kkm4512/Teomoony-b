#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_sql - 서비스DB(PostgreSQL)에 .sql 파일을 실행한다 (2026-10-24)
  py svc_sql.py ..\\deploy\\svc\\pg\\001_schema.sql
★ 접속: 127.0.0.1:15432 · teomoony · .env SVC_DB_PASSWORD (화면 · 로그에 안 찍는다)"""
import os, sys
import psycopg
HERE = os.path.dirname(os.path.abspath(__file__))

def env():
    d = {}
    for ln in open(os.path.join(HERE, "..", ".env"), encoding="utf-8"):
        ln = ln.strip()
        if ln and not ln.startswith("#") and "=" in ln:
            k, v = ln.split("=", 1); d[k.strip()] = v.strip().strip('"').strip("'")
    return d

def connect():
    e = env()
    return psycopg.connect(host="127.0.0.1", port=15432, dbname="teomoony", user="teomoony", password=e["SVC_DB_PASSWORD"], autocommit=True)

if __name__ == "__main__":
    p = sys.argv[1]
    sql = open(p, encoding="utf-8").read()
    with connect() as c:
        c.execute(sql)
        print("ok", os.path.basename(p))
        for q in sys.argv[2:]:
            for r in c.execute(q).fetchall(): print(r)
