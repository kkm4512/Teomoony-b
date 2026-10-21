/* 289 : gold.complex_kapt 의 지하철 칸도 넓힌다 (2026-10-21 20:34 z-kapt 실패)
   ★ 281 에서 silver.kapt_complex.subway_line/station 을 NVARCHAR(1000) 으로 넓혔는데, 280 이 그 전에 만든
     gold.complex_kapt(뷰 SELECT * 로 만든 표)는 **예전 폭(80자)** 그대로였다 → 재적재 맨 끝
     usp_refresh_complex_kapt 의 INSERT 가 2628(잘림)로 실패. 트랜잭션이라 표는 그대로(154) 남았다.
   ★ 파생 표라 칸 폭을 바꿔도 된다. 바꾼 뒤 다시 굳힌다. */
SET NOCOUNT ON;
GO
IF COL_LENGTH('gold.complex_kapt', N'지하철노선') < 2000 ALTER TABLE gold.complex_kapt ALTER COLUMN 지하철노선 NVARCHAR(1000) NULL;
IF COL_LENGTH('gold.complex_kapt', N'지하철') < 2000     ALTER TABLE gold.complex_kapt ALTER COLUMN 지하철 NVARCHAR(1000) NULL;
GO
EXEC gold.usp_refresh_complex_kapt;
GO
SET NOCOUNT ON;
SELECT 연결 = COUNT(*), 굳힌 = MAX(굳힌시각) FROM gold.complex_kapt;
