/* 조각은 다 빠른데(단지 1.3s · 법정동 0.35s · 부속 0.42s) 엔드포인트는 18초다.
   ★ 내가 부속을 LEFT JOIN + OR 로 엮었다. OR 가 끼면 옵티마이저가
     538,377행과 통째로 조인하는 계획을 고를 수 있다.
   A 예전(부속 없음) / B 지금(LEFT JOIN+OR) / C 대안(UNION 먼저) 을 나란히 잰다.
   ⚠ OPTION (RECOMPILE) 은 **파생 테이블 안에 못 쓴다** — 문장 끝에 둔다(한 번 틀렸다). */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q NVARCHAR(200) = N'%석관%';
SELECT TOP 51 변형='A 예전(부속 없음)', v.complex_id
  FROM gold.v_complex_map v
 WHERE v.complex_nm LIKE @q OR v.rep_plat_plc LIKE @q OR v.rep_road_addr LIKE @q
 ORDER BY v.dong_cnt DESC, v.pnu_cnt DESC, v.complex_id
OPTION (RECOMPILE);
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q2 NVARCHAR(200) = N'%석관%';
WITH 부속맞음 AS (
  SELECT cb.complex_id FROM silver.bld_atch_jibun a
    JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = a.mgm_bldrgst_pk
   WHERE a.is_current = 1 AND a.plat_plc LIKE @q2 GROUP BY cb.complex_id)
SELECT TOP 51 변형='B 지금(LEFT JOIN+OR)', v.complex_id
  FROM gold.v_complex_map v
  LEFT JOIN 부속맞음 am ON am.complex_id = v.complex_id
 WHERE v.complex_nm LIKE @q2 OR v.rep_plat_plc LIKE @q2 OR v.rep_road_addr LIKE @q2
    OR am.complex_id IS NOT NULL
 ORDER BY v.dong_cnt DESC, v.pnu_cnt DESC, v.complex_id
OPTION (RECOMPILE);
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q3 NVARCHAR(200) = N'%석관%';
WITH 걸림 AS (
  SELECT v.complex_id FROM gold.v_complex_map v
   WHERE v.complex_nm LIKE @q3 OR v.rep_plat_plc LIKE @q3 OR v.rep_road_addr LIKE @q3
  UNION
  SELECT cb.complex_id FROM silver.bld_atch_jibun a
    JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = a.mgm_bldrgst_pk
   WHERE a.is_current = 1 AND a.plat_plc LIKE @q3)
SELECT TOP 51 변형='C 대안(UNION 먼저)', v.complex_id
  FROM gold.v_complex_map v
  JOIN 걸림 g ON g.complex_id = v.complex_id
 ORDER BY v.dong_cnt DESC, v.pnu_cnt DESC, v.complex_id
OPTION (RECOMPILE);
