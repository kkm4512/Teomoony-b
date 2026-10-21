SET NOCOUNT ON;
/* 세 시군구의 축별 적재 현황. 11110 종로 · 11290 성북(장위동만 목표) · 11380 은평 */
WITH s AS (SELECT sgg FROM (VALUES ('11110'),('11290'),('11380')) v(sgg))
SELECT 축='① 법정동코드',   s.sgg, 건수=(SELECT COUNT(*) FROM meta.lawd_code  WHERE sgg_cd=s.sgg) FROM s
UNION ALL SELECT '② 기본개요', s.sgg, (SELECT COUNT(*) FROM silver.bld_basis_outline WHERE is_current=1 AND sigungu_cd=s.sgg) FROM s
UNION ALL SELECT '② 표제부',   s.sgg, (SELECT COUNT(*) FROM silver.bld_title        WHERE is_current=1 AND sigungu_cd=s.sgg) FROM s
UNION ALL SELECT '② 총괄표제부',s.sgg,(SELECT COUNT(*) FROM silver.bld_recap_title  WHERE is_current=1 AND sigungu_cd=s.sgg) FROM s
UNION ALL SELECT '③ 전유부(호)',s.sgg,(SELECT COUNT(*) FROM silver.bld_expos       WHERE is_current=1 AND sigungu_cd=s.sgg) FROM s
UNION ALL SELECT '③ 주택가격', s.sgg, (SELECT COUNT(*) FROM silver.bld_hsprc        WHERE is_current=1 AND sigungu_cd=s.sgg) FROM s
UNION ALL SELECT '④ 필지',     s.sgg, (SELECT COUNT(*) FROM silver.cadastral_parcel WHERE is_current=1 AND LEFT(lawd_cd,5)=s.sgg) FROM s
UNION ALL SELECT '⑤ 건물외곽선',s.sgg,(SELECT COUNT(*) FROM silver.building_footprint WHERE is_current=1 AND LEFT(lawd_cd,5)=s.sgg) FROM s
UNION ALL SELECT '⑥ 법정동경계',s.sgg,(SELECT COUNT(*) FROM silver.lawd_boundary    WHERE sgg_cd=s.sgg) FROM s
UNION ALL SELECT '⑦ 실거래',   s.sgg, (SELECT COUNT(*) FROM silver.rtms_trade       WHERE sgg_cd=s.sgg) FROM s
UNION ALL SELECT '⑧ 건축인허가',s.sgg,(SELECT COUNT(*) FROM silver.arch_permit      WHERE is_current=1 AND sigungu_cd=s.sgg) FROM s
UNION ALL SELECT '⑨ K-apt단지',s.sgg, (SELECT COUNT(*) FROM silver.kapt_complex     WHERE is_current=1 AND LEFT(bjd_code,5)=s.sgg) FROM s
UNION ALL SELECT '⑨ 관리비',   s.sgg, (SELECT COUNT(*) FROM silver.kapt_cost c
                                        WHERE EXISTS (SELECT 1 FROM silver.kapt_complex k
                                                       WHERE k.kapt_code=c.kapt_code AND k.is_current=1
                                                         AND LEFT(k.bjd_code,5)=s.sgg)) FROM s
ORDER BY 1, 2;

PRINT '';
PRINT '--- 단지 수 / 화면에 뜨는 것 ---';
SELECT sigungu_cd, 단지=COUNT(*),
       총괄있음=SUM(CASE WHEN has_recap=1 THEN 1 ELSE 0 END),
       좌표있음=SUM(CASE WHEN centroid_lat IS NOT NULL THEN 1 ELSE 0 END)
  FROM gold.complex WHERE sigungu_cd IN ('11110','11290','11380')
 GROUP BY sigungu_cd ORDER BY 1;
