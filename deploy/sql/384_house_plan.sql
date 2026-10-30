/* 384 주택 사업계획승인(주택인허가) — 공고 전 · 공사 중 아파트 (2026-10-30 사장님 "ㄱㄱ")
   ★ 원천: hub.t0201(주택인허가 기본개요) · hub.t0215(대지위치) — 건축HUB 대용량 전국 파일, 원문 그대로. 이 표(gold.house_plan)는 **파생**(다시 만든다).
   ★ 고르는 규칙(추측 없음):
     · 지금 판(마지막월 IS NULL) · 총세대 20+ · 사용검사일 **비어 있음** · 승인일 2016-01-01 이후
     · 위치: 기본개요의 지번(대지구분 0 = 일반 → PNU 11번째 1 · 1 = 산 → 2). 블록(2)·지번 없음이면 대지위치(0215)의 대표 지번 → 아무 지번.
       PNU 가 지금 필지에 있을 때만 좌표(필지 중심) — 없으면 좌표 NULL(지도에 안 그림 · 목록엔 남음)
     · '완공 대장 있음': 그 필지에 지금 건축물대장(표제부)이 있고 사용승인일 ≥ 승인일이면 — 사용검사일 칸이 비어 있어도 다 지은 것 → 지도에서 뺀다(상태로 남김)
   ★ 이름은 원문(건물_명) 그대로. 단지와 이름으로 잇지 않는다. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF OBJECT_ID('gold.house_plan') IS NULL
CREATE TABLE gold.house_plan (
    hp_pk        VARCHAR(40)   NOT NULL CONSTRAINT pk_house_plan PRIMARY KEY,
    이름         NVARCHAR(200) NULL,
    대지위치     NVARCHAR(300) NULL,
    pnu          CHAR(19)      NULL,
    위치근거     NVARCHAR(60)  NULL,
    세대         INT           NULL,
    주건축물수   INT           NULL,
    연면적       DECIMAL(18,2) NULL,
    용도         NVARCHAR(100) NULL,
    승인일       CHAR(8)       NULL,
    착공예정일   CHAR(8)       NULL,
    착공일       CHAR(8)       NULL,
    사용검사예정일 CHAR(8)     NULL,
    상태         NVARCHAR(40)  NULL,
    lat          FLOAT         NULL,
    lng          FLOAT         NULL,
    처음월       CHAR(6)       NULL,
    만든때       DATETIME2(0)  NOT NULL CONSTRAINT df_house_plan DEFAULT SYSDATETIME()
);
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_house_plan
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    IF OBJECT_ID('tempdb..#b') IS NOT NULL DROP TABLE #b;
    SELECT hp_pk = h.관리_주택대장_PK, 이름 = gold.fn_name_mask(NULLIF(LTRIM(RTRIM(h.건물_명)), ''))  /* 390: 끝 괄호의 사람 이름은 가린다 */, 대지위치 = h.대지_위치,
           pnu0 = CASE WHEN ISNULL(h.대지_구분_코드, '0') IN ('0', '1') AND TRY_CAST(h.번 AS INT) > 0 AND LEN(h.시군구_코드) = 5 AND LEN(h.법정동_코드) = 5
                       THEN CAST(h.시군구_코드 + h.법정동_코드 + CASE WHEN h.대지_구분_코드 = '1' THEN '2' ELSE '1' END
                                 + RIGHT('0000' + CAST(TRY_CAST(h.번 AS INT) AS VARCHAR(4)), 4)
                                 + RIGHT('0000' + CAST(ISNULL(TRY_CAST(h.지 AS INT), 0) AS VARCHAR(4)), 4) AS CHAR(19)) END,
           세대 = TRY_CAST(h.총_세대_수 AS INT), 주건축물수 = TRY_CAST(h.주_건축물_수 AS INT), 연면적 = TRY_CAST(h.연면적 AS DECIMAL(18,2)),
           용도 = NULLIF(h.용도_코드_명, ''), 승인일 = NULLIF(h.승인_일, ''), 착공예정일 = NULLIF(h.착공_예정_일, ''), 착공일 = NULLIF(h.착공_일, ''),
           사용검사예정일 = NULLIF(h.사용_검사_예정_일, ''), h.처음월
      INTO #b
      FROM hub.t0201 h
     WHERE h.마지막월 IS NULL AND TRY_CAST(h.총_세대_수 AS INT) >= 20 AND ISNULL(h.사용_검사_일, '') = '' AND h.승인_일 >= '20160101';

    /* 대지위치(0215) 지번 — 기본개요에 지번이 없거나 블록일 때. 대표 먼저 */
    IF OBJECT_ID('tempdb..#j') IS NOT NULL DROP TABLE #j;
    SELECT hp_pk = d.관리_주택대장_PK,
           pnu = CAST(d.시군구_코드 + d.법정동_코드 + CASE WHEN d.대지_구분_코드 = '1' THEN '2' ELSE '1' END
                      + RIGHT('0000' + CAST(TRY_CAST(d.번 AS INT) AS VARCHAR(4)), 4)
                      + RIGHT('0000' + CAST(ISNULL(TRY_CAST(d.지 AS INT), 0) AS VARCHAR(4)), 4) AS CHAR(19)),
           rn = ROW_NUMBER() OVER (PARTITION BY d.관리_주택대장_PK ORDER BY CASE WHEN d.대표_여부 = '1' THEN 0 ELSE 1 END, d.번, d.지)
      INTO #j
      FROM hub.t0215 d JOIN #b b ON b.hp_pk = d.관리_주택대장_PK
     WHERE d.마지막월 IS NULL AND ISNULL(d.대지_구분_코드, '0') IN ('0', '1') AND TRY_CAST(d.번 AS INT) > 0
       AND LEN(d.시군구_코드) = 5 AND LEN(d.법정동_코드) = 5;

    IF OBJECT_ID('tempdb..#r') IS NOT NULL DROP TABLE #r;
    SELECT b.*, pnu = COALESCE(p0.pnu, p1.pnu),
           위치근거 = CASE WHEN p0.pnu IS NOT NULL THEN N'기본개요 지번 필지 중심' WHEN p1.pnu IS NOT NULL THEN N'대지위치 지번 필지 중심' END,
           lat = COALESCE(p0.centroid_lat, p1.centroid_lat), lng = COALESCE(p0.centroid_lng, p1.centroid_lng)
      INTO #r
      FROM #b b
      LEFT JOIN silver.cadastral_parcel p0 ON p0.pnu = b.pnu0 AND p0.is_current = 1
      OUTER APPLY (SELECT TOP 1 j.pnu, cp.centroid_lat, cp.centroid_lng FROM #j j JOIN silver.cadastral_parcel cp ON cp.pnu = j.pnu AND cp.is_current = 1
                    WHERE j.hp_pk = b.hp_pk ORDER BY j.rn) p1;

    /* 완공 대장 있음: 그 필지 지금 표제부의 사용승인일 ≥ 승인일 */
    IF OBJECT_ID('tempdb..#done') IS NOT NULL DROP TABLE #done;
    SELECT DISTINCT r.hp_pk INTO #done
      FROM #r r JOIN silver.bld_title t ON t.is_current = 1 AND t.sigungu_cd = LEFT(r.pnu, 5) AND t.bjdong_cd = SUBSTRING(r.pnu, 6, 5)
                                      AND TRY_CAST(t.bun AS INT) = CAST(SUBSTRING(r.pnu, 12, 4) AS INT) AND ISNULL(TRY_CAST(t.ji AS INT), 0) = CAST(RIGHT(r.pnu, 4) AS INT)
     WHERE r.pnu IS NOT NULL AND t.use_apr_day >= r.승인일;

    BEGIN TRAN;
        DELETE FROM gold.house_plan;
        INSERT INTO gold.house_plan (hp_pk, 이름, 대지위치, pnu, 위치근거, 세대, 주건축물수, 연면적, 용도, 승인일, 착공예정일, 착공일, 사용검사예정일, 상태, lat, lng, 처음월)
        SELECT r.hp_pk, r.이름, r.대지위치, r.pnu, r.위치근거, r.세대, r.주건축물수, r.연면적, r.용도, r.승인일, r.착공예정일, r.착공일, r.사용검사예정일,
               CASE WHEN d.hp_pk IS NOT NULL THEN N'완공 대장 있음' WHEN r.착공일 IS NOT NULL THEN N'착공' ELSE N'사업승인' END,
               r.lat, r.lng, r.처음월
          FROM #r r LEFT JOIN #done d ON d.hp_pk = r.hp_pk;
    COMMIT;
    SELECT 전체 = COUNT(*), 좌표 = COUNT(lat), 사업승인 = SUM(CASE WHEN 상태 = N'사업승인' THEN 1 ELSE 0 END),
           착공 = SUM(CASE WHEN 상태 = N'착공' THEN 1 ELSE 0 END), 완공대장 = SUM(CASE WHEN 상태 = N'완공 대장 있음' THEN 1 ELSE 0 END)
      FROM gold.house_plan;
END
GO
EXEC gold.usp_refresh_house_plan;
GO
SELECT x = (SELECT STRING_AGG(CAST(CONCAT(hp_pk, ' ', 이름, ' ', 세대, '세대 승인', 승인일, ' ', 상태, ' ', 위치근거, ' ', ROUND(lat, 5), ',', ROUND(lng, 5)) AS NVARCHAR(MAX)), ' ## ') FROM gold.house_plan WHERE hp_pk = '1030100004481');
