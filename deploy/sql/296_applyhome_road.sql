/* ============================================================
   296_applyhome_road : 청약홈 공고 주소가 **도로명**일 때 대장 도로명과 대조해 지번을 찾는다 (2026-10-21 밤)
   ★ '못 품' 42건 대부분이 "도봉로 232 (미아동)" 꼴이었다 — 지번이 없다.
     load_applyhome.py 가 도로명 · 건물번호만 떼어 두면(주소_도로 · 주소_건물본번/부번), 여기서
     silver.bld_title.new_plat_plc('서울특별시 강북구 도봉로 232 (미아동)') 와 **문자 그대로** 맞춰 본다.
   ★ 후보 지번이 **정확히 하나**일 때만 채운다. 둘 이상이면 비워 둔다(정책 1장 — 추측하지 않는다).
     블록 지번(plat_gb 2)은 PNU 가 안 되므로 쓰지 않는다.
   ★ 이름으로 잇지 않는다 — 주소(도로명 + 건물번호)는 식별자다.
   ★ 동 이름은 있는데 법정동 코드를 못 찾은 공고도 여기서 한 번 더(시군구 + 동, 후보 1).
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF COL_LENGTH('silver.applyhome_pblanc', '주소_도로') IS NULL
    ALTER TABLE silver.applyhome_pblanc ADD 주소_도로 NVARCHAR(80) NULL, 주소_건물본번 INT NULL, 주소_건물부번 INT NULL;
GO
IF COL_LENGTH('silver.applyhome_pblanc', '주소근거') < 120
    ALTER TABLE silver.applyhome_pblanc ALTER COLUMN 주소근거 NVARCHAR(60) NULL;
GO
CREATE OR ALTER PROCEDURE gold.usp_applyhome_road_to_jibun
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @동 INT = 0, @도로 INT = 0;

    /* ① 동 이름 → 법정동 (시군구 + 동, 후보 1) */
    UPDATE p SET lawd_cd = l.cd
      FROM silver.applyhome_pblanc p
     CROSS APPLY (SELECT cd = MIN(lc.lawd_cd), n = COUNT(*) FROM meta.lawd_code lc
                   WHERE lc.ri_nm IS NULL AND lc.is_abolished = 0 AND lc.emd_nm = p.주소_동
                     AND REPLACE(lc.sgg_nm, ' ', '') = p.주소_시군구
                     AND (LEFT(lc.lawd_cd, 2) = '11' OR LEFT(lc.lawd_cd, 5) IN ('41171', '41173'))) l
     WHERE p.lawd_cd IS NULL AND p.주소_동 IS NOT NULL AND l.n = 1;
    SET @동 = @@ROWCOUNT;

    /* ② 도로명 + 건물번호 → 대장 지번 (후보 1) */
    IF OBJECT_ID('tempdb..#w') IS NOT NULL DROP TABLE #w;
    SELECT p.house_manage_no, p.pblanc_no, s.sgg_cd,
           pat = N'% ' + p.주소_도로 + N' ' + CAST(p.주소_건물본번 AS NVARCHAR(10))
                 + ISNULL(N'-' + CAST(p.주소_건물부번 AS NVARCHAR(10)), N'')
      INTO #w
      FROM silver.applyhome_pblanc p
     CROSS APPLY (SELECT sgg_cd = MIN(LEFT(lc.lawd_cd, 5)), n = COUNT(DISTINCT LEFT(lc.lawd_cd, 5)) FROM meta.lawd_code lc
                   WHERE lc.is_abolished = 0 AND REPLACE(lc.sgg_nm, ' ', '') = p.주소_시군구
                     AND (LEFT(lc.lawd_cd, 2) = '11' OR LEFT(lc.lawd_cd, 5) IN ('41171', '41173'))) s
     WHERE p.lawd_cd IS NULL AND p.주소_도로 IS NOT NULL AND p.주소_건물본번 IS NOT NULL AND s.n = 1
       AND p.주소_도로 NOT LIKE N'%[%[_]%';

    IF OBJECT_ID('tempdb..#m') IS NOT NULL DROP TABLE #m;
    SELECT DISTINCT w.house_manage_no, w.pblanc_no, b.sigungu_cd, b.bjdong_cd, b.plat_gb_cd, b.bun, b.ji
      INTO #m
      FROM #w w JOIN silver.bld_title b
        ON b.is_current = 1 AND b.sigungu_cd = w.sgg_cd
       AND (b.new_plat_plc LIKE w.pat + N' %' OR b.new_plat_plc LIKE w.pat)
     WHERE b.bjdong_cd IS NOT NULL AND b.bun IS NOT NULL AND ISNULL(b.plat_gb_cd, '0') IN ('0', '1');

    UPDATE p SET lawd_cd = m.sigungu_cd + m.bjdong_cd,
                 주소_산 = CASE WHEN m.plat_gb_cd = '1' THEN '1' ELSE '0' END,
                 주소_본번 = CAST(TRY_CAST(m.bun AS INT) AS VARCHAR(10)),
                 주소_부번 = CAST(ISNULL(TRY_CAST(m.ji AS INT), 0) AS VARCHAR(10)),
                 주소_동 = ISNULL(p.주소_동, (SELECT TOP 1 lc.emd_nm FROM meta.lawd_code lc WHERE lc.lawd_cd = m.sigungu_cd + m.bjdong_cd)),
                 주소근거 = N'도로명 → 대장 지번(후보 1)'
      FROM silver.applyhome_pblanc p
      JOIN #m m ON m.house_manage_no = p.house_manage_no AND m.pblanc_no = p.pblanc_no
     WHERE p.lawd_cd IS NULL
       AND (SELECT COUNT(*) FROM #m m2 WHERE m2.house_manage_no = m.house_manage_no AND m2.pblanc_no = m.pblanc_no) = 1;
    SET @도로 = @@ROWCOUNT;
    PRINT CONCAT(N'296: 동 이름으로 ', @동, N' · 도로명으로 ', @도로);
END
GO
