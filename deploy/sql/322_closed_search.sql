/* ============================================================
   322_closed_search : 폐쇄·말소 대장을 **주소로도** 찾게 — 검색용 짧은 주소 칸 + 색인 (2026-10-23 사장님 "지도에 보이고 검색에 보이면 붙은 것")
   ★ 지번주소 '서울특별시 송파구 가락동 479번지' → '가락동 479' · 도로명주소 '서울특별시 송파구 송파대로 345 (가락동)' → '송파대로 345'
     (마지막 '구 ' 뒤 · '번지' · 괄호 뗌). 원문 칸은 그대로 두고 계산 칸만 더한다(PERSISTED · 색인 → 앞부분 일치로 바로 찾는다).
   ★ 처음엔 원문 주소 칸에 '%말%' 를 걸었다 — '가락동 479' 제안이 10초. 32만 줄을 훑어서다.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
GO
IF COL_LENGTH('gold.closed_site', '지번짧게') IS NULL
    ALTER TABLE gold.closed_site ADD 지번짧게 AS CAST(LTRIM(REPLACE(
        CASE WHEN CHARINDEX(N' 구', REVERSE(plat_plc)) > 0 THEN RIGHT(plat_plc, CHARINDEX(N' 구', REVERSE(plat_plc)) - 1) ELSE plat_plc END, N'번지', N'')) AS NVARCHAR(150)) PERSISTED;
IF COL_LENGTH('gold.closed_site', '도로짧게') IS NULL
    ALTER TABLE gold.closed_site ADD 도로짧게 AS CAST(LTRIM(
        LEFT(CASE WHEN CHARINDEX(N' 구', REVERSE(new_plat_plc)) > 0 THEN RIGHT(new_plat_plc, CHARINDEX(N' 구', REVERSE(new_plat_plc)) - 1) ELSE new_plat_plc END,
             CHARINDEX(N' (', CASE WHEN CHARINDEX(N' 구', REVERSE(new_plat_plc)) > 0 THEN RIGHT(new_plat_plc, CHARINDEX(N' 구', REVERSE(new_plat_plc)) - 1) ELSE new_plat_plc END + N' (') - 1)) AS NVARCHAR(150)) PERSISTED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_closed_site_jibun_s' AND object_id = OBJECT_ID('gold.closed_site'))
    CREATE INDEX ix_closed_site_jibun_s ON gold.closed_site (지번짧게) INCLUDE (이름, 총괄세대, 동수);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_closed_site_road_s' AND object_id = OBJECT_ID('gold.closed_site'))
    CREATE INDEX ix_closed_site_road_s ON gold.closed_site (도로짧게) INCLUDE (이름, 총괄세대, 동수);
GO
SELECT TOP 5 plat_plc, 지번짧게, new_plat_plc, 도로짧게 FROM gold.closed_site WHERE new_plat_plc IS NOT NULL ORDER BY NEWID();
