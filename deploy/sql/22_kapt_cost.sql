SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE Teomoony;
GO
/* ============================================================
   22_kapt_cost : 관리비 3개 서비스 적재 + 세대수/주차 필드 교정

   ★ 먼저, 고쳐야 할 것 세 가지 (2026-10-16 발견)

   (1) parking_cnt 에 세대수가 들어 있었다
       load_kapt.py 가 `parking_cnt = kaptdaCnt` 로 넣고 있었다.
       kaptdaCnt 는 **세대수**다. 실제 주차는 kaptdPcnt(지상)+kaptdPcntu(지하) 다.
       래미안퍼스트하이: kaptdaCnt 1,562  /  주차 0 + 1,911 = 1,911
       화면의 "주차" 가 세대수를 보여주고 있었다.

   (2) ho_cnt(호수) 를 뷰 7곳에서 "세대" 로 쓰고 있었다
       hoCnt 는 **호수**, kaptdaCnt 가 **세대수**다. 보통 같지만 다른 단지가 있다.
       래미안퍼스트하이: 호수 1,568 / 세대수 1,562
       그래서 v_complex_kapt 의 "세대차 -6" 은 실제 불일치가 아니라
       호수↔세대수 비교였다. 대장 세대수 1,562 와 kaptdaCnt 1,562 는 정확히 맞는다.
       성북구 100개 중 호수≠세대수 는 8개. 그중 2개는 신축 미입주(세대수 0).
       -> hhld_cnt 를 새로 만들고, 뷰는 hhld_cnt 를 쓴다. 호수는 호수로 남긴다.

   (3) 관리비는 **세대당**으로 비교한다. 분모가 (2) 다.
       분모를 호수로 잡으면 전 단지의 세대당 금액이 조용히 틀린다.
       이 파일이 관리비를 들이는 파일이므로 여기서 같이 고친다.

   ★ 왜 long 테이블인가 — 오늘 하루의 교훈

     "같은 이름의 항목에 단지마다 다른 게 들어있다" 가 반복됐다.
       - 전기료는 electC(공용부) 와 electP(세대부) 두 개다. 더하면 다른 걸 섞는다
       - 장위참누리는 electP = 0 (세대 전기를 한전이 직공급)
       - 난방은 장위동 11/11 이 0 (전부 개별난방)
       - 제세공과금 안에 electCost 가 또 있다

     그래서 **원본 필드명을 그대로 보존한다.** 넓은 테이블로 접으면
     어느 숫자가 어느 필드에서 왔는지 잃고, 그 상태로 합계를 내면 조용히 틀린다.
     필드가 추가돼도 ALTER 가 필요 없다는 건 부수적인 이득이다.

   ★ 서비스 경계를 넘어 더하지 않는다
     공용관리비 합계와 개별사용료 합계를 또 더하면 안 된다(전기가 양쪽에 있다).
     그래서 뷰도 **서비스별로만** 합계를 낸다. 전체 총합 컬럼을 만들지 않는다.
   ============================================================ */

/* ------------------------------------------------------------
   (1)(2) silver.kapt_complex — 세대수 컬럼 추가
   ------------------------------------------------------------ */
IF COL_LENGTH('silver.kapt_complex', 'hhld_cnt') IS NULL
    ALTER TABLE silver.kapt_complex
        ADD hhld_cnt INT NULL;   -- kaptdaCnt  세대수. ho_cnt(hoCnt)는 호수다
GO

/* ------------------------------------------------------------
   관리비 원본 — 단지 × 월 × 오퍼레이션 × 필드
   ------------------------------------------------------------ */
