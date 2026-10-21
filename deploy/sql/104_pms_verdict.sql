/* ============================================================
   104_pms_verdict : 아파트 단지 인허가 0건의 정체를 가른다 (진단용 · 읽기 전용)

   103 의 5절은 '법정동엔 허가가 있는데 단지 필지엔 0' 을 쟀다.
   그 값은 두 가설에서 **똑같이 나온다** — 가르지 못한다.

     (1) 재개발·재건축은 주택법 사업계획승인 대상이라 건축인허가에 아예 없다
         -> 응암동 5,408건은 전부 단독·근생급이고, 아파트급 허가는 0건이어야 한다
     (2) 조인이 arch_permit.pnu = complex_pnu.pnu 정확일치라 합필 전 지번을 놓친다
         -> 응암동 안에 아파트급 허가가 **있는데** 단지에 안 붙어 있어야 한다

   그래서 이 파일은 '단지에 붙었나' 가 아니라 **'그런 허가가 존재하나'** 를 본다.

   ★ 4절의 이름 매칭은 이 판정에만 쓰는 probe 다. 적재·화면에 쓰지 않는다
     (정책.md 1장 — 코드로만 잇는다). 여기서 이름을 쓰는 이유는 단 하나,
     "코드로 안 붙는 것이 없어서인지 못 찾아서인지" 를 가리기 위해서다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. pnu 가 비어 있지는 않은가 (조인 자체가 가능한가) ---';
/* pnu 가 NULL 이면 어느 단지에도 못 붙는다. 그러면 (2)의 변종이다. */
SELECT 시군구 = sigungu_cd,
       전체    = COUNT(*),
       pnu있음 = SUM(CASE WHEN pnu IS NOT NULL THEN 1 ELSE 0 END),
       pnu없음 = SUM(CASE WHEN pnu IS NULL     THEN 1 ELSE 0 END)
  FROM silver.arch_permit
 WHERE is_current = 1
 GROUP BY sigungu_cd
 ORDER BY sigungu_cd;
GO

PRINT '--- 2. 판정 핵심 : 아파트급 허가가 존재하는가 ---';
/* 세대수 구간별 허가 수.
     150세대 이상이 0건이면  -> (1) 없는 게 맞다. 화면은 정직하다
     150세대 이상이 있으면   -> (2) 조인이 놓치고 있다. 화면이 거짓말 중
   장위동(11290)을 같이 띄운다. README 기준 2,370건 중 최대가 299세대였다 —
   그 패턴이 은평에서도 같은지가 (1)의 방증이다. */
SELECT 시군구 = sigungu_cd,
       허가전체     = COUNT(*),
       세대NULL     = SUM(CASE WHEN hhld_cnt IS NULL THEN 1 ELSE 0 END),
       [1~49세대]   = SUM(CASE WHEN hhld_cnt BETWEEN 1 AND 49    THEN 1 ELSE 0 END),
       [50~149]     = SUM(CASE WHEN hhld_cnt BETWEEN 50 AND 149  THEN 1 ELSE 0 END),
       [150~299]    = SUM(CASE WHEN hhld_cnt BETWEEN 150 AND 299 THEN 1 ELSE 0 END),
       [300~999]    = SUM(CASE WHEN hhld_cnt BETWEEN 300 AND 999 THEN 1 ELSE 0 END),
       [1000+]      = SUM(CASE WHEN hhld_cnt >= 1000 THEN 1 ELSE 0 END),
       최대세대     = MAX(hhld_cnt)
  FROM silver.arch_permit
 WHERE is_current = 1
 GROUP BY sigungu_cd
 ORDER BY sigungu_cd;
GO

PRINT '--- 3. 세대수 상위 20건 — 무엇이 들어와 있나 ---';
/* 단지붙음 = N 이면서 세대수가 큰 행이 보이면 그 자리가 바로 (2)의 증거다. */
SELECT TOP 20
       시군구 = a.sigungu_cd, 법정동 = a.bjdong_cd,
       허가명 = a.bld_nm,
       세대   = a.hhld_cnt, 동수 = a.main_bld_cnt,
       구분   = a.arch_gb_nm, 주용도 = a.main_purps_nm,
       허가일 = a.arch_pms_day, 사용승인 = a.use_apr_day,
       pnu    = a.pnu,
       단지붙음 = CASE WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp
                                      WHERE cp.pnu = a.pnu)
                       THEN N'Y' ELSE N'N' END
  FROM silver.arch_permit a
 WHERE a.is_current = 1
 ORDER BY a.hhld_cnt DESC;
GO

PRINT '--- 4. 이름으로 역추적 (probe 전용 — 적재·화면에 쓰지 않는다) ---';
/* 단지명 앞 3글자가 허가명에 들어 있는 행을 같은 법정동 안에서 찾는다.
   나오면 (2) 확정이고, 두 pnu 를 나란히 찍으므로 **왜 안 붙었는지**까지 보인다
   (본번이 다르면 합필, 부번만 다르면 분할, 산여부가 다르면 변환 문제). */
WITH c AS (
    SELECT complex_id, complex_nm, hhld_cnt_sum,
           lawd = sigungu_cd + bjdong_cd
      FROM gold.complex
     WHERE sigungu_cd IN ('11110','11380')
       AND hhld_cnt_sum >= 300
       AND LEN(complex_nm) >= 3
)
SELECT TOP 40
       c.complex_id, 단지 = c.complex_nm, 단지세대 = c.hhld_cnt_sum,
       허가명 = a.bld_nm, 허가세대 = a.hhld_cnt,
       구분 = a.arch_gb_nm, 허가일 = a.arch_pms_day,
       단지pnu = (SELECT TOP 1 cp.pnu FROM gold.complex_pnu cp
                   WHERE cp.complex_id = c.complex_id ORDER BY cp.pnu),
       허가pnu = a.pnu
  FROM c
  JOIN silver.arch_permit a
    ON a.is_current = 1
   AND a.pnu LIKE c.lawd + '%'
   AND a.bld_nm LIKE N'%' + LEFT(c.complex_nm, 3) + N'%'
 ORDER BY a.hhld_cnt DESC;
GO

PRINT '--- 5. 읽는 법 ---';
PRINT '  2절 [150~299]/[300+] 가 은평에서 0 이고 장위동과 같은 모양이면 -> (1) 없는 게 맞다.';
PRINT '      그러면 화면의 "허가가 없습니다" 는 정직하다. 다만 *왜* 없는지를';
PRINT '      화면이 말해야 한다 — "재개발은 주택법 대상이라 이 축에 없습니다".';
PRINT '      빈칸 사유 어휘로는 [해당 없음] 이지 [아직 적재 전] 이 아니다.';
PRINT '  3절에 세대수 큰데 단지붙음=N 이 보이거나 4절에 행이 나오면 -> (2) 조인 문제.';
PRINT '      pnu 두 개를 비교해 본번/부번/산여부 중 어디가 어긋났는지 본다.';
PRINT '  1절 pnu없음 이 많으면 -> (2)의 변종. 조인 이전에 키가 없는 것이다.';
GO
