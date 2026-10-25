/* 355 필지 본번 · 부번 칸 넓힘 (2026-10-25)
   VWorld 원본에 본번 '524목장용' 처럼 글자가 붙은 값이 있어 VARCHAR(10) 에 안 들어가 그 읍면동이 통째로 실패했다(나주 문평면).
   원본을 자르거나 고치지 않고 칸을 넓힌다. VARCHAR 길이만 늘리는 것은 표를 다시 쓰지 않는다(메타데이터만). */
SET LOCK_TIMEOUT 30000;
ALTER TABLE silver.cadastral_parcel ALTER COLUMN bonbun VARCHAR(40) NULL;
ALTER TABLE silver.cadastral_parcel ALTER COLUMN bubun  VARCHAR(40) NULL;
GO
SELECT c.name, c.max_length FROM sys.columns c WHERE c.object_id = OBJECT_ID('silver.cadastral_parcel') AND c.name IN ('bonbun', 'bubun');
GO
