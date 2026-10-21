/* 화면이 잠실(524566)에 "이 단지 호에 공시가격이 없습니다" 라고 단정했다.
   scope.주택가격 은 **법정동에 hsprc 가 하나라도 있나**로 판정한다 —
   적재가 그 법정동을 **반만** 받았으면 '없다' 가 거짓이 된다.
   그래서 (1) 그 법정동 hsprc 건수 (2) 이 단지 호 중 hsprc 있는 호
   (3) 그 법정동이 아직 **덜 받은** 상태인지 를 센다. */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @lawd CHAR(10) = (SELECT sigungu_cd + bjdong_cd FROM gold.complex WHERE complex_id = 524566);
SELECT 법정동 = @lawd,
       법정동_hsprc = (SELECT COUNT(*) FROM silver.bld_hsprc WHERE is_current = 1 AND pnu LIKE @lawd + '%');
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* ★ 집계 안에 서브쿼리 금지 — SUM(CASE WHEN EXISTS(...)) 로 또 밟았다(오늘 세 번째).
   APPLY 로 **먼저 한 줄로 만든 뒤** 센다. */
SELECT 이단지_호 = COUNT(*), hsprc있는호 = SUM(x.있나)
  FROM gold.v_complex_ho h
 CROSS APPLY (SELECT 있나 = CASE WHEN MAX(t.hsprc) IS NULL THEN 0 ELSE 1 END
                FROM silver.bld_hsprc t
               WHERE t.mgm_bldrgst_pk = h.호PK AND t.is_current = 1) x
 WHERE h.complex_id = 524566;
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/* 이 법정동의 주택가격 적재가 끝났나 — meta.load_page 를 본다 */
DECLARE @lawd2 CHAR(10) = (SELECT sigungu_cd + bjdong_cd FROM gold.complex WHERE complex_id = 524566);
SELECT 상태 = ISNULL(STRING_AGG(CAST(CONCAT(p.status, ' ', p.sgg_cd, '/', p.bjdong_cd,
               ' 쪽', ISNULL(CAST(p.page AS VARCHAR(10)),'-'),
               ' 총', ISNULL(CAST(p.api_total AS VARCHAR(10)),'-')) AS NVARCHAR(MAX)), N'
'), '(load_page 에 이 법정동 주택가격 줄이 없음)')
  FROM meta.load_page p
 WHERE p.sgg_cd = LEFT(@lawd2,5) AND p.bjdong_cd = RIGHT(@lawd2,5)
   AND p.op = 'getBrHsprcInfo';