IF OBJECT_ID('silver.kapt_cost', 'U') IS NULL
BEGIN
    CREATE TABLE silver.kapt_cost (
        kapt_code   VARCHAR(20)   NOT NULL,
        ym          CHAR(6)       NOT NULL,   -- searchDate YYYYMM
        svc         VARCHAR(3)    NOT NULL,   -- CMN 공용관리비 / IND 개별사용료 / REP 장기수선충당금
        op          VARCHAR(60)   NOT NULL,   -- getHsmp...V3
        fld         VARCHAR(40)   NOT NULL,   -- 원본 필드명 그대로
        amount      DECIMAL(20,4) NULL,       -- 원. sPer(요율)만 % 다
        /* 재공시가 있으면 금액이 바뀐다. 덮되, 바뀐 횟수를 남긴다 */
        chg_cnt     INT           NOT NULL CONSTRAINT DF_kapt_cost_chg DEFAULT 0,
        first_at    DATETIME2(0)  NOT NULL CONSTRAINT DF_kapt_cost_first DEFAULT SYSDATETIME(),
        loaded_at   DATETIME2(0)  NOT NULL CONSTRAINT DF_kapt_cost_load  DEFAULT SYSDATETIME(),
        CONSTRAINT PK_kapt_cost PRIMARY KEY (kapt_code, ym, op, fld)
    );
    CREATE INDEX IX_kapt_cost_ym  ON silver.kapt_cost (ym, svc) INCLUDE (kapt_code, amount);
    CREATE INDEX IX_kapt_cost_fld ON silver.kapt_cost (fld, ym) INCLUDE (kapt_code, amount);
END
GO

/* ------------------------------------------------------------
   필드 사전 — 한글 이름과 "비교 가능한가" 를 데이터로 남긴다

   비교가능 = 1 : 단지 간 세대당 비교에 써도 되는 항목
   비교가능 = 0 : 계약 형태가 단지마다 달라 비교하면 틀리는 항목
                  (한 단지 안의 추이로만 쓴다)

   판단을 코드가 아니라 데이터에 둔다. 화면과 집계가 같은 근거를 본다.
   ------------------------------------------------------------ */
IF OBJECT_ID('meta.kapt_cost_item', 'U') IS NULL
    CREATE TABLE meta.kapt_cost_item (
        op        VARCHAR(60)   NOT NULL,
        fld       VARCHAR(40)   NOT NULL,
        svc       VARCHAR(3)    NOT NULL,
        item_nm   NVARCHAR(60)  NOT NULL,   -- 오퍼레이션의 항목명 (인건비 ...)
        sub_nm    NVARCHAR(60)  NULL,       -- 필드 수준 (급여 / 상여금 ...)
        cmprbl    BIT           NOT NULL,   -- 단지 간 비교 가능?
        note      NVARCHAR(300) NULL,
        CONSTRAINT PK_kapt_cost_item PRIMARY KEY (op, fld)
    );
GO

