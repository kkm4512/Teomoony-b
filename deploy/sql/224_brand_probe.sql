/* ============================================================
   224_brand_probe : 브랜드 매칭이 영문 표기를 얼마나 놓치나 (2026-10-20)

   왜: 사용자가 GS25계동 의 브랜드가 비어 있는 것을 보고 "고쳐라" 했다.
   고치기 전에 **세어 본다** — 어떤 영문 표기가 실제로 있고, 그 패턴이
   엉뚱한 상호를 끌어오지는 않는지. 특히 CU 는 두 글자라 위험하다.
   읽기만 한다. 아무것도 바꾸지 않는다.
   ============================================================ */
USE Teomoony;
GO
PRINT '--- 1) 편의점 안에서 음차 vs 영문 ---';
SELECT 총 = COUNT(*),
  씨유    = SUM(CASE WHEN bizes_nm LIKE N'%씨유%'     THEN 1 ELSE 0 END),
  CU영문  = SUM(CASE WHEN bizes_nm LIKE N'%CU%'       AND bizes_nm NOT LIKE N'%씨유%'     THEN 1 ELSE 0 END),
  지에스25= SUM(CASE WHEN bizes_nm LIKE N'%지에스25%' THEN 1 ELSE 0 END),
  GS영문  = SUM(CASE WHEN bizes_nm LIKE N'%GS25%'     AND bizes_nm NOT LIKE N'%지에스25%' THEN 1 ELSE 0 END),
  세븐    = SUM(CASE WHEN bizes_nm LIKE N'%세븐일레븐%' THEN 1 ELSE 0 END),
  세븐영문= SUM(CASE WHEN (bizes_nm LIKE N'%7-ELEVEN%' OR bizes_nm LIKE N'%7ELEVEN%' OR bizes_nm LIKE N'%SEVEN ELEVEN%')
                      AND bizes_nm NOT LIKE N'%세븐일레븐%' THEN 1 ELSE 0 END),
  이마트24= SUM(CASE WHEN bizes_nm LIKE N'%이마트24%' THEN 1 ELSE 0 END),
  EMART24 = SUM(CASE WHEN bizes_nm LIKE N'%EMART24%'  AND bizes_nm NOT LIKE N'%이마트24%' THEN 1 ELSE 0 END),
  미니스톱= SUM(CASE WHEN bizes_nm LIKE N'%미니스톱%' THEN 1 ELSE 0 END),
  MINISTOP= SUM(CASE WHEN bizes_nm LIKE N'%MINISTOP%' AND bizes_nm NOT LIKE N'%미니스톱%' THEN 1 ELSE 0 END)
FROM silver.semas_store WHERE is_current = 1 AND inds_scls_nm = N'편의점';
GO
PRINT '--- 2) CU 영문이 끌어온 상호를 눈으로 본다 (헛걸림 확인) ---';
SELECT 보기 = STRING_AGG(nm, N' | ') FROM (
  SELECT TOP 25 nm = bizes_nm FROM silver.semas_store
   WHERE is_current = 1 AND inds_scls_nm = N'편의점'
     AND bizes_nm LIKE N'%CU%' AND bizes_nm NOT LIKE N'%씨유%'
   GROUP BY bizes_nm ORDER BY COUNT(*) DESC) t;
GO
PRINT '--- 3) GS25 영문이 끌어온 상호 ---';
SELECT 보기 = STRING_AGG(nm, N' | ') FROM (
  SELECT TOP 25 nm = bizes_nm FROM silver.semas_store
   WHERE is_current = 1 AND inds_scls_nm = N'편의점'
     AND bizes_nm LIKE N'%GS25%' AND bizes_nm NOT LIKE N'%지에스25%'
   GROUP BY bizes_nm ORDER BY COUNT(*) DESC) t;
