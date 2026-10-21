/* 중심좌표가 없는 단지 (2026-10-19)
   AI 검색 결과를 눌렀더니 'geography::Point failed ... parameter 1 is not
   allowed to be null' 로 죽었다. 얼마나 되는지 세어서 본다. */
SET NOCOUNT ON;
SELECT 지역 = CASE sigungu_cd
                WHEN '11110' THEN '종로' WHEN '11290' THEN '성북'
                WHEN '11380' THEN '은평' WHEN '11650' THEN '서초(양재)'
                WHEN '41171' THEN '안양만안' WHEN '41173' THEN '안양동안'
                ELSE sigungu_cd END,
       단지 = COUNT(*),
       좌표있음 = SUM(CASE WHEN centroid_lat IS NOT NULL
                            AND centroid_lng IS NOT NULL THEN 1 ELSE 0 END),
       좌표없음 = SUM(CASE WHEN centroid_lat IS NULL
                            OR centroid_lng IS NULL THEN 1 ELSE 0 END)
  FROM gold.complex WHERE is_active = 1
 GROUP BY sigungu_cd ORDER BY sigungu_cd;

/* 아까 누른 그 단지 */
SELECT complex_id, complex_nm, centroid_lat, centroid_lng, rep_pnu
  FROM gold.complex WHERE complex_id = 119686;
