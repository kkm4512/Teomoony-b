# -*- coding: utf-8 -*-
"""학원·교습소 적재 — 나이스 교육정보 개방포털 (교육부 · 16개 시도교육청)  2026-10-20

  py load_academy.py                   서울(B10) 전부
  py load_academy.py --office J10      경기도교육청
  py load_academy.py --probe           1쪽만 떠서 생김새와 값의 분포를 보여준다

★ 요청주소 https://open.neis.go.kr/hub/acaInsTiInfo · 호출 제한 없음
  필수 인자: KEY, Type, pIndex, pSize, ATPT_OFCDC_SC_CODE(시도교육청코드)

★ **에러일 때는 래퍼가 아예 없다.** 정상은
    {"acaInsTiInfo":[{"head":[{"list_total_count":N},{"RESULT":{...}}]},{"row":[...]}]}
  이고, 에러는 최상위에 RESULT 만 온다(2026-10-20 실측):
    ERROR-290 인증키 무효 / ERROR-300 필수값 누락 → **즉시 멈춘다**
    INFO-200 해당 데이터 없음                    → 빈 쪽이다. 실패가 아니다.
  학교 API 때 이 지점에서 '조용한 0건' 을 만들었다. 같은 실수를 하지 않는다.

★ 좌표가 안 온다. 출력 25항목에 위도·경도도 PNU 도 건물관리번호도 없다.
  그래서 lat/lon/geog 는 **NULL 로 넣고** geocode_academy.py 가 나중에 채운다.
  geocode_status 를 NULL 로 두는 것이 '아직 안 했다' 는 표시다.

★ 학원지정번호는 시도교육청 안에서만 고유하다(버스 ARS 와 같은 함정).
  자연키에 시도교육청코드를 반드시 넣는다.

★ 한 학원이 여러 줄로 오는지 명세가 말해주지 않는다. 그래서 자연키에
  분야·계열·과정까지 넣고, 끝에 **'행 N / 서로 다른 학원지정번호 M'** 을 찍는다.
  추측하지 말고 세어서 안다.

★ 분야명·교습계열명의 묶음(화면 대분류)은 여기서 정하지 않는다.
  실제로 어떤 값이 오는지 끝에 전부 찍는다 — 그걸 보고 207 에 짠다.
"""
import argparse, hashlib, json, os, sys, time
import requests, pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
URL  = "https://open.neis.go.kr/hub/acaInsTiInfo"

# 출력명 -> 테이블 칸
F = [("ATPT_OFCDC_SC_CODE", "office_cd"), ("ATPT_OFCDC_SC_NM", "office_nm"),
     ("ADMST_ZONE_NM", "admst_zone_nm"), ("ACA_INSTI_SC_NM", "insti_sc_nm"),
     ("ACA_ASNUM", "aca_asnum"), ("ACA_NM", "aca_nm"),
     ("ESTBL_YMD", "estbl_ymd"), ("REG_YMD", "reg_ymd"),
     ("REG_STTUS_NM", "reg_sttus_nm"),
     ("CAA_BEGIN_YMD", "caa_begin_ymd"), ("CAA_END_YMD", "caa_end_ymd"),
     ("TOFOR_SMTOT", "tofor_smtot"), ("DTM_RCPTN_ABLTY_NMPR_SMTOT", "dtm_nmpr_smtot"),
     ("REALM_SC_NM", "realm_sc_nm"), ("LE_ORD_NM", "le_ord_nm"),
     ("LE_CRSE_LIST_NM", "le_crse_list_nm"), ("LE_CRSE_NM", "le_crse_nm"),
     ("PSNBY_THCC_CNTNT", "thcc_cntnt"), ("THCC_OTHBC_YN", "thcc_othbc_yn"),
     ("BRHS_ACA_YN", "brhs_aca_yn"),
     ("FA_RDNMA", "road_addr"), ("FA_RDNDA", "road_addr_dtl"),
     ("FA_RDNZC", "zip_no"), ("FA_TELNO", "tel_no"), ("LOAD_DTM", "load_dtm")]
COLS = [c for _, c in F]
KEYF = ["office_cd", "aca_asnum", "realm_sc_nm", "le_ord_nm", "le_crse_nm"]
INTF = {"tofor_smtot", "dtm_nmpr_smtot"}


