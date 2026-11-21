/* 424 (2026-11-21 · DQM ③ 보완 실행 · 사장님 "알람은 제외하고 일단 진행해봐")
   R17 '단지에 안 이어짐'(서울 · 단지종류) 줄에 **이을 수 있는 단지 후보**를 공식 코드로 찾아 ops.dqm_bowan 에 적는다.
   ★ 원본 칸(silver.rtms_trade.match_complex_id)은 덮지 않는다(결정 5: 보완 = 별도 칸 + 출처). 화면 반영은 결과를 보고 따로 정한다.
   열쇠(원천이 준 공식 코드 — 같은 열쇠를 가진 **이미 이어진** 줄이 모두 한 단지일 때만 후보):
     ① apt_seq(국토부 단지 일련번호)  ② 도로명코드 + 건물 본번 · 부번  ③ 시군구 + 법정동 + 지번(가려지지 않은 것)
   열쇠 둘 이상이 서로 다른 단지를 가리키면(엇갈림) 후보로 안 적는다. 이름같음 = 원천 건물이름과 단지 이름(공백 · 괄호 뺀 것)이 한쪽이 다른 쪽을 품음.
   ★ 11-21 첫 실측: 열쇠로 찾은 후보 3만 줄의 대부분은 **재건축 전 옛 건물의 거래**였다(주공2 → 래미안블레스티지 같은 자리 · 같은 도로명).
     그대로 이으면 옛 아파트 값이 새 단지 시세에 섞인다. 그래서 확실 = 연식같음(원천 건축년도가 단지 사용승인 연도 ±1 안) 이고
     이름같음 이거나 단지 이름이 주소뿐(대장에 이름 없는 단지 · 예 '반포동 901번지' = 1974 반포주공1단지)인 줄만.
     (연식만 같고 이름이 다른 '한양 → 반포 래미안아이파크' 같은 것은 단지 기록에 옛 동이 섞인 것이라 뺀다.)
   매일 규칙 run · apply 뒤에 다시 만든다(zq-dqm-rules-par). */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('ops.dqm_bowan') IS NULL
    CREATE TABLE ops.dqm_bowan (trade_sk BIGINT NOT NULL PRIMARY KEY, trade_kind VARCHAR(20), cand_complex_id INT NOT NULL,
        근거 VARCHAR(40) NOT NULL, 근거줄 INT NULL, 이름같음 BIT NULL, 연식같음 BIT NULL, 확실 BIT NULL, bld_nm NVARCHAR(200) NULL, complex_nm NVARCHAR(200) NULL, 만든때 DATETIME2 DEFAULT SYSDATETIME());
IF COL_LENGTH('ops.dqm_bowan', '확실') IS NULL ALTER TABLE ops.dqm_bowan ADD 연식같음 BIT NULL, 확실 BIT NULL;
IF OBJECT_ID('ops.dqm_bowan_stat') IS NULL
    CREATE TABLE ops.dqm_bowan_stat (만든때 DATETIME2 DEFAULT SYSDATETIME(), trade_kind VARCHAR(20), 안이어짐 INT, 후보 INT, 이름같음 INT, 엇갈림 INT, 열쇠없음 INT, 확실 INT NULL);
IF COL_LENGTH('ops.dqm_bowan_stat', '확실') IS NULL ALTER TABLE ops.dqm_bowan_stat ADD 확실 INT NULL;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
IF OBJECT_ID('tempdb..#u') IS NOT NULL DROP TABLE #u;
SELECT trade_sk, trade_kind, sgg_cd, umd_nm, jibun, jibun_masked, bld_nm, apt_seq, road_cd, road_bonbun, road_bubun, build_year
  INTO #u FROM silver.rtms_trade
 WHERE match_complex_id IS NULL AND trade_kind IN ('APT_TRADE_DEV','APT_RENT','RH_TRADE','RH_RENT','OFFI_TRADE','OFFI_RENT') AND sgg_cd LIKE '11%';
