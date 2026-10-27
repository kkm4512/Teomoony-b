# -*- coding: utf-8 -*-
"""hub_swap - 허브 뷰(hubv.bld_*)를 우리 대장 표와 같은 모양의 진짜 표로 만들고(silver.<표>__hub) 같은 색인을 붙인 뒤 이름을 바꿔 끼운다 (2026-10-25)
  사장님 "너 말한대로 ㄱㄱ" — 뷰를 바로 쓰면 지번·관리번호로 바로 못 찾아 느리다 → 한 번 만들어 같은 색인.
  py hub_swap.py build [표 …]     __hub 표 만들기(기존 silver 는 건드리지 않음)
  py hub_swap.py check            줄 수 · 색인 비교
  py hub_swap.py swap             silver.<표> → <표>_api(남겨 둠) · <표>__hub → <표>   (되돌리기: py hub_swap.py back)
  ★ _api 표는 지우지 않는다(기록). __hub 는 파생이라 다시 만들 수 있다."""
import sys, time
from svc_publish import env, ms_conn
TABLES = ["bld_recap_title", "bld_atch_jibun", "bld_jijigu", "bld_title", "bld_flr_outline", "bld_expos", "bld_basis_outline", "bld_expos_pubuse_area", "bld_hsprc"]
WIDE = {"bld_flr_outline": ["etc_purps", "etc_strct"], "bld_expos_pubuse_area": ["etc_purps", "etc_strct"]}   # 이어 붙인 글자 — 넉넉히

def log(*a): print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)

def typ(r):
    dt, ln, pr, sc, dp = r
    if dt in ("varchar", "nvarchar", "char", "nchar", "varbinary", "binary"): return f"{dt}({'MAX' if ln == -1 else ln})"
    if dt in ("decimal", "numeric"): return f"{dt}({pr},{sc})"
    if dt in ("datetime2", "time", "datetimeoffset"): return f"{dt}({dp})"
    return dt

# ★ 2026-10-26 전유공용(hub.l0306 1억 1천만 줄)을 한 문장으로 넣다가 정렬이 tempdb 를 수백 GB 로 키워 C 드라이브가 가득 찼다(DB 멈춤).
#   → 관리PK 순으로 잘라 넣는다(한 번에 CHUNK 줄). 묶는 열쇠가 관리PK 로 시작하므로 한 건물이 두 조각으로 갈리지 않는다.
#   끊겨도 이어받는다(--resume: 이미 넣은 마지막 관리PK 다음부터 — 조각 하나는 한 문장이라 반쯤 들어가는 일이 없다).
CHUNKED = {"bld_expos_pubuse_area": "hub.l0306", "bld_flr_outline": "hub.l0304"}
CHUNK = 2_000_000
RESUME = "--resume" in sys.argv

def build(cur, t):
    t0 = time.time()
    if RESUME and t in CHUNKED:
        cur.execute(f"SELECT OBJECT_ID('silver.{t}__hub')")
        if cur.fetchone()[0]:
            return fill_chunked(cur, t, t0, resume=True)
    cur.execute(f"IF OBJECT_ID('silver.{t}__hub') IS NOT NULL DROP TABLE silver.{t}__hub")
    cur.execute(f"SELECT TOP 0 * INTO silver.{t}__hub FROM silver.{t}")
    cur.execute(f"""SELECT c.name, TYPE_NAME(c.user_type_id), c.max_length, c.precision, c.scale, c.scale, c.is_nullable, c.is_identity
                      FROM sys.columns c WHERE c.object_id = OBJECT_ID('silver.{t}__hub') ORDER BY c.column_id""")
    cols = cur.fetchall()
    for n, dt, ml, pr, sc, dp, nul, ide in cols:
        ln = ml if ml == -1 or dt not in ("nvarchar", "nchar") else ml // 2
        if n in WIDE.get(t, []):
            cur.execute(f"ALTER TABLE silver.{t}__hub ALTER COLUMN [{n}] NVARCHAR(4000) NULL")
        elif not nul and not ide:
            cur.execute(f"ALTER TABLE silver.{t}__hub ALTER COLUMN [{n}] {typ((dt, ln, pr, sc, dp))} NULL")
    if t in CHUNKED:
        return fill_chunked(cur, t, t0)
    names = [c[0] for c in cols if not c[7]]
    cl = ", ".join(f"[{n}]" for n in names)
    log(f"{t}: 넣는 중 ({len(names)}칸)")
    cur.execute(f"INSERT INTO silver.{t}__hub WITH (TABLOCK) ({cl}) SELECT {cl} FROM hubv.{t} OPTION (MAXDOP 4)")
    indexes(cur, t, t0)

def fill_chunked(cur, t, t0, resume=False):
    src = CHUNKED[t]
    cur.execute(f"SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('silver.{t}__hub') AND c.is_identity = 0 ORDER BY c.column_id")
    cl = ", ".join(f"[{r[0]}]" for r in cur.fetchall())
    last = ""
    if resume:
        cur.execute(f"SELECT MAX(mgm_bldrgst_pk), COUNT_BIG(*) FROM silver.{t}__hub"); last, n0 = cur.fetchone(); last = last or ""
        log(f"{t}: 이어받기 — 이미 {n0:,}줄 · 마지막 관리PK {last}")
    else:
        log(f"{t}: 관리PK 순으로 {CHUNK:,}줄씩")
        cur.execute(f"INSERT INTO silver.{t}__hub ({cl}) SELECT {cl} FROM hubv.{t} WHERE mgm_bldrgst_pk IS NULL")
    k = 0
    while True:
        cur.execute(f"SELECT MAX(x.k) FROM (SELECT TOP {CHUNK} [관리_건축물대장_PK] AS k FROM {src} WHERE [관리_건축물대장_PK] > %s ORDER BY [관리_건축물대장_PK]) x", (last,))
        hi = cur.fetchone()[0]
        if hi is None: break
        st = time.time()
        cur.execute(f"INSERT INTO silver.{t}__hub ({cl}) SELECT {cl} FROM hubv.{t} WHERE mgm_bldrgst_pk > %s AND mgm_bldrgst_pk <= %s OPTION (MAXDOP 4)", (last, hi))
        k += 1; log(f"   조각 {k} · ~{hi} · {cur.rowcount:,}줄 · {time.time()-st:.0f}초"); last = hi
    indexes(cur, t, t0)

