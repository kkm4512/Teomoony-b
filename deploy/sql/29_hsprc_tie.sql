SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   29_hsprc_tie : 동률을 쪼개지 않는 분위 — 2026-10-17

   27_hsprc 는 NTILE(5) 를 썼다. NTILE 은 **값이 같아도 행 수를 기준으로**
   다섯 덩이를 만든다. 그래서 같은 금액이 서로 다른 분위를 받았다:

       115동 13층 3라인  757,000,000  라인분위 3
       115동 16층 3라인  757,000,000  라인분위 4      <- 같은 금액

   한 라인 16개 호 중 10개가 최고가로 동률이면 그 10개가 3/4/5 분위로 흩어진다.
   배치도 색 모드의 의도가 "같은 라인을 세로로 훑으면 층 프리미엄이 보인다" 인데,
   ★ 실제로는 **없는 그라데이션이 보인다.** 측정 도구가 패턴을 만들어 낸 것이다.

   ────────────────────────────────────────────────────────────
   ★ 1차 수정은 PERCENT_RANK 였고, 그것도 틀렸다 (같은 날 실측).

     PERCENT_RANK = (순위-1)/(전체-1) 이라 **1.0 에 닿는 것은 동률 없는 단독 1등뿐**이다.
     돈암동 최고가 757,000,000 은 28호 동률이라 0.9748 에서 멈췄고,
     1 + FLOOR(4*pr) 로는 4분위가 천장이 된다. 실측 분포:

         PERCENT_RANK   1:313  2:226  3:279  4:256  5:**0**
         CUME_DIST      1:212  2:157  3:257  4:210  5:238

     색 단계를 다섯 개 만들어 놓고 네 개만 쓰고 있었다.

     CUME_DIST = (이 값 이하인 행 수)/(전체) 다. 범위가 (0, 1] 이라
     **최상위 동률 그룹이 정확히 1.0 을 받는다.** CEILING(5*cd) 로 1~5 가 다 나온다.
     의미도 이쪽이 맞다 — "이 가격 이하가 전체의 몇 %인가" 가 분위다.
   ────────────────────────────────────────────────────────────

   ★ 구간 안에 값이 한 종류뿐이면 분위를 NULL 로 둔다.
     그때 모든 행이 cd = 1.0 을 받아 **전부 5분위(제일 비싼 칸)로 칠해진다.**
     "차이가 없다" 와 "제일 비싸다" 는 다른 말이다.
     6장 빈칸 어휘의 NA(해당 없음) 에 해당한다.

   ★ COUNT(DISTINCT x) OVER () 는 SQL Server 가 거부한다 (창 함수에 DISTINCT 불가).
     양방향 DENSE_RANK 합 - 1 이 구간 내 고유값 개수다.
   ============================================================ */
USE Teomoony;
GO

/* ────────────────────────────────────────────────────────────
   ★ 2026-10-17 성능 — 단지 하나를 여는데 테이블 전체를 정렬하고 있었다.

     처음 구조는 이랬다:

         l AS (SELECT ... ROW_NUMBER() OVER (PARTITION BY mgm_bldrgst_pk ...)
                 FROM silver.bld_hsprc)        <- 여기엔 complex_id 가 없다
         j AS (gold.v_complex_ho JOIN l)
         r AS (... 분위 ...)

     화면은 `WHERE complex_id = @c` 로 부른다. 그런데 그 조건이 **창 함수
     아래로 못 내려간다** — 옵티마이저는 파티션 키에 들어 있는 컬럼으로만
     술어를 밀어낼 수 있는데, l 의 파티션 키는 mgm_bldrgst_pk 뿐이다.
     그래서 단지 하나를 열 때마다 bld_hsprc **전체**에 창 함수가 돌았다.

     2만 행일 때는 안 보였다. 주택가격을 전국으로 넓히는 중에 드러났고,
     적재(쓰기 잠금)와 겹치자 화면이 아예 안 떴다.
     ★ 적재 중에 화면을 열어 보지 않았으면 못 봤을 종류다.

     고친 방법: 먼저 조인해서 complex_id 를 끌어온 뒤, **모든 창 함수의
     파티션 맨 앞에 complex_id 를 둔다.** 호PK 가 단지를 결정하므로 결과는
     같고, 술어는 내려간다.
   ──────────────────────────────────────────────────────────── */