MERGE meta.kapt_cost_item AS t
USING (VALUES
  /* --- 공용관리비 17종. 전부 단지 운영비라 세대당 비교가 성립한다 --- */
  ('getHsmpLaborCostInfoV3','pay','CMN',N'인건비',N'급여',1,NULL),
  ('getHsmpLaborCostInfoV3','sundryCost','CMN',N'인건비',N'제수당',1,NULL),
  ('getHsmpLaborCostInfoV3','bonus','CMN',N'인건비',N'상여금',1,NULL),
  ('getHsmpLaborCostInfoV3','pension','CMN',N'인건비',N'퇴직금',1,NULL),
  ('getHsmpLaborCostInfoV3','accidentPremium','CMN',N'인건비',N'산재보험료',1,NULL),
  ('getHsmpLaborCostInfoV3','employPremium','CMN',N'인건비',N'고용보험료',1,NULL),
  ('getHsmpLaborCostInfoV3','nationalPension','CMN',N'인건비',N'국민연금',1,NULL),
  ('getHsmpLaborCostInfoV3','healthPremium','CMN',N'인건비',N'건강보험료',1,NULL),
  ('getHsmpLaborCostInfoV3','welfareBenefit','CMN',N'인건비',N'식대 등 복리후생비',1,NULL),
  ('getHsmpTaxdueInfoV3','electCost','CMN',N'제세공과금',N'전기료',1,
     N'공용관리비 쪽 전기료다. 개별사용료 electC/electP 와 중복 계상하지 말 것'),
  ('getHsmpTaxdueInfoV3','telCost','CMN',N'제세공과금',N'전화료',1,NULL),
  ('getHsmpTaxdueInfoV3','postageCost','CMN',N'제세공과금',N'우편료',1,NULL),
  ('getHsmpTaxdueInfoV3','taxrestCost','CMN',N'제세공과금',N'제세공과금',1,NULL),
  ('getHsmpVhcleMntncCostInfoV3','fuelCost','CMN',N'차량유지비',N'연료비',1,NULL),
  ('getHsmpVhcleMntncCostInfoV3','refairCost','CMN',N'차량유지비',N'수리비',1,NULL),
  ('getHsmpVhcleMntncCostInfoV3','carInsurance','CMN',N'차량유지비',N'보험료',1,NULL),
  ('getHsmpVhcleMntncCostInfoV3','carEtc','CMN',N'차량유지비',N'기타',1,NULL),
  ('getHsmpEtcCostInfoV3','careItemCost','CMN',N'기타부대비용',N'관리용품구입비',1,NULL),
  ('getHsmpEtcCostInfoV3','accountingCost','CMN',N'기타부대비용',N'회계감사비',1,NULL),
  ('getHsmpEtcCostInfoV3','hiddenCost','CMN',N'기타부대비용',N'잡비',1,NULL),
  ('getHsmpOfcrkCostInfoV3','officeSupply','CMN',N'제사무비',N'사무용품비',1,NULL),
  ('getHsmpOfcrkCostInfoV3','bookSupply','CMN',N'제사무비',N'도서인쇄비',1,NULL),
  ('getHsmpOfcrkCostInfoV3','transportCost','CMN',N'제사무비',N'여비교통비',1,NULL),
  ('getHsmpClothingCostInfoV3','clothesCost','CMN',N'피복비',NULL,1,NULL),
  ('getHsmpEduTraingCostInfoV3','eduCost','CMN',N'교육훈련비',NULL,1,NULL),
  ('getHsmpCleaningCostInfoV3','cleanCost','CMN',N'청소비',NULL,1,NULL),
  ('getHsmpGuardCostInfoV3','guardCost','CMN',N'경비비',NULL,1,NULL),
  ('getHsmpDisinfectionCostInfoV3','disinfCost','CMN',N'소독비',NULL,1,NULL),
  ('getHsmpElevatorMntncCostInfoV3','elevCost','CMN',N'승강기유지비',NULL,1,NULL),
  ('getHsmpHomeNetworkMntncCostInfoV3','hnetwCost','CMN',N'지능형홈네트워크설비유지비',NULL,1,NULL),
  ('getHsmpRepairsCostInfoV3','lrefCost1','CMN',N'수선비',NULL,1,NULL),
  ('getHsmpFacilityMntncCostInfoV3','lrefCost2','CMN',N'시설유지비',NULL,1,NULL),
  ('getHsmpSafetyCheckUpCostInfoV3','lrefCost3','CMN',N'안전점검비',NULL,1,NULL),
  ('getHsmpDisasterPreventionCostInfoV3','lrefCost4','CMN',N'재해예방비',NULL,1,NULL),
  ('getHsmpConsignManageFeeInfoV3','manageCost','CMN',N'위탁관리수수료',NULL,1,NULL),
  /* --- 개별사용료 10종. 사용량 통과분이라 단지 간 비교는 하지 않는다 --- */
  ('getHsmpHeatCostInfoV3','heatC','IND',N'난방비',N'공용부',0,N'개별난방 단지는 0 으로 온다'),
  ('getHsmpHeatCostInfoV3','heatP','IND',N'난방비',N'세대부',0,N'개별난방 단지는 0 으로 온다'),
  ('getHsmpHotWaterCostInfoV3','waterHotC','IND',N'급탕비',N'공용부',0,NULL),
  ('getHsmpHotWaterCostInfoV3','waterHotP','IND',N'급탕비',N'세대부',0,NULL),
  ('getHsmpGasRentalFeeInfoV3','gasC','IND',N'가스사용료',N'공용부',0,NULL),
  ('getHsmpGasRentalFeeInfoV3','gasP','IND',N'가스사용료',N'세대부',0,NULL),
  ('getHsmpElectricityCostInfoV3','electC','IND',N'전기료',N'공용부',0,NULL),
  ('getHsmpElectricityCostInfoV3','electP','IND',N'전기료',N'세대부',0,
     N'한전 직공급 단지는 0 이다(장위참누리). 공용부와 더하면 다른 걸 섞는다'),
  ('getHsmpWaterCostInfoV3','waterCoolC','IND',N'수도료',N'공용부',0,NULL),
  ('getHsmpWaterCostInfoV3','waterCoolP','IND',N'수도료',N'세대부',0,NULL),
  ('getHsmpWaterPurifierTankFeeInfoV3','purifi','IND',N'정화조오물수수료',NULL,0,NULL),
  ('getHsmpDomesticWasteFeeInfoV3','scrap','IND',N'생활폐기물수수료',NULL,0,NULL),
  ('getHsmpBuildingInsuranceFeeInfoV3','buildInsu','IND',N'건물보험료',NULL,0,NULL),
  ('getHsmpMovingInRepresentationMtgInfoV3','preMeet','IND',N'입주자대표회의운영비',NULL,0,NULL),
  ('getHsmpElectionOrpnsInfoV3','electionMng','IND',N'선거관리위원회운영비',NULL,0,NULL),
  /* --- 장기수선충당금 4종 --- */
  ('getHsmpMonthFeeInfoV3','sLevy','REP',N'장기수선충당금',N'월 부과액',1,NULL),
  ('getHsmpReserveBalanceInfoV3','sTot','REP',N'장기수선충당금',N'적립 잔액',1,
     N'누적액이라 준공 연도에 좌우된다. 세대당으로 보되 연식과 같이 본다'),
  ('getHsmpAccumulationTariffInfoV3','sPer','REP',N'장기수선충당금',N'적립 요율',1,
     N'단위가 원이 아니다. 금액 합계에 넣지 말 것'),
  ('getHsmpMonthRetalFeeInfoV3','sUse','REP',N'장기수선충당금',N'월 사용액',1,NULL)
) AS s (op, fld, svc, item_nm, sub_nm, cmprbl, note)
   ON t.op = s.op AND t.fld = s.fld
