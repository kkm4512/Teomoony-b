/* 240_idea_probe (3) : 공용을 '주거공용 vs 기타공용' 으로 가를 수 있나 (2026-10-21) 읽기만.
   ★ 흔히 말하는 '전용률' 은 전용 ÷ (전용 + **주거**공용) 이다.
     기타공용(주차장 등)까지 넣으면 전혀 다른 수가 된다. 가를 수 있는지부터 본다. */
USE Teomoony;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 보기 = STRING_AGG(CAST(용도 + ' = ' + CAST(건수 AS VARCHAR(20)) AS NVARCHAR(MAX)), ' | ')
              WITHIN GROUP (ORDER BY 건수 DESC)
  FROM (SELECT TOP 20 용도 = ISNULL(main_purps_nm, N'(빈칸)'), 건수 = COUNT(*)
          FROM silver.bld_expos_pubuse_area
         WHERE is_current = 1 AND expos_pubuse_gb_cd = '2'
         GROUP BY main_purps_nm ORDER BY COUNT(*) DESC) q;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '--- 층 구분(지하/지상)으로도 갈리나 ---';
SELECT 보기 = STRING_AGG(CAST(ISNULL(flr_gb_cd,'?') + ' = ' + CAST(건수 AS VARCHAR(20)) AS NVARCHAR(MAX)), ' | ')
  FROM (SELECT flr_gb_cd, 건수 = COUNT(*)
          FROM silver.bld_expos_pubuse_area
         WHERE is_current = 1 AND expos_pubuse_gb_cd = '2'
         GROUP BY flr_gb_cd) q;
GO
