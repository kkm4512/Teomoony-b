#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svc_pub_urls - 주소 단위 응답을 서비스DB 로 미리 담는다 (2026-11-01, 서비스DB 분리 1묶음)
  py svc_pub_urls.py                 # 모든 묶음(지문이 같으면 건너뜀)
  py svc_pub_urls.py --only areas,redev_detail --force areas
★ 단지 상세(svc_publish)와 같은 방식: **같은 서버 · 같은 주소**에서 받은 몸을 그대로 담는다(?_svcbuild=1 로 서비스DB 길을 비켜 적재DB 경로가 답하게).
  → 화면과 값이 같다는 게 처음부터 보장된다. 담는 키 = 경로 + 물음표 칸을 이름순으로 세운 것(svc.js 공개응답이 같은 규칙으로 찾는다).
★ 묶음마다 '키 목록 SQL'(적재DB) 로 주소를 다 만든다 → 새 목록에 없는 옛 주소는 지운다(그 묶음 것만).
★ 400 · 404 도 원 서버가 그렇게 답한 것이라 그대로 담는다. 5xx · 끊김은 담지 않는다(옛 값을 남김)."""
import argparse, gzip, hashlib, json, sys, time, urllib.parse, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
from svc_publish import env, ms_conn, pg_conn, WEB

U = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;\n"
# (묶음, 지문 SQL(None = 매번), 키 SQL(줄마다 주소 하나 — 첫 칸), 일꾼 수)
SETS = [
  ("areas", """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(lawd_cd, sido_nm, sgg_nm, emd_nm, ri_nm, is_abolished))) FROM meta.lawd_code), '|',
                         (SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.lawd_boundary), '|',
                         (SELECT CONCAT(COUNT_BIG(*), '/', MAX(year)) FROM silver.adm_boundary), '|',
                         (SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.ri_boundary), '|',
                         (SELECT COUNT_BIG(*) FROM gold.complex))""",
   U + """SELECT u = '/api/areas/sido'
          UNION ALL SELECT DISTINCT '/api/areas/sgg?sido=' + sido_cd FROM meta.lawd_code WHERE sgg_nm IS NULL AND emd_nm IS NULL AND ri_nm IS NULL AND is_abolished = 0
          UNION ALL SELECT DISTINCT '/api/areas/dongs?kind=' + k.k + '&sgg=' + l.sgg_cd FROM meta.lawd_code l CROSS JOIN (VALUES ('lawd'), ('adm')) k(k)
                     WHERE l.sgg_nm IS NOT NULL AND l.emd_nm IS NULL AND l.ri_nm IS NULL AND l.is_abolished = 0 AND l.sgg_cd IS NOT NULL
          UNION ALL SELECT DISTINCT '/api/areas/dongs?sgg=' + l.sgg_cd FROM meta.lawd_code l
                     WHERE l.sgg_nm IS NOT NULL AND l.emd_nm IS NULL AND l.ri_nm IS NULL AND l.is_abolished = 0 AND l.sgg_cd IS NOT NULL
          UNION ALL SELECT DISTINCT '/api/areas/ris?emd=' + LEFT(lawd_cd, 8) + '00' FROM meta.lawd_code WHERE ri_nm IS NOT NULL AND is_abolished = 0""", 4),
  ("coverage", None, "SELECT u = '/api/coverage'", 1),
  ("redev_detail", "SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to), '/', (SELECT COUNT_BIG(*) FROM silver.applyhome_pblanc), '/', (SELECT COUNT_BIG(*) FROM gold.redev_plan_link), '/', (SELECT COUNT_BIG(*) FROM gold.complex)) FROM silver.redev_zone",
   U + """SELECT '/api/redev/' + present_sn + '/detail' FROM silver.redev_zone WHERE is_current = 1
          UNION ALL SELECT '/api/redev/' + present_sn FROM silver.redev_zone WHERE is_current = 1""", 3),
]


def 키(u):
    """주소 → 담는 키: 경로 + 물음표 칸 이름순(_svc* · _t 는 뺌). svc.js 공개응답의 키()와 같아야 한다."""
    p = urllib.parse.urlsplit(u)
    q = sorted((k, v) for k, v in urllib.parse.parse_qsl(p.query, keep_blank_values=True) if not k.startswith("_svc") and k != "_t")
    return p.path + ("?" + urllib.parse.urlencode(q, quote_via=urllib.parse.quote) if q else "")


def 받기(u, timeout=180):
    sep = "&" if "?" in u else "?"
    req = urllib.request.Request(WEB + u + sep + "_svcbuild=1", headers={"Accept-Encoding": "identity"})
    for a in range(3):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as h:
            if h.code in (400, 404): return h.code, h.read()
            if a == 2: return None, None
        except Exception:
            if a == 2: return None, None
        time.sleep(2 * (a + 1))


def run_set(ms, pg, name, fp_sql, key_sql, workers, force):
    with pg.cursor() as c:
        c.execute("SELECT fingerprint FROM svc.pub_state WHERE name = %s", (name,)); r = c.fetchone()
    fp = None
    if fp_sql:
        cur = ms.cursor(); cur.execute(fp_sql); fp = str(cur.fetchone()[0])
        if r and r[0] == fp and not force:
            print(f"  {name}: 원천 그대로 — 건너뜀", flush=True); return
    cur = ms.cursor(); cur.execute(key_sql)
    while cur.description is None and cur.nextset(): pass
    urls = sorted({row[0] for row in cur.fetchall() if row[0]})
    t = time.time(); 담음 = 실패 = 0; 키들 = set()

    def 하나(u):
        st, body = 받기(u)
        return u, st, body
    with ThreadPoolExecutor(max_workers=workers) as ex:
        for u, st, body in ex.map(하나, urls):
            k = 키(u); 키들.add(k)
            if st is None: 실패 += 1; continue
            try:
                j = json.loads(body.decode("utf-8"))
                if st == 200 and isinstance(j, dict) and j.get("error"): 실패 += 1; continue
            except Exception:
                실패 += 1; continue
            gz = gzip.compress(body, 6)
            with pg.cursor() as c:
                c.execute("""INSERT INTO svc.resp_pub (url, set_name, status, body_gz, sha, bytes, at) VALUES (%s, %s, %s, %s, %s, %s, now())
                             ON CONFLICT (url) DO UPDATE SET set_name = EXCLUDED.set_name, status = EXCLUDED.status, body_gz = EXCLUDED.body_gz,
                                                             sha = EXCLUDED.sha, bytes = EXCLUDED.bytes,
                                                             at = CASE WHEN svc.resp_pub.sha = EXCLUDED.sha THEN svc.resp_pub.at ELSE now() END""",
                          (k, name, st, gz, hashlib.sha256(body).hexdigest(), len(body)))
            pg.commit(); 담음 += 1
    지움 = 0
    if not 실패:   # 다 받았을 때만 옛 주소를 지운다(일부 실패면 옛 값을 남긴다)
        with pg.cursor() as c:
            c.execute("SELECT url FROM svc.resp_pub WHERE set_name = %s", (name,))
            옛 = [x[0] for x in c.fetchall() if x[0] not in 키들]
            if 옛: c.execute("DELETE FROM svc.resp_pub WHERE url = ANY(%s)", (옛,)); 지움 = len(옛)
        pg.commit()
    with pg.cursor() as c:
        c.execute("""INSERT INTO svc.pub_state VALUES (%s, %s, %s, %s, now(), %s)
                     ON CONFLICT (name) DO UPDATE SET fingerprint = EXCLUDED.fingerprint, urls = EXCLUDED.urls, failed = EXCLUDED.failed,
                                                      built_at = EXCLUDED.built_at, secs = EXCLUDED.secs""",
                  (name, fp if not 실패 else None, len(urls), 실패, time.time() - t))
    pg.commit()
    print(f"  {name}: 주소 {len(urls):,} · 담음 {담음:,} · 실패 {실패:,} · 지움 {지움:,} · {time.time() - t:.0f}초", flush=True)


def run(ms, pg, only=(), force=()):
    with pg.cursor() as c:
        c.execute("""CREATE TABLE IF NOT EXISTS svc.resp_pub (url text PRIMARY KEY, set_name text NOT NULL, status int NOT NULL,
                     body_gz bytea NOT NULL, sha text, bytes int, at timestamptz NOT NULL DEFAULT now())""")
        c.execute("CREATE INDEX IF NOT EXISTS ix_resp_pub_set ON svc.resp_pub (set_name)")
        c.execute("""CREATE TABLE IF NOT EXISTS svc.pub_state (name text PRIMARY KEY, fingerprint text, urls int, failed int,
                     built_at timestamptz, secs real)""")
    pg.commit()
    for name, fp_sql, key_sql, w in SETS:
        if only and name not in only: continue
        run_set(ms, pg, name, fp_sql, key_sql, w, name in force or "all" in force)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=""); ap.add_argument("--force", default="")
    a = ap.parse_args()
    e = env(); ms = ms_conn(e); pg = pg_conn(e)
    t = time.time()
    run(ms, pg, set(filter(None, a.only.split(","))), set(filter(None, a.force.split(","))))
    print(f"주소 묶음 끝 · {time.time() - t:.0f}초")


if __name__ == "__main__":
    main()
