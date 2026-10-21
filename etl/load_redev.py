#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_redev - 서울시 정비사업 구역 폴리곤을 silver.redev_zone 에 적재

  py load_redev.py

출처 / 라이선스
  서울 열린데이터광장 OA-22712「서울시 도시계획사업 현황(서울플랜+) 공간정보」
  공공누리 제4유형 — 출처표시 + 상업적 이용금지 + 변경금지.
  ★ **비상업적 이용** 전제다. 화면에 출처를 표시한다.

왜 파일에서 읽나 (API 가 아니라)
  * 이 자료는 **반기 갱신 ZIP 파일**이다. 실시간 API 가 없다.
  * 원본이 **EPSG:5174** 라 4326 으로 바꿔야 하는데, 그 변환은 pyproj 가
    필요하다. 적재기에 좌표 변환을 손으로 넣지 않는다 - 틀려도 그럴듯한
    값이 나와서 **조용히 틀린다.**
  * 그래서 변환까지 끝낸 NDJSON 을 data/ 에 두고 여기서는 읽기만 한다.
    갱신 방법은 data/README.txt 에 적어 두었다.

연결
  구역에는 PNU 가 없다. 단지와는 **공간교차**로 잇는다 (gold.v_complex_redev).
"""
import hashlib, json, os, sys
import pymssql

from load_building import load_env, stats, wkt

HERE  = os.path.dirname(os.path.abspath(__file__))
ENV   = os.path.join(HERE, "..", ".env")
DATA  = os.path.join(HERE, "data", "uq120_4326.ndjson")
CODES = os.path.join(HERE, "data", "uq120_codes.json")


def _notify(title, lines):
    try:
        import notify
        ok, why = notify.send("[터무니] " + title + "\n" + "\n".join(lines))
        print(f"[알림] {'보냄' if ok else '안 보냄 - ' + str(why)}")
    except Exception as e:
        print(f"[알림] 실패 - {type(e).__name__}: {e}")


def main():
    for p in (DATA, CODES):
        if not os.path.exists(p):
            sys.exit(f"파일이 없습니다: {p}\n  data/README.txt 의 갱신 방법을 보세요")
    codes = json.load(open(CODES, encoding="utf-8"))
    atrb, propel = codes["atrb"], codes["propel"]

    env = load_env(ENV)
    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()

    seen, n_new, n_chg, n_skip, unk_a, unk_p = set(), 0, 0, 0, set(), set()
    for ln in open(DATA, encoding="utf-8"):
        d = json.loads(ln)
        pr, g = d["p"], d["g"]
        sn = (pr.get("PRESENT_SN") or "").strip()
        if not sn:
            n_skip += 1
            continue
        seen.add(sn)
        co = g["coordinates"]
        minx, miny, maxx, maxy = stats(co)
        sc = (pr.get("SCLAS_CL") or pr.get("ATRB_SE") or "").strip()
        a = atrb.get(sc)
        if sc and not a:
            unk_a.add(sc)                     # ★ 모르는 코드는 모른다고 남긴다
        pc = (pr.get("PROPEL_CD") or "").strip()
        pv = propel.get(pc) or {}
        pn = pv.get("nm")
        if pc and not pv:
            unk_p.add(pc)
        try:
            ar = float(pr.get("DGM_AR") or 0) or None
        except Exception:
            ar = None

        vals = dict(present_sn=sn,
                    zone_nm=(pr.get("DGM_NM") or "").strip() or None,
                    lclas_cl=(pr.get("LCLAS_CL") or "").strip() or None,
                    sclas_cl=sc or None,
                    atrb_se=(pr.get("ATRB_SE") or "").strip() or None,
                    biz_lclas_nm=a[0] if a else None,
                    biz_mlsfc_nm=a[1] if a else None,
                    biz_nm=a[2] if a else None,
                    propel_cd=pc or None,
                    propel_nm=pn,
                    # ★ 진행도는 코드표 순서에서 온 값이다. '보류' 처럼 단계가
                    #   아닌 것은 None 이고, 화면은 그걸 '단계 아님' 으로 그린다.
                    propel_pct=pv.get("pct"),
                    propel_fam=pv.get("fam"),
                    signgu_se=(pr.get("SIGNGU_SE") or "").strip() or None,
                    area_m2=ar,
                    create_dat=(str(pr.get("CREATE_DAT") or "").replace("-", "")[:8] or None),
                    geojson=json.dumps(g, ensure_ascii=False, separators=(",", ":")),
                    centroid_lat=round((miny + maxy) / 2, 7),
                    centroid_lng=round((minx + maxx) / 2, 7),
                    bbox_minx=round(minx, 7), bbox_miny=round(miny, 7),
                    bbox_maxx=round(maxx, 7), bbox_maxy=round(maxy, 7))
        rh = hashlib.sha256(
            "\x1f".join(str(vals[k]) for k in sorted(vals)).encode("utf-8")).digest()

        # 값이 바뀌었으면 옛 행을 닫는다 (SCD2)
        cur.execute("""UPDATE silver.redev_zone
                          SET is_current = 0, valid_to = SYSDATETIME()
                        WHERE is_current = 1 AND present_sn = %s AND row_hash <> %s""",
                    (sn, rh))
        n_chg += cur.rowcount
        cols = list(vals.keys())
        cur.execute(
            f"IF NOT EXISTS (SELECT 1 FROM silver.redev_zone "
            f"WHERE is_current=1 AND present_sn=%s) "
            f"INSERT INTO silver.redev_zone ({', '.join(cols)}, geom, row_hash) "
            f"VALUES ({', '.join(['%s']*len(cols))}, "
            f"geometry::STGeomFromText(%s, 4326).MakeValid(), %s)",
            (sn,) + tuple(vals[c] for c in cols) + (wkt(co), rh))
        n_new += cur.rowcount
    conn.commit()

    # 파일에서 사라진 구역을 닫는다. ★ 이 파일은 **서울 전체 전량**이라
    #   범위를 따질 필요가 없다 - 용도지역(11-40)과 다른 점이다.
    cur.execute("SELECT present_sn FROM silver.redev_zone WHERE is_current = 1")
    gone = [r[0] for r in cur.fetchall() if r[0] not in seen]
    for sn in gone:
        cur.execute("""UPDATE silver.redev_zone SET is_current = 0, valid_to = SYSDATETIME()
                        WHERE is_current = 1 AND present_sn = %s""", (sn,))
    conn.commit()

    cur.execute("SELECT COUNT(*) FROM silver.redev_zone WHERE is_current = 1")
    tot = cur.fetchone()[0]
    print(f"\n정비구역 총 {tot:,}건  (신규 {n_new:,} / 변경 {n_chg:,} / "
          f"사라짐 {len(gone):,} / 키없음 {n_skip:,})")
    if unk_a:
        print(f"  ! 코드표에 없는 사업유형: {', '.join(sorted(unk_a))}")
    if unk_p:
        print(f"  ! 코드표에 없는 추진단계: {', '.join(sorted(unk_p))}")

    cur.execute("""SELECT TOP 8 ISNULL(biz_nm, N'(코드없음)'), COUNT(*)
                     FROM silver.redev_zone WHERE is_current = 1
                    GROUP BY biz_nm ORDER BY COUNT(*) DESC""")
    print("\n사업유형")
    for b, c in cur.fetchall():
        print(f"  {b:<22} {c:,}")
    cur.execute("""SELECT COUNT(*) FROM silver.redev_zone
                    WHERE is_current = 1 AND propel_cd IS NOT NULL AND propel_pct IS NULL""")
    print(f"\n  진행도가 없는 구역 {cur.fetchone()[0]:,}건"
          f" (코드표에 없는 코드, 또는 '보류' 처럼 진행 단계가 아닌 것)")
    cur.execute("""SELECT TOP 8 ISNULL(propel_nm, N'(코드없음)'), COUNT(*)
                     FROM silver.redev_zone WHERE is_current = 1
                    GROUP BY propel_nm ORDER BY COUNT(*) DESC""")
    print("\n추진단계")
    for b, c in cur.fetchall():
        print(f"  {b:<22} {c:,}")

    _notify("정비구역 적재 완료",
            [f"정비구역 총 {tot:,}건",
             f"신규 {n_new:,} / 변경 {n_chg:,} / 사라짐 {len(gone):,}"])
    conn.close()


if __name__ == "__main__":
    main()
