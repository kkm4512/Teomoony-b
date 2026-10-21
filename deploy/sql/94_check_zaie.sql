SET NOCOUNT ON;
USE Teomoony;
GO
/* 94_check_zaie : 장위자이레디언트가 대장에 있는가 (읽기 전용)

   실거래 645건이 지번 62-1 로 들어왔는데 그 PNU 에 대장이 없다.
   재개발 신축은 여러 필지를 합병하므로, 실거래 신고 지번과 대장 대지위치가
   갈렸을 가능성이 높다. 이름으로 찾아 지번을 맞춰 본다. */

PRINT '=== 1. 대장에 이름이 있나 (기본개요) ===';
SELECT TOP 20 b.pnu, b.bun, b.ji, b.bld_nm, b.regstr_kind_nm,
       b.mgm_bldrgst_pk, b.mgm_up_bldrgst_pk
FROM silver.bld_basis_outline b
WHERE b.is_current = 1 AND b.sigungu_cd = '11290'
  AND (b.bld_nm LIKE N'%레디언트%' OR b.bld_nm LIKE N'%자이%')
ORDER BY b.pnu, b.bld_nm;
GO

PRINT '';
PRINT '=== 2. 장위동 62-1 필지에 뭐가 있나 ===';
SELECT 대장 = (SELECT COUNT(*) FROM silver.bld_basis_outline
                WHERE is_current = 1 AND pnu = '1129013800100620001'),
       단지필지 = (SELECT COUNT(*) FROM gold.complex_pnu WHERE pnu = '1129013800100620001'),
       필지 = (SELECT COUNT(*) FROM silver.cadastral_parcel
                WHERE is_current = 1 AND pnu = '1129013800100620001');
GO

PRINT '';
PRINT '=== 3. 장위동 대장 적재량 (페이지 상한에 걸려 덜 들어왔는지) ===';
SELECT 기본개요 = COUNT(*),
       서로다른지번 = COUNT(DISTINCT pnu),
       최신등록 = MAX(crtn_day)
FROM silver.bld_basis_outline
WHERE is_current = 1 AND sigungu_cd = '11290' AND bjdong_cd = '13800';
GO

PRINT '';
PRINT '=== 4. 장위동 대장에서 세대 많은 단지 상위 (신축이 들어왔는지) ===';
SELECT TOP 15 c.complex_id, c.complex_nm, c.dong_cnt, c.hhld_cnt_sum,
       c.rep_jibun, c.oldest_use_apr
FROM gold.complex c
WHERE c.sigungu_cd = '11290'
ORDER BY c.hhld_cnt_sum DESC;
GO
