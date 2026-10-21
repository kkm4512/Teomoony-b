/* 138_timing : 단지 상세가 왜 1.9초인가 (읽기 전용) 2026-10-18
   단지 크기와 무관하게 일정한 지연이다 -> "그 단지 때문" 이 아니다.
   짐작을 두 번 했고 두 번 다 틀렸다(공간조인 / 전용면적 서브쿼리).
   이번엔 잰다. */
USE Teomoony;
GO
SET NOCOUNT ON;
SET STATISTICS TIME ON;
GO
PRINT '=== A. 새로 만든 뷰 gold.v_complex_permit ===';
SELECT COUNT(*) FROM gold.v_complex_permit WHERE complex_id = 103835;
GO
PRINT '=== B. 옛 방식 (PNU 직접 조인) ===';
SELECT COUNT(*) FROM gold.complex_pnu cp
  JOIN silver.arch_permit a ON a.pnu = cp.pnu AND a.is_current=1
 WHERE cp.complex_id = 103835;
GO
PRINT '=== C. hos (OUTER APPLY 판) ===';
SELECT COUNT(*) FROM gold.v_complex_ho h
  LEFT JOIN gold.v_complex_ho_price p ON p.호PK = h.호PK
  OUTER APPLY (SELECT s=SUM(a2.area) FROM silver.bld_expos_pubuse_area a2
                WHERE a2.mgm_bldrgst_pk=h.호PK AND a2.is_current=1
                  AND a2.expos_pubuse_gb_cd='1') ea
 WHERE h.complex_id = 103835;
GO
PRINT '=== D. 공간조인 건물 ===';
SELECT COUNT(DISTINCT f.bd_mgt_sn) FROM gold.complex_pnu cp
  JOIN silver.cadastral_parcel p ON p.pnu=cp.pnu AND p.is_current=1 AND p.geom IS NOT NULL
  JOIN silver.building_footprint f ON f.is_current=1 AND f.geom IS NOT NULL
   AND f.bbox_minx<=p.bbox_maxx AND f.bbox_maxx>=p.bbox_minx
   AND f.bbox_miny<=p.bbox_maxy AND f.bbox_maxy>=p.bbox_miny
   AND f.geom.STIntersects(p.geom)=1
 WHERE cp.complex_id = 103835;
GO
SET STATISTICS TIME OFF;
GO
