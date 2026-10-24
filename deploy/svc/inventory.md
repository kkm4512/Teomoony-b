# 서비스DB 분리 1단계 — 서버 API · 읽는 표 목록 (inventory)

2026-10-24 · Teomoony-f/src/server.js(7,602줄) · public/app.js 를 읽어서 만든 목록(코드는 안 고침). 행 수 · 크기는 같은 날 DB 실측(sys.partitions).

## 0. 요약

| 항목 | 수 |
|---|---|
| 열린 길(app.get/post/put/delete) | 82 — 화면·공개 66 · 진단/집안 전용 16 |
| 화면이 실제로 부르는 /api 길 | 60 (app.js fetch 기준 · /api/zones · /api/redev 는 `/api/${overlay}` 로 부름) |
| 읽는 표 · 뷰 · 함수(이름 기준) | 132 — 뷰를 풀어 바닥 표까지 내리면 화면용 98개 |
| 그 바닥 표의 지금 크기 합 | 57.2 GB (원본 칸·옛 버전 포함) |
| 단지 상세 쿼리 | 34개 — 입력이 전부 `@id` 하나 → **34개 모두 단지별로 미리 계산 가능**(그중 4개는 '받았나' 범위 판정 → 시군구 단위 표로) |
| T-SQL 전용 문법 사용(아래 6장) | 큰 것만: APPLY 29 · TOP 128 · 공간 메서드 52+생성 19 · ISNULL 82 · 임시표 17종(79곳) · DECLARE 29 |
| 서비스DB 예상 크기 | **10~15 GB**(화면 단위로 미리 계산 · 지금 줄만 · 필요한 칸만 — 7장) |

## 1. 화면 · 공개 API

`s.`=silver · `g.`=gold · `m.`=meta · `o.`=ops. app.js = 화면 코드에서 그 주소를 부르는 곳 수. 공간 = .STxxx 공간 메서드 수(bbox 칸 비교는 따로).

