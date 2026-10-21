/* 목표별 ops 비교 (2026-10-19) - 안양에 rtms 가 왜 안 들어갔는지 */
SET NOCOUNT ON;
SELECT target_id, sgg_cd, bjdong_cd = ISNULL(bjdong_cd,'전체'),
       ops, priority, enabled, note
  FROM meta.load_target
 ORDER BY priority, sgg_cd, bjdong_cd;
