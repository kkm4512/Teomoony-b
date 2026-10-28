#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_kapt_cost - 관리비 3개 서비스를 silver.kapt_cost 에 적재

  py load_kapt_cost.py --lawd 1129013800 --ym 202412
  py load_kapt_cost.py --sgg 11290 --from 202401 --to 202412
  py load_kapt_cost.py --sgg 11290 --months 12          # 최근 12개월

왜 long 테이블인가 (정책.md 3-9, CONTEXT.md 4-30)
  "같은 이름의 항목에 단지마다 다른 게 들어있다" 가 이 축의 핵심 함정이다.
  전기료는 electC(공용부)/electP(세대부) 두 개이고, 장위참누리는 electP 가 0 이다
  (세대 전기를 한전이 직공급). 난방은 장위동 11/11 이 0 이다(개별난방).
  그래서 **원본 필드명을 그대로** 저장한다. 넓은 테이블로 접으면 어느 숫자가
  어디서 왔는지 잃고, 그 상태로 합계를 내면 조용히 틀린다.

주의
  * 오퍼레이션 이름은 추측으로 맞힐 수 없다. 2026-10-16 에 340개를 찍어보고
    전부 틀렸다. 포털의 openapi 상세 페이지에서 긁어 확정한 것이 아래 OPS 다.
    포털 문서는 개별사용료를 V2 이름으로 보여주는데 **실제로는 V3 만 동작한다.**
  * 서비스당 일일 트래픽이 있다. 단지 하나당 31 호출이라 성북구 148개면
    4,588 호출이다. 서비스별로는 CMN 17×148, IND 10×148, REP 4×148 로 나뉜다.
  * data.go.kr 은 장애를 HTTP 200 으로 돌려준다. 에러 바디는 실패로 다룬다.
    아니면 "값 없음" 으로 착각해 0 을 적재한다.
  * 키는 kaptCode 다. 정식 단지(ROOT_PK)와는 코드로 안 붙는다(정책.md 4장).
    관리비는 K-apt 축 위에만 산다.
