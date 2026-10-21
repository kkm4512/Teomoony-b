/* ============================================================
   219_vlrat_rank : 용적률 분위 (2026-10-20)

   사용자 원칙: "원본 데이터를 훼손하지않고 제공 / 내 개인적인 생각을 빼는게 핵심"

   ★ 그래서 이 뷰가 지키는 것
     1) 원본(silver.bld_jijigu, bld_title)은 **한 글자도 안 고친다.** 읽기만 한다.
     2) **모르면 분위를 내지 않는다.** NULL 로 두고 `사유` 에 왜인지 적는다.
        숫자를 만들 수 있다고 만들지 않는다 — '도시지역 안에서 상위 30%' 는
        비교 대상이 서울 거의 전부라 **뜻이 없는 숫자**다.
     3) 바구니의 **크기(n)와 단계**를 같이 내보낸다. 몇 개 중 몇 등인지 모르면
        '상위 30%' 는 읽을 수 없다.
     4) 같은 것의 다른 표기(`1022`/`UQA122`)만 합친다 — **이름**으로 묶으므로
        추론이 한 글자도 안 들어간다.

   ★ `vl_rat` 를 쓴다. `tot_area / plat_area` 로 **계산하지 않는다**:
     - 전체 연면적에는 지하·주차장이 들어가 용적률과 전혀 다른 수가 된다
       (올림픽파크포레온 273.9% vs 467.6%).
     - 원본에 불가능한 값이 있다(선인상가 tot_area 50,222,615㎡ = 대지의 3,000배).
     - 반면 `vl_rat` 는 `vl_rat_estm_tot_area/plat_area` 와 소수점까지 맞았다.

   ★ 대표 용도지역이 **둘 이상인 건물 278건**(0.08%)은 하나를 고르지 않는다.
     고르는 순간 내 판단이 들어간다. 분위 없이 사유만 적는다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('gold.v_bld_vlrat') IS NOT NULL DROP VIEW gold.v_bld_vlrat;
GO
CREATE VIEW gold.v_bld_vlrat
AS
WITH 대표 AS (
    /* 건물 하나의 **대표 용도지역**. 둘 이상이면 개수로 드러낸다. */
    SELECT j.mgm_bldrgst_pk,
           jijigu_nm = MIN(j.jijigu_nm),
           대표개수  = COUNT(*)
      FROM silver.bld_jijigu j
     WHERE j.is_current = 1 AND j.jijigu_gb_cd = '1' AND j.repr_yn = '1'
       AND j.jijigu_nm IS NOT NULL
     GROUP BY j.mgm_bldrgst_pk
),
재료 AS (
    SELECT t.mgm_bldrgst_pk, t.pnu, t.bld_nm,
           t.vl_rat, t.bc_rat, t.plat_area, t.vl_rat_estm_tot_area,
           d.jijigu_nm, d.대표개수, l.단계, l.상위, l.비고,
           /* 분위를 낼 수 있는 조건을 **한 군데**서 정한다 */
           잴까 = CASE WHEN t.vl_rat > 0
                        AND d.대표개수 = 1
                        AND l.단계 IN (2, 3) THEN 1 ELSE 0 END
      FROM silver.bld_title t
      LEFT JOIN 대표 d ON d.mgm_bldrgst_pk = t.mgm_bldrgst_pk
      LEFT JOIN meta.jijigu_level l ON l.jijigu_nm = d.jijigu_nm
     WHERE t.is_current = 1
),
분위 AS (
    SELECT r.*,
           /* ★ 바구니 = 용도지역 **이름**. 코드 두 체계가 자동으로 합쳐진다. */
           순위비 = CASE WHEN r.잴까 = 1 THEN
                          PERCENT_RANK() OVER (PARTITION BY CASE WHEN r.잴까 = 1
                                                                THEN r.jijigu_nm END
                                               ORDER BY r.vl_rat)
                    END,
           바구니수 = CASE WHEN r.잴까 = 1 THEN
                          COUNT(*) OVER (PARTITION BY CASE WHEN r.잴까 = 1
                                                          THEN r.jijigu_nm END)
                      END
      FROM 재료 r
)
SELECT mgm_bldrgst_pk, pnu, bld_nm,
       vl_rat, bc_rat, plat_area, vl_rat_estm_tot_area,
       용도지역 = jijigu_nm, 단계, 상위, 바구니수,
       /* 화면이 바로 쓰는 값: 높을수록 많이 지은 것. 0~100. */
       상위percent = CASE WHEN 순위비 IS NOT NULL
                          THEN CAST(ROUND((1 - 순위비) * 100, 1) AS DECIMAL(5,1)) END,
       넓은비교 = CASE WHEN 단계 = 2 THEN 1 ELSE 0 END,   -- 종이 섞인 바구니
       /* ★ 분위가 없으면 **왜 없는지** 반드시 적는다. 빈칸만 주면 버그처럼 보인다. */
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

PRINT '--- 분위를 낸 것 / 못 낸 것 ---';
SELECT 분위있음 = SUM(CASE WHEN 상위percent IS NOT NULL THEN 1 ELSE 0 END),
       분위없음 = SUM(CASE WHEN 상위percent IS NULL THEN 1 ELSE 0 END),
       전체 = COUNT(*)
  FROM gold.v_bld_vlrat;
GO
PRINT '--- 분위를 못 낸 사유 ---';
SELECT 사유, 건수 = COUNT(*) FROM gold.v_bld_vlrat
 WHERE 상위percent IS NULL GROUP BY 사유 ORDER BY COUNT(*) DESC;
GO
PRINT '--- 바구니별 (분위를 낸 것) ---';
SELECT 용도지역, 단계, 넓은비교, 건수 = COUNT(*),
       최소 = MIN(vl_rat), 중앙 = AVG(vl_rat), 최대 = MAX(vl_rat)
  FROM gold.v_bld_vlrat WHERE 상위percent IS NOT NULL
 GROUP BY 용도지역, 단계, 넓은비교 ORDER BY COUNT(*) DESC;
GO