| 메서드 | 주소 | 분류 | app.js | 쿼리 | 공간 | bbox칸 | 쓰기 | 읽는 것 |
|---|---|---|---|---|---|---|---|---|
| GET | `/api/usage` | 사용자·운영(쓰기 영역) | 2 | 1 |  |  |  | o.req_log, o.usage_hour, o.usage_owner_ip |
| GET | `/api/admin/ips` | 사용자·운영(쓰기 영역) | 1 | 1 |  |  |  | o.req_log, o.usage_owner_ip |
| GET | `/api/config` | 화면 읽기 | 1 | 1 |  |  |  | g.complex, m.coverage, m.lawd_code |
| GET | `/api/coverage` | 화면 읽기 | 1 | 0 |  |  |  | m.coverage, m.lawd_code |
| GET | `/api/health` | 홈 수치 | 2 | 2 |  |  |  | g.complex, g.complex_pnu, g.region_bdong, g.region_hdong, g.v_trade_offsite, m.coverage, s.academy, s.bld_atch_jibun, s.bld_basis_outline, s.bld_expos, s.bld_expos_pubuse_area, s.bld_flr_outline, s.bld_hsprc, s.building_footprint, s.bus_route, s.bus_route_stat … |
| GET | `/api/complexes` | 화면 읽기 | 1 | 10 |  | 12 |  | g.applyhome_link, g.closed_site, g.complex, g.complex_alias, g.complex_bld, g.complex_kapt, g.complex_pnu, g.region_hdong, g.region_hdong_change, g.v_complex_map, g.v_lawd_map, g.v_newbuild, m.coverage, m.lawd_code, s.applyhome_pblanc, s.bld_atch_jibun, s.cada … |
| GET | `/api/suggest` | 화면 읽기 | 1 | 1 |  | 28 |  | g.applyhome_link, g.closed_site, g.complex, g.complex_alias, g.complex_kapt, g.complex_pnu, g.region_hdong, g.region_hdong_change, g.v_newbuild, m.coverage, m.lawd_code, s.academy, s.adm_boundary, s.applyhome_pblanc, s.cadastral_parcel, s.kapt_complex, s.kinde … |
| GET | `/api/adms/:cd/geo` | 화면 읽기 | 2 | 1 |  |  |  | g.complex_station, m.lawd_code, s.adm_boundary |
| POST | `/api/login` | 사용자·운영(쓰기 영역) | 2 | 2 |  |  | ✔ | m.app_user |
| GET | `/api/me` | 사용자·운영(쓰기 영역) | 1 | 0 |  |  |  | o.usage_owner_ip |
| POST | `/api/inquiry` | 사용자·운영(쓰기 영역) | 2 | 1 |  |  | ✔ | o.inquiry |
| GET | `/api/inquiries` | 사용자·운영(쓰기 영역) | 1 | 1 |  |  |  | o.inquiry |
| POST | `/api/inquiry/:id/answer` | 사용자·운영(쓰기 영역) | 1 | 1 |  |  | ✔ | o.inquiry, o.notice |
| GET | `/api/my` | 사용자·운영(쓰기 영역) | 1 | 1 |  |  |  | g.complex, m.app_user, o.ask_log, o.fav_complex, o.inquiry, o.notice |
| GET | `/api/my/badge` | 사용자·운영(쓰기 영역) | 1 | 1 |  |  |  | o.fav_complex, o.notice |
| PUT | `/api/my/fav/:id` | 사용자·운영(쓰기 영역) | 1 | 1 |  |  | ✔ | g.complex, o.fav_complex |
| DELETE | `/api/my/fav/:id` | 사용자·운영(쓰기 영역) | 1 | 1 |  |  | ✔ | o.fav_complex |
| POST | `/api/my/notice/read` | 사용자·운영(쓰기 영역) | 2 | 6 |  |  | ✔ | g.complex, g.complex_area, g.complex_area_trade, g.complex_redev_hit, g.complex_school_near, g.complex_station, g.complex_trade_max, g.complex_zone_hit, g.region_bdong, m.coverage, m.lawd_code, o.ask_log, o.notice, s.redev_zone, s.rtms_trade |
| GET | `/api/ask` | AI 검색(읽기+로그 쓰기) | 1 | 11 |  |  |  | g.ask_attr_meta, g.closed_site, g.complex, g.complex_alias, g.complex_area, g.complex_area_trade, g.complex_kapt, g.complex_redev_hit, g.complex_school_near, g.complex_station, g.complex_trade_max, g.complex_zone_hit, g.region_bdong, g.v_newbuild, m.coverage,  … |
| GET | `/api/newbuilds` | 화면 읽기 | 1 | 2 |  |  |  | g.v_kapt_cost_item, g.v_kapt_cost_latest, g.v_newbuild, s.kapt_complex, s.kapt_cost |
| GET | `/api/newbuilds/:code` | 화면 읽기 | 1 | 2 |  |  |  | g.v_kapt_cost_item, g.v_kapt_cost_latest, g.v_newbuild, g.v_newbuild_trade, s.kapt_complex, s.kapt_cost |
| GET | `/api/lawds` | 화면 읽기 | 1 | 1 |  | 4 |  | g.v_lawd_map, s.adm_boundary, s.lawd_boundary |
| GET | `/api/adms` | 화면 읽기 | 1 | 1 |  | 4 |  | s.adm_boundary |
| GET | `/api/zones` | 화면 읽기 | 0 | 1 |  | 4 |  | s.land_use_zone |
| GET | `/api/redev` | 화면 읽기 | 0 | 1 |  | 4 |  | g.v_complex_redev, s.redev_zone |
| GET | `/api/redev/:sn/detail` | 화면 읽기 | 1 | 1 | 2 | 20 |  | g.applyhome_link, g.complex_alias, g.complex_trade_max, g.redev_plan_link, g.school_link, g.v_complex_map, g.v_complex_redev, s.applyhome_pblanc, s.cadastral_parcel, s.redev_zone, s.rtms_trade, s.school_zone, s.seoul_redev_plan |
| GET | `/api/school/:sid` | 화면 읽기 | 1 | 1 | 10 |  |  | g.complex, g.school_link, s.school, s.school_group, s.school_zone, s.school_zone_link, s.schoolinfo, s.schoolinfo_move, s.schoolinfo_stat |
| GET | `/api/schoolzone/:kind/:id` | 화면 읽기 | 1 | 1 | 2 |  |  | g.school_link, s.school, s.school_group, s.school_zone, s.school_zone_link |
| GET | `/api/redev/:sn` | 화면 읽기 | 1 | 1 |  |  |  | s.redev_zone |
| GET | `/api/lawds/:lawd/geo` | 화면 읽기 | 2 | 1 |  |  |  | g.usp_refresh_applyhome_link, g.v_lawd_map, s.lawd_boundary |
| GET | `/api/applyhome` | 화면 읽기 | 4 | 1 |  |  |  | g.applyhome_link, g.complex, g.complex_pnu, g.fn_complex_silv, s.applyhome_cmpet, s.applyhome_mdl, s.applyhome_pblanc, s.applyhome_score, s.kapt_complex, s.rtms_trade |
| GET | `/api/applyhome/dong/:lawd` | 화면 읽기 | 1 | 1 |  | 4 |  | g.applyhome_link, m.lawd_code, s.applyhome_pblanc, s.cadastral_parcel, s.lawd_boundary |
| GET | `/api/applyhome/:house/where` | 화면 읽기 | 1 | 2 |  | 4 |  | s.applyhome_pblanc, s.cadastral_parcel, s.land_move_done, s.land_move_hist |
| GET | `/api/applyhome/pins` | 화면 읽기 | 1 | 1 |  | 4 |  | g.applyhome_link, s.applyhome_pblanc, s.cadastral_parcel, s.land_use_plan |
| GET | `/api/complexes/:id/landuse-shape` | 화면 읽기 | 1 | 2 | 1 | 8 |  | g.complex_pnu, s.cadastral_parcel, s.land_use_plan, s.vworld_zone, s.vworld_zone_done |
| GET | `/api/complexes/:id/usage` | 화면 읽기 | 1 | 1 |  |  |  | g.complex, g.complex_bld, g.v_complex_ho, s.bld_expos_pubuse_area, s.bld_recap_title, s.bld_title, s.childcare, s.kinder_info, s.kindergarten |
| GET | `/api/kinder/:code` | 화면 읽기 | 1 | 1 | 1 |  |  | s.kinder_info, s.kindergarten |
| GET | `/api/childcare/:st` | 화면 읽기 | 1 | 1 | 1 |  |  | s.childcare |
| GET | `/api/complexes/:id/poi-list` | 화면 읽기 | 1 | 1 |  |  |  | g.v_complex_poi |
| GET | `/api/complexes/:id/childcare` | 화면 읽기 | 1 | 1 | 2 |  |  | g.complex, s.childcare |
| GET | `/api/complexes/:id/pharmacy` | 화면 읽기 | 1 | 1 | 2 |  |  | g.closed_site, g.complex, m.coverage, s.mois_pharmacy, s.rtms_trade |
| GET | `/api/closed/pins` | 화면 읽기 | 1 | 1 |  |  |  | g.closed_site, g.complex |
| GET | `/api/closed/site/:key` | 화면 읽기 | 4 | 1 |  |  |  | g.closed_site, g.complex, s.bld_closed_detail_done, s.bld_closed_expos, s.bld_closed_expos_area, s.bld_closed_flr, s.bld_closed_title, s.cadastral_parcel, s.land_move_done, s.land_move_hist, s.ned_aphus_done, s.ned_aphus_price, s.rtms_trade |
| GET | `/api/closed/site/:key/ned` | 화면 읽기 | 1 | 1 |  |  |  | g.closed_site, s.ned_aphus_price |
| GET | `/api/complexes/:id/closed` | 화면 읽기 | 1 | 1 |  |  |  | g.closed_site, g.complex, g.complex_pnu, m.lawd_code, s.adm_boundary, s.bld_closed_title, s.cadastral_parcel |
| GET | `/api/areas/sido` | 화면 읽기 | 1 | 1 |  |  |  | g.complex, m.lawd_code |
| GET | `/api/areas/sgg` | 화면 읽기 | 1 | 1 |  | 8 |  | g.complex, m.lawd_code, s.adm_boundary, s.lawd_boundary |
| GET | `/api/areas/dongs` | 화면 읽기 | 1 | 2 |  | 8 |  | g.complex, m.coverage, m.lawd_code, s.adm_boundary, s.lawd_boundary |
| GET | `/api/areas/here` | 화면 읽기 | 1 | 1 | 2 | 8 |  | s.adm_boundary, s.lawd_boundary |
| GET | `/api/areas/relate` | 화면 읽기 | 1 | 1 | 7 | 16 |  | s.adm_boundary, s.lawd_boundary |
| GET | `/api/complexes/:id/points` | 화면 읽기 | 1 | 4 | 7 |  |  | g.complex, g.v_complex_academy, g.v_complex_bus, g.v_complex_childcare, g.v_complex_kinder, g.v_complex_poi, g.v_complex_school, g.v_complex_subway, s.bus_route, s.bus_route_station, s.hira_inst, s.hira_open |
| GET | `/api/complexes/near` | 화면 읽기 | 1 | 1 | 2 |  |  | g.complex, m.lawd_code |
| GET | `/api/complexes/markers` | 화면 읽기 | 1 | 1 |  |  |  | g.complex_alias, g.v_complex_map, s.rtms_trade |
| GET | `/api/complexes/:id` | 화면 읽기 | 3 | 36 | 5 |  |  | g.bld_violation, g.bld_vlrat, g.complex, g.complex_alias, g.complex_bld, g.complex_kapt, g.complex_pnu, g.fn_complex_silv, g.redev_plan_link, g.school_link, g.v_bld_vlrat, g.v_complex_academy, g.v_complex_bus, g.v_complex_floor, g.v_complex_ho, g.v_complex_ho_ … |
| GET | `/api/ho/:pk` | 화면 읽기 | 1 | 7 |  |  |  | g.complex, g.v_complex_ho, g.v_complex_ho_price, g.v_complex_map, g.v_ho_hsprc, m.recordset, s.bld_expos_pubuse_area, s.bld_flr_outline |
| GET | `/api/complexes/:id/geo` | 화면 읽기 | 1 | 1 |  |  |  | g.complex, g.complex_pnu, g.fn_complex_silv, s.cadastral_parcel |
| GET | `/api/complexes/:id/history` | 화면 읽기 | 1 | 1 |  |  |  | g.applyhome_link, g.change_log, g.closed_site, g.complex, g.complex_pnu, g.complex_redev_hit, g.fn_complex_silv, g.redev_plan_link, s.applyhome_pblanc, s.arch_permit, s.land_move_hist, s.redev_zone, s.rtms_trade, s.seoul_redev_plan |
| GET | `/api/complexes/:id/hira` | 화면 읽기 | 1 | 1 | 7 |  |  | g.complex, m.coverage, s.hira_inst, s.hira_open |
| GET | `/api/complexes/:id/landuse` | 화면 읽기 | 1 | 1 |  |  |  | g.complex, g.complex_pnu, s.land_use_done, s.land_use_plan |
| GET | `/api/complexes/:id/buildings` | 화면 읽기 | 1 | 1 | 1 | 8 |  | g.complex, g.complex_pnu, s.building_footprint, s.cadastral_parcel |
| GET | `/api/buildings` | 화면 읽기 | 1 | 1 |  | 4 |  | g.complex, g.complex_pnu, s.building_footprint |
| GET | `/api/parcels` | 화면 읽기 | 1 | 1 |  | 4 |  | g.complex, g.complex_pnu, s.cadastral_parcel |
| GET | `/robots.txt` | 정적/SEO | — | 0 |  |  |  |  |
| GET | `/about` | 정적/SEO | — | 0 |  |  |  |  |
| GET | `/sitemap.xml` | 정적/SEO | — | 1 |  |  |  | g.v_complex_map |
| GET | `/c/:id` | 화면 읽기 | — | 1 |  |  |  | g.complex, g.complex_alias, g.complex_trade_max, g.v_complex_map, s.rtms_trade |

