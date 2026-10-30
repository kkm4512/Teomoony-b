#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""hub_month - 건축물대장 월 갱신(건축HUB 대용량 전국 파일 · 익월 20일) — **바뀐 대장만** (2026-10-28 사장님 "1 ㄱㄱ")
  py hub_month.py                 (수집 일정 '건축물대장 월 갱신' · 매월 22일 02:00) · 새 달이 없으면 종료코드 3
  py hub_month.py --month 202610  (그 달만 · 이어하기)
  ① 새 달 확인 — 허브 목록에 우리가 넣은 달(hub.month_done)보다 뒤 달이 7종 다 있나
  ② 받기 — 대장 뼈대 7종(기본개요 · 총괄표제부 · 표제부 · 층별개요 · 부속지번 · 전유부 · 지역지구구역) + 건축인허가 기본개요 · 동별개요(10-28) · hub_bulk.py
  ③ 버전 표에 얹기 — load_hub.py(같은 줄은 그대로 · 바뀐 줄은 새 줄 · 사라진 줄은 닫음 = 원본 그대로의 월별 버전) · 층별개요는 hub_latest(구획 줄 그대로)도
  ④ 바뀐 대장 PK = 이번 달에 새로 생긴 줄 + 이번 달에 사라진 줄(hub.month_chg 에 남김)
  ⑤ 우리 대장 표(silver.bld_*) — 그 PK 만: 지금 줄을 닫고(is_current = 0 · valid_to) 허브 뷰(hubv)의 지금 줄을 넣는다. **지우지 않는다**(이력이 남는다)
  ⑥ 바뀐 시군구만 단지 구성(gold.usp_build_complexes) → K-apt 연결 · 좌표 한 번 → 실거래 재매칭 → 서비스DB '상세 다시' → 단지 조각 묶기(정책 2-1)
  ★ 공동주택가격(0308) · 전유공용면적(0306)은 여기 없다 — 달마다 5.9GB · 3.3GB 이고 값은 해마다(공시 4월 말) 바뀐다 → 따로(연 1회).
  ★ 단계마다 _hub_month_state.json 에 적어 끊기면 거기서 잇는다. 한 단계라도 실패하면 멈춘다(다음 단계로 안 간다)."""
import argparse, glob, json, os, shutil, subprocess, sys, time
from svc_publish import env, ms_conn, pg_conn
from load_hub import SPEC
HERE = os.path.dirname(os.path.abspath(__file__)); py = sys.executable
STATE = os.path.join(HERE, "_hub_month_state.json")
ROOT = os.path.join(HERE, "..", "deploy", "bulk", "hub")
CODES = {"0301": "bld_basis_outline", "0302": "bld_recap_title", "0303": "bld_title", "0304": "bld_flr_outline",
         "0305": "bld_atch_jibun", "0309": "bld_expos", "0310": "bld_jijigu",
         # ★ 10-28: 건축인허가 기본개요 · 동별개요도(379 · pms_swap 으로 전국 허브판이 됨) — 열쇠 칸이 대장과 다르다
         "0101": "arch_permit", "0102": "arch_permit_dong"}
HUBKEY = {"0101": "관리_허가대장_PK", "0102": "관리_동별_개요_PK"}          # 그 밖은 관리_건축물대장_PK
SKEY = {"0101": "mgm_pmsrgst_pk", "0102": "mgm_dong_ouln_pk"}              # 그 밖은 mgm_bldrgst_pk
CAT = lambda c: SPEC[c]["분류"]
def log(*a): print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)
def run(*a):
    log("$", " ".join(a)); r = subprocess.run([py, *a], cwd=HERE)
    if r.returncode != 0: sys.exit(f"✘ {a[0]} 실패(종료코드 {r.returncode}) — 여기서 멈춤(다시 돌리면 이 단계부터)")
def st_get():
    try: return json.load(open(STATE, encoding="utf-8"))
    except Exception: return {}
def st_put(month, step):
    s = st_get(); s[month] = step; json.dump(s, open(STATE, "w", encoding="utf-8"), ensure_ascii=False)

ap = argparse.ArgumentParser(); ap.add_argument("--month"); a = ap.parse_args()
cur = ms_conn(env()).cursor()
cur.execute("SELECT MAX(월) FROM hub.month_done WHERE code = '0303'"); last = cur.fetchone()[0]
if a.month: M = a.month
else:
    # ① 허브 목록(hub_bulk --list 는 _export/hub_items.json 을 새로 쓴다)
    run("hub_bulk.py", "--list", "--cat", "건축물대장", "건축인허가")
    items = json.load(open(os.path.join(HERE, "_export", "hub_items.json"), encoding="utf-8"))
    names = {(CAT(c), SPEC[c]["이름"]) for c in CODES}
    by = {}
    for i in items:
        if i["월"] and (i["cat"], i["이름"]) in names: by.setdefault(i["월"], set()).add((i["cat"], i["이름"]))
    new = sorted(m for m, s in by.items() if m > (last or "") and s >= names)
    log(f"우리 마지막 달 {last} · 허브 목록의 달 {sorted(by)} · 새 달 {new}")
    if not new: log("출처에 새 것 없음"); sys.exit(3)
    M = new[0]   # 한 번에 한 달(밀렸으면 다음 실행이 다음 달)
step = st_get().get(M, "")
prev = last if (last or "") < M else None
log(f"달 {M} · 앞 달 {prev} · 지난번 끝낸 단계 '{step or '없음'}'")
free = shutil.disk_usage(HERE).free / 2**30
if free < 40 and step in ("", "받기"): log(f"C 남은 {free:.0f}GB < 40GB — 건너뜀"); sys.exit(3)

if step == "":
    for cat in sorted({CAT(c) for c in CODES}):
        run("hub_bulk.py", "--cat", cat, "--only", *sorted({SPEC[c]["이름"] for c in CODES if CAT(c) == cat}), "--month", f"{M[:4]}-{M[4:]}", "--workers", "3")
    st_put(M, "받기"); step = "받기"
if step == "받기":
    for c in CODES: run("load_hub.py", "--code", c, "--month", M)
    run("hub_latest.py", "--code", "0304", "--month", M)      # 층별개요 뷰(hubv.bld_flr_outline)가 읽는 구획 줄 그대로
    for z in glob.glob(os.path.join(ROOT, M, "*.zip")): os.remove(z)   # 원본 zip 은 다음 달 목록에서 다시 받을 수 있다(3개월) — 디스크
    st_put(M, "얹기"); step = "얹기"
if step == "얹기":
    cur.execute("""IF OBJECT_ID('hub.month_chg') IS NULL
                   CREATE TABLE hub.month_chg (월 CHAR(6) NOT NULL, code CHAR(4) NOT NULL, pk NVARCHAR(33) NOT NULL, CONSTRAINT pk_hub_month_chg PRIMARY KEY (월, code, pk))""")
    cur.execute("DELETE FROM hub.month_chg WHERE 월 = %s", (M,))
    for c in CODES:
        hk = HUBKEY.get(c, "관리_건축물대장_PK")
        cur.execute(f"""INSERT hub.month_chg (월, code, pk)
                        SELECT DISTINCT %s, %s, [{hk}] FROM hub.t{c}
                         WHERE [{hk}] IS NOT NULL AND (처음월 = %s OR 마지막월 = %s)""", (M, c, M, prev or "000000"))
        log(f"  {c} {SPEC[c]['이름']}: 바뀐 대장 {cur.rowcount:,}")
    st_put(M, "바뀐것"); step = "바뀐것"
if step == "바뀐것":
    for c, t in CODES.items():
        st = time.time()
        cur.execute(f"SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('silver.{t}') AND c.is_identity = 0 ORDER BY c.column_id")
        cl = ", ".join(f"[{r[0]}]" for r in cur.fetchall())
        cur.execute(f"""SET XACT_ABORT ON; BEGIN TRAN;
            UPDATE s SET is_current = 0, valid_to = SYSDATETIME()
              FROM silver.{t} s JOIN hub.month_chg g ON g.월 = %s AND g.code = %s AND g.pk = s.{SKEY.get(c, "mgm_bldrgst_pk")}
             WHERE s.is_current = 1;
            DECLARE @닫음 INT = @@ROWCOUNT;
            INSERT INTO silver.{t} ({cl})
            SELECT {cl} FROM hubv.{t} v WHERE v.{SKEY.get(c, "mgm_bldrgst_pk")} IN (SELECT pk FROM hub.month_chg WHERE 월 = %s AND code = %s) OPTION (MAXDOP 4);
            DECLARE @넣음 INT = @@ROWCOUNT;
            COMMIT; SELECT @닫음, @넣음;""", (M, c, M, c))
        n1, n2 = cur.fetchone()
        log(f"  silver.{t}: 옛 줄 닫음 {n1:,} · 새 줄 {n2:,} · {time.time()-st:.0f}초")
    cur.execute("IF OBJECT_ID('hub.l0304') IS NOT NULL DROP TABLE hub.l0304")   # 파생(파일에서 다시 만들 수 있음) — 디스크
    st_put(M, "대장"); step = "대장"
if step == "대장":
    cur.execute("""SELECT DISTINCT b.sigungu_cd FROM silver.bld_basis_outline b
                    WHERE b.mgm_bldrgst_pk IN (SELECT pk FROM hub.month_chg WHERE 월 = %s AND code LIKE '03%%') AND b.sigungu_cd IS NOT NULL ORDER BY 1""", (M,))
    sggs = [r[0] for r in cur.fetchall()]
    sf = os.path.join(HERE, "_hub_month_sgg.txt"); open(sf, "w").write("\n".join(sggs) + "\n")
    log(f"바뀐 시군구 {len(sggs)}")
    run("gold_nation.py", "--sgg-file", sf, "--done-file", os.path.join(HERE, f"_hub_month_gold_{M}.txt"))
    st_put(M, "단지"); step = "단지"
if step == "단지":
    run("load_rtms.py", "--rematch-only")
    st_put(M, "실거래"); step = "실거래"
if step == "실거래":
    cur.execute("""SELECT cb.complex_id FROM gold.complex_bld cb
                    WHERE cb.mgm_bldrgst_pk IN (SELECT pk FROM hub.month_chg WHERE 월 = %s AND code LIKE '03%%')
                   UNION SELECT cp.complex_id FROM gold.complex_pnu cp     -- 10-28: 인허가가 바뀐 필지의 단지(상세의 인허가 칸)
                    WHERE cp.pnu IN (SELECT a.pnu FROM silver.arch_permit a WHERE a.mgm_pmsrgst_pk IN (SELECT pk FROM hub.month_chg WHERE 월 = %s AND code = '0101'))""", (M, M))
    ids = [r[0] for r in cur.fetchall()]
    pg = pg_conn(env())
    with pg.cursor() as c:
        c.execute("CREATE TABLE IF NOT EXISTS svc.detail_dirty (complex_id int PRIMARY KEY, why text NOT NULL, at timestamptz NOT NULL DEFAULT now())")
        c.execute("INSERT INTO svc.detail_dirty (complex_id, why) SELECT x, %s FROM unnest(%s::int[]) x ON CONFLICT (complex_id) DO NOTHING", (f"대장 월 갱신 {M}", ids or [0]))
        c.execute("DELETE FROM svc.resp_cache WHERE complex_id = ANY(%s)", (ids or [0],))
    pg.commit(); log(f"서비스DB '상세 다시' 표에 {len(ids):,} 단지")
    st_put(M, "서비스"); step = "서비스"
if step == "서비스":
    r = subprocess.run([py, "merge_frag_cron.py"], cwd=HERE)
    if r.returncode not in (0, 3): sys.exit(f"✘ 단지 조각 묶기 실패(종료코드 {r.returncode})")
    # 10-30: 주택인허가(사업계획승인) 새 달 → 지도 '승인' 핀(gold.house_plan). 실패해도 대장 갱신은 끝난 것 — 기록만 남긴다
    r = subprocess.run([py, "house_permit_load.py"], cwd=HERE)
    if r.returncode: log(f"! 주택인허가 갱신 실패(종료코드 {r.returncode}) — 다음 달에 다시")
    st_put(M, "끝")
log(f"끝 — {M}")
