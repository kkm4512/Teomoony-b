#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_lawd - 법정동코드 마스터 채우기

  py load_lawd.py --sgg 11110
  py load_lawd.py --sgg 11110 11140 11170

왜 필요한가
---------------------------------------------------------------
실거래가는 법정동을 "이름"으로만 준다(umdNm='숭인동'). PNU 를 조립하려면
이름 -> 코드 변환이 필요한데, 그 표가 meta.lawd_code 다.
이게 비어 있으면 실거래가 축이 통째로 안 붙는다.

어디서 가져오나
---------------------------------------------------------------
행정표준코드관리시스템 전체자료가 정석이지만 별도 다운로드가 필요하다.
여기서는 이미 쓰고 있는 VWorld 연속지적도에서 파생한다.
필지마다 pnu(법정동코드 10자리 포함)와 addr(법정동 이름)이 들어 있으므로,
시군구 전체 필지를 속성만 받아(geometry=false) 둘을 짝지으면 된다.

  pnu  1111016500100400001  -> 법정동코드 1111016500
  addr 서울특별시 종로구 이화동 40-1 -> 이화동

종로구 기준 49페이지 / 약 30초. 한 번만 돌리면 된다.

한계
---------------------------------------------------------------
지적도에 필지가 있는 법정동만 나온다. 필지가 없는 법정동(해상 등)은 빠진다.
전국을 정확히 맞추려면 결국 행정표준코드 전체자료가 필요하다.
"""
import argparse, os, re, sys, time
import requests
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
VW   = "https://api.vworld.kr/req/data"

TAIL_RE = re.compile(r'\s*(산\s*)?\d+(-\d+)?\s*번?지?\s*$')



# ★ VWorld 키는 **등록 도메인에 묶인다** (2026-10-20 실측).
#   domain=localhost -> INCORRECT_KEY. 그런데 fetch 가 그 단위만 건너뛰고 넘어가서
#   **적재가 조용히 0건이 된다.** 실제로 필지가 446,040 에서 멈췄는데 끝까지 돌면
#   "OK" 로 보고될 뻔했다. 하드코딩하지 않고 .env 의 VWORLD_DOMAIN 을 읽는다.
def vworld_domain(env):
    return (env.get("VWORLD_DOMAIN") or "teomoony.com").strip()


DOMAIN = "teomoony.com"   # main() 에서 .env 값으로 덮어쓴다


def load_env(p):
    d = {}
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", nargs="+", required=True, help="시군구코드 5자리")
    args = ap.parse_args()

    env = load_env(ENV)

    global DOMAIN

    DOMAIN = vworld_domain(env)

    print(f"  VWorld domain = {DOMAIN}")
    key = env.get("VWORLD_KEY", "").strip()
    if not key:
        sys.exit(".env 의 VWORLD_KEY 가 비어 있습니다")

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()

    for sgg in args.sgg:
        print(f"\n시군구 {sgg}")
        found = {}          # lawd_cd -> (sido, sgg, emd, ri, full)
        page, t0 = 1, time.time()
        while True:
            p = {"service": "data", "version": "2.0", "request": "GetFeature",
                 "key": key, "data": "LP_PA_CBND_BUBUN",
                 "attrFilter": f"pnu:like:{sgg}",
                 "geometry": "false", "attribute": "true", "crs": "EPSG:4326",
                 "format": "json", "size": "1000", "page": str(page),
                 "domain": DOMAIN}
            try:
                j = requests.get(VW, params=p, timeout=120).json().get("response", {})
            except Exception as e:
                print(f"  page {page} 실패: {e}"); break
            if j.get("status") != "OK":
                if j.get("status") != "NOT_FOUND":
                    print(f"  page {page}: {j.get('status')} {j.get('error', {})}")
                break
            fs = j["result"]["featureCollection"]["features"]
            for f in fs:
                pr = f.get("properties", {}) or {}
                pnu, addr = (pr.get("pnu") or "").strip(), (pr.get("addr") or "").strip()
                if len(pnu) != 19 or not addr:
                    continue
                lawd = pnu[:10]
                if lawd in found:
                    continue
                t = TAIL_RE.sub("", addr).strip().split()
                if len(t) < 3:
                    continue
                found[lawd] = (t[0], t[1], t[2], t[3] if len(t) > 3 else None, " ".join(t))
            tot = int(j.get("page", {}).get("total", 1))
            if page % 10 == 0 or page == tot:
                print(f"  {page}/{tot} 페이지  법정동 {len(found)}개 발견")
            if page >= tot:
                break
            page += 1
            time.sleep(0.1)

        ins = upd = 0
        for lawd, (sido, s2, emd, ri, full) in sorted(found.items()):
            cur.execute("SELECT full_nm FROM meta.lawd_code WHERE lawd_cd=%s", (lawd,))
            r = cur.fetchone()
            if r is None:
                cur.execute("""INSERT INTO meta.lawd_code
                               (lawd_cd, sido_nm, sgg_nm, emd_nm, ri_nm, full_nm)
                               VALUES (%s,%s,%s,%s,%s,%s)""", (lawd, sido, s2, emd, ri, full))
                ins += 1
            elif r[0] != full:
                cur.execute("""UPDATE meta.lawd_code
                                  SET sido_nm=%s, sgg_nm=%s, emd_nm=%s, ri_nm=%s, full_nm=%s
                                WHERE lawd_cd=%s""", (sido, s2, emd, ri, full, lawd))
                upd += 1
        conn.commit()
        print(f"  완료 {time.time()-t0:.0f}s  법정동 {len(found)}개 (신규 {ins} / 갱신 {upd})")

    cur.execute("SELECT COUNT(*) FROM meta.lawd_code")
    print(f"\nmeta.lawd_code 총 {cur.fetchone()[0]:,}건")
    cur.execute("""SELECT TOP 10 sgg_nm, COUNT(*) FROM meta.lawd_code
                   GROUP BY sgg_nm ORDER BY 2 DESC""")
    for nm, c in cur.fetchall():
        print(f"  {nm or '-':12s} {c:4d}개 법정동")
    conn.close()


if __name__ == "__main__":
    main()
