#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Teomoony 적재기 - 공공데이터포털 -> MSSQL

이 스크립트는 반드시 형님 PC 에서 실행해야 합니다.
(클라우드 작업환경은 egress 허용목록 때문에 data.go.kr 로 나가지 못합니다)

----------------------------------------------------------------
사용 순서
----------------------------------------------------------------
  1) probe  - 먼저 이걸 돌립니다. 실제 응답을 그대로 떠서
              필드명/건수/결과코드를 보여주고 raw 파일로 저장합니다.
              매핑을 확정하기 전에 실물을 보는 단계입니다.

      python teomoony_ingest.py probe --op getBrTitleInfo --sigungu 11110 --bjdong 10100

  2) load   - probe 로 확인한 뒤 실제 적재합니다.
              bronze(원본 보존) -> silver(정규화, SCD2) 순으로 들어갑니다.

      python teomoony_ingest.py load --op getBrTitleInfo --sigungu 11110

  3) build  - 단지코드 발급 + 4축 매핑 구성

      python teomoony_ingest.py build --sigungu 11110

----------------------------------------------------------------
설계 원칙
----------------------------------------------------------------
  * 원본을 버리지 않는다. 공공 API 는 필드가 예고 없이 늘어난다.
    파싱 실패해도 bronze.api_payload 에 원문이 남아 재처리가 가능하다.
  * row_hash 가 같으면 쓰지 않는다. 무의미한 이력 버전 폭증 방지.
  * PNU 는 DB 함수(meta.fn_make_pnu)로만 만든다. 파이썬에서 문자열
    조립하면 platGbCd 0/1/2 -> PNU 1/2 매핑 실수가 반드시 난다.
