/* 387 공사 중 건물(건축허가 신축 · 착공 · 사용승인 전) — 대장 단지처럼 보이는 상세용 (2026-10-30 사장님 "그냥 일반 건대장 나온 단지처럼 보여줄 수 있는 거 아니야?" · "ㄱㄱ")
   ★ 원천: silver.arch_permit(건축인허가 기본개요 — 전국 허브판) · 동별개요 · hub.t0103 층별개요 · 386 파생표. 원문 그대로, 이 표는 **파생**.
   ★ 고르는 규칙(추측 없음):
     · 지금 판 · 건축구분 '신축' · 실제 착공일 2022-01-01 이후 · 사용승인일 비어 있음
     · 그 필지에 지금 건축물대장(표제부)이 있고 사용승인일 ≥ 허가일이면 뺀다 — 다 지어 대장이 생긴 것(대장 단지가 보여 준다)
     · 주용도 공동주택 이거나, 업무시설인데 층별개요 주용도(소분류)에 '오피스텔' 이 있는 것 · 세대 + 호 10 이상
     · 같은 필지에 여럿이면 허가일이 가장 늦은 한 건(설계변경으로 쌓인 옛 허가가 핀으로 겹치지 않게)
     · 좌표 = 그 필지(지금 지적도) 중심. 필지가 없으면 좌표 NULL(목록 · 검색에만)
   ★ 이름은 원문(건물_명) — 끝 괄호의 사람 이름만 가린다(390). 대장 단지와 이름으로 잇지 않는다.
   ★ 2019~2021 착공인데 승인 기록이 없는 건(22,617)은 공사 중이라 단정할 수 없어 넣지 않는다. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* 상세의 동별 층수(층별개요 → 허가 번호) — 원문 표에 색인만 더한다(값은 안 건드림) */
IF OBJECT_ID('hub.t0103') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_hub_t0103_pms' AND object_id = OBJECT_ID('hub.t0103'))
    CREATE INDEX ix_hub_t0103_pms ON hub.t0103 (관리_허가대장_PK) INCLUDE (관리_동별_개요_PK, 층_구분_코드_명, 층_번호, 주_용도_코드_명, 층_면적, 마지막월);
GO
CREATE OR ALTER PROCEDURE gold.usp_refresh_pre_build
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    IF OBJECT_ID('gold.pre_build_n') IS NOT NULL DROP TABLE gold.pre_build_n;
    ;WITH c AS (
        SELECT a.mgm_pmsrgst_pk, a.pnu, a.bld_nm, a.plat_plc, a.main_purps_nm, a.hhld_cnt, a.ho_cnt, a.fmly_cnt, a.tot_area, a.main_bld_cnt,
               a.arch_pms_day, a.stcns_sched_day, a.real_stcns_day,
               /* 동별개요 주용도는 대분류(업무시설)뿐이라 오피스텔을 못 가른다 → 층별개요 주용도(소분류 원문)에 '오피스텔' 이 있는지 */
               오피스텔 = CASE WHEN a.main_purps_nm = N'업무시설' AND EXISTS (SELECT 1 FROM hub.t0103 f WHERE f.관리_허가대장_PK = a.mgm_pmsrgst_pk AND f.마지막월 IS NULL AND f.주_용도_코드_명 LIKE N'%오피스텔%') THEN 1 ELSE 0 END
          FROM silver.arch_permit a
         WHERE a.is_current = 1 AND a.arch_gb_nm = N'신축'
           AND NULLIF(LTRIM(a.use_apr_day), '') IS NULL
           AND a.real_stcns_day >= '20220101' AND LEN(a.real_stcns_day) = 8
           AND a.pnu IS NOT NULL
           AND ISNULL(a.hhld_cnt, 0) + ISNULL(a.ho_cnt, 0) >= 10
           AND a.main_purps_nm IN (N'공동주택', N'업무시설')
           AND NOT EXISTS (SELECT 1 FROM silver.bld_title t WHERE t.pnu = a.pnu AND t.is_current = 1 AND t.use_apr_day >= a.arch_pms_day)
    ), r AS (
        SELECT c.*, rn = ROW_NUMBER() OVER (PARTITION BY c.pnu ORDER BY c.arch_pms_day DESC, c.mgm_pmsrgst_pk DESC)
          FROM c WHERE c.main_purps_nm = N'공동주택' OR c.오피스텔 = 1
    )
    SELECT pk = CAST(r.mgm_pmsrgst_pk AS VARCHAR(50)), r.pnu,
           이름 = CAST(gold.fn_name_mask(NULLIF(LTRIM(RTRIM(r.bld_nm)), N'')) AS NVARCHAR(200)),  /* 390: 끝 괄호의 사람 이름은 가린다 */
           대지위치 = r.plat_plc, 용도 = CASE WHEN r.main_purps_nm = N'업무시설' THEN N'오피스텔(업무시설)' ELSE r.main_purps_nm END,
           세대 = r.hhld_cnt, 호 = r.ho_cnt, 가구 = r.fmly_cnt, 연면적 = r.tot_area, 주건축물수 = r.main_bld_cnt,
           허가일 = r.arch_pms_day, 착공예정일 = r.stcns_sched_day, 착공일 = r.real_stcns_day,
           lat = CAST(p.centroid_lat AS FLOAT), lng = CAST(p.centroid_lng AS FLOAT),
           만든때 = SYSDATETIME()
      INTO gold.pre_build_n
      FROM r
      OUTER APPLY (SELECT TOP 1 cp.centroid_lat, cp.centroid_lng FROM silver.cadastral_parcel cp WHERE cp.pnu = r.pnu AND cp.is_current = 1) p
     WHERE r.rn = 1;
    CREATE UNIQUE CLUSTERED INDEX cx_pre_build ON gold.pre_build_n (pk);
    CREATE INDEX ix_pre_build_ll ON gold.pre_build_n (lat, lng) INCLUDE (이름, 세대, 호, 용도, 착공일);
    BEGIN TRAN;
        IF OBJECT_ID('gold.pre_build') IS NOT NULL DROP TABLE gold.pre_build;
        EXEC sp_rename 'gold.pre_build_n', 'pre_build';
    COMMIT;
    SELECT 전체 = COUNT(*), 좌표 = SUM(CASE WHEN lat IS NOT NULL THEN 1 ELSE 0 END),
           공동주택 = SUM(CASE WHEN 용도 = N'공동주택' THEN 1 ELSE 0 END), 오피스텔 = SUM(CASE WHEN 용도 <> N'공동주택' THEN 1 ELSE 0 END)
      FROM gold.pre_build;
END
GO
EXEC gold.usp_refresh_pre_build;
GO
