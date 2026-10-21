/* ============================================================
   127_bridge : 지번이 안 되면 무엇으로 잇나 (읽기 전용)  2026-10-18

   확정된 사실: 재개발은 합필 때 **새 본번**을 받고(녹번동 281·282·283),
   그 번호는 인허가 어디에도 없다. 대지위치(getApPlatPlcInfo)는 지번을 더
   주지만 전부 합필 **전**쪽이다. 지번으로는 못 잇는다.

   그러면 합필을 **견디는** 속성으로 잇는다. 후보:
     (법정동, 세대수, 사용승인일)  - 셋 다 코드성 값이고 이름이 아니다.
   래미안 베라힐즈: 허가 1,305세대 / 단지 1,305세대. 우연인지 규칙인지를 센다.
   ★ 유일성이 핵심이다. 한 허가가 단지 둘에 걸리면 못 쓴다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

PRINT '--- 1. 대장 단지에 사용승인일이 있나 ---';
SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA='gold' AND TABLE_NAME='complex'
   AND (COLUMN_NAME LIKE '%apr%' OR COLUMN_NAME LIKE '%use%'
        OR COLUMN_NAME LIKE '%day%' OR COLUMN_NAME LIKE '%hhld%'
        OR COLUMN_NAME LIKE '%sigungu%' OR COLUMN_NAME LIKE '%bjdong%')
 ORDER BY ORDINAL_POSITION;
GO

PRINT '--- 2. 신축 허가(300세대+, 사용승인 있음) 를 (법정동+세대수) 로 단지에 대보기 ---';
SELECT a.mgm_pmsrgst_pk, 허가명 = a.bld_nm, 허가세대 = a.hhld_cnt,
       허가사용승인 = a.use_apr_day, a.sigungu_cd, a.bjdong_cd,
       후보단지수 = (SELECT COUNT(*) FROM gold.complex c
                      WHERE c.sigungu_cd = a.sigungu_cd AND c.bjdong_cd = a.bjdong_cd
                        AND c.hhld_cnt_sum = a.hhld_cnt),
       후보단지 = (SELECT TOP 1 c.complex_nm FROM gold.complex c
                    WHERE c.sigungu_cd = a.sigungu_cd AND c.bjdong_cd = a.bjdong_cd
                      AND c.hhld_cnt_sum = a.hhld_cnt)
  FROM silver.arch_permit a
 WHERE a.is_current = 1 AND a.hhld_cnt >= 300
   AND a.arch_gb_nm = N'신축' AND a.use_apr_day IS NOT NULL
 ORDER BY a.hhld_cnt DESC;
GO

PRINT '--- 3. 세대수만으로 얼마나 갈리나 (법정동 안에서) ---';
WITH a AS (SELECT DISTINCT sigungu_cd, bjdong_cd, hhld_cnt
             FROM silver.arch_permit
            WHERE is_current=1 AND hhld_cnt >= 300 AND arch_gb_nm = N'신축')
SELECT 후보단지수 = n, 허가수 = COUNT(*)
  FROM (SELECT n = (SELECT COUNT(*) FROM gold.complex c
                     WHERE c.sigungu_cd=a.sigungu_cd AND c.bjdong_cd=a.bjdong_cd
                       AND c.hhld_cnt_sum = a.hhld_cnt)
          FROM a) t
 GROUP BY n ORDER BY n;
PRINT '  후보단지수 = 1 이 많아야 쓸 만한 다리다. 0 은 세대수가 안 맞는 것이고';
PRINT '  2 이상은 갈라야 할 것이 남은 것이다(사용승인일로 더 좁힌다).';
GO