"""

import argparse
import hashlib
import progress
import json
import os
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime
from urllib.parse import urlencode

import requests

# ---------------- DB 드라이버 (pymssql 우선, 없으면 pyodbc) ----------------
_DRIVER = None
try:
    import pymssql  # pip install pymssql  (별도 ODBC 드라이버 설치 불필요)
    _DRIVER = "pymssql"
except ImportError:
    try:
        import pyodbc  # ODBC Driver 18 for SQL Server 필요
        _DRIVER = "pyodbc"
    except ImportError:
        pass


# ============================================================
# 오퍼레이션 레지스트리
#   필드 매핑은 probe 결과를 보고 확정합니다.
#   아래는 건축물대장정보 서비스의 공개 스펙 기준 초안입니다.
# ============================================================
BLD_BASE = "https://apis.data.go.kr/1613000/BldRgstHubService"
# 건축인허가는 별도 서비스다. 같은 키를 쓰지만 활용신청이 따로 필요하다.
PMS_BASE = "https://apis.data.go.kr/1613000/ArchPmsHubService"

# ★ 아래 매핑은 종로구 청운동(11110/10100) 실데이터 전수로 검증됨 (2026-10-12)
#   기본개요 899 / 표제부 359 / 총괄표제부 13 / 부속지번 257
OPS = {
 "getBrBasisOulnInfo": dict(
   url=f"{BLD_BASE}/getBrBasisOulnInfo", domain="BLDRGST",
   target="silver.bld_basis_outline", keys=["mgm_bldrgst_pk"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk","mgmUpBldrgstPk":"mgm_up_bldrgst_pk",
        "bldgId":"bldg_id","regstrGbCd":"regstr_gb_cd","regstrGbCdNm":"regstr_gb_nm",
        "regstrKindCd":"regstr_kind_cd","regstrKindCdNm":"regstr_kind_nm",
        "sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd","platGbCd":"plat_gb_cd",
        "bun":"bun","ji":"ji","platPlc":"plat_plc","bylotCnt":"bylot_cnt",
        "splotNm":"splot_nm","block":"block","lot":"lot",
        "naRoadCd":"na_road_cd","naBjdongCd":"na_bjdong_cd","naUgrndCd":"na_ugrnd_cd",
        "naMainBun":"na_main_bun","naSubBun":"na_sub_bun","newPlatPlc":"new_plat_plc",
        "bldNm":"bld_nm","jiyukCd":"jiyuk_cd","jiyukCdNm":"jiyuk_nm",
        "jiguCd":"jigu_cd","jiguCdNm":"jigu_nm","guyukCd":"guyuk_cd","guyukCdNm":"guyuk_nm",
        "crtnDay":"crtn_day"}),

 "getBrTitleInfo": dict(
   url=f"{BLD_BASE}/getBrTitleInfo", domain="BLDRGST",
   target="silver.bld_title", keys=["mgm_bldrgst_pk"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk",
        "regstrGbCd":"regstr_gb_cd","regstrGbCdNm":"regstr_gb_nm",
        "regstrKindCd":"regstr_kind_cd","regstrKindCdNm":"regstr_kind_nm",
        "sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd","platGbCd":"plat_gb_cd",
        "bun":"bun","ji":"ji","platPlc":"plat_plc","bylotCnt":"bylot_cnt",
        "naRoadCd":"na_road_cd","naBjdongCd":"na_bjdong_cd","naUgrndCd":"na_ugrnd_cd",
        "naMainBun":"na_main_bun","naSubBun":"na_sub_bun","newPlatPlc":"new_plat_plc",
        "bldNm":"bld_nm","dongNm":"dong_nm","splotNm":"splot_nm","block":"block","lot":"lot",
        "mainAtchGbCd":"main_atch_gb_cd","mainAtchGbCdNm":"main_atch_gb_nm",
        "platArea":"plat_area","archArea":"arch_area","bcRat":"bc_rat","totArea":"tot_area",
        "vlRatEstmTotArea":"vl_rat_estm_tot_area","vlRat":"vl_rat",
        "totDongTotArea":"tot_dong_tot_area",
        "strctCd":"strct_cd","strctCdNm":"strct_nm","etcStrct":"etc_strct",
        "mainPurpsCd":"main_purps_cd","mainPurpsCdNm":"main_purps_nm","etcPurps":"etc_purps",
        "roofCd":"roof_cd","roofCdNm":"roof_nm","etcRoof":"etc_roof",
        "hhldCnt":"hhld_cnt","fmlyCnt":"fmly_cnt","hoCnt":"ho_cnt","heit":"heit",
        "grndFlrCnt":"grnd_flr_cnt","ugrndFlrCnt":"ugrnd_flr_cnt",
        "rideUseElvtCnt":"ride_use_elvt_cnt","emgenUseElvtCnt":"emgen_use_elvt_cnt",
        "atchBldCnt":"atch_bld_cnt","atchBldArea":"atch_bld_area",
        "indrMechUtcnt":"indr_mech_utcnt","indrMechArea":"indr_mech_area",
        "oudrMechUtcnt":"oudr_mech_utcnt","oudrMechArea":"oudr_mech_area",
        "indrAutoUtcnt":"indr_auto_utcnt","indrAutoArea":"indr_auto_area",
        "oudrAutoUtcnt":"oudr_auto_utcnt","oudrAutoArea":"oudr_auto_area",
        "pmsDay":"pms_day","stcnsDay":"stcns_day","useAprDay":"use_apr_day",
        "pmsnoYear":"pmsno_year","pmsnoKikCd":"pmsno_kik_cd","pmsnoKikCdNm":"pmsno_kik_nm",
        "pmsnoGbCd":"pmsno_gb_cd","pmsnoGbCdNm":"pmsno_gb_nm",
        "engrGrade":"engr_grade","engrRat":"engr_rat","engrEpi":"engr_epi",
        "gnBldGrade":"gn_bld_grade","gnBldCert":"gn_bld_cert",
        "itgBldGrade":"itg_bld_grade","itgBldCert":"itg_bld_cert",
        "rserthqkDsgnApplyYn":"rserthqk_dsgn_apply_yn","rserthqkAblty":"rserthqk_ablty",
        "crtnDay":"crtn_day"}),

 "getBrRecapTitleInfo": dict(
   url=f"{BLD_BASE}/getBrRecapTitleInfo", domain="BLDRGST",
   target="silver.bld_recap_title", keys=["mgm_bldrgst_pk"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk","sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd",
        "platGbCd":"plat_gb_cd","bun":"bun","ji":"ji","platPlc":"plat_plc",
        "newPlatPlc":"new_plat_plc","bldNm":"bld_nm",
        "regstrGbCd":"regstr_gb_cd","regstrGbCdNm":"regstr_gb_nm",
        "regstrKindCd":"regstr_kind_cd","regstrKindCdNm":"regstr_kind_nm",
        "newOldRegstrGbCd":"new_old_regstr_gb_cd","newOldRegstrGbCdNm":"new_old_regstr_gb_nm",
        "naRoadCd":"na_road_cd","naBjdongCd":"na_bjdong_cd","naUgrndCd":"na_ugrnd_cd",
        "naMainBun":"na_main_bun","naSubBun":"na_sub_bun",
        "splotNm":"splot_nm","block":"block","lot":"lot","bylotCnt":"bylot_cnt",
        "platArea":"plat_area","archArea":"arch_area","bcRat":"bc_rat","totArea":"tot_area",
        "vlRat":"vl_rat","vlRatEstmTotArea":"vl_rat_estm_tot_area",
        "mainPurpsCd":"main_purps_cd","mainPurpsCdNm":"main_purps_nm","etcPurps":"etc_purps",
        "mainBldCnt":"main_bld_cnt","atchBldCnt":"atch_bld_cnt","atchBldArea":"atch_bld_area",
        "hhldCnt":"hhld_cnt","fmlyCnt":"fmly_cnt","hoCnt":"ho_cnt","totPkngCnt":"tot_pkng_cnt",
        "indrMechUtcnt":"indr_mech_utcnt","indrMechArea":"indr_mech_area",
        "oudrMechUtcnt":"oudr_mech_utcnt","oudrMechArea":"oudr_mech_area",
        "indrAutoUtcnt":"indr_auto_utcnt","indrAutoArea":"indr_auto_area",
        "oudrAutoUtcnt":"oudr_auto_utcnt","oudrAutoArea":"oudr_auto_area",
        "engrGrade":"engr_grade","engrRat":"engr_rat","engrEpi":"engr_epi",
        "gnBldGrade":"gn_bld_grade","gnBldCert":"gn_bld_cert",
        "itgBldGrade":"itg_bld_grade","itgBldCert":"itg_bld_cert",
        "pmsnoYear":"pmsno_year","pmsnoKikCd":"pmsno_kik_cd","pmsnoKikCdNm":"pmsno_kik_nm",
        "pmsnoGbCd":"pmsno_gb_cd","pmsnoGbCdNm":"pmsno_gb_nm",
        "useAprDay":"use_apr_day","pmsDay":"pms_day","stcnsDay":"stcns_day",
        "crtnDay":"crtn_day"}),

 # ---- 주택가격(공시가격) (2026-10-17 추가) : 호 x 연도 ----
 # 2026-10-17 실측 (돈암동 636, totalCount 21,480 = 1,102호 x 약 20년).
 #  · mgmBldrgstPk 가 **전유부와 같은 호 단위 PK** 다 -> 코드로 붙는다
 #  · 키는 (호PK, 기준일). 같은 호가 2006~2026 로 ~20행 온다
 #  · API 에 연도 필터가 없다. 최신만 받을 수 없으므로 **전량 받고 뷰에서 고른다**
 #  · 지번 하나가 215페이지다. 끊기면 --from-page 로 이어 받을 것
 #
 # ★ 공시가격은 실거래가가 아니다(과세표준용, 실거래의 60~70%).
 #   단지 **간** 비교에 쓰지 않는다 — 27_hsprc.sql 머리말 참조.
 "getBrHsprcInfo": dict(
   url=f"{BLD_BASE}/getBrHsprcInfo", domain="BLDRGST",
   # ★ 키에 crtn_day 가 들어간다. 같은 호·같은 기준일에 **공시 회차가 둘**이다
   #   (결정공시 -> 조정공시). 빼면 둘이 서로를 밀어내며 이력이 끝없이 쌓인다.
   #   28_hsprc_fix.sql 머리말 참조.
   target="silver.bld_hsprc", keys=["mgm_bldrgst_pk","std_day","crtn_day"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk","stdDay":"std_day","hsprc":"hsprc",
        "sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd",
        "platGbCd":"plat_gb_cd","bun":"bun","ji":"ji",
        "platPlc":"plat_plc","bldNm":"bld_nm",
        "regstrGbCd":"regstr_gb_cd","regstrKindCd":"regstr_kind_cd",
        "crtnDay":"crtn_day"}),

 # ---- 전유부 (2026-10-16 추가) : 호 단위 ----
 # ★ 정책.md 4장이 기각한 것은 **전유공용면적**(getBrExposPubuseAreaInfo)이다.
 #   그 기각 사유는 "호당 전유 1행 + 공용 N행 -> 응답의 80%가 공용, 지번당 수천 건".
 #   **전유부는 호당 1행**이라 그 사유가 해당하지 않는다. 다른 축이다.
 #
 # 기본개요에 이미 전유부 PK 가 들어와 있다(돈암동 14,666건, regstr_kind_cd=4).
 # 뼈대는 있고 **호명칭·동명칭만 없다.** 그걸 이 축이 채운다.
 #
 # 2026-10-16 probe 로 확정 (돈암동 636, totalCount 1,102 = 1,074세대 + 상가 등).
 #  · 전 필드 **100% 채움**: dongNm · hoNm · flrGbCd · flrNo
 #  · `mgmUpBldrgstPk` 는 **응답에 없다.** 상위 PK 는 기본개요(kind=4)에 있고
 #    거기서 동 -> 단지까지 전수 연결된다(돈암동 14,666건 결손 0). 중복으로 안 받는다.
 #  · `flrNoNm` 도 없다(층별개요에는 있다). 기대 필드명으로 매핑하면 영영 NULL 이다.
 "getBrExposInfo": dict(
   url=f"{BLD_BASE}/getBrExposInfo", domain="BLDRGST",
   target="silver.bld_expos", keys=["mgm_bldrgst_pk"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk",
        "sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd",
        "platGbCd":"plat_gb_cd","bun":"bun","ji":"ji",
        "platPlc":"plat_plc","newPlatPlc":"new_plat_plc","bldNm":"bld_nm",
        "dongNm":"dong_nm","hoNm":"ho_nm",
        "flrGbCd":"flr_gb_cd","flrGbCdNm":"flr_gb_nm","flrNo":"flr_no",
        "regstrGbCd":"regstr_gb_cd","regstrGbCdNm":"regstr_gb_nm",
        "regstrKindCd":"regstr_kind_cd","regstrKindCdNm":"regstr_kind_nm",
        "naRoadCd":"na_road_cd","naBjdongCd":"na_bjdong_cd","naUgrndCd":"na_ugrnd_cd",
        "naMainBun":"na_main_bun","naSubBun":"na_sub_bun",
        "crtnDay":"crtn_day"}),

 # ---- 층별개요 (2026-10-16 추가) ----
 # 동 x 층 격자를 만드는 축. 각 층의 용도·구조·면적이 들어온다.
 # 호출 단위가 **동이 아니라 지번**이라 비용이 가볍다 (전유부처럼 호 단위가 아니다).
 #
 # 호는 여기 **없다.** ho_nm 을 가진 테이블은 silver.bld_expos_pubuse_area 뿐이고
 # 그건 적재하지 않기로 한 축이다(정책.md 4장). 층까지다.
 #
 # 2026-10-16 probe 로 확정 (돈암동 636, 305건).
 #  · 철자 함정: 응답은 **areaExctYn** 이다. `areaExclYn`(Excl) 로 쓰면 영영 NULL 이다
 #  · `dongNm` 이 응답에 있다 -> 동별 표제부와 조인하지 않고도 동을 안다
 #  · `mainAtchGbCd` 주/부속 구분이 있다 (지하주차장·교회가 부속건축물로 온다)
 #  · 자연키가 **유일하지 않다** -> collapse 로 합친다. collapse_rows() 주석 참조
 "getBrFlrOulnInfo": dict(
   url=f"{BLD_BASE}/getBrFlrOulnInfo", domain="BLDRGST",
   target="silver.bld_flr_outline",
   keys=["mgm_bldrgst_pk","flr_gb_cd","flr_no","main_purps_cd","strct_cd","main_atch_gb_cd"],
   collapse=dict(by=["mgm_bldrgst_pk","flr_gb_cd","flr_no","main_purps_cd",
                     "strct_cd","main_atch_gb_cd"],
                 sum=["area"], count_into="seg_cnt"),
   map={"mgmBldrgstPk":"mgm_bldrgst_pk","dongNm":"dong_nm","bldNm":"bld_nm",
        "flrGbCd":"flr_gb_cd","flrGbCdNm":"flr_gb_nm",
        "flrNo":"flr_no","flrNoNm":"flr_no_nm",
        "strctCd":"strct_cd","strctCdNm":"strct_nm","etcStrct":"etc_strct",
        "mainPurpsCd":"main_purps_cd","mainPurpsCdNm":"main_purps_nm","etcPurps":"etc_purps",
        "mainAtchGbCd":"main_atch_gb_cd","mainAtchGbCdNm":"main_atch_gb_nm",
        "area":"area","areaExctYn":"area_excl_yn","crtnDay":"crtn_day"}),

 "getBrAtchJibunInfo": dict(
   url=f"{BLD_BASE}/getBrAtchJibunInfo", domain="BLDRGST",
   target="silver.bld_atch_jibun", keys=["mgm_bldrgst_pk","atch_pnu"],
   pnu_from=("atch_sigungu_cd","atch_bjdong_cd","atch_plat_gb_cd","atch_bun","atch_ji"),
   pnu_col="atch_pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk","platPlc":"plat_plc",
        "atchSigunguCd":"atch_sigungu_cd","atchBjdongCd":"atch_bjdong_cd",
        "atchPlatGbCd":"atch_plat_gb_cd","atchBun":"atch_bun","atchJi":"atch_ji",
        "atchRegstrGbCd":"atch_gb_cd","crtnDay":"crtn_day"}),

 # ---- 전유공용면적 (2026-10-18 추가) : 호 단위 면적 ----
 # ★ 정책 4장이 **기각했던 축**이다. 사유는 분량이었다 —
 #   "호당 전유 1행 + 공용 N행 -> 응답의 80%가 공용, 지번당 수천 건".
 #   그 사유는 지금도 참이다. 바뀐 것은 **얻는 것**이다:
 #     · 호 상세의 `전용면적` 칸이 비어 있다(지금 '해당 없음')
 #     · 격자에 평형 필터를 못 건다 — 호별 면적이 없어서
 #     · 실거래는 평형으로 묶이는데(4-1) 대장 쪽에 평형이 없어 둘을 못 잇는다
 #   그래서 **별도 그룹(grp='area')** 으로 둔다. `--grp area` 로 일부러 불러야 돈다.
 #
 # ★ PK 가 응답에 없다 (명세 실측 2026-10-18)
 #   `mgmExposPubuseAreaPk` 는 **건축인허가** 쪽에만 있다. 건축물대장
 #   전유공용면적에는 없다. 그래서 자연키를 직접 정한다 — 층별개요와 같은 처지고
 #   같은 조합을 쓴다. 층·용도·구조까지 넣어야 한 호의 '전유 1 + 공용 N' 이
 #   서로를 밀어내지 않는다. 31_expos_area.sql 의 유니크 인덱스와 **같아야 한다.**
 #
 # ★ collapse 는 층별개요와 같은 이유다
 #   같은 자연키로 여러 행이 오면(구획이 나뉜 경우) 면적을 합치고 몇 개였는지 센다.
 #   합쳤다는 사실을 seg_cnt 에 남긴다 — 조용히 하나로 뭉개지 않는다.
 "getBrExposPubuseAreaInfo": dict(
   url=f"{BLD_BASE}/getBrExposPubuseAreaInfo", domain="BLDRGST",
   target="silver.bld_expos_pubuse_area",
   keys=["mgm_bldrgst_pk","expos_pubuse_gb_cd","main_atch_gb_cd",
         "flr_gb_cd","flr_no","main_purps_cd","strct_cd"],
   collapse=dict(by=["mgm_bldrgst_pk","expos_pubuse_gb_cd","main_atch_gb_cd",
                     "flr_gb_cd","flr_no","main_purps_cd","strct_cd"],
                 sum=["area"], count_into="seg_cnt"),
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk",
        "sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd","platGbCd":"plat_gb_cd",
        "bun":"bun","ji":"ji","platPlc":"plat_plc","bldNm":"bld_nm",
        "dongNm":"dong_nm","hoNm":"ho_nm",
        "flrGbCd":"flr_gb_cd","flrNo":"flr_no",
        "exposPubuseGbCd":"expos_pubuse_gb_cd","mainAtchGbCd":"main_atch_gb_cd",
        "strctCd":"strct_cd","strctCdNm":"strct_nm","etcStrct":"etc_strct",
        "mainPurpsCd":"main_purps_cd","mainPurpsCdNm":"main_purps_nm",
        "etcPurps":"etc_purps","area":"area",
        "regstrGbCd":"regstr_gb_cd","regstrKindCd":"regstr_kind_cd",
        "crtnDay":"crtn_day"}),

 # ---- 지역지구구역 (2026-10-19) ----
 # ★ 어제 VWorld 로 올린 용도지역 폴리곤(11-40)의 **대장 쪽 짝**이다.
 #   `mgmBldrgstPk` 로 1:1 이고 `jijiguCdNm` 이 VWorld `uname` 과 **같은 어휘**다
 #   ("제2종일반주거지역"). 땅으로 잰 것과 대장이 적어 둔 것이 어긋나면 신호다.
 # ★ 한 응답에 **세 종류**가 섞여 온다 — 용도지역/용도지구/용도구역.
 #   `jijiguGbCd` 로 갈린다. 용도'지역'만 쓸 거면 걸러야 한다.
 # ★ 자연키는 (PK, 구분, 코드) 다. 한 건물이 지역 1 + 지구 N + 구역 N 을 갖는다.
 #   PK 만으로 잡으면 서로를 밀어낸다 — 층별개요에서 겪은 것과 같은 함정이다.
 # ★ 분량 실측(2026-10-19): 장위동 2,819 · 불광동 3,237 · 돈암동 472 · 사직동 220.
 "getBrJijiguInfo": dict(
   url=f"{BLD_BASE}/getBrJijiguInfo", domain="BLDRGST",
   target="silver.bld_jijigu",
   keys=["mgm_bldrgst_pk","jijigu_gb_cd","jijigu_cd"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmBldrgstPk":"mgm_bldrgst_pk",
        "sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd","platGbCd":"plat_gb_cd",
        "bun":"bun","ji":"ji","platPlc":"plat_plc","newPlatPlc":"new_plat_plc",
        "splotNm":"splot_nm","block":"block","lot":"lot",
        "jijiguGbCd":"jijigu_gb_cd","jijiguGbCdNm":"jijigu_gb_nm",
        "jijiguCd":"jijigu_cd","jijiguCdNm":"jijigu_nm",
        "reprYn":"repr_yn","etcJijigu":"etc_jijigu","crtnDay":"crtn_day"}),

 # ---- 건축인허가 (건축HUB) ----
 # 대장은 "지어진 것", 인허가는 "지으려는 것". 신축은 거래가 먼저 일어나고
 # 대장이 나중에 생긴다. 그 시차를 메운다 (CONTEXT.md 4-14).
 # 필드는 장위동 62-1 실응답으로 확인했다 (기본개요 15 / 동별개요 29).
 "getApBasisOulnInfo": dict(
   url=f"{PMS_BASE}/getApBasisOulnInfo", domain="ARCHPMS",
   target="silver.arch_permit", keys=["mgm_pmsrgst_pk"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmPmsrgstPk":"mgm_pmsrgst_pk",
        "sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd","platGbCd":"plat_gb_cd",
        "bun":"bun","ji":"ji","platPlc":"plat_plc","bldNm":"bld_nm",
        "splotNm":"splot_nm","block":"block","lot":"lot",
        "jimokCd":"jimok_cd","jimokCdNm":"jimok_nm",
        "jiyukCd":"jiyuk_cd","jiyukCdNm":"jiyuk_nm",
        "jiguCd":"jigu_cd","jiguCdNm":"jigu_nm",
        "guyukCd":"guyuk_cd","guyukCdNm":"guyuk_nm",
        "archGbCd":"arch_gb_cd","archGbCdNm":"arch_gb_nm",
        "mainPurpsCd":"main_purps_cd","mainPurpsCdNm":"main_purps_nm",
        "platArea":"plat_area","archArea":"arch_area","bcRat":"bc_rat",
        "totArea":"tot_area","vlRatEstmTotArea":"vl_rat_estm_tot_area","vlRat":"vl_rat",
        "mainBldCnt":"main_bld_cnt","atchBldDongCnt":"atch_bld_dong_cnt",
        "hhldCnt":"hhld_cnt","hoCnt":"ho_cnt","fmlyCnt":"fmly_cnt",
        "totPkngCnt":"tot_pkng_cnt",
        "archPmsDay":"arch_pms_day","stcnsSchedDay":"stcns_sched_day",
        "realStcnsDay":"real_stcns_day","stcnsDelayDay":"stcns_delay_day",
        "useAprDay":"use_apr_day","crtnDay":"crtn_day"}),

 "getApDongOulnInfo": dict(
   url=f"{PMS_BASE}/getApDongOulnInfo", domain="ARCHPMS",
   target="silver.arch_permit_dong", keys=["mgm_dong_ouln_pk"],
   pnu_from=("sigungu_cd","bjdong_cd","plat_gb_cd","bun","ji"), pnu_col="pnu",
   map={"mgmDongOulnPk":"mgm_dong_ouln_pk","mgmPmsrgstPk":"mgm_pmsrgst_pk",
        "sigunguCd":"sigungu_cd","bjdongCd":"bjdong_cd","platGbCd":"plat_gb_cd",
        "bun":"bun","ji":"ji","platPlc":"plat_plc","bldNm":"bld_nm",
        "mainAtchGbCd":"main_atch_gb_cd","mainAtchGbCdNm":"main_atch_gb_nm",
        "mainPurpsCd":"main_purps_cd","mainPurpsCdNm":"main_purps_nm",
        "strctCd":"strct_cd","strctCdNm":"strct_nm",
        "roofCd":"roof_cd","roofCdNm":"roof_nm",
        "archArea":"arch_area","totArea":"tot_area",
        "vlRatEstmTotArea":"vl_rat_estm_tot_area",
        "hhldCnt":"hhld_cnt","hoCnt":"ho_cnt","fmlyCnt":"fmly_cnt",
        "rideUseElvtCnt":"ride_use_elvt_cnt","emgenUseElvtCnt":"emgen_use_elvt_cnt",
        "crtnDay":"crtn_day"}),
}

NUMERIC_HINTS = ("_area","_cnt","_rat","_no","heit","_bun","_utcnt","_cert","_epi","_ar","_pclnd")
# 소수점을 유지해야 하는 것들. 나머지 숫자는 int 로.
FLOAT_HINTS   = ("_area","_rat","_ar","_pclnd","heit","_cert","_epi")

# ★ 컬럼명이 **정확히** 이것일 때. 부분일치 힌트로는 안 잡힌다 (2026-10-16).
#   층별개요의 `area` 가 그렇다 — "_area" 가 "area" 안에 없어서 숫자 판정이
#   안 되고 문자열로 들어간다. 힌트에 "area" 를 넣어 해결하면 **`area_excl_yn`
#   까지 숫자로 보고 float("Y") 에 실패해 NULL 로 덮는다.** 그래서 정확일치로 분리한다.
# 빈 페이지를 끝으로 보기 전에 몇 번 더 쳐보는가 (2026-10-16).
# data.go.kr 건축물대장은 totalCount 가 남아 있는데도 빈 items 를 돌려준다.
EMPTY_RETRIES = 4

# 서비스 측 **일시** 장애. 재시도하면 대개 풀린다 — 중단할 이유가 아니다.
#   01 어플리케이션 에러 / 02 DB 에러 / 04 HTTP 에러 / 05 서비스 연결실패
# 30·31·32(키 문제)는 재시도해도 안 풀리므로 여기 넣지 않는다.
TRANSIENT_CODES = ("01", "02", "04", "05")
ERROR_RETRIES = 4

#   hsprc(공시가격)도 마찬가지다 — 어떤 힌트에도 안 걸린다. 원 단위 정수다.
NUMERIC_EXACT = ("area", "hsprc")
FLOAT_EXACT   = ("area",)


# ============================================================
# DB
# ============================================================
def db_connect(cfg):
    d = cfg["db"]
    if _DRIVER == "pymssql":
        return pymssql.connect(server=d["host"], port=int(d.get("port", 11433)),
                               user=d["user"], password=d["password"],
                               database=d.get("database", "Teomoony"), charset="UTF-8",
                               autocommit=False)
    if _DRIVER == "pyodbc":
        cs = (f"DRIVER={{ODBC Driver 18 for SQL Server}};"
              f"SERVER={d['host']},{d.get('port',11433)};DATABASE={d.get('database','Teomoony')};"
              f"UID={d['user']};PWD={d['password']};TrustServerCertificate=yes;Encrypt=no")
        return pyodbc.connect(cs, autocommit=False)
    sys.exit("DB 드라이버가 없습니다.  pip install pymssql   (권장)")


def is_deadlock(e):
    """교착(1205)인가. SQL Server 가 스스로 "Rerun the transaction" 이라고 한다.

    ★ 교착은 **건너뛸 행이 아니라 다시 할 일**이다 (2026-10-17).
      스레드 넷이 같은 테이블의 is_current 인덱스를 함께 치면 난다. 그런데
      적재기는 행 단위 except 로 이걸 '건너뛸 행' 으로 삼켰고, 교착은
      **트랜잭션 전체를 죽이므로** 바로 다음 commit 이 3902 로 터지면서
      그 법정동이 통째로 FAIL 이 됐다. 원인은 삼킨 쪽에 있었는데 3902 만
      보였다 - README 미결 3번이 "재현 조건 미상" 이던 이유다.
    """
    m = str(e)
    return "1205" in m or "deadlock" in m.lower()


def q(cur, sql, params=None):
    """pymssql 은 %s, pyodbc 는 ? 를 쓴다 - 플레이스홀더를 맞춰준다."""
    if _DRIVER == "pyodbc":
        sql = sql.replace("%s", "?")
    cur.execute(sql, params or ())


# ============================================================
# API 호출
# ============================================================
def call_api(url, service_key, params, timeout=30, retries=3):
    p = dict(params)
    p["serviceKey"] = service_key          # 포털 발급키 (Decoding 키를 그대로)
    full = f"{url}?{urlencode(p)}"
    last = None
    for attempt in range(1, retries + 1):
        try:
            r = requests.get(url, params=p, timeout=timeout)
            return full, r.status_code, r.text
        except requests.RequestException as e:
            last = e
            time.sleep(1.5 * attempt)
    return full, None, f"<requestFailed>{last}</requestFailed>"


def parse_items(body_text):
    """
    공공데이터 XML -> (result_code, result_msg, total_count, [dict, ...])
    <item> 의 자식 태그를 전부 그대로 담는다. 스펙에 없는 필드도 놓치지 않는다.
    """
    try:
        root = ET.fromstring(body_text)
    except ET.ParseError:
        return None, "XML_PARSE_ERROR", None, []

    code = root.findtext(".//resultCode") or root.findtext(".//returnReasonCode")
    msg = root.findtext(".//resultMsg") or root.findtext(".//returnAuthMsg") or ""
    total = root.findtext(".//totalCount")
    total = int(total) if (total and total.strip().isdigit()) else None

    rows = []
    for item in root.iter("item"):
        d = {}
        for ch in item:
            v = (ch.text or "").strip()
            d[ch.tag] = v if v != "" else None
        if d:
            rows.append(d)
    return code, msg, total, rows


def to_native(col, val):
    if val is None:
        return None
    s = str(val).strip()
    if s == "":
        return None
    if col in NUMERIC_EXACT or any(h in col for h in NUMERIC_HINTS):
        try:
            f = float(s)
        except ValueError:
            return None            # 숫자 자리에 문자가 오는 경우 - 버린다
        return f if (col in FLOAT_EXACT or any(h in col for h in FLOAT_HINTS)) else int(f)
    return s


def row_hash(mapped, cols):
    h = hashlib.sha256()
    for c in cols:
        h.update(str(mapped.get(c, "")).encode("utf-8"))
        h.update(b"\x1f")
    return h.digest()


# ============================================================
# probe
# ============================================================
def cmd_probe(cfg, args):
    op = OPS.get(args.op)
    if not op:
        sys.exit(f"알 수 없는 op: {args.op}\n사용 가능: {', '.join(OPS)}")

    params = {"numOfRows": min(args.rows,100), "pageNo": 1, "_type": "xml"}
    if args.sigungu: params["sigunguCd"] = args.sigungu
    if args.bjdong:  params["bjdongCd"] = args.bjdong
    if args.bun:     params["bun"] = args.bun.zfill(4)
    if args.ji:      params["ji"] = args.ji.zfill(4)

    print(f"\n[probe] {args.op}")
    print(f"  params: {params}")

    full, status, body = call_api(op["url"], cfg["service_key"], params)
    code, msg, total, rows = parse_items(body)

    os.makedirs(args.out, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    raw_path = os.path.join(args.out, f"{args.op}_{stamp}.xml")
    with open(raw_path, "w", encoding="utf-8") as f:
        f.write(body)

    print(f"  HTTP        : {status}")
    print(f"  resultCode  : {code}   {msg}")
    print(f"  totalCount  : {total}")
    print(f"  items       : {len(rows)}")
    print(f"  raw 저장    : {raw_path}")

    if not rows:
        print("\n  ** item 이 없습니다. 아래를 확인하세요 **")
        print("   - resultCode 30/31 : 서비스키 미등록/만료")
        print("   - resultCode 03    : 데이터 없음 (파라미터 조합 문제)")
        print("   - 키는 'Decoding' 키를 쓰고, 활용신청 승인 상태여야 합니다")
        print("\n  --- 응답 앞부분 ---")
        print(body[:1200])
        return

    known, unknown = [], []
    for k in rows[0].keys():
        (known if k in op["map"] else unknown).append(k)

    print(f"\n  매핑된 필드   ({len(known)}) : {', '.join(sorted(known))}")
    if unknown:
        print(f"\n  ** 매핑 안된 필드 ({len(unknown)}) ** : {', '.join(sorted(unknown))}")
        print("     -> 이 목록을 저에게 주시면 스키마에 반영하겠습니다")
    missing = [k for k in op["map"] if k not in rows[0]]
    if missing:
        print(f"\n  응답에 없는 기대필드 ({len(missing)}) : {', '.join(sorted(missing))}")

    print("\n  --- 첫 레코드 ---")
    for k, v in rows[0].items():
        print(f"    {k:28s} = {v}")


# ============================================================
# load
# ============================================================
def cmd_load(cfg, args):
    op = OPS.get(args.op)
    if not op:
        sys.exit(f"알 수 없는 op: {args.op}")

    conn = db_connect(cfg)
    cur = conn.cursor()

    # 소스 등록
    q(cur, """
        MERGE meta.api_source AS t
        USING (SELECT %s AS domain, %s AS operation) AS s
          ON t.domain = s.domain AND t.operation = s.operation
        WHEN NOT MATCHED THEN
          INSERT (domain, provider, operation, base_url, resp_format)
          VALUES (s.domain, N'국토교통부', s.operation, %s, 'xml');
    """, (op["domain"], args.op, op["url"]))
    q(cur, "SELECT source_id FROM meta.api_source WHERE domain=%s AND operation=%s",
      (op["domain"], args.op))
    source_id = cur.fetchone()[0]

    q(cur, """INSERT INTO meta.ingest_run (source_id, run_mode, scope_key)
              VALUES (%s, %s, %s); SELECT CAST(SCOPE_IDENTITY() AS BIGINT);""",
      (source_id, "FULL" if not args.bun else "SINGLE", f"{args.sigungu}/{args.bjdong or '*'}"))
    run_id = int(cur.fetchone()[0])
    conn.commit()
    print(f"[load] run_id={run_id} op={args.op}")

    # ---- 받은 페이지를 적는다 (2026-10-19) ----
    #  ★ 왜: 이어받기를 **행 수로 역산**하고 있었다("255,200행 -> p2550").
    #    그건 "받은 행 수 = 앞에서부터 연속된 페이지" 라는 가정이라, 페이지를
    #    병렬로 받으면 깨진다. 2페이지가 실패해도 행 수는 늘어서, 다음 이어받기가
    #    그 구멍을 모르고 건너뛴다 — **조용히 빠진 페이지**다. 정책 1장.
    #  ★ 그래서 추정하지 말고 받은 페이지를 그대로 적는다.
    #    meta.v_load_page_gap 이 "어디가 비었나" 를 바로 답한다.
    #  ★ 법정동이 없으면(시군구 전체/지번 단위) 적지 않는다 - 키가 안 선다.
    def mark_page(pg, items_n, st, tot):
        if not args.bjdong:
            return
        try:
            q(cur, """
                UPDATE meta.load_page
                   SET items=%s, status=%s, api_total=%s, run_id=%s,
                       fetched_at=SYSDATETIME()
                 WHERE sgg_cd=%s AND bjdong_cd=%s AND op=%s AND page=%s;
                IF @@ROWCOUNT = 0
                INSERT INTO meta.load_page
                       (sgg_cd, bjdong_cd, op, page, items, status, api_total, run_id)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s);""",
              (items_n, st, tot, run_id, args.sigungu, args.bjdong, args.op, pg,
               args.sigungu, args.bjdong, args.op, pg, items_n, st, tot, run_id))
            conn.commit()
        except Exception as e:
            # 기록 실패가 적재를 막으면 안 된다. 다만 **조용히 넘기지는 않는다.**
            print(f"  [page-mark] {pg}쪽 기록 실패: {e}")
            try: conn.rollback()
            except Exception: pass

    # ★ --from-page: 끊긴 데서 이어 받는다 (2026-10-16).
    #   적재기는 늘 1페이지부터 돌았다. 중간에 끊기면 다시 돌려도 앞부분을 또
    #   받아버리고(행은 '동일'로 건너뛰지만 **API 호출은 그대로 쓴다**) 같은
    #   자리에서 또 죽는다. 전유부 14,666건(147페이지)에서 이게 드러났다.
    #   앞 페이지 응답이 같다는 보장은 없으므로 **자동 추정은 하지 않는다.**
    #   사람이 로그를 보고 넘길 페이지를 정한다.
    total_rows, req_cnt, page = 0, 0, max(1, int(getattr(args, "from_page", 1) or 1))
    status_final, err = "OK", None
    # API 가 말한 전체 건수와 실제로 받은 item 수. 끝에서 맞춰 본다.
    api_total, items_got, empty_retry, err_retry = None, 0, 0, 0
    # ★ 이어 받을 때는 **앞 페이지에서 받은 것으로 치고 시작한다** (2026-10-17).
    #   안 그러면 이번 실행에서 받은 수만 totalCount 와 비교해, 전건을 다 채우고도
    #   PARTIAL 로 찍히고 "전건 수신" 종료 조건도 안 걸린다. --from-page 를 넣으면서
    #   만든 버그다. 앞 페이지가 꽉 찼다는 **가정**이므로 추정치임을 밝힌다.
    if page > 1:
        items_got = (page - 1) * min(args.rows, 100)
        print(f"  [resume] {page}페이지부터. 앞 {page-1}페이지(약 {items_got}건)는 "
              f"받은 것으로 칩니다 — 그 구간이 실제로 들어와 있는지는 **확인하고 쓰십시오**.")
    skipped_total = 0
    tot_ins = tot_upd = tot_same = 0

    try:
        while True:
            params = {"numOfRows": min(args.rows,100), "pageNo": page, "_type": "xml",
                      "sigunguCd": args.sigungu}
            if args.bjdong: params["bjdongCd"] = args.bjdong
            if args.bun:    params["bun"] = args.bun.zfill(4)
            if args.ji:     params["ji"] = args.ji.zfill(4)

            full, http, body = call_api(op["url"], cfg["service_key"], params)
            req_cnt += 1
            code, msg, total, rows = parse_items(body)

            # bronze - 원문 보존 (파싱 결과와 무관하게 항상)
            q(cur, """INSERT INTO bronze.api_payload
                      (run_id, source_id, req_url_hash, req_params, http_status,
                       result_code, body, body_sha256)
                      VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
              (run_id, source_id,
               hashlib.sha256(full.encode()).digest(), json.dumps(params, ensure_ascii=False),
               http, code, body, hashlib.sha256(body.encode()).digest()))
            conn.commit()

            if code not in (None, "00", "0"):
                # ★ 일시 장애는 중단이 아니다 (2026-10-16).
                #   `resultCode=05 서비스 연결실패` 로 5페이지에서 끊겼는데
                #   **status=OK 로 기록됐다**(400/6029). 정책 7장의
                #   "HTTP 200 은 성공이 아니다" 와 같은 뿌리다.
                if code in TRANSIENT_CODES and err_retry < ERROR_RETRIES:
                    err_retry += 1
                    wait = 3.0 * err_retry
                    print(f"  page {page}: resultCode={code} {msg} "
                          f"-> {wait:.0f}초 후 재시도 {err_retry}/{ERROR_RETRIES}")
                    time.sleep(wait)
                    continue
                print(f"  page {page}: resultCode={code} {msg} -> 중단")
                if code in ("30", "31", "32"):
                    status_final, err = "FAIL", f"service key error {code}: {msg}"
                else:
                    err = err or f"resultCode {code}: {msg}"
                break
            if total is not None:
                api_total = total
            if not rows:
                # ★★ 빈 페이지가 끝이 아니다 (2026-10-16 실측).
                #   같은 호출을 두 번 돌렸는데 1회차는 8페이지(800건), 2회차는
                #   1페이지(100건)에서 빈 응답이 왔다. totalCount 는 5,194 였다.
                #   **200 + resultCode 00 + items 없음** 도 성공이 아니다 —
                #   정책 7장 "HTTP 200 은 성공이 아니다" 의 형제 사례다.
                #   call_api 의 재시도는 네트워크 예외만 잡으므로 여기서 다시 친다.
                #   ★ totalCount 가 **아예 없는** 응답은 실패다 (2026-10-16).
                #     진짜로 데이터가 없으면 <totalCount>0</totalCount> 이 온다 —
                #     probe 로 확인했다. totalCount 태그 자체가 없다는 것은
                #     응답이 제대로 오지 않았다는 뜻이다. 그래서 None 도 재시도한다.
                if ((api_total is None or items_got < api_total)
                        and empty_retry < EMPTY_RETRIES):
                    empty_retry += 1
                    wait = 2.0 * empty_retry
                    got = f"{items_got}/{api_total}" if api_total is not None \
                          else f"{items_got}, totalCount 없음(code={code})"
                    print(f"  page {page}: item 없음 (받은 {got}) "
                          f"-> {wait:.0f}초 후 재시도 {empty_retry}/{EMPTY_RETRIES}")
                    time.sleep(wait)
                    continue          # page 를 올리지 않고 같은 페이지를 다시
                # ★ 행이 비었다고 다 받은 것이 아니다 (2026-10-16).
                #   totalCount 가 더 크면 API 가 중간에 끊은 것이고, 여기서 조용히
                #   "종료" 로 적으면 **부분 적재가 정상으로 기록된다.**
                #   돈암동 층별개요가 8페이지(800건)에서 빈 페이지로 끝났는데
                #   그게 전부인지 잘린 것인지 알 방법이 없었다.
                if getattr(args, "range_mode", False):
                    # ★ 구간 실행에서 빈 페이지는 **끝이 아니다**(2026-10-20 수정).
                    #   처음엔 여기서 break 했는데, 그러면 한 페이지가 비었다고
                    #   **그 구간의 남은 페이지를 통째로 버린다.** 기본개요 적재에서
                    #   중간빠짐 58·24·21·14쪽이 그렇게 생겼다.
                    #   적재기가 원래 적어 둔 경고 그대로다 - "빈 페이지가 끝이
                    #   아니다(2026-10-16 실측). 같은 호출을 두 번 돌렸는데 1회차는
                    #   8페이지, 2회차는 1페이지에서 빈 응답이 왔다."
                    #   재시도(EMPTY_RETRIES)를 다 쓴 뒤에도 비면 **그 페이지만**
                    #   EMPTY 로 적고 다음 페이지로 간다. 구간의 끝은 max_pages 가
                    #   정한다 - 빈 응답이 정하는 게 아니다.
                    print(f"  page {page}: item 없음 -> 이 쪽만 비움으로 적고 계속")
                    mark_page(page, 0, "EMPTY", api_total)
                    empty_retry = 0
                    if args.max_pages and page >= args.max_pages:
                        break
                    page += 1
                    continue
                if api_total is not None and items_got < api_total:
                    print(f"  page {page}: item 없음 -> **중단**  "
                          f"받은 {items_got} < totalCount {api_total} "
                          f"({api_total - items_got}건 모자람)")
                    status_final = "PARTIAL"
                    err = f"truncated: got {items_got} of {api_total}"
                elif api_total is None:
                    # 끝까지 totalCount 를 못 받았다. 몇 건이 맞는지 알 수 없으므로
                    # **OK 라고 적지 않는다.** 모르는 것은 모른다고 적는다.
                    print(f"  page {page}: item 없음 + totalCount 없음 -> **중단** "
                          f"(받은 {items_got}건이 전부인지 확인 불가)")
                    status_final = "PARTIAL"
                    err = err or f"no totalCount; got {items_got}"
                else:
                    print(f"  page {page}: item 없음 -> 종료"
                          f"  (totalCount {api_total} 전건 수신)")
                # 빈 페이지도 **적는다.** 안 적으면 "아직 안 받은 것" 과
                # "받았더니 비어 있던 것" 을 구별할 수 없다.
                mark_page(page, 0, "EMPTY", api_total)
                break

            empty_retry = err_retry = 0   # 한 페이지라도 받았으면 재시도 카운터를 되돌린다
            # ★ 교착이면 페이지를 통째로 되돌리고 다시 한다 (2026-10-17).
            #   이미 커밋된 앞 페이지는 그대로 있고, SCD 업서트는 같은 내용을
            #   다시 넣으면 '동일' 로 떨어지므로 페이지 재실행은 안전하다.
            for attempt in range(4):
                try:
                    (n_ins, n_upd, n_same), skipped = upsert_silver(cur, op, rows, run_id)
                    if any(is_deadlock(why) for _, why in skipped):
                        raise RuntimeError("deadlock 1205 (행 단위로 잡혔다)")
                    conn.commit()
                    break
                except Exception as e:
                    if attempt == 3 or not is_deadlock(e):
                        raise
                    try:
                        conn.rollback()
                    except Exception:
                        pass
                    wait = 0.4 * (2 ** attempt)
                    print(f"  page {page}: 교착 -> {wait:.1f}초 쉬고 재시도 "
                          f"({attempt + 1}/3)")
                    time.sleep(wait)
            items_got += len(rows)
            total_rows += n_ins + n_upd
            tot_ins += n_ins; tot_upd += n_upd; tot_same += n_same
            print(f"  page {page}: {len(rows)} items -> 신규 {n_ins} · 변경 {n_upd} · 동일 {n_same}"
                  f"  (누적 신규+변경 {total_rows})")
            mark_page(page, len(rows), "OK", api_total)
            if skipped:
                # 건너뛴 행은 **반드시 보고한다.** 조용히 넘어가면 부분 적재가
                # 정상으로 보인다 — 오늘 적재기에서 네 번 반복한 그 실수다.
                skipped_total += len(skipped)
                status_final = "PARTIAL"
                err = err or f"{len(skipped)} rows skipped: {skipped[0][1]}"
                print(f"    ** {len(skipped)}행 건너뜀 **  키={skipped[0][0]}")
                print(f"       {skipped[0][1]}")

            if api_total is not None and items_got >= api_total:
                print(f"  totalCount {api_total} 전건 수신 -> 종료")
                break
            if args.max_pages and page >= args.max_pages:
                # ★ 구간을 **일부러** 나눠 받을 때는 PARTIAL 이 아니다(2026-10-19).
                #   페이지 병렬을 붙이면서 생겼다. 일부러 끊은 것과 API 가 끊은
                #   것을 같은 말로 적으면, 진짜 사고가 묻힌다.
                if getattr(args, "range_mode", False):
                    print(f"  구간 끝 (p{args.from_page}~{args.max_pages}) -> 정상 종료")
                else:
                    print(f"  max_pages({args.max_pages}) 도달 -> 중단")
                    status_final = "PARTIAL"
                break
            page += 1
            time.sleep(cfg.get("sleep_sec", 0.2))

    except KeyboardInterrupt:
        # ★ Ctrl+C 는 Exception 이 아니라 BaseException 이다 (2026-10-17).
        #   전에는 아래 `except Exception` 이 못 잡았고, 판정 줄이 try 안에
        #   있어서 **건너뛴 채 finally 로 갔다.** status_final 은 초기값 "OK".
        #   그래서 **중단된 적재가 성공으로 기록됐다** — 수색동 기본개요가
        #   3,400/9,174 에서 멈춘 채 OK 로 남았고, run_plan 이 DONE 으로
        #   건너뛰어 영영 안 채워졌다.
        status_final = "ABORTED"
        err = err or f"사용자 중단: got {items_got}" + (
            f" of {api_total}" if api_total is not None else "")
        print(f"\n  ** 중단됨 — {err} **")
        raise
    except Exception as e:
        conn.rollback()
        status_final, err = "FAIL", str(e)[:1900]
        print(f"  오류: {e}")
        raise
    finally:
        # ★★ 판정은 **finally 에 둔다** (2026-10-17).
        #   어제는 "출구가 여럿이면 판정은 한 곳에" 라고 while 루프 **뒤**에
        #   뒀다. 그것도 출구 하나였다 — 정상 종료라는 출구. 중단과 예외는
        #   그 줄을 지나가지 않는다. 진짜로 모든 경로가 지나는 곳은 finally 다.
        if status_final == "OK" and (api_total is None or items_got < api_total):
            status_final = "PARTIAL"
            err = err or (f"truncated: got {items_got} of {api_total}"
                          if api_total is not None
                          else f"no totalCount; got {items_got}")
            print(f"  ** {err} -> PARTIAL **")
        # ★ finally 에서 난 예외는 **원래 예외를 덮는다** (2026-10-17).
        #   인허가 적재 14건이 `3902 COMMIT TRANSACTION has no corresponding
        #   BEGIN` 으로 죽었는데, 그건 여기 commit 이 낸 소리일 뿐 **진짜 원인이
        #   아닐 수 있다.** 진짜 원인은 위에서 이미 터졌고 파이썬이 이 줄의
        #   예외로 갈아 끼운 것이다. 기록 갱신이 실패하는 건 받아들이되,
        #   **원래 오류를 가리지는 않게** 한다.
        #   갱신을 못 하면 ingest_run 은 RUNNING 으로 남고, run_plan 은 그걸
        #   RETRY 로 본다 - 안 한 일과 끊긴 일을 섞지 않는다는 규칙 그대로다.
        try:
            q(cur, """UPDATE meta.ingest_run
                         SET finished_at=SYSDATETIME(), status=%s, req_count=%s, row_count=%s, err_msg=%s
                       WHERE run_id=%s""",
              (status_final, req_cnt, total_rows, err, run_id))
            conn.commit()
        except Exception as e2:
            print(f"  ** 실행 기록 갱신 실패: {e2}")
            print(f"     (run_id={run_id} 는 RUNNING 으로 남는다 -> RETRY 로 잡힌다.")
            print(f"      진짜 원인은 이 줄이 아니라 **위쪽 오류**를 보라)")
            try:
                conn.rollback()
            except Exception:
                pass
        finally:
            try:
                conn.close()
            except Exception:
                pass

    print(f"[load] 완료  status={status_final}  requests={req_cnt}"
          f"  신규 {tot_ins} · 변경 {tot_upd} · 동일 {tot_same}"
          + (f"  items={items_got}/{api_total}" if api_total is not None else ""))
    if skipped_total:
        print(f"  ** {skipped_total}행이 DB 오류로 건너뛰어졌다. 위 사유를 보고 스키마를 고친 뒤 다시 돌릴 것. **")
    if status_final == "PARTIAL":
        print("  ** 부분 적재다. 다시 돌리면 이어서 채워진다(row_hash 가 같으면 건너뛴다). **")


