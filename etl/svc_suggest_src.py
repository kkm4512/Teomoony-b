# -*- coding: utf-8 -*-
"""자동완성(/api/suggest) 을 서비스DB 로 옮길 때의 원천 표들 (2026-10-25, 2단계 둘째 묶음) — svc_layers.py 가 읽는다.
★ 원칙: 검색어와 상관없는 값(묶음별 출력 칸 · 상자 · 개수 · 문자열 합치기 · 평균)은 **적재DB 가 미리 계산**해 그대로 담는다.
  서비스DB 는 거르기(LIKE) · 순서 · 상한 · 전체 개수만 한다 → 값이 옛 경로와 같을 수밖에 없게.
★ 이름 비교용 칸: _ns = 띄어쓰기 뺀 것(옛 REPLACE(x, ' ', '')) — 옛 질의가 그 칸을 쓰는 곳에만."""
D = "double precision"
U = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;\n"
TRGM = lambda c: f"USING gin ({c} gin_trgm_ops)"

SUGG = [
  # 1 구 — 단지가 있는 시군구만 · 상자는 그 단지들
  ("sg_sgg", None, U + """
    SELECT l.sgg_cd, l.sgg_nm, l.sido_nm, b.minx, b.miny, b.maxx, b.maxy
      FROM meta.lawd_code l
     CROSS APPLY (SELECT minx = MIN(c.bbox_minx), miny = MIN(c.bbox_miny), maxx = MAX(c.bbox_maxx), maxy = MAX(c.bbox_maxy), n = COUNT(*)
                    FROM gold.complex c
                   WHERE c.rep_pnu >= CAST(l.sgg_cd + '00000000000000' AS CHAR(19)) AND c.rep_pnu <= CAST(l.sgg_cd + '99999999999999' AS CHAR(19))) b
     WHERE l.emd_nm IS NULL AND l.ri_nm IS NULL AND l.sgg_nm IS NOT NULL AND b.n > 0""",
   [("sgg_cd", "text"), ("sgg_nm", "text"), ("sido_nm", "text"), ("minx", D), ("miny", D), ("maxx", D), ("maxy", D)], []),
  # 2 법정동
  ("sg_lawd", None, U + """
    SELECT l.lawd_cd, l.emd_nm, l.full_nm,
           경계있음 = CASE WHEN EXISTS (SELECT 1 FROM silver.lawd_boundary x WHERE x.lawd_cd = l.lawd_cd AND x.is_current = 1) THEN 1 ELSE 0 END,
           minx = COALESCE(lb.bbox_minx, b.minx), miny = COALESCE(lb.bbox_miny, b.miny), maxx = COALESCE(lb.bbox_maxx, b.maxx), maxy = COALESCE(lb.bbox_maxy, b.maxy)
      FROM meta.lawd_code l
      LEFT JOIN silver.lawd_boundary lb ON lb.lawd_cd = l.lawd_cd AND lb.is_current = 1
     OUTER APPLY (SELECT minx = MIN(c.bbox_minx), miny = MIN(c.bbox_miny), maxx = MAX(c.bbox_maxx), maxy = MAX(c.bbox_maxy)
                    FROM gold.complex c
                   WHERE lb.lawd_cd IS NULL
                     AND c.rep_pnu >= CAST(l.lawd_cd + '000000000' AS CHAR(19)) AND c.rep_pnu <= CAST(l.lawd_cd + '999999999' AS CHAR(19))) b
     WHERE l.ri_nm IS NULL AND l.emd_nm IS NOT NULL
       AND EXISTS (SELECT 1 FROM gold.complex c WHERE c.rep_pnu >= CAST(l.lawd_cd + '000000000' AS CHAR(19)) AND c.rep_pnu <= CAST(l.lawd_cd + '999999999' AS CHAR(19)))""",
   [("lawd_cd", "text"), ("emd_nm", "text"), ("full_nm", "text"), ("경계있음", "int"), ("minx", D), ("miny", D), ("maxx", D), ("maxy", D)], []),
  # 3 행정동 (최신 해 경계) — 397 (2026-10-31): 이름 · 지금없음은 공식 연계(gold.adm_link)와 행안부 이력으로.
  #   지금없음 = 경계가 이어진 행안부 행정동이 말소됨(예: 2026.07.01 인천 중구 · 전남광주 통합 — 통계청 새 경계가 나오기 전)
  ("sg_adm", None, U + """
    SELECT a.adm_cd_sgis, a.year, a.adm_nm, a.emd_nm, mois_nm = k.행정동명, a.연결비율,
           minx = a.bbox_minx, miny = a.bbox_miny, maxx = a.bbox_maxx, maxy = a.bbox_maxy,
           지금없음 = CASE WHEN k.현행 = 0 THEN 1 ELSE 0 END
      FROM silver.adm_boundary a
      LEFT JOIN gold.adm_link k ON k.adm_cd_sgis = a.adm_cd_sgis AND k.year = a.year
     WHERE a.year = (SELECT MAX(year) FROM silver.adm_boundary)""",
   [("adm_cd_sgis", "text"), ("year", "text"), ("adm_nm", "text"), ("emd_nm", "text"), ("mois_nm", "text"), ("연결비율", D),
    ("minx", D), ("miny", D), ("maxx", D), ("maxy", D), ("지금없음", "int")], []),
  # 4 단지 — 합쳐지지 않은 단지 전부(57만). nm_ns 는 이름이 진짜 이름일 때만(주소로 대신한 이름은 NULL)
  ("sg_complex",
   """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(complex_id, complex_nm, complex_nm_ns, complex_nm_src, rep_plat_plc, rep_road_addr,
                                                               hhld_cnt_sum, dong_cnt, centroid_lat, centroid_lng, merged_into))) FROM gold.complex), '|',
                    (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(complex_id, 실거래이름))) FROM gold.complex_alias), '|',
                    (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(site_key, pnu))) FROM gold.closed_site), '|',
                    (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(pnu, complex_id))) FROM gold.complex_pnu))""",
   U + """
    SELECT c.complex_id, c.complex_nm, c.rep_plat_plc, c.rep_road_addr, c.hhld_cnt_sum, c.dong_cnt, c.centroid_lat, c.centroid_lng,
           nm_ns = CASE WHEN c.complex_nm_src <> 'ADDR' THEN c.complex_nm_ns END,
           실거래이름 = al.실거래이름,
           폐쇄 = ISNULL(f.n, 0)
      FROM gold.complex c
      LEFT JOIN gold.complex_alias al ON al.complex_id = c.complex_id
      LEFT JOIN (SELECT cp.complex_id, n = COUNT(*) FROM gold.complex_pnu cp JOIN gold.closed_site s ON s.pnu = cp.pnu GROUP BY cp.complex_id) f
             ON f.complex_id = c.complex_id
     WHERE c.merged_into IS NULL""",
   [("complex_id", "int PRIMARY KEY"), ("complex_nm", "text"), ("rep_plat_plc", "text"), ("rep_road_addr", "text"), ("hhld_cnt_sum", "int"),
    ("dong_cnt", "int"), ("centroid_lat", D), ("centroid_lng", D), ("nm_ns", "text"), ("실거래이름", "text"), ("폐쇄", "int")],
   [TRGM("nm_ns"), TRGM("complex_nm"), TRGM("rep_plat_plc"), TRGM("rep_road_addr"), TRGM('"실거래이름"')]),
  # 4' 단지의 다른 이름 — K-apt(이어진 것) · K-apt(지번으로) · 실거래. live = 그 단지가 합쳐지지 않음
  ("sg_complex_name", None, U + """
    SELECT complex_id = ck.complex_id, src = 'kapt', name = ck.kapt_name, name_ns = REPLACE(ck.kapt_name, ' ', ''),
           live = CASE WHEN c.complex_id IS NOT NULL AND c.merged_into IS NULL THEN 1 ELSE 0 END
      FROM gold.complex_kapt ck LEFT JOIN gold.complex c ON c.complex_id = ck.complex_id
    UNION ALL
    SELECT cp.complex_id, 'kaptpnu', k.kapt_name, REPLACE(k.kapt_name, ' ', ''), CASE WHEN c.merged_into IS NULL THEN 1 ELSE 0 END
      FROM silver.kapt_complex k JOIN gold.complex_pnu cp ON cp.pnu = k.pnu JOIN gold.complex c ON c.complex_id = cp.complex_id
     WHERE k.is_current = 1
    UNION ALL
    SELECT al.complex_id, 'alias', al.실거래이름, REPLACE(al.실거래이름, ' ', ''), CASE WHEN c.complex_id IS NOT NULL AND c.merged_into IS NULL THEN 1 ELSE 0 END
      FROM gold.complex_alias al LEFT JOIN gold.complex c ON c.complex_id = al.complex_id""",
   [("complex_id", "int"), ("src", "text"), ("name", "text"), ("name_ns", "text"), ("live", "int")],
   [TRGM("name_ns"), TRGM("name")]),
  # 5 신축(대장 없는 K-apt)
  ("sg_newbuild", None, U + """SELECT n.kapt_code, n.kapt_name, name_ns = REPLACE(n.kapt_name, ' ', ''), n.lawd_nm, n.세대, n.centroid_lat, n.centroid_lng,
                                        n.pnu, n.동수, n.사용승인, n.거래, n.kapt_addr, n.doro_juso
                                 FROM gold.v_newbuild n""",
   [("kapt_code", "text"), ("kapt_name", "text"), ("name_ns", "text"), ("lawd_nm", "text"), ("세대", "int"), ("centroid_lat", D), ("centroid_lng", D),
    ("pnu", "text"), ("동수", "int"), ("사용승인", "text"), ("거래", "int"), ("kapt_addr", "text"), ("doro_juso", "text")], []),
  # 6 재개발 · 정비
  ("sg_redev", None, U + """SELECT z.present_sn, z.zone_nm, z.biz_nm, z.propel_nm, z.centroid_lat, z.centroid_lng,
                                   minx = z.bbox_minx, miny = z.bbox_miny, maxx = z.bbox_maxx, maxy = z.bbox_maxy,
                                   zone_ns = REPLACE(z.zone_nm, ' ', ''), biz_ns = REPLACE(z.biz_nm, ' ', ''),
                                   z.biz_lclas_nm, z.propel_pct, z.area_m2, has_geo = CASE WHEN z.geojson IS NOT NULL THEN 1 ELSE 0 END
                              FROM silver.redev_zone z WHERE z.is_current = 1""",
   [("present_sn", "text"), ("zone_nm", "text"), ("biz_nm", "text"), ("propel_nm", "text"), ("centroid_lat", D), ("centroid_lng", D),
    ("minx", D), ("miny", D), ("maxx", D), ("maxy", D), ("zone_ns", "text"), ("biz_ns", "text"),
    ("biz_lclas_nm", "text"), ("propel_pct", "int"), ("area_m2", D), ("has_geo", "int")], []),
  # 7 지하철역 — 역 이름마다 한 줄(노선 합치기 · 평균 좌표는 적재DB 가 계산)
  ("sg_subway", None, U + """SELECT s.sttn_nm, 노선 = STRING_AGG(s.line_nm, N' · ') WITHIN GROUP (ORDER BY s.line_nm), lat = AVG(s.lat), lon = AVG(s.lon)
                               FROM silver.subway_station s WHERE s.is_current = 1 AND s.lat IS NOT NULL GROUP BY s.sttn_nm""",
   [("sttn_nm", "text"), ("노선", "text"), ("lat", D), ("lon", D)], []),
  # 8 학교
  ("sg_school", None, U + """SELECT s.school_nm, s.school_se, 주소 = COALESCE(s.rdnmadr, s.lnmadr), s.lat, s.lon
                               FROM silver.school s WHERE s.is_current = 1 AND s.lat IS NOT NULL""",
   [("school_nm", "text"), ("school_se", "text"), ("주소", "text"), ("lat", D), ("lon", D)], [TRGM("school_nm")]),
  # 9 유치원
  ("sg_kinder", None, U + "SELECT k.kinder_nm, 주소 = k.addr, lat = k.lat, lon = k.lng FROM silver.kindergarten k WHERE k.lat IS NOT NULL",
   [("kinder_nm", "text"), ("주소", "text"), ("lat", D), ("lon", D)], []),
  # 10 학원 — 좌표 없는 것도 담는다(못 붙인 수를 센다)
  ("sg_academy", None, U + "SELECT a.aca_nm, a.realm_sc_nm, 주소 = a.road_addr, a.lat, a.lon FROM silver.academy a WHERE a.is_current = 1",
   [("aca_nm", "text"), ("realm_sc_nm", "text"), ("주소", "text"), ("lat", D), ("lon", D)], [TRGM("aca_nm")]),
  # 11 상가(61만) — 앞부분 일치만 → lower(이름) 앞부분 색인
  # ★ 적재DB 의 LIKE · = 는 너비도 무시한다(_AS 뒤에 _WS 없음): '제１GKI'(전각 1)가 '제1%' 에 걸린다 → NFKC + 소문자 키로 비교(10-25 대조에서 1건)
  ("sg_semas",
   "SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to), '/v2') FROM silver.semas_store",
   U + """SELECT m.bizes_nm, m.brch_nm, m.inds_scls_nm, 주소 = m.rdnm_adr, m.lat, m.lon, m.adong_nm, m.bizes_id
            FROM silver.semas_store m WHERE m.is_current = 1 AND m.lat IS NOT NULL""",
   [("bizes_nm", "text"), ("brch_nm", "text"), ("inds_scls_nm", "text"), ("주소", "text"), ("lat", D), ("lon", D), ("adong_nm", "text"),
    ("bizes_id", "text"), ("nm_key", "text")],
   ["(nm_key text_pattern_ops)"],
   ["UPDATE {t} SET nm_key = lower(normalize(bizes_nm, NFKC))"]),
  # 12 폐쇄 · 말소 대장
  ("sg_closed",
   """SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(site_key, 이름, 폐쇄구분, shter_day, 주용도, 총괄세대, plat_plc, lat, lng, now_complex_id, 동수, 지번짧게, 도로짧게)))
        FROM gold.closed_site""",
   U + """SELECT s.site_key, s.이름, 이름_ns = REPLACE(s.이름, ' ', ''), s.폐쇄구분, s.shter_day, s.주용도, s.총괄세대, s.plat_plc, s.lat, s.lng,
                 s.now_complex_id, s.동수, s.지번짧게, s.도로짧게
            FROM gold.closed_site s""",
   [("site_key", "text"), ("이름", "text"), ("이름_ns", "text"), ("폐쇄구분", "text"), ("shter_day", "text"), ("주용도", "text"), ("총괄세대", "int"),
    ("plat_plc", "text"), ("lat", D), ("lng", D), ("now_complex_id", "int"), ("동수", "int"), ("지번짧게", "text"), ("도로짧게", "text")],
   [TRGM('"이름_ns"'), '("지번짧게" text_pattern_ops)', '("도로짧게" text_pattern_ops)']),
  # 13 청약 공고 — 단지에 안 이어진 공고 · 지번(pnu)마다 묶음 키 g · 자리(필지 상자 가운데)는 적재DB 가 계산
  ("sg_applyhome", None, U + """
    SELECT p.house_manage_no, p.pblanc_no, p.house_nm, name_ns = REPLACE(p.house_nm, ' ', ''), p.공고종류, p.rcrit_pblanc_de, p.hssply_adres, p.tot_suply,
           g = COALESCE(p.pnu, 'H' + p.house_manage_no),
           lat = (cp.bbox_miny + cp.bbox_maxy) / 2, lng = (cp.bbox_minx + cp.bbox_maxx) / 2
      FROM silver.applyhome_pblanc p
      LEFT JOIN silver.cadastral_parcel cp ON cp.pnu = p.pnu AND cp.is_current = 1
     WHERE NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no)""",
   [("house_manage_no", "text"), ("pblanc_no", "text"), ("house_nm", "text"), ("name_ns", "text"), ("공고종류", "text"), ("rcrit_pblanc_de", "text"),
    ("hssply_adres", "text"), ("tot_suply", "int"), ("g", "text"), ("lat", D), ("lng", D)], []),
  # 14 바뀐 행정동 — 검색어와 상관없는 부분(옛 동 → 새 동 · 상자 · adm_cd)을 통째로. 날짜는 'YYYY-MM-DD' 글자로(화면이 UTC 로 읽는다)
  ("sg_hdong_old", None, U + """
    DECLARE @최신분기 DATE = (SELECT MAX(개정일자) FROM silver.region_link_snap WHERE 완전 = 1);
    SELECT g.행정동코드, g.시도명, g.시군구명, g.행정동명, 마지막 = CONVERT(CHAR(10), g.마지막, 23), 후분기 = CONVERT(CHAR(10), g.후분기, 23),
           g.새이름, g.새코드, g.새수, g.새현행아님,
           adm_cd = CASE WHEN g.새수 = 1 THEN (SELECT TOP 1 a.adm_cd_sgis FROM silver.adm_boundary a
                                                JOIN silver.region_link l ON l.행정구역코드 = a.adm_cd_sgis AND l.행정동코드 = g.새코드 AND l.개정일자 = @최신분기) END,
           b.minx, b.miny, b.maxx, b.maxy
      FROM (SELECT o.행정동코드, o.시도명, o.시군구명, o.행정동명, 마지막 = o.마지막본분기, 후분기 = MAX(c.후분기),
                   새이름 = STRING_AGG(n.행정동명, N' · ') WITHIN GROUP (ORDER BY n.행정동명),
                   새코드 = MIN(c.새코드), 새수 = COUNT(*), 새현행아님 = SUM(CASE WHEN n.현행 = 0 THEN 1 ELSE 0 END)
              FROM gold.region_hdong o
              JOIN gold.region_hdong_change c ON c.옛코드 = o.행정동코드 AND c.새코드 IS NOT NULL
              JOIN gold.region_hdong n ON n.행정동코드 = c.새코드
             WHERE o.현행 = 0 AND LEFT(o.행정동코드, 5) IN (SELECT sgg_cd FROM meta.coverage WHERE 자료 = N'단지')
               AND NOT EXISTS (SELECT 1 FROM gold.region_hdong z WHERE z.현행 = 1 AND z.시군구명 = o.시군구명 AND z.행정동명 = o.행정동명)
             GROUP BY o.행정동코드, o.시도명, o.시군구명, o.행정동명, o.마지막본분기) g
      OUTER APPLY (SELECT minx = MIN(lb.bbox_minx), miny = MIN(lb.bbox_miny), maxx = MAX(lb.bbox_maxx), maxy = MAX(lb.bbox_maxy)
                     FROM silver.region_link l JOIN silver.lawd_boundary lb ON lb.lawd_cd = l.법정동코드 AND lb.is_current = 1
                    WHERE l.개정일자 = @최신분기
                      AND l.행정동코드 IN (SELECT c2.새코드 FROM gold.region_hdong_change c2 WHERE c2.옛코드 = g.행정동코드)) b""",
   [("행정동코드", "text"), ("시도명", "text"), ("시군구명", "text"), ("행정동명", "text"), ("마지막", "text"), ("후분기", "text"),
    ("새이름", "text"), ("새코드", "text"), ("새수", "int"), ("새현행아님", "int"), ("adm_cd", "text"),
    ("minx", D), ("miny", D), ("maxx", D), ("maxy", D)], []),

  # ===== 목록 검색(/api/complexes?q) =====
  # 단지 목록 칸 그대로(gold.v_complex_map) + 폐쇄 수 · 실거래이름(보여 줄 때 붙임) · rep_pnu(옛 행정동 → 법정동 범위)
  ("sg_cmap", None, U + """
    SELECT v.complex_id, v.complex_nm, v.grouping_rule, v.has_recap, v.rep_jibun, v.rep_plat_plc, v.rep_road_addr, v.lawd_nm,
           v.dong_cnt, v.pnu_cnt, v.parcel_hit, v.hhld_cnt_sum, v.tot_area_sum, v.oldest_use_apr, v.jiga_avg, v.centroid_lat, v.centroid_lng,
           v.rep_pnu, 폐쇄 = ISNULL(f.n, 0), al.실거래이름
      FROM gold.v_complex_map v
      LEFT JOIN (SELECT cp.complex_id, n = COUNT(*) FROM gold.complex_pnu cp JOIN gold.closed_site s ON s.pnu = cp.pnu GROUP BY cp.complex_id) f
             ON f.complex_id = v.complex_id
      LEFT JOIN gold.complex_alias al ON al.complex_id = v.complex_id""",
   [("complex_id", "int PRIMARY KEY"), ("complex_nm", "text"), ("grouping_rule", "text"), ("has_recap", "boolean"), ("rep_jibun", "text"),
    ("rep_plat_plc", "text"), ("rep_road_addr", "text"), ("lawd_nm", "text"), ("dong_cnt", "int"), ("pnu_cnt", "int"), ("parcel_hit", "int"),
    ("hhld_cnt_sum", "int"), ("tot_area_sum", D), ("oldest_use_apr", "text"), ("jiga_avg", D), ("centroid_lat", D), ("centroid_lng", D),
    ("rep_pnu", "text"), ("폐쇄", "int"), ("실거래이름", "text"), ("s_all", "text")],
   # s_all = 이름 · 지번주소 · 도로명을 한 칸에(소문자) — 두 글자 검색은 trigram 이 못 받쳐 57만 줄을 훑는데, ILIKE 세 칸보다 LIKE 한 칸이 몇 배 빠르다
   #   (사이에 chr(1) — 검색어에 그 글자가 없으니 칸을 넘어 걸리지 않는다). 10-25 '은평' 2.6초(3초 제한 턱밑).
   [TRGM("s_all"), "(dong_cnt DESC NULLS LAST, pnu_cnt DESC NULLS LAST, complex_id)", "(left(rep_pnu, 10))"],
   ["UPDATE {t} SET s_all = lower(coalesce(complex_nm, '') || chr(1) || coalesce(rep_plat_plc, '') || chr(1) || coalesce(rep_road_addr, ''))"]),
  # 부속지번(건축물대장 관련지번) → 단지
  ("sg_atch", None, U + """SELECT cb.complex_id, a.plat_plc FROM silver.bld_atch_jibun a JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = a.mgm_bldrgst_pk
                             WHERE a.is_current = 1""",
   [("complex_id", "int"), ("plat_plc", "text")], [TRGM("plat_plc")]),
  # 옛 행정동 → 새 행정동 쌍(목록 검색의 '바뀜') · 그 새 동이 걸친 법정동
  ("sg_hdong_pair", None, U + """
    SELECT o.행정동코드, o.시군구명, o.행정동명, 마지막 = CONVERT(CHAR(10), o.마지막본분기, 23), 후분기 = CONVERT(CHAR(10), c.후분기, 23),
           c.새코드, 새이름 = n.행정동명, 새현행 = n.현행
      FROM gold.region_hdong o
      JOIN gold.region_hdong_change c ON c.옛코드 = o.행정동코드 AND c.새코드 IS NOT NULL
      JOIN gold.region_hdong n ON n.행정동코드 = c.새코드
     WHERE o.현행 = 0 AND LEFT(o.행정동코드, 5) IN (SELECT sgg_cd FROM meta.coverage WHERE 자료 = N'단지')
       AND NOT EXISTS (SELECT 1 FROM gold.region_hdong z WHERE z.현행 = 1 AND z.시군구명 = o.시군구명 AND z.행정동명 = o.행정동명)""",
   [("행정동코드", "text"), ("시군구명", "text"), ("행정동명", "text"), ("마지막", "text"), ("후분기", "text"), ("새코드", "text"), ("새이름", "text"),
    ("새현행", "boolean")], []),
  ("sg_hdong_plaw", None, U + """
    DECLARE @최신분기 DATE = (SELECT MAX(개정일자) FROM silver.region_link_snap WHERE 완전 = 1);
    SELECT DISTINCT o.행정동명, c.옛코드, l.법정동코드, l.법정동명
      FROM gold.region_hdong o
      JOIN gold.region_hdong_change c ON c.옛코드 = o.행정동코드 AND c.새코드 IS NOT NULL
      JOIN silver.region_link l ON l.행정동코드 = c.새코드 AND l.개정일자 = @최신분기
     WHERE o.현행 = 0 AND LEFT(o.행정동코드, 5) IN (SELECT sgg_cd FROM meta.coverage WHERE 자료 = N'단지')
       AND NOT EXISTS (SELECT 1 FROM gold.region_hdong z WHERE z.현행 = 1 AND z.시군구명 = o.시군구명 AND z.행정동명 = o.행정동명)""",
   [("행정동명", "text"), ("옛코드", "text"), ("법정동코드", "text"), ("법정동명", "text")], []),
]
