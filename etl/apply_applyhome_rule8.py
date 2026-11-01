# -*- coding: utf-8 -*-
"""apply_applyhome_rule8 - 청약 공고 잇기 여덟째 · 아홉째 길(402)을 지금 프로시저(gold.usp_refresh_applyhome_link)에 끼워 넣고 다시 돈다 (2026-11-01)
  ★ 지금 정의(OBJECT_DEFINITION)를 읽어 'COMMIT; ... SELECT 공고 =' 바로 앞에 402 블록을 넣는다(이미 있으면 안 넣음) → CREATE OR ALTER → EXEC.
  ★ 그다음: 자동완성 공고 · 정비 층 다시 담기 · 새로 이어진 단지 상세 다시 담기."""
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from svc_publish import env, ms_conn
blk = open(os.path.join(HERE, "..", "deploy", "sql", "402_applyhome_rule8.sql"), encoding="utf-8").read()
conn = ms_conn(env()); cur = conn.cursor()
cur.execute("SELECT OBJECT_DEFINITION(OBJECT_ID('gold.usp_refresh_applyhome_link'))"); d = cur.fetchone()[0]
cur.execute("SELECT house_manage_no + '|' + pblanc_no FROM gold.applyhome_link"); 전 = {r[0] for r in cur.fetchall()}
if "여덟째 (402" in d and "--replace" in sys.argv:   # 블록을 고쳐 다시 끼운다(402 시작 ~ 아홉째 끝)
    i = d.index("        /* 여덟째 (402"); j = d.index("HAVING COUNT(DISTINCT n.kapt_code) = 1;", i) + len("HAVING COUNT(DISTINCT n.kapt_code) = 1;")
    d = d[:i] + blk.strip("\n") + d[j:]
    d = re.sub(r"^\s*CREATE\s+(OR\s+ALTER\s+)?PROCEDURE", "CREATE OR ALTER PROCEDURE", d, count=1, flags=re.I)
    cur.execute(d); print("프로시저의 402 블록 바꿈", flush=True)
elif "여덟째 (402" not in d:
    m = re.search(r"\n(\s*)COMMIT;\s*\n\s*SELECT 공고 = \(SELECT COUNT\(\*\) FROM silver\.applyhome_pblanc\)", d)
    if not m or len(re.findall(r"SELECT 공고 = \(SELECT COUNT\(\*\) FROM silver\.applyhome_pblanc\)", d)) != 1: sys.exit("끼울 자리를 못 찾음 — 안 바꿈")
    d = d[:m.start()] + "\n" + blk.rstrip() + d[m.start():]
    d = re.sub(r"^\s*CREATE\s+(OR\s+ALTER\s+)?PROCEDURE", "CREATE OR ALTER PROCEDURE", d, count=1, flags=re.I)
    cur.execute(d); print("프로시저에 402 블록 넣음", flush=True)
else:
    print("402 블록 이미 있음", flush=True)
cur.execute("EXEC gold.usp_refresh_applyhome_link")
while True:
    if cur.description:
        for r in cur.fetchall(): print("  ", r, flush=True)
    if not cur.nextset(): break
cur.execute("""SELECT l.house_manage_no + '|' + l.pblanc_no, l.complex_id, l.kapt_code, p.house_nm, l.근거 FROM gold.applyhome_link l
               JOIN silver.applyhome_pblanc p ON p.house_manage_no = l.house_manage_no AND p.pblanc_no = l.pblanc_no""")
후 = cur.fetchall()
새 = [r for r in 후 if r[0] not in 전]
print(f"새로 이어진 공고 {len(새)}", flush=True)
for r in 새: print("  ", r[3], "→", r[1] or ('K-apt ' + str(r[2])), "·", r[4][:30], flush=True)
ids = {r[1] for r in 새 if r[1]}
for x in sys.argv:   # --also 1,2,3 : 전에 잘못 붙었다 풀린 단지도 상세를 다시 담는다
    if x.startswith("--also="): ids |= {int(v) for v in x[7:].split(",") if v.strip().isdigit()}
ids = sorted(ids)
subprocess.run([sys.executable, os.path.join(HERE, "svc_layers.py"), "--only", "sg_applyhome,sg_redev", "--force", "sg_applyhome,sg_redev"])
if ids:
    subprocess.run([sys.executable, os.path.join(HERE, "svc_publish.py"), "--mode", "ids", "--kinds", "detail", "--ids", *map(str, ids)])