IF OBJECT_ID('gold.v_complex_ho_price') IS NOT NULL DROP VIEW gold.v_complex_ho_price;
GO
CREATE VIEW gold.v_complex_ho_price
AS
WITH j AS (
    SELECT h.complex_id, h.호PK, h.동PK, h.동, h.층, h.호, h.라인,
           기준일 = e.std_day, 공시일 = e.crtn_day, 공시가격 = e.hsprc,
           rn   = ROW_NUMBER() OVER (PARTITION BY h.complex_id, h.호PK
                                     ORDER BY e.std_day DESC, e.crtn_day DESC),
           회차 = COUNT(*)     OVER (PARTITION BY h.complex_id, h.호PK, e.std_day)
    FROM gold.v_complex_ho h
    JOIN silver.bld_hsprc e
      ON e.mgm_bldrgst_pk = h.호PK
     AND e.is_current = 1 AND e.hsprc > 0
),
k AS (
    SELECT * FROM j WHERE rn = 1
),
r AS (
    SELECT k.*,
           단지cd   = CUME_DIST() OVER (PARTITION BY k.complex_id ORDER BY k.공시가격),
           단지최저 = MIN(k.공시가격) OVER (PARTITION BY k.complex_id),
           단지최고 = MAX(k.공시가격) OVER (PARTITION BY k.complex_id),
           단지종류 = DENSE_RANK() OVER (PARTITION BY k.complex_id ORDER BY k.공시가격)
                    + DENSE_RANK() OVER (PARTITION BY k.complex_id ORDER BY k.공시가격 DESC) - 1,
           라인cd   = CUME_DIST() OVER (PARTITION BY k.complex_id, k.동PK, k.라인
                                        ORDER BY k.공시가격),
           라인최저 = MIN(k.공시가격) OVER (PARTITION BY k.complex_id, k.동PK, k.라인),
           라인최고 = MAX(k.공시가격) OVER (PARTITION BY k.complex_id, k.동PK, k.라인),
           라인종류 = DENSE_RANK() OVER (PARTITION BY k.complex_id, k.동PK, k.라인
                                        ORDER BY k.공시가격)
                    + DENSE_RANK() OVER (PARTITION BY k.complex_id, k.동PK, k.라인
                                        ORDER BY k.공시가격 DESC) - 1
    FROM k
)
SELECT complex_id, 호PK, 동PK, 동, 층, 호, 라인,
       기준일, 공시일, 공시가격, 공시회차 = 회차,
       단지분위 = CASE WHEN 단지최저 < 단지최고
                       THEN CONVERT(INT, CEILING(5.0 * 단지cd)) END,
       라인분위 = CASE WHEN 라인최저 < 라인최고
                       THEN CONVERT(INT, CEILING(5.0 * 라인cd)) END,
       단지값종류 = 단지종류,
       라인값종류 = 라인종류,         -- 1 이면 그 라인은 층 차이가 없다
       단지최저, 단지최고, 라인최저, 라인최고
FROM r;
GO

/* 조인 키에 인덱스가 없으면 위 구조도 소용없다. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_hsprc_pk_current')
CREATE INDEX ix_bld_hsprc_pk_current ON silver.bld_hsprc (mgm_bldrgst_pk)
    INCLUDE (std_day, crtn_day, hsprc) WHERE is_current = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='ix_bld_expos_pk_current')
CREATE INDEX ix_bld_expos_pk_current ON silver.bld_expos (mgm_bldrgst_pk)
    WHERE is_current = 1;
GO

PRINT '29_hsprc_tie done.';
GO
