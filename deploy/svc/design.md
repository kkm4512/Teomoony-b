# 서비스DB 분리 설계 (2026-10-24 21:28 사장님 결정)

결정
1. 적재DB = 지금 SQL Server 그대로 (bronze · silver · gold · 변경 로그 · 원본 버전)
2. 서비스DB = **PostgreSQL 17 + PostGIS 3.5** (teomoony-svc 컨테이너, 127.0.0.1:15432) — 화면은 여기만 읽는다
3. 발행 = **1시간마다** (실거래처럼 몇 시간마다 바뀌는 자료 때문에)
4. Redis = **수도권(서울 11 · 인천 28 · 경기 41) 대단지** 기준으로 미리 채움 + 나머지는 많이 본 순(LRU)

자원(같은 PC · WSL 15.4GB · CPU 12): 적재 MSSQL 9.5GB/CPU 9 · 서비스 PG 3GB/CPU 3 · Redis 1GB(768MB 상한)

## 1. 흐름
```
공공 API·파일 → 적재DB(MSSQL) ──발행기(1시간마다)──▶ 서비스DB(PostgreSQL) ◀── 서비스 서버(Teomoony-f) ◀── Redis
```
- 화면은 적재DB 에 **붙지 않는다**. 적재가 아무리 무거워도 화면은 영향 없음 · 반쯤 넣은 데이터가 안 보임.
- 쓰기 영역(app.*: 사용자 · 관심 단지 · 문의 · 접속 기록 · AI 질문)은 서비스DB 에 두고 서비스 서버가 쓴다. 발행은 건드리지 않는다.

## 2. 서비스DB 표 (inventory.md 7장 기준)
| 표 | 키 | 내용 | 갱신 |
|---|---|---|---|
| svc.complex_card | complex_id | 검색·목록·마커: 이름(+띄어쓰기 뺀 · 실거래이름 · 부속지번) · 주소 · 좌표(geometry) · 세대 · 동 · 사용승인 · 최근 매매 | 매시 |
| svc.complex_detail | complex_id | **지금 /api/complexes/:id 응답과 같은 모양의 JSON**(제원 · 동+위반 · K-apt · 인허가 · 필지 · 용도지역 · 정비 · 관리비 …) | 매시(바뀐 단지만) |
| svc.complex_near | complex_id | 주변(학교 · 학구도 · 유치원 · 어린이집 · 학원 · 역 · 버스 · 상권 · 병원 · 약국) JSON | 주변 자료 바뀔 때 |
| svc.complex_ho / svc.ho_price | complex_id·동·호 / 호 | 동·호 배치 · 면적 · 공시가격(연도별) | 매시(바뀐 단지만) |
| svc.trade · svc.trade_stat · svc.trade_offsite | complex_id … | 단지에 붙은 실거래 · 평형 요약 · 전세가율 · 단지 밖 신고 | 매시 |
| svc.history_event | complex_id·날짜 | 이 땅의 역사(옛 대장 · 옛 거래 · 정비 · 인허가 · 청약 · 분양권 · 용도지역 바뀜 · 토지이동) | 매시 |
| svc.map_parcel · svc.map_building · svc.map_layer | pnu / 건물번호 / 레이어 | 지도 폴리곤(GiST 색인) | 바뀐 것만 |
| svc.poi | 종류·id | 지도 점(+팝업 JSON) | 바뀐 것만 |
| svc.newbuild · svc.applyhome · svc.closed_site | 각 키 | 대장 없는 신축 · 청약 · 옛 대장 자리 | 매시 |
| svc.region · svc.coverage · svc.stats | — | 행정구역 · 받은 범위("없다" vs "안 받았다") · 홈 수치 | 매시 |
| svc.publish | publish_id | 발행 기록(시작 · 끝 · 표별 줄 수 · 검사 결과 · 기준선) | 발행마다 |

검색: pg_trgm GIN 색인(부분 일치도 색인을 탐 — 지금 LIKE '%…%' 느림의 근본 해결). 지도: PostGIS GiST + `&&`.
예상 크기 10~15GB(지금 화면이 읽는 바닥 표 57GB 중 '지금 줄 · 쓰는 칸' 만).

## 3. 발행기 (적재DB → 서비스DB, 매시)
- **기준선(watermark)**: 자료마다 '마지막으로 끝까지 성공한 적재(ops.ingest_run 끝남)' 시각. 그 뒤에 진행 중인 적재분은 이번 발행에서 빠진다 → 반쪽 데이터가 안 나간다.
- **바뀐 것만**: silver 의 valid_from(SCD) · 변경 로그 · gold 다시 만든 시각으로 '이번에 바뀐 단지' 목록을 만들고 그 단지만 다시 계산해 넣는다(upsert).
  복잡한 계산(공간 · APPLY · 임시표)은 **적재DB 안(T-SQL)** 에서 하고, 결과(줄 · JSON)만 PostgreSQL 로 COPY.
- **한 발행 = 한 트랜잭션**(PG): 읽는 쪽은 이전 판 아니면 새 판만 본다. 지도 레이어처럼 통째로 바꾸는 표는 새 표를 옆에 만들고 이름을 바꿔 끼운다.
- **검사**: 표별 줄 수 급감(전 판 대비 -2% 넘게 줄면 멈춤) · 매칭률(ops.match_rate) 급락 · JSON 깨짐 → 실패 시 **이전 판 유지 + 알림**.
- 첫 판(전체)은 시군구 단위로 나눠 집합 계산 — 단지 57만 개를 하나씩 부르지 않는다.

## 4. Redis
- 키에 발행 번호: `d:{publish_id}:{complex_id}` → 발행되면 다음 요청부터 저절로 새 판(지우는 일 없음).
- 값은 gzip 한 JSON 그대로 — 서버가 풀지 않고 `Content-Encoding: gzip` 로 내보낸다(상세 한 개 원본 ~450KB → ~45KB).
- **미리 채움**: 매 발행 직후 수도권(11·28·41) **500세대 이상** 단지 상세 · 검색 상위어. 지금 기준 1,204단지 ≈ 55MB. 경기 전체가 들어오면 ~8천 단지 ≈ 350MB(상한 768MB 안). 문턱(500)은 설정값.
- 나머지는 열린 것만 담고 넘치면 오래 안 본 것부터 버림(allkeys-lru).

## 5. 순서
1. ✅ 쿼리 · 표 목록(inventory.md) · 이 설계
2. 컨테이너: MSSQL 메모리 13→9.5GB · CPU 9 / postgis 3GB · CPU 3 / redis 1GB (22:40, 토지특성 끝난 뒤 재시작)
3. 서비스DB 스키마(svc.* · app.*) · 발행기 첫 판(전체) · 검사
4. 서비스 서버: server.js → 화면별 모듈 · PostgreSQL 만 읽기 · Redis
5. 대조: 옛 서버(적재DB) vs 새 서버(서비스DB) — 단지 수백 개 상세 JSON 칸별 비교 → 같으면 전환
6. 매시 발행 예약 · 적재DB 의 화면 접속 끊기
