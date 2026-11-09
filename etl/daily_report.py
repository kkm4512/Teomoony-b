#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""daily_report - 하루 한 번 슬랙으로: ① 오픈 API 키 상태 ② 배치(수집 일정) 결과 ③ 이용 현황  (2026-11-09 사장님 "하루에 한번 정리해서 슬랙으로")

  python daily_report.py           모아서 슬랙으로 보낸다(수집 일정 cl-daily-report-par · 매일 08:30)
  python daily_report.py --dry     보내지 않고 화면에만

★ 키 · 웹후크 주소는 화면 · 로그 · 슬랙에 안 낸다(응답 글을 옮길 때 키 값은 *** 로 지운다).
★ 한 곳이 실패해도 나머지는 센다 — 리포트를 못 만든 칸은 '못 셈 (이유)' 로 그대로 보낸다.
★ API 확인은 키마다 가장 가벼운 호출 1건(1줄 · 1쪽). 하루 30건 남짓.
★ 시각: ops.collect_run · 접속 기록(app.req_log)은 한국시간 벽시계 값이다.
"""
import os, sys, re, json, datetime, traceback, urllib.parse
from concurrent.futures import ThreadPoolExecutor
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
KST = datetime.timezone(datetime.timedelta(hours=9))
NOW = datetime.datetime.now(KST)
TODAY = NOW.date()
YDAY = TODAY - datetime.timedelta(days=1)


def env():
    d = {}
    for ln in open(os.path.join(HERE, "..", ".env"), encoding="utf-8"):
        ln = ln.strip()
        if ln and not ln.startswith("#") and "=" in ln:
            k, v = ln.split("=", 1); d[k.strip()] = v.strip().strip('"').strip("'")
    return d


E = env()
SECRETS = [v for k, v in E.items() if len(v) >= 8 and any(s in k for s in ("KEY", "SECRET", "TOKEN", "PASSWORD", "WEBHOOK"))]


def hide(s):
    s = str(s)
    for v in SECRETS:
        s = s.replace(v, "***")
        s = s.replace(urllib.parse.quote(v, safe=""), "***")
    return s


# ---------------------------------------------------------------- ① API 키 상태
# 만료일이 있는 키(API키_유효기간.md) — 45일 안으로 들어오면 경고
EXPIRES = [
    ("브이월드 VWORLD_KEY(개발키)", datetime.date(2027, 4, 13), "브이월드 → 인증키 관리 → 연장(만료일 전에만)"),
    ("브이월드 VWORLD_NED_KEY(개발키)", datetime.date(2027, 4, 20), "브이월드 → 인증키 관리 → 연장(만료일 전에만)"),
    ("보육정보 CHILDCARE_KEY(운영)", datetime.date(2027, 10, 20), "보육정보공개 API → 이용 신청현황 → 갱신 신청"),
    ("공공데이터포털(가장 이른 신청 추정)", datetime.date(2028, 10, 14), "data.go.kr 마이페이지 → 개발계정 → 연장"),
]
WARN_DAYS = 45

AUTH = re.compile(r"SERVICE_KEY_IS_NOT_REGISTERED|DEADLINE_HAS_EXPIRED|SERVICE_ACCESS_DENIED|UNREGISTERED|INCORRECT_KEY|EXPIRE_KEY|"
                  r"INVALID_KEY|승인되지 않은|인증키가 (만료|유효하지)|ERROR-290|INFO-100|Unauthorized|등록되지 않은 인증키|invalid x-api-key|authentication_error|"
                  r"유효하지 않은 (apiKey|키)|\"status\"\s*:\s*\"DENIED|\"errCd\"\s*:\s*-401|consumer_key", re.I)
QUOTA = re.compile(r"LIMITED_NUMBER_OF_SERVICE_REQUESTS|EXCEEDS|호출 ?한도|OVER_REQUEST_LIMIT", re.I)

K = E.get("DATA_GO_KR_KEY", "")
ym2 = (TODAY.replace(day=1) - datetime.timedelta(days=1)).strftime("%Y%m")          # 지난달
ym3 = ((TODAY.replace(day=1) - datetime.timedelta(days=1)).replace(day=1) - datetime.timedelta(days=1)).strftime("%Y%m")   # 두 달 전
B = "https://apis.data.go.kr/1613000"


def ok_dgk(r):      # 공공데이터포털: XML resultCode 00/000 · JSON header.resultCode
    t = r.text
    if re.search(r"<resultCode>\s*0+\s*</resultCode>", t): return True
    try:
        j = r.json()
        h = (j.get("response") or {}).get("header") or j.get("header") or {}
        if str(h.get("resultCode", "")).strip("0") == "" and str(h.get("resultCode", "")) != "": return True
        if isinstance(j.get("data"), list) or "currentCount" in j or "totalCount" in j: return True   # odcloud · 표준데이터
    except ValueError:
        pass
    return False


def J(path, *keys):
    def f(r):
        try:
            x = r.json()
            for k in path:
                x = x[k] if not isinstance(x, list) else x[k]
            return x in keys if keys else bool(x)
        except Exception:
            return False
    return f


KAPT = {}


def kapt_code():
    if "c" not in KAPT:
        r = requests.get(f"{B}/AptListService4/getLegaldongAptList4",
                         params={"serviceKey": K, "bjdCode": "1111011500", "numOfRows": 5, "pageNo": 1, "_type": "json"}, timeout=25)
        m = re.search(r'"kaptCode"\s*:\s*"([A-Z0-9]+)"', r.text) or re.search(r"<kaptCode>([A-Z0-9]+)</kaptCode>", r.text)
        KAPT["c"] = m.group(1) if m else "A10027875"
    return KAPT["c"]


def P(**kw): return kw


CHECKS = [
    # (무리, 이름, 키 이름, url, params(함수 가능), 정상 판정)
    ("공공데이터포털", "실거래 아파트 매매", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcAptTradeDev/getRTMSDataSvcAptTradeDev", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "실거래 아파트 전월세", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcAptRent/getRTMSDataSvcAptRent", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "실거래 연립다세대 매매", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcRHTrade/getRTMSDataSvcRHTrade", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "실거래 연립다세대 전월세", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcRHRent/getRTMSDataSvcRHRent", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "실거래 오피스텔 매매", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcOffiTrade/getRTMSDataSvcOffiTrade", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "실거래 오피스텔 전월세", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcOffiRent/getRTMSDataSvcOffiRent", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "실거래 단독다가구 매매", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcSHTrade/getRTMSDataSvcSHTrade", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "실거래 단독다가구 전월세", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcSHRent/getRTMSDataSvcSHRent", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "실거래 토지 매매", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcLandTrade/getRTMSDataSvcLandTrade", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "실거래 상업업무용 매매", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcNrgTrade/getRTMSDataSvcNrgTrade", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "실거래 분양권전매", "DATA_GO_KR_KEY", f"{B}/RTMSDataSvcSilvTrade/getRTMSDataSvcSilvTrade", lambda: P(serviceKey=K, LAWD_CD="11110", DEAL_YMD=ym2, numOfRows=1, pageNo=1), ok_dgk),
    ("공공데이터포털", "건축HUB 건축물대장", "DATA_GO_KR_KEY", f"{B}/BldRgstHubService/getBrTitleInfo", lambda: P(serviceKey=K, sigunguCd="11110", bjdongCd="10100", numOfRows=1, pageNo=1, _type="json"), ok_dgk),
    ("공공데이터포털", "건축HUB 건축인허가", "DATA_GO_KR_KEY", f"{B}/ArchPmsHubService/getApBasisOulnInfo", lambda: P(serviceKey=K, sigunguCd="11110", bjdongCd="10100", numOfRows=1, pageNo=1, _type="json"), ok_dgk),
    ("공공데이터포털", "건축HUB 주택인허가", "DATA_GO_KR_KEY", f"{B}/ShtRgstHubService/getSrTitleInfo", lambda: P(serviceKey=K, sigunguCd="11110", bjdongCd="10100", numOfRows=1, pageNo=1, _type="json"), ok_dgk),
    ("공공데이터포털", "공동주택 단지 목록", "DATA_GO_KR_KEY", f"{B}/AptListService4/getLegaldongAptList4", lambda: P(serviceKey=K, bjdCode="1111011500", numOfRows=1, pageNo=1, _type="json"), ok_dgk),
    ("공공데이터포털", "공동주택 기본정보", "DATA_GO_KR_KEY", f"{B}/AptBasisInfoServiceV5/getAphusBassInfoV5", lambda: P(serviceKey=K, kaptCode=kapt_code(), _type="json"), ok_dgk),
    ("공공데이터포털", "관리비 공용", "DATA_GO_KR_KEY", f"{B}/AptCmnuseManageCostServiceV3/getHsmpLaborCostInfoV3", lambda: P(serviceKey=K, kaptCode=kapt_code(), searchDate=ym3, _type="json"), ok_dgk),
    ("공공데이터포털", "관리비 개별", "DATA_GO_KR_KEY", f"{B}/AptIndvdlzManageCostServiceV3/getHsmpHeatCostInfoV3", lambda: P(serviceKey=K, kaptCode=kapt_code(), searchDate=ym3, _type="json"), ok_dgk),
    ("공공데이터포털", "관리비 장기수선", "DATA_GO_KR_KEY", f"{B}/AptRepairsCostServiceV3/getHsmpMonthFeeInfoV3", lambda: P(serviceKey=K, kaptCode=kapt_code(), searchDate=ym3, _type="json"), ok_dgk),
    ("공공데이터포털", "청약홈 분양정보", "DATA_GO_KR_KEY", "https://api.odcloud.kr/api/ApplyhomeInfoDetailSvc/v1/getAPTLttotPblancDetail", lambda: P(serviceKey=K, page=1, perPage=1), ok_dgk),
    ("공공데이터포털", "청약홈 경쟁률", "DATA_GO_KR_KEY", "https://api.odcloud.kr/api/ApplyhomeInfoCmpetRtSvc/v1/getAPTLttotPblancCmpet", lambda: P(serviceKey=K, page=1, perPage=1), ok_dgk),
    ("공공데이터포털", "학교 위치(표준데이터)", "DATA_GO_KR_KEY", "https://api.data.go.kr/openapi/tn_pubr_public_elesch_mskul_lc_api", lambda: P(serviceKey=K, pageNo=1, numOfRows=1, type="json"), ok_dgk),
    ("공공데이터포털", "심평원 병원", "DATA_GO_KR_KEY", "https://apis.data.go.kr/B551182/hospInfoServicev2/getHospBasisList", lambda: P(serviceKey=K, numOfRows=1, pageNo=1, _type="json"), ok_dgk),
    ("공공데이터포털", "심평원 약국", "DATA_GO_KR_KEY", "https://apis.data.go.kr/B551182/pharmacyInfoService/getParmacyBasisList", lambda: P(serviceKey=K, numOfRows=1, pageNo=1, _type="json"), ok_dgk),
    ("공공데이터포털", "행안부 약국", "DATA_GO_KR_KEY", "https://apis.data.go.kr/1741000/pharmacies/info", lambda: P(serviceKey=K, pageNo=1, numOfRows=1, returnType="json"), ok_dgk),
    ("공공데이터포털", "법정동 코드", "DATA_GO_KR_KEY", "https://apis.data.go.kr/1741000/StanReginCd/getStanReginCdList", lambda: P(serviceKey=K, type="json", pageNo=1, numOfRows=1), lambda r: '"RESULT"' in r.text and "INFO-0" in r.text or ok_dgk(r)),
    ("공공데이터포털", "소상공인 상가", "SEMAS_KEY", "https://apis.data.go.kr/B553077/api/open/sdsc2/storeListInRectangle",
     lambda: P(serviceKey=E.get("SEMAS_KEY", K), minx=126.976, miny=37.565, maxx=126.978, maxy=37.567, numOfRows=1, pageNo=1, type="json"), ok_dgk),
    ("브이월드", "용도지역(2D 데이터)", "VWORLD_KEY", "https://api.vworld.kr/req/data",
     lambda: P(service="data", version="2.0", request="GetFeature", key=E.get("VWORLD_KEY"), data="LT_C_UQ111", geomFilter="BOX(126.976,37.565,126.978,37.567)",
               size=1, page=1, format="json", geometry="false", domain=E.get("VWORLD_DOMAIN") or "teomoony.com"),
     J(("response", "status"), "OK", "NOT_FOUND")),
    ("브이월드", "토지특성(NED)", "VWORLD_KEY", "https://api.vworld.kr/ned/data/getLandCharacteristics",
     lambda: P(key=E.get("VWORLD_KEY"), domain=E.get("VWORLD_DOMAIN") or "teomoony.com", pnu="1111010100100010000", format="json", numOfRows=1, pageNo=1),
     lambda r: r.status_code == 200 and '"landCharacteristicss"' in r.text or '"field"' in r.text or '"totalCount"' in r.text),
    ("브이월드", "공동주택가격(NED)", "VWORLD_NED_KEY", "https://api.vworld.kr/ned/data/getApartHousingPriceAttr",
     lambda: P(key=E.get("VWORLD_NED_KEY") or E.get("VWORLD_KEY"), domain=E.get("VWORLD_DOMAIN") or "teomoony.com", pnu="1111010100100010000", format="json", numOfRows=1, pageNo=1),
     lambda r: r.status_code == 200 and ('"totalCount"' in r.text or '"field"' in r.text)),
    ("도로명주소", "주소 검색", "JUSO_KEY", "https://business.juso.go.kr/addrlink/addrLinkApi.do",
     lambda: P(confmKey=E.get("JUSO_KEY"), currentPage=1, countPerPage=1, keyword="세종대로 110", resultType="json"),
     J(("results", "common", "errorCode"), "0")),
    ("SGIS", "인증(토큰 받기)", "SGIS_KEY", "https://sgisapi.mods.go.kr/OpenAPI3/auth/authentication.json",
     lambda: P(consumer_key=E.get("SGIS_KEY"), consumer_secret=E.get("SGIS_SECRET")), J(("errCd",), 0, "0")),
    ("서울 열린데이터", "정비사업", "SEOUL_OPENAPI_KEY", lambda: f"http://openapi.seoul.go.kr:8088/{E.get('SEOUL_OPENAPI_KEY')}/json/vnBsnsNmtn/1/1/", None,
     lambda r: "INFO-000" in r.text),
    ("나이스", "학원 · 교습소", "NEIS_KEY", "https://open.neis.go.kr/hub/acaInsTiInfo",
     lambda: P(KEY=E.get("NEIS_KEY"), Type="json", pIndex=1, pSize=1, ATPT_OFCDC_SC_CODE="B10"), lambda r: "INFO-000" in r.text),
    ("학교알리미", "학교 기본정보", "SCHOOLINFO_KEY", "https://www.schoolinfo.go.kr/openApi.do",
     lambda: P(apiKey=E.get("SCHOOLINFO_KEY"), apiType="0", sidoCode="11", sggCode="11110", schulKndCode="02"), J(("resultCode",), "success")),
    ("유치원알리미", "유치원 기본현황", "KINDER_KEY", "https://e-childschoolinfo.moe.go.kr/api/notice/basicInfo2.do",
     lambda: P(key=E.get("KINDER_KEY"), sidoCode="11", sggCode="11110"), lambda r: '"kinderInfo"' in r.text or '"SUCCESS"' in r.text.upper()),
    ("보육정보", "어린이집 기본정보", "CHILDCARE_KEY", "https://api.childcare.go.kr/mediate/rest/cpmsapi030/cpmsapi030/request",
     lambda: P(key=E.get("CHILDCARE_KEY"), arcode="11110"), lambda r: r.status_code == 200 and "<item>" in r.text),
    ("Anthropic", "AI 질문(모델 목록)", "ANTHROPIC_API_KEY", "https://api.anthropic.com/v1/models", None, lambda r: r.status_code == 200),
]


def check(c):
    무리, 이름, 키이름, url, params, ok = c
    if not E.get(키이름) and not (키이름 == "SEMAS_KEY" and K):
        return 무리, 이름, "키없음", f".env 에 {키이름} 없음"
    try:
        u = url() if callable(url) else url
        h = {"User-Agent": "teomoony-daily-report"}
        if 키이름 == "ANTHROPIC_API_KEY":
            h.update({"x-api-key": E[키이름], "anthropic-version": "2023-06-01"})
        r = requests.get(u, params=(params() if params else None), headers=h, timeout=25)
        t = r.text[:3000]
        if AUTH.search(t) or r.status_code in (401, 403):
            return 무리, 이름, "키문제", hide(f"HTTP {r.status_code} · " + re.sub(r"\s+", " ", t)[:160])
        if QUOTA.search(t) or r.status_code == 429:
            return 무리, 이름, "한도", hide(f"HTTP {r.status_code} · " + re.sub(r"\s+", " ", t)[:120])
        if ok(r):
            return 무리, 이름, "정상", ""
        return 무리, 이름, "응답이상", hide(f"HTTP {r.status_code} · " + re.sub(r"\s+", " ", t)[:160])
    except Exception as e:
        return 무리, 이름, "연결실패", hide(f"{type(e).__name__}: {e}")[:160]


def api_part():
    with ThreadPoolExecutor(8) as ex:
        res = list(ex.map(check, CHECKS))
    nok = [x for x in res if x[2] != "정상"]
    lines = []
    groups = {}
    for 무리, 이름, st, why in res:
        g = groups.setdefault(무리, [0, 0]); g[1] += 1; g[0] += st == "정상"
    lines.append(" · ".join(f"{g} {a}/{b}" for g, (a, b) in groups.items()))
    for 무리, 이름, st, why in nok:
        lines.append(f":red_circle: *{무리} {이름}* — {st}  `{why}`")
    exp = []
    for nm, d, how in EXPIRES:
        left = (d - TODAY).days
        if left <= WARN_DAYS:
            exp.append(f":warning: *{nm}* 만료 {d:%Y-%m-%d} (D-{left}) — {how}")
    nxt = min(EXPIRES, key=lambda x: x[1])
    if not exp:
        lines.append(f"다음 만료: {nxt[0]} {nxt[1]:%Y-%m-%d} (D-{(nxt[1] - TODAY).days})")
    return lines + exp, len(nok) + len(exp)


# ---------------------------------------------------------------- ② 배치 결과
def batch_part():
    from svc_publish import ms_conn
    ms = ms_conn(E); cur = ms.cursor()
    cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")
    t0 = (NOW - datetime.timedelta(hours=24)).strftime("%Y-%m-%d %H:%M:%S"); t1 = NOW.strftime("%Y-%m-%d %H:%M:%S")
    cur.execute("SELECT 상태, COUNT(*) FROM ops.collect_run WHERE 예정 >= %s AND 예정 < %s GROUP BY 상태", (t0, t1))
    cnt = dict(cur.fetchall())
    cur.execute("""SELECT TOP 12 이름, CONVERT(VARCHAR(16), 예정, 120), 상태, LEFT(ISNULL(이유, N''), 140), 종료코드, 로그
                     FROM ops.collect_run WHERE 예정 >= %s AND 예정 < %s AND 상태 IN (N'실패', N'못돎')
                    ORDER BY 예정 DESC""", (t0, t1))
    bad = cur.fetchall()
    # 오래 도는 것(6시간 넘게 '도는중')
    cur.execute("""SELECT 이름, CONVERT(VARCHAR(16), 시작, 120) FROM ops.collect_run
                    WHERE 상태 = N'도는중' AND 시작 < DATEADD(HOUR, -6, CAST(%s AS DATETIME2(0)))""", (t1,))
    long_ = cur.fetchall()
    # 예정이 지났는데 안 놓인 일정(2시간 넘게) — collect_cron 이 멈췄을 때
    cur.execute("""SELECT 이름, CONVERT(VARCHAR(16), 다음, 120) FROM ops.collect_schedule
                    WHERE 켜짐 = 1 AND 다음 IS NOT NULL AND 다음 < DATEADD(HOUR, -2, CAST(%s AS DATETIME2(0)))""", (t1,))
    late = cur.fetchall()
    ms.close()
    order = ["성공", "건너뜀", "실패", "못돎", "도는중", "놓음"]
    head = " · ".join(f"{k} {cnt[k]:,}" for k in order if cnt.get(k)) or "기록 없음"
    lines = [f"지난 24시간 {sum(cnt.values()):,}번 — {head}"]
    for 이름, 예정, 상태, 이유, rc, 로그 in bad:
        lines.append(f":red_circle: *{이름}* {예정} {상태}(코드 {rc}) — {이유.strip()[:120]}" + (f"  `{로그}`" if 로그 else ""))
    for 이름, 시작 in long_:
        lines.append(f":hourglass: *{이름}* {시작} 부터 아직 도는중(6시간 넘음)")
    for 이름, 다음 in late[:8]:
        lines.append(f":warning: *{이름}* 예정 {다음} 이 지났는데 안 걸림 — 수집 일정 프로그램 확인")
    return lines, len(bad) + len(long_) + len(late)


def box_part():
    lines, n = [], 0
    try:
        st = json.load(open(os.path.join(HERE, "_queue", "_status.json"), encoding="utf-8"))
        a = datetime.datetime.strptime(st["alive_at"][:19], "%Y-%m-%d %H:%M:%S").replace(tzinfo=KST)
        gap = (NOW - a).total_seconds()
        if gap > 120: lines.append(f":red_circle: 작업 감시기 멈춤 — 마지막 {st['alive_at'][:16]}"); n += 1
    except Exception as e:
        lines.append(f":red_circle: 작업 감시기 상태 못 읽음 ({type(e).__name__})"); n += 1
    try:
        r = requests.get("http://127.0.0.1:5173/api/health", timeout=15)
        if r.status_code != 200: lines.append(f":red_circle: 웹서버 응답 {r.status_code}"); n += 1
    except Exception as e:
        lines.append(f":red_circle: 웹서버 응답 없음 ({type(e).__name__})"); n += 1
    try:
        r = requests.get("https://teomoony.com/api/health", timeout=20)
        if r.status_code != 200: lines.append(f":red_circle: teomoony.com 응답 {r.status_code} (Cloudflare 터널?)"); n += 1
    except Exception as e:
        lines.append(f":red_circle: teomoony.com 응답 없음 ({type(e).__name__})"); n += 1
    if not lines: lines.append("작업 감시기 · 웹서버 · teomoony.com 모두 응답")
    return lines, n


# ---------------------------------------------------------------- ③ 이용 현황(어제 하루)
def usage_part():
    d = YDAY.isoformat()
    u = requests.get("http://127.0.0.1:5173/api/usage", params={"day": d}, timeout=60).json()
    동작 = u.get("동작") or []
    사람 = sum(int(x.get("전체") or 0) for x in 동작)
    일별 = {x["날"]: int(x["횟수"]) for x in (u.get("일별") or [])}
    지난 = [일별.get((YDAY - datetime.timedelta(days=i)).isoformat(), 0) for i in range(1, 8)]
    avg = sum(지난) / 7 if 지난 else 0
    ips = sum(int(x.get("IP수") or 0) for x in (u.get("나라") or []) if x.get("갈래") in ("사람", "모름"))
    갈래 = {x["갈래"]: int(x.get("전체") or 0) for x in (u.get("갈래별") or [])}
    로봇 = {k: v for k, v in 갈래.items() if k not in ("사람", "모름") and v}
    top = sorted(동작, key=lambda x: -int(x.get("전체") or 0))[:5]
    lines = [f"어제({YDAY:%m-%d}) 사람 {사람:,}회 · 방문 IP {ips:,}곳 (지난 7일 평균 {avg:,.0f}회)"]
    if top:
        lines.append("많이 쓴 기능: " + " · ".join(f"{x['동작']} {int(x['전체']):,}" for x in top if int(x.get("전체") or 0)))
    if 로봇:
        lines.append("로봇: " + " · ".join(f"{k} {v:,}" for k, v in sorted(로봇.items(), key=lambda kv: -kv[1])))
    # 오류(바깥 요청 중 5xx) — 서비스DB 접속 기록
    n = 0
    try:
        import svc_sql
        with svc_sql.connect() as c:
            d0 = f"{YDAY} 00:00:00"; d1 = f"{TODAY} 00:00:00"
            tot, e5, p95 = c.execute("""SELECT count(*), count(*) FILTER (WHERE "상태" >= 500),
                                               percentile_disc(0.95) WITHIN GROUP (ORDER BY "밀리") FILTER (WHERE "경로" LIKE '/api/%%')
                                          FROM app.req_log WHERE "때" >= %s AND "때" < %s AND NOT "내부" """, (d0, d1)).fetchone()
            line = f"바깥 요청 {tot:,}건 · 서버 오류(5xx) {e5:,}건 · API 응답 95%가 {p95 or 0:,}ms 안"
            if e5:
                n += 1
                top5 = c.execute("""SELECT "경로", count(*) FROM app.req_log WHERE "때" >= %s AND "때" < %s AND NOT "내부" AND "상태" >= 500
                                     GROUP BY 1 ORDER BY 2 DESC LIMIT 3""", (d0, d1)).fetchall()
                line = ":red_circle: " + line + " — " + " · ".join(f"`{re.sub(r'/[0-9]{3,}', '/{n}', p)}` {k}" for p, k in top5)
            lines.append(line)
    except Exception as e:
        lines.append(f"(오류 집계 못 셈: {type(e).__name__})")
    return lines, n


# ---------------------------------------------------------------- 모으기 · 보내기
def part(title, fn):
    try:
        lines, n = fn()
    except Exception as e:
        traceback.print_exc()
        lines, n = [f":red_circle: 못 셈 — {hide(type(e).__name__ + ': ' + str(e))[:200]}"], 1
    return title, lines, n


def main():
    dry = "--dry" in sys.argv
    parts = [part("오픈 API", api_part), part("배치(수집 일정)", batch_part), part("서버", box_part), part("이용 현황", usage_part)]
    문제 = sum(n for _, _, n in parts)
    머리 = (f":large_green_circle: *터무니 일일 리포트* {TODAY:%Y-%m-%d}({'월화수목금토일'[TODAY.weekday()]}) — 이상 없음" if not 문제 else
            f":red_circle: *터무니 일일 리포트* {TODAY:%Y-%m-%d}({'월화수목금토일'[TODAY.weekday()]}) — 확인할 것 {문제}건")
    body = [머리]
    for title, lines, n in parts:
        body.append(f"\n*{title}*" + (" :red_circle:" if n else ""))
        body += [f"• {l}" for l in lines]
    text = hide("\n".join(body))
    print(text)
    if dry:
        return 0
    import slack
    ok, why = slack.send(text)
    print("\n슬랙: " + ("보냄" if ok else "못 보냄 - " + why))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
