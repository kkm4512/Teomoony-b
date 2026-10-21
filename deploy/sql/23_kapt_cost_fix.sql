SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE Teomoony;
GO
/* ============================================================
   23_kapt_cost_fix : 사람값 정의 교정 + 분양임대 구분을 뷰에 싣는다
                      (성북구 138단지 실측 후, 2026-10-16)

   ★ (1) 사람값에 위탁관리수수료를 넣어야 한다

     장위동 11단지에서 "공용관리비의 84% 가 사람값(인건비+청소비+경비비)" 이라고
     결론 냈다. 성북구 138단지로 넓히니 **예외가 하나 튀어나왔다.**

       길음서희스타힐스  사람값비중 27.3%   (나머지는 64~93%)

     항목을 열어 보니 **위탁관리수수료가 전체의 54%** 이고 **급여(pay) 가 0** 이었다.
     관리직원 인건비를 위탁수수료로 일괄 지급하는 구조다.

       사람값 + 위탁관리수수료  ->  27.3% → 81.6%   (다른 단지와 같은 자리)

     즉 **사람값비중이 낮은 것은 사람을 덜 쓰는 게 아니라 회계 처리가 다른 것**이다.
     이걸 모르고 비교하면 "관리를 적게 하는 단지" 로 잘못 읽는다.

     기존 `사람값` 컬럼은 **지우지 않는다.** 둘을 같이 내려보내면 둘의 차이가
     곧 "위탁 비중" 이고, 그게 단지의 관리 방식을 드러낸다.

   ★ (2) 분양/임대/혼합이 규모보다 강한 설명변수다

     성북구 138단지 실측 (code_sale_nm 기준, 2024.12):

       분양  94단지  58,646세대   세대당 113,098원   장충잔액 0 : 2단지
       임대  25단지   6,719세대   세대당  78,450원   장충잔액 0 : 25단지 (100%)
       혼합  19단지  15,796세대   세대당 118,550원   장충잔액 0 : 1단지

     - **임대는 25/25 전부 장기수선충당금 잔액이 0 이다.** 임대사업자가 부담하니
       입주자 적립금이 없다. 추정이 아니라 전수다
     - 분양 94개 중 잔액 0 인 둘은 **2024년 신축**이다
       -> `장충 잔액 = 0` 은 **임대이거나 신축**, 두 경우뿐이다
     - **혼합이 가장 비싸다.** 분양보다 세대당 5,452원 높고 주차도 가장 많다

     세대수 상관은 이걸 걷어내고 봐야 한다.

       세대수 vs 세대당관리비   전체 138단지  Spearman -0.25
                               분양 118단지            -0.47

     절반이 "임대는 주차도 적고 관리비도 싸다" 는 교란이었다.
     주차/세대도 같다: 전체 +0.43 -> 분양만 +0.26.

     > 장위동 11단지로는 이게 안 보였다. 그 11개 중 임대가 1개뿐이어서다.
       n=11 로 "규모 역상관이 뚜렷하다" 고 두 번 말했는데, 뚜렷한 건 규모가
       아니라 분양임대였다.

     그래서 **뷰가 code_sale_nm 을 직접 들고 있어야 한다.** 비교할 때마다
     kapt_complex 를 다시 조인하게 두면 빼먹는다.
   ============================================================ */