## 2. 진단 · 집안 전용 API (서비스 서버로 안 옮김 — 적재 쪽 관리 도구)

`/api/_usage_rebuild`, `/api/_off`, `/api/_verify212`, `/api/_apply`, `/api/_export`, `/api/_gap`, `/api/_slow`, `/api/_cover`, `/api/_prog`, `/api/_reqlog`, `/api/_who`, `/api/_rtms`, `/api/_ned`, `/api/_perf/:id`, `/api/_ask`, `/api/_my`

## 3. 표 · 뷰 · 함수별

갱신: 적재 = 적재 때마다 바뀜(발행 대상) · 사용자 = 화면에서 쓰는 운영 기록(서비스DB 안 쓰기 영역 — 발행이 덮어쓰면 안 됨) · 메타 = 적재 범위/진행.

| 이름 | 종류 | 행 | MB | 공간칸 | 읽는 화면 API | 갱신 |
|---|---|---|---|---|---|---|
| s.bld_hsprc | 표 | 34,958,910 | 14,829 |  | `/api/health`, `/api/complexes/:id` | 적재 |
| s.rtms_trade | 표 | 12,018,264 | 9,888 |  | `/api/health`, `/api/my/notice/read`, `/api/ask`, `/api/redev/:sn/detail` 외 7 | 적재 |
| s.bld_expos_pubuse_area | 표 | 14,953,654 | 7,997 |  | `/api/health`, `/api/complexes/:id/usage`, `/api/complexes/:id`, `/api/ho/:pk` | 적재 |
| s.land_char | 표 | 12,307,782 | 5,209 |  | `/api/health` | 적재 |
| s.bld_basis_outline | 표 | 5,051,357 | 4,220 |  | `/api/health`, `/api/complexes/:id` | 적재 |
| s.ned_aphus_price | 표 | 21,239,036 | 3,255 |  | `/api/closed/site/:key`, `/api/closed/site/:key/ned` | 적재 |
| s.bld_expos | 표 | 4,168,424 | 1,907 |  | `/api/health`, `/api/complexes/:id` | 적재 |
| s.cadastral_parcel | 표 | 1,010,699 | 1,668 | ✔ | `/api/health`, `/api/complexes`, `/api/suggest`, `/api/redev/:sn/detail` 외 10 | 적재 |
| s.bld_flr_outline | 표 | 3,104,974 | 1,173 |  | `/api/health`, `/api/complexes/:id`, `/api/ho/:pk` | 적재 |
| s.building_footprint | 표 | 647,774 | 1,105 | ✔ | `/api/health`, `/api/complexes/:id`, `/api/complexes/:id/buildings`, `/api/buildings` | 적재 |
| s.vworld_zone | 표 | 23,689 | 613 | ✔ | `/api/complexes/:id/landuse-shape` | 적재 |
| s.bld_title | 표 | 650,836 | 602 |  | `/api/complexes/:id/usage`, `/api/complexes/:id` | 적재 |
| s.semas_store | 표 | 610,752 | 488 | ✔ | `/api/health`, `/api/suggest` | 적재 |
| g.complex | 표 | 574,607 | 456 |  | `/api/config`, `/api/health`, `/api/complexes`, `/api/suggest` 외 27 | 적재 |
| s.land_use_plan | 표 | 1,264,091 | 454 |  | `/api/applyhome/pins`, `/api/complexes/:id/landuse-shape`, `/api/complexes/:id/landuse` | 적재 |
| s.land_move_hist | 표 | 1,770,203 | 453 |  | `/api/applyhome/:house/where`, `/api/closed/site/:key`, `/api/complexes/:id/history` | 적재 |
| s.kapt_cost | 표 | 890,544 | 389 |  | `/api/newbuilds`, `/api/newbuilds/:code`, `/api/complexes/:id` | 적재 |
| s.arch_permit | 표 | 620,853 | 361 |  | `/api/complexes/:id`, `/api/complexes/:id/history` | 적재 |
| s.lawd_boundary | 표 | 5,067 | 356 | ✔ | `/api/complexes`, `/api/suggest`, `/api/lawds`, `/api/lawds/:lawd/geo` 외 5 | 적재 |
| s.bld_closed_expos_area | 표 | 1,209,961 | 292 |  | `/api/closed/site/:key` | 적재 |
| s.region_link | 표 | 1,178,768 | 262 |  | `/api/complexes`, `/api/suggest` | 적재 |
| s.arch_permit_dong | 표 | 585,586 | 252 |  | `/api/complexes/:id` | 적재 |
| s.hira_inst | 표 | 105,776 | 248 | ✔ | `/api/complexes/:id/points`, `/api/complexes/:id/hira` | 적재 |
| g.closed_site | 표 | 329,587 | 224 |  | `/api/complexes`, `/api/suggest`, `/api/ask`, `/api/complexes/:id/pharmacy` 외 5 | 적재 |
| s.bld_closed_title | 표 | 355,846 | 209 |  | `/api/closed/site/:key`, `/api/complexes/:id/closed` | 적재 |
| g.complex_station | 표 | 3,318,984 | 155 |  | `/api/adms/:cd/geo`, `/api/my/notice/read`, `/api/ask` | 적재 |
| g.bld_vlrat | 표 | 626,600 | 128 |  | `/api/complexes/:id` | 적재 |
| s.land_use_zone | 표 | 8,081 | 127 | ✔ | `/api/health`, `/api/zones` | 적재 |
| s.bld_closed_expos | 표 | 422,455 | 104 |  | `/api/closed/site/:key` | 적재 |
| g.complex_school_near | 표 | 1,559,060 | 80 |  | `/api/my/notice/read`, `/api/ask` | 적재 |
| s.land_move_done | 표 | 1,051,506 | 70 |  | `/api/applyhome/:house/where`, `/api/closed/site/:key` | 적재 |
| g.complex_pnu | 표 | 659,381 | 65 |  | `/api/health`, `/api/complexes`, `/api/suggest`, `/api/applyhome` 외 9 | 적재 |
| g.complex_area_trade | 표 | 638,876 | 64 |  | `/api/my/notice/read`, `/api/ask` | 적재 |
| s.school_zone | 표 | 7,132 | 62 | ✔ | `/api/health`, `/api/redev/:sn/detail`, `/api/school/:sid`, `/api/schoolzone/:kind/:id` 외 1 | 적재 |
| s.bld_atch_jibun | 표 | 190,811 | 62 |  | `/api/health`, `/api/complexes` | 적재 |
| s.bus_stop | 표 | 227,065 | 56 | ✔ | `/api/health` | 적재 |
| g.complex_bld | 표 | 672,883 | 52 |  | `/api/complexes`, `/api/complexes/:id/usage`, `/api/complexes/:id` | 적재 |
| s.hira_open | 표 | 104,256 | 51 |  | `/api/complexes/:id/points`, `/api/complexes/:id/hira` | 적재 |
| g.bld_violation | 표 | 495,487 | 49 |  | `/api/complexes/:id` | 적재 |
| s.school_group | 표 | 1,760 | 46 | ✔ | `/api/school/:sid`, `/api/schoolzone/:kind/:id`, `/api/complexes/:id` | 적재 |
| s.redev_zone | 표 | 5,552 | 43 | ✔ | `/api/health`, `/api/complexes`, `/api/suggest`, `/api/my/notice/read` 외 5 | 적재 |
| s.academy | 표 | 27,356 | 34 | ✔ | `/api/health`, `/api/suggest`, `/api/complexes/:id` | 적재 |
| s.bld_closed_flr | 표 | 157,448 | 34 |  | `/api/closed/site/:key` | 적재 |
| g.complex_zone_hit | 표 | 590,981 | 32 |  | `/api/my/notice/read`, `/api/ask` | 적재 |
| g.change_log | 표 | 89,846 | 29 |  | `/api/complexes/:id/history` | 적재 |
| g.complex_trade_max | 표 | 191,481 | 26 |  | `/api/my/notice/read`, `/api/ask`, `/api/redev/:sn/detail`, `/c/:id` | 적재 |
| g.complex_redev_hit | 표 | 300,231 | 25 |  | `/api/my/notice/read`, `/api/ask`, `/api/complexes/:id/history` | 적재 |
| s.childcare | 표 | 4,259 | 21 | ✔ | `/api/complexes/:id/usage`, `/api/childcare/:st`, `/api/complexes/:id/childcare` | 적재 |
| g.complex_area | 표 | 503,468 | 21 |  | `/api/my/notice/read`, `/api/ask` | 적재 |
| s.bus_route_station | 표 | 88,800 | 18 |  | `/api/health`, `/api/complexes/:id/points`, `/api/complexes/:id` | 적재 |
| o.req_log | 표 | 28,504 | 16 |  | `/api/usage`, `/api/admin/ips` | 사용자 |
| s.bld_recap_title | 표 | 21,822 | 16 |  | `/api/complexes/:id/usage`, `/api/complexes/:id` | 적재 |
| s.kinder_info | 표 | 9,064 | 15 |  | `/api/complexes/:id/usage`, `/api/kinder/:code` | 적재 |
| s.schoolinfo_stat | 표 | 4,195 | 11 |  | `/api/school/:sid`, `/api/complexes/:id` | 적재 |
| s.schoolinfo_move | 표 | 4,210 | 9 |  | `/api/school/:sid` | 적재 |
| s.applyhome_cmpet | 표 | 9,416 | 9 |  | `/api/applyhome` | 적재 |
| s.mois_pharmacy | 표 | 23,395 | 8 | ✔ | `/api/complexes/:id/pharmacy` | 적재 |
| s.ned_aphus_done | 표 | 121,942 | 8 |  | `/api/closed/site/:key` | 적재 |
| s.land_use_done | 표 | 116,056 | 8 |  | `/api/complexes/:id/landuse` | 적재 |
| g.complex_alias | 표 | 75,274 | 7 |  | `/api/complexes`, `/api/suggest`, `/api/ask`, `/api/redev/:sn/detail` 외 3 | 적재 |
| s.bld_closed_detail_done | 표 | 73,293 | 6 |  | `/api/closed/site/:key` | 적재 |
| s.applyhome_pblanc | 표 | 994 | 6 |  | `/api/complexes`, `/api/suggest`, `/api/redev/:sn/detail`, `/api/applyhome` 외 4 | 적재 |
| m.lawd_code | 표 | 20,561 | 6 |  | `/api/config`, `/api/coverage`, `/api/complexes`, `/api/suggest` 외 10 | 메타 |
| s.school | 표 | 12,004 | 5 | ✔ | `/api/health`, `/api/suggest`, `/api/school/:sid`, `/api/schoolzone/:kind/:id` 외 1 | 적재 |
| s.schoolinfo | 표 | 1,416 | 5 |  | `/api/school/:sid`, `/api/complexes/:id` | 적재 |
| s.school_zone_link | 표 | 18,051 | 4 |  | `/api/school/:sid`, `/api/schoolzone/:kind/:id`, `/api/complexes/:id` | 적재 |
| s.applyhome_mdl | 표 | 4,868 | 4 |  | `/api/applyhome` | 적재 |
| s.kapt_complex | 표 | 4,101 | 4 |  | `/api/complexes`, `/api/suggest`, `/api/newbuilds`, `/api/newbuilds/:code` 외 2 | 적재 |
| s.seoul_redev_plan | 표 | 1,937 | 4 |  | `/api/redev/:sn/detail`, `/api/complexes/:id`, `/api/complexes/:id/history` | 적재 |
| g.complex_kapt | 표 | 3,307 | 4 |  | `/api/complexes`, `/api/suggest`, `/api/ask`, `/api/complexes/:id` | 적재 |
| s.applyhome_score | 표 | 3,050 | 3 |  | `/api/applyhome` | 적재 |
| s.adm_boundary | 표 | 457 | 2 | ✔ | `/api/suggest`, `/api/adms/:cd/geo`, `/api/lawds`, `/api/adms` 외 5 | 적재 |
| g.region_bdong | 표 | 28,656 | 2 |  | `/api/health`, `/api/my/notice/read`, `/api/ask` | 적재 |
| g.redev_plan_link | 표 | 1,614 | 1 |  | `/api/redev/:sn/detail`, `/api/complexes/:id`, `/api/complexes/:id/history` | 적재 |
| s.kindergarten | 표 | 824 | 1 | ✔ | `/api/health`, `/api/suggest`, `/api/complexes/:id/usage`, `/api/kinder/:code` | 적재 |
| g.school_link | 표 | 1,339 | 0 |  | `/api/redev/:sn/detail`, `/api/school/:sid`, `/api/schoolzone/:kind/:id`, `/api/complexes/:id` | 적재 |
| s.subway_station | 표 | 1,098 | 0 | ✔ | `/api/health`, `/api/suggest`, `/api/ask` | 적재 |
| g.applyhome_link | 표 | 564 | 0 |  | `/api/complexes`, `/api/suggest`, `/api/redev/:sn/detail`, `/api/applyhome` 외 3 | 적재 |
| g.region_hdong | 표 | 5,133 | 0 |  | `/api/health`, `/api/complexes`, `/api/suggest` | 적재 |
| o.ask_log | 표 | 941 | 0 |  | `/api/my`, `/api/my/notice/read`, `/api/ask` | 사용자 |
| g.region_hdong_change | 표 | 2,636 | 0 |  | `/api/complexes`, `/api/suggest` | 적재 |
| s.bus_route | 표 | 1,353 | 0 |  | `/api/health`, `/api/complexes/:id/points`, `/api/complexes/:id` | 적재 |
| s.road_addr | 표 | 3 | 0 |  | `/api/health` | 적재 |
| m.coverage | 표 | 2,129 | 0 |  | `/api/config`, `/api/coverage`, `/api/health`, `/api/complexes` 외 7 | 메타 |
| g.ask_attr_meta | 표 | 6 | 0 |  | `/api/ask` | 적재 |
| m.app_user | 표 | 1 | 0 |  | `/api/login`, `/api/my` | 사용자 |
| o.fav_complex | 표 | 1 | 0 |  | `/api/my`, `/api/my/badge`, `/api/my/fav/:id`, `/api/my/fav/:id` | 사용자 |
| o.inquiry | 표 | 3 | 0 |  | `/api/inquiry`, `/api/inquiries`, `/api/inquiry/:id/answer`, `/api/my` | 사용자 |
| o.notice | 표 | 3 | 0 |  | `/api/inquiry/:id/answer`, `/api/my`, `/api/my/badge`, `/api/my/notice/read` | 사용자 |
| o.usage_hour | 표 | 156 | 0 |  | `/api/usage` | 사용자 |
| o.usage_owner_ip | 표 | 11 | 0 |  | `/api/usage`, `/api/admin/ips`, `/api/me`, `/api/ask` | 사용자 |
| s.region_link_snap | 표 | 55 | 0 |  | `/api/complexes`, `/api/suggest` | 적재 |
| s.vworld_zone_done | 표 | 330 | 0 |  | `/api/complexes/:id/landuse-shape` | 적재 |
| g.fn_complex_silv ← g.complex, g.complex_pnu, g.applyhome_link, s.applyhome_pblanc, s.kapt_complex, g.complex_kapt, s.rtms_trade | 함수 |  |  |  | `/api/applyhome`, `/api/complexes/:id`, `/api/complexes/:id/geo`, `/api/complexes/:id/history` | 적재 |
| g.usp_refresh_applyhome_link | 프로시저 |  |  |  | `/api/lawds/:lawd/geo` | 적재 |
| g.v_bld_vlrat ← s.bld_jijigu, s.bld_title, s.bld_recap_title, m.jijigu_level | 뷰 |  |  |  | `/api/complexes/:id` | 적재 |
| g.v_complex_academy ← s.academy, g.complex (공간) | 뷰 |  |  |  | `/api/complexes/:id/points`, `/api/complexes/:id` | 적재 |
| g.v_complex_bus ← s.bus_stop, g.complex (공간) | 뷰 |  |  |  | `/api/complexes/:id/points`, `/api/complexes/:id` | 적재 |
| g.v_complex_childcare ← g.complex, s.childcare (공간) | 뷰 |  |  |  | `/api/complexes/:id/points` | 적재 |
| g.v_complex_floor ← s.bld_title, s.bld_flr_outline, g.complex_bld | 뷰 |  |  |  | `/api/complexes/:id` | 적재 |
| g.v_complex_ho ← g.complex_bld, s.bld_title, s.bld_expos, s.bld_basis_outline | 뷰 |  |  |  | `/api/complexes/:id/usage`, `/api/complexes/:id`, `/api/ho/:pk` | 적재 |
| g.v_complex_ho_price ← g.v_complex_ho, g.v_ho_hsprc | 뷰 |  |  |  | `/api/complexes/:id`, `/api/ho/:pk` | 적재 |
| g.v_complex_kinder ← s.kindergarten, g.complex (공간) | 뷰 |  |  |  | `/api/complexes/:id/points`, `/api/complexes/:id` | 적재 |
| g.v_complex_map ← g.complex, m.fn_pnu_to_jibun, m.lawd_code | 뷰 |  |  |  | `/api/complexes`, `/api/redev/:sn/detail`, `/api/complexes/markers`, `/api/complexes/:id` 외 3 | 적재 |
| g.v_complex_permit ← g.complex, g.complex_pnu, s.arch_permit | 뷰 |  |  |  | `/api/complexes/:id` | 적재 |
| g.v_complex_poi ← g.complex, g.complex_pnu, s.semas_store (공간) | 뷰 |  |  |  | `/api/complexes/:id/poi-list`, `/api/complexes/:id/points`, `/api/complexes/:id` | 적재 |
| g.v_complex_redev ← s.redev_zone, s.cadastral_parcel, g.complex_pnu (공간) | 뷰 |  |  |  | `/api/redev`, `/api/redev/:sn/detail`, `/api/complexes/:id` | 적재 |
| g.v_complex_school ← s.school, g.complex (공간) | 뷰 |  |  |  | `/api/complexes/:id/points`, `/api/complexes/:id` | 적재 |
| g.v_complex_subway ← s.subway_station, g.complex (공간) | 뷰 |  |  |  | `/api/complexes/:id/points`, `/api/complexes/:id` | 적재 |
| g.v_complex_zone ← g.complex_pnu, s.cadastral_parcel, s.land_use_zone (공간) | 뷰 |  |  |  | `/api/complexes/:id` | 적재 |
| g.v_ho_hsprc ← s.bld_hsprc, g.ned_ho_link, s.ned_aphus_price | 뷰 |  |  |  | `/api/complexes/:id`, `/api/ho/:pk` | 적재 |
| g.v_kapt_cost_item ← m.kapt_cost_item, s.kapt_cost | 뷰 |  |  |  | `/api/newbuilds`, `/api/newbuilds/:code`, `/api/complexes/:id` | 적재 |
| g.v_kapt_cost_latest ← s.kapt_cost, s.kapt_complex, m.lawd_code, g.v_kapt_cost_cmn, g.v_kapt_cost_rep | 뷰 |  |  |  | `/api/newbuilds`, `/api/newbuilds/:code`, `/api/complexes/:id` | 적재 |
| g.v_lawd_map ← g.complex, s.rtms_trade, s.lawd_boundary | 뷰 |  |  |  | `/api/complexes`, `/api/lawds`, `/api/lawds/:lawd/geo` | 적재 |
| g.v_newbuild ← g.complex_pnu, s.cadastral_parcel, s.arch_permit, s.rtms_trade, s.kapt_complex, m.lawd_code, g.complex_kapt, m.v_lawd_scope, g.v_pnu_bld | 뷰 |  |  |  | `/api/complexes`, `/api/suggest`, `/api/ask`, `/api/newbuilds` 외 1 | 적재 |
| g.v_newbuild_trade ← s.rtms_trade | 뷰 |  |  |  | `/api/newbuilds/:code`, `/api/complexes/:id` | 적재 |
| g.v_trade_offsite ← s.kapt_complex, m.lawd_code, g.complex, g.v_newbuild_gap | 뷰 |  |  |  | `/api/health`, `/api/complexes/:id` | 적재 |
| m.recordset | 없음(지운 표 · 주석/옛코드) |  |  |  | `/api/ho/:pk` | 메타 |
| m.v_lawd_scope ← m.ingest_run, m.api_source | 뷰 |  |  |  | `/api/complexes/:id` | 메타 |
| m.v_load_page_gap ← m.load_page | 뷰 |  |  |  | `/api/complexes/:id` | 메타 |
| m.v_load_progress ← m.v_load_plan | 뷰 |  |  |  | `/api/complexes/:id` | 메타 |
| s.registry_property | 없음(지운 표 · 주석/옛코드) |  |  |  | `/api/health` | 적재 |

