# -*- coding: utf-8 -*-
"""남은 넷(2026-10-25 사장님 "2번 ㄱㄱ") — 지금 위치 지역 이름(/api/areas/here) · 내 위치 주변 단지(/api/complexes/near) · 청약 핀(/api/applyhome/pins) 의 원천.
★ 도형은 적재DB 가 가진 그대로(geom.STAsText() — 적재 때 MakeValid 한 것)를 PostGIS 로 옮긴다 → 안에 드는지(STContains) 판정이 같은 도형으로 된다.
★ 청약 핀의 '셈'(안 이어진 공고 · 자리 없는 공고 수)은 bbox 와 상관없는 전체 수라 적재DB 가 계산해 한 줄로."""
D = "double precision"
U = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;\n"
GEOM = ["ALTER TABLE {t} ADD COLUMN g geometry", "UPDATE {t} SET g = ST_GeomFromText(wkt, 4326)", "ALTER TABLE {t} DROP COLUMN wkt"]

MISC = [
  # 행정동(최신 해) — 시군구 다수결(sgg_cd) 은 적재DB 의 옛 질의(시군구다수결)와 같은 계산
  ("here_adm", None, U + """
    WITH m AS (
      SELECT s = LEFT(adm_cd_sgis, 5), mo = LEFT(adm_cd_mois, 5), n = COUNT(*)
        FROM silver.adm_boundary
       WHERE year = (SELECT MAX(year) FROM silver.adm_boundary) AND adm_cd_mois IS NOT NULL AND 연결비율 >= 90
       GROUP BY LEFT(adm_cd_sgis, 5), LEFT(adm_cd_mois, 5)),
    sm AS (SELECT s, mo FROM (SELECT *, rn = ROW_NUMBER() OVER (PARTITION BY s ORDER BY n DESC, mo) FROM m) x WHERE rn = 1)
    SELECT cd = a.adm_cd_sgis, 이름 = a.emd_nm, sgg_cd = sm.mo,
           minx = a.bbox_minx, miny = a.bbox_miny, maxx = a.bbox_maxx, maxy = a.bbox_maxy, wkt = a.geom.STAsText()
      FROM silver.adm_boundary a LEFT JOIN sm ON sm.s = LEFT(a.adm_cd_sgis, 5)
     WHERE a.year = (SELECT MAX(year) FROM silver.adm_boundary)""",
   [("cd", "text"), ("이름", "text"), ("sgg_cd", "text"), ("minx", D), ("miny", D), ("maxx", D), ("maxy", D), ("wkt", "text")],
   ["USING gist (g)"], GEOM),
  ("here_lawd",
   "SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.lawd_boundary",
   U + """SELECT cd = b.lawd_cd, 이름 = b.emd_nm, sgg_cd = LEFT(b.lawd_cd, 5),
                 minx = b.bbox_minx, miny = b.bbox_miny, maxx = b.bbox_maxx, maxy = b.bbox_maxy, wkt = b.geom.STAsText()
            FROM silver.lawd_boundary b WHERE b.is_current = 1""",
   [("cd", "text"), ("이름", "text"), ("sgg_cd", "text"), ("minx", D), ("miny", D), ("maxx", D), ("maxy", D), ("wkt", "text")],
   ["USING gist (g)"], GEOM),
  # 내 위치 주변 — 옛 질의는 gold.complex 전부(합쳐진 것 포함) · 법정동 이름은 meta.lawd_code 조인 그대로
  ("near",
   """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(complex_id, complex_nm, has_recap, dong_cnt, hhld_cnt_sum, pnu_cnt,
                                                               centroid_lat, centroid_lng, rep_plat_plc, rep_road_addr, rep_pnu))) FROM gold.complex), '|',
                    (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(lawd_cd, full_nm))) FROM meta.lawd_code))""",
   U + """SELECT c.complex_id, c.complex_nm, c.has_recap, c.dong_cnt, c.hhld_cnt_sum, c.pnu_cnt, c.centroid_lat, c.centroid_lng,
                 c.rep_plat_plc, c.rep_road_addr, lawd_nm = l.full_nm
            FROM gold.complex c LEFT JOIN meta.lawd_code l ON l.lawd_cd = LEFT(c.rep_pnu, 10)
           WHERE c.centroid_lat IS NOT NULL""",
   [("complex_id", "int"), ("complex_nm", "text"), ("has_recap", "boolean"), ("dong_cnt", "int"), ("hhld_cnt_sum", "int"), ("pnu_cnt", "int"),
    ("centroid_lat", D), ("centroid_lng", D), ("rep_plat_plc", "text"), ("rep_road_addr", "text"), ("lawd_nm", "text")],
   ["(centroid_lng, centroid_lat)"]),
  # 청약 핀 — 단지에 안 이어진 공고 · 지금 필지 상자 가운데(필지 없는 공고는 핀이 없다 = 옛 질의의 JOIN)
  ("apin", None, U + """
    SELECT p.house_manage_no, p.pblanc_no, p.house_nm, p.공고종류, p.house_dtl_secd_nm, p.tot_suply, p.rcrit_pblanc_de, p.mvn_prearnge_ym, p.pnu,
           lat = (cp.bbox_miny + cp.bbox_maxy) / 2, lng = (cp.bbox_minx + cp.bbox_maxx) / 2
      FROM silver.applyhome_pblanc p
      JOIN silver.cadastral_parcel cp ON cp.pnu = p.pnu AND cp.is_current = 1
     WHERE NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no)""",
   [("house_manage_no", "text"), ("pblanc_no", "text"), ("house_nm", "text"), ("공고종류", "text"), ("house_dtl_secd_nm", "text"), ("tot_suply", "int"),
    ("rcrit_pblanc_de", "text"), ("mvn_prearnge_ym", "text"), ("pnu", "text"), ("lat", D), ("lng", D)], []),
  ("apin_cnt", None, U + """
    SELECT 안이어짐 = COUNT(DISTINCT x.house_manage_no),
           자리없음 = COUNT(DISTINCT CASE WHEN x.자리 = 0 THEN x.house_manage_no END)
      FROM (SELECT p.house_manage_no,
                   자리 = CASE WHEN p.pnu IS NOT NULL AND EXISTS (SELECT 1 FROM silver.cadastral_parcel cp WHERE cp.pnu = p.pnu AND cp.is_current = 1)
                               THEN 1 ELSE 0 END
              FROM silver.applyhome_pblanc p
             WHERE NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no)) x""",
   [("안이어짐", "int"), ("자리없음", "int")], []),
]

