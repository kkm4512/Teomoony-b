/* 213. 디스크 기준 성능 — 인덱스 셋 (2026-10-20)
   사용자 지시: "캐시는 막 넣지마 ... 일단 디스크기준으로만 보고"

   ★ 건드리는 표를 먼저 골랐다 — **지금 쓰이고 있는 표는 손대지 않는다.**
     silver.rtms_trade   : 적재 **완주**. 아무도 안 쓴다            -> 건드린다
     gold.complex        : build 끝. 필지 끝에 centroid 만 UPDATE  -> 건드린다
     silver.cadastral_parcel : **필지 적재가 지금 쓰는 중**          -> 손대지 않는다
     silver.bld_*        : **앞줄이 지금 쓰는 중**                   -> 손대지 않는다

   ─────────────────────────────────────────────────────────────
   ① ix_rtms_gap 을 지운다 — 틀린 처방이었다
   ─────────────────────────────────────────────────────────────
   211 에서 (match_pnu) WHERE match_complex_id IS NULL 로 만들었는데,
   재 보니 옵티마이저가 안 썼고 **힌트로 강제하면 오히려 느렸다**
   (기본 222~808ms vs 강제 1,185~1,216ms, 여러 번 재서 일관).
   이유: 필터 칸인 match_complex_id 가 인덱스에 **없어서** 조건을 확인하러
   본문으로 되돌아간다. 쓰이지도 않는 인덱스는 쓰기만 느리게 한다.

   ─────────────────────────────────────────────────────────────
   ② ix_rtms_gap2 — 필터 칸을 **키에 넣는다**
   ─────────────────────────────────────────────────────────────
   gold.v_newbuild_gap 이 요청마다 도는 집계:
       WHERE match_pnu IS NOT NULL AND match_complex_id IS NULL
       GROUP BY match_pnu
   (match_complex_id, match_pnu) 순서면 IS NULL 로 찾아 들어가 match_pnu 가
   **이미 정렬된 채** 나온다 -> 본문 접근 없이 스트림 집계.
   gold.v_trade_offsite(상세)와 gold.v_newbuild(지도 신축)가 둘 다 이걸 탄다.

   ─────────────────────────────────────────────────────────────
   ③ ix_rtms_canceled — /api/health 의 COUNT 를 좁은 인덱스로
   ─────────────────────────────────────────────────────────────
   `COUNT(*) FROM silver.rtms_trade WHERE is_canceled = 0` 가 1,053만 행을
   훑는다. is_canceled 는 PERSISTED 계산 칸이라 인덱스를 걸 수 있다.
   좁은 인덱스만 훑으면 된다.

   ─────────────────────────────────────────────────────────────
   ④ ix_complex_sort — 검색의 전수 정렬을 없앤다
   ─────────────────────────────────────────────────────────────
   빈 검색어면 gold.v_complex_map 538,377행을 ORDER BY dong_cnt DESC 로
   **전수 정렬**한 뒤 TOP 200 을 집는다. 게다가 그 뷰에
   `meta.fn_pnu_to_jibun(c.rep_pnu)` — **행마다 도는 스칼라 함수**가 있어
   병렬화가 막힌다. 정렬 순서대로 읽는 인덱스가 있으면 TOP 200 에서
   **일찍 멈춘다**(그러면 함수도 200번만 돈다).
   ★ ORDER BY 와 **정확히 같은 순서**여야 멈출 수 있다.

   ★ 되돌리기: 아래 DROP 세 줄.
     DROP INDEX ix_rtms_gap2 ON silver.rtms_trade;
     DROP INDEX ix_rtms_canceled ON silver.rtms_trade;
     DROP INDEX ix_complex_sort ON gold.complex;
*/
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_rtms_gap'
            AND object_id=OBJECT_ID('silver.rtms_trade'))
BEGIN
    DROP INDEX ix_rtms_gap ON silver.rtms_trade;
    PRINT '213 - ix_rtms_gap 지움 (211 은 틀린 처방이었다)';
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_rtms_gap2'
                AND object_id=OBJECT_ID('silver.rtms_trade'))
CREATE INDEX ix_rtms_gap2 ON silver.rtms_trade (match_complex_id, match_pnu)
 WHERE match_pnu IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_rtms_canceled'
                AND object_id=OBJECT_ID('silver.rtms_trade'))
CREATE INDEX ix_rtms_canceled ON silver.rtms_trade (is_canceled);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_complex_sort'
                AND object_id=OBJECT_ID('gold.complex'))
CREATE INDEX ix_complex_sort ON gold.complex (dong_cnt DESC, pnu_cnt DESC, complex_id);
GO
PRINT '213 완료';