IF OBJECT_ID('tempdb..#ks') IS NOT NULL DROP TABLE #ks;
SELECT apt_seq, n = COUNT(DISTINCT match_complex_id), cid = MIN(match_complex_id), m = COUNT(*) INTO #ks
  FROM silver.rtms_trade WHERE apt_seq IS NOT NULL AND match_complex_id IS NOT NULL AND sgg_cd LIKE '11%' GROUP BY apt_seq;
IF OBJECT_ID('tempdb..#kr') IS NOT NULL DROP TABLE #kr;
SELECT road_cd, road_bonbun, rb = ISNULL(road_bubun, '0'), n = COUNT(DISTINCT match_complex_id), cid = MIN(match_complex_id), m = COUNT(*) INTO #kr
  FROM silver.rtms_trade WHERE road_cd IS NOT NULL AND road_bonbun IS NOT NULL AND match_complex_id IS NOT NULL AND sgg_cd LIKE '11%'
 GROUP BY road_cd, road_bonbun, ISNULL(road_bubun, '0');
IF OBJECT_ID('tempdb..#kj') IS NOT NULL DROP TABLE #kj;
SELECT sgg_cd, umd_nm, jibun, n = COUNT(DISTINCT match_complex_id), cid = MIN(match_complex_id), m = COUNT(*) INTO #kj
  FROM silver.rtms_trade WHERE ISNULL(jibun_masked, 0) = 0 AND jibun IS NOT NULL AND match_complex_id IS NOT NULL AND sgg_cd LIKE '11%'
 GROUP BY sgg_cd, umd_nm, jibun;
IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;
SELECT u.trade_sk, u.trade_kind, u.bld_nm, u.build_year,
       s1 = CASE WHEN s.n = 1 THEN s.cid END, s1m = s.m, r1 = CASE WHEN r.n = 1 THEN r.cid END, r1m = r.m, j1 = CASE WHEN j.n = 1 THEN j.cid END, j1m = j.m,
       여럿 = CASE WHEN s.n > 1 OR r.n > 1 OR j.n > 1 THEN 1 ELSE 0 END
  INTO #c FROM #u u
  LEFT JOIN #ks s ON s.apt_seq = u.apt_seq
  LEFT JOIN #kr r ON r.road_cd = u.road_cd AND r.road_bonbun = u.road_bonbun AND r.rb = ISNULL(u.road_bubun, '0')
  LEFT JOIN #kj j ON j.sgg_cd = u.sgg_cd AND j.umd_nm = u.umd_nm AND j.jibun = u.jibun AND ISNULL(u.jibun_masked, 0) = 0;
IF OBJECT_ID('tempdb..#d') IS NOT NULL DROP TABLE #d;
SELECT c.*, cid = COALESCE(s1, r1, j1),
       엇갈림 = CASE WHEN (s1 IS NOT NULL AND r1 IS NOT NULL AND s1 <> r1) OR (s1 IS NOT NULL AND j1 IS NOT NULL AND s1 <> j1) OR (r1 IS NOT NULL AND j1 IS NOT NULL AND r1 <> j1) OR 여럿 = 1 THEN 1 ELSE 0 END,
       근거 = CONCAT_WS('+', CASE WHEN s1 IS NOT NULL THEN 'apt_seq' END, CASE WHEN r1 IS NOT NULL THEN '도로명' END, CASE WHEN j1 IS NOT NULL THEN '지번' END),
       근거줄 = COALESCE(s1m, r1m, j1m)
  INTO #d FROM #c c;
