/* 발견 2 다시 세기(11-18, 읽기만): 동이 빈 옛 줄 o 와, 동만 채워지고 나머지 키 칸이 같은 새 줄 n */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 전체 = COUNT_BIG(*), 동있음 = SUM(CASE WHEN ISNULL(bld_dong,'') <> '' THEN 1 ELSE 0 END) FROM silver.rtms_trade;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#n') IS NOT NULL DROP TABLE #n;
SELECT trade_sk, trade_kind, sgg_cd, umd_nm = ISNULL(umd_nm,N''), jibun = ISNULL(jibun,N''), bld_nm = ISNULL(bld_nm,N''), deal_ymd = ISNULL(deal_ymd,''),
       a = ISNULL(deal_amount,-1), d = ISNULL(deposit,-1), m = ISNULL(monthly_rent,-1), e = ISNULL(exclu_use_ar,-1), t = ISNULL(total_floor_ar,-1), f = ISNULL(floor_no,-9999),
       rg = ISNULL(rgst_date,'')
INTO #n FROM silver.rtms_trade WHERE ISNULL(bld_dong,'') <> '';
CREATE INDEX ix ON #n (sgg_cd, umd_nm, deal_ymd);
IF OBJECT_ID('tempdb..#p') IS NOT NULL DROP TABLE #p;
SELECT o.trade_sk AS o_sk, n.trade_sk AS n_sk, o.trade_kind, o_rg = ISNULL(o.rgst_date,''), n.rg, o.is_canceled, o.match_complex_id, o.deal_ymd
INTO #p
FROM silver.rtms_trade o JOIN #n n
  ON n.sgg_cd = o.sgg_cd AND n.umd_nm = ISNULL(o.umd_nm,N'') AND n.deal_ymd = ISNULL(o.deal_ymd,'')
 AND n.trade_kind = o.trade_kind AND n.jibun = ISNULL(o.jibun,N'') AND n.bld_nm = ISNULL(o.bld_nm,N'')
 AND n.a = ISNULL(o.deal_amount,-1) AND n.d = ISNULL(o.deposit,-1) AND n.m = ISNULL(o.monthly_rent,-1)
 AND n.e = ISNULL(o.exclu_use_ar,-1) AND n.t = ISNULL(o.total_floor_ar,-1) AND n.f = ISNULL(o.floor_no,-9999)
WHERE ISNULL(o.bld_dong,'') = '';
SELECT 종류 = trade_kind, 옛줄 = COUNT(DISTINCT o_sk), 짝 = COUNT(*),
       옛1새1 = (SELECT COUNT(*) FROM (SELECT o_sk FROM #p q WHERE q.trade_kind = p.trade_kind GROUP BY o_sk HAVING COUNT(*) = 1) x),
       옛등기빈 = COUNT(DISTINCT CASE WHEN o_rg = '' THEN o_sk END),
       단지붙음 = COUNT(DISTINCT CASE WHEN match_complex_id IS NOT NULL THEN o_sk END),
       최초 = MIN(deal_ymd), 최근 = MAX(deal_ymd)
FROM #p p GROUP BY trade_kind;
SELECT 새줄이옛줄여럿과 = COUNT(*) FROM (SELECT n_sk FROM #p GROUP BY n_sk HAVING COUNT(*) > 1) x;
SELECT 연 = LEFT(deal_ymd,4), 옛줄 = COUNT(DISTINCT o_sk) FROM #p GROUP BY LEFT(deal_ymd,4) ORDER BY 1;
