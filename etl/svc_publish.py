#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_publish - 적재DB(MSSQL) → 서비스DB(PostgreSQL) 발행 (2026-10-24 23:40, deploy/svc/design.md)

  py svc_publish.py --mode full   --workers 4           아직 안 담긴 단지 전부(이어받기 — 이미 담긴 건 건너뜀)
  py svc_publish.py --mode hourly                       지난 발행 뒤 바뀐 단지만 다시 + 밀린 것 일부
  py svc_publish.py --mode ids --ids 103835 518089      고른 단지만

★ 1단계: 단지 하나로 결과가 정해지는 응답을 **지금 서버(Teomoony-f, 적재DB 를 읽음)가 만드는 JSON 그대로** 받아 gzip 으로 svc.complex_json 에 담는다.
  화면과 값이 같다는 게 처음부터 보장된다(대조가 쉽다). 서버 쪽 캐시를 피하려고 상세는 ?_t=1(진단 시간표 _timing 은 떼고 담음), 나머지는 ?_svcbuild=1.
★ 원문 sha256 이 같으면 안 바꾼다(발행 번호도 그대로) — 바뀐 줄만 바뀐다.
★ 비밀번호 · 키는 화면 · 로그에 안 찍는다.
"""
import argparse, gzip, hashlib, json, os, re, sys, threading, time, urllib.request, urllib.error
from datetime import timezone
from concurrent.futures import ThreadPoolExecutor, as_completed
import pymssql, psycopg

HERE = os.path.dirname(os.path.abspath(__file__))
WEB = "http://127.0.0.1:5173"
ALL_KINDS = ["detail", "geo", "buildings", "history", "usage", "landuse", "landuse-shape", "childcare", "pharmacy", "hira", "closed"]
SMALL_KINDS = ["detail", "geo", "buildings", "history"]      # 세대 적은 단지(단독 · 소형)는 이것만 — 나머지는 열릴 때 적재DB 경로
SMALL_HHLD = 20
TIMING = re.compile(r',"_timing":\{[^{}]*\}')


def env():
    d = {}
    for ln in open(os.path.join(HERE, "..", ".env"), encoding="utf-8"):
        ln = ln.strip()
        if ln and not ln.startswith("#") and "=" in ln:
            k, v = ln.split("=", 1); d[k.strip()] = v.strip().strip('"').strip("'")
    return d


def ms_conn(e):
    return pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)), user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""), database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=True, timeout=0)


def pg_conn(e):
    return psycopg.connect(host="127.0.0.1", port=15432, dbname="teomoony", user="teomoony", password=e["SVC_DB_PASSWORD"], autocommit=False)


def fetch(cid, kind, timeout=180):
    path = f"/api/complexes/{cid}" + ("" if kind == "detail" else f"/{kind}")
    q = "?_t=1" if kind == "detail" else "?_svcbuild=1"
    req = urllib.request.Request(WEB + path + q, headers={"Accept-Encoding": "identity"})
    for a in range(3):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, r.read().decode("utf-8")
        except urllib.error.HTTPError as h:
            body = h.read().decode("utf-8", "replace")
            if h.code in (400, 404): return h.code, body          # 원 서버가 그렇게 답한 것 — 그대로 담는다
            if a == 2: return None, f"HTTP {h.code}"
        except Exception as ex:
            if a == 2: return None, f"{type(ex).__name__}: {str(ex)[:80]}"
        time.sleep(2 * (a + 1))


def one(cid, kind):
    t0 = time.time()
    st, body = fetch(cid, kind)
    if st is None: return cid, kind, None, body, time.time() - t0
    if kind == "detail": body = TIMING.sub("", body, count=1)
    try: json.loads(body)
    except Exception: return cid, kind, None, "JSON 아님", time.time() - t0
    return cid, kind, st, body, time.time() - t0


def sync_list(ms, pg):
    cur = ms.cursor()
    cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT complex_id, ISNULL(hhld_cnt_sum, 0), sigungu_cd, merged_into FROM gold.complex")
    rows = cur.fetchall()
    with pg.cursor() as c:
        c.execute("CREATE TEMP TABLE t_list (LIKE svc.complex_list INCLUDING DEFAULTS) ON COMMIT DROP")
        with c.copy("COPY t_list (complex_id, hhld, sgg_cd, merged_into) FROM STDIN") as cp:
            for r in rows: cp.write_row((r[0], r[1], (r[2] or None), r[3]))
        c.execute("""INSERT INTO svc.complex_list (complex_id, hhld, sgg_cd, merged_into)
                     SELECT complex_id, hhld, sgg_cd, merged_into FROM t_list
                     ON CONFLICT (complex_id) DO UPDATE SET hhld = EXCLUDED.hhld, sgg_cd = EXCLUDED.sgg_cd, merged_into = EXCLUDED.merged_into, updated_at = now()
                     WHERE (svc.complex_list.hhld, svc.complex_list.sgg_cd, svc.complex_list.merged_into) IS DISTINCT FROM (EXCLUDED.hhld, EXCLUDED.sgg_cd, EXCLUDED.merged_into)""")
        c.execute("DELETE FROM svc.complex_list l WHERE NOT EXISTS (SELECT 1 FROM t_list t WHERE t.complex_id = l.complex_id)")
    pg.commit()
    return len(rows)


def kinds_for(hhld):
    return ALL_KINDS if (hhld or 0) >= SMALL_HHLD else SMALL_KINDS


def changed_ids(ms, since):
    """지난 발행(기준선) 뒤 적재DB 에서 바뀐 것 → 단지 번호. 원천 시각 칸이 있는 표만."""
    cur = ms.cursor()
    cur.execute("""SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
      DECLARE @s DATETIME2 = %s;
      SELECT DISTINCT x.complex_id FROM (
        SELECT complex_id = match_complex_id FROM silver.rtms_trade WHERE loaded_at > @s AND match_complex_id IS NOT NULL
        UNION SELECT ck.complex_id FROM silver.kapt_cost k JOIN gold.complex_kapt ck ON ck.kapt_code = k.kapt_code WHERE k.loaded_at > @s
        UNION SELECT cp.complex_id FROM silver.arch_permit a JOIN gold.complex_pnu cp ON cp.pnu = a.pnu WHERE a.valid_from > @s
        UNION SELECT cb.complex_id FROM silver.bld_title t JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = t.mgm_bldrgst_pk WHERE t.valid_from > @s
        UNION SELECT cb.complex_id FROM gold.bld_violation v JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = v.mgm_bldrgst_pk WHERE v.만든때 > @s
        UNION SELECT cp.complex_id FROM gold.change_log g JOIN gold.complex_pnu cp ON cp.pnu = g.키 WHERE g.자료 = N'토지특성' AND g.만든때 > @s
        /* 10-25: 지역 단위 적재(건축물대장 · 인허가 · 공시가격 …)가 끝난 곳 — 시각 칸이 없는 표가 많아서 적재 기록(meta.ingest_run)으로.
           scope_key '41135/10900' = 그 법정동 · '41135/00000' = 그 시군구 전체. 상세의 '받은자료'(시군구 행 수)도 이때 바뀐다 */
        UNION SELECT cp.complex_id FROM meta.ingest_run r
                JOIN gold.complex_pnu cp ON cp.pnu LIKE LEFT(r.scope_key, 5) + CASE WHEN SUBSTRING(r.scope_key, 7, 5) IN ('00000', '') THEN '' ELSE SUBSTRING(r.scope_key, 7, 5) END + '%%'
               WHERE r.status = 'OK' AND r.row_count > 0 AND r.finished_at > @s AND r.scope_key LIKE '[0-9][0-9][0-9][0-9][0-9]%%'
      ) x WHERE x.complex_id IS NOT NULL""", (since,))
    return [r[0] for r in cur.fetchall()]


MARKER_SQL = """SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @cut CHAR(8) = CONVERT(CHAR(8), DATEADD(YEAR, -3, CAST(DATEADD(HOUR, 0, SYSDATETIME()) AS DATE)), 112);
WITH s AS (
  SELECT cid = r.match_complex_id,
         area_grp = CAST(FLOOR(COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar)) AS INT),
         r.deal_amount, r.deal_ymd, r.dealing_gbn,
         rn = ROW_NUMBER() OVER (PARTITION BY r.match_complex_id
                ORDER BY CASE WHEN r.deal_ymd >= @cut THEN 0 ELSE 1 END, CASE WHEN r.deal_ymd >= @cut THEN r.deal_amount END DESC,
                         r.deal_ymd DESC, r.deal_amount DESC, r.trade_sk DESC)
    FROM silver.rtms_trade r
   WHERE r.match_complex_id IS NOT NULL AND r.is_rent = 0 AND r.is_canceled = 0 AND r.deal_amount IS NOT NULL)
