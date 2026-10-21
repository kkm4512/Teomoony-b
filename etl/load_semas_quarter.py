#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_semas_quarter - 상권 **분기 스냅샷**을 silver.semas_quarter 에 적재

  py load_semas_quarter.py            (data/semas_q_*.csv 전부)

출처: 소상공인시장진흥공단_상가(상권)정보 (data.go.kr 15083033)
      분기 CSV · 시도별로 나뉨 · **이용허락범위 제한 없음** · utf-8
      과거 분기 49개가 '주기성 과거 데이터' 에 전부 열려 있다.

★ 왜 필요한가
  API(`silver.semas_store`)는 '지금 영업중' 만 준다 - **폐업이 안 보인다.**
  분기 파일을 쌓아야 "1년 새 몇 곳이 사라졌나" 를 말할 수 있다.

★ bizes_id 는 분기를 넘어 유지된다 (실측 185: 2025-06 샘플 1,000 중 871 생존).
  id 가 재발급됐다면 0 에 가까웠을 것이다. 그래서 비교가 성립한다.

★ 파일명에서 분기를 읽는다: semas_q_YYYYMM_*.csv
★ 전국을 다 넣지 않는다. 우리 단지가 있는 구만 잘라서 넣는다(추출법은 README).
"""
import csv, glob, io, os, re, sys, time
import pymssql

from load_building import load_env

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
DATA = os.path.join(HERE, "data")

COLS = ["quarter", "bizes_id", "bizes_nm", "inds_lcls_cd", "inds_lcls_nm",
        "inds_mcls_cd", "inds_mcls_nm", "inds_scls_cd", "inds_scls_nm",
        "signgu_cd", "ldong_cd", "pnu", "bld_mng_no", "lon", "lat"]


def _notify(title, lines):
    try:
        import notify
        ok, why = notify.send("[터무니] " + title + "\n" + "\n".join(lines))
        print(f"[알림] {'보냄' if ok else '안 보냄 - ' + str(why)}")
    except Exception as e:
        print(f"[알림] 실패 - {type(e).__name__}: {e}")


def num(s, nd=8):
    try:
        return round(float(s), nd)
    except Exception:
        return None


def main():
    env = load_env(ENV)
    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    files = sorted(glob.glob(os.path.join(DATA, "semas_q_*.csv")))
    if not files:
        sys.exit("etl/data/semas_q_*.csv 가 없습니다")
    total = 0
    wiped = set()          # 이번 실행에서 이미 비운 분기
    for path in files:
        m = re.search(r"semas_q_(\d{6})", os.path.basename(path))
        if not m:
            print(f"  건너뜀(분기를 못 읽음): {os.path.basename(path)}")
            continue
        q = m.group(1)
        with io.open(path, encoding="utf-8", newline="") as f:
            rows = list(csv.DictReader(f))
        need = ["상가업소번호", "상호명", "상권업종대분류코드", "지번코드", "경도", "위도"]
        miss = [c for c in need if rows and c not in rows[0]]
        if miss:
            sys.exit(f"컬럼이 바뀌었다: 없음 {miss}")
        print(f"{os.path.basename(path)}  분기 {q}  {len(rows):,}행")

        # ★ 같은 분기 파일이 **여러 개**일 수 있다(지역을 나눠 뽑아 넣으면 그렇다).
        #   분기별로 **처음 한 번만** 지운다. 파일마다 지우면 두 번째 파일이
        #   첫 번째가 넣은 것을 쓸어버린다 - 2026-10-19 에 안양을 더하다 알아챘다.
        if q not in wiped:
            cur.execute("DELETE FROM silver.semas_quarter WHERE quarter = %s", (q,))
            print(f"  기존 {q} {max(cur.rowcount,0):,}건 지우고 다시 넣습니다 (분기 스냅샷은 통째로 교체)")
            wiped.add(q)
        else:
            print(f"  {q} 는 이 실행에서 이미 비웠습니다 — 이어서 넣습니다")

        seen, payload, no_xy, bad_pnu, dup_db = set(), [], 0, 0, 0
        for r in rows:
            bid = (r["상가업소번호"] or "").strip()
            if not bid or bid in seen:
                continue
            seen.add(bid)
            lon, lat = num(r["경도"]), num(r["위도"])
            if lon is None or lat is None:
                no_xy += 1
            pnu = (r.get("지번코드") or "").strip()
            # ★ 19자리 숫자일 때만 PNU 로 본다. 아니면 비운다(정책 1장).
            if not (len(pnu) == 19 and pnu.isdigit()):
                if pnu:
                    bad_pnu += 1
                pnu = None
            payload.append((
                q, bid,
                (r.get("상호명") or "").strip() or None,
                (r.get("상권업종대분류코드") or "").strip() or None,
                (r.get("상권업종대분류명") or "").strip() or None,
                (r.get("상권업종중분류코드") or "").strip() or None,
                (r.get("상권업종중분류명") or "").strip() or None,
                (r.get("상권업종소분류코드") or "").strip() or None,
                (r.get("상권업종소분류명") or "").strip() or None,
                (r.get("시군구코드") or "").strip() or None,
                (r.get("법정동코드") or "").strip() or None,
                pnu,
                (r.get("건물관리번호") or "").strip() or None,
                lon, lat))

        ins = (f"INSERT INTO silver.semas_quarter ({', '.join(COLS)}, geog) VALUES ("
               + ", ".join(["%s"] * len(COLS))
               + ", CASE WHEN %s IS NULL OR %s IS NULL THEN NULL "
                 "ELSE geography::Point(%s, %s, 4326) END)")
        batch = [p + (p[14], p[13], p[14], p[13]) for p in payload]   # lat, lon
        for i in range(0, len(batch), 1000):
            cur.executemany(ins, batch[i:i + 1000])
            if (i // 1000) % 10 == 0:
                print(f"    {min(i+1000, len(batch)):,}/{len(batch):,}")
        conn.commit()
        total += len(payload)
        print(f"  넣음 {len(payload):,} · 좌표없음 {no_xy:,} · PNU 모양이 아님 {bad_pnu:,}")

    cur.execute("""SELECT quarter, COUNT(*) FROM silver.semas_quarter
                    GROUP BY quarter ORDER BY quarter""")
    print("\n분기별 보유")
    for q, n in cur.fetchall():
        print(f"  {q}  {n:,}")
    _notify("상권 분기 스냅샷 적재 완료", [f"{total:,}건"])
    conn.close()


if __name__ == "__main__":
    main()
