#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_rtms - 국토교통부 실거래가 10종 적재 + 단지 매칭

  ※ 한때 "11종" 으로 적혀 있었으나 KINDS 는 10개다. 공장창고 매매
    (RTMSDataSvcIndTrade) 는 엔드포인트를 못 찾아 빠져 있다.

  py load_rtms.py --sgg 11110 --from 202401 --to 202512            # 전 종목
  py load_rtms.py --sgg 11110 --from 202401 --to 202512 --kind RH_TRADE
  py load_rtms.py --rematch-only                                   # 다운로드 없이 매칭만

  --rematch-only 는 대장을 새로 적재해 단지가 생긴 뒤에 쓴다. 단지 매칭은
  다운로드와 무관한 일인데 예전에는 적재 루프 끝에만 있어서, 법정동 하나를
  추가할 때마다 실거래 10종 전체 재다운로드가 강제됐다 (CONTEXT.md 4-22 ③).

종목별 매칭 가능성
---------------------------------------------------------------
  APT_TRADE_DEV  코드 제공      -> PNU 직접 조립 (CODE_DIRECT)  ★최선
  APT_RENT / RH_* / OFFI_*      -> 법정동 이름 -> 코드 경유 (LAWD_JIBUN)
  SH_* / LAND_TRADE / NRG_TRADE -> 지번이 '1**' 로 마스킹. 조립 불가 (MASKED)

  단독주택·토지·상업용은 개인 식별을 막으려고 지번 뒷자리를 가린다.
  설계로 못 푸는 한계라, 법정동 단위 집계까지만 쓴다.

주의
  * 아파트는 구 엔드포인트(AptTrade) 대신 상세(AptTradeDev)를 쓴다.
    같은 거래인데 상세에만 코드가 있다.
  * API 가 거래 고유번호를 안 준다 -> 자연키 해시로 중복 차단
  * 해제 거래는 같은 거래가 다시 내려온다 -> 기존 행 UPDATE
  * 금액은 "63,000"(만원) -> 원 단위로 환산해 저장
