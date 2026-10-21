/* 174. 브랜드를 한글 음차로 다시 센다 (2026-10-19) — 읽기 전용
   ★ 173 에서 'GS25','CU' 로 찾아 0건이 나왔다. 실제는 **지에스25, 씨유** 다.
     데이터가 없던 게 아니라 **내 검색어가 틀렸다.** */
SET NOCOUNT ON;
PRINT '--- A. 브랜드별 (한글 음차) ---';
SELECT 브랜드 = b.disp, 개수 = (SELECT COUNT(*) FROM silver.semas_store s
                                WHERE s.is_current = 1 AND s.bizes_nm LIKE N'%' + b.pat + N'%')
  FROM (VALUES (N'GS25',N'지에스25'),(N'CU',N'씨유'),(N'세븐일레븐',N'세븐일레븐'),
               (N'이마트24',N'이마트24'),(N'올리브영',N'올리브영'),(N'스타벅스',N'스타벅스'),
               (N'다이소',N'다이소'),(N'메가커피',N'메가커피'),(N'파리바게뜨',N'파리바게뜨'),
               (N'뚜레쥬르',N'뚜레쥬르'),(N'투썸',N'투썸'),(N'이디야',N'이디야'),
               (N'맥도날드',N'맥도날드'),(N'버거킹',N'버거킹'),(N'롯데리아',N'롯데리아'),
               (N'빽다방',N'빽다방'),(N'컴포즈',N'컴포즈'),(N'노브랜드',N'노브랜드')
       ) b(disp,pat)
 ORDER BY 2 DESC;

PRINT '';
PRINT '--- B. 편의점 상호에 브랜드가 적힌 비율 (제대로) ---';
SELECT 전체 = COUNT(*),
       브랜드적힘 = SUM(CASE WHEN bizes_nm LIKE N'%지에스25%' OR bizes_nm LIKE N'%씨유%'
                          OR bizes_nm LIKE N'%세븐일레븐%' OR bizes_nm LIKE N'%이마트24%'
                          OR bizes_nm LIKE N'%미니스톱%' OR bizes_nm LIKE N'%스토리웨이%'
                          THEN 1 ELSE 0 END)
  FROM silver.semas_store WHERE is_current = 1 AND inds_scls_nm = N'편의점';

PRINT '';
PRINT '--- C. 녹번역 500m 안 브랜드 ---';
SELECT 브랜드 = b.disp, 개수 = COUNT(*), 최단m = MIN(CAST(v.dist_m AS INT))
  FROM gold.v_complex_poi v
  JOIN (VALUES (N'GS25',N'지에스25'),(N'CU',N'씨유'),(N'세븐일레븐',N'세븐일레븐'),
               (N'이마트24',N'이마트24'),(N'올리브영',N'올리브영'),(N'스타벅스',N'스타벅스'),
               (N'다이소',N'다이소'),(N'파리바게뜨',N'파리바게뜨'),(N'메가커피',N'메가커피'),
               (N'투썸',N'투썸'),(N'이디야',N'이디야'),(N'빽다방',N'빽다방')
       ) b(disp,pat) ON v.bizes_nm LIKE N'%' + b.pat + N'%'
 WHERE v.complex_id = 95051 AND v.dist_m <= 500
 GROUP BY b.disp ORDER BY COUNT(*) DESC;
