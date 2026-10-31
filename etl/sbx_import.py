# -*- coding: utf-8 -*-
"""sbx_import - export_sbx.py 가 꺼낸 TSV 를 **클라우드 시험 공간(sandbox) DB** 에 넣는다 (2026-10-31)
  python sbx_import.py <폴더> [이름 ...]      이름을 안 주면 폴더의 .tsv 전부
★ 시험 공간 전용. 넣기 전에 같은 이름의 표를 지우고 새로 만든다 — 실제 DB(PC)에 쓰면 안 된다.
  그래서 그 DB 에 표지 표 sbx.marker 가 있을 때만 돈다(시험 공간을 만들 때 한 번 만든다 · PC DB 에는 없다).
★ <이름>.cols.json 이 있으면 원래 칸 형식 그대로, 없으면(use.* 집계) 모두 NVARCHAR(400) · n/hhld 는 BIGINT.
★ TSV 규칙(export_sbx.py): NULL = \\N · \\\\ \\t \\n \\r 은 되돌린다.
"""
import json, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from svc_publish import env
import pymssql


def 풀기(v):
    if v == "\\N": return None
    if "\\" not in v: return v
    out, i = [], 0
    while i < len(v):
        c = v[i]
        if c == "\\" and i + 1 < len(v):
            n = v[i + 1]; out.append({"\\": "\\", "t": "\t", "n": "\n", "r": "\r"}.get(n, "\\" + n)); i += 2
        else:
            out.append(c); i += 1
    return "".join(out)


def 형(c):
    t = c["type"]
    if t in ("varchar", "char", "nvarchar", "nchar", "varbinary", "binary"):
        ml = c["max_length"]
        if ml == -1: return f"{t}(max)"
        if t in ("nvarchar", "nchar"): ml //= 2
        return f"{t}({ml})"
    if t in ("decimal", "numeric"): return f"{t}({c['precision']},{c['scale']})"
    if t in ("datetime2", "time", "datetimeoffset"): return f"{t}({c['scale']})"
    if t in ("geography", "geometry", "hierarchyid", "sql_variant", "xml"): return "nvarchar(max)"
    return t


def 글(v, t):
    if v is None: return "NULL"
    if t in ("varbinary", "binary") and v.startswith("0x"): return v
    if t in ("int", "bigint", "smallint", "tinyint", "bit", "float", "real", "decimal", "numeric", "money"): return v
    return "N'" + v.replace("'", "''") + "'"


def main():
    폴더 = sys.argv[1]; 이름들 = sys.argv[2:] or sorted(f[:-4] for f in os.listdir(폴더) if f.endswith(".tsv"))
    e = env()
    if e.get("DB_HOST") not in ("127.0.0.1", "localhost"): sys.exit("시험 공간 DB 가 아닙니다")
    conn = pymssql.connect(server=e["DB_HOST"], port=int(e["DB_PORT"]), user=e["DB_USER"], password=e["DB_PASSWORD"],
                           database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=True)
    cur = conn.cursor()
    cur.execute("SELECT CASE WHEN OBJECT_ID('sbx.marker') IS NULL THEN 0 ELSE 1 END")
    if cur.fetchone()[0] != 1: sys.exit("sbx.marker 가 없습니다 — 시험 공간 DB 가 아니면 돌지 않습니다")
    for 이름 in 이름들:
        t0 = time.time()
        p = os.path.join(폴더, 이름 + ".tsv"); pj = os.path.join(폴더, 이름 + ".cols.json")
        f = open(p, encoding="utf-8", newline="\n"); 머리 = f.readline().rstrip("\n").split("\t")
        if os.path.exists(pj):
            meta = json.load(open(pj, encoding="utf-8")); 표 = meta["table"]; cs = {c["name"]: c for c in meta["columns"]}
            칸들 = [(h, 형(cs[h]), cs[h]["type"], cs[h]["nullable"]) for h in 머리]; pk = meta.get("pk") or []
        else:
            표 = "sbx." + 이름.replace(".", "_"); pk = []
            칸들 = [(h, "bigint" if h in ("n", "hhld") else "nvarchar(400)", "bigint" if h in ("n", "hhld") else "nvarchar", True) for h in 머리]
        sch, tb = 표.split(".")
        cur.execute(f"IF SCHEMA_ID('{sch}') IS NULL EXEC('CREATE SCHEMA [{sch}]')")
        cur.execute(f"IF OBJECT_ID('{표}') IS NOT NULL DROP TABLE {표}")
        정의 = ",\n".join(f"[{h}] {ty} {'NULL' if nl else 'NOT NULL'}" for h, ty, _, nl in 칸들)
        if pk: 정의 += f",\nCONSTRAINT [pk_{sch}_{tb}] PRIMARY KEY ({', '.join('[' + k + ']' for k in pk)})"
        cur.execute(f"CREATE TABLE {표} (\n{정의}\n)")
        목록 = ", ".join(f"[{h}]" for h, *_ in 칸들); n = 0; 묶음 = []
        def 넣기():
            cur.execute(f"INSERT {표} ({목록}) VALUES " + ",\n".join(묶음)); 묶음.clear()
        for ln in f:
            vs = ln.rstrip("\n").split("\t")
            묶음.append("(" + ",".join(글(풀기(v), 칸들[i][2]) for i, v in enumerate(vs)) + ")"); n += 1
            if len(묶음) >= 900: 넣기()
        if 묶음: 넣기()
        print(f"  {표}: {n:,}줄 · {time.time()-t0:.0f}초", flush=True)


if __name__ == "__main__":
    main()