WHEN MATCHED THEN UPDATE SET
     t.svc = s.svc, t.item_nm = s.item_nm, t.sub_nm = s.sub_nm,
     t.cmprbl = s.cmprbl, t.note = s.note
WHEN NOT MATCHED BY TARGET THEN
     INSERT (op, fld, svc, item_nm, sub_nm, cmprbl, note)
     VALUES (s.op, s.fld, s.svc, s.item_nm, s.sub_nm, s.cmprbl, s.note);
GO
/* ------------------------------------------------------------
   gold.v_kapt_cost_item — 원본 한 줄에 한글 이름을 붙인 것

   사전에 없는 필드도 사라지지 않는다(LEFT JOIN). API 가 필드를 추가하면
   item_nm 이 NULL 로 뜨고, 그게 "사전에 추가하라" 는 신호다.
   ------------------------------------------------------------ */
CREATE OR ALTER VIEW gold.v_kapt_cost_item AS
SELECT c.kapt_code, c.ym, c.svc, c.op, c.fld, c.amount,
       항목 = d.item_nm, 세부 = d.sub_nm,
       비교가능 = d.cmprbl,
       사전등록 = CASE WHEN d.op IS NULL THEN 0 ELSE 1 END,
       비고 = d.note,
       c.chg_cnt, c.loaded_at
