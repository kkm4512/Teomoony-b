/* 281. silver.kapt_complex.subway_line · subway_station 을 넓힌다 (2026-10-21 QA)
   ★ 왜: z-kapt-bg(16:56)가 3분 만에 죽었다 — 어느 단지의 subway_line 이 80자를 넘었다
     ('1호선, 1호선, 1호선, 1호선, 2호선, 2호선, 3호선, 4호선, 부산-김해경전철, …' — 원본이 그렇게 온다).
     원본을 자르지 않는다(정책: 원본을 훼손하지 않는다) — 칸을 넓힌다. NVARCHAR 늘리기는 메타데이터만 바뀐다.
   ★ 다시 돌려도 된다. */
IF COL_LENGTH('silver.kapt_complex', 'subway_line') < 2000
    ALTER TABLE silver.kapt_complex ALTER COLUMN subway_line NVARCHAR(1000) NULL;
GO
IF COL_LENGTH('silver.kapt_complex', 'subway_station') < 2000
    ALTER TABLE silver.kapt_complex ALTER COLUMN subway_station NVARCHAR(1000) NULL;
GO
SELECT subway_line = COL_LENGTH('silver.kapt_complex', 'subway_line') / 2,
       subway_station = COL_LENGTH('silver.kapt_complex', 'subway_station') / 2;
