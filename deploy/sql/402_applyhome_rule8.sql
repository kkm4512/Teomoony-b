        /* 여덟째 (402 · 2026-11-01 사장님 "검색에서 같은 곳이 두 줄" → "ㄱㄱ"): 공고 지번 = 지금 단지 필지이고, 그 단지 사용승인이 그 지번 첫 공고 이후(= 그 공고로 지은 단지).
           ① 공고 지번(PNU 코드)의 지금 단지가 **하나**(다른 단지가 같은 필지에 있으면 막음) ② 그 단지 사용승인일 ≥ 그 지번의 첫 공고일(모든 공고 중) ③ 크기: 아파트 공고는 단지 세대 ≥ 공급 · 그 밖(민간임대 · 도시형 · 오피스텔)은 세대 또는 호 ≥ 공급(상가 · 화장실 같은 0세대 단지는 막힘)
           공고 전부터 있던 건물(재건축 · 리모델링 전 단지 · 옛 상가)은 사용승인이 공고보다 앞이라 안 이어진다. 이름은 안 본다. */
        IF OBJECT_ID('tempdb..#여덟') IS NOT NULL DROP TABLE #여덟;
        SELECT p.house_manage_no, p.pblanc_no, p.pnu, f.첫, p.tot_suply, p.공고종류
          INTO #여덟
          FROM silver.applyhome_pblanc p
          JOIN (SELECT pnu, 첫 = MIN(REPLACE(LEFT(rcrit_pblanc_de, 10), '-', '')) FROM silver.applyhome_pblanc WHERE pnu IS NOT NULL GROUP BY pnu) f ON f.pnu = p.pnu
         WHERE NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = p.house_manage_no AND l.pblanc_no = p.pblanc_no);
        IF OBJECT_ID('tempdb..#여덟단지0') IS NOT NULL DROP TABLE #여덟단지0;
        SELECT cp.pnu, n = COUNT(DISTINCT c.complex_id), complex_id = MIN(c.complex_id), 승인 = MIN(c.oldest_use_apr), 세대 = MIN(c.hhld_cnt_sum)
          INTO #여덟단지0
          FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id AND c.is_active = 1 AND c.merged_into IS NULL
         WHERE cp.pnu IN (SELECT pnu FROM #여덟)
         GROUP BY cp.pnu;
        IF OBJECT_ID('tempdb..#여덟단지') IS NOT NULL DROP TABLE #여덟단지;
        SELECT d.*, 호 = (SELECT SUM(t.ho_cnt) FROM gold.complex_bld cb JOIN silver.bld_title t ON t.mgm_bldrgst_pk = cb.mgm_bldrgst_pk AND t.is_current = 1
                          WHERE cb.complex_id = d.complex_id)
          INTO #여덟단지 FROM #여덟단지0 d;
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT e.house_manage_no, e.pblanc_no, d.complex_id, NULL,
               N'공고 지번 = 지금 단지 필지 · 그 필지의 단지 하나 · 단지 사용승인이 그 지번 첫 공고 이후', 0
          FROM #여덟 e JOIN #여덟단지 d ON d.pnu = e.pnu
         WHERE d.n = 1 AND LEN(d.승인) = 8 AND d.승인 >= e.첫
           /* ③ 크기가 맞을 때만 — 11-01 첫 적용에서 '래미안 원베일리(조합원 취소분)'(아파트 공고)이 같은 필지의 상가 단지(원베일리 스퀘어 · 0세대)에,
              '월명공원 한라비발디'(아파트 874)가 공중화장실에 붙었다. 아파트 공고(APT)는 단지 세대 ≥ 공급,
              그 밖(공공지원민간임대 · 도시형 · 오피스텔 — 대장에는 세대가 아니라 호로 적힌다)은 세대 ≥ 공급 또는 호 ≥ 공급 */
           AND ( (e.공고종류 = 'APT' AND ISNULL(d.세대, 0) > 0 AND d.세대 >= ISNULL(e.tot_suply, 0))
              OR (e.공고종류 <> 'APT' AND ((ISNULL(d.세대, 0) > 0 AND d.세대 >= ISNULL(e.tot_suply, 0)) OR (ISNULL(d.호, 0) > 0 AND d.호 >= ISNULL(e.tot_suply, 0)))) );
        /* 아홉째 (402): 공고 지번 = 대장 없는 신축(K-apt) 지번 · 그 지번의 신축이 하나 · 그 필지에 지금 단지 없음 → 그 신축에 */
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT e.house_manage_no, e.pblanc_no, NULL, MIN(n.kapt_code),
               N'공고 지번 = 대장 없는 신축(K-apt) 지번 · 그 지번의 신축 하나 · 그 필지에 지금 단지 없음', 0
          FROM #여덟 e JOIN gold.v_newbuild n ON n.pnu = e.pnu
         WHERE NOT EXISTS (SELECT 1 FROM #여덟단지 d WHERE d.pnu = e.pnu)
           AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = e.house_manage_no AND l.pblanc_no = e.pblanc_no)
         GROUP BY e.house_manage_no, e.pblanc_no HAVING COUNT(DISTINCT n.kapt_code) = 1;
        /* 열째 (402 · 11-01 사장님 "우리 데이터 안에서 확실하게 이을 수 있다면 이어서"): 공고 지번이 **사업 전 옛 지번**이라 지금 필지에 없는 곳(올림픽파크 포레온 공고 둔촌동 170-1 ↔ 단지 633).
           다리 = K-apt: K-apt 는 사업 전 지번으로 등록된 곳이 많고, 그 K-apt 는 이미 단지에 이어져 있다(gold.complex_kapt — 도로명코드 · 공식 지번 · 사용승인일로 이은 것).
           ① 공고 지번(PNU) = 그 K-apt 지번 ② 그 지번의 K-apt 가 가리키는 단지가 하나 ③ 그 지번에 다른 지금 단지(세대 있음)가 없음
           ④ 단지 사용승인 ≥ 그 지번 첫 공고일 ⑤ 크기(⑧과 같음: 아파트 공고는 세대 ≥ 공급). 이름은 안 본다. */
        IF OBJECT_ID('tempdb..#열') IS NOT NULL DROP TABLE #열;
        SELECT k.pnu, n = COUNT(DISTINCT ck.complex_id), complex_id = MIN(ck.complex_id)
          INTO #열
          FROM silver.kapt_complex k JOIN gold.complex_kapt ck ON ck.kapt_code = k.kapt_code
          JOIN gold.complex c ON c.complex_id = ck.complex_id AND c.is_active = 1 AND c.merged_into IS NULL
         WHERE k.is_current = 1 AND k.pnu IN (SELECT pnu FROM #여덟)
         GROUP BY k.pnu;
        INSERT INTO gold.applyhome_link (house_manage_no, pblanc_no, complex_id, kapt_code, 근거, 거리m)
        SELECT e.house_manage_no, e.pblanc_no, x.complex_id, NULL,
               N'공고 지번 = 단지에 이어진 K-apt 지번(사업 전 지번) · 그 지번의 단지 하나 · 사용승인이 첫 공고 이후 · 세대 ≥ 공급', 0
          FROM #여덟 e JOIN #열 x ON x.pnu = e.pnu
          JOIN gold.complex c ON c.complex_id = x.complex_id
         WHERE x.n = 1
           AND NOT EXISTS (SELECT 1 FROM gold.applyhome_link l WHERE l.house_manage_no = e.house_manage_no AND l.pblanc_no = e.pblanc_no)
           AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp JOIN gold.complex c2 ON c2.complex_id = cp.complex_id AND c2.is_active = 1 AND c2.merged_into IS NULL AND c2.hhld_cnt_sum > 0
                            WHERE cp.pnu = e.pnu AND cp.complex_id <> x.complex_id)
           AND LEN(c.oldest_use_apr) = 8 AND c.oldest_use_apr >= e.첫
           AND ( (e.공고종류 = 'APT' AND ISNULL(c.hhld_cnt_sum, 0) > 0 AND c.hhld_cnt_sum >= ISNULL(e.tot_suply, 0))
              OR (e.공고종류 <> 'APT' AND ISNULL(c.hhld_cnt_sum, 0) >= ISNULL(e.tot_suply, 0)) );