# ---- 11-01 사장님 "서비스 DB 로 분리하는 건 해야 하는 거니까 해봐" — 1묶음: 지도 위 남은 bbox 층 넷 ----
# 화면 질의(server.js /api/prebuilds · /api/houseplans · /api/redev · /api/zones)에서 bbox 조건 · TOP 만 뺀 그대로. 형은 화면 응답과 같게(float · char 그대로).
MISC += [
  ("prebuild",
   """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(pk, 이름, 대지위치, 용도, 세대, 호, 착공일, lat, lng))) FROM gold.pre_build), '|',
                    (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(complex_id, 종류, 원문pk))) FROM gold.pre_complex))""",
   U + """SELECT b.pk, b.이름, b.대지위치, b.용도, b.세대, b.호, b.착공일, b.lat, b.lng, g.complex_id
            FROM gold.pre_build b LEFT JOIN gold.pre_complex g ON g.종류 = 'p' AND g.원문pk = b.pk""",
   [("pk", "text"), ("이름", "text"), ("대지위치", "text"), ("용도", "text"), ("세대", "int"), ("호", "int"), ("착공일", "text"),
    ("lat", D), ("lng", D), ("complex_id", "int")],
   ["(lng, lat)"]),
  ("houseplan",
   """SELECT CONCAT((SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(hp_pk, 이름, 대지위치, 세대, 주건축물수, 용도, 승인일, 착공예정일, 착공일,
                                                                    사용검사예정일, 상태, lat, lng, 위치근거))) FROM gold.house_plan), '|',
                    (SELECT CONCAT(COUNT_BIG(*), '/', CHECKSUM_AGG(CHECKSUM(complex_id, 종류, 원문pk))) FROM gold.pre_complex))""",
   U + """SELECT h.hp_pk, h.이름, h.대지위치, h.세대, h.주건축물수, h.용도, h.승인일, h.착공예정일, h.착공일, h.사용검사예정일, h.상태, h.lat, h.lng, h.위치근거,
                 complex_id = (SELECT g.complex_id FROM gold.pre_complex g WHERE g.종류 = 'h' AND g.원문pk = h.hp_pk)
            FROM gold.house_plan h WHERE h.상태 <> N'완공 대장 있음'""",
   [("hp_pk", "text"), ("이름", "text"), ("대지위치", "text"), ("세대", "int"), ("주건축물수", "int"), ("용도", "text"), ("승인일", "text"),
    ("착공예정일", "text"), ("착공일", "text"), ("사용검사예정일", "text"), ("상태", "text"), ("lat", D), ("lng", D), ("위치근거", "text"),
    ("complex_id", "int")],
   ["(lng, lat)"]),
  # 정비사업 구역 겹쳐보기 — 재개발(reb) · 그 밖(etc) 가름은 화면 쪽(svc.js)이 server.js 와 **같은 목록**으로 한다
  ("redev_zone",
   "SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.redev_zone",
   U + """SELECT present_sn, zone_nm, biz_lclas_nm, biz_nm, propel_cd, propel_nm, propel_pct, propel_fam, area_m2, geojson,
                 bbox_minx, bbox_miny, bbox_maxx, bbox_maxy
            FROM silver.redev_zone WHERE is_current = 1 AND geojson IS NOT NULL""",
   [("present_sn", "text"), ("zone_nm", "text"), ("biz_lclas_nm", "text"), ("biz_nm", "text"), ("propel_cd", "text"), ("propel_nm", "text"),
    ("propel_pct", "int"), ("propel_fam", "text"), ("area_m2", D), ("geojson", "text"), ("minx", D), ("miny", D), ("maxx", D), ("maxy", D)],
   ["USING gist (box(point(minx, miny), point(maxx, maxy)))"]),
  ("landzone",
   "SELECT CONCAT(COUNT_BIG(*), '/', MAX(valid_from), '/', MAX(valid_to)) FROM silver.land_use_zone",
   U + """SELECT uname, dyear, dnum, sigg_name, area_m2_approx, geojson,
                 grp = CASE WHEN uname LIKE N'%주거지역' THEN '주거' WHEN uname LIKE N'%상업지역' THEN '상업'
                            WHEN uname LIKE N'%공업지역' THEN '공업' WHEN uname LIKE N'%녹지지역' THEN '녹지' ELSE NULL END,
                 bbox_minx, bbox_miny, bbox_maxx, bbox_maxy
            FROM silver.land_use_zone
           WHERE is_current = 1 AND geojson IS NOT NULL AND LTRIM(ISNULL(uname, '')) <> ''""",
   [("uname", "text"), ("dyear", "text"), ("dnum", "text"), ("sigg_name", "text"), ("area_m2_approx", D), ("geojson", "text"), ("grp", "text"),
    ("minx", D), ("miny", D), ("maxx", D), ("maxy", D)],
   ["USING gist (box(point(minx, miny), point(maxx, maxy)))"]),
]