"""
import argparse, hashlib, os, re, sys, time
import progress
import xml.etree.ElementTree as ET
import requests
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
B    = "https://apis.data.go.kr/1613000"

# kind -> (엔드포인트, 전월세여부, 지번마스킹여부)
KINDS = {
  "APT_TRADE_DEV": (f"{B}/RTMSDataSvcAptTradeDev/getRTMSDataSvcAptTradeDev", 0, 0),
  "APT_RENT":      (f"{B}/RTMSDataSvcAptRent/getRTMSDataSvcAptRent",         1, 0),
  "RH_TRADE":      (f"{B}/RTMSDataSvcRHTrade/getRTMSDataSvcRHTrade",         0, 0),
  "RH_RENT":       (f"{B}/RTMSDataSvcRHRent/getRTMSDataSvcRHRent",           1, 0),
  "OFFI_TRADE":    (f"{B}/RTMSDataSvcOffiTrade/getRTMSDataSvcOffiTrade",     0, 0),
  "OFFI_RENT":     (f"{B}/RTMSDataSvcOffiRent/getRTMSDataSvcOffiRent",       1, 0),
  "SH_TRADE":      (f"{B}/RTMSDataSvcSHTrade/getRTMSDataSvcSHTrade",         0, 1),
  "SH_RENT":       (f"{B}/RTMSDataSvcSHRent/getRTMSDataSvcSHRent",           1, 1),
  "LAND_TRADE":    (f"{B}/RTMSDataSvcLandTrade/getRTMSDataSvcLandTrade",     0, 1),
  "NRG_TRADE":     (f"{B}/RTMSDataSvcNrgTrade/getRTMSDataSvcNrgTrade",       0, 1),
  # ★ 2026-10-21: 아파트 분양권·입주권 전매. 지번은 **사업 전 지번**(청약홈 공고와 같다) — 단지에는 안 붙이고(282 가 건너뜀)
  #   PNU 까지만 둔다. 분양권/입주권 구분은 ownership_gbn(291). --kind SILV_TRADE 로만 부른다(전 종목 기본값에서 뺀다).
  "SILV_TRADE":    (f"{B}/RTMSDataSvcSilvTrade/getRTMSDataSvcSilvTrade",     0, 0),
}
KINDS_DEFAULT = [k for k in KINDS if k != "SILV_TRADE"]   # --kind 를 안 주면 예전과 같은 10 종목

JIBUN_RE = re.compile(r'^\s*(산)?\s*(\d+)(?:\s*-\s*(\d+))?\s*$')
TAIL_RE  = re.compile(r'\s*(산\s*)?\d+(-\d+)?\s*번?지?\s*$')


def load_env(p):
    d = {}
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    return d


def months(a, b):
    y, m = int(a[:4]), int(a[4:6]); ey, em = int(b[:4]), int(b[4:6]); out = []
    while (y, m) <= (ey, em):
        out.append(f"{y}{m:02d}")
        m += 1
        if m > 12: m, y = 1, y + 1
    return out


def seed_lawd(cur, conn):
    cur.execute("SELECT COUNT(*) FROM meta.lawd_code")
    if cur.fetchone()[0]:
        return 0
    cur.execute("""SELECT DISTINCT sigungu_cd + bjdong_cd, plat_plc
                     FROM silver.bld_basis_outline
                    WHERE is_current=1 AND sigungu_cd IS NOT NULL
                      AND bjdong_cd IS NOT NULL AND plat_plc IS NOT NULL""")
    seen, n = set(), 0
    for lawd, plc in cur.fetchall():
        if lawd in seen: continue
        seen.add(lawd)
        t = TAIL_RE.sub("", plc).strip().split()
        if len(t) < 3: continue
        cur.execute("""IF NOT EXISTS (SELECT 1 FROM meta.lawd_code WHERE lawd_cd=%s)
                       INSERT INTO meta.lawd_code (lawd_cd,sido_nm,sgg_nm,emd_nm,ri_nm,full_nm)
                       VALUES (%s,%s,%s,%s,%s,%s)""",
                    (lawd, lawd, t[0], t[1], t[2], t[3] if len(t) > 3 else None, " ".join(t)))
        n += 1
    conn.commit()
    return n


def fetch(url, key, sgg, ym, retries=3):
    out, page = [], 1
    while True:
        p = {"serviceKey": key, "LAWD_CD": sgg, "DEAL_YMD": ym,
             "numOfRows": "1000", "pageNo": str(page)}
        txt = None
        for a in range(retries):
            try:
                txt = requests.get(url, params=p, timeout=60).text; break
            except Exception:
                time.sleep(1.5 * (a + 1))
        if txt is None: return out, "NETWORK_FAIL"
        try: x = ET.fromstring(txt)
        except ET.ParseError: return out, "PARSE_FAIL"
        code = x.findtext(".//resultCode") or x.findtext(".//returnReasonCode")
        if code not in (None, "00", "000", "0"):
            msg = x.findtext(".//resultMsg") or x.findtext(".//returnAuthMsg") or ""
            return out, f"{code} {msg}"
        items = [{c.tag: (c.text or "").strip() for c in it} for it in x.iter("item")]
        if not items: break
        out += items
        tot = x.findtext(".//totalCount")
        tot = int(tot) if tot and tot.isdigit() else len(out)
        if page * 1000 >= tot: break
        page += 1; time.sleep(0.12)
    return out, "OK"


def money(s):
    s = (s or "").replace(",", "").strip()
    return int(float(s)) * 10000 if s.replace(".", "", 1).replace("-", "", 1).isdigit() else None


def num(s, f=float):
    s = (s or "").replace(",", "").strip()
    try: return f(float(s))
    except (ValueError, TypeError): return None


def pick(r, *names):
    """필드명이 종목마다 다르고 대소문자도 섞여 있다."""
    low = {k.lower(): v for k, v in r.items()}
    for n in names:
        v = low.get(n.lower())
        if v not in (None, ""): return v
    return None


def rematch(cur, conn, name2code_all):
    """이미 적재된 행의 매칭을 다시 계산한다.

    자연키가 같으면 INSERT 를 건너뛰므로, 첫 적재 때 법정동코드가 없어
    NO_LAWD 로 남은 행은 코드를 나중에 채워도 그대로 남는다.
    매번 끝에 이 패스를 돌려 현재 meta.lawd_code 기준으로 다시 맞춘다.
    (마스킹된 행은 영구히 불가하므로 건드리지 않는다)
    """
    cur.execute("""SELECT trade_sk, sgg_cd, umd_nm, jibun
                     FROM silver.rtms_trade
                    WHERE match_pnu IS NULL
                      AND jibun_masked = 0
                      AND match_method <> 'MASKED'""")
    rows = cur.fetchall()
    if not rows:
        return 0, 0
    fixed = still = 0
    for sk, sgg, umd, jib in rows:
        lawd = name2code_all.get((sgg, umd))
        m = JIBUN_RE.match(jib or "")
        if lawd and m:
            pnu = (f"{lawd}{'2' if m.group(1) else '1'}"
                   f"{int(m.group(2)):04d}{int(m.group(3) or 0):04d}")
            cur.execute("""UPDATE silver.rtms_trade
                              SET match_pnu=%s, match_method='LAWD_JIBUN', match_note=NULL
                            WHERE trade_sk=%s""", (pnu, sk))
            fixed += 1
        else:
            still += 1
            cur.execute("""UPDATE silver.rtms_trade
                              SET match_method=%s,
                                  match_note=%s
                            WHERE trade_sk=%s""",
                        ("NO_LAWD" if not lawd else "NONE",
                         (f"법정동 '{umd}' 코드 없음" if not lawd
                          else f"지번 파싱 실패: {jib}"), sk))
    conn.commit()
    return fixed, still


def match_pass(cur, conn, name2code_all, unknown=None):
    """다운로드와 무관하게 '지금 DB 상태' 기준으로 매칭을 다시 계산한다.

    두 단계가 서로 다른 것을 고친다:
      rematch()   법정동코드가 생겨 PNU 를 조립할 수 있게 된 행   (README 10장 ⑦)
      단지 매칭    대장이 들어와 단지가 생긴 PNU 에 붙이는 행      (CONTEXT 4-22 ③)

    둘 다 "행은 이미 있다" 와 "매칭이 끝났다" 를 구분하지 못해 생긴 자리다.
    적재와 분리돼 있어야 범위를 넓힐 때 재다운로드가 강제되지 않는다.
    """
    st = progress.Step("매칭 패스")
    fixed, still = rematch(cur, conn, name2code_all)
    if fixed or still:
        print(f"\n재매칭  복구 {fixed:,}건 / 여전히 불가 {still:,}건")

    print("\n단지 매칭")
    # ★ 2026-10-21 (CONTEXT 11-148): 예전엔 UPDATE ... JOIN complex_pnu 였다 — **한 필지에 단지가 여럿이면
    #   아무거나 하나**에 붙었다(잠실어린이집 5,195건 = 파크리오 거래). 규칙은 이제 프로시저 한 자리에 있다:
    #   주거 거래는 세대 있는 단지 > 대지 > 세대 많은 순, 오피스텔은 오피스텔 동이 있는 단지 먼저(282).
    #   이미 붙은 거래도 규칙과 다르면 고치고, 옛 값은 ops.rtms_rematch_log 에 남는다.
    cur.execute("EXEC gold.usp_match_complex_trade")
    r = cur.fetchone()
    conn.commit()
    if r:
        print(f"  회차 {r[0]} · 고쳐 붙음 {r[1]:,}건 · 새로 붙음 {r[2]:,}건 · {r[4]}초")
    cur.execute("EXEC gold.usp_refresh_complex_trade"); conn.commit()
    cur.execute("EXEC gold.usp_refresh_complex_alias"); cur.fetchall(); conn.commit()   # 285 실거래 이름
    st.done()

    cur.execute("""SELECT trade_kind, match_method, cnt, pnu_ok, complex_ok, canceled
                     FROM gold.v_rtms_match_quality ORDER BY trade_kind, cnt DESC""")
    print(f"\n  {'종목':16s} {'매칭방법':12s} {'건수':>7s} {'PNU':>7s} {'단지':>7s} {'해제':>6s}")
    for k, m, c, p, cx, ca in cur.fetchall():
        print(f"  {k:16s} {m or '-':12s} {c:7,d} {p or 0:7,d} {cx or 0:7,d} {ca or 0:6,d}")

    cur.execute("""SELECT COUNT(*), SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END)
                     FROM silver.rtms_trade""")
    tot, hit = cur.fetchone()
    print(f"\n  전체 {tot:,}건 중 단지 매칭 {hit or 0:,}건 ({100.0*(hit or 0)/max(tot,1):.1f}%)")
    if unknown:
        print("\n  법정동 코드를 못 찾은 이름 (적재 범위 밖):")
        for k, v in sorted(unknown.items(), key=lambda x: -x[1])[:8]:
            print(f"    {k:12s} {v:5d}건")
        print("    -> 해당 법정동 건축물대장을 적재하면 매칭됩니다")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg")
    ap.add_argument("--from", dest="ym_from")
    ap.add_argument("--to", dest="ym_to")
    ap.add_argument("--kind", action="append", choices=sorted(KINDS),
                    help="생략하면 전 종목")
    ap.add_argument("--no-match", action="store_true",
                    help="끝의 매칭 패스(전체 다시 붙이기 · 요약 재계산)를 건너뛴다. 여러 구를 나눠 받을 때 마지막에 한 번만 돌린다.")
    ap.add_argument("--rematch-only", action="store_true",
                    help="다운로드 없이 매칭만 다시 계산한다. "
                         "대장을 새로 적재해 단지가 생긴 뒤에 쓴다.")
    args = ap.parse_args()

    env = load_env(ENV)
    key = env.get("DATA_GO_KR_KEY", "").strip()
    if not args.rematch_only:
        need = [n for n, v in (("--sgg", args.sgg), ("--from", args.ym_from),
                               ("--to", args.ym_to)) if not v]
        if need:
            ap.error(f"{' '.join(need)} 가 필요합니다 (--rematch-only 가 아닌 경우)")
        if not key:
            sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있습니다")

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()

    n = seed_lawd(cur, conn)
    if n:
        print(f"meta.lawd_code 를 적재 데이터로 {n}건 생성 (적재 범위만 커버)\n")
    # 재매칭용 - 시군구 구분까지 포함한 전체 매핑
    cur.execute("SELECT sgg_cd, emd_nm, lawd_cd FROM meta.lawd_code WHERE emd_nm IS NOT NULL")
    name2code_all = {(r[0], r[1]): r[2] for r in cur.fetchall()}

    # 시군구와 무관하게 DB 전체를 다시 맞춘다. 다운로드 없음.
    if args.rematch_only:
        print("재매칭 전용 — 다운로드 없이 현재 대장·단지 기준으로 다시 계산합니다.")
        match_pass(cur, conn, name2code_all)
        conn.close()
        return

    cur.execute("SELECT emd_nm, lawd_cd FROM meta.lawd_code WHERE sgg_cd=%s", (args.sgg,))
    name2code = {r[0]: r[1] for r in cur.fetchall()}

    kinds = args.kind or sorted(KINDS_DEFAULT)   # 분양권은 --kind 로 따로
    ms = months(args.ym_from, args.ym_to)
    print(f"시군구 {args.sgg} · {ms[0]}~{ms[-1]} ({len(ms)}개월) · 종목 {len(kinds)}개")
    print(f"법정동 이름->코드 매핑 {len(name2code)}건\n")

    unknown = {}
    for kind in kinds:
        url, is_rent, masked = KINDS[kind]
        got = new = 0
        halted = None
        for ym in ms:
            rows, st = fetch(url, key, args.sgg, ym)
            if st != "OK":
                halted = st; break
            got += len(rows)
            for r in rows:
                yr, mo, dy = pick(r,"dealYear"), pick(r,"dealMonth"), pick(r,"dealDay")
                ymd = (f"{yr}{int(mo):02d}{int(dy):02d}"
                       if yr and mo and dy and str(mo).isdigit() and str(dy).isdigit() else None)
                umd  = pick(r, "umdNm")
                jib  = pick(r, "jibun")
                is_masked = bool(jib and "*" in jib) or (masked and not jib)

                # ---- PNU : 코드가 있으면 직접, 없으면 이름 경유 ----
                sgg_cd = pick(r,"sggCd") or args.sgg
                umd_cd = pick(r,"umdCd")
                land   = pick(r,"landCd")
                bon, bub = pick(r,"bonbun"), pick(r,"bubun")
                pnu = None; method = "NONE"; note = None
                if umd_cd and bon:
                    san = "2" if str(land) == "2" else "1"
                    pnu = f"{sgg_cd}{umd_cd}{san}{int(bon):04d}{int(bub or 0):04d}"
                    method = "CODE_DIRECT"
                elif is_masked:
                    method = "MASKED"; note = f"지번 마스킹: {jib}"
                else:
                    lawd = name2code.get(umd)
                    if not lawd:
                        method = "NO_LAWD"; note = f"법정동 '{umd}' 코드 없음"
                        if umd: unknown[umd] = unknown.get(umd, 0) + 1
                    else:
                        m = JIBUN_RE.match(jib or "")
                        if m:
                            pnu = (f"{lawd}{'2' if m.group(1) else '1'}"
                                   f"{int(m.group(2)):04d}{int(m.group(3) or 0):04d}")
                            method = "LAWD_JIBUN"
                        else:
                            note = f"지번 파싱 실패: {jib}"

                rsgg, rcd = pick(r,"roadNmSggCd","roadnmsggcd"), pick(r,"roadNmCd","roadnmcd")
                vals = dict(
                    trade_kind=kind, is_rent=is_rent,
                    sgg_cd=sgg_cd, umd_cd=umd_cd, umd_nm=umd, land_cd=land,
                    bonbun=bon, bubun=bub, jibun=jib, jibun_masked=1 if is_masked else 0,
                    road_nm=pick(r,"roadNm","roadnm"),
                    road_cd=(f"{rsgg}{rcd}" if rsgg and rcd else None),
                    road_bonbun=pick(r,"roadNmBonbun","roadnmbonbun"),
                    road_bubun=pick(r,"roadNmBubun","roadnmbubun"),
                    bld_nm=pick(r,"aptNm","mhouseNm","offiNm"),
                    bld_dong=pick(r,"aptDong"),
                    house_type=pick(r,"houseType"),
                    building_use=pick(r,"buildingUse"), building_type=pick(r,"buildingType"),
                    land_use=pick(r,"landUse"), jimok=pick(r,"jimok"),
                    apt_seq=pick(r,"aptSeq"),
                    deal_ymd=ymd, deal_year=num(yr,int), deal_month=num(mo,int),
                    deal_amount=money(pick(r,"dealAmount")),
                    deposit=money(pick(r,"deposit")),
                    monthly_rent=money(pick(r,"monthlyRent")),
                    pre_deposit=money(pick(r,"preDeposit")),
                    pre_monthly_rent=money(pick(r,"preMonthlyRent")),
                    contract_term=pick(r,"contractTerm"), contract_type=pick(r,"contractType"),
                    use_rr_right=pick(r,"useRRRight"),
                    exclu_use_ar=num(pick(r,"excluUseAr")),
                    total_floor_ar=num(pick(r,"totalFloorAr")),
                    plottage_ar=num(pick(r,"plottageAr")),
                    building_ar=num(pick(r,"buildingAr")),
                    land_ar=num(pick(r,"landAr")),
                    deal_area=num(pick(r,"dealArea")),
                    floor_no=num(pick(r,"floor"),int), build_year=num(pick(r,"buildYear"),int),
                    dealing_gbn=pick(r,"dealingGbn"), buyer_gbn=pick(r,"buyerGbn"),
                    sler_gbn=pick(r,"slerGbn"), share_dealing=pick(r,"shareDealingType"),
                    estate_agent_sgg=pick(r,"estateAgentSggNm"),
                    land_leasehold=pick(r,"landLeaseholdGbn"), rgst_date=pick(r,"rgstDate"),
                    ownership_gbn=pick(r,"ownershipGbn"),          # 분양권 '분' / 입주권 '입' (SILV_TRADE 만)
                    match_pnu=pnu, match_method=method, match_note=note,
                )
                nat = hashlib.sha256("\x1f".join(str(vals[k]) for k in (
                    "trade_kind","sgg_cd","umd_nm","jibun","bld_nm","bld_dong","deal_ymd",
                    "deal_amount","deposit","monthly_rent","exclu_use_ar","total_floor_ar",
                    "floor_no")).encode()).digest()

                cur.execute("UPDATE silver.rtms_trade SET cdeal_type=%s, cdeal_day=%s "
                            "WHERE nat_key=%s",
                            (pick(r,"cdealType"), pick(r,"cdealDay"), nat))
                if cur.rowcount == 0:
                    cols = list(vals.keys())
                    cur.execute(
                        f"INSERT INTO silver.rtms_trade (nat_key, {', '.join(cols)}, cdeal_type, cdeal_day) "
                        f"VALUES (%s, {', '.join(['%s']*len(cols))}, %s, %s)",
                        (nat,) + tuple(vals[c] for c in cols)
                        + (pick(r,"cdealType"), pick(r,"cdealDay")))
                    new += 1
            conn.commit()
        tag = f"  {kind:14s} 수신 {got:5d}  신규 {new:5d}"
        print(tag + (f"   [중단: {halted}]" if halted else ""))

    if getattr(args, "no_match", False):
        print("\n(--no-match: 매칭 패스 건너뜀)")
    else:
        match_pass(cur, conn, name2code_all, unknown)
    conn.close()


if __name__ == "__main__":
    main()
