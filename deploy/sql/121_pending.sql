USE Teomoony;
GO
SET NOCOUNT ON;
GO
PRINT '--- 그룹별 남은 일 (TODO/RETRY) ---';
SELECT grp, 상태, 단위수 = COUNT(*)
  FROM meta.v_load_plan
 WHERE 상태 <> 'DONE'
 GROUP BY grp, 상태 ORDER BY grp, 상태;
PRINT '--- 선행 미충족이 섞여 있나 ---';
SELECT 선행, 건수 = COUNT(*) FROM meta.v_load_plan WHERE 상태 <> 'DONE' GROUP BY 선행;
GO
