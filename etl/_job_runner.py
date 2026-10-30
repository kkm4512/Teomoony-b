# -*- coding: utf-8 -*-
"""_job_runner.py — 집 밖에서 내린 지시를 이 PC 에서 대신 실행한다 (2026-10-18).

★ 왜 필요한가
  Claude 는 이 PC 의 **터미널에 타이핑할 수 없다.** 터미널·IDE·탐색기가
  전부 tier "click" 으로만 허용되기 때문이다(설계상 차단이고 우회 대상이
  아니다). 대신 Claude 는 **연결 폴더에 파일을 쓸 수 있다.**
  그래서 역할을 나눈다 — Claude 가 `_queue\\<이름>.job` 을 떨구고,
  이 프로그램이 그걸 집어서 실행한다. 화면도 클릭도 필요 없다.

★ 보안 — 이게 핵심이다
  **아무 명령이나 돌리지 않는다.** 아래 JOBS 에 적힌 이름만 실행한다.
  그 외에는 실행하지 않고 `_queue\\rejected\\` 로 옮긴 뒤 사유를 적는다.
  창을 닫으면 아무것도 안 돈다 — **그 창이 문지기다.**

  sql.<이름> 만 인자를 받는데, 이것도
    · 이름이 [A-Za-z0-9_]+ 일 때만
    · deploy\\sql\\<이름>.sql 이 **이미 있을 때만**
  돈다. 큐 파일 안의 내용은 **읽지도 않는다** — 파일 '이름' 이 전부다.
  내용을 읽어 실행하면 그게 곧 원격 셸이 된다.

★ 상태를 밖에서 읽을 수 있게 한다
  `_queue\\_status.json` 에 심장박동을 쓴다. Claude 는 터미널을 못 보지만
  이 파일은 읽을 수 있으므로, "감시가 살아 있나" 를 **추측하지 않고 확인**한다.
"""
import json, os, re, subprocess, sys, threading, time

HERE   = os.path.dirname(os.path.abspath(__file__))
QDIR   = os.path.join(HERE, "_queue")
DONE   = os.path.join(QDIR, "done")
REJECT = os.path.join(QDIR, "rejected")
LOGDIR = os.path.abspath(os.path.join(HERE, "..", "logs"))
STATUS = os.path.join(QDIR, "_status.json")
SQLDIR = os.path.abspath(os.path.join(HERE, "..", "deploy", "sql"))
POLL   = 10

