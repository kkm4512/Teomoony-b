/* '석관' 검색만 18초다(래미안 3.4 · 자이 2.1 · e편한 1.9). 법정동은 347ms 로 아니었다.
   ★ 남은 용의자는 **내가 넣은 부속지번 CTE** 다. '대조동 14-45' 로 쟀을 땐 1행이라
     398ms 였는데, '석관' 은 부속지번에도 많이 걸린다 —
     **좁은 검색어로만 재고 "싸다" 고 한 것이 내 잘못이다.** 넓은 말로 다시 잰다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q NVARCHAR(200) = N'%석관%';
SELECT 변형='부속 CTE (석관)', 단지수 = COUNT(*)
  FROM (
    SELECT cb.complex_id
      FROM silver.bld_atch_jibun a
      JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = a.mgm_bldrgst_pk
     WHERE a.is_current = 1 AND a.plat_plc LIKE @q
     GROUP BY cb.complex_id
  ) x;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q2 NVARCHAR(200) = N'%석관%';
SELECT 변형='부속 원본만(조인 전)', 행 = COUNT(*)
  FROM silver.bld_atch_jibun a
 WHERE a.is_current = 1 AND a.plat_plc LIKE @q2;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* complex_bld 크기 — 조인 상대가 큰가 */
SELECT 표='gold.complex_bld', 행 = COUNT(*) FROM gold.complex_bld;