FROM silver.kapt_cost c
LEFT JOIN meta.kapt_cost_item d ON d.op = c.op AND d.fld = c.fld;
GO

/* ------------------------------------------------------------
   gold.v_kapt_cost_cmn — 공용관리비, 단지 × 월

   세대당 금액이 이 축의 핵심이다. 분모는 hhld_cnt(세대수)다.
   세대수가 0 이거나 없으면 세대당을 내지 않는다(0 으로 나누지 않고 NULL 로 둔다).
   신축 미입주 단지가 0 으로 오기 때문이다.

   사람값 = 인건비 + 청소비 + 경비비. 장위동 11개 단지에서 합계의 84% 였다.
   이 비중이 공용관리비를 단지 간 비교 가능한 축으로 만든다.
   ------------------------------------------------------------ */
CREATE OR ALTER VIEW gold.v_kapt_cost_cmn AS
WITH a AS (
    SELECT c.kapt_code, c.ym,
           합계     = SUM(c.amount),
           인건비   = SUM(CASE WHEN c.op = 'getHsmpLaborCostInfoV3'            THEN c.amount END),
           청소비   = SUM(CASE WHEN c.op = 'getHsmpCleaningCostInfoV3'         THEN c.amount END),
           경비비   = SUM(CASE WHEN c.op = 'getHsmpGuardCostInfoV3'            THEN c.amount END),
           수선비   = SUM(CASE WHEN c.op = 'getHsmpRepairsCostInfoV3'          THEN c.amount END),
           시설유지 = SUM(CASE WHEN c.op = 'getHsmpFacilityMntncCostInfoV3'    THEN c.amount END),
           안전점검 = SUM(CASE WHEN c.op = 'getHsmpSafetyCheckUpCostInfoV3'    THEN c.amount END),
           재해예방 = SUM(CASE WHEN c.op = 'getHsmpDisasterPreventionCostInfoV3' THEN c.amount END),
           승강기   = SUM(CASE WHEN c.op = 'getHsmpElevatorMntncCostInfoV3'    THEN c.amount END),
           위탁수수료 = SUM(CASE WHEN c.op = 'getHsmpConsignManageFeeInfoV3'   THEN c.amount END),
           제세공과금 = SUM(CASE WHEN c.op = 'getHsmpTaxdueInfoV3'             THEN c.amount END),
           항목수   = COUNT(*)
    FROM silver.kapt_cost c
    WHERE c.svc = 'CMN'
    GROUP BY c.kapt_code, c.ym
)
SELECT a.kapt_code, a.ym,
       단지명 = k.kapt_name,
       세대   = NULLIF(k.hhld_cnt, 0),
       호수   = NULLIF(k.ho_cnt, 0),
       사용승인 = k.kapt_usedate,
       a.합계, a.인건비, a.청소비, a.경비비,
       사람값 = ISNULL(a.인건비,0) + ISNULL(a.청소비,0) + ISNULL(a.경비비,0),
       수선유지 = ISNULL(a.수선비,0) + ISNULL(a.시설유지,0)
                + ISNULL(a.안전점검,0) + ISNULL(a.재해예방,0),
       a.승강기, a.위탁수수료, a.제세공과금,
       세대당 = CASE WHEN NULLIF(k.hhld_cnt,0) IS NULL THEN NULL
                     ELSE CAST(a.합계 / k.hhld_cnt AS DECIMAL(18,0)) END,
       사람값비중 = CASE WHEN NULLIF(a.합계,0) IS NULL THEN NULL
                     ELSE CAST(100.0 * (ISNULL(a.인건비,0)+ISNULL(a.청소비,0)+ISNULL(a.경비비,0))
                               / a.합계 AS DECIMAL(5,1)) END,
       a.항목수