"""
import argparse, json, os, sys, time
from concurrent.futures import ThreadPoolExecutor
from datetime import date
import requests
import pymssql

import progress
from _rate import 조절기
# ★ 2026-10-24 17:05: 27구 × 16스레드(동시 432)로 과거 관리비를 받자 K-apt 쪽이 HTTP_ERROR(04)로 막았다(실거래 API 는 멀쩡 — 이 서비스만).
#   속도를 프로세스마다 맞춘다(--rps · 막히면 절반 + 쉼). 구 여러 개를 동시에 돌리면 합이 '구 수 × rps' 다.
조절 = 조절기(10, 20, 60)

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
BASE = "https://apis.data.go.kr/1613000"
LIST = f"{BASE}/AptListService4/getLegaldongAptList4"

CMN = "AptCmnuseManageCostServiceV3"
IND = "AptIndvdlzManageCostServiceV3"
REP = "AptRepairsCostServiceV3"

# (svc, service_path, operation)  — 31개. 포털 상세에서 확정, 2026-10-16 실호출 검증.
OPS = [
    ("CMN", CMN, "getHsmpLaborCostInfoV3"),               # 인건비
    ("CMN", CMN, "getHsmpTaxdueInfoV3"),                  # 제세공과금
    ("CMN", CMN, "getHsmpVhcleMntncCostInfoV3"),          # 차량유지비
    ("CMN", CMN, "getHsmpEtcCostInfoV3"),                 # 기타 부대비용
    ("CMN", CMN, "getHsmpOfcrkCostInfoV3"),               # 제사무비
    ("CMN", CMN, "getHsmpClothingCostInfoV3"),            # 피복비
    ("CMN", CMN, "getHsmpEduTraingCostInfoV3"),           # 교육훈련비
    ("CMN", CMN, "getHsmpCleaningCostInfoV3"),            # 청소비
    ("CMN", CMN, "getHsmpGuardCostInfoV3"),               # 경비비
    ("CMN", CMN, "getHsmpDisinfectionCostInfoV3"),        # 소독비
    ("CMN", CMN, "getHsmpElevatorMntncCostInfoV3"),       # 승강기 유지비
    ("CMN", CMN, "getHsmpHomeNetworkMntncCostInfoV3"),    # 지능형 홈네트워크
    ("CMN", CMN, "getHsmpRepairsCostInfoV3"),             # 수선비
    ("CMN", CMN, "getHsmpFacilityMntncCostInfoV3"),       # 시설유지비
    ("CMN", CMN, "getHsmpSafetyCheckUpCostInfoV3"),       # 안전점검비
    ("CMN", CMN, "getHsmpDisasterPreventionCostInfoV3"),  # 재해예방비
    ("CMN", CMN, "getHsmpConsignManageFeeInfoV3"),        # 위탁관리수수료
    ("IND", IND, "getHsmpHeatCostInfoV3"),                # 난방비
    ("IND", IND, "getHsmpHotWaterCostInfoV3"),            # 급탕비
    ("IND", IND, "getHsmpGasRentalFeeInfoV3"),            # 가스사용료
    ("IND", IND, "getHsmpElectricityCostInfoV3"),         # 전기료
    ("IND", IND, "getHsmpWaterCostInfoV3"),               # 수도료
    ("IND", IND, "getHsmpWaterPurifierTankFeeInfoV3"),    # 정화조오물수수료
    ("IND", IND, "getHsmpDomesticWasteFeeInfoV3"),        # 생활폐기물수수료
    ("IND", IND, "getHsmpBuildingInsuranceFeeInfoV3"),    # 건물보험료
    ("IND", IND, "getHsmpMovingInRepresentationMtgInfoV3"),  # 입주자대표회의 운영비
    ("IND", IND, "getHsmpElectionOrpnsInfoV3"),           # 선거관리위원회 운영비
    ("REP", REP, "getHsmpMonthFeeInfoV3"),                # 장충 월 부과액   sLevy
    ("REP", REP, "getHsmpReserveBalanceInfoV3"),          # 장충 적립 잔액   sTot
    ("REP", REP, "getHsmpAccumulationTariffInfoV3"),      # 장충 적립 요율   sPer
    ("REP", REP, "getHsmpMonthRetalFeeInfoV3"),           # 장충 월 사용액   sUse
]

SKIP_FIELDS = {"kaptCode", "kaptName"}


def load_env(path):
    d = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    return d


def get(url, key, params, retries=4):
    """에러 바디(HTTP 200)를 실패로 다룬다. load_kapt.get() 과 같은 이유."""
    p = dict(params); p["serviceKey"] = key
    for a in range(retries):
        조절.기다림()
        try:
            r = requests.get(url, params=p, timeout=40)
            if r.status_code == 200:
                try:
                    j = r.json()
                except Exception:
                    return None
                if isinstance(j, dict) and "OpenAPI_ServiceResponse" in j:
                    # ★ 하루 호출 한도를 넘으면 계속 두드려도 다 실패다 — 받은 데까지 두고 **멈춘다**(다음 날 같은 명령이 빈 것만 채운다)
                    if "LIMITED_NUMBER_OF_SERVICE_REQUESTS" in json.dumps(j) or '"22"' in json.dumps(j):
                        print("\n★ data.go.kr 하루 호출 한도 초과 — 여기서 멈춥니다(받은 것은 그대로)", flush=True)
                        os._exit(3)
                    조절.실패()          # HTTP_ERROR(04) — K-apt 쪽이 버거워한다. 다 같이 쉰다
                    time.sleep(1.5 * (a + 1))
                    continue
                조절.성공()
                return j
            조절.실패()
        except Exception:
            조절.실패()
        time.sleep(1.0 * (a + 1))
    return None


def item_of(j):
    """응답 -> item dict. 없으면 {} (데이터 없음), 호출 실패는 None 으로 구분."""
    if j is None:
        return None
    it = ((j.get("response") or {}).get("body") or {}).get("item")
    return it if isinstance(it, dict) else {}


def to_num(v):
    try:
        s = str(v).strip().replace(",", "")
        if s in ("", "None", "-"):
            return None
        return float(s)
    except Exception:
        return None


def months(a, b):
    """'202401','202412' -> ['202401',...,'202412']"""
    y, m = int(a[:4]), int(a[4:6]); ey, em = int(b[:4]), int(b[4:6])
    out = []
    while (y, m) <= (ey, em):
        out.append(f"{y:04d}{m:02d}")
        m += 1
        if m == 13:
            y, m = y + 1, 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lawd", action="append", help="법정동코드 10자리")
    ap.add_argument("--sgg",  action="append", help="시군구코드 5자리")
    ap.add_argument("--db-list", action="store_true",
                    help="2026-10-28 전국: 단지 목록을 K-apt 목록 API(법정동마다 1회 · 서비스당 하루 5,000) 대신 이미 받은 silver.kapt_complex 에서")
    ap.add_argument("--ym",   action="append", help="YYYYMM (여러 번 가능)")
    ap.add_argument("--from", dest="ym_from")
    ap.add_argument("--to",   dest="ym_to")
    ap.add_argument("--months", type=int, help="최근 N개월 (전월 기준 역순)")
    ap.add_argument("--svc", action="append", choices=["CMN", "IND", "REP"],
                    help="서비스만 골라 적재 (트래픽을 나눠 돌릴 때)")
    ap.add_argument("--threads", type=int, default=8, help="한 단지·한 달의 오퍼레이션을 같이 부를 스레드 수(2026-10-24)")
    ap.add_argument("--rps", type=float, default=10.0, help="이 프로세스의 초당 호출 수 상한(처음 값 · 스스로 올리고 내림)")
    args = ap.parse_args()
    global 조절
    조절 = 조절기(args.rps, args.rps * 2, 60)

    env = load_env(ENV)
    key = env.get("DATA_GO_KR_KEY")
    if not key:
        sys.exit(".env 의 DATA_GO_KR_KEY 가 없습니다.")

    yms = list(args.ym or [])
    if args.ym_from and args.ym_to:
        yms += months(args.ym_from, args.ym_to)
    if args.months:
        t = date.today()
        y, m = t.year, t.month - 1          # 전월까지. 당월은 아직 안 올라온다
        if m == 0:
            y, m = y - 1, 12
        for _ in range(args.months):
            yms.append(f"{y:04d}{m:02d}")
            m -= 1
            if m == 0:
                y, m = y - 1, 12
    yms = sorted(set(yms))
    if not yms:
        sys.exit("대상 월이 없습니다. --ym / --from+--to / --months 중 하나를 주세요.")

    ops = [o for o in OPS if not args.svc or o[0] in args.svc]

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()

    lawds = list(args.lawd or [])
    for sgg in (args.sgg or []):
        cur.execute("SELECT lawd_cd FROM meta.lawd_code WHERE sgg_cd=%s ORDER BY lawd_cd", (sgg,))
        lawds += [r[0] for r in cur.fetchall()]
    lawds = sorted(set(lawds))
    if not lawds:
        sys.exit("대상 법정동이 없습니다. --lawd 또는 --sgg 를 주세요.")

    # 단지 목록은 월과 무관하므로 한 번만 받는다
    st = progress.Step(f"단지 목록 — 법정동 {len(lawds)}개" + (" (DB)" if args.db_list else ""))
    codes = []
    if args.db_list:
        # ★ 2026-10-28: 전국 19,487 법정동을 목록 API 로 부르면 K-apt 목록 서비스 하루 한도를 다 쓴다 — 주간 K-apt 갱신이 받아 둔 표를 쓴다
        cur.execute("SELECT DISTINCT kapt_code FROM silver.kapt_complex WHERE is_current = 1 AND LEFT(bjd_code, 5) IN (" +
                    ",".join(["%s"] * len(set(l[:5] for l in lawds))) + ")", tuple(sorted(set(l[:5] for l in lawds))))
        codes = [r[0].strip() for r in cur.fetchall() if r[0]]
        lawds_api = []
    else:
        lawds_api = lawds
    for lawd in lawds_api:
        j = get(LIST, key, {"bjdCode": lawd, "numOfRows": 500, "pageNo": 1})
        items = (((j or {}).get("response") or {}).get("body") or {}).get("items") or []
        if isinstance(items, dict):
            items = items.get("item") or []
        if isinstance(items, dict):
            items = [items]
        for it in items:
            c = (it.get("kaptCode") or "").strip()
            if c:
                codes.append(c)
    codes = sorted(set(codes))
    st.done(f"단지 {len(codes)}개")
    if not codes:
        sys.exit("단지가 없습니다.")

    calls = len(codes) * len(yms) * len(ops)
    print(f"월 {len(yms)}개 × 단지 {len(codes)}개 × 오퍼레이션 {len(ops)}개 = 호출 {calls:,}회")
    # tick 은 단지-월 하나가 끝날 때만. 호출마다 찍으면 수천 줄이 쏟아진다.
    pg = progress.Progress(len(codes) * len(yms), "관리비")

    풀 = ThreadPoolExecutor(max_workers=max(1, args.threads))
    ins = upd = same = empty = fail = unknown = 0
    allzero = 0
    seen_unknown = set()
    for ym in yms:
        for code in codes:
            rows = []
            broke = False
            # ★ 2026-10-24 사장님 "운영키 · 스레드 최대한": 한 단지·한 달의 31 오퍼레이션을 **같이** 부른다(예전엔 하나씩 — 단지 하나에 6초).
            #   쓰기는 아래에서 이 스레드 하나가 순서대로 한다(DB 연결은 하나).
            결과 = list(풀.map(lambda o: (o, item_of(get(f"{BASE}/{o[1]}/{o[2]}", key, {"kaptCode": code, "searchDate": ym}))), ops))
            for (svc, path, op), it in 결과:
                if it is None:
                    fail += 1
                    broke = True
                    continue
                if not it:
                    empty += 1
                    continue
                for k, v in it.items():
                    if k in SKIP_FIELDS:
                        continue
                    n = to_num(v)
                    if n is None:
                        continue
                    rows.append((svc, op, k, n))
                    if (op, k) not in seen_unknown:
                        seen_unknown.add((op, k))
            pg.tick(f"{ym} {code}  항목 {len(rows)}")
            if broke and not rows:
                continue
            # ★ 2026-10-24(과거 이력 받기 전 실측): **공개 전 달은 항목이 전부 0 으로 온다**(올림픽선수기자촌 2014.01 인건비 9칸 모두 0 · 2015.01 부터 값).
            #   0 을 그대로 넣으면 '관리비 0원' 이라는 거짓이 된다. 한 단지·한 달의 31 오퍼레이션 값이 **모두 0** 이면 '자료 없음' 으로 본다.
            #   (한 항목만 0 인 것은 진짜 0 일 수 있다 — 개별난방 단지의 난방비 등 — 그대로 둔다.)
            if rows and all(r[3] == 0 for r in rows):
                allzero += 1
                continue
            for svc, op, fld, amt in rows:
                cur.execute("""