def collapse_rows(op, rows):
    """
    같은 자연키의 행을 한 행으로 합친다. op 가 `collapse` 를 정의할 때만 돈다.

    왜 필요한가 (2026-10-16, 층별개요):
      건축물대장 층별개요는 **같은 층에 같은 용도·구조가 여러 구획으로** 들어온다.
      실측: 지하주차장 지하2층 아파트 철근콘크리트 부속건축물 이 면적만 다른
      두 행(283.2 / 264.5). 식별 컬럼이 전부 같아 **어떤 조합으로도 유일해지지 않는다.**

      쓸 수 있는 선택지가 셋이었다.
        · 키에 area 를 넣는다  -> 면적이 정정되면 옛 행이 안 닫히고 고아로 남는다. **기각**
        · rnum(응답 순번)을 쓴다 -> 구획 하나가 늘면 뒤가 전부 밀려 거짓 변경이 쏟아진다. **기각**
        · 합친다               -> 채택. 화면이 필요한 것은 "이 동 이 층에 아파트 547.7㎡"
                                 이지 구획 내역이 아니다.

      **원본은 bronze.api_payload 에 그대로 남으므로 되돌릴 수 있다**(1원칙).
      합쳤다는 사실은 `seg_cnt`(구획 수)로 남긴다 — 조용히 합치지 않는다.
    """
    spec = op.get("collapse")
    if not spec:
        return rows
    gb, add, cnt_col = spec["by"], spec["sum"], spec.get("count_into")
    out, idx = [], {}
    for r in rows:
        k = tuple(r.get(c) for c in gb)
        if k in idx:
            tgt = idx[k]
            for c in add:
                a, b = tgt.get(c), r.get(c)
                if a is not None or b is not None:
                    tgt[c] = float(a or 0) + float(b or 0)
            if cnt_col:
                tgt[cnt_col] = tgt.get(cnt_col, 1) + 1
        else:
            if cnt_col:
                r[cnt_col] = 1
            idx[k] = r
            out.append(r)
    return out


