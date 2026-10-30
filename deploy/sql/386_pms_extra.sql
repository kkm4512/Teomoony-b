/* 386 건축인허가 부가 원문 — 평형 · 층별 용도 · 철거멸실 (2026-10-30 사장님 "ㄱㄱ+")
   ★ 원천: 건축HUB 건축인허가 대용량 전국 파일, 원문 그대로(hub.t0103 층별개요 · t0104 호별개요 · t0107 철거멸실관리대장 · t0112 전유공용면적).
     받아만 두고 화면에 안 쓰던 것을 잇는다. 이 표 셋은 **파생**(언제든 다시 만든다 — 원문은 hub 에 그대로).
   ★ 잇는 열쇠(실측 · 추측 없음)
     · 호별개요 · 전유공용면적 · 층별개요 → 관리_허가대장_PK (기본개요와 100% 같은 번호, 표본 500/500)
     · 철거멸실 → 관리_허가대장_PK 가 **비어 있다** → 지번(시군구 · 법정동 · 대지구분 · 번 · 지)으로 PNU (대지구분 0 → 1, 1(산) → 2)
   ★ 값 규칙
     · 평형 = 평형_구분_명 원문(84A · 153-1 · 301 …). 전유 = 그 평형의 '전유' 면적 합, 공용 = '공용' 면적 합, 호수 = 호별개요에서 그 평형인 호 개수
       — **허가(설계) 기준**이다. 설계변경 · 사용승인 뒤 대장 값과 다를 수 있다(화면이 그렇게 적는다).
     · 층별 = (층 구분 · 주용도)마다 가장 낮은 층 ~ 가장 높은 층 · 층 수 · 면적 합. 여러 동을 합친 범위다.
     · 철거멸실 = 원문 칸 그대로(구분 · 시작 · 종료 · 멸실일 · 연면적 · 동수 · 용도 · 구조 · 세대 · 가구 · 호 · 석면 함유 표시).
   ★ 다시 만들 때 읽는 쪽을 막지 않게 _n 표에 다 만든 뒤 이름만 바꿔 끼운다. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_pms_extra
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    /* ── 1. 평형 (전유공용면적 + 호별개요) ── */
    IF OBJECT_ID('gold.pms_unit_type_n') IS NOT NULL DROP TABLE gold.pms_unit_type_n;
    CREATE TABLE gold.pms_unit_type_n (
        mgm_pmsrgst_pk VARCHAR(50)   NOT NULL,
        평형           NVARCHAR(100) NOT NULL,
        호수           INT           NULL,
        전유           DECIMAL(18,4) NULL,
        공용           DECIMAL(18,4) NULL,
        용도           NVARCHAR(100) NULL,
        기타용도       NVARCHAR(200) NULL
    );
    ;WITH a AS (
        SELECT pk = CAST(LTRIM(RTRIM(관리_허가대장_PK)) AS VARCHAR(50)),
               평형 = CAST(LTRIM(RTRIM(평형_구분_명)) AS NVARCHAR(100)),
               전유 = SUM(CASE WHEN 전유_공용_구분_코드_명 = N'전유' THEN TRY_CONVERT(DECIMAL(18,4), TRY_CONVERT(FLOAT, NULLIF(LTRIM(면적), N''))) END),
               공용 = SUM(CASE WHEN 전유_공용_구분_코드_명 = N'공용' THEN TRY_CONVERT(DECIMAL(18,4), TRY_CONVERT(FLOAT, NULLIF(LTRIM(면적), N''))) END),
               용도 = MAX(CASE WHEN 전유_공용_구분_코드_명 = N'전유' THEN CAST(NULLIF(LTRIM(RTRIM(주_용도_코드_명)), N'') AS NVARCHAR(100)) END),
               기타용도 = MAX(CASE WHEN 전유_공용_구분_코드_명 = N'전유' THEN CAST(NULLIF(LTRIM(RTRIM(기타_용도)), N'') AS NVARCHAR(200)) END)
          FROM hub.t0112
         WHERE 마지막월 IS NULL AND NULLIF(LTRIM(관리_허가대장_PK), N'') IS NOT NULL AND NULLIF(LTRIM(평형_구분_명), N'') IS NOT NULL
         GROUP BY LTRIM(RTRIM(관리_허가대장_PK)), LTRIM(RTRIM(평형_구분_명))
    ), h AS (
        SELECT pk = CAST(LTRIM(RTRIM(관리_허가대장_PK)) AS VARCHAR(50)),
               평형 = CAST(LTRIM(RTRIM(평형_구분_명)) AS NVARCHAR(100)),
               호수 = COUNT(*)
          FROM hub.t0104
         WHERE 마지막월 IS NULL AND NULLIF(LTRIM(관리_허가대장_PK), N'') IS NOT NULL AND NULLIF(LTRIM(평형_구분_명), N'') IS NOT NULL
         GROUP BY LTRIM(RTRIM(관리_허가대장_PK)), LTRIM(RTRIM(평형_구분_명))
    )
    INSERT gold.pms_unit_type_n WITH (TABLOCK) (mgm_pmsrgst_pk, 평형, 호수, 전유, 공용, 용도, 기타용도)
    SELECT COALESCE(a.pk, h.pk), COALESCE(a.평형, h.평형), h.호수, a.전유, a.공용, a.용도, a.기타용도
      FROM a FULL JOIN h ON h.pk = a.pk AND h.평형 = a.평형;
    CREATE CLUSTERED INDEX cx_pms_unit_type ON gold.pms_unit_type_n (mgm_pmsrgst_pk);

    /* ── 2. 층별 용도 (층별개요) ── */
    IF OBJECT_ID('gold.pms_floor_use_n') IS NOT NULL DROP TABLE gold.pms_floor_use_n;
    CREATE TABLE gold.pms_floor_use_n (
        mgm_pmsrgst_pk VARCHAR(50)   NOT NULL,
        층구분         NVARCHAR(20)  NULL,
        용도           NVARCHAR(100) NULL,
        최저층         INT           NULL,
        최고층         INT           NULL,
        층줄수         INT           NULL,
        면적           DECIMAL(18,2) NULL
    );
    INSERT gold.pms_floor_use_n WITH (TABLOCK) (mgm_pmsrgst_pk, 층구분, 용도, 최저층, 최고층, 층줄수, 면적)
    SELECT CAST(LTRIM(RTRIM(관리_허가대장_PK)) AS VARCHAR(50)),
           CAST(NULLIF(LTRIM(RTRIM(층_구분_코드_명)), N'') AS NVARCHAR(20)),
           CAST(NULLIF(LTRIM(RTRIM(주_용도_코드_명)), N'') AS NVARCHAR(100)),
           MIN(TRY_CONVERT(INT, TRY_CONVERT(FLOAT, NULLIF(LTRIM(층_번호), N'')))),
           MAX(TRY_CONVERT(INT, TRY_CONVERT(FLOAT, NULLIF(LTRIM(층_번호), N'')))),
           COUNT(*),
           SUM(TRY_CONVERT(DECIMAL(18,2), TRY_CONVERT(FLOAT, NULLIF(LTRIM(층_면적), N''))))
      FROM hub.t0103
     WHERE 마지막월 IS NULL AND NULLIF(LTRIM(관리_허가대장_PK), N'') IS NOT NULL
     GROUP BY LTRIM(RTRIM(관리_허가대장_PK)), NULLIF(LTRIM(RTRIM(층_구분_코드_명)), N''), NULLIF(LTRIM(RTRIM(주_용도_코드_명)), N'');
    CREATE CLUSTERED INDEX cx_pms_floor_use ON gold.pms_floor_use_n (mgm_pmsrgst_pk);

    /* ── 3. 철거멸실 (지번 → PNU) ── */
    IF OBJECT_ID('gold.pms_demolish_n') IS NOT NULL DROP TABLE gold.pms_demolish_n;
    SELECT pnu = CASE WHEN LEN(LTRIM(RTRIM(시군구_코드))) = 5 AND LEN(LTRIM(RTRIM(법정동_코드))) = 5
                           AND TRY_CAST(NULLIF(LTRIM(번), N'') AS INT) IS NOT NULL
                      THEN CAST(LTRIM(RTRIM(시군구_코드)) + LTRIM(RTRIM(법정동_코드))
                                + CASE LTRIM(RTRIM(ISNULL(대지_구분_코드, N'0'))) WHEN N'1' THEN N'2' ELSE N'1' END
                                + RIGHT(N'0000' + CAST(TRY_CAST(번 AS INT) AS NVARCHAR(10)), 4)
                                + RIGHT(N'0000' + CAST(ISNULL(TRY_CAST(NULLIF(LTRIM(지), N'') AS INT), 0) AS NVARCHAR(10)), 4) AS CHAR(19)) END,
           행_sk,
           대지위치   = CAST(NULLIF(LTRIM(RTRIM(대지_위치)), N'') AS NVARCHAR(300)),
           건물명     = CAST(NULLIF(LTRIM(RTRIM(건물_명)), N'') AS NVARCHAR(200)),
           구분       = CAST(NULLIF(LTRIM(RTRIM(철거_멸실_구분_코드_명)), N'') AS NVARCHAR(40)),
           시작일     = CAST(NULLIF(LTRIM(RTRIM(철거_시작_일)), N'') AS CHAR(8)),
           종료일     = CAST(NULLIF(LTRIM(RTRIM(철거_종료_일)), N'') AS CHAR(8)),
           멸실일     = CAST(NULLIF(LTRIM(RTRIM(철거_멸실_일)), N'') AS CHAR(8)),
           연면적     = TRY_CONVERT(DECIMAL(18,2), TRY_CONVERT(FLOAT, NULLIF(LTRIM(연면적), N''))),
           건축물수   = TRY_CONVERT(INT, TRY_CONVERT(FLOAT, NULLIF(LTRIM(건축물_수), N''))),
           용도       = CAST(NULLIF(LTRIM(RTRIM(주_용도_코드_명)), N'') AS NVARCHAR(100)),
           구조       = CAST(NULLIF(LTRIM(RTRIM(구조_코드_명)), N'') AS NVARCHAR(100)),
           세대       = TRY_CONVERT(INT, TRY_CONVERT(FLOAT, NULLIF(LTRIM(세대_수), N''))),
           가구       = TRY_CONVERT(INT, TRY_CONVERT(FLOAT, NULLIF(LTRIM(가구_수), N''))),
           호         = TRY_CONVERT(INT, TRY_CONVERT(FLOAT, NULLIF(LTRIM(호_수), N''))),
           석면_천장재 = CAST(NULLIF(LTRIM(RTRIM(천장재_함유_유무)), N'') AS NVARCHAR(4)),
           석면_단열재 = CAST(NULLIF(LTRIM(RTRIM(단열재_함유_유무)), N'') AS NVARCHAR(4)),
           석면_지붕재 = CAST(NULLIF(LTRIM(RTRIM(지붕재_함유_유무)), N'') AS NVARCHAR(4)),
           석면_보온재 = CAST(NULLIF(LTRIM(RTRIM(보온재_함유_유무)), N'') AS NVARCHAR(4)),
           석면_바닥재 = CAST(NULLIF(LTRIM(RTRIM(바닥재_함유_유무)), N'') AS NVARCHAR(4)),
           석면_기타   = CAST(NULLIF(LTRIM(RTRIM(기타_함유_유무)), N'') AS NVARCHAR(4)),
           석면_해당없음 = CAST(NULLIF(LTRIM(RTRIM(해당없음_유무)), N'') AS NVARCHAR(4)),
           생성일     = CAST(NULLIF(LTRIM(RTRIM(생성_일자)), N'') AS CHAR(8))
      INTO gold.pms_demolish_n
      FROM hub.t0107
     WHERE 마지막월 IS NULL;
    DELETE gold.pms_demolish_n WHERE pnu IS NULL;
    CREATE CLUSTERED INDEX cx_pms_demolish ON gold.pms_demolish_n (pnu);

    /* ── 바꿔 끼우기 ── */
    BEGIN TRAN;
        IF OBJECT_ID('gold.pms_unit_type') IS NOT NULL DROP TABLE gold.pms_unit_type;
        EXEC sp_rename 'gold.pms_unit_type_n', 'pms_unit_type';
        IF OBJECT_ID('gold.pms_floor_use') IS NOT NULL DROP TABLE gold.pms_floor_use;
        EXEC sp_rename 'gold.pms_floor_use_n', 'pms_floor_use';
        IF OBJECT_ID('gold.pms_demolish') IS NOT NULL DROP TABLE gold.pms_demolish;
        EXEC sp_rename 'gold.pms_demolish_n', 'pms_demolish';
    COMMIT;

    SELECT 평형줄 = (SELECT COUNT_BIG(*) FROM gold.pms_unit_type),
           평형허가 = (SELECT COUNT(DISTINCT mgm_pmsrgst_pk) FROM gold.pms_unit_type),
           층줄 = (SELECT COUNT_BIG(*) FROM gold.pms_floor_use),
           철거줄 = (SELECT COUNT_BIG(*) FROM gold.pms_demolish);
END
GO
