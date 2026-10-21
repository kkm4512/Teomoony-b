SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   28_hsprc_fix : 공시 회차를 키에 넣는다 — 2026-10-17

   27_hsprc 의 키는 (호PK, 기준일) 이었다. 그런데 **같은 호·같은 기준일에
   두 건이 온다.** 금액은 같고 `crtn_day`(생성일자)만 다르다:

       10247  583,000,000  기준일 20260101  생성 2026-05-17
       10248  583,000,000  기준일 20260101  생성 2026-06-27

   공시가격은 **결정공시 -> 이의신청 -> 조정공시** 로 두 번 올라온다.
   금액이 안 바뀌면 생성일만 다른 두 건이 남는다. 돈암동 636번지에서
   **1,074건 전부 최신 기준일(20260101)** 에 몰려 있었다.

   키가 (호PK, 기준일) 이면 둘이 서로를 밀어내므로 **적재를 돌릴 때마다
   is_current 가 뒤집히고 이력이 끝없이 쌓인다.** 적재는 OK 로 끝나는데
   데이터가 조용히 흔들리는 종류다.

   ★ 선택지가 둘이었다.
     · crtn_day 를 row_hash 에서 뺀다  -> 간단하지만 **언제 공시된 것인지를 잃는다**
     · 키에 넣는다                      -> 채택. 두 회차를 다 남기고 뷰가 최신을 고른다

     이 프로젝트는 원본을 안 버리는 쪽을 계속 택해왔다(bronze, seg_cnt,
     건폐율 59,315% 를 NULL 로 안 바꾼 것). 공시 회차 자체가 정보다.
   ============================================================ */
USE Teomoony;
GO

/* 1) 유일 인덱스를 회차까지 포함하도록 */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name='uq_bld_hsprc_current')
    DROP INDEX uq_bld_hsprc_current ON silver.bld_hsprc;
GO
CREATE UNIQUE INDEX uq_bld_hsprc_current ON silver.bld_hsprc
    (mgm_bldrgst_pk, std_day, crtn_day) WHERE is_current = 1;
GO

/* 2) 예전 키로 만료당한 행을 되살린다.
      새 키로는 서로 다른 행이므로 둘 다 현재행이어야 한다.
      **같은 새 키에 현재행이 이미 있는 것만 빼고** 되살린다. */
UPDATE h
   SET is_current = 1, valid_to = '9999-12-31'
  FROM silver.bld_hsprc h
 WHERE h.is_current = 0
   AND NOT EXISTS (
        SELECT 1 FROM silver.bld_hsprc c
         WHERE c.is_current = 1
           AND c.mgm_bldrgst_pk = h.mgm_bldrgst_pk
           AND c.std_day = h.std_day
           AND c.crtn_day = h.crtn_day);
GO
PRINT '되살린 행:';
SELECT 전체=COUNT(*), 현재행=SUM(CASE WHEN is_current=1 THEN 1 ELSE 0 END),
       만료행=SUM(CASE WHEN is_current=0 THEN 1 ELSE 0 END)
FROM silver.bld_hsprc;
GO

/* 3) 최신 선택에 회차를 반영한다.
      같은 기준일에 회차가 여럿이면 **나중에 공시된 것**이 현재 가격이다. */
IF OBJECT_ID('gold.v_complex_ho_price') IS NOT NULL DROP VIEW gold.v_complex_ho_price;
GO
CREATE VIEW gold.v_complex_ho_price
AS
WITH l AS (
    SELECT mgm_bldrgst_pk, std_day, crtn_day, hsprc,
           rn = ROW_NUMBER() OVER (PARTITION BY mgm_bldrgst_pk
                                   ORDER BY std_day DESC, crtn_day DESC),
           회차 = COUNT(*) OVER (PARTITION BY mgm_bldrgst_pk, std_day)
    FROM silver.bld_hsprc
    WHERE is_current = 1 AND hsprc > 0
),
j AS (
    SELECT h.complex_id, h.호PK, h.동PK, h.동, h.층, h.호, h.라인,
           기준일 = l.std_day, 공시일 = l.crtn_day, 공시가격 = l.hsprc,
           공시회차 = l.회차            -- 2 이상이면 그 기준일에 재공시가 있었다
    FROM gold.v_complex_ho h
    JOIN l ON l.mgm_bldrgst_pk = h.호PK AND l.rn = 1
)
SELECT j.*,
       단지분위 = NTILE(5) OVER (PARTITION BY j.complex_id       ORDER BY j.공시가격),
       라인분위 = NTILE(5) OVER (PARTITION BY j.complex_id, j.동PK, j.라인 ORDER BY j.공시가격)
FROM j;
GO

PRINT '28_hsprc_fix done.';
GO
