#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_semas - 소상공인 상가(상권)정보 점포를 silver.semas_store 에 적재

  py load_semas.py --lawd 1129013800 1138010100     (법정동 지정)
  py load_semas.py                                   (단지가 있는 법정동 전부)

출처 / 라이선스
  소상공인시장진흥공단_상가(상권)정보_API (data.go.kr 15012005)
  **이용허락범위 제한 없음**. 원자료 출처는 국세청/카드사. 분기 갱신.

왜 사각형(Rectangle)으로 받나
  * 처음엔 단지 중심 반경 1000m 로 받았다. 돌려 보니 **호출 133회에 수신
    289,261건, 신규 11,636건** - **96% 가 중복**이었다. 장위동 한 동에
    총괄표제부 단지가 98개라 98번 부르고, 두 번째부터는 거의 전부 신규 0 이었다.
  * API 목록을 보고 `storeListInRectangle` 로 바꿨다. **법정동 bbox 한 번**이면
    그 동이 통째로 온다. 장위동 2,408건 = 3페이지. 133회 -> 3회.
  * bbox 는 `silver.cadastral_parcel` 에서 법정동별로 뽑는다 -
    load_building / load_landuse 가 쓰는 **같은 출처**다.

★ 내가 틀렸던 것 (2026-10-19)
  `storeListInDong` 을 법정동코드로 불러서 INVALID_REQUEST_PARAMETER 를 받고
  "divId 조합을 못 찾았다" 고 적었다. 실제로는 **행정동 단위**였다
  (divId=adongCd, key=11290760 -> 장위1동 611건). divId 추측은 맞았고
  **코드 종류가 틀렸다.** 명세를 보기 전에 추측으로 찔러 본 대가다.

★ 이 API 는 '현재 영업 중' 스냅샷이다. 폐업률은 여기서 안 나온다 -
  분기별 CSV 를 쌓아야 한다(data/README 참고).
