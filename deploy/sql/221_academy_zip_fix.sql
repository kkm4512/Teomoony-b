/* ============================================================
   221_academy_zip_fix : silver.academy 의 zip_no 를 넓힌다 (2026-10-20)

   ★ academy-bg 첫 실행이 여기서 터졌다:
     "String or binary data would be truncated ... column 'zip_no'.
      Truncated value: '13551'"  (잘린 결과를 보여주는 메시지다. 원본은 6자리)

   ★ 원인을 **전수로** 확인했다(NEIS 서울 B10 + 경기 J10 = 64,769건):
       zip_no  5자 53,205 · **6자 11,556** · 빈값 8
       6자 예: '135519'  — 2015년 이전 구 우편번호가 그대로 남아 있다.
     같이 잰 다른 고정길이 칸(estbl_ymd · reg_ymd · caa_begin_ymd · caa_end_ymd ·
     load_dtm · aca_asnum · office_cd · thcc_othbc_yn · brhs_aca_yn)은
     **전부 한도 안**이었다.
     하나 고치고 또 터지지 않게 미리 다 재 두었다.

   ★ 자르지 않는다. 칸을 넓힌다. 구 우편번호도 원본이다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA='silver' AND TABLE_NAME='academy'
              AND COLUMN_NAME='zip_no' AND CHARACTER_MAXIMUM_LENGTH < 10)
BEGIN
  ALTER TABLE silver.academy ALTER COLUMN zip_no VARCHAR(10) NULL;
  PRINT '  zip_no -> VARCHAR(10)';
END
ELSE PRINT '  zip_no 이미 충분함(또는 표가 없음)';
GO
SELECT 칸 = COLUMN_NAME, 자료형 = DATA_TYPE, 길이 = CHARACTER_MAXIMUM_LENGTH
  FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_SCHEMA='silver' AND TABLE_NAME='academy' AND COLUMN_NAME='zip_no';
GO
SELECT 지금행수 = COUNT(*) FROM silver.academy;
GO
