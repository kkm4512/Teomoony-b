/* '석관' 검색: SQL 단독 1.74초인데 엔드포인트는 7.1초. 남은 것은 **신축 검색**이다.
   가설: `ORDER BY 거래 DESC` — 거래는 v_newbuild 의 OUTER APPLY(rtms_trade 집계)다.
   정렬하려면 **걸린 행마다 그 집계를 돌려야** 한다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q NVARCHAR(200) = N'%석관%';
SELECT TOP 8 변형='A 지금(거래 DESC 정렬)', kapt_code, 거래
  FROM gold.v_newbuild
 WHERE kapt_name LIKE @q OR kapt_addr LIKE @q OR doro_juso LIKE @q
 ORDER BY 거래 DESC, 세대 DESC;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q2 NVARCHAR(200) = N'%석관%';
SELECT TOP 8 변형='B 거래 빼고(세대만)', kapt_code, 세대
  FROM gold.v_newbuild
 WHERE kapt_name LIKE @q2 OR kapt_addr LIKE @q2 OR doro_juso LIKE @q2
 ORDER BY 세대 DESC;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q3 NVARCHAR(200) = N'%석관%';
SELECT 변형='C 몇 건이나 걸리나', 행 = COUNT(*)
  FROM silver.kapt_complex k
 WHERE k.is_current = 1 AND (k.kapt_name LIKE @q3 OR k.kapt_addr LIKE @q3 OR k.doro_juso LIKE @q3);