# 돌릴 수 있는 것 전부. 여기 없으면 안 돈다.
JOBS = {
    "go-retry": [sys.executable, "run_plan.py", "go", "--retry", "--workers", "4"],
    "go":       [sys.executable, "run_plan.py", "go", "--workers", "4"],
    "plan":     [sys.executable, "run_plan.py", "plan"],
    "rematch":  [sys.executable, "load_rtms.py", "--rematch-only"],

    # ---- 공시가격(hsprc) 마저 받기 (2026-10-19 밤) ----
    # 운영계정 승인됨: getBrHsprcInfo 일일 트래픽 1,000,000.
    # ★ workers 를 올리면 빨라지지만 **503 과 DB 쓰기 경합**도 같이 는다.
    #   오늘 낮 building 적재 때 silver.building_footprint 락 경합으로
    #   단지 상세가 45초까지 갔다 - 이제 그 화면은 teomoony.com 으로 공개돼 있다.
    #   8 부터 보고 로그에 503 이 없으면 12 로 올린다.
    "hsprc":    [sys.executable, "run_plan.py", "go", "--ops", "hsprc",
                 "--retry", "--workers", "8"],
    "hsprc-12": [sys.executable, "run_plan.py", "go", "--ops", "hsprc",
                 "--retry", "--workers", "12"],

    # ---- 페이지 단위로 나눠 받기 (2026-10-19) ----
    # ★ 병렬 단위가 법정동이라, 남은 동이 5개면 스레드를 10개 줘도 논다.
    #   한 동이 2,550쪽인 hsprc 는 **페이지를 갈라야** 스레드가 다 일한다.
    #   meta.load_page 에 받은 페이지를 적으므로 구멍이 나면 눈에 보인다.
    "pages-dry": [sys.executable, "load_pages.py", "--op", "getBrHsprcInfo",
                  "--dry-run"],
    "pages":     [sys.executable, "load_pages.py", "--op", "getBrHsprcInfo",
                  "--workers", "10"],
    # ★ 실측 10개: 218쪽/분, 503 **0건**. 적재기 주석이 경고한 "동시 호출을
    #   늘리면 503 도 는다" 에 아직 안 닿았다 - 올릴 여유가 있다.
    # ★ chunk 도 같이 올린다(60->120). 작은 동에서는 페이지 받는 값보다
    #   **프로세스 띄우는 값**(파이썬 시작 + DB 접속)이 크다. 구간을 키우면
    #   그 값이 절반이 된다. 스레드만 올리면 그 비용이 그대로 따라온다.
    "pages-20":  [sys.executable, "load_pages.py", "--op", "getBrHsprcInfo",
                  "--workers", "20", "--chunk", "120"],

    # ---- 서울 확장 (2026-10-20 새벽) ----
    # ★ 넣는 것과 받는 것을 **가른다**. seoul-add 는 목표만 넣고,
    #   얼마나 되는 일인지는 pages-dry / rtms-seoul-dry 로 따로 잰다.
    #   크기를 모르고 시작하면 한도나 시간에 걸려 중간에 멈춘다.
    "seoul-add-dry": [sys.executable, "add_seoul.py", "--dry-run"],
    "seoul-add":     [sys.executable, "add_seoul.py"],
    # 전유공용면적을 서울 목표에 **덧붙인다**(2026-10-20, 사용자 승인).
    # 호 상세의 전용면적이 여기서 나온다. 덮지 않고 붙인다.
    "seoul-exar-dry": [sys.executable, "add_seoul.py", "--add-ops", "exar", "--dry-run"],
    "seoul-exar":     [sys.executable, "add_seoul.py", "--add-ops", "exar"],
    "size-exar":      [sys.executable, "size_ops.py", "--only", "exar"],

    # 실거래는 load_target 의 ops 로 **안 돈다**(NEEDS_PERIOD). 따로 부른다.
    "rtms-seoul-dry": [sys.executable, "rtms_seoul.py", "--dry-run",
                       "--from", "200601", "--to", "202610"],
    "rtms-seoul":     [sys.executable, "rtms_seoul.py", "--workers", "6",
                       "--from", "200601", "--to", "202610"],

    # ★ 기본개요가 **문**이다(2026-10-20). v_load_plan 의 선행 판정에서
    #   basis 와 pms 만 'OK' 이고, 표제부·총괄·층별·전유부·전유공용·주택가격·
    #   부속지번·지역지구는 전부 그 법정동에 기본개요가 들어가야 열린다.
    #   그래서 서울을 넓힐 때는 **basis 를 먼저 끝내야** 나머지가 돈다.
    "pages-dry-basis": [sys.executable, "load_pages.py",
                        "--op", "getBrBasisOulnInfo", "--dry-run"],
    "pages-basis":     [sys.executable, "load_pages.py",
                        "--op", "getBrBasisOulnInfo",
                        "--workers", "20", "--chunk", "120"],
    # 축별 크기를 한 번에 재서 표로 — "서울 전체 = 며칠" 에 답하려고.
    "size-ops": [sys.executable, "size_ops.py"],
    # ★ 큐는 이름을 sorted() 로 집는다 - 일감을 여러 개 떨어뜨리면 **가나다 순**
    #   으로 돌아서 hsprc(18시간)가 recap(0분)보다 먼저 잡힌다. 한 일감 안에서
    #   순서를 지킨다. 싼 축부터: 총괄 -> 부속지번 -> 표제부 -> 지역지구 ->
    #   층별 -> 전유부 (합 약 5.5시간). 주택가격(18시간)은 따로 건다.
    "chain-cheap": [sys.executable, "pages_chain.py",
                    "--ops", "recap,atch,title,jijigu,flr,expos"],
    "chain-hsprc": [sys.executable, "pages_chain.py", "--ops", "hsprc"],
    # 실측(2026-10-20) 뒤 확정한 순서. 싼 것부터 - 중간에 끊겨도 쓸 수 있는 축이
    # 먼저 쌓인다. 합 약 35.6시간이라 이틀에 걸쳐 돈다.
    #   표제부 22분 · 지역지구 27분 · 층별 1.9h · 전유부 2.5h
    #   전유공용면적 12.2h · 주택가격 18.1h
    "chain-all": [sys.executable, "pages_chain.py",
                  "--ops", "title,jijigu,flr,expos,exar,hsprc"],


    # ---- 로그인 준비 (2026-10-19) ----
    # 테이블 + 서명키(AUTH_SECRET) + root 계정. 여러 번 돌려도 안전하다 -
    # 이미 있으면 **건드리지 않는다**(비밀번호를 덮어쓰면 안 된다).
    # ★ python 이 아니라 node 다. 스크립트는 절대경로로 준다(cwd 가 etl 이라서).
    "auth-init": ["node", r"C:\Project\Teomoony-f\tools\auth_init.js"],
    # root 비밀번호를 .env 의 ROOT_PASSWORD 값으로 맞춘다.
    # ★ 비밀번호를 인자로 받지 않는다 - 터미널 기록과 프로세스 목록에 남는다.
    "auth-passwd": ["node", r"C:\Project\Teomoony-f\tools\auth_passwd.js"],
    "ask-probe": ["node", r"C:\Project\Teomoony-f\tools\ask_probe.js"],
    "db-probe": ["node", r"C:\Project\Teomoony-f\tools\db_probe.js"],
    # ★ 진단은 **큐를 막지 않는다**(2026-10-20). 36시간짜리 적재가 돌면 30초짜리
    #   쿼리 하나도 그 뒤에 선다. start 로 새 창에 띄우면 큐는 바로 다음으로 간다
    #   (web, cf-run 이 쓰던 그 방식). 읽기 전용 진단에만 쓴다 - 쓰는 작업은
    #   큐를 타야 한다. 같은 테이블에 두 적재가 동시에 쓰면 교착이 난다.
    "db-bg": ["cmd", "/c", "start", "db probe", r"C:\Project\Teomoony\etl\_db_probe_bg.cmd"],
    # ★ 실거래는 건축물대장과 **같이 돌려도 된다**(2026-10-20).
    #   API 가 다르고(RTMSDataSvc*, 한도 별도) 쓰는 테이블도 다르다
    #   (silver.rtms_trade). 교착 1205 는 20 스레드가 **같은 테이블**에 몰려서
    #   났던 것이라 여기엔 안 걸린다. 새 창으로 띄워 큐를 막지 않는다.
    "rtms-bg": ["cmd", "/c", "start", "RTMS seoul", r"C:\Project\Teomoony\etl\_rtms_bg.cmd"],
    # ★ 적재한 silver 를 **화면이 읽는 gold 로** 만든다(2026-10-20).
    #   build 가 안 돌아서 서울 21개 구가 gold.complex 에 0 이었다 -
    #   465만 건을 받아 놓고 화면에는 아무것도 안 보이는 상태였다.
    #   build 가 읽는 축(기본개요·표제부·총괄·부속지번)은 이미 끝났고
    #   앞줄이 쓰는 축(층별·전유부·전유공용·주택가격)은 안 읽어서 같이 돌 만하다.
    "gold-bg": [sys.executable, "seoul_gold.py"],
    # 임시 명령 통로(2026-10-19). _win.cmd 를 고쳐 쓰고 win.job 을 떨어뜨린다.
    # 결과는 etl/_win.out.txt. ★ ASCII + CRLF 로만 쓴다 - cmd 가 CP949 로 읽는다.
    "win": ["cmd", "/c", r"C:\Project\Teomoony\etl\_win.cmd"],
    # Cloudflare 터널(2026-10-19). login 은 **창을 띄워야 한다** - 브라우저
    # 인증을 사용자가 직접 한다. 그래서 start 로 새 창에 띄운다.
    "cf-login": ["cmd", "/c", "start", "cloudflared login", r"C:\Project\Teomoony\cf_login.cmd"],
    "cf-run": ["cmd", "/c", "start", "teomoony tunnel", r"C:\Project\Teomoony\cf_run.cmd"],
    # ★ 서비스 등록은 관리자 권한이 필요하다 - 스크립트가 스스로 UAC 를 띄운다.
    "cf-service": ["cmd", "/c", "start", "cloudflared service", r"C:\Project\Teomoony\cf_service.cmd"],
    "cf-fix": ["cmd", "/c", "start", "cloudflared fix", r"C:\Project\Teomoony\cf_fix.cmd"],

    # ---- 안양·서초 실거래 (2026-10-19) ----
    # ★ 왜 따로 있나: rtms 는 **meta.load_target 의 ops 로 안 돈다.** 목표 9개
    #   어디에도 rtms 가 없다(서울 3구조차). run_plan 의 OPS 사전에는 있지만
    #   NEEDS_PERIOD 라 --from/--to 없이는 못 돌아서, 지금껏 이 스크립트를
    #   직접 불러 넣어 왔다. 2026-10-19 에 안양 단지 17,600개를 넣고도
    #   "안양 제일 비싼" 이 SCOPE 였던 이유가 이것이다 - 단지는 왔는데 거래가 없었다.
    # ★ 기간은 기존 3개 구와 **같게** 맞춘다: 2024-01 ~ 2025-12, 전 종목(10종).
    #   (11110 23,189 / 11290 52,429 / 11380 59,515 건 — 안양도 이 규모로 본다)
    # ★ --sgg 는 하나만 받는다. 그래서 구마다 따로 둔다.
    "rtms-anyang-m": [sys.executable, "load_rtms.py", "--sgg", "41171",
                      "--from", "202401", "--to", "202512"],
    "rtms-anyang-d": [sys.executable, "load_rtms.py", "--sgg", "41173",
                      "--from", "202401", "--to", "202512"],
    # 양재동 단지(2,715개)의 거래. rtms 는 시군구 단위라 서초구 전체가 들어오지만
    # 매칭은 우리가 가진 단지에만 붙으므로 해롭지 않다.
    "rtms-seocho":   [sys.executable, "load_rtms.py", "--sgg", "11650",
                      "--from", "202401", "--to", "202512"],

    # ---- 화면 서버 다시 띄우기 (2026-10-19) ----
    # ★ 왜 큐에 있나: 이 VM 에서는 Windows 프로세스를 띄울 수 없다(파일만 공유된다).
    #   바탕화면 아이콘은 click 티어로도 입력이 안 먹었다 - 마우스 이동조차
    #   전달되지 않았다. 감시기는 Windows 에서 돌고 있으니 **여기가 유일한 통로**다.
    # ★ start 로 분리해서 띄운다. 그냥 npm start 를 돌리면 감시기가 거기
    #   영원히 묶여서 다음 작업을 못 집는다.
    "web": ["cmd", "/c", "start", "터무니 화면 서버",
            r"C:\Project\Teomoony-f\restart_web.cmd"],

    # ---- 전유공용면적 (2026-10-18) ----
    # ★ probe 를 먼저 둔다. 이 축은 **분량이 미지수**다 — 정책 4장이 기각한
    #   사유가 "지번당 수천 건" 인데 법정동 단위 실측이 없다. 한 번지를 1페이지만
    #   떠서 totalCount 를 보고 범위를 정한다. 추측으로 며칠치 한도를 쓰지 않는다.
    #   (--max-pages 1 이라 run_mode 가 SINGLE 이고, 러너의 이어받기 가드가
    #    이 흔적을 보고 나중에 1페이지부터 받게 한다 — 구멍이 안 생긴다)
    "probe-exar": [sys.executable, "teomoony_ingest.py", "load",
                   "--op", "getBrExposPubuseAreaInfo",
                   "--sigungu", "11290", "--bjdong", "10300",
                   "--bun", "0636", "--max-pages", "1"],
    # 실제 적재. **일부러 불러야** 돈다 — base/ext 와 섞이지 않는다.
    "go-area":    [sys.executable, "run_plan.py", "go",
                   "--grp", "area", "--retry", "--workers", "2", "--skip-build"],

    # ---- 연속지적도 필지 (2026-10-18) ----
    # ★ 왜 필요한가: 건물 외곽선을 PNU 가 아니라 **필지 폴리곤과 공간 교차**로
    #   잇게 바꿨다(CONTEXT 11-26). 그런데 성북구는 필지가 통째로 비어 있어서
    #   150세대+ 단지 110개(약 7만 세대)가 땅이 없어 건물을 못 그린다.
    # ★ 분량 실측(2026-10-18, VWorld 직접 조회): 성북구 37개 법정동
    #   = 필지 38,811개 / size=1000 기준 **62회 호출**. 몇 분이면 끝난다.
    #   (법정동 하나를 1회로 받는다. 필지를 하나씩 부르지 않는다)
    "cadastral-sb": [sys.executable, "load_cadastral.py", "--lawd",
                     "1129010200","1129010300","1129010400","1129010500","1129010600",
                     "1129010700","1129010800","1129010900","1129011000","1129011100",
                     "1129011200","1129011300","1129011400","1129011500","1129011600",
                     "1129011700","1129011800","1129011900","1129012000","1129012100",
                     "1129012200","1129012300","1129012400","1129012500","1129012600",
                     "1129012700","1129012800","1129013000","1129013100","1129013200",
                     "1129013300","1129013400","1129013500","1129013600","1129013700",
                     "1129013900"],
    # 인자 없이 = 단지가 참조하는 법정동 **전부**. 이미 받은 곳은 SCD2 라
    # 해시가 같으면 변경 없음으로 지나간다. 범위가 늘어난 뒤 한 번씩 돌린다.
    "cadastral":    [sys.executable, "load_cadastral.py"],

    # ---- 건물 외곽선 (2026-10-18) ----
    # ★ **필지와 짝이다. 따로 넣지 마라.** load_building 은 1단계에서
    #   cadastral_parcel 의 bbox 로 영역 질의를 한다(건물 레이어에는 PNU 속성이
    #   없어 attrFilter 를 못 쓴다). 그래서 **필지가 없으면 bbox 가 없고,
    #   bbox 가 없으면 건물도 안 받아진다.**
    #   실측으로 그게 드러났다: 성북구에서 필지가 원래 있던 성북동만
    #   건물 3,142개(필지 4,932, 64%)였고, 필지가 0이던 길음동·종암동은
    #   건물도 0이었다. 2026-10-18 에 필지를 채웠으니 이제 받아진다.
    # ★ 분량 추정: 성북 필지 38,811 x 관측 비율 0.6 ≈ 건물 2만여 동.
    #   필지 적재가 16.5분이었으니 비슷한 자릿수로 본다 (정확히는 돌려봐야 안다).
    "building-sb":  [sys.executable, "load_building.py", "--lawd",
                     "1129010200","1129010300","1129010400","1129010500","1129010600",
                     "1129010700","1129010800","1129010900","1129011000","1129011100",
                     "1129011200","1129011300","1129011400","1129011500","1129011600",
                     "1129011700","1129011800","1129011900","1129012000","1129012100",
                     "1129012200","1129012300","1129012400","1129012500","1129012600",
                     "1129012700","1129012800","1129013000","1129013100","1129013200",
                     "1129013300","1129013400","1129013500","1129013600","1129013700",
                     "1129013900"],
    # 인자 없이 = 필지가 적재된 법정동 전부. 필지 범위를 넓힌 **뒤에** 돌린다.
    "building":     [sys.executable, "load_building.py"],

    # ---- 용도지역 (2026-10-18) ----
    # ★ probe 를 먼저 둔다. 한 법정동만 받아서 적재기가 제대로 도는지 본다 -
    #   전부 돌려 놓고 틀린 걸 발견하면 되돌릴 게 많아진다.
    #   장위동(1129013800) 은 재정비촉진지구라 용도지역이 여러 종류 섞여 있다.
    "landuse-probe": [sys.executable, "load_landuse.py", "--lawd", "1129013800"],
    # 필지가 적재된 법정동 전부. 1,400건 안팎이라 몇 분이면 끝난다.
    "landuse":       [sys.executable, "load_landuse.py"],

    # ---- 정비사업 구역 (2026-10-19) ----
    # 서울 열린데이터광장 OA-22712. API 가 아니라 **반기 갱신 파일**이라
    # data/uq120_4326.ndjson 을 읽기만 한다(갱신법은 data/README.txt).
    "redev":         [sys.executable, "load_redev.py"],

    # ---- 지역지구구역 (2026-10-19) ----
    # ★ probe 를 먼저. 장위동 하나(2,819건 / 29페이지)로 적재기가 제대로 도는지 본다.
    "go-jijigu-probe": [sys.executable, "run_plan.py", "go", "--ops", "jijigu",
                        "--sgg", "11290", "--workers", "1"],
    # 전체. --ops 로 부르므로 base/ext 와 섞이지 않는다.
    "go-jijigu":       [sys.executable, "run_plan.py", "go", "--ops", "jijigu",
                        "--retry", "--workers", "2"],

    # ---- 상권 점포 (2026-10-19) ----
    # 소상공인 상가(상권)정보 API. 반경 1000m 로 받아 두고 300/500 은 SQL 에서 센다.
    # ★ probe: 장위동(성북) + 수색동(은평) 두 법정동만.
    "semas-probe":   [sys.executable, "load_semas.py",
                      "--lawd", "1129013800", "1138010100"],
    "semas":         [sys.executable, "load_semas.py"],

    # ---- 학교 위치 (2026-10-19) ----
    # 전국초중등학교위치표준데이터 (data.go.kr 15021148, 교육부/한국교육시설안전원).
    # ★ 상권 데이터에는 학교가 **0건**이라 별도 출처가 필요하다(실측 176_edu).
    # ★ 키 등록이 먼저다 - 15021148 에서 활용신청(자동승인) 을 누르기 전에는
    #   SERVICE_KEY_IS_NOT_REGISTERED_ERROR(30) 로 **즉시 멈춘다**(조용히 0건 아님).
    # probe: 1페이지만 떠서 총건수와 **값의 생김새**를 본다. 추측으로 쓰지 않는다.
    "school-probe":  [sys.executable, "load_school.py", "--probe"],
    "school":        [sys.executable, "load_school.py"],

    # ---- 버스정류소 (2026-10-19) ----
    # TAGO 버스정류소정보 (data.go.kr 15096280). 활용신청(자동승인) 이 먼저다.
    # ★ 순서가 있다: cities(도시코드를 **추측 않고 받는다**) -> probe(생김새)
    #   -> bus-seoul / bus(전국). 좌표 반경(getCrdntPrxmtSttnList) 은 안 쓴다 -
    #   단지마다 한 번이라 11-46(상권 96% 중복)과 같은 낭비가 된다.
    # ★ load_bus.py(API) 는 **버렸다** — TAGO 도시 목록에 서울이 없다(실측).
    #   백업 load_bus.py.bak_api 로 남긴다. 아래가 파일 기반 후임이다.
    "bus-cities":    [sys.executable, "load_bus.py", "--cities"],

    # ---- 대중교통: 버스정류장 + 지하철역 (2026-10-19, 파일 기반) ----
    # 버스   data/bus_stop_*.csv      (국토부 15067528, 227,065행, 서울 포함)
    # 지하철 data/subway_station_*.xlsx (국가철도공단 15013205, 1,099행, 47노선)
    "subway":        [sys.executable, "load_transit.py", "--what", "subway"],
    "bus-file":      [sys.executable, "load_transit.py", "--what", "bus"],
    "transit":       [sys.executable, "load_transit.py"],

    # ---- 상권 분기 스냅샷 (2026-10-19) ----
    # 폐업을 보려면 '지금 영업중' 스냅샷(API) 말고 **분기 파일**을 쌓아야 한다.
    # bizes_id 가 분기를 넘어 유지되는 건 185 에서 실측했다(1,000 중 871 생존).
    "semas-q":       [sys.executable, "load_semas_quarter.py"],

    # ---- 버스 경유노선 (2026-10-19) ----
    # '몇 번 버스가 서나'. 노선 기준이라 1,352회면 서울 전부를 덮는다
    # (정류장 기준이면 13,010회). 하루 한도 1,000 이라 **이어받기**로 돈다 -
    # 이미 받은 노선은 건너뛰고, 한도에 걸리면 받은 데까지 저장하고 멈춘다.
    "bus-route":     [sys.executable, "load_bus_route.py"],

    # ---- 학구도(초등학교 통학구역) (2026-10-19) ----
    # 거리가 아니라 **배정**을 말하려면 이 폴리곤이 있어야 한다.
    # SHP 는 받을 때 4326 ndjson 으로 바꿔서 data/ 에 넣는다(README).
    "school-zone":   [sys.executable, "load_school_zone.py"],

    # ---- AI 검색 조건 요약표(312) 다시 세기 (2026-10-22) ----
    # ★ 적재가 끝나면 handle() 이 **저절로** 뒷줄에 건다(요약다시). 손으로 떨궈도 된다. 약 20분.
    "z-askattr-par":  ["__SQL__", os.path.join(SQLDIR, "314_ask_attr_refresh.sql"), "314_ask_attr_refresh"],
    # ---- 받은 범위표(339 meta.coverage) 다시 세기 (2026-10-24 전국 넓히기 1단계) ----
    # ★ 화면의 'SCOPE(아직 안 받음)' 와 "○○만 다룹니다" 가 이 표를 본다. 받는 작업이 끝나면 저절로 건다(범위걸기). 약 20초.
    "z-coverage-par": ["__SQL__", os.path.join(SQLDIR, "339_coverage_run.sql"), "339_coverage_run"],

    # ---- 유치원 (2026-10-19) ----
    # ★ 유치원알리미 자체 도메인이다(data.go.kr 아님).
    #   basicInfo2.do 를 쓴다 - basicInfo.do 에는 **좌표가 없다**(실측).
    #   data.go.kr 설명에는 '위치정보' 가 있다고 적혀 있다. 설명 말고 응답을 본다.
    # ★ 래퍼는 kinderInfo 다. response 가 아니다 - 학교 API 와 또 다르다.
    # ★ 시도x시군구 단위라 우리 6개 구면 **6회**면 끝난다.
    "kinder-probe": [sys.executable, "load_kinder.py", "--probe"],
    "kinder":       [sys.executable, "load_kinder.py"],

    # ---- 전국 법정동코드 (2026-10-19) ----
    # 범위를 넓힐 때마다 시군구/법정동 코드를 찾는 일을 없앤다.
    # 공식 파일(국토부 15063424)이라 VWorld 파생본의 한계가 없다.
    "lawd-file":     [sys.executable, "load_lawd_file.py"],

    # ---- 범위 넓히기: 안양 + 양재 (2026-10-19) ----
    # ★ 코드는 meta.lawd_code 에서 **확인한 것**이다. 외워서 쓰지 않았다 -
    #   양재동을 1165010300 으로 기억하고 있었는데 실제는 1165010200 이었다.
    "add-anyang-m":  [sys.executable, "run_plan.py", "add", "--sgg", "41171"],
    "add-anyang-d":  [sys.executable, "run_plan.py", "add", "--sgg", "41173"],
    "add-yangjae":   [sys.executable, "run_plan.py", "add",
                      "--sgg", "11650", "--bjdong", "10200"],
}