SELECT c.complex_id, c.complex_nm, c.rep_plat_plc, CAST(c.has_recap AS INT), c.dong_cnt, c.hhld_cnt_sum,
       CAST(c.centroid_lat AS FLOAT), CAST(c.centroid_lng AS FLOAT), c.trade_cnt, c.rent_cnt,
       s.area_grp, CAST(s.deal_amount AS VARCHAR(30)), s.deal_ymd, s.dealing_gbn, al.실거래이름,
       lawd_cd = LEFT(c.rep_pnu, 10)   -- 10-27 동네 고르기의 단지 수(대표 지번의 법정동 · 동네 목록이 쓰는 것과 같은 기준)
  FROM gold.v_complex_map c
  LEFT JOIN s ON s.cid = c.complex_id AND s.rn = 1
  LEFT JOIN gold.complex_alias al ON al.complex_id = c.complex_id
 WHERE c.centroid_lat IS NOT NULL"""


def publish_markers(ms, pg):
    """지도 마커(단지 점 + 최근 3년 최고가) — 통째로 새 표를 만들어 바꿔 끼운다(읽는 쪽은 옛 표 아니면 새 표만 본다)."""
    t = time.time()
    cur = ms.cursor(); cur.execute(MARKER_SQL); rows = cur.fetchall()
    with pg.cursor() as c:
        c.execute("DROP TABLE IF EXISTS svc.complex_marker_new")
        c.execute("""CREATE TABLE svc.complex_marker_new (
            complex_id int PRIMARY KEY, complex_nm text, rep_plat_plc text, has_recap boolean, dong_cnt int, hhld_cnt_sum int,
            centroid_lat double precision, centroid_lng double precision, trade_cnt int, rent_cnt int,
            area_grp int, max_amount text, max_ymd text, max_dealing text, 실거래이름 text, lawd_cd text)""")
        with c.copy("COPY svc.complex_marker_new FROM STDIN") as cp:
            for r in rows:
                r = list(r); r[3] = bool(r[3]) if r[3] is not None else None
                cp.write_row(r)
        c.execute("CREATE INDEX ix_marker_new_lnglat ON svc.complex_marker_new (centroid_lng, centroid_lat)")
        c.execute("CREATE INDEX ix_marker_new_ord ON svc.complex_marker_new (dong_cnt DESC, hhld_cnt_sum DESC)")
        c.execute("ANALYZE svc.complex_marker_new")
        # ★ 2026-10-27 사장님 "법정동 · 행정동 고를 때 단지 개수도" — **지도에 찍히는 이 마커 표 그대로** 센다(목록 · 지도와 같은 수).
        #   시도 · 시군구 · 읍면동(앞 8자리 — 리 단지도 그 읍·면에 든다) · 리 = 대표 지번의 법정동코드 앞자리.
        #   행정동 = 마커 점이 행정동 경계(SGIS) 안에 드는 것. 이름으로 잇지 않는다. 같이 바꿔 끼운다.
        c.execute("DROP TABLE IF EXISTS svc.area_cnt_new")
        c.execute("CREATE TABLE svc.area_cnt_new (kind text, cd text, n int, PRIMARY KEY (kind, cd))")
        c.execute(r"""INSERT INTO svc.area_cnt_new
            SELECT k, cd, count(*) FROM (
              SELECT 'sido' k, left(lawd_cd, 2) cd FROM svc.complex_marker_new WHERE lawd_cd ~ '^\d{10}$'
              UNION ALL SELECT 'sgg', left(lawd_cd, 5) FROM svc.complex_marker_new WHERE lawd_cd ~ '^\d{10}$'
              UNION ALL SELECT 'emd', left(lawd_cd, 8) || '00' FROM svc.complex_marker_new WHERE lawd_cd ~ '^\d{10}$'
              UNION ALL SELECT 'ri', lawd_cd FROM svc.complex_marker_new WHERE lawd_cd ~ '^\d{10}$' AND right(lawd_cd, 2) <> '00') z
            GROUP BY k, cd""")
        c.execute("SELECT to_regclass('svc.lyr_adm') IS NOT NULL"); 
        if c.fetchone()[0]:
            c.execute("""CREATE TEMP TABLE _adm ON COMMIT DROP AS
                         SELECT adm_cd_sgis cd, ST_SetSRID(ST_GeomFromGeoJSON(geojson), 4326) g FROM svc.lyr_adm WHERE geojson IS NOT NULL""")
            c.execute("CREATE INDEX ON _adm USING gist (g)")
            c.execute("""INSERT INTO svc.area_cnt_new
                         SELECT 'adm', a.cd, count(*) FROM _adm a
                           JOIN svc.complex_marker_new m ON ST_Intersects(a.g, ST_SetSRID(ST_MakePoint(m.centroid_lng, m.centroid_lat), 4326))
                          GROUP BY a.cd ON CONFLICT DO NOTHING""")
        # ★ 2026-10-28 사장님 "실거래 있다고 뜨는데 없어": 실거래 다시 잇기(match_complex_id 만 바뀜)는 changed_ids(loaded_at)에 안 잡힌다 —
        #   마커는 새 값, 상세는 옛 값이 나갔다(김제 대방아파트). 옛 마커와 새 마커의 실거래 칸이 다른 단지를 '상세 다시' 표에 적어 둔다.
        #   표로 남기는 까닭: 마커만 다시 하는 실행(svc_markers_only)이 먼저 돌아도 잃지 않게 — 매시 발행이 꺼내 다시 담고 지운다.
        c.execute("CREATE TABLE IF NOT EXISTS svc.detail_dirty (complex_id int PRIMARY KEY, why text NOT NULL, at timestamptz NOT NULL DEFAULT now())")
        c.execute("SELECT to_regclass('svc.complex_marker') IS NOT NULL")
        if c.fetchone()[0]:
            c.execute("""INSERT INTO svc.detail_dirty (complex_id, why)
                         SELECT n.complex_id, '마커 실거래 칸 바뀜' FROM svc.complex_marker_new n JOIN svc.complex_marker o USING (complex_id)
                          WHERE (n.trade_cnt, n.rent_cnt, n.area_grp, n.max_amount, n.max_ymd) IS DISTINCT FROM (o.trade_cnt, o.rent_cnt, o.area_grp, o.max_amount, o.max_ymd)
                         ON CONFLICT (complex_id) DO UPDATE SET why = EXCLUDED.why, at = now()""")   # 실거래가 먼저(상가 새 판 표시보다)
            print(f"  상세 다시 표에 적음 {c.rowcount:,}(마커 실거래 칸 바뀜)", flush=True)
    pg.commit()
    import psycopg.errors   # 바꿔 끼우기는 짧게 + 잠금 3초 제한(svc_layers 와 같은 이유)
    for 번 in range(20):
        try:
            with pg.cursor() as c:
                c.execute("SET LOCAL lock_timeout = '3s'")
                c.execute("DROP TABLE IF EXISTS svc.complex_marker")
                c.execute("ALTER TABLE svc.complex_marker_new RENAME TO complex_marker")
                c.execute("ALTER INDEX svc.ix_marker_new_lnglat RENAME TO ix_marker_lnglat")
                c.execute("ALTER INDEX svc.ix_marker_new_ord RENAME TO ix_marker_ord")
                c.execute("DROP TABLE IF EXISTS svc.area_cnt")
                c.execute("ALTER TABLE svc.area_cnt_new RENAME TO area_cnt")
                c.execute("ALTER INDEX svc.area_cnt_new_pkey RENAME TO area_cnt_pkey")
            pg.commit(); break
        except psycopg.errors.LockNotAvailable:
            pg.rollback(); time.sleep(5)
    else:
        raise RuntimeError("complex_marker: 바꿔 끼우기 잠금을 못 잡음")
    print(f"  지도 마커 {len(rows):,}곳 · {time.time() - t:.0f}초", flush=True)
    return len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["full", "hourly", "ids", "dirty"], default="hourly")
    ap.add_argument("--ids", nargs="*", type=int)
    ap.add_argument("--ids-file", default="", help="ids: 줄마다 단지 번호 하나(10-28 svc_trade_stale)")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0, help="이번에 담을 단지 수 상한(0 = 없음)")
    ap.add_argument("--dirty", type=int, default=3000, help="hourly 때 '상세 다시' 표에서 몇 개 꺼내나")
    ap.add_argument("--backlog", type=int, default=3000, help="hourly 때 밀린(아직 안 담긴) 단지를 몇 개 더 담나")
    ap.add_argument("--kinds", default="", help="쉼표로 — 비우면 세대 수에 따라")
    ap.add_argument("--rebuild", action="store_true", help="이미 담긴 것도 다시 받는다(full)")
    ap.add_argument("--minutes", type=float, default=0, help="이 시간이 지나면 멈춘다(이어받기)")
    ap.add_argument("--sample", type=int, default=0, help="full: 무작위 N 단지만(속도 재기)")
    ap.add_argument("--markers", action="store_true", help="지도 마커 표도 다시(hourly 는 늘)")
    ap.add_argument("--markers-only", action="store_true")
    ap.add_argument("--layers", action="store_true", help="지도 층도(hourly 는 늘)")
    ap.add_argument("--min-hhld", type=int, default=0, help="full: 세대가 이 이상인 단지만(0-1세대 46만 곳은 열릴 때 적재DB 경로)")
    a = ap.parse_args()
    e = env(); ms = ms_conn(e); pg = pg_conn(e)
    t0 = time.time()
    n_list = sync_list(ms, pg)
    with pg.cursor() as c:
        c.execute("SELECT max(watermark) FROM svc.publish WHERE status = 'ok' AND kind = 'hourly'"); last_wm = c.fetchone()[0]
        c.execute("SELECT now()"); wm = c.fetchone()[0]
        c.execute("INSERT INTO svc.publish (kind, watermark, note) VALUES (%s, %s, %s) RETURNING publish_id", (a.mode, wm, f"단지 목록 {n_list:,}"))
        pid = c.fetchone()[0]
    pg.commit()
    print(f"[{time.strftime('%H:%M:%S')}] 발행 {pid} · {a.mode} · 단지 목록 {n_list:,}", flush=True)
    if a.markers or a.markers_only or a.mode == "hourly":
        publish_markers(ms, pg)
    if a.mode == "hourly" or a.layers:   # 10-25 2단계: 지도 층(필지 · 건물 · 법정동 · 행정동 · 닫힌 대장 · 신축) — 원천이 그대로인 층은 건너뜀
        try:
            import svc_layers; svc_layers.run(ms, pg)
        except Exception as ex:
            pg.rollback(); print(f"  !! 지도 층 실패: {ex}", flush=True)
    if a.markers_only:
        with pg.cursor() as c:
            c.execute("UPDATE svc.publish SET finished_at = now(), status = 'ok', note = note || ' · 마커만' WHERE publish_id = %s", (pid,))
        pg.commit(); return

    # 대상 (단지, 종류) 목록
    with pg.cursor() as c:
        c.execute("SELECT complex_id, hhld, sgg_cd FROM svc.complex_list WHERE merged_into IS NULL")
        info = {r[0]: (r[1], r[2]) for r in c.fetchall()}
        c.execute("SELECT complex_id, kind FROM svc.complex_json"); have = {(r[0], r[1]) for r in c.fetchall()}
    pg.commit()   # 같은 이유(아래 적재DB 질의 · 받기 동안 열어 두지 않게)
    def 순위(cid):   # 세대 많은 단지부터(전국) — 같은 세대 수면 수도권(서울 · 인천 · 경기) 먼저
        # ★ 10-27 전국 단지 657만: 예전 순서(수도권 전부 → 그 밖)면 수도권 단독 수백만 채가 부산 · 대구 큰 아파트보다 앞섰다
        h, s = info.get(cid, (0, None)); return (-(h or 0), 0 if (s or '')[:2] in ('11', '28', '41') else 1, cid)
    want = []
    if a.mode == "ids":
        ids = list(a.ids or [])
        if a.ids_file: ids += [int(x) for x in open(a.ids_file, encoding="utf-8").read().split() if x.strip().isdigit()]
        want = [(cid, k) for cid in ids for k in (a.kinds.split(",") if a.kinds else kinds_for(info.get(cid, (0,))[0]))]
    elif a.mode == "dirty":
        # ★ 10-28 사장님 "너판단으로 ㄱㄱ": '상세 다시' 표를 끝까지 비운다(상가 새 판처럼 많이 쌓인 것) — 실거래 바뀜 먼저 · 그다음 세대 많은 곳.
        #   이미 담긴 상세만(안 담긴 곳은 열릴 때 적재DB 경로가 지금 값으로 답한다). 하다 끊겨도 받은 만큼 표에서 빠져 다음에 이어 한다.
        with pg.cursor() as c:
            c.execute("CREATE TABLE IF NOT EXISTS svc.detail_dirty (complex_id int PRIMARY KEY, why text NOT NULL, at timestamptz NOT NULL DEFAULT now())")
            # ★ 10-29: 적힌 뒤에 이미 다시 담긴 상세(매시 발행이 같은 단지를 먼저 담은 것)는 받지 않고 표에서만 뺀다 — 같은 상세를 두 번 받지 않게
            c.execute("""DELETE FROM svc.detail_dirty d USING svc.complex_json j
                          WHERE j.complex_id = d.complex_id AND j.kind = 'detail' AND j.updated_at > d.at""")
            print(f"  상세 다시 표 — 적힌 뒤 이미 다시 담긴 {c.rowcount:,}곳은 뺌", flush=True)
            rows = c.execute("SELECT complex_id, why = '마커 실거래 칸 바뀜' FROM svc.detail_dirty").fetchall()
        pg.commit()
        담김 = {cid for cid, k in have if k == "detail"}
        먼저 = {cid for cid, t in rows if t}
        ids = sorted([cid for cid, t in rows if cid in info and cid in 담김], key=lambda x: (0 if x in 먼저 else 1, 순위(x)))
        # ★ 10-30: 받을 수 없는 줄은 표에서 뺀다 — 서비스DB 에 상세가 안 담긴 단지(열면 적재DB 경로가 지금 값으로 답한다) ·
        #   단지 목록에 없는 단지(묶이거나 빠짐). 안 빼면 표에 영영 남아 매번 '받을 것 0' 으로 끝났다(10-30 18:50 1,916곳).
        못받음 = [cid for cid, t in rows if not (cid in info and cid in 담김)]
        if 못받음:
            with pg.cursor() as c:
                c.execute("DELETE FROM svc.detail_dirty WHERE complex_id = ANY(%s)", (못받음,))
            pg.commit()
            print(f"  상세 다시 표 — 받을 수 없는 {len(못받음):,}곳은 뺌(안 담긴 상세 · 목록에 없는 단지)", flush=True)
        print(f"  상세 다시 표 {len(rows):,} · 이번에 받을 것 {len(ids):,}(실거래 먼저 {len(먼저 & set(ids)):,})", flush=True)
        if not ids:
            with pg.cursor() as c:
                c.execute("UPDATE svc.publish SET finished_at = now(), status = 'ok', note = note || ' · 상세 다시 표 빔' WHERE publish_id = %s", (pid,))
            # ★ 10-30: 비울 것이 없는 건 정상 — 0 으로 끝낸다(3 이면 작업 감시기가 '적재 실패' 알림을 보냈다 · 10-30 18:50)
            pg.commit(); print("  할 일 없음 — 상세 다시 표가 비었습니다", flush=True); sys.exit(0)
        want = [(cid, "detail") for cid in ids]
    elif a.mode == "full":
        for cid in sorted(info, key=순위):
            if (info[cid][0] or 0) < a.min_hhld: continue
            for k in (a.kinds.split(",") if a.kinds else kinds_for(info[cid][0])):
                if a.rebuild or (cid, k) not in have: want.append((cid, k))
    else:  # hourly
        since = last_wm or wm.replace(hour=0, minute=0, second=0, microsecond=0)
        # ★ 10-25: 적재DB 시각은 UTC(컨테이너 SYSDATETIME) · 기준선은 KST — UTC 로 바꿔 넘긴다(전에는 9시간 앞을 기준으로 봐서 바뀐 게 0건이었다)
        # ★ 이미 서비스DB 에 담긴 단지만 다시 — 안 담긴 곳은 어차피 적재DB 경로가 답하고, 밀린 것(backlog)이 차례로 담는다
        담김 = {cid for cid, k in have if k == "detail"}
        ch_all = changed_ids(ms, since.astimezone(timezone.utc).replace(tzinfo=None))
        ch = [cid for cid in ch_all if cid in info and cid in 담김]
        # 10-28: '상세 다시' 표(마커 실거래 칸이 바뀐 단지) — 세대 많은 곳부터 a.dirty 개까지. 끝나면 받은 것만 지운다(아래)
        with pg.cursor() as c:
            c.execute("SELECT to_regclass('svc.detail_dirty') IS NOT NULL")
            dirty = [r[0] for r in c.execute("SELECT complex_id FROM svc.detail_dirty WHERE why = '마커 실거래 칸 바뀜'").fetchall()] if c.fetchone()[0] else []
        pg.commit()
        dirty = sorted([cid for cid in dirty if cid in info and cid in 담김], key=순위)[: a.dirty]
        chs = set(ch); ch += [cid for cid in dirty if cid not in chs]
        print(f"  상세 다시 표에서 {len(dirty):,}", flush=True)
        # 지나며 담긴 응답(호 상세 · 주변 지점 · 점포 목록)은 그 단지가 바뀌면 지운다 — 다음 요청 때 옛 경로가 새로 답하고 다시 담긴다
        with pg.cursor() as c:
            c.execute("DELETE FROM svc.resp_cache WHERE complex_id = ANY(%s)", (list(ch_all) or [0],))
            print(f"  지나며 담긴 응답 지움 {c.rowcount:,}", flush=True)
        pg.commit()
        want = [(cid, k) for cid in sorted(ch, key=순위) for k in kinds_for(info[cid][0]) if k in ("detail", "history", "usage")]
        밀림 = [(cid, k) for cid in sorted(info, key=순위) for k in kinds_for(info[cid][0]) if (cid, k) not in have][: a.backlog]
        print(f"  바뀐 단지 {len(ch):,}(기준 {since}) · 밀린 것 {len(밀림):,} 더", flush=True)
        want += 밀림
    if a.sample:
        import random
        pick = set(random.sample(sorted({w[0] for w in want}), min(a.sample, len({w[0] for w in want}))))
        want = [w for w in want if w[0] in pick]
    if a.limit: want = want[: a.limit]
    print(f"  받을 것 {len(want):,}", flush=True)

    with pg.cursor() as c:
        c.execute("SELECT complex_id, kind, sha FROM svc.complex_json WHERE complex_id = ANY(%s)", (list({w[0] for w in want}) or [0],))
        old = {(r[0], r[1]): r[2] for r in c.fetchall()}
    pg.commit()   # 10-25: 읽기 뒤 트랜잭션을 닫는다 — 열어 둔 채 받기(수 분)를 하면 서비스DB 가 2분에 끊는다(idle_in_transaction_session_timeout)
    new = chg = same = bad = 0; buf = []; 시간 = {}; 지울 = []
    def 표에서빼기():   # 10-28: 다시 담은 상세는 '상세 다시' 표에서 뺀다 — 이 발행이 시작된 뒤 다시 적힌 것은 남긴다(그건 또 바뀐 것)
        nonlocal 지울
        if not 지울: return
        with pg.cursor() as c:
            c.execute("SELECT to_regclass('svc.detail_dirty') IS NOT NULL")
            if c.fetchone()[0]: c.execute("DELETE FROM svc.detail_dirty WHERE complex_id = ANY(%s) AND at <= %s", (지울, wm))
        pg.commit(); 지울 = []
    def flush():
        nonlocal buf
        if not buf: return
        with pg.cursor() as c:
            c.executemany("""INSERT INTO svc.complex_json (complex_id, kind, status, body_gz, sha, bytes, publish_id, updated_at)
                             VALUES (%s,%s,%s,%s,%s,%s,%s, now())
                             ON CONFLICT (complex_id, kind) DO UPDATE SET status = EXCLUDED.status, body_gz = EXCLUDED.body_gz, sha = EXCLUDED.sha,
                               bytes = EXCLUDED.bytes, publish_id = EXCLUDED.publish_id, updated_at = now()""", buf)
        pg.commit(); buf = []
    끝시각 = t0 + a.minutes * 60 if a.minutes else None
    with ThreadPoolExecutor(a.workers) as ex:
        it = iter(want); 진행 = set()
        def 채우기():
            while len(진행) < a.workers * 2:
                try: w = next(it)
                except StopIteration: return
                진행.add(ex.submit(one, *w))
        채우기(); n = 0
        while 진행:
            done = next(as_completed(진행)); 진행.discard(done)
            cid, kind, st, body, dt = done.result(); n += 1
            시간.setdefault(kind, []).append(dt)
            if st is not None and kind == "detail": 지울.append(cid)
            if st is None:
                bad += 1
                if bad <= 20: print(f"  !! {cid}/{kind}: {body}", flush=True)
            else:
                raw = body.encode("utf-8"); sha = hashlib.sha256(raw).hexdigest()
                o = old.get((cid, kind))
                if o == sha: same += 1
                else:
                    (new if o is None else chg)
                    if o is None: new += 1
                    else: chg += 1
                    buf.append((cid, kind, st, gzip.compress(raw, 6), sha, len(raw), pid))
                    if len(buf) >= 200: flush()
            if n % 500 == 0:
                flush(); 표에서빼기()
                el = time.time() - t0
                print(f"  [{time.strftime('%H:%M:%S')}] {n:,}/{len(want):,} · 새 {new:,} · 바뀜 {chg:,} · 같음 {same:,} · 실패 {bad} · {n/el:.1f}건/초", flush=True)
            if not (끝시각 and time.time() > 끝시각): 채우기()
    flush()
    st = "ok" if bad == 0 or bad < max(10, n * 0.01) else "failed"
    표에서빼기()
    with pg.cursor() as c:
        c.execute("""UPDATE svc.publish SET finished_at = now(), status = %s, rows_new = %s, rows_changed = %s, rows_same = %s, rows_failed = %s,
                     note = note || %s WHERE publish_id = %s""",
                  (st, new, chg, same, bad, f" · 받음 {n:,}/{len(want):,}", pid))
    pg.commit()
    평균 = " · ".join(f"{k} {sum(v)/len(v):.2f}s" for k, v in 시간.items())
    print(f"\n끝 발행 {pid} {st} · 새 {new:,} · 바뀜 {chg:,} · 같음 {same:,} · 실패 {bad} · {time.time()-t0:.0f}초\n  종류별 평균 {평균}", flush=True)
    sys.exit(0 if st == "ok" else 1)


if __name__ == "__main__":
    main()
