/* 부속지번으로 검색하면 단지가 찾아지나.
   검색은 `complex_nm · rep_plat_plc · rep_road_addr` **대표 주소만** 본다(server.js).
   `silver.bld_atch_jibun` 은 183,031건 받아 놓고 **한 번도 안 읽는다**(CONTEXT 11-110).
   ★ 그러면 "45-2 로 검색했는데 대표가 45-1 인 단지" 는 **안 잡힌다**는 뜻이다.
     짐작하지 말고 **실제 사례를 뽑아** 확인한다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 부속지번_전체 = COUNT(*),
       건물수 = COUNT(DISTINCT mgm_bldrgst_pk),
       PNU있음 = SUM(CASE WHEN atch_pnu IS NULL THEN 0 ELSE 1 END)
  FROM silver.bld_atch_jibun WHERE is_current = 1;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 대표지번과 **다른** 부속지번을 가진 단지 다섯 — 검색 시험용 */
SELECT 사례 = STRING_AGG(CAST(CONCAT(x.complex_id,'|',x.complex_nm,'|대표:',x.rep_plat_plc,
                                      '|부속:',x.부속) AS NVARCHAR(MAX)), N'
')
  FROM (
    SELECT TOP 5 c.complex_id, c.complex_nm, c.rep_plat_plc, 부속 = MIN(a.plat_plc)
      FROM gold.complex c
      JOIN gold.complex_bld cb ON cb.complex_id = c.complex_id
      JOIN silver.bld_atch_jibun a ON a.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND a.is_current = 1
     WHERE a.plat_plc IS NOT NULL AND c.rep_plat_plc IS NOT NULL
       AND a.plat_plc <> c.rep_plat_plc
     GROUP BY c.complex_id, c.complex_nm, c.rep_plat_plc
     ORDER BY c.complex_id
  ) x;