def indexes(cur, t, t0):
    cur.execute(f"SELECT COUNT_BIG(*) FROM silver.{t}__hub"); n = cur.fetchone()[0]
    log(f"{t}: {n:,}줄 · {time.time()-t0:.0f}초 — 색인")
    cur.execute(f"""SELECT i.name, i.type_desc, i.is_primary_key, i.is_unique, i.filter_definition,
          (SELECT STRING_AGG('[' + c.name + ']' + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE '' END, ',') WITHIN GROUP (ORDER BY ic.key_ordinal) FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0),
          (SELECT STRING_AGG('[' + c.name + ']', ',') FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1)
          FROM sys.indexes i WHERE i.object_id = OBJECT_ID('silver.{t}') AND i.type > 0 ORDER BY i.type, i.name""")
    for nm, td, pk, uq, flt, kc, inc in cur.fetchall():
        cur.execute(f"SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('silver.{t}__hub') AND name IN (%s, %s)", (nm, nm + "_h"))
        if cur.fetchone()[0]:
            log(f"   {nm} · 이미 있음"); continue
        t1 = time.time()
        if pk:
            sql = f"ALTER TABLE silver.{t}__hub ADD CONSTRAINT [{nm}_h] PRIMARY KEY {td} ({kc}) WITH (DATA_COMPRESSION = PAGE, MAXDOP = 4)"
        else:
            sql = (f"CREATE {'UNIQUE ' if uq else ''}{td} INDEX [{nm}] ON silver.{t}__hub ({kc})" + (f" INCLUDE ({inc})" if inc else "") +
                   (f" WHERE {flt}" if flt else "") + " WITH (DATA_COMPRESSION = PAGE, MAXDOP = 4)")
        try:
            cur.execute(sql); log(f"   {nm} · {time.time()-t1:.0f}초")
        except Exception as ex:
            log(f"   ✘ {nm}: {str(ex)[:300]}")
    log(f"{t}: 끝 · {time.time()-t0:.0f}초")

def check(cur):
    bad = []
    for t in TABLES:
        cur.execute(f"""SELECT (SELECT COUNT_BIG(*) FROM silver.{t} WHERE is_current = 1),
                               (SELECT COUNT_BIG(*) FROM silver.{t}__hub) ,
                               (SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('silver.{t}') AND type > 0),
                               (SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('silver.{t}__hub') AND type > 0)""")
        a, b, i1, i2 = cur.fetchone()
        log(f"{t}: 지금(API) {a:,} · 허브 {b:,} · 색인 {i1}/{i2}{'' if i1 == i2 else '  ✘ 색인 모자람'}")
        if i1 != i2 or b < a: bad.append(t)   # 허브가 API 보다 줄이 적으면(허브는 전국이라 더 많아야 한다) 바꿔 끼우지 않는다
    if bad: sys.exit("✘ 바꿔 끼우기 전에 볼 것: " + ", ".join(bad))

def swap(cur, back=False):
    cur.execute("SET LOCK_TIMEOUT 10000")
    for k in range(5):
        try:
            cur.execute("BEGIN TRAN")
            for t in TABLES:
                if not back:
                    cur.execute(f"EXEC sp_rename 'silver.{t}', '{t}_api'")
                    cur.execute(f"EXEC sp_rename 'silver.{t}__hub', '{t}'")
                else:
                    cur.execute(f"EXEC sp_rename 'silver.{t}', '{t}__hub'")
                    cur.execute(f"EXEC sp_rename 'silver.{t}_api', '{t}'")
            cur.execute("COMMIT"); log("바꿔 끼움 끝" if not back else "되돌림 끝"); return
        except Exception as ex:
            try: cur.execute("IF @@TRANCOUNT > 0 ROLLBACK")
            except Exception: pass
            log(f"잠금 기다림 실패 {k+1}/5: {str(ex)[:200]}"); time.sleep(20)
    sys.exit("바꿔 끼우기 실패 — 그대로 둠")

if __name__ == "__main__":
    ms = ms_conn(env()); ms.autocommit(True); cur = ms.cursor()
    cur.execute("SELECT recovery_model_desc FROM sys.databases WHERE database_id = DB_ID()"); log("복구 모델", cur.fetchone()[0])
    op = sys.argv[1]
    if op == "build":
        import os, subprocess
        h = os.path.dirname(os.path.abspath(__file__))
        if subprocess.call([sys.executable, "ms_q.py", os.path.join("..", "deploy", "sql", "353_hub_views.sql")], cwd=h) != 0: sys.exit("뷰 적용 실패")
        for t in ([x for x in sys.argv[2:] if not x.startswith("--")] or TABLES): build(cur, t)
        check(cur)
    elif op == "index":   # 2026-10-26 표는 다 넣었는데 색인 도중 끊겼을 때(디스크 압축으로 DB 를 내림) — 넣은 줄은 두고 없는 색인만
        for t in [x for x in sys.argv[2:] if not x.startswith("--")]: indexes(cur, t, time.time())
    elif op == "check": check(cur)
    elif op == "swap": swap(cur)
    elif op == "back": swap(cur, back=True)