"""
import argparse, hashlib, os, sys, time
import requests
import pymssql

from load_building import load_env

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
BASE = "https://apis.data.go.kr/B553077/api/open/sdsc2"


def fetch_rect(key, x0, y0, x1, y1, retries=3):
    """사각형 영역을 페이징해서 전부 받는다. 깨진 JSON 에 죽지 않는다."""
    out, page = [], 1
    while True:
        p = {"serviceKey": key, "minx": x0, "miny": y0, "maxx": x1, "maxy": y1,
             "numOfRows": 1000, "pageNo": page, "type": "json"}
        last = None
        for a in range(retries):
            try:
                r = requests.get(BASE + "/storeListInRectangle", params=p, timeout=180)
                try:
                    j = r.json()
                except ValueError:
                    j = {"header": {"resultCode": "BROKEN", "resultMsg": r.text[:200]}}
                last = j
                code = (j.get("header") or {}).get("resultCode")
                if code == "00":
                    break
                if code == "03":           # NODATA - 정상적으로 '없음'
                    return out
            except Exception as e:
                last = {"header": {"resultCode": "EXC", "resultMsg": str(e)}}
            time.sleep(1.2 * (a + 1))
        h = (last or {}).get("header") or {}
        if h.get("resultCode") != "00":
            print(f"    ! page {page}: {h.get('resultCode')} {str(h.get('resultMsg'))[:90]}")
            return out
        body = last.get("body") or {}
        items = body.get("items") or []
        out += items
        try:
            total = int(body.get("totalCount") or 0)
        except Exception:
            total = len(out)
        if len(out) >= total or not items:
            break
        page += 1
        time.sleep(0.12)
    return out


def _notify(title, lines):
    try:
        import notify
        ok, why = notify.send("[터무니] " + title + "\n" + "\n".join(lines))
        print(f"[알림] {'보냄' if ok else '안 보냄 - ' + str(why)}")
    except Exception as e:
        print(f"[알림] 실패 - {type(e).__name__}: {e}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lawd", nargs="*", help="법정동코드 10자리")
    ap.add_argument("--pad", type=float, default=0.0008, help="법정동 bbox 여유(도)")
    args = ap.parse_args()

    env = load_env(ENV)
    key = env.get("SEMAS_KEY", "").strip()
    if not key:
        sys.exit(".env 의 SEMAS_KEY 가 비어 있습니다 (data.go.kr 15012005 활용신청)")

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()

    # 법정동 bbox 로 받는다. 출처는 load_building / load_landuse 와 같은
    # silver.cadastral_parcel 이다 - 같은 규칙을 두 군데 적지 않는다(11-38 교훈).
    q = """SELECT lawd_cd,
                  MIN(bbox_minx), MIN(bbox_miny), MAX(bbox_maxx), MAX(bbox_maxy)
             FROM silver.cadastral_parcel
            WHERE is_current = 1
            GROUP BY lawd_cd"""
    p = []
    if args.lawd:
        q += " HAVING lawd_cd IN (" + ",".join(["%s"] * len(args.lawd)) + ")"
        p = list(args.lawd)
    q += " ORDER BY lawd_cd"
    cur.execute(q, tuple(p))
    rows = cur.fetchall()
    if not rows:
        sys.exit("필지가 없습니다. load_cadastral.py 를 먼저 돌리세요.")

    print(f"대상 법정동 {len(rows):,}개  ·  사각형(bbox) 질의  pad {args.pad}도")
    seen, n_new, n_chg, calls, recv = set(), 0, 0, 0, 0
    today = time.strftime("%Y%m%d")

    for lawd, x0, y0, x1, y1 in rows:
        items = fetch_rect(key, float(x0) - args.pad, float(y0) - args.pad,
                                float(x1) + args.pad, float(y1) + args.pad)
        calls += 1
        recv += len(items)
        n = 0
        for r in items:
            bid = (r.get("bizesId") or "").strip()
            if not bid or bid in seen:
                continue
            seen.add(bid)
            lon, lat = r.get("lon"), r.get("lat")
            try:
                lon, lat = float(lon), float(lat)
            except Exception:
                lon = lat = None
            pnu = (r.get("lnoCd") or "").strip()
            vals = dict(
                bizes_id=bid,
                bizes_nm=(r.get("bizesNm") or "").strip() or None,
                brch_nm=(r.get("brchNm") or "").strip() or None,
                inds_lcls_cd=(r.get("indsLclsCd") or "").strip() or None,
                inds_lcls_nm=(r.get("indsLclsNm") or "").strip() or None,
                inds_mcls_cd=(r.get("indsMclsCd") or "").strip() or None,
                inds_mcls_nm=(r.get("indsMclsNm") or "").strip() or None,
                inds_scls_cd=(r.get("indsSclsCd") or "").strip() or None,
                inds_scls_nm=(r.get("indsSclsNm") or "").strip() or None,
                ksic_cd=(r.get("ksicCd") or "").strip() or None,
                ksic_nm=(r.get("ksicNm") or "").strip() or None,
                signgu_cd=(r.get("signguCd") or "").strip() or None,
                adong_cd=(r.get("adongCd") or "").strip() or None,
                adong_nm=(r.get("adongNm") or "").strip() or None,
                ldong_cd=(r.get("ldongCd") or "").strip() or None,
                ldong_nm=(r.get("ldongNm") or "").strip() or None,
                # ★ 19자리일 때만 PNU 로 본다. 길이가 다르면 **비운다** -
                #   조용히 틀린 PNU 는 NULL 보다 나쁘다(정책 1장).
                pnu=pnu if len(pnu) == 19 and pnu.isdigit() else None,
                lno_adr=(r.get("lnoAdr") or "").strip() or None,
                bld_mng_no=(r.get("bldMngNo") or "").strip() or None,
                bld_nm=(r.get("bldNm") or "").strip() or None,
                rdnm_adr=(r.get("rdnmAdr") or "").strip() or None,
                flr_no=(str(r.get("flrNo") or "").strip() or None),
                ho_no=(str(r.get("hoNo") or "").strip() or None),
                lon=round(lon, 8) if lon is not None else None,
                lat=round(lat, 8) if lat is not None else None,
                collected_at=today)
            rh = hashlib.sha256(
                "\x1f".join(str(vals[k]) for k in sorted(vals) if k != "collected_at")
                .encode("utf-8")).digest()
            cur.execute("""UPDATE silver.semas_store
                              SET is_current = 0, valid_to = SYSDATETIME()
                            WHERE is_current = 1 AND bizes_id = %s AND row_hash <> %s""",
                        (bid, rh))
            n_chg += max(cur.rowcount, 0)
            cols = list(vals.keys())
            if lon is not None and lat is not None:
                cur.execute(
                    f"IF NOT EXISTS (SELECT 1 FROM silver.semas_store "
                    f"WHERE is_current=1 AND bizes_id=%s) "
                    f"INSERT INTO silver.semas_store ({', '.join(cols)}, geog, row_hash) "
                    f"VALUES ({', '.join(['%s']*len(cols))}, "
                    f"geography::Point(%s, %s, 4326), %s)",
                    (bid,) + tuple(vals[c] for c in cols) + (lat, lon, rh))
            else:
                cur.execute(
                    f"IF NOT EXISTS (SELECT 1 FROM silver.semas_store "
                    f"WHERE is_current=1 AND bizes_id=%s) "
                    f"INSERT INTO silver.semas_store ({', '.join(cols)}, row_hash) "
                    f"VALUES ({', '.join(['%s']*len(cols))}, %s)",
                    (bid,) + tuple(vals[c] for c in cols) + (rh,))
            # ★ IF NOT EXISTS ... INSERT 는 **안 넣었을 때 rowcount 가 -1** 이다
            #   (SQL Server 가 '의미 없음' 으로 -1 을 준다). 그대로 더하면
            #   "신규 -3,357" 같은 수가 찍힌다 - 화면에서 보고 고쳤다(2026-10-19).
            #   반경 적재 때는 seen 집합이 먼저 걸러서 이 경로를 안 타 안 드러났다.
            n += max(cur.rowcount, 0)
        conn.commit()
        n_new += n
        print(f"  {lawd}  수신 {len(items):6,}  신규 {n:6,}")

    cur.execute("SELECT COUNT(*) FROM silver.semas_store WHERE is_current = 1")
    tot = cur.fetchone()[0]
    cur.execute("""SELECT COUNT(*), SUM(CASE WHEN pnu IS NOT NULL THEN 1 ELSE 0 END),
                          SUM(CASE WHEN bld_mng_no IS NOT NULL THEN 1 ELSE 0 END)
                     FROM silver.semas_store WHERE is_current = 1""")
    a, b, c2 = cur.fetchone()
    print(f"\n점포 총 {tot:,}건  (호출 {calls:,} · 수신 {recv:,} · 신규 {n_new:,} · 변경 {n_chg:,})")
    print(f"  PNU 있음 {b:,}/{a:,} ({100.0*b/max(a,1):.1f}%)  ·  "
          f"건물관리번호 있음 {c2:,}/{a:,} ({100.0*c2/max(a,1):.1f}%)")
    cur.execute("""SELECT TOP 10 inds_lcls_cd, inds_lcls_nm, COUNT(*)
                     FROM silver.semas_store WHERE is_current = 1
                    GROUP BY inds_lcls_cd, inds_lcls_nm ORDER BY COUNT(*) DESC""")
    print("\n업종 대분류")
    for cd, nm2, n2 in cur.fetchall():
        print(f"  {cd:<4} {nm2 or '':<14} {n2:,}")

    _notify("상권 점포 적재 완료",
            [f"법정동 {len(rows):,}개 · 호출 {calls:,}",
             f"점포 총 {tot:,}건 (신규 {n_new:,})",
             f"PNU 보유 {100.0*b/max(a,1):.1f}%"])
    conn.close()


if __name__ == "__main__":
    main()
