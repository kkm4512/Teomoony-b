/* 163. 추진단계 진행도 컬럼 (2026-10-19)
   ★ 코드표에 적힌 **그 순서**에서 뽑는다 (가족 안 i/n). 이름을 보고 짐작하지 않는다.
   ★ '보류' 처럼 진행 단계가 아닌 것은 **NULL** 이다. 100% 로 두면
     "완료" 로 읽힌다 — 틀린 값보다 빈 값이 낫다(정책 1장). */
IF COL_LENGTH('silver.redev_zone','propel_pct') IS NULL
    ALTER TABLE silver.redev_zone ADD propel_pct INT NULL;
GO
IF COL_LENGTH('silver.redev_zone','propel_fam') IS NULL
    ALTER TABLE silver.redev_zone ADD propel_fam NVARCHAR(60) NULL;
GO
PRINT '163 완료';
