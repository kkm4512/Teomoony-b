#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_school - 전국 초·중·고 위치를 silver.school 에 적재

  py load_school.py --probe      (1페이지만 떠서 생김새를 본다)
  py load_school.py              (전부)

출처 / 라이선스
  전국초중등학교위치표준데이터 (data.go.kr 15021148)
  제공 한국교육시설안전원 / 소관 교육부
  요청주소 https://api.data.go.kr/openapi/tn_pubr_public_elesch_mskul_lc_api
  활용승인 자동 · 개발계정 10,000건/일 · numOfRows 최대 1000

★ 왜 이게 필요한가
  소상공인 상가(상권)정보에는 **학교가 0건**이다(2026-10-19 실측).
  상가가 아니라서 수집 대상이 아니다. 학교는 이 표준데이터로만 온다.

★ 코드로 붙지 않는다
  PNU 도 건물관리번호도 안 온다. 지번주소는 문자열이라 그대로 PNU 가 아니다.
  **좌표 거리만 쓴다.** 주소를 PNU 로 바꾸는 건 별도 작업이고,
  틀리면 조용히 틀리므로 여기서 하지 않는다(정책 1장).

★ 키 등록이 먼저다
  2026-10-19 기준 .env 의 DATA_GO_KR_KEY 로 부르면
  SERVICE_KEY_IS_NOT_REGISTERED_ERROR(30) 가 난다 -
  data.go.kr 15021148 에서 **활용신청(자동승인)** 을 눌러야 한다.
