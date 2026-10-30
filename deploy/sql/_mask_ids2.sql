/* 390 덧붙임(10-30 23:10 '대표 · 대표자 · 대표이사 뒤 이름' · 괄호 안 괄호) — 서비스DB 에 옛 이름이 담겼을 수 있는 단지 번호 (svc_dirty_sql 용 · 한 번)
   ① 이번에 이름을 가린 단지 ② 같은 필지의 옛 대장 이름이 '대표' 꼴인 단지 ③ 표제부 · 총괄 건물명이 '대표' 꼴인 단지 ④ 같은 필지 허가 건물명이 '대표' 꼴인 단지 */
SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT CAST(키 AS INT) FROM ops.name_mask_log WHERE 종류 = 'complex' AND 때 >= '2026-10-30T23:00:00'
UNION SELECT cp.complex_id FROM gold.complex_pnu cp JOIN gold.closed_site s ON s.pnu = cp.pnu
       JOIN ops.name_mask_log l ON l.종류 = 'closed_site' AND l.키 = CAST(s.site_key AS VARCHAR(80)) AND l.때 >= '2026-10-30T23:00:00'
UNION SELECT cb.complex_id FROM gold.complex_bld cb JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
       WHERE t.bld_nm LIKE N'%대표%)' AND gold.fn_name_mask(t.bld_nm) <> t.bld_nm
UNION SELECT cb.complex_id FROM gold.complex_bld cb JOIN silver.bld_recap_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
       WHERE t.bld_nm LIKE N'%대표%)' AND gold.fn_name_mask(t.bld_nm) <> t.bld_nm
UNION SELECT cp.complex_id FROM gold.complex_pnu cp JOIN silver.arch_permit a ON a.pnu = cp.pnu AND a.is_current = 1
       WHERE a.bld_nm LIKE N'%대표%)' AND gold.fn_name_mask(a.bld_nm) <> a.bld_nm;