MERGE silver.kapt_cost AS t
USING (SELECT CAST(%s AS VARCHAR(20)) AS kapt_code, CAST(%s AS CHAR(6)) AS ym, CAST(%s AS VARCHAR(3)) AS svc,
              CAST(%s AS VARCHAR(60)) AS op, CAST(%s AS VARCHAR(40)) AS fld,
              CAST(%s AS DECIMAL(20,4)) AS amount) AS s
/* 2026-10-23: 문자열 파라미터가 nvarchar 로 와서 열 쪽 변환 → 표를 통째로 훑었다(NED 때와 같은 일) — 열 형식으로 CAST */
   ON t.kapt_code = s.kapt_code AND t.ym = s.ym AND t.op = s.op AND t.fld = s.fld
/* (a IS NULL) <> (b IS NULL) 은 T-SQL 에서 문법 오류다 — 불리언을 값으로 못 쓴다.
   s.amount 는 NULL 로 올 일이 없다(to_num 이 None 이면 적재를 건너뛴다). */
WHEN MATCHED AND (t.amount IS NULL OR t.amount <> s.amount)
     THEN UPDATE SET t.amount = s.amount, t.chg_cnt = t.chg_cnt + 1,
                     t.loaded_at = SYSDATETIME()
WHEN NOT MATCHED BY TARGET
     THEN INSERT (kapt_code, ym, svc, op, fld, amount)
          VALUES (s.kapt_code, s.ym, s.svc, s.op, s.fld, s.amount)
