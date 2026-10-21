/* ============================================================
   116_exar_scope : 전유공용면적을 어디까지 넓힐까 (읽기 전용)  2026-10-18

   장위동(11290/13800)·수색동(11380/10100)은 끝났다. 다음은 은평(11380)과
   종로(11110)인데, **얼마나 드는지를 먼저 잰다.**
   실측 비율: 전유공용 7,658건 / 1,102호 = 6.95건/호, 100건/페이지.
   -> 호출수 ~= ceil(호수 * 6.95 / 100) + 번지당 오버헤드.
   지난번 전체 범위 추산이 19,026 콜(약 이틀)이었다. 그 숫자를 다시 만든다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. 지금 exar 가 켜져 있는 법정동 ---';
SELECT sigungu_cd, bjdong_cd, ops, enabled, note
  FROM meta.load_target
 WHERE ops LIKE '%exar%'
 ORDER BY sigungu_cd, bjdong_cd;
GO

PRINT '--- 2. 후보 법정동별 호수와 예상 호출수 ---';
/* 전유부(호)가 이미 적재된 곳만 센다 — 호가 없으면 전유공용도 받을 게 없다. */
SELECT e.sigungu_cd, e.bjdong_cd,
       동명 = MAX(d.bjdong_nm),
       호수 = COUNT(*),
       예상건 = CAST(COUNT(*) * 6.95 AS INT),
       예상콜 = CEILING(COUNT(*) * 6.95 / 100.0),
       이미 = MAX(CASE WHEN t.ops LIKE '%exar%' THEN N'Y' ELSE N'' END)
  FROM silver.bld_expos e
  LEFT JOIN meta.lawd_code d
         ON d.lawd_cd = e.sigungu_cd + e.bjdong_cd
  LEFT JOIN meta.load_target t
         ON t.sigungu_cd = e.sigungu_cd AND t.bjdong_cd = e.bjdong_cd
 WHERE e.is_current = 1
   AND e.sigungu_cd IN ('11110','11380','11290')
 GROUP BY e.sigungu_cd, e.bjdong_cd
 ORDER BY COUNT(*) DESC;
GO

PRINT '--- 3. 시군구 합계 ---';
SELECT e.sigungu_cd, 법정동수 = COUNT(DISTINCT e.bjdong_cd), 호수 = COUNT(*),
       예상콜 = CEILING(COUNT(*) * 6.95 / 100.0),
       예상시간_분 = CEILING(COUNT(*) * 6.95 / 100.0) / 80
  FROM silver.bld_expos e
 WHERE e.is_current = 1 AND e.sigungu_cd IN ('11110','11380','11290')
 GROUP BY e.sigungu_cd;
PRINT '  (80콜/분 = 수색+장위 1,650콜이 20분 걸린 실측에서 나온 값)';
GO
