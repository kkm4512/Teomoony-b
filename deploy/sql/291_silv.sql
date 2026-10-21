/* 291 : 분양권·입주권 전매 실거래(SILV_TRADE) 받을 준비 (2026-10-21)
   ★ silver.rtms_trade 에 ownership_gbn(분양권 '분' / 입주권 '입') 칸. NULL 허용 칸 추가라 표를 다시 쓰지 않는다.
   ★ 분양권은 단지에 안 붙인다 — 282 의 usp_match_complex_trade 가 SILV 를 건너뛰게 고쳤다(그 파일을 다시 올린다).
     잇는 곳은 청약홈 공고(같은 사업 전 지번 → PNU 같음). */
SET NOCOUNT ON;
GO
IF COL_LENGTH('silver.rtms_trade', 'ownership_gbn') IS NULL
    ALTER TABLE silver.rtms_trade ADD ownership_gbn NVARCHAR(10) NULL;
GO
SELECT 칸 = COL_LENGTH('silver.rtms_trade', 'ownership_gbn');