BEGIN TRAN;
TRUNCATE TABLE ops.dqm_bowan;
INSERT ops.dqm_bowan (trade_sk, trade_kind, cand_complex_id, 근거, 근거줄, 이름같음, 연식같음, bld_nm, complex_nm)
SELECT d.trade_sk, d.trade_kind, d.cid, d.근거, d.근거줄,
       CASE WHEN g.complex_nm IS NULL OR d.bld_nm IS NULL THEN NULL
            WHEN CHARINDEX(x.a, x.b) > 0 OR CHARINDEX(x.b, x.a) > 0 THEN 1 ELSE 0 END,
       CASE WHEN TRY_CAST(d.build_year AS INT) IS NULL OR TRY_CAST(LEFT(g.oldest_use_apr, 4) AS INT) IS NULL THEN NULL
            WHEN TRY_CAST(d.build_year AS INT) BETWEEN TRY_CAST(LEFT(g.oldest_use_apr, 4) AS INT) - 1
                                                   AND ISNULL(TRY_CAST(LEFT(g.latest_use_apr, 4) AS INT), TRY_CAST(LEFT(g.oldest_use_apr, 4) AS INT)) + 1 THEN 1 ELSE 0 END,
       d.bld_nm, g.complex_nm
  FROM #d d LEFT JOIN gold.complex g ON g.complex_id = d.cid
  CROSS APPLY (SELECT a = REPLACE(REPLACE(REPLACE(ISNULL(d.bld_nm, N''), N' ', N''), N'(', N''), N')', N''),
                      b = REPLACE(REPLACE(REPLACE(ISNULL(g.complex_nm, N''), N' ', N''), N'(', N''), N')', N'')) x
 WHERE d.cid IS NOT NULL AND d.엇갈림 = 0 AND LEN(x.a) > 0 AND LEN(x.b) > 0 OR (d.cid IS NOT NULL AND d.엇갈림 = 0 AND (d.bld_nm IS NULL OR g.complex_nm IS NULL));
UPDATE ops.dqm_bowan SET 확실 = CASE WHEN 연식같음 = 1 AND (이름같음 = 1 OR complex_nm LIKE N'%번지') THEN 1 ELSE 0 END;
INSERT ops.dqm_bowan_stat (trade_kind, 안이어짐, 후보, 이름같음, 엇갈림, 열쇠없음, 확실)
SELECT d.trade_kind, COUNT(*), SUM(CASE WHEN b.trade_sk IS NOT NULL THEN 1 ELSE 0 END), SUM(CASE WHEN b.이름같음 = 1 THEN 1 ELSE 0 END),
       SUM(CASE WHEN d.cid IS NOT NULL AND d.엇갈림 = 1 THEN 1 ELSE 0 END), SUM(CASE WHEN d.cid IS NULL AND d.여럿 = 0 THEN 1 ELSE 0 END), SUM(CASE WHEN b.확실 = 1 THEN 1 ELSE 0 END)
  FROM #d d LEFT JOIN ops.dqm_bowan b ON b.trade_sk = d.trade_sk GROUP BY d.trade_kind;
COMMIT;
SELECT trade_kind, 안이어짐, 후보, 이름같음, 확실, 엇갈림, 열쇠없음 FROM ops.dqm_bowan_stat WHERE 만든때 = (SELECT MAX(만든때) FROM ops.dqm_bowan_stat) ORDER BY 안이어짐 DESC;
SELECT 근거, 줄 = COUNT(*), 이름같음 = SUM(CASE WHEN 이름같음 = 1 THEN 1 ELSE 0 END), 이름다름 = SUM(CASE WHEN 이름같음 = 0 THEN 1 ELSE 0 END) FROM ops.dqm_bowan GROUP BY 근거 ORDER BY 2 DESC;
SELECT 연식 = CASE 연식같음 WHEN 1 THEN '같음' WHEN 0 THEN '다름' ELSE '모름' END, 이름 = CASE 이름같음 WHEN 1 THEN '같음' WHEN 0 THEN '다름' ELSE '모름' END, 줄 = COUNT(*)
  FROM ops.dqm_bowan GROUP BY 연식같음, 이름같음 ORDER BY 3 DESC;
SELECT TOP 12 b.trade_kind, b.근거, b.bld_nm, b.complex_nm, t.build_year, g.oldest_use_apr, b.근거줄 FROM ops.dqm_bowan b
  JOIN silver.rtms_trade t ON t.trade_sk = b.trade_sk JOIN gold.complex g ON g.complex_id = b.cand_complex_id WHERE b.확실 = 1 ORDER BY NEWID();
SELECT TOP 6 b.trade_kind, b.근거, b.bld_nm, b.complex_nm, t.build_year, g.oldest_use_apr FROM ops.dqm_bowan b
  JOIN silver.rtms_trade t ON t.trade_sk = b.trade_sk JOIN gold.complex g ON g.complex_id = b.cand_complex_id WHERE b.이름같음 = 0 AND b.연식같음 = 1 ORDER BY NEWID();
