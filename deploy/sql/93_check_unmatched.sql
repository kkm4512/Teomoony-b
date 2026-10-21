SET NOCOUNT ON;
USE Teomoony;
GO
/* 93_check_unmatched : PNU 는 조립됐는데 단지가 없는 거래 (읽기 전용)

   장위동 645건. 종로구에서는 9건뿐이었다.
   가설 A: 재개발로 멸실 -> 지번은 있는데 건축물대장 현재행이 없다
   가설 B: 지번 파싱이 틀려 엉뚱한 PNU 를 만들었다
   필지에는 있는데 대장에만 없으면 A, 둘 다 없으면 B 쪽이다.

   ★ 배치를 GO 로 나눈다. 한 덩어리로 두면 아래쪽 구문 오류 하나에
     위쪽 질의까지 통째로 안 돈다(파싱이 배치 단위라서). */

PRINT '=== 1. 미매칭 건의 PNU 가 어디에 있나 ===';
SELECT 미매칭 = COUNT(*),
       필지에있음 = SUM(CASE WHEN p.pnu IS NOT NULL THEN 1 ELSE 0 END),
       대장에있음 = SUM(CASE WHEN b.pnu IS NOT NULL THEN 1 ELSE 0 END),
       둘다없음 = SUM(CASE WHEN p.pnu IS NULL AND b.pnu IS NULL THEN 1 ELSE 0 END)
FROM silver.rtms_trade r
OUTER APPLY (SELECT TOP 1 pnu FROM silver.cadastral_parcel
              WHERE pnu = r.match_pnu AND is_current = 1) p
OUTER APPLY (SELECT TOP 1 pnu FROM silver.bld_basis_outline
              WHERE pnu = r.match_pnu AND is_current = 1) b
WHERE r.match_pnu IS NOT NULL AND r.match_complex_id IS NULL
  AND LEFT(r.match_pnu, 10) = '1129013800';
GO

PRINT '';
PRINT '=== 2. 종목별 ===';
SELECT trade_kind, 건수 = COUNT(*)
FROM silver.rtms_trade
WHERE match_pnu IS NOT NULL AND match_complex_id IS NULL
  AND LEFT(match_pnu,10) = '1129013800'
GROUP BY trade_kind ORDER BY COUNT(*) DESC;
GO

PRINT '';
PRINT '=== 3. 거래 연도별 (재개발 멸실이면 과거에 몰린다) ===';
SELECT deal_year, 미매칭 = COUNT(*)
FROM silver.rtms_trade
WHERE match_pnu IS NOT NULL AND match_complex_id IS NULL
  AND LEFT(match_pnu,10) = '1129013800'
GROUP BY deal_year ORDER BY deal_year;
GO

PRINT '';
PRINT '=== 4. 미매칭이 몰린 지번 상위 ===';
/* 집계 함수 안에 서브쿼리를 넣을 수 없다. 먼저 행마다 판정해 두고 집계한다. */
WITH u AS (
    SELECT r.jibun, r.bld_nm,
           CASE WHEN p.pnu IS NOT NULL THEN 1 ELSE 0 END AS has_parcel,
           CASE WHEN b.pnu IS NOT NULL THEN 1 ELSE 0 END AS has_bld
    FROM silver.rtms_trade r
    OUTER APPLY (SELECT TOP 1 pnu FROM silver.cadastral_parcel
                  WHERE pnu = r.match_pnu AND is_current = 1) p
    OUTER APPLY (SELECT TOP 1 pnu FROM silver.bld_basis_outline
                  WHERE pnu = r.match_pnu AND is_current = 1) b
    WHERE r.match_pnu IS NOT NULL AND r.match_complex_id IS NULL
      AND LEFT(r.match_pnu,10) = '1129013800'
)
SELECT TOP 15 jibun, bld_nm, 건수 = COUNT(*),
       필지있음 = MAX(has_parcel), 대장있음 = MAX(has_bld)
FROM u GROUP BY jibun, bld_nm ORDER BY COUNT(*) DESC;
GO