def upsert_silver(cur, op, rows, run_id):
    """
    SCD Type 2 적재
      1) 키가 같고 row_hash 가 다른 현재행을 닫는다 (is_current=0, valid_to=now)
      2) 현재행이 없는 키를 새 버전으로 넣는다
    row_hash 가 같으면 아무것도 하지 않는다 -> 이력 폭증 방지
    """
    target = op["target"]
    keys = op["keys"]
    cols = list(dict.fromkeys(op["map"].values()))
    pnu_col = op.get("pnu_col")
    pnu_from = op.get("pnu_from")
    if pnu_col and pnu_col not in cols:
        cols.append(pnu_col)
    # collapse 가 만들어내는 구획 수 컬럼도 적재 대상이다 (map 에는 없다)
    _cnt_col = (op.get("collapse") or {}).get("count_into")
    if _cnt_col and _cnt_col not in cols:
        cols.append(_cnt_col)

    # ★ merged 를 무조건 세면 "처리한 행"이 "넣은 행"처럼 보인다 (2026-10-16).
    #   이미 들어있는 7,000건을 다시 훑어도 로그는 똑같이 "merged" 라고 찍혔다.
    #   신규 / 변경 / 동일 을 가른다 — 재실행이 의미가 있었는지 사람이 알아야 한다.
    ins, upd, same, skipped = 0, 0, 0, []
    mapped_rows = []
    for raw in rows:
        m = {}
        for src, dst in op["map"].items():
            m[dst] = to_native(dst, raw.get(src))
        mapped_rows.append(m)
    # 자연키가 유일하지 않은 축은 여기서 합친다 (collapse_rows 주석 참조)
    mapped_rows = collapse_rows(op, mapped_rows)

    for m in mapped_rows:

        # PNU 는 DB 함수로만 만든다 (platGbCd 매핑 실수 방지)
        if pnu_col and pnu_from:
            q(cur, "SELECT meta.fn_make_pnu(%s,%s,%s,%s,%s)",
              tuple(None if m.get(c) is None else str(m.get(c)) for c in pnu_from))
            m[pnu_col] = cur.fetchone()[0]

        if any(m.get(k) in (None, "") for k in keys if k != pnu_col):
            continue  # 키가 없으면 버린다 (bronze 에 원문은 남아 있다)

        rh = row_hash(m, cols)

        where_key = " AND ".join(
            f"{k} = %s" if m.get(k) is not None else f"{k} IS NULL" for k in keys
        )
        key_vals = tuple(m[k] for k in keys if m.get(k) is not None)

        # ★ 한 행 때문에 run 전체가 죽지 않게 한다 (2026-10-16).
        #   정릉동 258-37 의 건폐율 59,315% 가 DECIMAL(9,5) 를 넘겨 적재가
        #   18페이지에서 통째로 터졌다. 17페이지까지 넣고 FAIL 이었다.
        #   **건너뛰되 조용히 넘어가지 않는다** — 건수와 사유를 호출자에게 돌려주고
        #   호출자는 그 run 을 PARTIAL 로 남긴다. "모르는 것을 모른다고 적는다".
        try:
            # 1) 변경된 현재행 닫기
            q(cur, f"""UPDATE {target}
                          SET is_current = 0, valid_to = SYSDATETIME()
                        WHERE is_current = 1 AND {where_key} AND row_hash <> %s""",
              key_vals + (rh,))
            closed = cur.rowcount or 0

            # 2) 현재행 없으면 신규 버전 삽입
            collist = ", ".join(cols) + ", row_hash, src_run_id"
            ph = ", ".join(["%s"] * len(cols)) + ", %s, %s"
            q(cur, f"""IF NOT EXISTS (SELECT 1 FROM {target} WHERE is_current = 1 AND {where_key})
                         INSERT INTO {target} ({collist}) VALUES ({ph})""",
              key_vals + tuple(m.get(c) for c in cols) + (rh, run_id))
            if cur.rowcount and cur.rowcount > 0:
                upd += 1 if closed else 0
                ins += 0 if closed else 1
            else:
                same += 1          # 이미 같은 내용으로 들어있다
        except Exception as e:
            skipped.append((key_vals, f"{type(e).__name__}: {str(e)[:160]}"))
            # ★ 여기서 **바로** 찍는다 (2026-10-17).
            #   전에는 호출자가 commit 을 지난 뒤에 모아서 찍었다. 그런데 이
            #   오류가 트랜잭션을 죽이는 종류면(교착 1205 같은) **바로 다음
            #   commit 이 3902 로 먼저 터져** 이 줄들은 영영 안 찍힌다.
            #   인허가 실패 14건의 진짜 원인이 그렇게 사라졌다 - README 미결
            #   3번이 "재현 조건 미상" 으로 남아 있던 이유다.
            #   **증거는 모아 놓고 버리고 있었다.**
            kind = "교착 — 페이지를 다시 한다" if is_deadlock(e) else "행 건너뜀"
            print(f"    ** {kind} ** 키={key_vals}")
            print(f"       {type(e).__name__}: {str(e)[:300]}")

    return (ins, upd, same), skipped


