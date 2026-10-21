/* 292 : 단지 없는 거래를 모으는 두 뷰에서 분양권·입주권(SILV_TRADE)을 뺀다 (2026-10-21)
   ★ v_newbuild_gap(→ v_trade_offsite · v_newbuild) · v_newbuild_trade 는 match_complex_id IS NULL 인 거래를 PNU 로 모은다.
     분양권은 일부러 단지에 안 붙이므로(291) 여기 들어와 **매매처럼** 집계된다 — 장위자이레디언트처럼 K-apt 지번이 사업 전 지번이면 섞인다.
     분양권은 분양 칸(청약홈)에서 따로 보인다.
   ★ 뷰 정의는 **DB 에 있는 것 그대로** 꺼내 조건 한 줄만 끼운다(파일이 여러 벌이라 파일을 믿지 않는다). 끼울 자리가 정확히 하나일 때만. */
SET NOCOUNT ON;
DECLARE @d NVARCHAR(MAX), @o NVARCHAR(400), @n INT;
SET @d = OBJECT_DEFINITION(OBJECT_ID('gold.v_newbuild_gap'));
SET @o = N'WHERE match_pnu IS NOT NULL AND match_complex_id IS NULL';
SET @n = (LEN(@d) - LEN(REPLACE(@d, @o, N''))) / LEN(@o);
IF @n = 1 AND @d NOT LIKE N'%SILV%'
BEGIN
    SET @d = REPLACE(@d, @o, @o + N' AND trade_kind NOT LIKE ''SILV%''   /* 292 분양권 제외 */');
    SET @d = STUFF(@d, CHARINDEX(N'CREATE VIEW', @d), LEN(N'CREATE VIEW'), N'CREATE OR ALTER VIEW');
    EXEC sp_executesql @d;
END
SELECT 뷰 = 'gap', 자리 = @n, 분양권제외 = CASE WHEN OBJECT_DEFINITION(OBJECT_ID('gold.v_newbuild_gap')) LIKE N'%SILV%' THEN 1 ELSE 0 END;
GO
SET NOCOUNT ON;
DECLARE @d NVARCHAR(MAX), @o NVARCHAR(400), @n INT;
SET @d = OBJECT_DEFINITION(OBJECT_ID('gold.v_newbuild_trade'));
SET @o = N'  AND r.match_complex_id IS NULL';
SET @n = (LEN(@d) - LEN(REPLACE(@d, @o, N''))) / LEN(@o);
IF @n = 1 AND @d NOT LIKE N'%SILV%'
BEGIN
    SET @d = REPLACE(@d, @o, @o + NCHAR(13) + NCHAR(10) + N'  AND r.trade_kind NOT LIKE ''SILV%''   /* 292 분양권 제외 */');
    SET @d = STUFF(@d, CHARINDEX(N'CREATE VIEW', @d), LEN(N'CREATE VIEW'), N'CREATE OR ALTER VIEW');
    EXEC sp_executesql @d;
END
SELECT 뷰 = 'trade', 자리 = @n, 분양권제외 = CASE WHEN OBJECT_DEFINITION(OBJECT_ID('gold.v_newbuild_trade')) LIKE N'%SILV%' THEN 1 ELSE 0 END;
