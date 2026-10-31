# -*- coding: utf-8 -*-
"""apply_region_1031 - 법정동·행정동 마스터(395~398)를 PC 적재DB 에 한 번에 반영 (2026-10-31, 클라우드 시험 공간에서 검증한 것)
  python apply_region_1031.py

  1 SQL 395(행안부 코드 원문 표) · 396(이름 · 옛→지금) · 397(행정동 경계 공식 연결) · 398(매주 일정) 을 차례로
  2 행안부 말소코드 포함판 넣기 — data/region_code/jscode*_malso.zip 중 가장 새 것(없으면 게시판에서 받음: mois_jscode_watch.py)
  3 EXEC gold.usp_build_bdong_succ · gold.usp_build_adm_link
  4 서비스DB 층 다시 발행: adm(행정동 경계) · sg_adm(자동완성 행정동) — --force
  5 확인 숫자 출력
★ 원본 표는 건드리지 않는다. 새 표(silver.mois_* · gold.bdong_succ_code · gold.complex_lawd_now · gold.adm_link)와 뷰만 만든다.
★ 웹 코드(Teomoony-f)는 이 다음에 받는다 — 웹이 새 뷰를 먼저 찾으면 /r 쪽이 깨진다.
"""
import glob, os, re, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from svc_publish import env, ms_conn
SQL = os.path.join(HERE, "..", "deploy", "sql")


def 돌리기(cur, 파일):
    t0 = time.time()
    for b in re.split(r"^\s*GO\s*$", open(os.path.join(SQL, 파일), encoding="utf-8").read(), flags=re.M | re.I):
        if not b.strip(): continue
        cur.execute(b)
        while True:
            if cur.description:
                for r in cur.fetchall(): print("   ", r)
            if not cur.nextset(): break
    print(f"  {파일} · {time.time() - t0:.0f}초", flush=True)


def main():
    cur = ms_conn(env()).cursor()
    for f in ("395_mois_jscode.sql", "396_bdong_succ.sql", "397_adm_link.sql", "398_schedule_mois_jscode.sql"):
        돌리기(cur, f)
    zs = sorted(glob.glob(os.path.join(HERE, "..", "data", "region_code", "jscode*_malso.zip")))
    if zs:
        r = subprocess.run([sys.executable, os.path.join(HERE, "load_mois_jscode.py"), zs[-1]])
        if r.returncode != 0: sys.exit("행안부 코드 넣기 실패")
    else:
        r = subprocess.run([sys.executable, os.path.join(HERE, "mois_jscode_watch.py")])
        if r.returncode not in (0, 3): sys.exit("행안부 코드 받기 실패")
    t0 = time.time(); cur.execute("EXEC gold.usp_build_bdong_succ"); print("  옛→지금:", cur.fetchall(), f"{time.time() - t0:.0f}초", flush=True)
    t0 = time.time(); cur.execute("EXEC gold.usp_build_adm_link"); print("  행정동 연결:", cur.fetchall(), f"{time.time() - t0:.0f}초", flush=True)
    r = subprocess.run([sys.executable, os.path.join(HERE, "svc_layers.py"), "--only", "adm,sg_adm", "--force", "adm,sg_adm"])
    print("  서비스DB 층 발행:", "됨" if r.returncode == 0 else f"실패({r.returncode})", flush=True)
    cur.execute("""SELECT 이름없던코드 = (SELECT COUNT(*) FROM gold.v_lawd_name WHERE 출처 = N'행안부이력'),
                          확정대응 = (SELECT COUNT(*) FROM gold.bdong_succ_code),
                          단지위치 = (SELECT COUNT(*) FROM gold.complex_lawd_now),
                          행정동경계 = (SELECT COUNT(*) FROM gold.adm_link),
                          공식연결 = (SELECT COUNT(*) FROM gold.adm_link WHERE 행정동코드 IS NOT NULL),
                          말소된행정동경계 = (SELECT COUNT(*) FROM gold.adm_link WHERE 현행 = 0)""")
    print("  확인:", cur.fetchall())


if __name__ == "__main__":
    main()
