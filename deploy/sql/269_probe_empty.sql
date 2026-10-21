/* C(UNION 먼저)가 '석관' 에서 1.6초로 가장 빠르다. 그런데 **빈 검색**(목록 둘러보기)은
   예전에 89ms 였다 — UNION 으로 538,377개 id 를 모으면 거기서 느려질 수 있다.
   ★ 빠른 쪽만 보고 바꾸면 다른 쪽이 조용히 느려진다. 둘 다 잰다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q NVARCHAR(200) = NULL, @qid INT = NULL;
SELECT TOP 51 변형='A 빈 검색 — 예전 모양', v.complex_id
  FROM gold.v_complex_map v
 WHERE (@q IS NULL AND @qid IS NULL)
    OR (@q IS NOT NULL AND (v.complex_nm LIKE @q OR v.rep_plat_plc LIKE @q OR v.rep_road_addr LIKE @q))
    OR (@qid IS NOT NULL AND v.complex_id = @qid)
 ORDER BY v.dong_cnt DESC, v.pnu_cnt DESC, v.complex_id
OPTION (RECOMPILE);
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @q2 NVARCHAR(200) = NULL, @qid2 INT = NULL;
WITH 부속맞음 AS (
  SELECT cb.complex_id, 부속지번 = MIN(a.plat_plc)
    FROM silver.bld_atch_jibun a
    JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = a.mgm_bldrgst_pk
   WHERE @q2 IS NOT NULL AND a.is_current = 1 AND a.plat_plc LIKE @q2
   GROUP BY cb.complex_id),
걸림 AS (
  SELECT complex_id FROM gold.v_complex_map
   WHERE @q2 IS NOT NULL AND (complex_nm LIKE @q2 OR rep_plat_plc LIKE @q2 OR rep_road_addr LIKE @q2)
  UNION SELECT complex_id FROM 부속맞음
  UNION SELECT @qid2 WHERE @qid2 IS NOT NULL)
SELECT TOP 51 변형='B 빈 검색 — C 모양', v.complex_id
  FROM gold.v_complex_map v
  LEFT JOIN 부속맞음 am ON am.complex_id = v.complex_id
 WHERE (@q2 IS NULL AND @qid2 IS NULL)
    OR v.complex_id IN (SELECT complex_id FROM 걸림)
 ORDER BY v.dong_cnt DESC, v.pnu_cnt DESC, v.complex_id
OPTION (RECOMPILE);
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* C — 검색어가 있을 때 같은 모양이 여전히 빠른가 */
DECLARE @q3 NVARCHAR(200) = N'%석관%', @qid3 INT = NULL;
WITH 부속맞음 AS (
  SELECT cb.complex_id, 부속지번 = MIN(a.plat_plc)
    FROM silver.bld_atch_jibun a
    JOIN gold.complex_bld cb ON cb.mgm_bldrgst_pk = a.mgm_bldrgst_pk
   WHERE @q3 IS NOT NULL AND a.is_current = 1 AND a.plat_plc LIKE @q3
   GROUP BY cb.complex_id),
걸림 AS (
  SELECT complex_id FROM gold.v_complex_map
   WHERE @q3 IS NOT NULL AND (complex_nm LIKE @q3 OR rep_plat_plc LIKE @q3 OR rep_road_addr LIKE @q3)
  UNION SELECT complex_id FROM 부속맞음
  UNION SELECT @qid3 WHERE @qid3 IS NOT NULL)
SELECT TOP 51 변형='C 석관 — 같은 모양', v.complex_id, am.부속지번
  FROM gold.v_complex_map v
  LEFT JOIN 부속맞음 am ON am.complex_id = v.complex_id
 WHERE (@q3 IS NULL AND @qid3 IS NULL)
    OR v.complex_id IN (SELECT complex_id FROM 걸림)
 ORDER BY v.dong_cnt DESC, v.pnu_cnt DESC, v.complex_id
OPTION (RECOMPILE);
