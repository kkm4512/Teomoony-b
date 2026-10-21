/* 160. 용도지역이 실제로 여러 개 걸친 단지 찾기 (2026-10-19) — 읽기 전용
   ★ 화면 막대가 여러 줄일 때 제대로 그려지는지 볼 표본이 필요하다. */
SET NOCOUNT ON;
WITH z AS (
  SELECT v.complex_id, v.uname, a = SUM(v.xarea)
    FROM gold.v_complex_zone v GROUP BY v.complex_id, v.uname
), r AS (
  SELECT complex_id, uname, pct = 100.0*a/SUM(a) OVER (PARTITION BY complex_id)
    FROM z
), m AS (
  SELECT complex_id, n = COUNT(*) FROM r WHERE pct >= 5 GROUP BY complex_id HAVING COUNT(*) >= 2
)
SELECT TOP 10 c.complex_id, 단지 = LEFT(c.complex_nm,24), 세대 = c.hhld_cnt_sum,
       구성 = STUFF((SELECT ', ' + r2.uname + ' ' + CAST(CAST(r2.pct AS DECIMAL(5,1)) AS VARCHAR(8)) + '%'
                       FROM r r2 WHERE r2.complex_id = m.complex_id AND r2.pct >= 5
                      ORDER BY r2.pct DESC FOR XML PATH('')), 1, 2, '')
  FROM m JOIN gold.complex c ON c.complex_id = m.complex_id
 WHERE c.has_recap = 1
 ORDER BY c.hhld_cnt_sum DESC;
