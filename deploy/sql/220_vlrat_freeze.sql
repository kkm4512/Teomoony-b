/* ============================================================
   220_vlrat_freeze : 용적률 분위를 표로 굳힌다 (2026-10-20)

   왜: `gold.v_bld_vlrat` 는 정확하지만 **7.5초**다. 창 함수(PERCENT_RANK)가
     바구니 **전체**를 보아야 해서, 단지 하나만 물어도 표 전체를 훑는다.
     단지 상세에 붙이면 모든 화면이 7.5초가 된다. 그래서 굳힌다.

   ★ 굳히면 '언제 기준인가' 라는 새 문제가 생긴다. 그래서 `굳힌때` 를 같이 적는다.
     건축물대장이 더 들어오면 **다시 돌려야 한다** — 그 사실을 표가 들고 있게.

   ★ SELECT INTO 로 만든다. 칸 타입을 손으로 적으면 뷰와 어긋날 수 있다 —
     뷰가 주는 타입을 그대로 받는 게 가장 안전하다.
   ★ READ UNCOMMITTED 로 읽는다. 지금 다른 적재가 돌고 있고, 이건 읽기 전용이다.
   ★ 굳힌 뒤 **뷰와 대조**한다. 굳히기의 유일한 위험은 조용히 달라지는 것이다.
   ============================================================ */
USE Teomoony;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO
IF OBJECT_ID('gold.bld_vlrat') IS NOT NULL DROP TABLE gold.bld_vlrat;
GO
SELECT mgm_bldrgst_pk, pnu, bld_nm, vl_rat, bc_rat, plat_area,
       용도지역, 단계, 상위, 바구니수, 상위percent, 넓은비교, 사유,
       굳힌때 = SYSDATETIME()
  INTO gold.bld_vlrat
  FROM gold.v_bld_vlrat;
GO
/* 조회는 늘 mgm_bldrgst_pk 로 들어온다(gold.complex_bld 와 잇는다) */
CREATE UNIQUE CLUSTERED INDEX cx_bld_vlrat ON gold.bld_vlrat (mgm_bldrgst_pk);
GO
CREATE INDEX ix_bld_vlrat_pnu ON gold.bld_vlrat (pnu)
    INCLUDE (상위percent, 용도지역, 바구니수, 넓은비교) WHERE pnu IS NOT NULL;
GO
PRINT '--- 굳힌 결과 ---';
SELECT 전체 = COUNT(*),
       분위있음 = SUM(CASE WHEN 상위percent IS NOT NULL THEN 1 ELSE 0 END),
       바구니종류 = COUNT(DISTINCT 용도지역)
  FROM gold.bld_vlrat;
GO
