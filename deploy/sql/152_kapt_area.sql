/* 152. K-apt 면적으로 공급면적을 역산할 수 있나 (2026-10-18) — 읽기 전용
   ★ 가설: 관리비부과면적(kapt_marea) 은 **공급면적 기준**으로 부과된다.
     맞다면 priv_area / kapt_marea 가 65~81% 범위에 들어온다.
     계약면적 기준이면 45% 근처로 떨어진다.
   ★ 이건 확인이지 주장이 아니다. 숫자가 말하게 둔다. */
SET NOCOUNT ON;

PRINT '--- A. 분포 (아파트, 면적 둘 다 있는 단지) ---';
WITH k AS (
  SELECT kapt_code, kapt_name, ho_cnt, priv_area, kapt_marea, kapt_tarea,
         r = priv_area / NULLIF(kapt_marea, 0)
    FROM silver.kapt_complex
   WHERE is_current = 1 AND code_apt_nm = N'아파트'
     AND priv_area > 0 AND kapt_marea > 0
)
SELECT 단지수 = COUNT(*),
       평균 = CAST(AVG(r) * 100 AS DECIMAL(5,1)),
       최소 = CAST(MIN(r) * 100 AS DECIMAL(5,1)),
       최대 = CAST(MAX(r) * 100 AS DECIMAL(5,1)),
       [40%미만] = SUM(CASE WHEN r < 0.40 THEN 1 ELSE 0 END),
       [40_50]   = SUM(CASE WHEN r >= 0.40 AND r < 0.50 THEN 1 ELSE 0 END),
       [50_60]   = SUM(CASE WHEN r >= 0.50 AND r < 0.60 THEN 1 ELSE 0 END),
       [60_70]   = SUM(CASE WHEN r >= 0.60 AND r < 0.70 THEN 1 ELSE 0 END),
       [70_85]   = SUM(CASE WHEN r >= 0.70 AND r < 0.85 THEN 1 ELSE 0 END),
       [85이상]  = SUM(CASE WHEN r >= 0.85 THEN 1 ELSE 0 END)
  FROM k;

PRINT '';
PRINT '--- B. 래미안 장위 등 아는 단지로 대조 ---';
SELECT TOP 12 k.kapt_name, 세대 = k.ho_cnt,
       전용합 = CAST(k.priv_area AS DECIMAL(12,1)),
       관리비부과 = CAST(k.kapt_marea AS DECIMAL(12,1)),
       연면적 = CAST(k.kapt_tarea AS DECIMAL(12,1)),
       [전용/관리비] = CAST(k.priv_area / NULLIF(k.kapt_marea,0) * 100 AS DECIMAL(5,1)),
       [전용/연면적] = CAST(k.priv_area / NULLIF(k.kapt_tarea,0) * 100 AS DECIMAL(5,1)),
       세대당전용 = CAST(k.priv_area / NULLIF(k.ho_cnt,0) AS DECIMAL(8,2)),
       세대당부과 = CAST(k.kapt_marea / NULLIF(k.ho_cnt,0) AS DECIMAL(8,2))
  FROM silver.kapt_complex k
 WHERE k.is_current = 1
   AND (k.kapt_name LIKE N'%래미안%장위%' OR k.kapt_name LIKE N'%장위%'
     OR k.kapt_name LIKE N'%백련산%' OR k.kapt_name LIKE N'%센트레빌%아스테리움%')
 ORDER BY k.ho_cnt DESC;

PRINT '';
PRINT '--- C. 커버리지: 우리 단지 중 K-apt 가 붙고 면적이 있는 비율 ---';
SELECT 총괄단지 = COUNT(*),
       kapt연결 = SUM(CASE WHEN vk.kapt_code IS NOT NULL THEN 1 ELSE 0 END),
       면적있음 = SUM(CASE WHEN k.priv_area > 0 AND k.kapt_marea > 0 THEN 1 ELSE 0 END)
  FROM gold.complex c
  LEFT JOIN gold.v_complex_kapt vk ON vk.complex_id = c.complex_id
  LEFT JOIN silver.kapt_complex k ON k.kapt_code = vk.kapt_code AND k.is_current = 1
 WHERE c.is_active = 1 AND c.has_recap = 1;