FROM a
JOIN silver.kapt_complex k ON k.kapt_code = a.kapt_code AND k.is_current = 1;
GO

/* ------------------------------------------------------------
   gold.v_kapt_cost_rep — 장기수선충당금, 단지 × 월

   ★ sPer(적립 요율) 은 금액이 아니다. 합계에 넣지 않는다.
   ★ 적립 잔액은 누적액이다. 준공이 오래된 단지가 당연히 크다.
     세대당으로 보고, 연식과 같이 봐야 의미가 생긴다.
   ------------------------------------------------------------ */
CREATE OR ALTER VIEW gold.v_kapt_cost_rep AS
WITH a AS (
    SELECT kapt_code, ym,
           월부과 = SUM(CASE WHEN fld = 'sLevy' THEN amount END),
           잔액   = SUM(CASE WHEN fld = 'sTot'  THEN amount END),
           월사용 = SUM(CASE WHEN fld = 'sUse'  THEN amount END),
           요율   = SUM(CASE WHEN fld = 'sPer'  THEN amount END)
    FROM silver.kapt_cost
    WHERE svc = 'REP'
    GROUP BY kapt_code, ym
)
SELECT a.kapt_code, a.ym,
       단지명 = k.kapt_name,
       세대 = NULLIF(k.hhld_cnt, 0),
       사용승인 = k.kapt_usedate,
       a.월부과, a.잔액, a.월사용, a.요율,
       월부과_세대당 = CASE WHEN NULLIF(k.hhld_cnt,0) IS NULL THEN NULL
                        ELSE CAST(a.월부과 / k.hhld_cnt AS DECIMAL(18,0)) END,
       잔액_세대당   = CASE WHEN NULLIF(k.hhld_cnt,0) IS NULL THEN NULL
                        ELSE CAST(a.잔액   / k.hhld_cnt AS DECIMAL(18,0)) END
FROM a
JOIN silver.kapt_complex k ON k.kapt_code = a.kapt_code AND k.is_current = 1;
GO

/* ------------------------------------------------------------
   gold.v_kapt_cost_latest — 단지당 1행. 가장 최근 달.

   ★ 개별사용료는 여기 없다. 단지 간 비교에 쓰지 않기 때문이다(정책.md 3-9).
     보려면 gold.v_kapt_cost_item 에서 svc='IND' 로 직접 본다.
   ★ 공용관리비 합계와 장충을 더한 "총 관리비" 컬럼을 만들지 않는다.
     성격이 다른 돈이고, 더하면 그 합이 사실처럼 쓰인다.
   ------------------------------------------------------------ */
CREATE OR ALTER VIEW gold.v_kapt_cost_latest AS
WITH m AS (
    SELECT kapt_code, ym = MAX(ym) FROM silver.kapt_cost GROUP BY kapt_code
)
SELECT m.kapt_code, m.ym,
       단지명 = k.kapt_name,
       법정동 = l.emd_nm,
       세대 = NULLIF(k.hhld_cnt, 0),
       사용승인 = k.kapt_usedate,
       공용관리비 = c.합계,
       세대당 = c.세대당,
       사람값비중 = c.사람값비중,
       장충_월부과 = r.월부과,
       장충_잔액 = r.잔액,
       장충_잔액_세대당 = r.잔액_세대당,
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
/* ============================================================
   (2) 의 뒤처리 — ho_cnt(호수) 를 "세대" 로 쓰던 뷰를 고친다

   21_kapt_link.sql 의 정의를 그대로 가져와 **두 줄만** 바꿨다.
   새로 쓰지 않는다 — 조인을 다시 짜다가 엉뚱한 테이블을 붙일 뻔했다(2026-10-16).

   아직 남은 것: 16_gap_states.sql / 19_newbuild_date.sql 의 `세대 = k.ho_cnt`.
   그쪽은 신축 단지(세대수가 0 으로 오는 구간)를 다루는 뷰라 호수가 오히려
   맞는 경우가 섞여 있다. 재적재로 hhld_cnt 가 채워진 뒤에 실측하고 고친다.
   ============================================================ */