# ============================================================
# build
# ============================================================
def cmd_build(cfg, args):
    conn = db_connect(cfg)
    cur = conn.cursor()
    st = progress.Step(f"단지 구성 sigungu={args.sigungu or 'ALL'}")
    q(cur, "EXEC gold.usp_build_complexes @sigungu_cd=%s, @bjdong_cd=%s",
      (args.sigungu, args.bjdong))
    conn.commit()
    st.done()

    # ★ 2026-10-21: 단지가 다시 묶였으면 **단지 ↔ K-apt 연결 표**도 다시 굳힌다(280).
    #   연결 규칙(gold.v_complex_kapt)이 단지의 사용승인일·세대·지번을 보기 때문이다.
    q(cur, "EXEC gold.usp_refresh_complex_kapt")
    r = cur.fetchone()
    conn.commit()
    print(f"  단지 ↔ K-apt 연결 다시 굳힘: {r[0]:,}개 ({r[1]}초)")

    for sql, label in [
        ("SELECT COUNT(*) FROM gold.complex", "단지"),
        ("SELECT COUNT(*) FROM gold.complex_bld", "단지-동 매핑"),
        ("SELECT COUNT(*) FROM gold.complex_pnu", "단지-필지 매핑"),
    ]:
        q(cur, sql); print(f"  {label:16s}: {cur.fetchone()[0]:,}")

    q(cur, """SELECT TOP 20 gap_type, COUNT(*) FROM gold.v_link_gap
              GROUP BY gap_type ORDER BY 2 DESC""")
    gaps = cur.fetchall()
    if gaps:
        print("\n  연계 결손:")
        for g, c in gaps:
            print(f"    {g:16s}: {c:,}")
    conn.close()


