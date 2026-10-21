/* 150. usp_refresh_complex_building 을 공간교차로 바꾼다 (2026-10-18)
   ★ 왜
     11-26 에서 건물 잇는 규칙을 PNU 동일 -> **필지 폴리곤 공간교차** 로 바꿨다
     (재개발 합필 때문에 PNU 가 안 맞는다). 그런데 화면(server.js)만 바꾸고
     **이 프로시저는 안 바꿨다.** 그래서 같은 화면이 모순을 말했다 -
     지도는 외곽선 34개를 그리는데 옆에는 '대장 동 / 건물 = 50 / 0' 이라고.
     적재 요약의 '건물이 붙은 단지 N/M' 도 같은 거짓말을 했다.
     측정(149): 총괄단지 2,788 중 **거짓0 191개, 수가 다른 것 1,068개(38%)**.
   ★ 화면과 **똑같은 조인**을 쓴다. 두 경로가 다른 규칙을 쓰면 또 갈라진다.
   ★ LEFT JOIN 으로 **줄어드는 쪽도 반영**한다. 예전 규칙이 과다 계산한
     단지를 그대로 두면 이번엔 반대로 거짓말이 남는다. */
SET NOCOUNT ON;

PRINT '--- 전 (총괄표제부 단지) ---';
SELECT 단지 = COUNT(*), 건물있음 = SUM(CASE WHEN ISNULL(bld_cnt,0) > 0 THEN 1 ELSE 0 END),
       건물합 = SUM(ISNULL(bld_cnt,0))
  FROM gold.complex WHERE is_active = 1 AND has_recap = 1;
GO

ALTER PROCEDURE gold.usp_refresh_complex_building
AS
BEGIN
    SET NOCOUNT ON;
    /* 화면(server.js /api/complexes/:id/buildings)과 같은 조인이다.
       bbox 로 먼저 거르고 STIntersects 로 확정한다. */
    WITH b AS (
        SELECT cp.complex_id,
               bld_cnt   = COUNT(DISTINCT f.bd_mgt_sn),
               max_floor = MAX(f.gro_flo_co)
          FROM gold.complex_pnu cp
          JOIN silver.cadastral_parcel p
            ON p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL
          JOIN silver.building_footprint f
            ON f.is_current = 1 AND f.geom IS NOT NULL
           AND f.bbox_minx <= p.bbox_maxx AND f.bbox_maxx >= p.bbox_minx
           AND f.bbox_miny <= p.bbox_maxy AND f.bbox_maxy >= p.bbox_miny
           AND f.geom.STIntersects(p.geom) = 1
         GROUP BY cp.complex_id
    )
    UPDATE c
       SET c.bld_cnt    = ISNULL(b.bld_cnt, 0),
           c.max_floor  = b.max_floor,
           c.updated_at = SYSDATETIME()
      FROM gold.complex c
      LEFT JOIN b ON b.complex_id = c.complex_id
     WHERE EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.complex_id = c.complex_id);
END
GO

PRINT '--- 다시 계산 ---';
DECLARE @t0 DATETIME2 = SYSDATETIME();
EXEC gold.usp_refresh_complex_building;
PRINT CONCAT('  걸린 시간(초) = ', DATEDIFF(SECOND, @t0, SYSDATETIME()));
GO

PRINT '';
PRINT '--- 후 (총괄표제부 단지) ---';
SELECT 단지 = COUNT(*), 건물있음 = SUM(CASE WHEN ISNULL(bld_cnt,0) > 0 THEN 1 ELSE 0 END),
       건물합 = SUM(ISNULL(bld_cnt,0))
  FROM gold.complex WHERE is_active = 1 AND has_recap = 1;

PRINT '';
PRINT '--- 구별 ---';
SELECT 구 = sigungu_cd, 단지 = COUNT(*),
       건물있음 = SUM(CASE WHEN ISNULL(bld_cnt,0) > 0 THEN 1 ELSE 0 END),
       없음 = SUM(CASE WHEN ISNULL(bld_cnt,0) = 0 THEN 1 ELSE 0 END)
  FROM gold.complex WHERE is_active = 1 AND has_recap = 1
 GROUP BY sigungu_cd ORDER BY sigungu_cd;

PRINT '';
PRINT '--- 응암동 큰 단지 확인 ---';
SELECT TOP 10 complex_id, 단지명 = LEFT(complex_nm, 24), 동수 = dong_cnt,
       세대 = hhld_cnt_sum, bld_cnt, max_floor
  FROM gold.complex
 WHERE is_active = 1 AND has_recap = 1 AND rep_plat_plc LIKE N'%응암동%'
 ORDER BY hhld_cnt_sum DESC;

PRINT '';
PRINT '--- 은뜨락(96758) 은 왜 0 인가 ---';
SELECT cp.pnu,
       필지있나 = (SELECT COUNT(*) FROM silver.cadastral_parcel p
                    WHERE p.pnu = cp.pnu AND p.is_current = 1),
       geom있나 = (SELECT COUNT(*) FROM silver.cadastral_parcel p
                    WHERE p.pnu = cp.pnu AND p.is_current = 1 AND p.geom IS NOT NULL),
       bbox     = (SELECT TOP 1 CONCAT(FORMAT(p.bbox_minx,'0.0000'), ' ',
                          FORMAT(p.bbox_miny,'0.0000'), ' ~ ',
                          FORMAT(p.bbox_maxx,'0.0000'), ' ',
                          FORMAT(p.bbox_maxy,'0.0000'))
                     FROM silver.cadastral_parcel p
                    WHERE p.pnu = cp.pnu AND p.is_current = 1),
       그bbox안_건물 = (SELECT COUNT(*)
                          FROM silver.cadastral_parcel p
                          JOIN silver.building_footprint f
                            ON f.is_current = 1
                           AND f.bbox_minx <= p.bbox_maxx AND f.bbox_maxx >= p.bbox_minx
                           AND f.bbox_miny <= p.bbox_maxy AND f.bbox_maxy >= p.bbox_miny
                         WHERE p.pnu = cp.pnu AND p.is_current = 1)
  FROM gold.complex_pnu cp WHERE cp.complex_id = 96758;
