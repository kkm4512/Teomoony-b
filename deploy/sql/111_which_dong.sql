/* 111_which_dong : 11290/10700 이 정말 돈암동인가 (읽기 전용) 2026-10-18
   ★ 내가 '돈암동=10700' 을 추측으로 썼다. 코드는 실측한다 — 정책 7장. */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 1. 성북구(11290) 법정동 코드표 ---';
SELECT bjdong_cd, 법정동 = bjdong_nm FROM meta.lawd_code
 WHERE sgg_cd='11290' ORDER BY bjdong_cd;
GO
PRINT '--- 2. 57232 브라운스톤 돈암은 어느 법정동인가 ---';
SELECT complex_id, complex_nm, sigungu_cd, bjdong_cd, rep_pnu, rep_plat_plc,
       dong_cnt, hhld_cnt_sum
  FROM gold.complex WHERE complex_id = 57232;
GO
PRINT '--- 3. 성북구에서 ext 축이 들어와 있는 법정동 ---';
SELECT bjdong_cd, expos=COUNT(*) FROM silver.bld_expos
 WHERE is_current=1 AND sigungu_cd='11290' GROUP BY bjdong_cd ORDER BY bjdong_cd;
GO
PRINT '--- 4. 그 법정동들의 적재 기록 ---';
SELECT r.scope_key, s.operation, r.run_mode, r.status, r.req_count, r.row_count, r.started_at
  FROM meta.ingest_run r LEFT JOIN meta.api_source s ON s.source_id=r.source_id
 WHERE r.scope_key LIKE '11290/%' AND s.operation IN
       ('getBrExposInfo','getBrFlrOulnInfo','getBrHsprcInfo')
 ORDER BY r.scope_key, r.started_at;
GO
