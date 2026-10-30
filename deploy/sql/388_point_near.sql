/* 388 한 점(위도 · 경도) 주변 — 단지 뷰와 **같은 식**의 함수 (2026-10-30 사장님 "상권 학교는 못 붙여?" — 공사 중 건물 · 승인 아파트 상세)
   ★ gold.v_complex_poi · school · subway · bus · academy 의 정의(OBJECT_DEFINITION)를 그대로 가져와
     'FROM gold.complex c' 만 한 점짜리 줄(complex_id = 0)로 바꿔 gold.fn_pt_* 로 만든다 — 규칙(업종 묶음 · 반경 · 운영중 학교 …)을 새로 적지 않는다.
   ★ 뷰를 고치면 이 파일을 다시 돌린다(그래야 같은 식이 유지된다). 유치원 뷰는 모양이 달라 손으로 같은 식을 적었다.
   ★ on_site(이 단지 땅 위 점포)는 단지가 없으니 늘 0. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
DECLARE @v SYSNAME, @f SYSNAME, @d NVARCHAR(MAX), @i INT, @body NVARCHAR(MAX), @n INT;
DECLARE k CURSOR LOCAL FAST_FORWARD FOR
  SELECT v, f FROM (VALUES ('gold.v_complex_poi', 'gold.fn_pt_poi'), ('gold.v_complex_school', 'gold.fn_pt_school'),
                           ('gold.v_complex_subway', 'gold.fn_pt_subway'), ('gold.v_complex_bus', 'gold.fn_pt_bus'),
                           ('gold.v_complex_academy', 'gold.fn_pt_academy')) x(v, f);
OPEN k; FETCH NEXT FROM k INTO @v, @f;
WHILE @@FETCH_STATUS = 0
BEGIN
  SET @d = OBJECT_DEFINITION(OBJECT_ID(@v));
  SET @i = CHARINDEX('VIEW', @d, CHARINDEX('CREATE', @d));
  SET @body = SUBSTRING(@d, CHARINDEX('SELECT', @d, @i), LEN(@d));
  SET @n = (LEN(@body) - LEN(REPLACE(@body, 'FROM gold.complex c', ''))) / LEN('FROM gold.complex c');
  IF @n <> 1 BEGIN CLOSE k; DEALLOCATE k; RAISERROR('%s: FROM gold.complex c 가 %d 번 — 모양이 바뀌었다, 손으로 본다', 16, 1, @v, @n); RETURN; END;
  SET @body = REPLACE(@body, 'FROM gold.complex c',
      'FROM (SELECT complex_id = 0, centroid_lat = @lat, centroid_lng = @lng, is_active = CAST(1 AS BIT)) c');
  EXEC (N'CREATE OR ALTER FUNCTION ' + @f + N' (@lat FLOAT, @lng FLOAT) RETURNS TABLE AS RETURN ' + @body);
  FETCH NEXT FROM k INTO @v, @f;
END
CLOSE k; DEALLOCATE k;
GO
/* 유치원 — gold.v_complex_kinder 와 같은 식(반경 500m) */
CREATE OR ALTER FUNCTION gold.fn_pt_kinder (@lat FLOAT, @lng FLOAT) RETURNS TABLE AS RETURN
SELECT complex_id = 0,
       k.kinder_cd, k.kinder_nm, k.establish, k.addr, k.tel_no, k.oper_time,
       k.cap_cnt, k.pupil_cnt, k.class_cnt, k.pbnt_tmng,
       k.lat, lon = k.lng,
       dist_m = geography::Point(@lat, @lng, 4326).STDistance(k.geog)
  FROM silver.kindergarten k
 WHERE k.geog IS NOT NULL
   AND geography::Point(@lat, @lng, 4326).STDistance(k.geog) <= 500;
GO
SELECT 만든것 = (SELECT STRING_AGG(name, ', ') FROM sys.objects WHERE schema_id = SCHEMA_ID('gold') AND name LIKE 'fn_pt_%'),
       시험_상권 = (SELECT COUNT(*) FROM gold.fn_pt_poi(37.4739, 127.1313)),
       시험_학교 = (SELECT COUNT(*) FROM gold.fn_pt_school(37.4739, 127.1313)),
       시험_역 = (SELECT COUNT(*) FROM gold.fn_pt_subway(37.4739, 127.1313)),
       시험_버스 = (SELECT COUNT(*) FROM gold.fn_pt_bus(37.4739, 127.1313)),
       시험_학원 = (SELECT COUNT(*) FROM gold.fn_pt_academy(37.4739, 127.1313)),
       시험_유치원 = (SELECT COUNT(*) FROM gold.fn_pt_kinder(37.4739, 127.1313));
