/* 419 (2026-11-18 · DQM 발견 2 · 사장님 ㄱㄱ): 동이 뒤늦게 채워져 두 줄이 된 같은 거래 — 동 빈 옛 줄을 백업하고 지운다.
   짝 = 동만 빼고 키 칸(종류 · 시군구 · 법정동 · 지번 · 단지명 · 계약일 · 금액 · 보증금 · 월세 · 전용 · 연면적 · 층)이 같은 '동 있는 새 줄'.
   옛 줄 하나 = 새 줄 하나(1:1)일 때만 지운다. 11-18 21:41 실측 9,841줄(모두 아파트 매매 · 모두 1:1).
   ★ 되돌리기: SET IDENTITY_INSERT silver.rtms_trade ON; INSERT silver.rtms_trade (칸들) SELECT 칸들 FROM ops.rtms_dongdup_bak1118; (is_canceled · n_sk · 백업시각 칸은 빼고)
   load_rtms.py 도 같은 날 고침 — 앞으로는 새 줄을 넣지 않고 옛 줄을 고친다. */
SET XACT_ABORT ON;
IF OBJECT_ID('tempdb..#p') IS NOT NULL DROP TABLE #p;
SELECT o_sk = o.trade_sk, n_sk = n.trade_sk
INTO #p
FROM silver.rtms_trade o JOIN silver.rtms_trade n
  ON n.trade_kind = o.trade_kind AND n.sgg_cd = o.sgg_cd AND ISNULL(n.umd_nm,N'') = ISNULL(o.umd_nm,N'') AND ISNULL(n.deal_ymd,'') = ISNULL(o.deal_ymd,'')
 AND ISNULL(n.jibun,N'') = ISNULL(o.jibun,N'') AND ISNULL(n.bld_nm,N'') = ISNULL(o.bld_nm,N'')
 AND ISNULL(n.deal_amount,-1) = ISNULL(o.deal_amount,-1) AND ISNULL(n.deposit,-1) = ISNULL(o.deposit,-1) AND ISNULL(n.monthly_rent,-1) = ISNULL(o.monthly_rent,-1)
 AND ISNULL(n.exclu_use_ar,-1) = ISNULL(o.exclu_use_ar,-1) AND ISNULL(n.total_floor_ar,-1) = ISNULL(o.total_floor_ar,-1) AND ISNULL(n.floor_no,-9999) = ISNULL(o.floor_no,-9999)
WHERE ISNULL(o.bld_dong,'') = '' AND ISNULL(n.bld_dong,'') <> '';
-- 1:1 만
DELETE p FROM #p p WHERE p.o_sk IN (SELECT o_sk FROM #p GROUP BY o_sk HAVING COUNT(*) > 1) OR p.n_sk IN (SELECT n_sk FROM #p GROUP BY n_sk HAVING COUNT(*) > 1);
SELECT 지울줄 = COUNT(*) FROM #p;
SELECT 해제다름 = SUM(CASE WHEN ISNULL(o.cdeal_type,'') <> ISNULL(n.cdeal_type,'') THEN 1 ELSE 0 END),
       단지다름 = SUM(CASE WHEN ISNULL(o.match_complex_id,-1) <> ISNULL(n.match_complex_id,-1) THEN 1 ELSE 0 END),
       옛줄만단지 = SUM(CASE WHEN o.match_complex_id IS NOT NULL AND n.match_complex_id IS NULL THEN 1 ELSE 0 END)
FROM #p p JOIN silver.rtms_trade o ON o.trade_sk = p.o_sk JOIN silver.rtms_trade n ON n.trade_sk = p.n_sk;

BEGIN TRAN;
IF OBJECT_ID('ops.rtms_dongdup_bak1118') IS NULL
    SELECT o.*, n_sk = p.n_sk, 백업시각 = SYSDATETIME() INTO ops.rtms_dongdup_bak1118
    FROM #p p JOIN silver.rtms_trade o ON o.trade_sk = p.o_sk;
ELSE
    INSERT ops.rtms_dongdup_bak1118 SELECT o.*, p.n_sk, SYSDATETIME() FROM #p p JOIN silver.rtms_trade o ON o.trade_sk = p.o_sk
    WHERE NOT EXISTS (SELECT 1 FROM ops.rtms_dongdup_bak1118 b WHERE b.trade_sk = o.trade_sk);
DELETE o FROM silver.rtms_trade o JOIN #p p ON p.o_sk = o.trade_sk
WHERE EXISTS (SELECT 1 FROM ops.rtms_dongdup_bak1118 b WHERE b.trade_sk = o.trade_sk);
SELECT 지움 = @@ROWCOUNT;
COMMIT;
SELECT 백업줄 = COUNT(*), 단지수 = COUNT(DISTINCT match_complex_id) FROM ops.rtms_dongdup_bak1118;
