        /* 여덟째 (402 · 2026-11-01 사장님 "검색에서 같은 곳이 두 줄" → "ㄱㄱ"): 공고 지번 = 지금 단지 필지이고, 그 단지 사용승인이 그 지번 첫 공고 이후(= 그 공고로 지은 단지).
           ① 공고 지번(PNU 코드)의 지금 단지가 **하나**(다른 단지가 같은 필지에 있으면 막음) ② 그 단지 사용승인일 ≥ 그 지번의 첫 공고일(모든 공고 중)
           공고 전부터 있던 건물(재건축 · 리모델링 전 단지 · 옛 상가)은 사용승인이 공고보다 앞이라 안 이어진다. 이름은 안 본다. */
        IF OBJECT_ID('tempdb..#여덟') IS NOT NULL DROP TABLE #여덟;
        SELECT p.house_manage_no, p.pblanc_no, p.pnu, f.첫
          INTO #여덟
          FROM silver.applyhome_pblanc p
          JOIN (SELECT pnu, 첫 = MIN(REPLACE(LEFT(rcrit_pblanc_de, 10), '-', '')) FROM silver.applyhome_pblanc WHERE pnu IS NOT NULL GROUP BY pnu) f ON f.pnu = p.pnu
         WHERE NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no);
        IF OBJECT_ID('tempdb..#여덟단지') IS NOT NULL DROP TABLE #여덟단지;
        SELECT cp.pnu, n = COUNT(DISTINCT c.complex_id), complex_id = MIN(c.complex_id), 승인 = MIN(c.oldest_use_apr)
          INTO #여덟단지
          FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL
         WHERE cp.pnu IN (SELECT pnu FROM #여덟)
         GROUP BY cp.pnu;
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT e.house_manage_no, e.pblanc_no, d.complex_id, NULL,
               N'공고 지번 = 지금 단지 필지 · 그 필지의 단지 하나 · 단지 사용승인이 그 지번 첫 공고 이후', 0
          FROM #여덟 e JOIN #여덟단지 d ON d.pnu = e.pnu
         WHERE d.n = 1 AND LEN(d.승인) = 8 AND d.승인 >= e.첫;
        /* 아홉째 (402): 공고 지번 = 대장 없는 신축(K-apt) 지번 · 그 지번의 신축이 하나 · 그 필지에 지금 단지 없음 → 그 신축에 */
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT e.house_manage_no, e.pblanc_no, NULL, MIN(n.kapt_code),
               N'공고 지번 = 대장 없는 신축(K-apt) 지번 · 그 지번의 신축 하나 · 그 필지에 지금 단지 없음', 0
          FROM #여덟 e JOIN gold.v_newbuild n ON n.pnu = e.pnu
         WHERE NOT EXISTS (SELECT 1 FROM #여덟단지 d WHERE d.pnu = e.pnu)
           AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = e.house_manage_no AND l.pblanc_no = e.pblanc_no)
         GROUP BY e.house_manage_no, e.pblanc_no HAVING COUNT(DISTINCT n.kapt_code) = 1;