CREATE OR ALTER VIEW gold.v_kapt_cost_cmn AS
WITH a AS (
    SELECT c.kapt_code, c.ym,
           합계     = SUM(c.amount),
           인건비   = SUM(CASE WHEN c.op = 'getHsmpLaborCostInfoV3'            THEN c.amount END),
           급여     = SUM(CASE WHEN c.fld = 'pay'                              THEN c.amount END),
           청소비   = SUM(CASE WHEN c.op = 'getHsmpCleaningCostInfoV3'         THEN c.amount END),
           경비비   = SUM(CASE WHEN c.op = 'getHsmpGuardCostInfoV3'            THEN c.amount END),
           위탁수수료 = SUM(CASE WHEN c.op = 'getHsmpConsignManageFeeInfoV3'   THEN c.amount END),
           수선비   = SUM(CASE WHEN c.op = 'getHsmpRepairsCostInfoV3'          THEN c.amount END),
           시설유지 = SUM(CASE WHEN c.op = 'getHsmpFacilityMntncCostInfoV3'    THEN c.amount END),
           안전점검 = SUM(CASE WHEN c.op = 'getHsmpSafetyCheckUpCostInfoV3'    THEN c.amount END),
           재해예방 = SUM(CASE WHEN c.op = 'getHsmpDisasterPreventionCostInfoV3' THEN c.amount END),
           승강기   = SUM(CASE WHEN c.op = 'getHsmpElevatorMntncCostInfoV3'    THEN c.amount END),
           제세공과금 = SUM(CASE WHEN c.op = 'getHsmpTaxdueInfoV3'             THEN c.amount END),
           항목수   = COUNT(*)
    FROM silver.kapt_cost c
    WHERE c.svc = 'CMN'
    GROUP BY c.kapt_code, c.ym
)
SELECT a.kapt_code, a.ym,
       단지명 = k.kapt_name,
       분양임대 = k.code_sale_nm,          -- ★ 최강 설명변수. 뷰가 직접 들고 있는다
       관리방식 = k.code_mgr_nm,           -- 자치 / 위탁. 위탁 비중과 같이 본다
       세대   = NULLIF(k.hhld_cnt, 0),
       호수   = NULLIF(k.ho_cnt, 0),
       사용승인 = k.kapt_usedate,
       연식   = CASE WHEN ISNUMERIC(LEFT(k.kapt_usedate,4)) = 1
                     THEN YEAR(GETDATE()) - CAST(LEFT(k.kapt_usedate,4) AS INT) END,
       a.합계, a.인건비, a.급여, a.청소비, a.경비비, a.위탁수수료,
       /* 인건비+청소비+경비비. 위탁관리 단지에서는 과소평가된다 */
       사람값 = ISNULL(a.인건비,0) + ISNULL(a.청소비,0) + ISNULL(a.경비비,0),
       /* ★ 위탁관리수수료까지. 단지 간 비교에는 이쪽을 쓴다 */
       운영인력비 = ISNULL(a.인건비,0) + ISNULL(a.청소비,0) + ISNULL(a.경비비,0)
                  + ISNULL(a.위탁수수료,0),
       수선유지 = ISNULL(a.수선비,0) + ISNULL(a.시설유지,0)
                + ISNULL(a.안전점검,0) + ISNULL(a.재해예방,0),
       a.승강기, a.제세공과금,
       세대당 = CASE WHEN NULLIF(k.hhld_cnt,0) IS NULL THEN NULL
                     ELSE CAST(a.합계 / k.hhld_cnt AS DECIMAL(18,0)) END,
       사람값비중 = CASE WHEN NULLIF(a.합계,0) IS NULL THEN NULL
                     ELSE CAST(100.0 * (ISNULL(a.인건비,0)+ISNULL(a.청소비,0)+ISNULL(a.경비비,0))
                               / a.합계 AS DECIMAL(5,1)) END,
       운영인력비중 = CASE WHEN NULLIF(a.합계,0) IS NULL THEN NULL
                     ELSE CAST(100.0 * (ISNULL(a.인건비,0)+ISNULL(a.청소비,0)
                                        +ISNULL(a.경비비,0)+ISNULL(a.위탁수수료,0))
                               / a.합계 AS DECIMAL(5,1)) END,
       위탁비중 = CASE WHEN NULLIF(a.합계,0) IS NULL THEN NULL
                     ELSE CAST(100.0 * ISNULL(a.위탁수수료,0) / a.합계 AS DECIMAL(5,1)) END,
       /* 급여가 0 이면서 위탁수수료가 큰 단지 — 사람값비중으로 비교하면 틀린다 */
       급여없음 = CASE WHEN ISNULL(a.급여,0) = 0 AND ISNULL(a.위탁수수료,0) > 0
                       THEN 1 ELSE 0 END,
       a.항목수
FROM a
JOIN silver.kapt_complex k ON k.kapt_code = a.kapt_code AND k.is_current = 1;
GO

/* ------------------------------------------------------------
   gold.v_kapt_cost_latest — 분양임대 / 연식 / 운영인력비중 추가

   ★ 장충_잔액_상태 — 0 을 "모아둔 돈이 없다" 로 읽으면 안 된다.
     임대(25/25 전수)와 신축은 0 이 정상이다.
   ------------------------------------------------------------ */
CREATE OR ALTER VIEW gold.v_kapt_cost_latest AS
WITH m AS (
    SELECT kapt_code, ym = MAX(ym) FROM silver.kapt_cost GROUP BY kapt_code
)
SELECT m.kapt_code, m.ym,
       단지명 = k.kapt_name,
       법정동 = l.emd_nm,
       분양임대 = k.code_sale_nm,
       관리방식 = k.code_mgr_nm,
       세대 = NULLIF(k.hhld_cnt, 0),
       사용승인 = k.kapt_usedate,
       c.연식,
       공용관리비 = c.합계,
       세대당 = c.세대당,
       c.사람값비중, c.운영인력비중, c.위탁비중, c.급여없음,
       장충_월부과 = r.월부과,
       장충_잔액 = r.잔액,
       장충_잔액_세대당 = r.잔액_세대당,
       /* 0 의 뜻을 뷰가 말해준다 */
       장충_잔액_상태 = CASE
           WHEN r.잔액 > 0 THEN N'적립'
           WHEN k.code_sale_nm = N'임대' THEN N'임대 — 사업자 부담'
           WHEN LEFT(k.kapt_usedate,4) >= CAST(YEAR(GETDATE()) - 3 AS CHAR(4)) THEN N'신축 — 적립 전'
           WHEN r.잔액 IS NULL THEN N'미적재'
           ELSE N'0 — 확인 필요' END,
       주차 = ISNULL(k.parking_ground,0) + ISNULL(k.parking_under,0),
       주차_세대당 = CASE WHEN NULLIF(k.hhld_cnt,0) IS NULL THEN NULL
                     ELSE CAST(1.0 * (ISNULL(k.parking_ground,0)+ISNULL(k.parking_under,0))
                               / k.hhld_cnt AS DECIMAL(6,2)) END,
       전기차 = ISNULL(k.el_charger_ground,0) + ISNULL(k.el_charger_under,0),
       전기차_비율 = CASE WHEN NULLIF(k.hhld_cnt,0) IS NULL THEN NULL
                     ELSE CAST(100.0 * (ISNULL(k.el_charger_ground,0)+ISNULL(k.el_charger_under,0))
                               / k.hhld_cnt AS DECIMAL(5,1)) END
FROM m
JOIN silver.kapt_complex k ON k.kapt_code = m.kapt_code AND k.is_current = 1
LEFT JOIN meta.lawd_code l ON l.lawd_cd = k.bjd_code
LEFT JOIN gold.v_kapt_cost_cmn c ON c.kapt_code = m.kapt_code AND c.ym = m.ym
LEFT JOIN gold.v_kapt_cost_rep r ON r.kapt_code = m.kapt_code AND r.ym = m.ym;
GO