OUTPUT $action;""", (code, ym, svc, op, fld, amt))
                act = (cur.fetchone() or ["NONE"])[0]
                if act == "INSERT":
                    ins += 1
                elif act == "UPDATE":
                    upd += 1
                else:
                    same += 1
            conn.commit()
    pg.done()

    # 사전에 없는 필드를 알려준다 — API 가 항목을 추가하면 여기서 드러난다
    cur.execute("""SELECT DISTINCT c.op, c.fld FROM silver.kapt_cost c
                    LEFT JOIN meta.kapt_cost_item d ON d.op=c.op AND d.fld=c.fld
                   WHERE d.op IS NULL ORDER BY c.op, c.fld""")
    miss = cur.fetchall()
    print(f"\n신규 {ins:,} | 변경 {upd:,} | 동일 {same:,} | 데이터없음 {empty:,} | 전부0(공개 전 달) {allzero:,} | 호출실패 {fail:,}")
    if miss:
        print(f"\n사전(meta.kapt_cost_item)에 없는 필드 {len(miss)}개 — 뜻을 확인해 추가할 것:")
        for op, fld in miss:
            print(f"    {op}.{fld}")
    if fail:
        print("\n호출실패가 있으면 포털 장애일 수 있다. 같은 명령을 다시 돌리면 빈 것만 채워진다.")
    conn.close()


if __name__ == "__main__":
    main()