GO
PRINT '--- 4) 전체에서 카페·빵집·기타 브랜드 영문 표기 ---';
SELECT
  스타벅스  = SUM(CASE WHEN bizes_nm LIKE N'%스타벅스%'  THEN 1 ELSE 0 END),
  STARBUCKS = SUM(CASE WHEN bizes_nm LIKE N'%STARBUCK%'  AND bizes_nm NOT LIKE N'%스타벅스%'  THEN 1 ELSE 0 END),
  투썸      = SUM(CASE WHEN bizes_nm LIKE N'%투썸%'      THEN 1 ELSE 0 END),
  TWOSOME   = SUM(CASE WHEN bizes_nm LIKE N'%TWOSOME%'   AND bizes_nm NOT LIKE N'%투썸%'      THEN 1 ELSE 0 END),
  이디야    = SUM(CASE WHEN bizes_nm LIKE N'%이디야%'    THEN 1 ELSE 0 END),
  EDIYA     = SUM(CASE WHEN bizes_nm LIKE N'%EDIYA%'     AND bizes_nm NOT LIKE N'%이디야%'    THEN 1 ELSE 0 END),
  메가커피  = SUM(CASE WHEN bizes_nm LIKE N'%메가커피%'  THEN 1 ELSE 0 END),
  MEGA      = SUM(CASE WHEN bizes_nm LIKE N'%MEGACOFFEE%' OR bizes_nm LIKE N'%MEGA COFFEE%' THEN 1 ELSE 0 END),
  컴포즈     = SUM(CASE WHEN bizes_nm LIKE N'%컴포즈%'    THEN 1 ELSE 0 END),
  COMPOSE   = SUM(CASE WHEN bizes_nm LIKE N'%COMPOSE%'   AND bizes_nm NOT LIKE N'%컴포즈%'    THEN 1 ELSE 0 END),
  빽다방    = SUM(CASE WHEN bizes_nm LIKE N'%빽다방%'    THEN 1 ELSE 0 END),
  PAIK      = SUM(CASE WHEN bizes_nm LIKE N'%PAIK%'      AND bizes_nm NOT LIKE N'%빽다방%'    THEN 1 ELSE 0 END)
FROM silver.semas_store WHERE is_current = 1;
GO
PRINT '--- 5) 나머지 브랜드 영문 표기 ---';
SELECT
  파리바게뜨= SUM(CASE WHEN bizes_nm LIKE N'%파리바게뜨%' THEN 1 ELSE 0 END),
  PARIS     = SUM(CASE WHEN (bizes_nm LIKE N'%PARIS BAGUETTE%' OR bizes_nm LIKE N'%PARISBAGUETTE%') AND bizes_nm NOT LIKE N'%파리바게뜨%' THEN 1 ELSE 0 END),
  뚜레쥬르  = SUM(CASE WHEN bizes_nm LIKE N'%뚜레쥬르%'  THEN 1 ELSE 0 END),
  TOUS      = SUM(CASE WHEN bizes_nm LIKE N'%TOUS LES%'  AND bizes_nm NOT LIKE N'%뚜레쥬르%'  THEN 1 ELSE 0 END),
  맥도날드  = SUM(CASE WHEN bizes_nm LIKE N'%맥도날드%'  THEN 1 ELSE 0 END),
  MCDONALD  = SUM(CASE WHEN bizes_nm LIKE N'%MCDONALD%'  AND bizes_nm NOT LIKE N'%맥도날드%'  THEN 1 ELSE 0 END),
  버거킹    = SUM(CASE WHEN bizes_nm LIKE N'%버거킹%'    THEN 1 ELSE 0 END),
  BURGERKING= SUM(CASE WHEN (bizes_nm LIKE N'%BURGER KING%' OR bizes_nm LIKE N'%BURGERKING%') AND bizes_nm NOT LIKE N'%버거킹%' THEN 1 ELSE 0 END),
  롯데리아  = SUM(CASE WHEN bizes_nm LIKE N'%롯데리아%'  THEN 1 ELSE 0 END),
  LOTTERIA  = SUM(CASE WHEN bizes_nm LIKE N'%LOTTERIA%'  AND bizes_nm NOT LIKE N'%롯데리아%'  THEN 1 ELSE 0 END),
  올리브영  = SUM(CASE WHEN bizes_nm LIKE N'%올리브영%'  THEN 1 ELSE 0 END),
  OLIVE     = SUM(CASE WHEN (bizes_nm LIKE N'%OLIVE YOUNG%' OR bizes_nm LIKE N'%OLIVEYOUNG%') AND bizes_nm NOT LIKE N'%올리브영%' THEN 1 ELSE 0 END),
  다이소    = SUM(CASE WHEN bizes_nm LIKE N'%다이소%'    THEN 1 ELSE 0 END),
  DAISO     = SUM(CASE WHEN bizes_nm LIKE N'%DAISO%'     AND bizes_nm NOT LIKE N'%다이소%'    THEN 1 ELSE 0 END),
  노브랜드  = SUM(CASE WHEN bizes_nm LIKE N'%노브랜드%'  THEN 1 ELSE 0 END),
  NOBRAND   = SUM(CASE WHEN (bizes_nm LIKE N'%NO BRAND%' OR bizes_nm LIKE N'%NOBRAND%') AND bizes_nm NOT LIKE N'%노브랜드%' THEN 1 ELSE 0 END)
FROM silver.semas_store WHERE is_current = 1;
GO
