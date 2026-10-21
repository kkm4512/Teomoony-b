SET NOCOUNT ON;
DECLARE @sgg CHAR(5)='11380', @bjd CHAR(5)='10100', @bun VARCHAR(10)='0417';

PRINT '=== 1) 수색동 417 기본개요 (API 는 1,266) ===';
SELECT regstr_kind_cd, regstr_kind_nm, 건수=COUNT(*), 이름=MIN(bld_nm)
  FROM silver.bld_basis_outline
 WHERE is_current=1 AND sigungu_cd=@sgg AND bjdong_cd=@bjd AND bun=@bun
 GROUP BY regstr_kind_cd, regstr_kind_nm ORDER BY regstr_kind_cd;

PRINT '';
PRINT '=== 2) 417 의 표제부/총괄 이름 ===';
SELECT TOP 20 t.regstr_kind_cd, t.bld_nm, t.dong_nm, t.hhld_cnt, t.use_apr_day
  FROM silver.bld_title t
 WHERE t.is_current=1 AND t.sigungu_cd=@sgg AND t.bjdong_cd=@bjd AND t.bun=@bun
 ORDER BY t.dong_nm;
SELECT TOP 5 r.bld_nm, r.hhld_cnt, r.use_apr_day
  FROM silver.bld_recap_title r
 WHERE r.is_current=1 AND r.sigungu_cd=@sgg AND r.bjdong_cd=@bjd AND r.bun=@bun;

PRINT '';
PRINT '=== 3) 단지로 묶였나 ===';
SELECT c.complex_id, c.complex_nm, c.complex_nm_src, c.rep_plat_plc,
       c.dong_cnt, c.hhld_cnt_sum, c.has_recap, c.grouping_rule
  FROM gold.complex c
 WHERE c.rep_plat_plc LIKE N'%수색동 417%'
    OR c.complex_nm LIKE N'%롯데캐슬%';

PRINT '';
PRINT '=== 4) 수색동 세대수 상위 ===';
SELECT TOP 8 complex_id, complex_nm, rep_plat_plc, dong_cnt, hhld_cnt_sum, has_recap
  FROM gold.complex WHERE sigungu_cd=@sgg AND bjdong_cd=@bjd
 ORDER BY ISNULL(hhld_cnt_sum,0) DESC;
