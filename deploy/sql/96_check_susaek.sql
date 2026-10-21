SET NOCOUNT ON;
PRINT '=== A) DB 의 수색동 지번별 건수 (410~420) ===';
SELECT bun, 건수=COUNT(*), 종류=COUNT(DISTINCT regstr_kind_cd)
  FROM silver.bld_basis_outline
 WHERE is_current=1 AND sigungu_cd='11380' AND bjdong_cd='10100'
   AND bun BETWEEN '0410' AND '0420'
 GROUP BY bun ORDER BY bun;

PRINT '';
PRINT '=== B) 수색동 전체 건수 (API 는 9,174) ===';
SELECT 전체=COUNT(*), 현재행=SUM(CASE WHEN is_current=1 THEN 1 ELSE 0 END),
       지번수=COUNT(DISTINCT bun)
  FROM silver.bld_basis_outline
 WHERE sigungu_cd='11380' AND bjdong_cd='10100';

PRINT '';
PRINT '=== C) bun 이 어떤 꼴로 저장돼 있나 (앞 10개) ===';
SELECT TOP 10 bun, LEN(bun) AS 길이, 건수=COUNT(*)
  FROM silver.bld_basis_outline
 WHERE is_current=1 AND sigungu_cd='11380' AND bjdong_cd='10100'
 GROUP BY bun, LEN(bun) ORDER BY bun;

PRINT '';
PRINT '=== D) 그 적재가 뭐라고 기록했나 ===';
SELECT r.run_id, s.operation, r.scope_key, r.status,
       r.req_count, r.row_count, r.started_at, r.finished_at, r.err_msg
  FROM meta.ingest_run r JOIN meta.api_source s ON s.source_id=r.source_id
 WHERE r.scope_key='11380/10100'
 ORDER BY r.started_at;