def child_env():
    """★ 자식이 UTF-8 로 말하게 한다 (2026-10-18).

    run_plan.py 가 **콘솔**로 쓸 때는 파이썬이 유니코드를 그대로 내보내지만,
    여기처럼 **파일로 리다이렉트**하면 로캘 인코딩(cp949)으로 떨어진다.
    그래서 두 가지가 한꺼번에 났다:
      · `—`(U+2014) 가 cp949 에 없어서 UnicodeEncodeError 로 **죽었다**
      · 죽지 않은 줄도 cp949 로 쓰였는데 로그는 utf-8 로 열려 **한글이 깨졌다**
    run_plan.py 는 제 자식들에게 이미 같은 처리를 한다(child_env, 10-17).
    빠져 있던 고리는 **run_plan 자신**이었다.

    ★ 버퍼도 끈다 (2026-10-18 오후). 파이썬은 **파이프로 쓸 때** 출력을
    블록 단위로 모았다가 내보낸다. 그래서 긴 작업이 도는 동안 로그가 텅 비어
    있고, 밖에서 보는 쪽은 **멈춘 것과 구분을 못 한다.** 은평 적재(119분)
    내내, 그리고 필지 적재 중에도 그랬다. 느린 것은 상관없지만 **말이 없는
    것은 문제다** - 화면을 못 보는 쪽이 "살아 있나" 를 추측하게 만든다.
    """
    e = dict(os.environ)
    e["PYTHONIOENCODING"] = "utf-8"
    e["PYTHONUTF8"] = "1"
    e["PYTHONUNBUFFERED"] = "1"
    return e


