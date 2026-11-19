SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
        /* 시각 칸은 UTC(컨테이너 SYSDATETIME) → 한국 시각으로 */
        SELECT TOP 8 run_id, 시작 = DATEADD(HOUR, 9, 시작), 끝 = DATEADD(HOUR, 9, 끝), 범위, 메모 FROM ops.rtms_gone_run ORDER BY run_id DESC;
        /* 종류마다 그 종류를 대조한 가장 최근 '서울 전체(시군구 25)' run — 분양권은 따로 다시 대조했다(11-19 run 4) */
        WITH r AS (SELECT run_id FROM ops.rtms_gone_run WHERE 끝 IS NOT NULL AND 범위 LIKE N'%시군구 25%'),
             k AS (SELECT b.trade_kind, run = MAX(b.run_id) FROM ops.rtms_gone_bundle b JOIN r ON r.run_id = b.run_id GROUP BY b.trade_kind),
             g AS (SELECT run_id, trade_kind, 격리 = COUNT(*) FROM ops.rtms_gone_bak GROUP BY run_id, trade_kind),
             b AS (SELECT k.run, b.trade_kind, 묶음 = COUNT(*), 받기실패 = SUM(CASE WHEN b.상태 <> 'OK' THEN 1 ELSE 0 END),
                          원천줄 = SUM(CAST(b.원천줄 AS BIGINT)), 적재줄 = SUM(CAST(b.적재줄 AS BIGINT)), 적재에만 = SUM(ISNULL(b.적재에만, 0)), 원천에만 = SUM(ISNULL(b.원천에만, 0))
                     FROM k JOIN ops.rtms_gone_bundle b ON b.run_id = k.run AND b.trade_kind = k.trade_kind GROUP BY k.run, b.trade_kind)
        SELECT b.*, 격리 = ISNULL(g.격리, 0), 끝 = DATEADD(HOUR, 9, x.끝)
          FROM b LEFT JOIN g ON g.run_id = b.run AND g.trade_kind = b.trade_kind JOIN ops.rtms_gone_run x ON x.run_id = b.run ORDER BY b.trade_kind;
        SELECT run_id, trade_kind, 줄 = COUNT(*), 단지 = COUNT(DISTINCT match_complex_id), 격리시각 = DATEADD(HOUR, 9, MAX(격리시각))
          FROM ops.rtms_gone_bak GROUP BY run_id, trade_kind ORDER BY run_id DESC, COUNT(*) DESC;
