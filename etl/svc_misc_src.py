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