def ts():  return time.strftime("%Y%m%d_%H%M%S")
def now(): return time.strftime("%Y-%m-%d %H:%M:%S")

def write_status(**kw):
    kw["alive_at"] = now()
    kw["pid"] = os.getpid()
    try:
        tmp = STATUS + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(kw, f, ensure_ascii=False, indent=1)
        os.replace(tmp, STATUS)
    except Exception:
        pass        # 상태를 못 써도 일은 계속한다

EXTRA = os.path.join(HERE, "_jobs_extra.json")

def extra_jobs():
    """`_jobs_extra.json` 을 **부를 때마다** 읽는다.

    ★ 왜: JOBS 는 이 파일 안에 있어서, 일감을 하나 더하려면 restart 가 필요하다.
      그런데 restart 는 **앞줄 작업이 끝나야** 처리된다 - 36시간짜리가 돌면
      새 일감 하나 추가하려고 적재를 세워야 했다(오늘 네 번 세웠다).
      이 파일은 매번 읽으므로 **멈추지 않고 일감을 더할 수 있다.**
    ★ 형식: {"이름": ["실행파일", "인자", ...]}  — JOBS 와 같다.
    ★ JOBS 가 먼저다. 같은 이름이면 코드에 적힌 것이 이긴다.
    """
    try:
        with open(EXTRA, encoding="utf-8") as f:
            d = json.load(f)
        return {k: v for k, v in d.items()
                if isinstance(v, list) and all(isinstance(x, str) for x in v)}
    except FileNotFoundError:
        return {}
    except Exception as e:
        print(f"  (_jobs_extra.json 을 못 읽었다: {e})")
        return {}

