/* ============================================================
   234_vlrat_rank2 : 용적률 분위 — **바구니를 둘로 나눈다** (2026-10-20)

   왜 고치나: 219 는 표제부(silver.bld_title)만 보았다. 그런데 **아파트 단지는
     용도지역이 총괄표제부에 붙는다.** 실측:
         대표 용도지역이 있는 대장 353,448건
           표제부에 있음 343,280 (97%)
           총괄에 있음    10,124 ( 3%)   <- 아파트 단지가 여기 있다
     그래서 창덕궁·도곡렉슬 같은 단지는 분위가 **통째로 비어** 있었다.

   ★ 사용자 결정(2026-10-20): **섞지 않고 바구니를 나눈다.**
     '단지 대지 전체의 용적률'(총괄)과 '건물 하나의 용적률'(표제부)은 다른 말이다.
     같은 줄에 세우려면 "이 둘이 같은 뜻이다" 라고 내가 단정해야 하는데,
     그건 확인한 사실이 아니라 **내 판단**이다. 그래서 따로 센다.
     바구니 = (용도지역, 종류). 종류는 '단지' 또는 '건물'.

   ★ 작은 바구니 문제 — '5개 중 상위 20%' 는 뜻이 얕다. **거르지 않는다.**
     대신 `바구니수` 를 늘 같이 내보내서 **사람이 판단하게** 한다.
     몇 개부터 의미 있는지는 내가 정할 일이 아니다.

   ★ 219 의 원칙은 그대로다: 원본 안 고침 / 모르면 분위 안 냄 + 사유 적음 /
     바구니 크기 같이 냄 / 같은 것의 다른 표기만 **이름**으로 합침 /
     `vl_rat` 만 쓰고 tot_area 로 계산하지 않음(지하·주차장이 섞인다).
   ============================================================ */
USE Teomoony;
GO
IF OBJECT_ID('gold.v_bld_vlrat') IS NOT NULL DROP VIEW gold.v_bld_vlrat;
GO
CREATE VIEW gold.v_bld_vlrat
AS
WITH 대표 AS (
    SELECT j.mgm_bldrgst_pk,
           jijigu_nm = MIN(j.jijigu_nm),
           대표개수  = COUNT(*)
      FROM silver.bld_jijigu j
     WHERE j.is_current = 1 AND j.jijigu_gb_cd = '1' AND j.repr_yn = '1'
       AND j.jijigu_nm IS NOT NULL
     GROUP BY j.mgm_bldrgst_pk
),
원본 AS (
    SELECT 종류 = N'건물', t.mgm_bldrgst_pk, t.pnu, t.bld_nm,
           t.vl_rat, t.bc_rat, t.plat_area, t.vl_rat_estm_tot_area
      FROM silver.bld_title t WHERE t.is_current = 1
    UNION ALL
    SELECT 종류 = N'단지', r.mgm_bldrgst_pk, r.pnu, r.bld_nm,
           r.vl_rat, r.bc_rat, r.plat_area, r.vl_rat_estm_tot_area
      FROM silver.bld_recap_title r WHERE r.is_current = 1
),
재료 AS (
    SELECT o.*, d.jijigu_nm, d.대표개수, l.단계, l.상위, l.비고,
           잴까 = CASE WHEN o.vl_rat > 0 AND d.대표개수 = 1
                        AND l.단계 IN (2, 3) THEN 1 ELSE 0 END
      FROM 원본 o
      LEFT JOIN 대표 d ON d.mgm_bldrgst_pk = o.mgm_bldrgst_pk
      LEFT JOIN meta.jijigu_level l ON l.jijigu_nm = d.jijigu_nm
),
분위 AS (
    SELECT r.*,
           순위비 = CASE WHEN r.잴까 = 1 THEN
                          PERCENT_RANK() OVER (
                            PARTITION BY CASE WHEN r.잴까 = 1 THEN r.jijigu_nm END,
                                         CASE WHEN r.잴까 = 1 THEN r.종류 END
                            ORDER BY r.vl_rat)
                    END,
           바구니수 = CASE WHEN r.잴까 = 1 THEN
                          COUNT(*) OVER (
                            PARTITION BY CASE WHEN r.잴까 = 1 THEN r.jijigu_nm END,
                                         CASE WHEN r.잴까 = 1 THEN r.종류 END)
                      END
      FROM 재료 r
)
SELECT 종류, mgm_bldrgst_pk, pnu, bld_nm,
       vl_rat, bc_rat, plat_area, vl_rat_estm_tot_area,
       용도지역 = jijigu_nm, 단계, 상위, 바구니수,
       상위percent = CASE WHEN 순위비 IS NOT NULL
                          THEN CAST(ROUND((1 - 순위비) * 100, 1) AS DECIMAL(5,1)) END,
       넓은비교 = CASE WHEN 단계 = 2 THEN 1 ELSE 0 END,
       사유 = CASE
           WHEN jijigu_nm IS NULL          THEN N'대장에 용도지역이 없습니다'
           WHEN 단계 IS NULL               THEN N'용도지역 이름을 분류하지 못했습니다'
           WHEN 단계 = 0                   THEN N'용도지역이 아닙니다(' + ISNULL(비고, N'별도 규제구역') + N')'
           WHEN 단계 = 1                   THEN N'너무 넓은 구분이라 분위를 내지 않습니다(' + jijigu_nm + N')'
           WHEN 대표개수 > 1               THEN N'대표 용도지역이 ' + CAST(대표개수 AS NVARCHAR(4)) + N'개라 하나로 정하지 않았습니다'
           WHEN vl_rat IS NULL OR vl_rat <= 0 THEN N'대장에 용적률이 없습니다'
       END,
       비고
  FROM 분위;
GO
PRINT '--- 종류별로 몇 건이 분위를 받았나 ---';
SELECT 종류, 전체 = COUNT(*),
       분위있음 = SUM(CASE WHEN 상위percent IS NOT NULL THEN 1 ELSE 0 END),
       바구니종류 = COUNT(DISTINCT CASE WHEN 상위percent IS NOT NULL THEN 용도지역 END)
  FROM gold.v_bld_vlrat GROUP BY 종류;
GO
