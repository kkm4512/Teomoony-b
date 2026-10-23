/* 일곱째 길 시험(쓰지 않음): 안 이어진 공고 p 의 공고 지번에 **이미 이어진 공고**(형제)가 있고
   ① 형제들이 가리키는 곳이 하나(단지 또는 대장 없는 K-apt) ② 그 필지에 그 곳 말고 다른 지금 단지 · K-apt 없음
   ③ p 공고일 ≥ 형제 첫 공고일 ④ 공급 ≤ 세대  → p 를 그곳에 */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#sib') IS NOT NULL DROP TABLE #sib;
SELECT p.pnu, 곳 = COALESCE('C' + CAST(l.complex_id AS VARCHAR(12)), 'K' + l.kapt_code), l.complex_id, l.kapt_code,
       첫 = REPLACE(p.rcrit_pblanc_de, '-', '')
  INTO #sib
  FROM gold.applyhome_link l JOIN silver.applyhome_pblanc p ON p.house_manage_no = l.house_manage_no AND p.pblanc_no = l.pblanc_no
 WHERE p.pnu IS NOT NULL;
IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t;
SELECT pnu, 곳n = COUNT(DISTINCT 곳), 곳 = MIN(곳), complex_id = MIN(complex_id), kapt_code = MIN(kapt_code), 첫 = MIN(첫)
  INTO #t FROM #sib GROUP BY pnu;
IF OBJECT_ID('tempdb..#u') IS NOT NULL DROP TABLE #u;
SELECT p.house_manage_no, p.pblanc_no, p.house_nm, p.house_secd_nm, p.pnu, p.tot_suply, 공고 = REPLACE(p.rcrit_pblanc_de, '-', ''),
       t.곳n, t.곳, t.complex_id, t.kapt_code, t.첫
  INTO #u
  FROM silver.applyhome_pblanc p JOIN #t t ON t.pnu = p.pnu
 WHERE NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no);
/* 필지의 다른 단지 · K-apt 수 — 미리 칸으로 */
IF OBJECT_ID('tempdb..#o') IS NOT NULL DROP TABLE #o;
SELECT u.house_manage_no, u.pblanc_no,
       다른단지 = (SELECT COUNT(DISTINCT cp.complex_id) FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id
                   WHERE cp.pnu = u.pnu AND c.is_active = 1 AND c.merged_into IS NULL AND (u.complex_id IS NULL OR cp.complex_id <> u.complex_id)),
       다른kapt = (SELECT COUNT(*) FROM silver.kapt_complex k WHERE k.is_current = 1 AND k.pnu = u.pnu AND (u.kapt_code IS NULL OR k.kapt_code <> u.kapt_code)
                   AND NOT EXISTS (SELECT 1 FROM gold.complex_kapt ck WHERE ck.kapt_code = k.kapt_code AND ck.complex_id = u.complex_id)),
       세대 = COALESCE((SELECT c.hhld_cnt_sum FROM gold.complex c WHERE c.complex_id = u.complex_id),
                       (SELECT TOP 1 COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt) FROM silver.kapt_complex k WHERE k.is_current = 1 AND k.kapt_code = u.kapt_code))
  INTO #o FROM #u u;
SELECT j = (SELECT
  안이어진형제있음 = (SELECT COUNT(*) FROM #u),
  서울 = (SELECT COUNT(*) FROM #u WHERE pnu LIKE '11%'),
  곳여럿 = (SELECT COUNT(*) FROM #u WHERE 곳n > 1),
  다른단지있음 = (SELECT COUNT(*) FROM #u u JOIN #o o ON o.house_manage_no = u.house_manage_no AND o.pblanc_no = u.pblanc_no WHERE u.곳n = 1 AND (o.다른단지 > 0 OR o.다른kapt > 0)),
  형제보다앞 = (SELECT COUNT(*) FROM #u u JOIN #o o ON o.house_manage_no = u.house_manage_no AND o.pblanc_no = u.pblanc_no WHERE u.곳n = 1 AND o.다른단지 = 0 AND o.다른kapt = 0 AND u.공고 < u.첫),
  세대모자람 = (SELECT COUNT(*) FROM #u u JOIN #o o ON o.house_manage_no = u.house_manage_no AND o.pblanc_no = u.pblanc_no WHERE u.곳n = 1 AND o.다른단지 = 0 AND o.다른kapt = 0 AND u.공고 >= u.첫 AND u.tot_suply > o.세대),
  이을것 = (SELECT u.house_manage_no, u.house_nm, u.house_secd_nm, u.pnu, u.공고, 형제첫 = u.첫, u.tot_suply, o.세대, u.complex_id, u.kapt_code,
                  이름 = COALESCE((SELECT complex_nm FROM gold.complex WHERE complex_id = u.complex_id), (SELECT TOP 1 kapt_name FROM silver.kapt_complex WHERE kapt_code = u.kapt_code))
              FROM #u u JOIN #o o ON o.house_manage_no = u.house_manage_no AND o.pblanc_no = u.pblanc_no
             WHERE u.곳n = 1 AND o.다른단지 = 0 AND o.다른kapt = 0 AND u.공고 >= u.첫 AND (u.tot_suply IS NULL OR u.tot_suply <= ISNULL(o.세대, 2147483647))
             ORDER BY u.pnu, u.공고 FOR JSON PATH),
  막힌것 = (SELECT u.house_manage_no, u.house_nm, u.pnu, u.공고, 형제첫 = u.첫, u.곳n, o.다른단지, o.다른kapt, u.tot_suply, o.세대
              FROM #u u JOIN #o o ON o.house_manage_no = u.house_manage_no AND o.pblanc_no = u.pblanc_no
             WHERE NOT (u.곳n = 1 AND o.다른단지 = 0 AND o.다른kapt = 0 AND u.공고 >= u.첫 AND (u.tot_suply IS NULL OR u.tot_suply <= ISNULL(o.세대, 2147483647)))
             ORDER BY u.pnu FOR JSON PATH)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