## 4. 단지 상세 `/api/complexes/:id` — 쿼리 34개

상세 앞머리(합쳐짐 확인 · `g.v_complex_map` 머리줄 · 실거래이름)와 뒤의 관리비 `costOf()`(`g.v_kapt_cost_latest` · `g.v_kapt_cost_item`)까지 합치면 37번. **입력은 전부 `@id` 하나** — 같은 데이터면 단지마다 답이 정해진다 = 발행 때 미리 만들 수 있다.

| 쿼리 | 줄 | 하는 일 | 읽는 것 | 반경(m) | 공간 | 단지별 미리 계산 |
|---|---|---|---|---|---|---|
| _q_dongs | 5751 | 동 목록 + 위반건축물 | g.bld_violation, g.complex_bld, s.bld_basis_outline, s.bld_recap_title, s.bld_title |  |  | ✔ |
| _q_spec | 5778 | 제원(총괄표제부 우선 · 동 합) | g.complex_bld, s.bld_basis_outline, s.bld_recap_title, s.bld_title |  |  | ✔ |
| _q_kapt | 5892 | K-apt 이음 | g.complex_kapt |  |  | ✔ |
| _q_scope | 5909 | 축별 적재 범위(법정동 단위 판정) → 범위표로 | g.complex, m.v_lawd_scope, m.v_load_progress, s.arch_permit, s.bld_expos, s.bld_flr_outline, s.bld_hsprc, s.bld_title, s.building_footprint, s.cadastral_parcel, s.kapt_complex, s.kapt_cost |  |  | 범위표(시군구·법정동) |
| _q_floors | 5950 | 층별 개요 | g.v_complex_floor |  |  | ✔ |
| _q_hos | 5960 | 호 목록 + 공시가격(최신) | g.v_complex_ho, g.v_complex_ho_price, s.bld_expos_pubuse_area |  |  | ✔ |
| _q_hoN | 6015 | 호 수 | g.v_complex_ho |  |  | ✔ |
| _q_exar | 6047 | 전유/공용 면적 | g.v_complex_ho, s.bld_expos_pubuse_area |  |  | ✔ |
| _q_permits | 6069 | 건축인허가 | g.v_complex_permit, s.arch_permit |  |  | ✔ |
| _q_permitDongs | 6109 | 인허가 동별 | g.v_complex_permit, s.arch_permit, s.arch_permit_dong |  |  | ✔ |
| _q_parcels | 6135 | 필지 + 공시지가 | g.complex_pnu, g.v_complex_zone, s.cadastral_parcel |  |  | ✔ |
| _q_zones | 6147 | 용도지역 걸침(공간 교차 — 뷰 안) | g.v_complex_zone |  |  | ✔ |
| _q_redev | 6160 | 정비구역 걸침 + 서울 정비계획 | g.redev_plan_link, g.v_complex_redev, s.seoul_redev_plan |  | ✔ | ✔ |
| _q_poi | 6178 | 상권 점포(반경) | g.v_complex_poi | 300, 500 |  | ✔ |
| _q_poiSum | 6191 | 상권 요약 500m | g.v_complex_poi | 500 |  | ✔ |
| _q_poiBrand | 6208 | 브랜드 점포 500m | g.v_complex_poi | 500 |  | ✔ |
| _q_poiLife | 6232 | 생활 업종 500m | g.v_complex_poi | 500 |  | ✔ |
| _q_subways | 6270 | 지하철역(거리 — 뷰 안) | g.v_complex_subway |  |  | ✔ |
| _q_busStops | 6286 | 버스 정류장 300m | g.v_complex_bus, s.bus_route_station | 300 |  | ✔ |
| _q_busList | 6328 | 정류장 목록 | g.v_complex_bus |  |  | ✔ |
| _q_busRoutes | 6337 | 노선 700m | g.complex, g.v_complex_bus, s.bus_route, s.bus_route_station | 700 | ✔ | ✔ |
| _q_schoolZone | 6381 | 학구도(공간) | g.complex, g.school_link, s.school, s.school_group, s.school_zone, s.school_zone_link, s.schoolinfo, s.schoolinfo_stat |  | ✔ | ✔ |
| _q_schools | 6428 | 학교 500m/1km + 학교알리미 | g.complex, g.school_link, g.v_complex_school, s.schoolinfo, s.schoolinfo_stat | 1000, 500 |  | ✔ |
| _q_kinders | 6488 | 유치원(거리 — 뷰 안) | g.v_complex_academy, g.v_complex_kinder, s.academy |  |  | ✔ |
| _q_aca | 6508 | 학원 500m | g.v_complex_academy, s.academy | 500 |  | ✔ |
| _q_szScope | 6530 | 학구도 받았나 → 범위표로 | g.bld_vlrat, g.complex, g.v_bld_vlrat, s.school_zone |  |  | 범위표(시군구·법정동) |
| _q_vlrat | 6553 | 용적률 분위 | g.bld_vlrat, g.complex_bld |  |  | ✔ |
| _q_kinderN | 6572 | 유치원 받았나 → 범위표로 | m.v_load_page_gap |  |  | 범위표(시군구·법정동) |
| _q_prcScope | 6586 | 공시가격 다 받았나(법정동) → 범위표로 | g.complex, g.v_complex_ho_price, m.v_load_page_gap, s.bld_hsprc |  |  | 범위표(시군구·법정동) |
| _q_hoPrc | 6614 | 호 공시가격 18년 추이 | g.v_complex_ho, g.v_complex_ho_price, g.v_ho_hsprc |  | ✔ | ✔ |
| _q_trades | 6684 | 실거래 종류별 최근 목록 | g.fn_complex_silv, s.rtms_trade | 120 |  | ✔ |
| _q_jeonse | 6744 | 전세가율 | s.rtms_trade |  |  | ✔ |
| _q_tradeStats | 6776 | 평형별 거래 요약 | g.v_trade_offsite, s.rtms_trade |  |  | ✔ |
| _q_off | 6945 | 단지 밖 지번으로 신고된 거래(추정) | g.v_newbuild_trade, g.v_trade_offsite, s.bld_expos, s.kapt_complex |  |  | ✔ |

