/* 184b. 우리 단지는 서울 어느 구까지 들어와 있나 (2026-10-19) — 읽기 전용
   LH 평면도의 서울시 단지는 '서울수서KTX(행복)'(강남 수서동)과
   '서울양원'(중랑 망우본동) 둘뿐이다. 그 구가 우리 범위 안인지부터 본다. */
SET NOCOUNT ON;
SELECT 시군구 = sigungu_cd, 단지 = COUNT(*)
  FROM gold.complex WHERE is_active = 1
 GROUP BY sigungu_cd ORDER BY COUNT(*) DESC;