# ============================================================
def main():
    ap = argparse.ArgumentParser(description="Teomoony 적재기")
    ap.add_argument("cmd", choices=["probe", "load", "build"])
    ap.add_argument("--config", default="config.json")
    ap.add_argument("--op", default="getBrTitleInfo")
    ap.add_argument("--sigungu")
    ap.add_argument("--bjdong")
    ap.add_argument("--bun")
    ap.add_argument("--ji")
    ap.add_argument("--rows", type=int, default=100)   # API 상한 100
    ap.add_argument("--from-page", type=int, default=1,
                    help="이 페이지부터 받는다. 끊긴 적재를 이어 받을 때 쓴다")
    ap.add_argument("--max-pages", type=int, default=0, dest="max_pages")
    ap.add_argument("--range-mode", action="store_true", dest="range_mode",
                    help="--from-page ~ --max-pages 구간만 받는다. 일부러 끊는 "
                         "것이므로 PARTIAL 로 적지 않는다 (페이지 병렬용)")
    ap.add_argument("--out", default="./raw")
    args = ap.parse_args()

    # ★ 일시정지 플래그(2026-10-20). etl/_pause.flag 가 있으면 **받지 않고 나간다.**
    #   왜 필요한가: 감시기 큐는 한 번에 하나씩 돌고, 긴 적재가 도는 동안에는
    #   진단 쿼리 하나도 못 넣는다. 프로세스를 밖에서 죽이려면 Windows 명령이
    #   필요한데 그것도 큐를 타야 하고, 컴퓨터 제어는 터미널에 타이핑을 못 한다.
    #   적재기는 **구간마다 새 프로세스**로 뜨므로, 파일 하나로 멈출 수 있다.
    #   ★ 종료코드 0 으로 나간다 - 이건 실패가 아니라 **안 한 것**이다.
    #     받지 않은 페이지는 meta.load_page 에 안 적히므로 구멍 보고서가 잡고,
    #     플래그를 지우고 다시 돌리면 그 구간만 받는다.
    _pause = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_pause.flag")
    if os.path.exists(_pause):
        print("[pause] _pause.flag 가 있어 받지 않고 나갑니다 "
              "(실패 아님 - 플래그를 지우고 다시 돌리면 이어받습니다)")
        return

    if not os.path.exists(args.config):
        sys.exit(f"설정 파일이 없습니다: {args.config}\nconfig.example.json 을 복사해서 채우세요.")
    with open(args.config, encoding="utf-8") as f:
        cfg = json.load(f)

    if args.cmd == "probe":
        cmd_probe(cfg, args)
    elif args.cmd == "load":
        if not args.sigungu:
            sys.exit("--sigungu 는 필수입니다 (예: 11110)")
        cmd_load(cfg, args)
    else:
        cmd_build(cfg, args)


if __name__ == "__main__":
    main()