**느린 쪽(2026-10-24 20:10 실측, 적재 중)**: hos 2.3초 · off 1.5초 · exar 1.4초 · busRoutes 1.2초 · busStops 1.2초 — 다 바닥 큰 표(전유공용면적 1,495만 · 실거래 1,202만)를 매번 다시 모은다.

## 5. 적재 범위 · 메타가 화면에 나가는 곳

`m.coverage`(339 · 자료×시군구) · `m.v_load_page_gap` · `m.v_load_progress` · `m.v_lawd_scope` · `m.v_target_sgg` — 화면이 "없음" 과 "안 받음" 을 가르는 데 쓴다. 서비스DB 에서는 **발행할 때 범위표 하나**(자료 × 시군구 × 법정동: 받음/일부/안 받음 · 기준일)로 굳혀 넘긴다.

## 6. T-SQL 전용 문법 (server.js 전체)

| 문법 | 곳 | PostgreSQL 에서 |
|---|---|---|
| CROSS/OUTER APPLY | 29 | LATERAL JOIN |
| TOP (n) | 128 | LIMIT |
| STRING_AGG | 8 | STRING_AGG(… ORDER BY …) 문법 다름 |
| geography/geometry 메서드(.STxxx) | 52 | PostGIS ST_* 함수(인자 순서 · geography 캐스팅) |
| geography::/geometry:: 생성 | 19 | ST_GeomFromText / ST_SetSRID(ST_MakePoint…) |
| ISNULL | 82 | COALESCE |
| TRY_CAST/TRY_CONVERT | 9 | 직접 함수(정규식 검사) |
| CONVERT( | 12 | CAST / to_char |
| DATEADD/DATEDIFF | 17 | interval 연산 |
| LEN( | 9 | length |
| #임시표 | 17종 · 79곳 | CTE 또는 TEMP TABLE |
| DECLARE @ | 29 | CTE 또는 함수 인자 |
| READ UNCOMMITTED | 84 | 없앰(MVCC — 읽기가 쓰기를 안 기다림) |
| OPTION (RECOMPILE 등) | 14 | 없앰 |
| WITH (NOLOCK/FORCESEEK…) | 6 | 없앰 |
| N'…' 유니코드 리터럴 | 210 | N 접두 없앰 |
| sql.Int/NVarChar 등 드라이버 형 | 309 | pg 드라이버 $1 자리표시(형 지정 없음) |
| .query( 호출 | 177 | (호출 수 — 전부 손봄) |
| gold.fn_* / meta.fn_* 함수 | 6 | SQL 함수로 다시 |
| SCOPE_IDENTITY/OUTPUT | 1 | RETURNING |
| MERGE | 2 | INSERT … ON CONFLICT |
| ROW_NUMBER() OVER | 20 | 같음 |
| PERCENTILE_CONT | 2 | 같음(WITHIN GROUP) |
| 뷰 · 함수(뷰 안 SQL) | 화면이 읽는 뷰 25개 + 함수 g.fn_complex_silv · m.fn_pnu_to_jibun | 다시 만듦(공간 뷰 9개) |

## 7. 서비스DB 표 초안 — 화면 단위로 미리 계산

원칙: **발행기가 적재DB 에서 계산해 통째로 넣고, 검사 통과하면 바꿔 끼운다.** 서비스 서버는 키(단지코드 · bbox · 검색어)로 읽기만 한다.
크기는 지금 바닥 표에서 '지금 줄(is_current) · 화면이 쓰는 칸만' 으로 줄인 추정.

| 표 | 키 | 칼럼(요지) | 원천(적재DB) | 크기 추정 | 갱신 |
|---|---|---|---|---|---|
| svc.complex_card | complex_id | 이름 · 검색용 이름(띄어쓰기 뺀) · 실거래이름 · 주소(지번/도로명) · 좌표 · bbox · 세대 · 동 · 사용승인 · 대표 평형 · 최근 매매 · 합쳐짐(merged_into) | g.complex · g.v_complex_map · g.complex_alias · g.complex_trade_max · s.bld_atch_jibun(부속지번 검색) | 57만 줄 · 0.2 GB | 매일 발행 |
| svc.complex_detail | complex_id | 섹션별 JSON: 제원 · 동(+위반) · 층 · K-apt · 인허가(+동) · 필지 · 용도지역 · 정비 · 용적률 분위 · 관리비(최신+항목) · 범위 표시 | 상세 쿼리 34개 중 아래 표로 안 뺀 것 전부 + costOf | 57만 줄 · 2~3 GB | 매일 발행 |
| svc.complex_near | complex_id | 학교(500m/1km + 학교알리미) · 학구도 · 유치원 · 어린이집 · 학원 500m · 지하철 · 버스(300m 정류장 · 700m 노선) · 상권(300/500m 요약 · 브랜드 · 생활) · 병원 · 약국 — JSON | g.v_complex_school/subway/bus/kinder/academy/childcare/poi · s.hira_* · s.mois_pharmacy | 57만 줄 · 1.5~2 GB | 주변 자료 바뀔 때(주 1회) |
| svc.complex_ho | complex_id, 동, 호 | 층 · 전용/공용 면적 · 용도 · 최신 공시가격 | g.v_complex_ho · s.bld_expos_pubuse_area · g.v_complex_ho_price | 420만 줄 · 0.6 GB | 매일 |
| svc.ho_price | 호 키(mgm_bldrgst_pk) | 연도별 공시가격 배열(18년) | g.v_ho_hsprc(s.bld_hsprc · s.ned_aphus_price) | 420만 줄 · 1~1.5 GB | 연 1회 + 보정 |
| svc.trade | complex_id, 종류, 날짜 | 금액 · 층 · 전용 · 해제 · 거래유형 · 등기일 (단지에 붙은 것만) | s.rtms_trade(match_complex_id) · g.fn_complex_silv(분양권) | 약 700만 줄 · 1.5~2 GB | 매일 |
| svc.trade_stat | complex_id, 평형 | 평형별 요약 · 전세가율 · 3년 최고 | g.complex_area_trade · _q_tradeStats · _q_jeonse | 64만 줄 · 0.1 GB | 매일 |
| svc.trade_offsite | complex_id | 단지 밖 지번 신고 거래(추정) | g.v_trade_offsite · g.v_newbuild_trade | 작음 | 매일 |
| svc.history_event | complex_id, 날짜 | 이 땅의 역사 줄(옛 대장 · 옛 거래 · 정비 · 인허가 · 청약 · 분양권 · 용도지역 바뀜 · 토지이동) | g.closed_site · g.change_log · s.land_move_hist · … | 수백만 줄 · 0.3 GB | 매일 |
| svc.map_parcel | pnu | 폴리곤(geometry) · 공시지가 · 지목 · complex_id | s.cadastral_parcel · g.complex_pnu | 100만 줄 · 1.2 GB | 매월 |
| svc.map_building | 건물관리번호 | 폴리곤 · 층 · complex_id | s.building_footprint | 65만 줄 · 0.8 GB | 매월 |
| svc.map_layer | 레이어, 키 | 폴리곤: 용도지역 · 정비구역 · 학구도 · 법정동/행정동 경계 · 토지이용(landuse-shape) | s.land_use_zone · s.redev_zone · s.school_zone · s.lawd_boundary · s.adm_boundary · s.vworld_zone · s.land_use_plan | 1.5 GB | 매월 |
| svc.poi | 종류, id | 점: 학교 · 역 · 정류장 · 유치원 · 어린이집 · 학원 · 병원 · 약국 · 상가 (+상세 JSON) | s.school* · s.subway_station · s.bus_* · s.kindergarten · s.childcare · s.academy · s.hira_* · s.mois_pharmacy · s.semas_store | 110만 줄 · 0.4 GB | 주 1회 |
| svc.newbuild · svc.applyhome · svc.closed_site | 각 키 | 대장 없는 신축 · 청약 공고(+경쟁률 · 모델 · 가점) · 옛 대장 자리(+NED 가격) | g.v_newbuild · s.applyhome_* · g.applyhome_link · g.closed_site · s.bld_closed_* | 0.5 GB | 매일 |
| svc.region | 코드 | 시도 · 시군구 · 법정동 · 행정동(현행/옛 · 바뀐 이력) · 검색용 이름 | g.region_bdong/hdong(_change) · m.lawd_code · s.region_link(_snap) | 0.3 GB | 분기 |
| svc.coverage | 자료, 시군구(, 법정동) | 받음/일부/안 받음 · 기준일 · 건수 — "없다" vs "안 받았다" | m.coverage · m.v_load_page_gap · m.v_lawd_scope · m.v_load_progress | 작음 | 발행마다 |
| svc.stats | 키 | 홈 수치(단지 · 필지 · 건물 · 실거래 · 주변 자료 수) | /api/health 의 COUNT 29개 | 1줄 | 발행마다 |
| app.* (쓰기 영역) | — | 사용자 · 관심 단지 · 문의 · 공지 · AI 질문 기록 · 접속 기록 · 시간별 이용 | 지금 o.* · m.app_user | 작음 | **서비스가 씀 — 발행이 건드리지 않음** |

**합계 추정: 10~15 GB** (지금 화면이 읽는 바닥 표 합 57.2 GB → 큰 것: 공시가격 14.8 · 실거래 9.9 · 전유공용면적 8.0 · 토지특성 5.2(홈 수치에만 씀 → 0) · 기본개요 4.2 · NED 가격 3.3 GB 가 '필요 칸 · 지금 줄' 로 줄어듦).

빠지는 것: bronze 원문 · SCD 옛 버전 · 적재 진행표(meta.load_page 등) · 건축HUB 원본 버전 · 변경 로그 원천(silver.land_char) · 진단 API 16개.

## 8. PostgreSQL + PostGIS 로 옮길 때 손볼 곳

| 길 | 손볼 곳 |
|---|---|
| **A. 서버 SQL 을 그대로 옮김** | `.query()` 177곳 전부 · TOP 128 · ISNULL 82 · APPLY 29 · 공간 메서드 52 + 생성 19 · #임시표 17종(79곳) · DECLARE 29 · 드라이버 형 지정 309 · N'' 210 · READ UNCOMMITTED 84(지움) · 뷰 34 + 함수 2 다시 만들기(공간 뷰 10) |
| **B. 7장대로 미리 계산 표로 바꾼 뒤 옮김(권장)** | 복잡한 SQL(공간 · APPLY · 임시표 · 뷰)은 **발행기(적재DB · T-SQL 그대로)** 로 간다. 서비스 쪽 쿼리는 키 조회 · bbox 조회(&&) · 검색(pg_trgm) 위주 **20~30개**로 줄어 문법 차이가 거의 남지 않는다 |

- 공간: 지금 지도 길 대부분은 `bbox_minx/miny/maxx/maxy` 칸 비교(공간 색인 아님). PostGIS 면 GiST 색인 + `&&` 로 바꾸는 게 자연스럽다.
- 검색: 지금 `LIKE '%…%'` (색인 못 탐) — PostgreSQL `pg_trgm` GIN 색인이면 부분 일치도 색인을 탄다(검색 느림의 근본 해결 후보).
- 라이선스 참고: 지금 DB 는 SQL Server **Developer**(개발·시험용 — 공개 서비스용 아님). Express 2025 는 무료 운영 가능하나 DB 50 GB · 버퍼 1.4 GB · 4코어 제한.
