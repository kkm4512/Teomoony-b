/* 부속지번 검색을 넣은 뒤 단어 검색이 7.6~19.4초다(빈 검색은 89ms).
   내가 넣은 CTE 탓인지 **쪼개서** 가른다. 짐작으로 되돌리지 않는다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q NVARCHAR(200) = N'%대조동 14-45%';
SELECT 변형='A 부속맞음 CTE 만', 행 = COUNT(*)
  FROM (
    SELECT cb.complex_id
      FROM silver.bld_atch_jibun a
      JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = a.mgm_bldrgst_pk
     WHERE a.is_current = 1 AND a.plat_plc LIKE @q
     GROUP BY cb.complex_id
  ) x;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q2 NVARCHAR(200) = N'%대조동 14-45%';
SELECT 변형='B 예전 검색(부속 없이)', 행 = COUNT(*)
  FROM gold.v_complex_map v
 WHERE v.complex_nm LIKE @q2 OR v.rep_plat_plc LIKE @q2 OR v.rep_road_addr LIKE @q2;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q3 NVARCHAR(200) = N'%센트라스%';
SELECT 변형='C 예전 검색(흔한 말)', 행 = COUNT(*)
  FROM gold.v_complex_map v
 WHERE v.complex_nm LIKE @q3 OR v.rep_plat_plc LIKE @q3 OR v.rep_road_addr LIKE @q3;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* D — 법정동 검색(검색 엔드포인트가 같이 돈다). v_lawd_map 은 무거운 뷰다(11-120). */
DECLARE @q4 NVARCHAR(200) = N'%대조동 14-45%';
SELECT 변형='D 법정동 검색', 행 = COUNT(*)
  FROM (SELECT TOP 8 lawd_cd, complex_cnt, trade_cnt, max_amount
          FROM gold.v_lawd_map
         WHERE emd_nm LIKE @q4 OR full_nm LIKE @q4 OR lawd_cd LIKE @q4
         ORDER BY complex_cnt DESC, emd_nm) y;
