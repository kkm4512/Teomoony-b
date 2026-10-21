#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_plan - 목표를 선언하면 할 일은 DB 가 계산한다

  py run_plan.py add  --sgg 11380                     # 은평구 전체를 목표로
  py run_plan.py add  --sgg 11290 --bjdong 13800      # 장위동만
  py run_plan.py list                                 # 목표 보기
  py run_plan.py plan                                 # 남은 일 보기 (아무것도 안 함)
  py run_plan.py go                                   # 실행
  py run_plan.py go --grp ext --max-min 90            # 세 축만, 90분까지
  py run_plan.py go --ops hsprc                       # 주택가격만
  py run_plan.py go --grp pms                         # 건축인허가만

왜 이렇게 만드나
---------------------------------------------------------------
범위를 넓힐 때마다 사람이 명령을 일곱 번 쳤다. 지역이 늘면 선형으로 는다.
그런데 **무엇이 끝났는지는 DB 가 이미 안다**(meta.ingest_run). 그러니 사람이
적을 것은 "할 일" 이 아니라 "어디까지 갖고 싶은가" 뿐이다.

  할 일 = 목표(meta.load_target) - 완료(meta.ingest_run)

★ 목록을 들고 있지 않는다. 매번 다시 계산한다.
  목록을 파일에 적어 두면 **그 파일이 두 번째 진실 공급원**이 되고,
  중간에 끊기거나 사람이 따로 돌린 적재와 어긋난다. 끊겨도 그냥 다시 돌리면
  된다 — 끝난 것은 DONE 이라 안 집는다.

★ TODO 와 RETRY 를 섞지 않는다.
  안 해본 것과 **끊긴 것**은 다른 문제다. 끊긴 쪽은 원인이 있을 수 있다.
  기본은 TODO 만 돌리고, RETRY 는 --retry 를 줘야 집는다.

