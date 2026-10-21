#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_lawd_file - 전국 법정동코드를 **공식 파일**로 meta.lawd_code 에 채운다

  py load_lawd_file.py

출처: 국토교통부_전국 법정동 (data.go.kr 15063424)
      CSV / utf-8-sig / 20,561행 / **이용허락범위 제한 없음**
      컬럼: 법정동코드, 시도명, 시군구명, 읍면동명, 리명, 순번, 생성일자

★ 왜 파일인가 — `load_lawd.py` 는 VWorld 지적도에서 **파생**한다
  그 방식은 "지적도에 필지가 있는 법정동만 나온다" 는 한계를 스스로 적어 뒀다.
  공식 파일은 그 한계가 없고, 시군구 코드도 같이 들어 있다.
  범위를 넓힐 때마다 코드를 찾는 일이 사라진다.

★ **코드를 외워서 쓰지 않는다.** 2026-10-19 에 양재동을 `1165010300` 으로
  기억하고 있었는데 실제는 **`1165010200`** 이었다. 이 파일로 확인해서 잡았다.

★ 시군구 행(읍면동이 빈 행)도 그대로 넣는다 — `--sgg` 에 넣을 코드가 거기 있다.
  읍면동이 있는 행만 넣으면 "안양시 동안구 = 41173" 을 또 어디선가 찾아야 한다.
"""
import csv, io, os, sys, time
import pymssql

from load_building import load_env

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
SRC  = os.path.join(HERE, "data", "lawd_code_20260729.csv")


def main():
    if not os.path.isfile(SRC):
        sys.exit(f"없는 파일: {SRC} (받는 법은 data/README.txt)")
    env = load_env(ENV)
    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    with io.open(SRC, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    need = ["법정동코드", "시도명", "시군구명", "읍면동명", "리명"]
    miss = [c for c in need if rows and c not in rows[0]]
    if miss:
        sys.exit(f"컬럼이 바뀌었다: 없음 {miss} / 있는 것 {list(rows[0].keys())}")
    print(f"읽음 {len(rows):,}행")

    cur.execute("SELECT COUNT(*) FROM meta.lawd_code")
    before = cur.fetchone()[0]

    batch = []
    for r in rows:
        cd = (r["법정동코드"] or "").strip()
        if len(cd) != 10 or not cd.isdigit():
            continue
        sido = (r["시도명"] or "").strip() or None
        sgg  = (r["시군구명"] or "").strip() or None
        emd  = (r["읍면동명"] or "").strip() or None
        ri   = (r["리명"] or "").strip() or None
        full = " ".join(x for x in (sido, sgg, emd, ri) if x) or None
        batch.append((cd, sido, sgg, emd, ri, full, cd[:2], cd[:5], cd[5:]))

    cur.execute("""IF OBJECT_ID('tempdb..#lc') IS NOT NULL DROP TABLE #lc;
                   CREATE TABLE #lc (lawd_cd CHAR(10), sido_nm NVARCHAR(40),
                     sgg_nm NVARCHAR(60), emd_nm NVARCHAR(60), ri_nm NVARCHAR(60),
                     full_nm NVARCHAR(200), sido_cd CHAR(2), sgg_cd CHAR(5), emd_cd CHAR(5))""")
    ins = "INSERT INTO #lc VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)"
    for i in range(0, len(batch), 1000):
        cur.executemany(ins, batch[i:i + 1000])

    # ★ 기존 행을 지우지 않는다. 같은 코드는 덮어쓰고, 없던 것만 넣는다.
    #   VWorld 에서 파생해 둔 것과 싸우지 않게 한다.
    # ★ sido_cd / sgg_cd / emd_cd 는 **계산 컬럼**이다(lawd_cd 에서 잘라 쓴다).
    #   넣으려다 'cannot be modified because it is either a computed column' 을
    #   맞았다 - 컬럼 목록만 보고 타입을 안 봤다. 좋은 설계였고 내가 중복을 넣으려 했다.
    cur.execute("""UPDATE t SET sido_nm=s.sido_nm, sgg_nm=s.sgg_nm, emd_nm=s.emd_nm,
                        ri_nm=s.ri_nm, full_nm=s.full_nm
                     FROM meta.lawd_code t JOIN #lc s ON s.lawd_cd = t.lawd_cd""")
    upd = max(cur.rowcount, 0)
    cur.execute("""INSERT INTO meta.lawd_code
                     (lawd_cd, sido_nm, sgg_nm, emd_nm, ri_nm, full_nm, loaded_at)
                   SELECT s.lawd_cd, s.sido_nm, s.sgg_nm, s.emd_nm, s.ri_nm, s.full_nm,
                          SYSDATETIME()
                     FROM #lc s
                    WHERE NOT EXISTS (SELECT 1 FROM meta.lawd_code t
                                       WHERE t.lawd_cd = s.lawd_cd)""")
    new = max(cur.rowcount, 0)
    cur.execute("DROP TABLE #lc")
    conn.commit()
    cur.execute("SELECT COUNT(*) FROM meta.lawd_code")
    after = cur.fetchone()[0]
    print(f"\n{before:,} -> {after:,}  (새로 {new:,} · 갱신 {upd:,})")
    cur.execute("""SELECT lawd_cd, full_nm FROM meta.lawd_code
                    WHERE lawd_cd IN ('4117100000','4117300000','1165010200')
                    ORDER BY lawd_cd""")
    print("\n이번에 쓸 코드 확인")
    for cd, nm in cur.fetchall():
        print(f"  {cd}  {nm}")
    conn.close()


if __name__ == "__main__":
    main()
