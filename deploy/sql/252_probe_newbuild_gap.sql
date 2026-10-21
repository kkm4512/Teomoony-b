/* 마커(v_newbuild.거래 = 704)와 상세(v_newbuild_trade.cnt 합 = 702)가 2건 다르다.
   원인 후보가 셋이라 **어느 것인지 재고** 고친다:
     ① 해제(취소) 거래  — 마커는 COUNT(*) 로 포함, 상세는 is_canceled=0 만
     ② 면적 없는 거래   — 상세 뷰가 COALESCE(exclu_use_ar, total_floor_ar) IS NOT NULL 로 버린다
     ③ building_ar 누락 — 단지 상세(tradeStats/jeonse)는 building_ar 까지 보는데 이 뷰는 안 본다
   ★ 장위자이레디언트 A10020716 의 pnu 로 전수 센다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @pnu CHAR(19) = (SELECT pnu FROM silver.kapt_complex
                          WHERE is_current = 1 AND kapt_code = 'A10020716');
SELECT pnu = @pnu,
       전체 = COUNT(*),
       해제 = SUM(CAST(r.is_canceled AS INT)),
       면적없음 = SUM(CASE WHEN COALESCE(r.exclu_use_ar, r.total_floor_ar) IS NULL
                          THEN 1 ELSE 0 END),
       면적없음_해제아님 = SUM(CASE WHEN COALESCE(r.exclu_use_ar, r.total_floor_ar) IS NULL
                                    AND r.is_canceled = 0 THEN 1 ELSE 0 END),
       building_ar만 = SUM(CASE WHEN COALESCE(r.exclu_use_ar, r.total_floor_ar) IS NULL
                                 AND r.building_ar IS NOT NULL THEN 1 ELSE 0 END),
       상세가세는것 = SUM(CASE WHEN r.is_canceled = 0
                               AND COALESCE(r.exclu_use_ar, r.total_floor_ar) IS NOT NULL
                               THEN 1 ELSE 0 END)
  FROM silver.rtms_trade r
 WHERE r.match_pnu = @pnu AND r.match_complex_id IS NULL;