CREATE OR ALTER VIEW gold.v_complex_kapt
AS
WITH p AS (
    SELECT c.complex_id, c.hhld_cnt_sum, c.dong_cnt, c.max_floor, c.oldest_use_apr,
           k.kapt_code
    FROM gold.complex c
    JOIN silver.kapt_complex k
      ON k.is_current = 1
     AND k.bjd_code = c.sigungu_cd + c.bjdong_cd
     AND k.kapt_usedate = c.oldest_use_apr
     AND NULLIF(k.kapt_usedate, '') IS NOT NULL
)
SELECT p.complex_id,
       k.kapt_code, k.kapt_name, k.kapt_addr, k.doro_juso,
       /* 대조용 — 매칭이 맞으면 맞아떨어진다 */
       /* ★ hoCnt 는 호수, kaptdaCnt 가 세대수다. 대장의 세대수합과 비교하려면
            세대수를 써야 한다. 호수로 비교하면 멀쩡한 단지가 어긋난 것처럼 보인다
            — 래미안퍼스트하이 호수 1,568 / 세대수 1,562 = 대장 1,562 (정확히 일치).
            적재 전 기존 행은 hhld_cnt 가 NULL 이라 호수로 떨어진다. */
       kapt_세대 = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt),
       kapt_호수 = k.ho_cnt,       대장_세대 = p.hhld_cnt_sum,
       kapt_동수 = k.dong_cnt,     대장_동수 = p.dong_cnt,
       kapt_최고층 = k.top_floor,  대장_최고층 = p.max_floor,
       사용승인 = k.kapt_usedate,
       /* 본문 */
       난방 = k.code_heat_nm, 복도 = k.code_hall_nm, 관리 = k.code_mgr_nm,
       분양임대 = k.code_sale_nm, 유형 = k.code_apt_nm,
       시공 = k.bcompany, 시행 = k.acompany,
       관리인원 = k.mgr_cnt,
       지하철 = k.subway_station, 지하철노선 = k.subway_line,
       지하철도보 = k.wtime_sub, 버스도보 = k.wtime_bus,
       /* ★ parking_cnt 에 kaptdaCnt(세대수)가 들어가 있었다. 화면이 주차로
            보여주고 있었다. 지금은 지상+지하 합이고, 재적재 전에는 상세 두 컬럼으로 떨어진다 */
       주차 = ISNULL(k.parking_ground, 0) + ISNULL(k.parking_under, 0),
       주차_원본 = k.parking_cnt,
       주차_지상 = k.parking_ground, 주차_지하 = k.parking_under,
       전기차_지상 = k.el_charger_ground, 전기차_지하 = k.el_charger_under,
       CCTV = k.cctv_cnt,
       경비인원 = k.sec_cnt, 경비업체 = k.sec_company, 경비방식 = k.code_sec_nm,
       청소인원 = k.clean_cnt, 청소업체 = k.clean_company, 청소방식 = k.code_clean_nm,
       음식물 = k.code_garbage_nm, 소독 = k.code_disinf_nm, 승강기관리 = k.code_elev_nm,
       부대복리시설 = k.welfare_facility, 편의시설 = k.convenient_facility,
       교육시설 = k.education_facility,
       연면적 = k.kapt_tarea, 전용면적합 = k.priv_area
FROM p
JOIN silver.kapt_complex k ON k.kapt_code = p.kapt_code AND k.is_current = 1
WHERE 1 = (SELECT COUNT(*) FROM p p2 WHERE p2.complex_id = p.complex_id)
  AND 1 = (SELECT COUNT(*) FROM p p3 WHERE p3.kapt_code  = p.kapt_code);
GO
