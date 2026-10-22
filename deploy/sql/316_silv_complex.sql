/* ============================================================
   316_silv_complex : 단지의 분양권·입주권 거래 — **한 곳에서** 고른다 (2026-10-22 사장님 "매매 탭에 섞고 분양권임을 표시")
   ★ 단지 상세의 실거래(매매 목록)와 분양·청약 칸이 **같은 함수**를 쓴다 — 두 곳에서 따로 만들면 갈라진다(작업방식 10장).
   ★ 두 길(이름은 안 본다):
     ① 공고 지번 — 이 단지에 이어진 청약 공고의 지번(+ 그 공고의 K-apt 지번 · 이 단지 필지), 첫 모집공고일 이후 계약
        + 입주권(ownership_gbn='입')은 공고 **전** 10년까지 — 조합원 권리는 일반분양 공고 전에 먼저 거래된다(2026-10-22 사장님 "입 ㄱㄱ")
     ② 같은 필지 · 거래 뒤 준공 — 이 단지 필지 · 이 단지 사용승인일 이전 계약 · 세대 있는 단지 · 같은 필지에 거래 뒤 준공된 다른 세대 단지가 없을 때
   ★ silver.rtms_trade.match_complex_id 에는 넣지 않는다 — 최고가(288) · 평당 · 전세가율 · AI 검색 · 지역 순위에 분양가가 섞이지 않게. 목록에만.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER FUNCTION gold.fn_complex_silv (@cid INT)
RETURNS TABLE
AS RETURN
WITH k AS (SELECT DISTINCT l.house_manage_no, l.pblanc_no FROM gold.applyhome_link l WHERE l.complex_id = @cid),
pn AS (
    SELECT p.pnu FROM k JOIN silver.applyhome_pblanc p ON p.house_manage_no = k.house_manage_no AND p.pblanc_no = k.pblanc_no WHERE p.pnu IS NOT NULL
    UNION SELECT kc.pnu FROM k JOIN gold.applyhome_link l ON l.house_manage_no = k.house_manage_no AND l.pblanc_no = k.pblanc_no
      JOIN silver.kapt_complex kc ON kc.kapt_code = l.kapt_code AND kc.is_current = 1 WHERE kc.pnu IS NOT NULL
    UNION SELECT cp.pnu FROM k JOIN gold.applyhome_link l ON l.house_manage_no = k.house_manage_no AND l.pblanc_no = k.pblanc_no
      JOIN gold.complex_pnu cp ON cp.complex_id = l.complex_id),
첫 AS (SELECT v = REPLACE(MIN(p.rcrit_pblanc_de), '-', '') FROM k JOIN silver.applyhome_pblanc p ON p.house_manage_no = k.house_manage_no AND p.pblanc_no = k.pblanc_no),
c AS (SELECT 준공 = CASE WHEN LEN(oldest_use_apr) = 8 AND hhld_cnt_sum > 0 THEN oldest_use_apr END FROM gold.complex WHERE complex_id = @cid),
a AS (
    SELECT t.trade_sk, 근거 = CAST(CASE WHEN t.deal_ymd >= 첫.v THEN N'공고 지번' ELSE N'공고 지번 · 공고 전 입주권' END AS NVARCHAR(30))
      FROM silver.rtms_trade t CROSS JOIN 첫
     WHERE t.trade_kind LIKE 'SILV%' AND 첫.v IS NOT NULL AND t.match_pnu IN (SELECT pnu FROM pn)
       AND (t.deal_ymd >= 첫.v
            OR (t.ownership_gbn = N'입' AND t.deal_ymd >= CONVERT(CHAR(8), DATEADD(YEAR, -10, CONVERT(DATE, 첫.v)), 112)))),
b AS (
    SELECT t.trade_sk, 근거 = CAST(N'같은 필지 · 거래 뒤 준공' AS NVARCHAR(30))
      FROM silver.rtms_trade t CROSS JOIN c
     WHERE c.준공 IS NOT NULL AND t.trade_kind LIKE 'SILV%' AND t.deal_ymd <= c.준공
       AND t.match_pnu IN (SELECT cp.pnu FROM gold.complex_pnu cp WHERE cp.complex_id = @cid)
       AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp2 JOIN gold.complex c2 ON c2.complex_id = cp2.complex_id AND c2.is_active = 1
                        WHERE cp2.pnu = t.match_pnu AND c2.complex_id <> @cid AND c2.hhld_cnt_sum > 0
                          AND LEN(c2.oldest_use_apr) = 8 AND c2.oldest_use_apr >= t.deal_ymd))
SELECT trade_sk, 근거 FROM a
UNION ALL
SELECT b.trade_sk, b.근거 FROM b WHERE NOT EXISTS (SELECT 1 FROM a WHERE a.trade_sk = b.trade_sk);
GO
SELECT n = COUNT(*) FROM gold.fn_complex_silv(545277);
