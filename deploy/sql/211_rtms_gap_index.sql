/* 211. 미매칭 실거래 집계를 받칠 인덱스 (2026-10-20)

   ★ 왜: gold.v_newbuild_gap 이 요청마다 이걸 돌린다.
       SELECT match_pnu, COUNT(*) FROM silver.rtms_trade
        WHERE match_pnu IS NOT NULL AND match_complex_id IS NULL
        GROUP BY match_pnu
     gold.v_trade_offsite(상세의 '연결되지 않은 거래')와 gold.v_newbuild(지도의
     신축 마커)가 **둘 다** 이걸 거친다. 실거래가 오늘 100만 -> 1,053만 이 되면서
     같이 10배 느려졌다.

   실측 (2026-10-20, localhost 직렬)
     전체 실거래        10,597,587
     집계 대상(미매칭)     184,644   (전체의 1.7%)
     서로 다른 PNU           6,779   <- 결과는 이것뿐인데
     집계만 돌리면          1,204ms
     상세 전체 (단지 3개)  1,648 ~ 2,138ms  중 off 가 1,633 ~ 2,120ms

   ★ 왜 기존 인덱스로 안 되나
     ix_rtms_complex (match_complex_id, deal_ymd) 는 match_complex_id IS NULL 을
     찾아주지만 **match_pnu 가 없다.** 18만 건을 본문에서 다시 집어와야 한다.
     ix_rtms_pnu (match_pnu) 는 반대로 match_complex_id 가 없다.
     -> 둘을 한 인덱스에 담고, **미매칭만** 담는다(1.7%라 아주 작다).

   ★ 지금이 적기다
     실거래 적재가 **완주**해서(25구 x 10종목 250칸, 빈칸 0) 이 표에 쓰는 사람이
     없다. 앞줄(chain-all)은 silver.bld_*, 뒷줄(필지)은 silver.cadastral_parcel 을
     쓰므로 이 인덱스 생성과 겹치지 않는다.
     ★ 그래도 생성 중에는 이 표를 **읽는** 화면 질의가 잠깐 막힌다(수 초).

   ★ 되돌리기: DROP INDEX ix_rtms_gap ON silver.rtms_trade;
*/
IF NOT EXISTS (SELECT 1 FROM sys.indexes
                WHERE name = 'ix_rtms_gap'
                  AND object_id = OBJECT_ID('silver.rtms_trade'))
BEGIN
    CREATE INDEX ix_rtms_gap
        ON silver.rtms_trade (match_pnu)
     WHERE match_complex_id IS NULL AND match_pnu IS NOT NULL;
    PRINT '211 완료 - ix_rtms_gap 만듦';
END
ELSE
    PRINT '211 - ix_rtms_gap 이 이미 있습니다 (할 일 없음)';
GO

/* 검산 — 만들고 나서 같은 집계를 다시 재 본다. 1,204ms 에서 줄어야 한다. */
SET STATISTICS TIME ON;
SELECT 서로다른PNU = COUNT_BIG(*) FROM (
    SELECT match_pnu FROM silver.rtms_trade
     WHERE match_pnu IS NOT NULL AND match_complex_id IS NULL
     GROUP BY match_pnu) x;
SET STATISTICS TIME OFF;
