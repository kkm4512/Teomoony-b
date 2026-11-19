/* 11-18 밤 다시 받기로 들어온 줄이 정말 '같은 키 k 번째' 인지(키 칸이 같은 쌍둥이가 있나) — 읽기만 */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#n') IS NOT NULL DROP TABLE #n;
SELECT trade_sk, trade_kind, sgg_cd, umd_nm, jibun, bld_nm, bld_dong, deal_ymd, deal_amount, deposit, monthly_rent, exclu_use_ar, total_floor_ar, floor_no
INTO #n FROM silver.rtms_trade WHERE loaded_at >= '2026-11-19 04:01:00' AND loaded_at < '2026-11-19 05:44:00';
SELECT 새줄 = (SELECT COUNT(*) FROM #n),
       쌍둥이있음 = COUNT(DISTINCT n.trade_sk)
FROM #n n JOIN silver.rtms_trade o ON o.trade_sk <> n.trade_sk AND o.trade_kind = n.trade_kind AND o.sgg_cd = n.sgg_cd
            AND ISNULL(o.umd_nm,N'') = ISNULL(n.umd_nm,N'') AND ISNULL(o.deal_ymd,'') = ISNULL(n.deal_ymd,'') AND ISNULL(o.jibun,N'') = ISNULL(n.jibun,N'')
            AND ISNULL(o.bld_nm,N'') = ISNULL(n.bld_nm,N'') AND ISNULL(o.bld_dong,N'') = ISNULL(n.bld_dong,N'')
            AND ISNULL(o.deal_amount,-1) = ISNULL(n.deal_amount,-1) AND ISNULL(o.deposit,-1) = ISNULL(n.deposit,-1) AND ISNULL(o.monthly_rent,-1) = ISNULL(n.monthly_rent,-1)
            AND ISNULL(o.exclu_use_ar,-1) = ISNULL(n.exclu_use_ar,-1) AND ISNULL(o.total_floor_ar,-1) = ISNULL(n.total_floor_ar,-1) AND ISNULL(o.floor_no,-9999) = ISNULL(n.floor_no,-9999);
