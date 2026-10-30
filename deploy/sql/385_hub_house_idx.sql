/* 385 주택인허가 승인 단지 상세(/api/houseplans/:pk)용 찾기 색인 (2026-10-30) — 원문 표에 색인만 더한다(값은 안 건드림)
   t0202 동별개요: 주택대장PK · t0204 호별개요: 동별개요PK · t0212 관리공동형별개요: 지번 */
IF OBJECT_ID('hub.t0202') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_hub_t0202_hp')
    CREATE INDEX ix_hub_t0202_hp ON hub.t0202 (관리_주택대장_PK) INCLUDE (마지막월);
GO
IF OBJECT_ID('hub.t0204') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_hub_t0204_dong')
    CREATE INDEX ix_hub_t0204_dong ON hub.t0204 (관리_동별_개요_PK) INCLUDE (마지막월, 평형_구분_명);
GO
IF OBJECT_ID('hub.t0212') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_hub_t0212_jibun')
    CREATE INDEX ix_hub_t0212_jibun ON hub.t0212 (시군구_코드, 법정동_코드, 번) INCLUDE (지, 사업_승인_일, 마지막월);
GO
SELECT x = (SELECT STRING_AGG(name, ', ') FROM sys.indexes WHERE name LIKE 'ix_hub_t02%');
