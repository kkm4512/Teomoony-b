# Teomoony-b — 터무니 적재 · DB

**단지코드 하나로 건축물대장 · 토지 · 건물 · 실거래가를 전부 조회한다.**

터무니(Teomoony)는 흩어져 있는 공공데이터를 단지 단위로 이어 보여 주는 조회 서비스입니다.
이 저장소는 그중 **데이터를 받아 DB 에 넣고 잇는 쪽**(Python 적재기 + SQL Server 스키마)입니다.
화면과 API 서버는 [Teomoony-f](https://github.com/kkm4512/Teomoony-f) 에 있습니다.

```
공공 API · 공개 파일 ──> etl/ (Python) ──> SQL Server
                                            meta   코드표 · 적재 기록 · 적재 범위
                                            bronze API 응답 원문
                                            silver 출처별 정제 테이블 (원본 필드명 보존)
                                            gold   단지 · 연결 · 화면용 뷰
```

## 무엇을 하나

**건축물대장을 기준(master)으로 단지를 묶고, 나머지 축을 코드로 붙입니다.**

| 축 | 잇는 키 |
|---|---|
| 건축물대장 (단지 묶기) | `mgmBldrgstPk` / `mgmUpBldrgstPk` |
| 토지 · 필지 · 공시지가 | PNU 19자리 (법정동 10 + 산 1 + 본번 4 + 부번 4) |
| 건물 외곽선 | 건물관리번호 25자리 — **앞 19자리가 PNU** |
| 실거래가 | PNU 를 조립 (법정동 이름 → 코드, 지번 문자열 파싱) |
| K-apt · 관리비 | 법정동 + 지번. 단지와의 연결은 **양쪽 1:1 일 때만** 추정 연결 |

- **단지코드가 재현됩니다.** 단지를 만든 근거를 `gold.complex_identity` 에 남겨, 다시 적재해도 같은 단지는 같은 코드를 받습니다.
- **안 붙은 이유를 셉니다.** 실거래가 단지에 붙지 않으면 `gold.v_rtms_gap` 이 이유를 분류합니다
  (`MASKED` 지번 가림 · `NO_BLD` 대장 없음 · `NO_TITLE` 전유부만 · `OUT_OF_SCOPE` 범위 밖 …).
  설명되지 않는 미매칭이 0 건이어야 정상입니다.
- 설계 판단과 검토 후 접은 것들의 이유는 `정책.md`, 시간순 작업 기록은 `CONTEXT.md` 에 있습니다.

## 데이터 출처

| 출처 | 받는 것 | 적재기 |
|---|---|---|
| 공공데이터포털 — 국토교통부 건축HUB | 건축물대장 (기본개요 · 표제부 · 총괄표제부 · 층별 · 전유부 · 주택가격), 건축인허가, 폐쇄말소대장 | `teomoony_ingest.py` `load_closed_bld.py` |
| 공공데이터포털 — 국토교통부 실거래가 | 아파트 · 연립다세대 · 오피스텔 · 단독다가구 · 토지 · 상업업무용 매매/전월세 10종 | `load_rtms.py` |
| 공공데이터포털 — K-apt | 공동주택 단지정보, 관리비 | `load_kapt.py` `load_kapt_cost.py` |
| 브이월드 VWorld (국토교통부) | 연속지적도 · 공시지가, 건물 외곽선, 법정동 경계, 용도지역, 토지특성 · 토지이용계획 · 토지이동이력, 공동주택가격 | `load_cadastral.py` `load_building.py` `load_lawd_geom.py` … |
| 청약홈 (한국부동산원) | 분양 공고 · 주택형 · 경쟁률 | `load_applyhome*.py` |
| 교육 | 학교 · 학구도(교육부), 유치원알리미, 나이스 학원 · 교습소, 어린이집(보육정보공개) | `load_school*.py` `load_kinder.py` `load_academy.py` `load_childcare.py` |
| 생활 | 병원 · 약국(건강보험심사평가원 · 행정안전부), 버스정류장 · 노선, 소상공인 상가정보 | `load_hira*.py` `load_bus*.py` `load_semas*.py` |
| 서울 열린데이터광장 | 정비사업 구역 · 계획 | `load_redev.py` `load_seoul_redev_plan.py` |
| 법정동코드 · 행정동 경계 | 행정표준코드 공식 파일, 통계청 SGIS | `load_lawd_file.py` `load_adm_boundary.py` |

각 데이터의 이용 조건은 해당 제공기관의 약관을 따릅니다. 수집 원본(`etl/raw/` 등)과 적재 파일은 저장소에 넣지 않습니다.

## 원칙

- **원본을 훼손하지 않습니다.** API 응답은 `bronze` 에 원문 그대로 두고, `silver` 도 원본 필드명을 지킵니다.
  값을 고치거나 채워 넣지 않으며, 코드로 이어지지 않는 것은 문자열 추측으로 잇지 않습니다.
  추정 연결은 이름부터 추정으로 남깁니다(`v_complex_kapt`). 틀리게 붙이느니 비워 두고 비운 이유를 적습니다.
- **비상업입니다.** 공공데이터를 이어 보여 주는 개인 프로젝트이며 상업적 목적으로 운영하지 않습니다.
- **키는 저장소에 없습니다.** API 키 · 비밀번호는 `.env` 와 `etl/config.json` 에만 두고, 둘 다 git 에 올리지 않습니다.
  문서와 스크립트도 비밀번호를 직접 적지 않고 `.env` 에서 읽습니다.

## 실행

준비물: **Windows + Docker Desktop**, **Python 3.10 이상**. 각 제공기관에서 발급받은 API 키.

### 1. 설정

```powershell
git clone https://github.com/kkm4512/Teomoony-b.git Teomoony
cd Teomoony
copy .env.example .env                      # 값을 채운다 — 아래 표
copy etl\config.example.json etl\config.json  # 건축물대장 적재기용 (키 · DB 비밀번호)
```

설정은 `.env.example` 에 이름만 적혀 있습니다. 키가 없는 축은 그 적재기만 못 돌 뿐 나머지는 동작합니다.

| 변수 | 필수 | 용도 |
|---|---|---|
| `DB_HOST` `DB_PORT` `DB_USER` `DB_PASSWORD` `DB_NAME` | ✅ | SQL Server. `DB_PASSWORD` 가 컨테이너 `sa` 비밀번호가 됩니다 |
| `DATA_GO_KR_KEY` | ✅ | 공공데이터포털 — 건축물대장 · 실거래가 · 인허가 · K-apt · 청약홈 · 심평원. API 마다 활용신청 필요 |
| `VWORLD_KEY` · `VWORLD_DOMAIN` | ✅ | 연속지적도 · 건물 외곽선 · 법정동 경계 · 용도지역. 발급 시 등록한 도메인 |
| `VWORLD_NED_KEY` | | VWorld 국가중점데이터 — 토지특성 · 토지이용계획 · 공동주택가격 |
| `KINDER_KEY` · `NEIS_KEY` · `CHILDCARE_KEY` | | 유치원알리미 · 나이스 · 보육정보공개 |
| `SEMAS_KEY` · `SEOUL_OPENAPI_KEY` | | 상가정보 · 서울 열린데이터광장 |
| `SGIS_KEY` · `SGIS_SECRET` | | 통계청 SGIS (행정동 경계) |
| `JUSO_KEY` | | 도로명주소 — 현재 미사용 |
| `KAKAO_*` | | 긴 적재가 끝났을 때 알림 (선택) |

Teomoony-f 를 옆 폴더에 두면 화면도 이 `.env` 를 함께 읽습니다. 화면 전용 변수는 Teomoony-f 의 `.env.example` 에 있습니다.

### 2. DB 띄우기 · 스키마

```powershell
docker compose --env-file .env -f deploy\docker-compose.yml up -d   # SQL Server 2022, localhost:11433
deploy\run_migrations.cmd                                           # 기본 스키마 (00~89 번)
py -m pip install -r etl\requirements.txt
py etl\apply_sql.py 102_coverage.sql                                # 그 뒤 번호의 스크립트는 필요한 것만 하나씩
```

`deploy/sql` 은 **번호 순서대로** 적용합니다. `15_build_fast.sql` 은 적용하지 않습니다(파일 머리에 이유).
진단용 스크립트(읽기 전용)도 같은 폴더에 섞여 있습니다.

### 3. 적재

```powershell
cd etl
py load_lawd_file.py                 # 법정동코드 (먼저)
py run_plan.py add --sgg 11110       # 종로구를 목표로
py run_plan.py plan                  # 남은 일 보기
py run_plan.py go                    # 실행. 끊겨도 다시 돌리면 이어서 간다
py load_rtms.py --sgg 11110 --from 202401 --to 202512   # 실거래가
py load_rtms.py --rematch-only       # 대장을 새로 넣었으면 실거래를 다시 잇는다
```

시군구 하나(종로구)가 대략 40분입니다. 적재 결과는 `meta.ingest_run` 과 `logs/` 에 남습니다.
나머지 축은 각 `load_*.py` 머리 주석에 사용법이 있습니다.

## 알아둘 것

- **단독 · 토지 · 상업용 실거래는 지번이 가려져(`1**`) 단지에 붙일 수 없습니다.** 설계로 풀 수 없는 한계이며, 법정동 단위 집계까지만 씁니다.
- **등기는 없습니다.** 등기부 공공 API 가 없고 키 체계(부동산고유번호 14자리)도 PNU 와 다릅니다.
- **좌표계는 EPSG:4326** 으로 통일합니다. VWorld 는 `crs=EPSG:4326` 으로 받아 변환이 없습니다.
- **건축물대장 API 는 페이지당 100건 상한**입니다. `numOfRows` 를 키워도 잘립니다.
- `.cmd` 파일은 ASCII 로만 씁니다 — `cmd.exe` 가 CP949 로 읽어 한글 주석이 줄 파싱을 깨뜨립니다.
- 전국 규모로 넓히려면 API 건별 호출이 아니라 EAIS 월배치 파일로 가야 합니다. 스키마와 단지 묶기 규칙은 그대로 쓸 수 있습니다.
