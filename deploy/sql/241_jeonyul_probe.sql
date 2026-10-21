/* 241_jeonyul_probe (4) : '주차장' 한 단어만 빼면 전용률이 그럴듯해지나 (2026-10-21) 읽기만.
   ★ etc_purps 는 **원본에 적힌 글자**다. 거기서 '주차장' 을 읽는 건 추론이 아니라 읽기다.
     목록을 내가 만들지 않는다 — 한 단어만 본다. */
USE Teomoony;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 공용 기타용도에 무엇이 적혀 있나 (상위) ---';
SELECT 보기 = STRING_AGG(CAST(용도 + '=' + CAST(건수 AS VARCHAR(20)) AS NVARCHAR(MAX)), ' | ')
              WITHIN GROUP (ORDER BY 건수 DESC)
  FROM (SELECT TOP 14 용도 = LEFT(ISNULL(NULLIF(etc_purps,''), N'(빈칸)'), 24), 건수 = COUNT(*)
          FROM silver.bld_expos_pubuse_area
         WHERE is_current = 1 AND expos_pubuse_gb_cd = '2'
         GROUP BY LEFT(ISNULL(NULLIF(etc_purps,''), N'(빈칸)'), 24)
         ORDER BY COUNT(*) DESC) q;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 도곡렉슬 3,003호: 주차장을 뺀 전용률 분포 ---';
WITH h AS (SELECT 호PK FROM gold.v_complex_ho WHERE complex_id = 507648),
b AS (
  SELECT e.mgm_bldrgst_pk,
         전유 = SUM(CASE WHEN e.expos_pubuse_gb_cd = '1' THEN e.area ELSE 0 END),
         주차 = SUM(CASE WHEN e.expos_pubuse_gb_cd = '2'
                         AND e.etc_purps LIKE N'%주차장%' THEN e.area ELSE 0 END),
         나머지공용 = SUM(CASE WHEN e.expos_pubuse_gb_cd = '2'
                         AND (e.etc_purps NOT LIKE N'%주차장%' OR e.etc_purps IS NULL)
                         THEN e.area ELSE 0 END)
    FROM h JOIN silver.bld_expos_pubuse_area e
      ON e.mgm_bldrgst_pk = h.호PK AND e.is_current = 1 AND e.area > 0
   GROUP BY e.mgm_bldrgst_pk)
SELECT 호 = COUNT(*),
       주차뺀전용률 = CAST(AVG(CASE WHEN 전유 > 0 AND 나머지공용 > 0
              THEN 100.0 * 전유 / (전유 + 나머지공용) END) AS DECIMAL(5,1)),
       최소 = CAST(MIN(CASE WHEN 전유 > 0 AND 나머지공용 > 0
              THEN 100.0 * 전유 / (전유 + 나머지공용) END) AS DECIMAL(5,1)),
       최대 = CAST(MAX(CASE WHEN 전유 > 0 AND 나머지공용 > 0
              THEN 100.0 * 전유 / (전유 + 나머지공용) END) AS DECIMAL(5,1)),
       계약기준 = CAST(AVG(CASE WHEN 전유 > 0 AND (주차 + 나머지공용) > 0
              THEN 100.0 * 전유 / (전유 + 주차 + 나머지공용) END) AS DECIMAL(5,1)),
       주차있는호 = SUM(CASE WHEN 주차 > 0 THEN 1 ELSE 0 END)
  FROM b;
GO
