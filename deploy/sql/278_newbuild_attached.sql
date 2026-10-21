/* 278. gold.v_newbuild — 부속지번까지 대장이 있는 지번은 '신축(대장 없음)' 에서 뺀다 (2026-10-21 QA)
   ★ 왜: '대장 없는 신축' 24곳 중 6곳은 K-apt 지번이 기존 단지의 **부속지번(ATTACHED)** 이었다.
     옛 판정(gold.v_pnu_bld.표제부 = 0)은 그 지번에 **표제부**가 있는지만 봐서 놓쳤다 —
     표제부는 대표지번에 있고 이 지번은 부속이라 0 으로 보였다.
       동소문한신휴플러스 409세대 ↔ 동소문2차 한신휴플러스 409세대
       길음뉴타운11단지 롯데캐슬골든힐스 399 ↔ 399 · 셀립은평 201 ↔ 한화생명 불광동사옥 201 …
     그래서 지도에 **같은 아파트가 두 번** 찍혔다(단지 마커 + 신축 마커).
   ★ 잃는 것 없음: 그 지번의 실거래는 complex_pnu 로 이미 그 단지에 붙어 있어 신축 쪽 '거래' 는 6곳 모두 0 이었다.
   ★ 속도: 436ms → 155ms (뺄 것을 먼저 거른다).
   ★ 남은 숙제(이 파일이 안 푼 것): K-apt 로 **기존 단지와 이어진**(gold.v_complex_kapt) 신축이 더 있다 —
     래미안퍼스트하이 ↔ 49101 등 12곳. 그 뷰가 무거워(2.2초) 지도 마커에 못 쓴다. 사장님 판단 대기(CONTEXT 11-146).
   ★ 바탕은 DB 의 현재 정의(17_newbuild.sql 의 2026-10-21 cnt 수정 포함)다. 바꾼 곳은 맨 아래 WHERE 한 줄뿐. */
CREATE OR ALTER VIEW gold.v_newbuild
AS
SELECT k.kapt_code,
       k.kapt_name,
       k.pnu,
       k.bjd_code,
       lawd_nm      = l.emd_nm,
       k.kapt_addr,
       k.doro_juso,
       세대          = k.ho_cnt,
       동수          = k.dong_cnt,
       사용승인       = k.kapt_usedate,
       k.top_floor,
       난방          = k.code_heat_nm,
       시공          = k.bcompany,
       시행          = k.acompany,
       거래          = ISNULL(t.cnt, 0),
       최근거래       = t.last_ymd,
       최고가         = t.max_amount,
       centroid_lat = p.centroid_lat,
       centroid_lng = p.centroid_lng,
       인허가         = ISNULL(a.cnt, 0)
FROM silver.kapt_complex k
/* 그 법정동 대장을 적재했는가. 안 했으면 "대장이 없다" 고 말할 수 없다. */
JOIN meta.v_lawd_scope sc ON sc.lawd_cd = k.bjd_code
LEFT JOIN meta.lawd_code l ON l.lawd_cd = k.bjd_code
LEFT JOIN gold.v_pnu_bld b ON b.pnu     = k.pnu
OUTER APPLY (
    SELECT TOP 1 centroid_lat, centroid_lng
    FROM silver.cadastral_parcel cp
    WHERE cp.is_current = 1 AND cp.pnu = k.pnu AND cp.centroid_lat IS NOT NULL
    ORDER BY cp.pnu
) p
OUTER APPLY (
    /* 2026-10-21 QA: 해제는 건수·범위에서 빼고 따로 센다(CONTEXT 4-5 · 11-117). */
    SELECT cnt = SUM(CASE WHEN r.is_canceled = 0 THEN 1 ELSE 0 END),
           해제 = SUM(CAST(r.is_canceled AS INT)),
           last_ymd = MAX(CASE WHEN r.is_canceled = 0 THEN r.deal_ymd END),
           max_amount = MAX(CASE WHEN r.is_canceled = 0 AND r.is_rent = 0
                                 THEN r.deal_amount END)
    FROM silver.rtms_trade r
    WHERE r.match_pnu = k.pnu AND r.match_complex_id IS NULL
) t
OUTER APPLY (
    SELECT cnt = COUNT(*) FROM silver.arch_permit ap
    WHERE ap.is_current = 1 AND ap.pnu = k.pnu
) a
WHERE k.is_current = 1
  AND k.pnu IS NOT NULL
  AND ISNULL(b.표제부, 0) = 0      -- 대장(표제부)이 아직 없다
  /* 278: 부속지번으로라도 어느 단지에 들어 있으면 대장이 있는 것이다 */
  AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = k.pnu);
GO
SELECT 신축 = COUNT(*) FROM gold.v_newbuild;