"""
import argparse, hashlib, os, sys, time
import requests
import pymssql

from load_building import load_env

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
URL  = "https://api.data.go.kr/openapi/tn_pubr_public_elesch_mskul_lc_api"


def _notify(title, lines):
    try:
        import notify
        ok, why = notify.send("[터무니] " + title + "\n" + "\n".join(lines))
        print(f"[알림] {'보냄' if ok else '안 보냄 - ' + str(why)}")
    except Exception as e:
        print(f"[알림] 실패 - {type(e).__name__}: {e}")


def fetch(key, page, rows=1000, retries=3):
    """한 페이지. 응답 모양이 기대와 다르면 **조용히 0건으로 넘기지 않고** 멈춘다."""
    p = {"serviceKey": key, "pageNo": page, "numOfRows": rows, "type": "json"}
    last = None
    for t in range(retries):
        try:
            r = requests.get(URL, params=p, timeout=120)
            j = r.json()
        except Exception as e:
            last = e
            time.sleep(2 * (t + 1))
            continue
        # 에러 봉투 (키 미등록 / 한도초과 등) 는 그대로 드러낸다
        if "OpenAPI_ServiceResponse" in j:
            h = j["OpenAPI_ServiceResponse"].get("cmmMsgHeader", {})
            sys.exit(f"API 거절: {h.get('errMsg')} ({h.get('returnAuthMsg')})")
        # ★ 이 API 는 `response` 래퍼가 **없다** - 최상위가 바로 header/body 다
        #   (2026-10-19 실측). 다른 data.go.kr API 모양을 그대로 베꼈다가
        #   `j["response"]` 가 빈 dict 이 되어 **totalCount 0 · 0건**으로
        #   조용히 끝났다. resultCode 는 "00" 이었다 - 그래서 더 위험했다.
        #   래퍼가 있는 API 도 있으므로 **둘 다** 받는다.
        resp = j.get("response") or j
        head = resp.get("header") or {}
        code = str(head.get("resultCode", ""))
        if code not in ("", "00", "0"):
            if code == "03":          # NODATA
                return [], 0
            sys.exit(f"API 오류 {code}: {head.get('resultMsg')}")
        body = resp.get("body") or {}
        items = body.get("items") or []
        if isinstance(items, dict):
            items = items.get("item") or []
        if isinstance(items, dict):          # 1건일 때 dict 하나로 오는 경우
            items = [items]
        total = int(body.get("totalCount") or 0)
        # ★ 정상(00)인데 1페이지가 비어 있으면 **응답 모양이 바뀐 것**이다.
        #   조용히 0건으로 끝내지 않는다 - 그게 오늘 실제로 벌어진 일이다.
        if page == 1 and not items:
            sys.exit("정상 응답인데 1페이지가 비어 있다 - 응답 구조가 바뀌었는지 "
                     "날것을 확인하라. 조용히 0건으로 끝내지 않는다.\n"
                     "  받은 최상위 키: " + ", ".join(sorted(j.keys())))
        return items, total
    sys.exit(f"호출 실패: {last}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe", action="store_true", help="1페이지만 보고 끝낸다")
    ap.add_argument("--rows", type=int, default=1000)
    args = ap.parse_args()

    env = load_env(ENV)
    key = env.get("DATA_GO_KR_KEY", "").strip()
    if not key:
        sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있습니다")

    items, total = fetch(key, 1, args.rows)
    print(f"총 {total:,}건  ·  페이지당 {args.rows}  ·  예상 호출 "
          f"{(total + args.rows - 1)//max(args.rows,1):,}회")
    if args.probe:
        print("\n--- 1건의 생김새 (추측하지 않고 눈으로 본다) ---")
        if items:
            for k, v in items[0].items():
                print(f"  {k:<16} {v!r}")
        else:
            print("  (빈 응답)")
        return

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    today = time.strftime("%Y%m%d")
    seen, n_new, n_chg, calls, recv, no_xy = set(), 0, 0, 0, 0, 0

    page = 1
    while True:
        if page > 1:
            items, _ = fetch(key, page, args.rows)
        calls += 1
        if not items:
            break
        recv += len(items)
        for r in items:
            sid = str(r.get("schoolId") or "").strip()
            if not sid or sid in seen:
                continue
            seen.add(sid)
            try:
                lat = float(r.get("latitude"))
                lon = float(r.get("longitude"))
            except Exception:
                lat = lon = None
            if lat is None:
                no_xy += 1
            vals = dict(
                school_id=sid,
                school_nm=(r.get("schoolNm") or "").strip() or None,
                school_se=(r.get("schoolSe") or "").strip() or None,
                fond_date=(r.get("fondDate") or "").strip() or None,
                fond_type=(r.get("fondType") or "").strip() or None,
                bnhh_se=(r.get("bnhhSe") or "").strip() or None,
                oper_sttus=(r.get("operSttus") or "").strip() or None,
                lnmadr=(r.get("lnmadr") or "").strip() or None,
                rdnmadr=(r.get("rdnmadr") or "").strip() or None,
                cddc_code=(str(r.get("cddcCode") or "").strip() or None),
                cddc_nm=(r.get("cddcNm") or "").strip() or None,
                edc_sport=(str(r.get("edcSport") or "").strip() or None),
                edc_sport_nm=(r.get("edcSportNm") or "").strip() or None,
                lat=round(lat, 8) if lat is not None else None,
                lon=round(lon, 8) if lon is not None else None,
                reference_date=(r.get("referenceDate") or "").strip() or None,
                collected_at=today)
            rh = hashlib.sha256(
                "\x1f".join(str(vals[k]) for k in sorted(vals) if k != "collected_at")
                .encode("utf-8")).digest()
            cur.execute("""UPDATE silver.school
                              SET is_current = 0, valid_to = SYSDATETIME()
                            WHERE is_current = 1 AND school_id = %s AND row_hash <> %s""",
                        (sid, rh))
            n_chg += max(cur.rowcount, 0)
            cols = list(vals.keys())
            if lat is not None and lon is not None:
                cur.execute(
                    f"IF NOT EXISTS (SELECT 1 FROM silver.school "
                    f"WHERE is_current=1 AND school_id=%s) "
                    f"INSERT INTO silver.school ({', '.join(cols)}, geog, row_hash) "
                    f"VALUES ({', '.join(['%s']*len(cols))}, "
                    f"geography::Point(%s, %s, 4326), %s)",
                    (sid,) + tuple(vals[c] for c in cols) + (lat, lon, rh))
            else:
                cur.execute(
                    f"IF NOT EXISTS (SELECT 1 FROM silver.school "
                    f"WHERE is_current=1 AND school_id=%s) "
                    f"INSERT INTO silver.school ({', '.join(cols)}, row_hash) "
                    f"VALUES ({', '.join(['%s']*len(cols))}, %s)",
                    (sid,) + tuple(vals[c] for c in cols) + (rh,))
            # ★ IF NOT EXISTS ... INSERT 는 안 넣었을 때 rowcount 가 -1 이다
            n_new += max(cur.rowcount, 0)
        conn.commit()
        print(f"  page {page:3}  수신 {len(items):5,}  누적신규 {n_new:6,}")
        if len(items) < args.rows:
            break
        page += 1

    cur.execute("""SELECT school_se, oper_sttus, COUNT(*)
                     FROM silver.school WHERE is_current = 1
                    GROUP BY school_se, oper_sttus ORDER BY school_se, oper_sttus""")
    print("\n학교급 x 운영상태")
    rows_ = cur.fetchall()
    for se, st, n in rows_:
        print(f"  {se or '(없음)':<10} {st or '(없음)':<8} {n:,}")
    cur.execute("SELECT COUNT(*) FROM silver.school WHERE is_current = 1")
    tot = cur.fetchone()[0]
    print(f"\n학교 총 {tot:,}건  (호출 {calls:,} · 수신 {recv:,} · "
          f"신규 {n_new:,} · 변경 {n_chg:,} · 좌표없음 {no_xy:,})")

    _notify("학교 위치 적재 완료",
            [f"호출 {calls:,} · 총 {tot:,}건 (신규 {n_new:,})",
             f"좌표 없음 {no_xy:,}건"])
    conn.close()


if __name__ == "__main__":
    main()
