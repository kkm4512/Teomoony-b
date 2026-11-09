# API 키 유효기간 정리 (2026-11-09 사장님 "어떤 key 의 유효기간이 얼마인지")

> 키 **값은 이 문서에 적지 않는다**(깃에 올라간다). 값은 `.env` 한 곳.
> **만료일 칸은 각 포털 마이페이지에서만 보인다** — 확인하면 이 표의 '만료일' 칸을 채운다.
> 2026-11-09 사장님 화면 확인: 브이월드(인증키 3건 중 우리가 쓰는 2건) · 도로명주소(운영 승인) · SGIS · 서울 열린데이터 · 학교알리미 · 유치원알리미 · 나이스(다섯 다 기간 표시 없음) · 보육정보(2027-10-20). 화면의 키와 `.env` 값은 앞부분만 대조해 같은 것을 확인했다(값은 여기 안 적음).
> 2026-11-09 확인: 최근 14일 `logs/*.log` 에 인증 오류(미등록 · 만료 · 잘못된 키) **0건** — 지금 쓰는 키는 다 살아 있다.

---

## 1. 한눈에

| `.env` 이름 | 발급처 · 확인하는 곳 | 기한 규칙(조사한 것) | 우리 키 | 만료일 |
|---|---|---|---|---|
| `DATA_GO_KR_KEY` (=`SEMAS_KEY` 같은 값) | 공공데이터포털 data.go.kr → 마이페이지 → 개발계정 | **활용신청(발급)일로부터 2년**(2026-11-09 사장님 확인) · 서비스마다 따로 | 10-19 07:35 백업에 이미 같은 값 | 서비스별 — 2장 |
| `VWORLD_KEY` | 브이월드 vworld.kr → 오픈API → 인증키 관리 | 개발키 **6개월 · 최대 3회 연장** · 운영키 2년(관리자 심사 후 연장) · **연장은 만료일 전에만** | **개발키 · 발급 2026-10-13 · 운영 심사 중**(화면 '개발(운영심사)') | **2027-04-13** |
| `VWORLD_NED_KEY` (+`VWORLD_DOMAIN`) | 브이월드(같은 곳) | 위와 같음 · 발급 때 등록한 도메인에서만 동작 | **개발키 · 발급 2026-10-20** | **2027-04-20** |
| `JUSO_KEY` | 주소기반산업지원서비스 business.juso.go.kr | 개발승인키는 기간이 있고 지나면 못 씀(다시 발급) · **운영키는 관리 화면에 기간 표시 없음** | **운영 · 승인**(도로명주소 검색 API · 시스템 '터무니' · https://teomoony.com) — 10-23 교체 | 표시 없음(기한 없는 것으로 본다) |
| `KAKAO_REST_API_KEY` · `KAKAO_CLIENT_SECRET` | 카카오 developers | 앱 키 자체의 기한 규칙은 못 찾음 | 10-19 이전 | — |
| `KAKAO_REFRESH_TOKEN` | 카카오(알림 `etl/notify.py`) | 2개월(갱신 안 하면 끊김) | **안 씀**(2026-11-09 사장님 "카카오 알림은 이제 안 쓴다") — 끊겨도 무시 | — |
| `SGIS_KEY` · `SGIS_SECRET` | 통계청 SGIS 개발지원센터 → 인증키발급센터 → 나의 인증키 | 이 둘로 AccessToken(4시간)을 받아 쓴다(코드가 매번 받음) · **화면에 기간 표시 없음** | 서비스 '터무니' · **신청 2026-10-21 · 발급** | 표시 없음 |
| `NEIS_KEY` | 나이스 교육정보 개방포털 open.neis.go.kr → 마이페이지 → 인증키 발급 | **화면에 기간 표시 없음** | 학원 · 교습소(`load_academy.py` · `academy_all.py`) · 활용용도 프로그램 개발 · **2026-10-20 발급 · 정상** | 표시 없음 |
| `KINDER_KEY` | 유치원알리미 e-childschoolinfo.moe.go.kr → 마이페이지 | **화면에 기간 표시 없음** | 개발계정 '단지정보 보여주기' · 유치원 기본현황 · **신청 2026-10-19 · 자동승인 · 승인** | 표시 없음 |
| `CHILDCARE_KEY` | 보육정보공개 API(한국사회보장정보원) → OPEN API 이용 신청현황 | 운영계정 **승인일로부터 1년** · 신청(갱신) 칸이 있다 — 만료 전에 갱신 신청 | 어린이집(`load_childcare.py`) · **운영 · 승인** · 어린이집별 기본정보 조회 · 신청 · 승인 2026-10-20 | **2027-10-20** |
| `SCHOOLINFO_KEY` | 학교알리미 schoolinfo.go.kr → OpenAPI → 나의 정보 조회 | **화면에 기간 표시 없음** · 2026-01-01 뒤 발급 키는 시·군·구 파라미터 필수(우리 키 해당) | 카카오 계정 · **정상** · 10-23 발급 | 표시 없음 |
| `SEOUL_OPENAPI_KEY` | 서울 열린데이터광장 data.seoul.go.kr → 마이페이지 → 인증키 | **화면에 기간 표시 없음** · 1회 1,000건 · 호출 횟수 제한 없음(지하철 실시간만 하루 1,000회) | 일반인증키 · **2026-10-22 · 정상** (계정에 키 6개 — 나머지 5개는 우리 코드가 안 씀) | 표시 없음 |
| `ANTHROPIC_API_KEY` | console.anthropic.com | 기한 없음(폐기 전까지) — 일반 정책 | 10-19 이전 | — |

'우리 키' 칸의 날짜는 **그 값이 처음 보이는 `.env` 백업 시각**(= 그때 이미 있었다는 뜻, 발급일은 그 전일 수 있다)이거나 CONTEXT 에 적힌 발급 날이다.

---

## 2. 공공데이터포털 — 한 키, 서비스별 기한

같은 `DATA_GO_KR_KEY` 라도 **활용신청 한 건마다 활용기간이 따로** 있다 — **발급일로부터 2년**(사장님 확인). 하나가 끝나면 그 서비스만 `DEADLINE_HAS_EXPIRED_ERROR`(코드 31) 를 낸다(미신청은 `SERVICE_KEY_IS_NOT_REGISTERED_ERROR` 30).
아래 '만료(추정)' = 일지에 적힌 신청일 + 2년. '10-14 이전' 은 이 프로젝트 일지(2026-10-14 시작) 전에 이미 쓰던 것 — **발급일을 모르니 늦어도 그 날짜 전에 끝난다**는 뜻이다. 정확한 날은 마이페이지 → 개발계정의 '활용기간'.

| 서비스(엔드포인트) | 쓰는 코드 | 신청(일지) | 만료(추정) |
|---|---|---|---|
| 아파트 매매 · 전월세 · 연립 · 단독 · 오피스텔 · 토지 · 상업업무 · 공장 실거래 (`RTMSDataSvc*`) | load_rtms.py | 10-14 이전 | 2028-10-14 전 (종류마다 따로 신청이면 줄마다) |
| 분양권전매 실거래 (`RTMSDataSvcSilvTrade`) | load_rtms.py | 10-21 무렵 | 2028-10-21 무렵 |
| 건축HUB 건축물대장 (`BldRgstHubService` — 표제부 · 총괄 · 전유 · 층별 · 공시가격 …) | load_building.py 외 | 10-14 이전 | 2028-10-14 전 |
| 건축HUB 건축인허가 (`ArchPmsHubService`) | load_* (pms) | 10-17 무렵 | 2028-10-17 무렵 |
| 건축HUB 주택인허가 (`ShtRgstHubService`) | load_closed_* · probe | 10-22 | 2028-10-22 |
| 공동주택 단지 목록 (`AptListService4`) | load_kapt.py | 10-14 이전 | 2028-10-14 전 |
| 공동주택 기본정보 (`AptBasisInfoServiceV5`) | load_kapt.py | 10-15 | 2028-10-15 |
| 공동주택 관리비 (`AptCmnuse` · `AptIndvdlz` · `AptRepairsCost` V3) | load_kapt_cost.py · kapt_cost_monthly.py | 10-15 무렵 | 2028-10-15 무렵 |
| 청약홈 분양정보 (odcloud `ApplyhomeInfoDetailSvc`) | load_applyhome.py | 10-18 | 2028-10-18 |
| 청약홈 경쟁률 (odcloud `ApplyhomeInfoCmpetRtSvc`, 15098905) | load_applyhome_cmpet.py | 10-22 | 2028-10-22 |
| 학교 (15021148) | load_school.py | 10-19 | 2028-10-19 |
| 버스 정류소 TAGO (15096280 · `BusSttnInfoInqireService`) | load_bus*.py | 10-19 | 2028-10-19 (서울 없음 — 안 써도 됨) |
| 심평원 병원정보 v2 · 약국정보 (`B551182`) | load_hira*.py | 10-21 | 2028-10-21 |
| 행안부 건강_약국 (`1741000/pharmacies`) | load_mois_pharmacy.py | 10-21 | 2028-10-21 |
| 법정동 코드 (15063424 · 15077871 `StanReginCd`) | load_lawd_api.py · _p_stanregin.py | 10-22 | 2028-10-22 |
| 소상공인 상가(상권)정보 (`B553077 sdsc2`, 키 `SEMAS_KEY`) | load_semas.py | 10-19 이전 | 2028-10-19 전 |

---

## 3. ⚠ 지금 챙길 것

1. (카카오 알림은 2026-11-09 부터 안 쓴다 — 토큰이 끊겨도 챙기지 않는다.)
2. **브이월드 — 가장 먼저 끝난다.** `VWORLD_KEY` **2027-04-13** · `VWORLD_NED_KEY` **2027-04-20**(둘 다 개발키). 연장은 **만료일 전에만** 된다(개발키 최대 3회) → **2027년 3월에 둘 다 연장 신청**. `VWORLD_KEY` 는 운영 심사 중이라 승인되면 2년짜리가 된다. 만료되면 HTTP 200 에 `EXPIRE_KEY`(인증키가 만료되었습니다)가 온다 — 빈 결과처럼 보일 수 있다.
3. **보육정보(어린이집)** — 운영계정 **2027-10-20** 만료. 2027년 9월에 갱신 신청.
4. **공공데이터포털** — 발급일로부터 2년이라 가장 이른 것도 **2028년 10월 전후**. 서비스가 15개 넘게 흩어져 하나만 끝나도 그 적재만 조용히 실패하니, 2028년 여름에 마이페이지에서 일괄 연장한다.

---

## 4. 만료되면 오는 응답(로그에서 찾을 글)

| 출처 | 만료 · 무효 응답 |
|---|---|
| 공공데이터포털 | `DEADLINE_HAS_EXPIRED_ERROR`(31) · `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`(30) · `SERVICE_ACCESS_DENIED_ERROR`(20) |
| 브이월드 | `EXPIRE_KEY` · `INCORRECT_KEY` · `E0001 승인되지 않은 인증키` (HTTP 200 으로 옴) |
| 도로명주소 | `승인되지 않은 KEY` · `개발승인키 기간이 만료되어…` |
| 카카오 | `invalid_grant` · `KOE322`(expired_or_invalid_refresh_token) |
| 나이스 | `ERROR-290`(인증키 무효) |

확인 한 줄: `grep -l -E "DEADLINE_HAS_EXPIRED|SERVICE_KEY_IS_NOT_REGISTERED|EXPIRE_KEY|INCORRECT_KEY|승인되지 않은|ERROR-290|invalid_grant|KOE322" logs/job_*.log`

---

## 5. 근거
- 공공데이터포털 인증 에러코드 표(DEADLINE_HAS_EXPIRED_ERROR 31): data.go.kr/data/15076332/fileData.do
- 브이월드 개발키 6개월(2024-02-29부터) · 연장 가능 · 운영키 별도: qquack.org/excel/openapi-parcelinfo (사용자 글 — 공식 문서는 인증키 관리 화면으로 확인)
- 브이월드 만료 응답 EXPIRE_KEY: github.com/kwonohjik/Property-related-Taxes/pull/2061 (2026-09 실측)
- 도로명주소 개발승인키 만료 오류: business.juso.go.kr/jst/jstRoadNmAddrApiPop
- 카카오 리프레시 토큰 2개월 · 1개월 이내 갱신 시 재발급: devtalk.kakao.com/t/api-access-token/139348
- SGIS AccessToken 4시간: sgis.mods.go.kr/developer/html/newOpenApi/api/dataApi/authAndUseApi.html
- 나이스 약관(이용기간 지정 가능): open.neis.go.kr/portal/userAgreementPage.do
- 서울 열린데이터광장 인증키 안내: data.seoul.go.kr/together/mypage/actkeyMain.do