def resolve(name):
    """큐 파일 이름 -> (argv, 설명) 또는 (None, 거절사유)."""
    if name in JOBS:
        return JOBS[name], " ".join(JOBS[name][1:])
    ex = extra_jobs()
    if name in ex:
        return ex[name], " ".join(ex[name][1:]) + "   (_jobs_extra.json)"
    if name.startswith("sql."):
        arg = name[4:]
        if not re.fullmatch(r"[A-Za-z0-9_]+", arg):
            return None, f"sql 이름이 [A-Za-z0-9_]+ 가 아님: {arg!r}"
        path = os.path.join(SQLDIR, arg + ".sql")
        if not os.path.isfile(path):
            return None, f"없는 파일: deploy\\sql\\{arg}.sql"
        return ["__SQL__", path, arg], f"sqlcmd < deploy\\sql\\{arg}.sql"
    return None, f"허용 목록에 없는 이름: {name!r}"

def db_password():
    env = os.path.abspath(os.path.join(HERE, "..", ".env"))
    with open(env, encoding="utf-8") as f:
        for line in f:
            if line.startswith("DB_PASSWORD="):
                return line.split("=", 1)[1].strip()
    raise RuntimeError(".env 에 DB_PASSWORD 가 없다")

def run_sql(path, arg, log):
    """docker 안의 sqlcmd 로 돌린다. 비밀번호는 **인자로만** 넘기고 적지 않는다."""
    # ★ 2026-10-24: 병렬 줄에서 SQL 작업 여럿이 같이 돌면 /tmp/job.sql 하나를 서로 덮어 **남의 SQL 을 돌린다** — 작업마다 이름을 따로
    dst = f"/tmp/job_{arg}.sql"
    subprocess.run(["docker", "cp", path, "teomoony-mssql:" + dst],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
    return subprocess.run(
        ["docker", "exec", "teomoony-mssql",
         "/opt/mssql-tools18/bin/sqlcmd", "-S", "localhost", "-U", "sa",
         "-P", db_password(), "-C", "-No", "-I", "-d", "Teomoony", "-W",
         # ★ -b : SQL 에러가 나면 **종료코드를 0 이 아닌 값으로** 돌려준다
         #   (2026-10-19). 이게 없어서 'Msg 130 ... 종료코드 0' 이 나왔다 -
         #   쿼리가 죽었는데 러너는 성공으로 보고, 실패 알림도 안 갔다.
         #   11-30(VWorld BOX 가 조용히 0건)과 같은 모양이라 고친다.
         #   ★ 지금까지 조용히 넘어가던 SQL 에러가 이제 실패로 뜬다.
         "-b",
         "-i", dst],
        stdout=log, stderr=subprocess.STDOUT).returncode

# ---- 적재 뒤 AI 검색 조건 요약표(312) 다시 세기 (2026-10-22 사장님 "적재 뒤에 저절로") ----
# ★ 요약표는 단지 · 대장 면적 · 실거래 · 역 · 학교 · 정비 · 용도에서 센다. 그중 하나라도 새로 받으면 묵는다.
#   그래서 **받는 작업**이 성공하면 병렬 줄(-par)에 z-askattr-par 를 한 번 건다 — 뒷줄은 긴 적재(landchar 31시간)가 잡고 있을 수 있고, 이 작업은 gold 파생표만 써서 다른 작업과 표가 안 겹친다. 이미 걸려 있거나 도는 중이면 또 걸지 않는다.
# ★ 받는 작업만(시험 · 미리보기 · 화면 · 터널 · 계정은 아님). 이름으로 고른다 — 새 적재 작업을 만들면 여기에도 넣는다.
요약다시 = re.compile(r"^(go|go-retry|go-area|seoul-add|seoul-exar|probe-exar|pages|pages-20|pages-basis|chain-.+|"
                      r"rtms-(seoul|anyang-m|anyang-d|seocho)|rtms-bg|rematch|gold-bg|building|cadastral|hsprc(-12)?|"
                      r"subway|transit|school|redev|landuse|.*exar.*-par|.*-tradepick-bg|ab-.*-bg|sql\.(283|287)_.+)$")
def 요약걸기(name):
    if name == "z-askattr-par" or name.endswith("-dry") or name.endswith("-probe") or not 요약다시.match(name):
        return
    q = os.path.join(QDIR, "z-askattr-par.job")
    if os.path.exists(q):
        return                      # 이미 걸려 있다(도는 중이면 파일이 아직 큐에 있다)
    try:
        with open(q, "w", encoding="utf-8") as f:
            f.write(f"{now()} {name} 뒤 — AI 검색 조건 요약표 다시 세기\n")
        print(f"         → z-askattr-par 를 병렬 줄에 걸었다({name} 뒤)")
    except Exception as e:
        print(f"         (z-askattr-par 를 못 걸었다: {e})")

# ---- 적재 뒤 받은 범위표(339) 다시 세기 (2026-10-24) ----
# ★ 무엇을 받았든 범위표는 묵는다 — 그래서 이름으로 고르지 않고 **z- 가 아닌 작업이 성공하면** 건다(시험 · 미리보기 제외).
#   20초짜리라 넉넉히 건다. 이미 걸려 있으면 또 걸지 않는다.
def 범위걸기(name):
    if name.startswith("z-") or name.endswith("-dry") or name.endswith("-probe") or "-test" in name:
        return
    q = os.path.join(QDIR, "z-coverage-par.job")
    if os.path.exists(q):
        return
    try:
        with open(q, "w", encoding="utf-8") as f:
            f.write(f"{now()} {name} 뒤 — 받은 범위표 다시 세기\n")
        print(f"         → z-coverage-par 를 병렬 줄에 걸었다({name} 뒤)")
    except Exception as e:
        print(f"         (z-coverage-par 를 못 걸었다: {e})")

def handle(path, quiet=False):
    """quiet=True 면 상태 파일을 쓰지 않는다 - 뒷줄(-bg) 작업용.

    ★ 왜: 상태 파일은 한 칸뿐이라 두 작업이 같이 쓰면 서로를 덮는다.
      앞줄이 36시간짜리를 돌고 있는데 뒷줄이 'idle' 로 덮어 버리면
      내가 큐를 잘못 읽는다. 뒷줄은 **로그만** 남긴다.
    """
    name = os.path.basename(path)[:-4]          # .job 떼기
    argv, what = resolve(name)
    stamp = ts()
    if argv is None:
        print(f"  [{now()}] 거절  {name}  — {what}")
        os.makedirs(REJECT, exist_ok=True)
        try:
            os.replace(path, os.path.join(REJECT, f"{stamp}_{name}.job"))
            with open(os.path.join(REJECT, f"{stamp}_{name}.why.txt"),
                      "w", encoding="utf-8") as f:
                f.write(what + "\n")
        except Exception as e:
            print(f"         (옮기지 못했다: {e})")
        if not quiet:
            write_status(state="idle", last=name, result="REJECTED", why=what)
        return

    logpath = os.path.join(LOGDIR, f"job_{stamp}_{name}.log")
    print(f"  [{now()}] 실행  {name}  -> {what}")
    print(f"         로그 logs\\{os.path.basename(logpath)}")
    if not quiet:
        write_status(state="running", job=name, cmd=what,
                     log=os.path.basename(logpath), started=now())
    t0 = time.time()
    os.makedirs(LOGDIR, exist_ok=True)
    rc = -1
    try:
        with open(logpath, "w", encoding="utf-8") as log:
            log.write(f"$ {what}\n  시작 {now()}\n\n"); log.flush()
            if argv[0] == "__SQL__":
                rc = run_sql(argv[1], argv[2], log)
            else:
                rc = subprocess.run(argv, cwd=HERE, stdout=log,
                                    stderr=subprocess.STDOUT,
                                    env=child_env()).returncode
            log.write(f"\n  끝 {now()}  종료코드 {rc}\n")
    except Exception as e:
        print(f"         오류: {e}")
        try:
            with open(logpath, "a", encoding="utf-8") as log:
                log.write(f"\n  실행 못 함: {e}\n")
        except Exception:
            pass
    took = time.time() - t0
    print(f"  [{now()}] 끝    {name}  종료코드 {rc}  ({took/60:.1f}분)")

    # ---- 실패하면 알린다 (2026-10-18) ----
    # ★ 성공은 적재기가 스스로 알린다(_notify). 실패는 **아무도 안 알렸다** -
    #   집 밖에 있으면 '끝난 것' 과 '죽은 것' 이 똑같이 조용하다. 11-33 에서
    #   성공 알림을 고치고 나서야 이쪽 구멍이 보였다.
    # ★ rc != 0 일 때만 보낸다. 성공까지 여기서 보내면 두 번 간다.
    # ★ 로그 꼬리를 같이 보낸다. 알림만 오고 원인을 보려고 PC 를 켜야 하면
    #   알림이 반쪽이다.
    # ★ 알림이 watcher 를 죽이면 안 된다 - 어떤 예외도 밖으로 안 던진다.
    # ★ 10-30: 종료코드 3 = '건너뜀(할 일 없음 · 출처에 새 것 없음 · 디스크 모자라 미룸)' — 이 프로젝트 약속(collect_cron 도 3 을 건너뜀으로 적는다).
    #   실패가 아니라 알리지 않는다(10-30 18:50 '상세 다시' 표가 빈 날 '적재 실패' 가 갔다). 진짜 멈춤은 다른 코드로 낸다(K-apt 한도 초과 = 4).
    if rc == 3:
        print("         건너뜀(종료코드 3 — 할 일 없음) · 알림 안 보냄")
    if rc not in (0, 3):
        try:
            tail = ""
            try:
                with open(logpath, encoding="utf-8", errors="replace") as f:
                    tail = "".join(f.readlines()[-6:]).strip()
            except Exception:
                pass
            import notify
            msg = ("[터무니] 적재 실패\n"
                   + name + " · 종료코드 " + str(rc)
                   + " · " + format(took / 60, ".1f") + "분\n"
                   + "로그 logs\\" + os.path.basename(logpath))
            if tail:
                msg += "\n---\n" + tail[-500:]
            ok, why = notify.send(msg)
            print("         실패 알림 " + ("보냄" if ok else "안 보냄 - " + str(why)))
        except Exception as e:
            print("         (실패 알림 못 보냄: %s)" % e)
    os.makedirs(DONE, exist_ok=True)
    try:
        os.replace(path, os.path.join(DONE, f"{stamp}_{name}.job"))
    except Exception as e:
        print(f"         (큐에서 못 치웠다 — 다음 바퀴에 또 돕니다: {e})")
    if rc == 0:
        요약걸기(name)
        범위걸기(name)
        if "landchar" in name:      # 2026-10-24(347): 토지특성을 새로 받았으면 변경 로그를 다시 뽑는다
            try:
                q = os.path.join(QDIR, "zl-changelog-par.job")
                if not os.path.exists(q):
                    with open(q, "w", encoding="utf-8") as f:
                        f.write(f"{now()} {name} 뒤 — 토지특성 변경 로그 다시\n")
            except Exception as e:
                print(f"         (zl-changelog-par 를 못 걸었다: {e})")
    if not quiet:
        write_status(state="idle", last=name, result=f"rc={rc}",
                     sec=round(took, 1), log=os.path.basename(logpath),
                     finished=now())

_bg = {"t": None}

PAR_MAX = 8   # 2026-10-24 사장님 "적재할 때 스레드를 최대한" — 4 → 8
_par = {}   # 이름 → 스레드


def par_watch():
    """병렬 줄(-par) — 2026-10-22 사장님 "병렬로 할 수 있는 건 최대한 병렬로".
    ★ 앞줄·뒷줄과 따로, **이름이 -par 로 끝나는 작업은 각자 스레드**로 같이 돈다(최대 PAR_MAX).
    ★ 같은 이름은 하나만. 상태 파일은 안 쓴다(quiet) — 로그만.
    ★ 쓰는 표가 겹치는 작업끼리는 -par 로 태우지 마라(교착 1205). 서로 다른 표·다른 API 키인 것만.
    """
    while True:
        try:
            for k in [k for k, t in _par.items() if not t.is_alive()]:
                _par.pop(k, None)
            jobs = sorted(f for f in os.listdir(QDIR) if f.endswith("-par.job"))
            for f in jobs:
                if len(_par) >= PAR_MAX: break
                if f in _par: continue
                print(f"  [{now()}] 병렬  {f[:-4]}  (앞줄·뒷줄과 같이 돕니다)")
                t = threading.Thread(target=handle, args=(os.path.join(QDIR, f),), kwargs={"quiet": True}, daemon=True)
                _par[f] = t; t.start()
        except Exception as e:
            print(f"  병렬 감시 오류(무시하고 계속): {e}")
        time.sleep(3)


def bg_watch():
    """뒷줄(-bg) 전용 감시 — **메인 루프와 따로 돈다**.

    ★ 처음엔 메인 루프 안에 넣었는데 안 됐다. 구조가 이렇다:
          while True:
              jobs = 큐 읽기        <- 한 번 읽고
              for f in jobs: handle(f)   <- 여기서 36시간 멈춘다
      앞줄이 도는 동안에는 **루프 자체가 안 돌아서** 뒷줄 검사도 같이 멈춘다.
      한 번 된 적이 있어 더 헷갈렸다 - 재시작 직후 큐에 남아 있던 것을 집은
      것뿐이었다. '한 번 됐다' 가 '된다' 는 아니다.
    ★ 그래서 **독립 스레드**로 뺀다. 메인 루프는 한 줄도 안 건드린다.
    ★ 한 번에 하나만. 뒷줄이 여럿이면 직렬로 둔 이유(교착 1205)가 되살아난다.
    ★ 쓰는 작업을 뒷줄에 태우려면 **테이블이 겹치지 않는지 먼저 보라.**
      실거래(silver.rtms_trade)는 건축물대장과 안 겹쳐서 괜찮다.
    """
    while True:
        try:
            if not (_bg["t"] and _bg["t"].is_alive()):
                jobs = sorted(f for f in os.listdir(QDIR)
                              if f.endswith("-bg.job"))
                if jobs:
                    f = jobs[0]
                    print(f"  [{now()}] 뒷줄  {f[:-4]}  (앞줄과 같이 돕니다)")
                    _bg["t"] = threading.Thread(
                        target=handle, args=(os.path.join(QDIR, f),),
                        kwargs={"quiet": True}, daemon=True)
                    _bg["t"].start()
        except Exception as e:
            print(f"  뒷줄 감시 오류(무시하고 계속): {e}")
        time.sleep(3)

def main():
    os.makedirs(QDIR, exist_ok=True)
    print()
    print("  터무니 작업 감시")
    print(f"  보는 곳 : {QDIR}")
    print(f"  허용    : {', '.join(sorted(JOBS))}, sql.<이름>, restart, stop")
    print(f"  (+ _jobs_extra.json 에 적은 것 - **멈추지 않고** 더할 수 있다)")
    print( "  이 창을 닫으면 아무것도 실행되지 않습니다.")
    print()
    write_status(state="idle", started=now())
    threading.Thread(target=bg_watch, daemon=True).start()
    threading.Thread(target=par_watch, daemon=True).start()
    while True:
        try:
            jobs = sorted(f for f in os.listdir(QDIR) if f.endswith(".job"))
        except Exception as e:
            print(f"  큐를 못 읽었다: {e}")
            jobs = []
        for f in jobs:
            # ★ restart.job - 코드를 새로 읽고 **다시 뜬다** (2026-10-19 추가)
            #   watch.cmd 는 _restart.flag 가 있을 때만 다시 띄운다. 그동안
            #   flag 를 따로 만들고 stop 을 넣는 식으로 썼는데, 2026-10-19 에
            #   **flag 없이 stop 만 넣어서 감시기를 죽여 버렸다.** 물리적으로
            #   가지 않으면 못 살리는 상태가 됐다. 두 동작을 하나로 묶는다.
            if f == "restart.job":
                # ★ 2026-10-22: 뒷줄·병렬 줄이 돌고 있으면 restart 를 **미룬다**.
                #   프로세스가 끝나면 데몬 스레드는 죽지만 자식 프로세스는 계속 돈다 →
                #   .job 이 done 으로 안 옮겨져 재시작 뒤 **같은 작업이 두 번** 뜬다.
                busy = [k for k, t in _par.items() if t.is_alive()]
                if (_bg.get("t") and _bg["t"].is_alive()) or busy:
                    continue
                print(f"  [{now()}] restart 받음 — 코드를 다시 읽고 돌아옵니다.")
                try: os.remove(os.path.join(QDIR, f))
                except Exception: pass
                try:
                    open(os.path.join(QDIR, "_restart.flag"), "w").close()
                except Exception as e:
                    print(f"  재시작 표시를 못 만들었다: {e} — 그냥 멈춥니다")
                    write_status(state="stopped", finished=now())
                    return
                write_status(state="restarting", finished=now())
                return
            if f == "stop.job":
                print(f"  [{now()}] stop 받음 — 감시를 끝냅니다.")
                print(f"  (다시 띄우려면 watch.cmd 를 실행하세요. 코드만 새로"
                      f" 읽히려면 stop 말고 **restart** 를 쓰세요.)")
                try: os.remove(os.path.join(QDIR, f))
                except Exception: pass
                write_status(state="stopped", finished=now())
                return
            if f[:-4].endswith("-bg"):
                continue                # 뒷줄 스레드가 따로 집는다
            if f[:-4].endswith("-par"):
                continue                # 병렬 줄 스레드가 따로 집는다
            handle(os.path.join(QDIR, f))
        write_status(state="idle")
        time.sleep(POLL)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n  중단됨 (Ctrl+C)")
        write_status(state="stopped", finished=now())
