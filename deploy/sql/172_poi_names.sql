/* 172. 상권을 '사람 말' 로 보여줄 수 있나 (2026-10-19) — 읽기 전용
   ★ 대분류(음식/소매/수리·개인)는 **분류 체계의 말**이지 사람 말이 아니다.
     사람이 궁금한 건 "편의점 있나 · 올리브영 있나 · 스벅 있나" 다.
     소분류(inds_scls_nm)와 상호명(bizes_nm)에 그게 실제로 있는지 본다. */
SET NOCOUNT ON;
PRINT '--- A. 녹번역e편한세상캐슬 500m 안 소분류 상위 20 ---';
SELECT TOP 20 소분류 = v.inds_scls_nm, 중분류 = v.inds_mcls_nm, 개수 = COUNT(*)
  FROM gold.v_complex_poi v
 WHERE v.complex_id = 95051 AND v.dist_m <= 500
 GROUP BY v.inds_scls_nm, v.inds_mcls_nm ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- B. 사람들이 찾는 것들이 소분류에 있나 (전체 기준) ---';
SELECT 소분류 = inds_scls_nm, 전체 = COUNT(*)
  FROM silver.semas_store WHERE is_current = 1
   AND inds_scls_nm IN (N'편의점', N'카페', N'약국', N'헬스클럽', N'노래연습장',
                        N'미용실', N'세탁소', N'치킨전문점', N'한식일반음식점',
                        N'커피전문점', N'제과점', N'어린이집', N'유치원')
 GROUP BY inds_scls_nm ORDER BY COUNT(*) DESC;

PRINT '';
PRINT '--- C. 브랜드가 상호명에 있나 ---';
SELECT 브랜드 = b.nm, 개수 = (SELECT COUNT(*) FROM silver.semas_store s
                              WHERE s.is_current = 1 AND s.bizes_nm LIKE N'%' + b.nm + N'%')
  FROM (VALUES (N'올리브영'),(N'스타벅스'),(N'다이소'),(N'GS25'),(N'CU'),
               (N'세븐일레븐'),(N'이마트24'),(N'메가커피'),(N'파리바게뜨'),
               (N'맥도날드'),(N'투썸'),(N'이디야')) b(nm);

PRINT '';
PRINT '--- D. 녹번역 500m 안 브랜드 실제 상호 ---';
SELECT TOP 15 상호 = v.bizes_nm, 소분류 = v.inds_scls_nm,
       거리m = CAST(v.dist_m AS INT)
  FROM gold.v_complex_poi v
 WHERE v.complex_id = 95051 AND v.dist_m <= 500
   AND (v.bizes_nm LIKE N'%올리브영%' OR v.bizes_nm LIKE N'%스타벅스%'
     OR v.bizes_nm LIKE N'%다이소%' OR v.bizes_nm LIKE N'%GS25%'
     OR v.bizes_nm LIKE N'%CU%' OR v.bizes_nm LIKE N'%메가커피%')
 ORDER BY v.dist_m;