경계
---------------------------------------------------------------
건축물대장 7종 + 건축인허가 2종만 법정동 단위로 ingest_run 에 남는다. 지적·건물·실거래·
K-apt·관리비는 기록이 없어 **대상 테이블에 행이 있는지로 거칠게** 본다.
거친 판정임을 출력에 적는다. 모르는 것을 아는 척하지 않는다(정책 6장).
"""
import argparse, os, re, signal, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor, as_completed
import pymssql
import runlog

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")

# 시군구 단위 거친 단계: (이름, 스크립트, 인자형태, 완료추정 SQL)
# 시군구 단위 거친 단계.
#   (스크립트, 인자형태, 시군구 완료추정 SQL, 법정동별 완료 SQL)
#
# ★ 법정동별 확인이 있는 단계는 **아직 없는 법정동만** 넘긴다 (2026-10-17).
#   전에는 시군구에 행이 하나라도 있으면 통째로 건너뛰었다. 은평구 건물
#   외곽선이 **102건**(종로 27,032 / 성북 13,811 과 비교하면 사실상 없음)
#   있다는 이유로 건너뛰어졌다. VWorld 를 bbox 로 받다 보니 이웃 시군구가
#   조금씩 흘러들어와 있었던 것이다 — 11200(4), 11230(118), 11305(299) 도 같다.
#   "행이 있으면 됐다" 는 판정이 정확히 이렇게 깨진다.
COARSE = {
    "cadastral": ("load_cadastral.py", "lawd",
                  "SELECT COUNT(*) FROM silver.cadastral_parcel "
                  "WHERE is_current=1 AND LEFT(lawd_cd,5)=%s",
                  "SELECT DISTINCT lawd_cd FROM silver.cadastral_parcel "
                  "WHERE is_current=1 AND LEFT(lawd_cd,5)=%s"),
    "building":  ("load_building.py", "lawd",
                  "SELECT COUNT(*) FROM silver.building_footprint "
                  "WHERE is_current=1 AND LEFT(lawd_cd,5)=%s",
                  "SELECT lawd_cd FROM silver.building_footprint "
                  "WHERE is_current=1 AND LEFT(lawd_cd,5)=%s "
                  "GROUP BY lawd_cd HAVING COUNT(*) >= 50"),
    "rtms":      ("load_rtms.py", "sgg",
                  "SELECT COUNT(*) FROM silver.rtms_trade WHERE sgg_cd=%s", None),
    "kapt":      ("load_kapt.py", "sgg", None, None),
    "cost":      ("load_kapt_cost.py", "sgg", None, None),
}

# ★ 기간을 **필수로 요구하는** 단계 (2026-10-17).
#   cost 만 고치고 rtms 를 안 봤다가 똑같이 `--from --to 가 필요합니다` 로
#   죽었다. 한 군데를 고칠 때 형제를 같이 봐야 한다 — 오늘 네 번째다.
#   그래서 특수 처리로 두지 않고 **표에 적는다.**
NEEDS_PERIOD = {"rtms", "cost"}

# ★ 이 문구가 적재기 출력에 보이면 **전체를 멈춘다** (2026-10-17).
#   일일 트래픽을 다 쓰거나 키가 죽으면 남은 수백 건이 몇 초 만에 줄줄이
#   실패하면서 **TODO 를 전부 RETRY 로 바꿔 놓는다.** RETRY 는 "사람이 봐야 할
#   것" 이라는 뜻인데, 그 의미가 쓰레기로 덮인다. 못 하는 상황이면 안 하는 게 맞다.
STOP_PATTERNS = (
    "resultCode=22",                        # 일일 트래픽 초과
    "LIMITED_NUMBER_OF_SERVICE_REQUESTS",
    "service key error",                    # 30/31/32
    "resultCode=30", "resultCode=31", "resultCode=32",
)

_stop = {"flag": False, "why": None}


def _on_sigint(sig, frm):
    # 두 번 누르면 즉시 죽는다. 한 번이면 **지금 돌고 있는 op 를 끝내고** 멈춘다.
    if _stop["flag"]:
        print("\n강제 종료."); sys.exit(130)
    _stop["flag"] = True; _stop["why"] = "사용자 중단"
    print("\n\n  ** 중단 요청. 지금 op 가 끝나면 멈춥니다. 한 번 더 누르면 즉시 종료 **\n")


def ts():
    return time.strftime("%H:%M:%S")


def hms(sec):
    m, x = divmod(int(sec), 60)
    return f"{m}분{x:02d}초" if m else f"{x}초"


def load_env(p):
    d = {}
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def conn(env):
    return pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=True)


def child_env():
    """★ 자식이 UTF-8 로 말하게 한다 (2026-10-17).

    윈도우에서 출력을 파이프로 받으면 자식 파이썬은 **콘솔 기본 인코딩(cp949)**
    으로 쓴다. 그걸 utf-8 로 읽어서 한글이 전부 깨졌다:

        '[load] \ufffd\ufffd\ufffd  status=OK  requests=3  \ufffd\ufffd\ufffd 200 ...'
                  완료 가 깨짐                     신규 가 깨짐

    로그 전문도 못 읽고 신규/변경/동일 집계도 못 뽑았다. 중단 감지(STOP_PATTERNS)
    만 멀쩡했는데 **그건 패턴이 전부 ASCII 라 운이 좋았던 것**이지 설계가 아니다.
    """
    e = dict(os.environ)
    e["PYTHONIOENCODING"] = "utf-8"
    e["PYTHONUTF8"] = "1"
    # ★ 파이프로 받으면 자식 파이썬이 블록 버퍼링을 한다 (2026-10-17).
    #   그러면 몇 KB 쌓일 때까지 화면에 아무것도 안 나와 **멈춘 것처럼 보인다.**
    #   run() 을 파이프로 바꾸면서 생긴 퇴보다.
    e["PYTHONUNBUFFERED"] = "1"
    return e


def run(script, *args):
    """자식 출력을 **한 줄씩 받아서 print 한다** (2026-10-17).

    ★ 전에는 subprocess.run 으로 그냥 돌렸다. 그러면 자식은 OS 파일
      디스크립터를 물려받으므로 출력이 **터미널로만 가고 logs/ 에는 안 남는다**
      (runlog 의 Tee 는 파이썬 객체라 자식이 안 거친다). --steps 가 25분을
      돌았는데 로그에는 단계 이름만 남아 있었다.

      print 로 다시 내보내면 Tee 를 거쳐 파일에도 들어간다. 한 줄씩 흘려보내므로
      긴 단계에서도 진행이 보인다.
    """
    cmd = [sys.executable, os.path.join(HERE, script), *map(str, args)]
    pr = subprocess.Popen(cmd, cwd=HERE, env=child_env(),
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          bufsize=0)          # 바이트로 받는다
    # ★ read(n) 을 쓰면 안 된다 (2026-10-17).
    #   텍스트/버퍼 스트림의 read(n) 은 **n 이 찰 때까지 블로킹**한다.
    #   자식의 첫 줄이 60자 남짓이면 256자가 안 차서 화면에 아무것도 안 나오고
    #   **멈춘 것처럼 보인다.** 버퍼링을 고치려다 더 나쁜 블로킹을 만들었다.
    #   bufsize=0 이면 stdout 이 raw FileIO 라 read(n) 이 syscall 한 번이고
    #   **지금 와 있는 만큼만** 돌려준다. (BufferedReader 의 read 와 다르다)
    dec = __import__("codecs").getincrementaldecoder("utf-8")("replace")
    while True:
        chunk = os.read(pr.stdout.fileno(), 4096)
        if not chunk:
            break
        sys.stdout.write(dec.decode(chunk))   # Tee 를 거치므로 logs/ 에도 남는다
        sys.stdout.flush()
    sys.stdout.write(dec.decode(b"", True))
    pr.wait()
    return pr.returncode == 0


def run_captured(script, *args, tag=None):
    """출력을 삼켜서 돌린다. 스레드로 돌릴 때 화면이 뒤섞이지 않게.

    돌려주는 것: (성공여부, 요약줄, 멈춰야 하는 사유 or None)

    ★ 실패하면 자식 출력을 **통째로 파일에 남긴다** (2026-10-17).
      전에는 마지막 한 줄만 들고 나머지를 버렸다. 그래서 인허가 14건이
      `3902 COMMIT TRANSACTION has no corresponding BEGIN` 으로 죽었을 때
      **진짜 원인이 담긴 줄들이 전부 사라졌다.** README 미결 3번이
      "재현 조건 미상" 으로 남아 있던 이유가 바로 이것이다 - 재현은
      여러 번 됐고, 볼 수가 없었을 뿐이다.
      성공한 실행은 그대로 버린다. 실패한 것만 남긴다.
    """
    cmd = [sys.executable, os.path.join(HERE, script), *map(str, args)]
    r = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=child_env())
    out = (r.stdout or "") + (r.stderr or "")
    why = next((pat for pat in STOP_PATTERNS if pat in out), None)
    # ★ PARTIAL 도 남긴다 (2026-10-18).
    #   위 주석이 "실패한 것만 남긴다" 라고 적고 있었는데, 그 '실패' 가
    #   **종료코드 0 이 아닌 것**이었다. 잘린 적재(PARTIAL)는 자식이 멀쩡히
    #   0 으로 끝나므로 여기 걸리지 않고 **출력이 통째로 버려졌다.**
    #   10-17 밤 hsprc 세 건이 그랬다 — 118분을 돌고 신사동·응암동이
    #   '신규 0' 으로 끝났는데, 몇 페이지에서 왜 멈췄는지를 적은 줄들이
    #   다시 한 번 모였다가 다시 한 번 버려졌다(10-4 와 같은 모양).
    #   `ok` 는 "자식이 안 죽었다" 이고 PARTIAL 은 "데이터가 모자란다" 다.
    #   **둘은 다른 얘기다.**
    partial = "status=PARTIAL" in out
    if (r.returncode != 0 or partial) and tag:
        kind = "fail" if r.returncode != 0 else "partial"
        d = os.path.join(HERE, "..", "logs")
        try:
            os.makedirs(d, exist_ok=True)
            fp = os.path.join(d, "%s_%s_%s.log" % (kind, time.strftime("%Y%m%d_%H%M%S"), tag))
            with open(fp, "w", encoding="utf-8") as fh:
                fh.write("$ %s\n\n%s" % (" ".join(cmd), out))
            tail = [x for x in out.splitlines() if x.strip()][-12:]
            print("             --- 자식 출력 끝 12줄 (%s) ---" % os.path.basename(fp))
            for x in tail:
                print("             | " + x[:160])
        except Exception as e:
            print("             (실패 로그를 못 남겼다: %s)" % e)
    # 적재기의 마지막 요약줄을 뽑는다
    summary = ""
    for line in reversed(out.splitlines()):
        if line.startswith("[load] 완료") or "status=" in line:
            summary = line.strip(); break
    if not summary:
        summary = (out.strip().splitlines() or [""])[-1][:120]
    return r.returncode == 0, summary, why


# ============================================================
def cmd_add(cur, a):
    """★ 안 준 것은 **안 바꾼다** (2026-10-17).

    전에는 --ops 만 주고 다시 add 하면 **note 와 priority 가 기본값으로
    덮였다.** 축 하나를 추가하려고 ops 를 고치는 게 흔한 일인데, 그때마다
    사람이 적어 둔 비고가 조용히 사라진다. 조용히 지우는 것이 가장 나쁘다.
    그래서 생략한 인자는 COALESCE 로 기존 값을 그대로 둔다."""
    cur.execute("""
        MERGE meta.load_target AS t
        USING (SELECT %s AS sgg_cd, %s AS bjdong_cd) AS s
           ON t.sgg_cd = s.sgg_cd
          AND (t.bjdong_cd = s.bjdong_cd OR (t.bjdong_cd IS NULL AND s.bjdong_cd IS NULL))
        WHEN MATCHED THEN UPDATE SET ops      = COALESCE(%s, t.ops),
                                     priority = COALESCE(%s, t.priority),
                                     note     = COALESCE(%s, t.note),
                                     enabled  = 1
        WHEN NOT MATCHED THEN INSERT (sgg_cd,bjdong_cd,ops,priority,note)
             VALUES (s.sgg_cd, s.bjdong_cd, COALESCE(%s,'base,ext'),
                     COALESCE(%s,100), %s);""",
        (a.sgg, a.bjdong, a.ops, a.priority, a.note, a.ops, a.priority, a.note))
    where = f"{a.sgg}" + (f"/{a.bjdong}" if a.bjdong else " 전체")
    print(f"목표 등록: {where}" + (f"  ops={a.ops}" if a.ops else "  (ops 유지)"))
    cmd_list(cur, a)


def cmd_list(cur, a):
    cur.execute("""SELECT target_id, sgg_cd, bjdong_cd, ops, priority, enabled, note
                     FROM meta.load_target ORDER BY priority, sgg_cd, bjdong_cd""")
    rows = cur.fetchall()
    if not rows:
        print("\n목표가 없습니다.  py run_plan.py add --sgg 11380"); return
    print(f"\n{'id':>3} {'시군구':>7} {'법정동':>7} {'ops':<16} {'순위':>4} {'사용':>4}  비고")
    for t, sgg, bjd, ops, pr, en, note in rows:
        print(f"{t:>3} {sgg:>7} {(bjd or '전체'):>7} {ops:<16} {pr:>4} "
              f"{('예' if en else '아니오'):>4}  {note or ''}")


def cmd_disable(cur, a):
    cur.execute("UPDATE meta.load_target SET enabled=0 WHERE target_id=%s", (a.target_id,))
    print(f"목표 {a.target_id} 끔"); cmd_list(cur, a)


def fetch_plan(cur, a, statuses, only_ready=True):
    """only_ready=True 면 **기본개요가 끝난 법정동만** 돌려준다.

    ★ 순서를 러너가 지킨다 (2026-10-17). --ops 로 축을 골라 돌릴 수 있게 해
      놓고 순서를 안 막아 둬서, 은평구에 기본개요보다 표제부가 먼저 들어갔다.
      깨지진 않지만 붕 뜬 채로 쌓이고, 그 사이 build 가 돌면 그 동들이
      빠진 단지가 생긴다. 기본개요는 계층의 단일 진실 공급원이다.
    """
    q = """SELECT sgg_cd, bjdong_cd, 법정동, op_alias, operation, grp, 상태, priority, sort_no
             FROM meta.v_load_plan WHERE 상태 IN (%s)""" % ",".join("%s" for _ in statuses)
    p = list(statuses)
    if only_ready:
        q += " AND 선행='OK'"
    if a.sgg:  q += " AND sgg_cd=%s";  p.append(a.sgg)
    if a.grp:  q += " AND grp=%s";     p.append(a.grp)
    if a.ops:
        names = [x.strip() for x in a.ops.split(",") if x.strip()]
        q += " AND op_alias IN (%s)" % ",".join("%s" for _ in names); p += names
    q += " ORDER BY priority, sgg_cd, sort_no, bjdong_cd"
    cur.execute(q, tuple(p))
    return cur.fetchall()


def warn_unplannable(cur):
    """★ 목표인데 계획에 안 잡히는 시군구를 드러낸다 (2026-10-17).

    meta.v_load_plan 은 meta.lawd_code 와 조인한다. 법정동코드가 아직 없는
    시군구는 **조인에서 통째로 사라져 계획에 한 줄도 안 나온다.** 목표로
    등록했는데 plan 이 아무 말도 안 하면 사람은 "할 일이 없구나" 로 읽는다.
    go 는 법정동코드를 먼저 채우므로 실제로는 돌아가지만, **조용한 것이 문제다.**
    """
    cur.execute("""SELECT t.sgg_cd, t.note FROM meta.load_target t
                    WHERE t.enabled=1 AND NOT EXISTS
                      (SELECT 1 FROM meta.lawd_code l WHERE l.sgg_cd=t.sgg_cd)
                    ORDER BY t.sgg_cd""")
    rows = cur.fetchall()
    if rows:
        print("\n  ** 계획을 못 세운 목표 **  법정동코드가 아직 없습니다")
        for sgg, note in rows:
            print(f"     {sgg}  {note or ''}")
        print("     go 가 먼저 채웁니다:  py run_plan.py go   또는"
              "  py load_lawd.py --sgg " + " ".join(r[0] for r in rows))
    return len(rows)


def cmd_plan(cur, a):
    cur.execute("""SELECT sgg_cd, op_alias, grp, 법정동수, 완료, 재시도, 남음, 선행미완
                     FROM meta.v_load_progress ORDER BY sgg_cd,
                          CASE grp WHEN 'base' THEN 0 ELSE 1 END, op_alias""")
    rows = cur.fetchall()
    if not rows:
        cur.execute("SELECT COUNT(*) FROM meta.load_target WHERE enabled=1")
        if cur.fetchone()[0] == 0:
            print("\n목표가 없습니다.  py run_plan.py add --sgg 11380"); return
        print("\n계획이 비어 있습니다 — 목표는 있는데 법정동이 안 잡힙니다.")
        warn_unplannable(cur); return
    print(f"\n{'시군구':>7} {'op':<7} {'법정동':>6} {'완료':>6} {'재시도':>6} {'남음':>6} {'선행대기':>8}")
    cur_sgg = None; tot_todo = tot_retry = tot_block = 0
    for sgg, op, grp, n, done, retry, todo, block in rows:
        if sgg != cur_sgg: print(); cur_sgg = sgg
        mark = "  <-" if todo or retry else ""
        print(f"{sgg:>7} {op:<7} {n:>6,} {done:>6,} {retry:>6,} {todo:>6,} "
              f"{block:>8,}{mark}")
        tot_todo += todo; tot_retry += retry; tot_block += block
    print(f"\n  남은 법정동x op : TODO {tot_todo:,}  RETRY {tot_retry:,}")
    if tot_block:
        print(f"  그중 {tot_block:,} 건은 **기본개요가 먼저** 필요합니다 "
              f"(py run_plan.py go --ops basis)")
    if tot_retry:
        print(f"\n  ** RETRY {tot_retry}건은 기본 실행에서 빠집니다. --retry 로 포함하세요 **")
        for r in fetch_plan(cur, a, ("RETRY",))[:10]:
            print(f"     {r[0]}/{r[1]} {r[2] or '':<8} {r[3]}")
    warn_unplannable(cur)
    estimate(cur, a)


def estimate(cur, a):
    """★ 남은 시간을 **실측으로** 센다 (2026-10-17).

    전에는 '법정동 하나당 36초' 라는 근거 없는 상수를 곱했다. op 마다 분량이
    다섯 배씩 차이 나는데(주택가격 98만 vs 총괄 841) 한 숫자로 뭉갠 것이다.
    meta.ingest_run 에 **끝난 적재의 시작/종료 시각이 이미 남아 있다.**
    같은 op 의 평균 소요로 남은 건수를 곱하면 된다.

    ★ 기록이 없는 op 는 **모른다고 적는다.** 아무 숫자나 꾸며 넣지 않는다.
    """
    cur.execute("""
        SELECT o.op_alias,
               평균초 = AVG(CAST(DATEDIFF(SECOND, r.started_at, r.finished_at) AS FLOAT)),
               표본 = COUNT(*)
          FROM meta.ingest_run r
          JOIN meta.api_source s ON s.source_id = r.source_id
          JOIN meta.load_op   o ON o.operation  = s.operation
         WHERE r.status = 'OK' AND r.finished_at IS NOT NULL
           AND DATEDIFF(SECOND, r.started_at, r.finished_at) BETWEEN 1 AND 7200
         GROUP BY o.op_alias""")
    seen = {alias: (avg, n) for alias, avg, n in cur.fetchall()}

    cur.execute("""SELECT op_alias, SUM(남음 + 재시도) FROM meta.v_load_progress
                    GROUP BY op_alias""")
    left = {alias: n for alias, n in cur.fetchall() if n}
    if not left:
        return

    print(f"\n  남은 시간 추정 (같은 op 의 실측 평균 x 남은 법정동 수)")
    print(f"  {'op':<7} {'남음':>5} {'평균':>8} {'표본':>5} {'예상':>9}")
    total = 0.0; unknown = []
    for alias, n in sorted(left.items()):
        if alias in seen:
            avg, cnt = seen[alias]
            total += avg * n
            print(f"  {alias:<7} {n:>5,} {avg:>7.0f}초 {cnt:>5,} {hms(avg*n):>9}")
        else:
            unknown.append((alias, n))
            print(f"  {alias:<7} {n:>5,} {'기록없음':>8} {'-':>5} {'모름':>9}")
    small = [a2 for a2, (av, n) in seen.items() if n < 5 and a2 in left]
    if small:
        print(f"\n  ** 표본이 적습니다({', '.join(small)}). 지금 표본은 돈암동·정릉동 같은")
        print("     **큰 법정동**이라 평균이 위로 치우칩니다. 종로구 87개는 대부분 작아서")
        print("     실제로는 이보다 빨리 끝날 가능성이 높습니다. 돌릴수록 정확해집니다. **")
    print(f"\n  스레드 1개 기준 약 {hms(total)}")
    for w in (2, 4):
        print(f"           {w}개   약 {hms(total/w)}  (완벽히 나뉠 때. "
              f"큰 법정동 하나가 바닥이다)")
    if unknown:
        names = ", ".join(f"{a}({n:,})" for a, n in unknown)
        print(f"\n  ** 아직 한 번도 안 돌려 본 op 는 추정에서 빠집니다: {names} **")
        print("     한 법정동만 먼저 돌려 보면 그 뒤로는 추정이 생깁니다.")


#  겹쳐 받을 페이지 수. SCD 업서트라 겹치는 행은 '동일' 로 떨어지므로 싸다.
#  0 으로 두지 않는 이유: DB 행 수와 API 가 준 건수가 정확히 같다는 보장이 없다
#  (flr/atch 의 99% 계통 오차가 그 예다). 모자라게 건너뛰면 **구멍이 남고**,
#  구멍은 '동일' 과 달리 눈에 안 띈다.
RESUME_BACKOFF_PAGES = 2
RESUME_ROWS_PER_PAGE = 100          # 대장 API 는 페이지당 100 상한 (README 8장)


def resume_pages(cur, work):
    """끊긴 적재를 **이어받을 페이지**를 법정동x op 별로 계산한다 (2026-10-18).

    ★ 왜 필요한가
      `--from-page` 는 10-16 에 적재기에 붙여 뒀는데 **러너가 그걸 안 넘겼다.**
      그래서 RETRY 는 매번 1페이지부터 다시 받았다. 10-17 밤 실측:

          신사동  이전 75,200 -> 이번에 8,000 (전부 '동일')   134 호출, 진전 0
          응암동  이전 97,000 -> 이번에 36,400 (전부 '동일')  584 호출, 진전 0
          진관동  이전 22,200 -> 152,300                     2,136 호출

      2,854 호출 중 940(33%)이 **이미 있는 행을 다시 확인한 것**이다.
      게다가 API 가 빈 페이지를 주는 지점이 매번 달라서(EMPTY_RETRIES=4)
      1페이지부터 받으면 **전보다 덜 가고 멈출 수도 있다** — 신사동이 그랬다.

    ★ 왜 행 수로 세나
      적재기가 "몇 페이지까지 받았다" 를 남기지 않는다. 남기게 하는 것이
      정석이지만(스키마가 바뀐다), 행 수 + 겹침이면 지금 구조로 된다.
      대신 **추측을 조용히 하지 않는다** — 계산한 값을 화면에 찍는다.

    돌려주는 것: {(sgg, bjdong, alias): from_page}.  못 세면 그 단위는 뺀다
    (= 1페이지부터. 지금까지의 동작과 같다).
    """
    try:
        from teomoony_ingest import OPS
    except Exception as e:
        print(f"  (이어받기 생략 - OPS 를 못 읽었다: {e})")
        return {}

    out, skipped = {}, []
    for unit in work:
        sgg, bjd, nm, alias, operation = unit[0], unit[1], unit[2], unit[3], unit[4]
        tbl = (OPS.get(operation) or {}).get("target") or ""
        if not re.fullmatch(r"[A-Za-z_]+\.[A-Za-z_]+", tbl):
            continue
        sch, _, name = tbl.partition(".")
        try:
            # ★★ 번지 probe 가 섞인 스코프는 **이어받지 않는다** (2026-10-18).
            #   이어받기는 "DB 행 = 법정동 전체 페이지네이션의 앞부분" 을 전제한다.
            #   `--bun` 으로 번지 하나만 떠본 probe(run_mode='SINGLE') 행이
            #   섞여 있으면 그 전제가 깨진다 — 행 수는 큰데 **앞 페이지를 안 받은
            #   상태**라, 건너뛴 페이지가 그대로 구멍이 된다.
            #   돈암동(11290/10300)이 실제로 그랬다: expos 8,702행이 전부 SINGLE
            #   probe 였고, 그대로 돌렸으면 1~84페이지를 영영 안 받았을 것이다.
            #   '동일' 은 로그에 보이지만 **구멍은 아무 데도 안 보인다.**
            #   CONTEXT 10-2 가 v_load_plan 에서 잡은 그 함정이 새 코드에 재발했다.
            cur.execute("""SELECT
                             full_n = SUM(CASE WHEN r.run_mode='FULL' THEN 1 ELSE 0 END),
                             other_n= SUM(CASE WHEN r.run_mode<>'FULL' THEN 1 ELSE 0 END)
                           FROM meta.ingest_run r
                           JOIN meta.api_source s ON s.source_id = r.source_id
                          WHERE r.scope_key = %s AND s.operation = %s""",
                        (f"{sgg}/{bjd}", operation))
            row = cur.fetchone() or (0, 0)
            full_n, other_n = int(row[0] or 0), int(row[1] or 0)
            if other_n > 0 or full_n == 0:
                why = "번지 probe 섞임" if other_n else "FULL 적재 기록 없음"
                skipped.append(f"{sgg}/{bjd} {alias}: {why} -> 1페이지부터")
                continue
            # ★ 컬럼이 있는지 **밖에서 확인하고** 센다. 없으면 이어받지 않는다.
            cur.execute("""SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
                            WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s
                              AND COLUMN_NAME IN
                                  ('sigungu_cd','bjdong_cd','is_current')""",
                        (sch, name))
            if int(cur.fetchone()[0] or 0) != 3:
                continue
            cur.execute(f"SELECT COUNT(*) FROM {tbl} WITH (NOLOCK) "
                        "WHERE is_current=1 AND sigungu_cd=%s AND bjdong_cd=%s",
                        (sgg, bjd))
            rows = int(cur.fetchone()[0] or 0)
        except Exception as e:
            skipped.append(f"{sgg}/{bjd} {alias}: {str(e)[:60]}")
            continue
        page = rows // RESUME_ROWS_PER_PAGE - RESUME_BACKOFF_PAGES
        if page > 1:
            out[(sgg, bjd, alias)] = (page, rows)
    if skipped:
        print(f"  (이어받기를 못 센 단위 {len(skipped)}건 - 1페이지부터 받습니다)")
        for s in skipped[:3]:
            print(f"     {s}")
    return out


def cmd_go(cur, a, env):
    statuses = ("TODO", "RETRY") if a.retry else ("TODO",)
    work = fetch_plan(cur, a, statuses)

    # 선행이 안 끝나 이번에 못 도는 것을 **말은 하고** 넘어간다.
    blocked = fetch_plan(cur, a, statuses, only_ready=False)
    n_blocked = len(blocked) - len(work)
    if n_blocked > 0:
        print(f"\n  ** 기본개요가 아직인 법정동이 있어 {n_blocked}건을 미룹니다 **")
        print("     기본개요가 계층을 들고 있어서 먼저 들어가야 합니다.")
        print("     먼저:  py run_plan.py go --ops basis")

    # ---------- 법정동코드가 비어 있으면 먼저 채운다 ----------
    cur.execute("""SELECT DISTINCT t.sgg_cd FROM meta.load_target t
                    WHERE t.enabled=1 AND NOT EXISTS
                      (SELECT 1 FROM meta.lawd_code l WHERE l.sgg_cd=t.sgg_cd)""")
    need_lawd = [r[0] for r in cur.fetchall()]
    if need_lawd:
        print(f"\n[법정동코드] {', '.join(need_lawd)} 가 비어 있어 먼저 채웁니다")
        for sgg in need_lawd:
            if not run("load_lawd.py", "--sgg", sgg):
                sys.exit(f"법정동코드 적재 실패: {sgg}")
        work = fetch_plan(cur, a, statuses)      # 법정동이 생겼으니 다시 계산

    if not work:
        print("\n법정동 단위(대장·인허가) 쪽은 남은 일이 없습니다.")
    else:
        # ★ 돌리기 전에 api_source 를 한 번에 등록한다 (2026-10-17).
        #   적재기는 시작할 때마다 MERGE meta.api_source 를 친다. 스레드를
        #   여러 개 돌리면 **같은 (domain, operation) 행에 동시에 MERGE** 가
        #   걸려 교착이 난다. 미리 채워 두면 MERGE 가 전부 MATCHED 로 빠진다.
        # ★ domain 을 박아 두지 않는다 (2026-10-17).
        #   건축인허가는 **다른 서비스**(ArchPmsHubService)다. 여기에 'BLDRGST' 를
        #   박아 두면 인허가 op 를 추가하는 순간 (BLDRGST, getApBasisOulnInfo) 라는
        #   없는 서비스의 행이 생기고, 적재기가 만드는 (ARCHPMS, ...) 와 둘이 된다.
        #   meta.load_op 이 domain/base_url 까지 들고 있으니 그걸 읽는다.
        cur.execute("""
            MERGE meta.api_source AS t
            USING (SELECT domain, operation, base_url FROM meta.load_op) AS s
               ON t.domain = s.domain AND t.operation = s.operation
            WHEN NOT MATCHED THEN
              INSERT (domain, provider, operation, base_url, resp_format)
              VALUES (s.domain, N'국토교통부', s.operation, s.base_url, 'xml');""")

        # ★ 끊긴 것은 이어받는다 (2026-10-18). 스레드 띄우기 **전에** 한 번에
        #   계산한다 — cur 를 스레드끼리 나눠 쓰지 않기 위해서다.
        resume = resume_pages(cur, work)
        if resume:
            print(f"\n  [이어받기] {len(resume)}건은 1페이지부터 받지 않습니다 "
                  f"(겹침 {RESUME_BACKOFF_PAGES}페이지)")
            for (s, b, al), (pg, rw) in sorted(resume.items())[:8]:
                print(f"     {s}/{b} {al:<8} DB {rw:,}행 -> --from-page {pg}")
            if len(resume) > 8:
                print(f"     ... 외 {len(resume)-8}건")

        nw = max(1, int(a.workers))
        print(f"\n[{ts()}] [대장·인허가] {len(work)}건 (법정동 x op)  스레드 {nw}개")
        print(f"  법정동 하나가 1~3분 걸린다. 30초마다 진행중을 찍는다.")
        if nw > 1:
            print("  ** 동시 호출을 늘리면 503(서비스 연결실패)도 같이 는다. "
                  "일일 트래픽도 그만큼 빨리 쓴다 **")
        t0 = time.time()
        counts = {"did": 0, "fail": 0}
        lock = threading.Lock()
        done_n = {"n": 0}

        # ★ 자식 출력을 캡처하므로 **끝날 때까지 화면이 조용하다** (2026-10-17).
        #   법정동 하나가 1~3분이라 멈춘 것처럼 보인다. 시작도 찍고, 도는 동안
        #   무엇이 얼마나 돌고 있는지도 주기적으로 찍는다.
        running = {}          # key -> (시작시각, 표시이름)

        op_blocked = set()   # 오늘 몫을 다 쓴 op (선행 확인용 blocked 와 다르다)

        def one(unit):
            sgg, bjd, nm, alias, operation, grp, st, pr, sn = unit
            if _stop["flag"] or alias in op_blocked:
                return None
            key = f"{sgg}/{bjd} {alias}"
            label = f"{sgg}/{bjd} {nm or '':<8} {alias:<6}"
            started = time.time()
            frm = resume.get((sgg, bjd, alias))
            extra = ("--from-page", str(frm[0])) if frm else ()
            with lock:
                running[key] = (started, label)
                tail = f"  (이어받기 p{frm[0]}, DB {frm[1]:,}행)" if frm else ""
                print(f"  [{ts()}] >> {label} 시작{tail}")
            ok, summary, why = run_captured(
                "teomoony_ingest.py", "load", "--op", operation,
                "--sigungu", sgg, "--bjdong", bjd, *extra,
                tag=f"{sgg}_{bjd}_{alias}")
            with lock:
                running.pop(key, None)
                done_n["n"] += 1
                i = done_n["n"]
                took = time.time() - started
                mark = "OK" if ok else "!!"
                print(f"  [{ts()}] {mark} [{i}/{len(work)}] {label} "
                      f"{hms(took)}  (전체 {hms(time.time()-t0)})")
                if summary:
                    print(f"             {summary[:110]}")
                if ok:
                    counts["did"] += 1
                else:
                    counts["fail"] += 1
                rl = globals().get("_RL")
                if rl:
                    rl.event(sgg=sgg, bjdong=bjd, 법정동=nm, op=alias,
                             ok=bool(ok), sec=round(took, 1),
                             before=st, summary=summary[:200], stop=why)
                    rl.count("ok" if ok else "fail")
                if why:
                    # ★ 한도는 **오퍼레이션별**이다 (2026-10-17 실측).
                    #   hsprc 가 22 를 받는 바로 그 시각에 atch·flr 는 멀쩡히
                    #   돌았다. 서비스 단위로 묶여 있다면 전부 막혔어야 한다.
                    #   그러니 **그 op 만 접고** 예산이 남은 다른 op 는 계속한다.
                    #   키 문제(30/31/32)는 어느 op 든 못 고치므로 전체를 멈춘다.
                    key_problem = "service key error" in why or why in (
                        "resultCode=30", "resultCode=31", "resultCode=32")
                    if key_problem:
                        _stop["flag"] = True; _stop["why"] = why
                        print(f"\n  ** 전체 중단: '{why}' — 키 문제는 어느 op 도 못 넘는다 **\n")
                    elif alias not in op_blocked:
                        op_blocked.add(alias)
                        print(f"\n  ** '{alias}' 접음: {why} **")
                        print(f"     이 op 의 오늘 몫을 다 썼습니다. 남은 {alias} 건은")
                        print(f"     건드리지 않습니다 — 내일 이어서 집습니다.")
                        print(f"     다른 op 는 계속합니다.\n")
            return ok

        def heartbeat():
            while not hb_stop.is_set():
                if hb_stop.wait(30):
                    break
                with lock:
                    if running:
                        now = time.time()
                        items = ", ".join(
                            f"{lb.strip()} {hms(now-stt)}"
                            for stt, lb in sorted(running.values()))
                        print(f"  [{ts()}] .. 진행중 {len(running)}건 — {items}")

        hb_stop = threading.Event()
        hb = threading.Thread(target=heartbeat, daemon=True); hb.start()

        try:
            if nw == 1:
                for unit in work:
                    if _stop["flag"]: break
                    if unit[3] in op_blocked: continue
                    if a.max_min and (time.time()-t0)/60 >= a.max_min:
                        print(f"\n  시간 상한 {a.max_min}분 도달. 멈춥니다."); break
                    one(unit)
            else:
                with ThreadPoolExecutor(max_workers=nw) as ex:
                    futs = []
                    it = iter(work)
                    # 상한을 넘기면 **새로 안 던진다**. 던진 것은 끝까지 기다린다.
                    for unit in it:
                        if _stop["flag"]: break
                        if unit[3] in op_blocked: continue
                        if a.max_min and (time.time()-t0)/60 >= a.max_min:
                            print(f"\n  시간 상한 {a.max_min}분 도달. "
                                  f"돌고 있는 것만 끝내고 멈춥니다."); break
                        futs.append(ex.submit(one, unit))
                        while sum(1 for f in futs if not f.done()) >= nw * 2:
                            time.sleep(0.2)
                            if _stop["flag"]: break
                    for f in as_completed(futs):
                        f.result()
        except KeyboardInterrupt:
            _stop["flag"] = True; _stop["why"] = "사용자 중단"
        finally:
            hb_stop.set()

        left = len(work) - counts["did"] - counts["fail"]
        print(f"\n  대장·인허가 결과: 성공 {counts['did']} / 실패 {counts['fail']} / "
              f"남김 {left}  ({(time.time()-t0)/60:.1f}분)")
        if op_blocked:
            print(f"  오늘 몫을 다 쓴 op: {', '.join(sorted(op_blocked))}")
            rl = globals().get("_RL")
            if rl: rl.set_note(f"한도 소진: {','.join(sorted(op_blocked))}")
        if _stop["why"]:
            print(f"  중단 사유: {_stop['why']}")
            rl = globals().get("_RL")
            if rl: rl.set_note(f"중단: {_stop['why']}")

    # ---------- 단지 구성 ----------
    # base 를 하나라도 새로 넣었으면 다시 묶어야 한다.
    if not a.skip_build and not _stop["flag"]:
        cur.execute("""SELECT DISTINCT sgg_cd FROM meta.load_target WHERE enabled=1"""
                    + (" AND sgg_cd=%s" if a.sgg else ""), (a.sgg,) if a.sgg else None)
        for (sgg,) in cur.fetchall():
            if _stop["flag"]: break
            print(f"\n[단지 구성] {sgg}")
            if not run("teomoony_ingest.py", "build", "--sigungu", sgg):
                print("  ! 단지 구성 실패 — 이후 단계가 옛 단지로 돌 수 있습니다")

    # ---------- 시군구 단위 거친 단계 ----------
    if a.steps and not _stop["flag"]:
        want = [s.strip() for s in a.steps.split(",") if s.strip()]
        bad = [s for s in want if s not in COARSE]
        if bad: sys.exit(f"--steps 에 모르는 이름: {', '.join(bad)}")
        cur.execute("SELECT DISTINCT sgg_cd FROM meta.load_target WHERE enabled=1"
                    + (" AND sgg_cd=%s" if a.sgg else ""), (a.sgg,) if a.sgg else None)
        sggs = [r[0] for r in cur.fetchall()]
        print(f"\n[시군구 단위] {', '.join(want)}")
        print("  ** 이 단계들은 ingest_run 에 안 남아 **대상 테이블에 행이 있는지**로만")
        print("     판정합니다. 부분 적재는 '있음' 으로 보입니다 — 거친 판정입니다.")
        for sgg in sggs:
            if _stop["flag"]: break
            cur.execute("SELECT lawd_cd FROM meta.lawd_code WHERE sgg_cd=%s", (sgg,))
            lawds = [r[0] for r in cur.fetchall()]
            for name in want:
                if _stop["flag"]: break
                script, argkind, probe, per_lawd = COARSE[name]
                todo = lawds
                if per_lawd and not a.force:
                    cur.execute(per_lawd, (sgg,))
                    have = {r[0] for r in cur.fetchall()}
                    todo = [l for l in lawds if l not in have]
                    if not todo:
                        print(f"  {sgg} {name:<10} 법정동 {len(lawds)}개 모두 있음 — 건너뜀")
                        continue
                    if len(todo) < len(lawds):
                        print(f"  {sgg} {name:<10} {len(lawds)-len(todo)}개 건너뛰고 "
                              f"{len(todo)}개만")
                elif probe and not a.force:
                    cur.execute(probe, (sgg,))
                    n = cur.fetchone()[0]
                    if n > 0:
                        print(f"  {sgg} {name:<10} 이미 {n:,}행 — 건너뜀 "
                              f"(**거친 판정**. 부분 적재도 '있음' 이다. --force 로 무시)")
                        continue
                # ★ 비용 경고는 --force 와 무관하다 (2026-10-17).
                #   --force 는 "이미 있어도 다시 받아라" 지 "경고를 끄라" 가
                #   아닌데 한 조건에 묶어 놔서, 정작 --force 로 돌릴 때
                #   경고가 안 떴다.
                if name == "cost":
                    # ★ 오퍼레이션이 **31개**다 (2026-10-17 교정).
                    #   처음에 3 으로 적어 호출량을 10배 적게 경고했다 —
                    #   종로를 "최대 1,404" 로 알렸는데 실제는 14,508 이었다.
                    #   CONTEXT 에 "단지당 31호출" 이라고 적혀 있는데도 틀렸다.
                    #   **과소 경고는 경고가 없는 것보다 나쁘다.**
                    #
                    #   한도는 모른다. 문서에 K-apt 일일 5,000 이라 적혀 있으나
                    #   종로가 14,508 호출을 막힘 없이 통과했다. 건축HUB 처럼
                    #   오퍼레이션별일 수도 있다 — **재지 않았다.**
                    KAPT_OPS = 31
                    cur.execute("""SELECT COUNT(*) FROM silver.kapt_complex
                                    WHERE is_current=1 AND LEFT(bjd_code,5)=%s""", (sgg,))
                    nk = cur.fetchone()[0]
                    y1, m1 = int(a.ym_from[:4]), int(a.ym_from[4:])
                    y2, m2 = int(a.ym_to[:4]), int(a.ym_to[4:])
                    months = max(0, (y2-y1)*12 + (m2-m1) + 1)
                    calls = nk * months * KAPT_OPS
                    print(f"  {sgg} cost  단지 {nk} x {months}개월 x "
                          f"오퍼레이션 {KAPT_OPS}개 = 약 {calls:,} 호출")
                    if calls > 20000:
                        print(f"       ** 호출이 많습니다. 시간이 오래 걸리고 "
                              f"(대략 {calls/4600:.0f}시간) 한도에 닿을 수 있습니다.")
                        print(f"          --from/--to 로 기간을 줄이면 선형으로 줄어듭니다 **")
                print(f"  {sgg} {name}")
                if argkind == "lawd":
                    ok = run(script, "--lawd", *todo)
                else:
                    extra = (["--from", a.ym_from, "--to", a.ym_to]
                             if name in NEEDS_PERIOD else [])
                    ok = run(script, "--sgg", sgg, *extra)
                if not ok:
                    # ★ 자식이 죽어도 러너는 다음으로 넘어간다. 그런데 **조용히**
                    #   넘어가면 안 돌았다는 걸 아무도 모른다 — cost 가 "대상 월이
                    #   없습니다" 로 끝났는데 성공처럼 지나갔다.
                    print(f"  ** {sgg} {name} 실패 — 위 메시지를 보라 **")
                    rl = globals().get("_RL")
                    if rl: rl.event(sgg=sgg, bjdong='*', op=name, ok=False,
                                    sec=0, before='COARSE', summary='실패', stop=None)

    # ★ 알림에 **남은 일**을 싣는다 (2026-10-17).
    #   빈손 패스의 카톡이 "적재 완료 · 0분" 한 줄이었다. 사람이 알고 싶은 것은
    #   무엇이 끝났는지보다 **무엇이 아직 남았는지**다. 덮지 않고 덧붙인다 —
    #   한도 소진·중단 사유가 이미 들어 있을 수 있다.
    try:
        cur.execute("""SELECT op_alias, SUM(재시도 + 남음)
                         FROM meta.v_load_progress
                        GROUP BY op_alias HAVING SUM(재시도 + 남음) > 0
                        ORDER BY op_alias""")
        left = cur.fetchall()
        rl = globals().get("_RL")
        if rl:
            rl.add_note("남은 일: " + (" · ".join(f"{k} {v}" for k, v in left)
                                       if left else "없음 (대장·인허가 기준)"))
    except Exception as e:
        print(f"  (남은 일 집계 실패: {type(e).__name__}: {e})")

    print("\n" + "="*58)
    cmd_plan(cur, a)


# ============================================================
def main():
    ap = argparse.ArgumentParser(description="목표 선언형 적재 러너")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("add", help="목표 등록/수정")
    p.add_argument("--sgg", required=True)
    p.add_argument("--bjdong", default=None, help="생략하면 시군구 전체")
    p.add_argument("--ops", default=None,
                   help="그룹(base,ext,pms) 또는 별칭(basis,title,flr,expos,hsprc,"
                        "pms,pmsdong). 생략하면 기존 목표는 그대로, 새 목표는 base,ext")
    p.add_argument("--priority", type=int, default=None)
    p.add_argument("--note", default=None)

    sub.add_parser("list", help="목표 보기")

    p = sub.add_parser("disable", help="목표 끄기")
    p.add_argument("--target-id", type=int, required=True)

    for name, helptext in (("plan", "남은 일 보기"), ("go", "실행")):
        p = sub.add_parser(name, help=helptext)
        p.add_argument("--sgg", default=None, help="이 시군구만")
        p.add_argument("--grp", default=None, choices=["base", "ext", "pms"])
        p.add_argument("--ops", default=None, help="별칭 쉼표 구분")
        if name == "go":
            p.add_argument("--retry", action="store_true",
                           help="끊긴 적재(RETRY)도 포함")
            p.add_argument("--max-min", type=float, default=0,
                           help="이 분 수를 넘기면 멈춘다. 밤새 나눠 돌릴 때")
            p.add_argument("--workers", type=int, default=1,
                           help="동시 스레드. 병목은 API 대기라 효과가 크지만 "
                                "503 과 트래픽 소모도 같이 는다. 3~4 부터 보기")
            p.add_argument("--steps", default=None,
                           help=f"시군구 단위 단계: {','.join(COARSE)}")
            p.add_argument("--from", dest="ym_from", default="202401",
                           help="관리비·실거래 시작월 YYYYMM")
            p.add_argument("--to", dest="ym_to", default="202512",
                           help="관리비·실거래 끝월 YYYYMM")
            p.add_argument("--skip-build", action="store_true")
            p.add_argument("--force", action="store_true")

    a = ap.parse_args()
    for k, v in (("sgg",None),("grp",None),("ops",None),("retry",False),("workers",1),
                 ("max_min",0),("steps",None),("skip_build",False),
                 ("force",False),("target_id",None),
                 ("ym_from","202401"),("ym_to","202512")):
        if not hasattr(a, k): setattr(a, k, v)

    env = load_env(ENV)
    c = conn(env); cur = c.cursor()
    try:
        cur.execute("SELECT 1 FROM meta.load_target WHERE 1=0")
    except Exception:
        sys.exit("meta.load_target 이 없습니다. deploy/sql/30_load_target.sql 을 먼저 적용하세요.")

    signal.signal(signal.SIGINT, _on_sigint)
    # ★ 돌린 것은 전부 파일로 남긴다 (2026-10-17).
    #   사람이 터미널 출력을 복사해 옮기는 것이 병목이었다. logs/ 를 보면
    #   무엇을 돌렸고 무엇이 깨졌는지 알 수 있다.
    with runlog.RunLog(a.cmd) as rl:
        globals()["_RL"] = rl
        try:
            if a.cmd == "go":
                cmd_go(cur, a, env)
            else:
                {"add": cmd_add, "list": cmd_list,
                 "disable": cmd_disable, "plan": cmd_plan}[a.cmd](cur, a)
        finally:
            c.close()


if __name__ == "__main__":
    main()