def load_env(p):
    d = {}
    if not os.path.exists(p): return d
    for line in open(p, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line: continue
        k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def clean(v):
    """공백만 있는 칸은 NULL 로. CAA_BEGIN_YMD 가 '        ' 로 온다."""
    if v is None: return None
    s = str(v).strip()
    return s or None


def i(v):
    try: return int(float(str(v).strip()))
    except (TypeError, ValueError): return None


def digest(parts):
    return hashlib.sha256("\x1f".join("" if p is None else str(p)
                                      for p in parts).encode("utf-8")).digest()


def fetch(key, office, pindex, psize):
    """한 쪽. 돌려주는 것: (rows, total).  total 은 list_total_count."""
    p = {"KEY": key, "Type": "json", "pIndex": pindex, "pSize": psize,
         "ATPT_OFCDC_SC_CODE": office}
    last = None
    for a in range(4):
        try:
            r = requests.get(URL, params=p, timeout=60)
            r.raise_for_status()
            j = r.json()
            last = j
            break
        except Exception as e:
            last = {"_예외": f"{type(e).__name__}: {e}"}
            if a == 3:
                raise SystemExit(f"  {office} {pindex}쪽 — 네 번 다 실패: {last}")
            time.sleep(1.5 * (a + 1))

    # ★ 에러 봉투: 최상위에 RESULT 만 온다
    if "acaInsTiInfo" not in last:
        res = (last.get("RESULT") or {})
        code, msg = res.get("CODE", "?"), res.get("MESSAGE", "")
        if code == "INFO-200":
            return [], 0                      # 빈 쪽. 실패가 아니다
        raise SystemExit(f"  멈춥니다 — {code}: {msg}\n"
                         f"  (받은 최상위 키: {', '.join(sorted(last.keys()))})\n"
                         "  ERROR-290 이면 .env 의 NEIS_KEY 를 확인하세요.")

    blocks = last["acaInsTiInfo"]
    head = blocks[0].get("head") or []
    total = 0
    for h in head:
        if "list_total_count" in h: total = int(h["list_total_count"])
        if "RESULT" in h and h["RESULT"].get("CODE") not in ("INFO-000",):
            raise SystemExit(f"  멈춥니다 — head RESULT {h['RESULT']}")
    rows = []
    for b in blocks[1:]:
        rows += b.get("row") or []
    return rows, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--office", default="B10", help="시도교육청코드 (서울 B10)")
    ap.add_argument("--psize", type=int, default=1000)
    ap.add_argument("--probe", action="store_true")
    # ★ 2026-10-20: 경기도교육청(J10)은 경기 **전체**를 한 번에 준다. 우리가
    #   범위에 넣은 것은 안양 두 구뿐이라 전부 넣으면 지오코딩이 수만 건 늘어난다.
    #   그래서 받기는 교육청 단위로 받고, **넣기 전에** 행정구역명으로 거른다.
    #   ATPT 코드로는 시군구를 못 좁힌다 - API 가 그 인자를 받지 않는다.
    ap.add_argument("--only-zone", nargs="*", default=None,
                    help="행정구역명에 이 낱말이 든 것만 넣는다 (예: --only-zone 안양). "
                         "생략하면 전부 넣는다.")
    a = ap.parse_args()

    env = load_env(ENV)
    key = env.get("NEIS_KEY", "").strip()
    if not key:
        sys.exit(".env 에 NEIS_KEY 가 없습니다 "
                 "(open.neis.go.kr 로그인 → 인증키 신청)")

    rows, total = fetch(key, a.office, 1, 5 if a.probe else a.psize)
    if a.probe:
        print(f"총 {total:,}건 (한 쪽만 떠봤습니다)")
        if rows:
            print(json.dumps(rows[0], ensure_ascii=False, indent=2)[:1500])
        return
    if not total:
        print(f"{a.office}: 0건 — INFO-200(해당 데이터 없음) 입니다. 실패가 아닙니다.")
        return

    print(f"{a.office}: 기대 {total:,}건 · 쪽당 {a.psize}")
    got = list(rows)
    page = 1
    짧은쪽 = []
    while len(got) < total:
        if len(rows) < a.psize:
            # ★ 끝이 아닌데 쪽이 짧게 왔다 — 한도가 걸렸을 수 있다. 숨기지 않는다
            짧은쪽.append((page, len(rows)))
        page += 1
        rows, _ = fetch(key, a.office, page, a.psize)
        if not rows:
            print(f"  {page}쪽이 비었습니다 — 여기서 멈춥니다 "
                  f"(받은 {len(got):,} / 기대 {total:,})")
            break
        got += rows
        print(f"  {page}쪽 {len(rows):4d}건 · 누적 {len(got):,}", flush=True)
        time.sleep(0.1)

    # ---- 넣기 전에 거른다 ----
    if a.only_zone:
        전 = len(got)
        # ★ 행정구역명이 비어 있는 행은 **버리지 않고 남긴다.** 거르는 기준이
        #   없는 것을 '해당 없음' 으로 단정하면 조용히 데이터를 잃는다.
        낱말 = list(a.only_zone)
        뺀것, 남김, 모름 = [], [], 0
        for r in got:
            z = (r.get("ADMST_ZONE_NM") or "").strip()
            if not z:
                모름 += 1; 남김.append(r); continue
            (남김 if any(w in z for w in 낱말) else 뺀것).append(r)
        got = 남김
        print(f"\n  --only-zone {' '.join(낱말)} : {전:,}건 중 {len(got):,}건 남김 "
              f"(뺀 것 {len(뺀것):,} · 행정구역명 비어서 남긴 것 {모름:,})")
        if 모름:
            print(f"  ★ 행정구역명이 빈 {모름:,}건은 **버리지 않았다** - "
                  f"거를 근거가 없는 것은 지우지 않는다. 뒤에서 확인할 것.")
        if not got:
            print("  남은 것이 0건입니다 — 넣지 않고 끝냅니다.")
            return

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()

    ins = (f"UPDATE silver.academy SET is_current=0, valid_to=SYSDATETIME() "
           f"WHERE is_current=1 AND nat_key=%s AND row_hash<>%s")
    ins2 = (f"IF NOT EXISTS (SELECT 1 FROM silver.academy "
            f"WHERE is_current=1 AND nat_key=%s) "
            f"INSERT INTO silver.academy (nat_key, {', '.join(COLS)}, "
            f"row_hash, collected_at) "
            f"VALUES (%s, {', '.join(['%s'] * len(COLS))}, %s, "
            f"CONVERT(char(8), SYSDATETIME(), 112))")

    키중복 = {}
    넣음 = 0
    for d in got:
        v = {}
        for src, col in F:
            v[col] = i(d.get(src)) if col in INTF else clean(d.get(src))
        nk = digest([v[k] for k in KEYF])
        rh = digest([v[c] for c in COLS])
        키중복[nk] = 키중복.get(nk, 0) + 1
        cur.execute(ins, (nk, rh))
        cur.execute(ins2, (nk, nk) + tuple(v[c] for c in COLS) + (rh,))
        넣음 += 1
    conn.commit()

    # ---- 보고 ----
    print(f"\n받은 {len(got):,} / 기대 {total:,}", end="")
    print("  · 구멍 0  (정상)" if len(got) == total
          else f"  · ★ 구멍 {total - len(got):,}건")
    if 짧은쪽:
        print(f"  ★ 끝이 아닌데 짧게 온 쪽 {len(짧은쪽)}개: {짧은쪽[:5]}")
        print("     pSize 가 서버에서 깎였을 수 있습니다 — 그러면 쪽을 더 받아야 합니다.")

    겹친키 = sum(1 for n in 키중복.values() if n > 1)
    print(f"\n행 {len(got):,} / 서로 다른 자연키 {len(키중복):,}", end="")
    if 겹친키:
        print(f"  · ★ 겹친 자연키 {겹친키:,}개 — 자연키 고른 것이 틀렸습니다.\n"
              "     (분야·계열·과정 말고 무엇이 더 다른지 보고 KEYF 를 고쳐야 합니다)")
    else:
        print("  · 겹침 없음 (자연키가 맞습니다)")

    cur.execute("SELECT COUNT(DISTINCT aca_asnum) FROM silver.academy "
                "WHERE is_current=1 AND office_cd=%s", (a.office,))
    print(f"서로 다른 학원지정번호 {cur.fetchone()[0]:,}개 "
          "— 행 수와 같으면 '1줄 = 1학원' 입니다")

    for 칸, 이름 in (("reg_sttus_nm", "등록상태"), ("insti_sc_nm", "학원/교습소"),
                     ("realm_sc_nm", "분야명"), ("le_ord_nm", "교습계열명")):
        cur.execute(f"SELECT {칸}, COUNT(*) FROM silver.academy "
                    f"WHERE is_current=1 AND office_cd=%s "
                    f"GROUP BY {칸} ORDER BY COUNT(*) DESC", (a.office,))
        vals = cur.fetchall()
        print(f"\n{이름} {len(vals)}가지")
        for k, n in vals[:40]:
            print(f"  {n:7,}  {k}")
        if len(vals) > 40:
            print(f"  ... 외 {len(vals) - 40}가지")

    cur.execute("SELECT COUNT(*) FROM silver.academy "
                "WHERE is_current=1 AND office_cd=%s AND road_addr IS NULL", (a.office,))
    없음 = cur.fetchone()[0]
    print(f"\n도로명주소 없는 행 {없음:,}건", end="")
    print(" — 이건 지오코딩해도 좌표가 안 나옵니다" if 없음 else "  (전부 있습니다)")
    print("\n★ 좌표는 아직 비어 있습니다. geocode_academy.py 를 돌려야 지도·거리에 뜹니다.")
    conn.close()


if __name__ == "__main__":
    main()
