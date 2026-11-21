#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dqm_rules - DQM ③ 규칙 실행기 (2026-11-19 사장님 "추천대로 ㄱ")

  규칙은 etl/dqm_rules.yaml 에만 있다(코드에 박지 않는다). 이 프로그램은 표를 읽어 silver.rtms_trade 의 줄마다
  어떤 규칙에 걸렸는지 적고(ops.dqm_rule_hit), 규칙별 · 종류별로 세고(ops.dqm_rule_stat · ops.dqm_grade_stat), 규칙마다 예시를 남긴다.
  ★ run 은 원본(silver.rtms_trade)을 읽기만 한다.
  ★ apply(2026-11-21 · 423): 가장 최근 run 에서 격리 · 버림 규칙에 걸린 줄을 ops.dqm_quarantine 로 옮기고 silver 에서 뺀다(지우지 않음).
    한 번에 --max(기본 2,000)줄 넘으면 멈춘다 — 규칙이 잘못 고쳐져 대량으로 걸리는 것을 막는다. 풀기는 ops.usp_dqm_release.

  python dqm_rules.py run [--rules dqm_rules.yaml]   규칙 실행 · 측정(약 수 분)
  python dqm_rules.py show <trade_sk>               그 줄이 걸린 규칙 · 등급(가장 최근 run)
  등급: 격리(버림 · 격리 규칙) > C(등급C · 보완 규칙) > B(표시 규칙) > A(안 걸림)
"""
import argparse, collections, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "data", "pylib312"))   # pyyaml (작업 큐 컨테이너용)
sys.path.insert(0, HERE)
import yaml                                                         # noqa: E402
from svc_publish import env, ms_conn                                # noqa: E402

등급순 = {"버림": "격리", "격리": "격리", "등급C": "C", "보완": "C", "표시": "B"}
DDL = """
IF OBJECT_ID('ops.dqm_rule_run') IS NULL CREATE TABLE ops.dqm_rule_run (run_id INT IDENTITY PRIMARY KEY, 시작 DATETIME2 DEFAULT SYSDATETIME(), 끝 DATETIME2 NULL,
    규칙버전 INT, 규칙수 INT, 대상줄 BIGINT NULL, 메모 NVARCHAR(400) NULL);
IF OBJECT_ID('ops.dqm_rule_stat') IS NULL CREATE TABLE ops.dqm_rule_stat (run_id INT, rule_id VARCHAR(10), 이름 NVARCHAR(200), 처리 NVARCHAR(20), 종류 NVARCHAR(400),
    대상줄 BIGINT, 걸린줄 BIGINT, 근거 BIGINT NULL, 초 FLOAT, 예시 NVARCHAR(MAX), 종류별 NVARCHAR(MAX));
IF OBJECT_ID('ops.dqm_rule_hit') IS NULL CREATE TABLE ops.dqm_rule_hit (run_id INT NOT NULL, trade_sk BIGINT NOT NULL, rule_id VARCHAR(10) NOT NULL,
    CONSTRAINT pk_dqm_rule_hit PRIMARY KEY (run_id, trade_sk, rule_id));
