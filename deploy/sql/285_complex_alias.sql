/* 285 : 단지의 **실거래 이름** — 같은 이름 단지를 가르는 보조 이름 (2026-10-21)
   ★ 왜: 대장 이름이 정말 같다 — 길음뉴타운 4곳 · 경희궁자이 4곳 · 강일리버파크 10곳 …(같은 시군구 안 같은 이름 5,973묶음).
     대장으로는 못 가른다. 그런데 그 단지에 **코드(PNU)로 이미 붙은 실거래**가 들고 온 이름은 갈린다:
       길음뉴타운 → 2단지푸르지오 · 6단지(래미안) · 8단지(래미안) · 9단지(래미안) / 경희궁자이 → (1)·(2)·(3)·(4)단지
   ★ 이름으로 **잇지 않는다**(정책 1장) — 이은 것은 PNU 다. 이 표는 그 결과에 적힌 이름을 옆에 적을 뿐이다.
   ★ 조건: 아파트·연립·오피스텔 거래(해제 제외) 중 한 이름이 3건 이상이고 60% 이상일 때만. 대장 이름과 같으면 안 적는다.
   ★ 다시 굳히는 곳: 283(거래 다시 붙인 뒤) · load_rtms.py 매칭 패스 끝. 손으로는 EXEC gold.usp_refresh_complex_alias */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('gold.complex_alias') IS NULL
CREATE TABLE gold.complex_alias (
    complex_id  INT            NOT NULL CONSTRAINT pk_complex_alias PRIMARY KEY,
    실거래이름  NVARCHAR(200)  NOT NULL,
    건수        INT            NOT NULL,
    전체        INT            NOT NULL,
    굳힌시각    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_complex_alias_nm')
    CREATE INDEX ix_complex_alias_nm ON gold.complex_alias (실거래이름);
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_complex_alias
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t0 DATETIME2 = SYSDATETIME();
    IF OBJECT_ID('tempdb..#a') IS NOT NULL DROP TABLE #a;
    SELECT cid = r.match_complex_id, nm = LTRIM(RTRIM(r.bld_nm)), n = COUNT(*)
      INTO #a
      FROM silver.rtms_trade r
     WHERE r.match_complex_id IS NOT NULL AND r.is_canceled = 0
       AND NULLIF(LTRIM(RTRIM(r.bld_nm)), '') IS NOT NULL
       AND (r.trade_kind LIKE 'APT%' OR r.trade_kind LIKE 'RH%' OR r.trade_kind LIKE 'OFFI%')
     GROUP BY r.match_complex_id, LTRIM(RTRIM(r.bld_nm));
    IF OBJECT_ID('tempdb..#v') IS NOT NULL DROP TABLE #v;
    SELECT x.cid, x.nm, x.n, x.합
      INTO #v
      FROM (SELECT a.*, 합 = SUM(a.n) OVER (PARTITION BY a.cid),
                   rn = ROW_NUMBER() OVER (PARTITION BY a.cid ORDER BY a.n DESC, a.nm) FROM #a a) x
      JOIN gold.complex c ON c.complex_id = x.cid
     WHERE x.rn = 1 AND x.n >= 3 AND 100.0 * x.n / x.합 >= 60
       AND REPLACE(x.nm, ' ', '') <> REPLACE(ISNULL(c.complex_nm, ''), ' ', '');
    BEGIN TRAN;
        DELETE FROM gold.complex_alias;
        INSERT INTO gold.complex_alias (complex_id, 실거래이름, 건수, 전체)
        SELECT cid, nm, n, 합 FROM #v;
    COMMIT;
    SELECT 실거래이름 = (SELECT COUNT(*) FROM gold.complex_alias), 초 = DATEDIFF(SECOND, @t0, SYSDATETIME());
END
GO
