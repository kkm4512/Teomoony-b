/* ============================================================
   110_donam_prov : 돈암동에 이미 있는 행이 어디서 왔나 (읽기 전용) 2026-10-18
   108 은 컬럼을 추측해서 틀렸다. 109 로 실제 컬럼을 확인하고 다시 쓴다.
     · bld_flr_outline 에는 sigungu_cd/bjdong_cd/pnu 가 **없다** -> basis 로 조인
     · meta.ingest_run 에는 operation 이 없다 -> api_source 로 조인
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. 돈암동 ext 축 행 수 + 지번 분포 ---';
SELECT ax='expos', n=COUNT(*), 지번수=COUNT(DISTINCT pnu)
  FROM silver.bld_expos WHERE is_current=1 AND sigungu_cd='11290' AND bjdong_cd='10700'
UNION ALL
SELECT 'hsprc', COUNT(*), COUNT(DISTINCT pnu)
  FROM silver.bld_hsprc WHERE is_current=1 AND sigungu_cd='11290' AND bjdong_cd='10700'
UNION ALL
SELECT 'flr', COUNT(*), COUNT(DISTINCT b.pnu)
  FROM silver.bld_flr_outline f
  JOIN silver.bld_basis_outline b
    ON b.mgm_bldrgst_pk = f.mgm_bldrgst_pk AND b.is_current=1
 WHERE f.is_current=1 AND b.sigungu_cd='11290' AND b.bjdong_cd='10700';
PRINT '  지번수가 1~2 뿐이면 번지 probe 다 -> 이어받기를 쓰면 구멍이 난다.';
GO

PRINT '--- 2. 돈암동 expos 의 지번별 분포 (상위 10) ---';
SELECT TOP 10 pnu, 행수=COUNT(*), 동=COUNT(DISTINCT dong_nm), 호=COUNT(DISTINCT ho_nm)
  FROM silver.bld_expos
 WHERE is_current=1 AND sigungu_cd='11290' AND bjdong_cd='10700'
 GROUP BY pnu ORDER BY COUNT(*) DESC;
GO

PRINT '--- 3. 적재 기록 (run_mode 포함) ---';
SELECT s.operation, r.run_mode, r.status, r.req_count, r.row_count, r.started_at,
       LEFT(ISNULL(r.err_msg,''),50) AS err
  FROM meta.ingest_run r
  LEFT JOIN meta.api_source s ON s.source_id = r.source_id
 WHERE r.scope_key = '11290/10700'
 ORDER BY r.started_at;
PRINT '  기록이 없는데 1 절에 데이터가 있으면 = 기록 밖에서 들어온 것이다.';
GO

PRINT '--- 4. 돈암동 대장 규모 (얼마나 받아야 하나) ---';
SELECT 기본개요=COUNT(*), 지번수=COUNT(DISTINCT pnu)
  FROM silver.bld_basis_outline
 WHERE is_current=1 AND sigungu_cd='11290' AND bjdong_cd='10700';
GO