IF OBJECT_ID('ops.dqm_grade_stat') IS NULL CREATE TABLE ops.dqm_grade_stat (run_id INT, trade_kind VARCHAR(20), 줄 BIGINT, A BIGINT, B BIGINT, C BIGINT, 격리 BIGINT);
"""


def 표읽기(p):
    d = yaml.safe_load(open(p, encoding="utf-8"))
    묶음 = d.get("종류묶음", {})
    for r in d["규칙"]:
        k = r.get("종류")
        r["_종류"] = 묶음[k] if isinstance(k, str) else (k or [])
        assert r["처리"] in 등급순, f"{r['id']}: 모르는 처리 {r['처리']}"
    return d


def 종류조건(r):
    return ("t.trade_kind IN (" + ", ".join(f"'{k}'" for k in r["_종류"]) + ") AND ") if r["_종류"] else ""


def cmd_run(a):
    d = 표읽기(os.path.join(HERE, a.rules))
    cur = ms_conn(env()).cursor()
    cur.execute(DDL)
    cur.execute("INSERT ops.dqm_rule_run (규칙버전, 규칙수) OUTPUT inserted.run_id VALUES (%s, %s)", (d["버전"], len(d["규칙"])))
    run = cur.fetchone()[0]; t0 = time.time()
    cur.execute(f"DELETE ops.dqm_rule_hit WHERE run_id IN (SELECT run_id FROM ops.dqm_rule_run WHERE 끝 IS NULL AND run_id < {run})")   # 도중에 죽은 run 의 줄
    print(f"[{time.strftime('%H:%M:%S')}] run {run} · 규칙 {len(d['규칙'])}개(버전 {d['버전']})", flush=True)
    cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT trade_kind, COUNT_BIG(*) FROM silver.rtms_trade GROUP BY trade_kind")
    종류줄 = {k: n for k, n in cur.fetchall()}; 전체 = sum(종류줄.values())
    for s in d.get("준비", []):
        t = time.time(); cur.execute(s); print(f"  준비 {time.time()-t:.0f}초", flush=True)
    for r in d["규칙"]:
        t = time.time(); w = f"{종류조건(r)}({r['sql']})"
        cur.execute(f"INSERT ops.dqm_rule_hit (run_id, trade_sk, rule_id) SELECT {run}, t.trade_sk, '{r['id']}' FROM silver.rtms_trade t WITH (NOLOCK) WHERE {w}")
        걸림 = cur.rowcount
        # 종류별 · 예시(최근 거래부터 8줄)
        cur.execute(f"""SELECT t.trade_kind, COUNT_BIG(*) FROM ops.dqm_rule_hit h JOIN silver.rtms_trade t WITH (NOLOCK) ON t.trade_sk = h.trade_sk
                         WHERE h.run_id = {run} AND h.rule_id = '{r['id']}' GROUP BY t.trade_kind""")
        종류별 = {k: n for k, n in cur.fetchall()}
        cur.execute(f"""SELECT TOP 8 t.trade_sk, t.trade_kind, t.sgg_cd, t.umd_nm, t.bld_nm, t.deal_ymd, t.deal_amount, t.deposit, t.monthly_rent,
                               t.exclu_use_ar, t.floor_no, t.build_year, t.dealing_gbn, t.cdeal_type, t.match_complex_id
                          FROM ops.dqm_rule_hit h JOIN silver.rtms_trade t WITH (NOLOCK) ON t.trade_sk = h.trade_sk
                         WHERE h.run_id = {run} AND h.rule_id = '{r['id']}' ORDER BY t.deal_ymd DESC, t.trade_sk DESC""")
        칸 = [c[0] for c in cur.description]
        예 = [{k: (float(v) if hasattr(v, "is_finite") else v) for k, v in zip(칸, x)} for x in cur.fetchall()]
        대상 = sum(종류줄.get(k, 0) for k in r["_종류"]) if r["_종류"] else 전체
        cur.execute("INSERT ops.dqm_rule_stat VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                    (run, r["id"], r["이름"], r["처리"], ",".join(r["_종류"]) or None, 대상, 걸림, r.get("근거"), round(time.time() - t, 1),
                     json.dumps(예, ensure_ascii=False, default=str), json.dumps(종류별, ensure_ascii=False)))
        print(f"  {r['id']:5s} {r['처리']:4s} 걸림 {걸림:>10,} / {대상:>11,}" + (f"  (근거 {r['근거']:,})" if isinstance(r.get('근거'), int) else "")
              + f"  {r['이름']}  {time.time()-t:.0f}초", flush=True)
    # 등급: 줄마다 가장 무거운 처리
    처리값 = ", ".join(f"('{r['id']}', '{등급순[r['처리']]}')" for r in d["규칙"])
    cur.execute(f"""
        IF OBJECT_ID('tempdb..#g') IS NOT NULL DROP TABLE #g;
        SELECT h.trade_sk, 등급 = CASE MAX(CASE p.g WHEN '격리' THEN 3 WHEN 'C' THEN 2 WHEN 'B' THEN 1 END) WHEN 3 THEN '격리' WHEN 2 THEN 'C' ELSE 'B' END
          INTO #g FROM ops.dqm_rule_hit h JOIN (VALUES {처리값}) p (rule_id, g) ON p.rule_id = h.rule_id WHERE h.run_id = {run} GROUP BY h.trade_sk;
        INSERT ops.dqm_grade_stat (run_id, trade_kind, 줄, A, B, C, 격리)
        SELECT {run}, k.trade_kind, k.n, k.n - ISNULL(x.B, 0) - ISNULL(x.C, 0) - ISNULL(x.격리, 0), ISNULL(x.B, 0), ISNULL(x.C, 0), ISNULL(x.격리, 0)
          FROM (SELECT trade_kind, n = COUNT_BIG(*) FROM silver.rtms_trade WITH (NOLOCK) GROUP BY trade_kind) k
          LEFT JOIN (SELECT t.trade_kind, B = SUM(CASE WHEN g.등급 = 'B' THEN 1 ELSE 0 END), C = SUM(CASE WHEN g.등급 = 'C' THEN 1 ELSE 0 END),
                            격리 = SUM(CASE WHEN g.등급 = '격리' THEN 1 ELSE 0 END)
                       FROM #g g JOIN silver.rtms_trade t WITH (NOLOCK) ON t.trade_sk = g.trade_sk GROUP BY t.trade_kind) x ON x.trade_kind = k.trade_kind;""")
    cur.execute(f"SELECT SUM(줄), SUM(A), SUM(B), SUM(C), SUM(격리) FROM ops.dqm_grade_stat WHERE run_id = {run}")
    n, A, B, C, Q = cur.fetchone()
    메모 = f"A {A:,} · B {B:,} · C {C:,} · 격리 {Q:,}"
    cur.execute("UPDATE ops.dqm_rule_run SET 끝 = SYSDATETIME(), 대상줄 = %s, 메모 = %s WHERE run_id = %s", (n, 메모, run))
    # 줄별 기록은 최근 2번만 남긴다(통계 · 예시는 다 남김)
    cur.execute(f"DELETE ops.dqm_rule_hit WHERE run_id < (SELECT MIN(run_id) FROM (SELECT TOP 2 run_id FROM ops.dqm_rule_run WHERE 끝 IS NOT NULL ORDER BY run_id DESC) x)")
    print(f"[{time.strftime('%H:%M:%S')}] 끝 run {run} · {n:,}줄 · {메모} · {(time.time()-t0)/60:.1f}분", flush=True)


def cmd_apply(a):
    import subprocess
    cur = ms_conn(env()).cursor()
    cur.execute("SELECT MAX(run_id) FROM ops.dqm_rule_run WHERE 끝 IS NOT NULL"); run = cur.fetchone()[0]
    cur.execute("SELECT rule_id FROM ops.dqm_rule_stat WHERE run_id = %s AND 처리 IN (N'격리', N'버림')", (run,))
    규칙 = [r[0] for r in cur.fetchall()]
    if not 규칙: print(f"run {run}: 격리 규칙 없음"); return
    목록 = ", ".join(f"'{x}'" for x in 규칙)
    # 후보 = 이번 run 에 격리 규칙으로 걸렸고 · 아직 silver 에 있고 · 격리 표에 한 번도 안 들어간 줄(풀린 줄은 사람이 진짜라고 본 것 — 다시 안 넣는다)
    cur.execute(f"""
        IF OBJECT_ID('tempdb..#q') IS NOT NULL DROP TABLE #q;
        SELECT h.trade_sk, rule_ids = STRING_AGG(h.rule_id, ',') WITHIN GROUP (ORDER BY h.rule_id)
          INTO #q FROM ops.dqm_rule_hit h
         WHERE h.run_id = {run} AND h.rule_id IN ({목록})
           AND EXISTS (SELECT 1 FROM silver.rtms_trade t WHERE t.trade_sk = h.trade_sk)
           AND NOT EXISTS (SELECT 1 FROM ops.dqm_quarantine q WHERE q.trade_sk = h.trade_sk)
         GROUP BY h.trade_sk;
        SELECT COUNT(*) FROM #q;""")
    n = cur.fetchone()[0]
    print(f"[{time.strftime('%H:%M:%S')}] run {run} · 격리 규칙 {','.join(규칙)} · 새로 옮길 줄 {n:,}", flush=True)
    if n == 0: return
    if n > a.max and not a.force:
        print(f"멈춤: {n:,}줄 > 상한 {a.max:,} — 규칙을 확인하고 --force 로 다시"); sys.exit(1)
    cur.execute("SELECT STRING_AGG(CAST(QUOTENAME(name) AS NVARCHAR(MAX)), ',') WITHIN GROUP (ORDER BY column_id) FROM sys.columns "
                "WHERE object_id = OBJECT_ID('silver.rtms_trade') AND is_computed = 0")
    칸 = cur.fetchone()[0]; 칸t = ",".join("t." + c for c in 칸.split(","))
    cur.execute(f"""
        SET XACT_ABORT ON; BEGIN TRAN;
        INSERT ops.dqm_quarantine ({칸}, run_id, rule_ids, 격리시각)
        SELECT {칸t}, {run}, q.rule_ids, SYSDATETIME() FROM silver.rtms_trade t JOIN #q q ON q.trade_sk = t.trade_sk;
        DELETE t FROM silver.rtms_trade t JOIN #q q ON q.trade_sk = t.trade_sk
         WHERE EXISTS (SELECT 1 FROM ops.dqm_quarantine b WHERE b.trade_sk = t.trade_sk AND b.run_id = {run});
        SELECT @@ROWCOUNT;
        COMMIT;""")
    뺌 = cur.fetchone()[0]
    cur.execute(f"SELECT rule_ids, COUNT(*), COUNT(DISTINCT match_complex_id) FROM ops.dqm_quarantine WHERE run_id = {run} GROUP BY rule_ids ORDER BY 2 DESC")
    for r in cur.fetchall(): print(f"  {r[0]:20s} {r[1]:>6,}줄 · 단지 {r[2]:,}")
    cur.execute(f"SELECT DISTINCT match_complex_id FROM ops.dqm_quarantine WHERE run_id = {run} AND match_complex_id IS NOT NULL")
    단지 = [r[0] for r in cur.fetchall()]
    print(f"[{time.strftime('%H:%M:%S')}] silver 에서 뺌 {뺌:,}줄 · 이어진 단지 {len(단지):,}", flush=True)
    # 거래 요약(gold) 다시 세기 + 단지 상세 다시 담기(지도 마커는 매시 발행이 통째로 다시 만든다)
    t = time.time(); cur.execute("EXEC gold.usp_refresh_complex_trade"); print(f"  거래 요약 다시 셈 {time.time()-t:.0f}초", flush=True)
    if 단지:
        f = os.path.join(HERE, "..", "logs", f"dqm_quarantine_ids_{run}.txt")
        open(f, "w").write("\n".join(map(str, 단지)) + "\n")
        r = subprocess.run([sys.executable, os.path.join(HERE, "svc_publish.py"), "--mode", "ids", "--kinds", "detail", "--workers", "4", "--ids-file", f])
        print(f"  상세 다시 담기 끝 rc={r.returncode}", flush=True)


def cmd_show(a):
    cur = ms_conn(env()).cursor()
    cur.execute("SELECT MAX(run_id) FROM ops.dqm_rule_run WHERE 끝 IS NOT NULL"); run = cur.fetchone()[0]
    cur.execute("SELECT h.rule_id, s.이름, s.처리 FROM ops.dqm_rule_hit h JOIN ops.dqm_rule_stat s ON s.run_id = h.run_id AND s.rule_id = h.rule_id WHERE h.run_id = %s AND h.trade_sk = %s", (run, a.trade_sk))
    hits = cur.fetchall()
    g = max((등급순[x[2]] for x in hits), key=lambda v: {"B": 1, "C": 2, "격리": 3}[v], default="A")
    print(f"run {run} · trade_sk {a.trade_sk} · 등급 {g}")
    for x in hits: print("  ", *x)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("run"); s.add_argument("--rules", default="dqm_rules.yaml")
    s = sp.add_parser("apply"); s.add_argument("--max", type=int, default=2000); s.add_argument("--force", action="store_true")
    s = sp.add_parser("show"); s.add_argument("trade_sk", type=int)
    a = ap.parse_args(); globals()["cmd_" + a.cmd](a)
