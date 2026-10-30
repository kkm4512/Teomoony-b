/* 390 이름 가림 — 서비스DB 에 옛 이름(괄호 속 사람 이름)이 담겼을 수 있는 단지 번호 (svc_dirty_sql 용 · 한 번)
   ① 이름을 가린 단지 ② 같은 필지의 옛(폐쇄) 대장 이름을 가린 단지 ③ 표제부 · 총괄표제부 건물명 · 동명이 가려지는 단지 ④ 같은 필지 허가 건물명이 가려지는 단지 */
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT CAST(키 AS INT) FROM ops.name_mask_log WHERE 종류 = 'complex'
UNION SELECT cp.complex_id FROM gold.complex_pnu cp JOIN gold.closed_site s ON s.pnu = cp.pnu WHERE s.이름 LIKE N'%(개인 이름 가림)'
UNION SELECT cb.complex_id FROM gold.complex_bld cb JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
       WHERE (t.bld_nm LIKE N'%)' AND gold.fn_name_mask(t.bld_nm) <> t.bld_nm) OR (t.dong_nm LIKE N'%)' AND gold.fn_name_mask(t.dong_nm) <> t.dong_nm)
UNION SELECT cb.complex_id FROM gold.complex_bld cb JOIN silver.bld_recap_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
       WHERE t.bld_nm LIKE N'%)' AND gold.fn_name_mask(t.bld_nm) <> t.bld_nm
UNION SELECT cp.complex_id FROM gold.complex_pnu cp JOIN silver.arch_permit a ON a.pnu = cp.pnu AND a.is_current = 1
       WHERE a.bld_nm LIKE N'%)' AND gold.fn_name_mask(a.bld_nm) <> a.bld_nm;
