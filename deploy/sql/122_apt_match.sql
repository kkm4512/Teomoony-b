/* ============================================================
   122_apt_match : 청약홈 공고를 우리 단지에 **코드로** 이을 수 있나 (읽기 전용)
                   2026-10-18

   청약홈은 법정동코드도 PNU 도 주지 않는다. 주는 것은 `HSSPLY_ADRES`
   주소 문자열 하나뿐이다(CONTEXT 11-19). 그래서 **잇기 전에 잇힐지를 잰다.**

   ★ 파싱은 VM 에서 끝내고 결과만 아래에 박아 둔다. 조각(법정동명/본번/부번)만
     가져오고 **PNU 조립은 meta.fn_make_pnu 안에서만** 한다(정책.md 1장).
     법정동명 -> 코드 해석도 SQL 에서 한다 - 실거래가 쓰는 예외 #1 과 같은 길이다.
   ★ 못 뽑은 주소는 NULL 로 들어 있다(도로명만 있는 2건). 추측하지 않는다.
   ★ 이 파일은 **아무것도 안 바꾼다.** 숫자를 보고 축을 올릴지 정하는 용도다.
   ============================================================ */
USE Teomoony;
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID('tempdb..#apt') IS NOT NULL DROP TABLE #apt;
CREATE TABLE #apt (
  house_no   NVARCHAR(20), pblanc_no NVARCHAR(20),
  house_nm   NVARCHAR(100), pblanc_de NVARCHAR(10),
  sgg_nm     NVARCHAR(20), emd_nm NVARCHAR(30),
  san        NVARCHAR(1),  bun NVARCHAR(10), ji NVARCHAR(10));

INSERT INTO #apt (house_no,pblanc_no,house_nm,pblanc_de,sgg_nm,emd_nm,san,bun,ji) VALUES
  (N'2020000807',N'2020000807',N'길음역 롯데캐슬 트윈골드',N'2020-07-03',N'성북구',N'길음동',N'0',N'542',N'1'),
  (N'2020000942',N'2020000942',N'DMC아트포레자이',N'2020-08-03',N'은평구',N'수색동',N'0',N'189',N'0'),
  (N'2020000928',N'2020000928',N'DMC센트럴자이',N'2020-08-03',N'은평구',N'증산동',N'0',N'213',N'20'),
  (N'2020000926',N'2020000926',N'DMC파인시티자이',N'2020-08-03',N'은평구',N'수색동',N'0',N'115',N'5'),
  (N'2020000899',N'2020000899',N'DMC SK VIEW 아이파크포레',N'2020-08-03',N'은평구',NULL,N'0',NULL,N'0'),
  (N'2021000336',N'2021000336',N'에비뉴 청계 I',N'2021-05-14',N'종로구',NULL,N'0',NULL,N'0'),
  (N'2021000422',N'2021000422',N'에비뉴 청계 II',N'2021-07-15',N'종로구',N'숭인동',N'0',N'1420',N'0'),
  (N'2021000891',N'2021000891',N'해링턴플레이스 안암',N'2021-11-25',N'성북구',N'안암동',N'0',N'132',N'17'),
  (N'2022000835',N'2022000835',N'장위자이 레디언트',N'2022-11-25',N'성북구',N'장위동',N'0',N'62',N'1'),
  (N'2023000052',N'2023000052',N'센트레빌 아스테리움 시그니처',N'2023-02-27',N'은평구',N'역촌동',N'0',N'189',N'1'),
  (N'2023000174',N'2023000174',N'새절역 두산위브 트레지움',N'2023-05-03',N'은평구',N'신사동',N'0',N'170',N'12'),
  (N'2023000457',N'2023000457',N'보문 센트럴 아이파크',N'2023-09-15',N'성북구',N'보문동1가',N'0',N'196',N'11'),
  (N'2024000284',N'2024000284',N'푸르지오 라디우스 파크',N'2024-07-05',N'성북구',N'장위동',N'0',N'25',N'55'),
  (N'2024000471',N'2024000471',N'연신내 양우내안애 퍼스티지',N'2024-08-30',N'은평구',N'갈현동',N'0',N'467',N'1'),
  (N'2024000692',N'2024000692',N'창경궁 롯데캐슬 시그니처',N'2024-11-28',N'성북구',N'삼선동2가',N'0',N'296',N'0'),
  (N'2025000177',N'2025000177',N'힐스테이트 메디알레',N'2025-05-09',N'은평구',N'대조동',N'0',N'88',N'0'),
  (N'2026000275',N'2026000275',N'장위 푸르지오 마크원',N'2026-06-19',N'성북구',N'장위동',N'0',N'68',N'37'),
  (N'2026000399',N'2026000399',N'브라운스톤 월곡 센트럴',N'2026-08-28',N'성북구',N'하월곡동',N'0',N'70',N'4');
GO

PRINT '--- 1. 법정동명이 코드로 풀리나 (시군구 안에서) ---';
/* 서울 = sido_cd 11. 시군구명으로 좁힌 뒤 법정동명으로 찾는다.
   리(ri)가 있는 행은 제외한다 - 서울엔 리가 없다. */
SELECT a.house_no, a.house_nm, a.sgg_nm, a.emd_nm,
       lawd_cd = l.lawd_cd,
       판정 = CASE WHEN a.emd_nm IS NULL THEN N'주소에 지번 없음(도로명만)'
                   WHEN l.lawd_cd IS NULL THEN N'법정동명 못 찾음'
                   ELSE N'OK' END
  FROM #apt a
  LEFT JOIN meta.lawd_code l
         ON l.sgg_nm = a.sgg_nm AND l.emd_nm = a.emd_nm
        AND ISNULL(l.ri_nm,N'') = N'' AND l.is_abolished = 0
        AND LEFT(l.lawd_cd,2) = '11'
 ORDER BY a.pblanc_de;
GO

PRINT '--- 2. ★ 그 PNU 가 우리에게 있나 ---';
WITH m AS (
  SELECT a.*, l.lawd_cd,
         pnu = meta.fn_make_pnu(LEFT(l.lawd_cd,5), RIGHT(l.lawd_cd,5),
                                CASE a.san WHEN N'1' THEN '1' ELSE '0' END, a.bun, a.ji)
    FROM #apt a
    LEFT JOIN meta.lawd_code l
           ON l.sgg_nm = a.sgg_nm AND l.emd_nm = a.emd_nm
          AND ISNULL(l.ri_nm,N'') = N'' AND l.is_abolished = 0
          AND LEFT(l.lawd_cd,2) = '11')
SELECT m.house_no, 공고명 = m.house_nm, m.pblanc_de, m.pnu,
       대장단지 = (SELECT TOP 1 c.complex_nm FROM gold.complex_pnu cp
                    JOIN gold.complex c ON c.complex_id = cp.complex_id
                   WHERE cp.pnu = m.pnu),
       신축단지 = (SELECT TOP 1 n.kapt_name FROM gold.v_newbuild n WHERE n.pnu = m.pnu),
       법정동적재 = CASE WHEN m.lawd_cd IS NULL THEN N'-'
                        WHEN EXISTS (SELECT 1 FROM meta.v_lawd_scope s
                                      WHERE s.lawd_cd = m.lawd_cd) THEN N'Y' ELSE N'N' END,
       판정 = CASE
         WHEN m.pnu IS NULL THEN N'PNU 못 만듦'
         WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = m.pnu) THEN N'대장 단지에 붙음'
         WHEN EXISTS (SELECT 1 FROM gold.v_newbuild n WHERE n.pnu = m.pnu)   THEN N'신축(대장전)에 붙음'
         WHEN NOT EXISTS (SELECT 1 FROM meta.v_lawd_scope s WHERE s.lawd_cd = m.lawd_cd)
              THEN N'그 법정동을 아직 안 봤다(SCOPE)'
         ELSE N'적재했는데 그 PNU 가 없다 - 합필 전 지번 의심' END
  FROM m ORDER BY m.pblanc_de;
GO

PRINT '--- 3. 요약 ---';
WITH m AS (
  SELECT a.*, l.lawd_cd,
         pnu = meta.fn_make_pnu(LEFT(l.lawd_cd,5), RIGHT(l.lawd_cd,5),
                                CASE a.san WHEN N'1' THEN '1' ELSE '0' END, a.bun, a.ji)
    FROM #apt a
    LEFT JOIN meta.lawd_code l
           ON l.sgg_nm = a.sgg_nm AND l.emd_nm = a.emd_nm
          AND ISNULL(l.ri_nm,N'') = N'' AND l.is_abolished = 0
          AND LEFT(l.lawd_cd,2) = '11')
SELECT 판정 = CASE
         WHEN m.pnu IS NULL THEN N'PNU 못 만듦'
         WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = m.pnu) THEN N'대장 단지에 붙음'
         WHEN EXISTS (SELECT 1 FROM gold.v_newbuild n WHERE n.pnu = m.pnu)   THEN N'신축(대장전)에 붙음'
         WHEN NOT EXISTS (SELECT 1 FROM meta.v_lawd_scope s WHERE s.lawd_cd = m.lawd_cd)
              THEN N'그 법정동을 아직 안 봤다(SCOPE)'
         ELSE N'적재했는데 그 PNU 가 없다' END,
       건수 = COUNT(*)
  FROM m GROUP BY CASE
         WHEN m.pnu IS NULL THEN N'PNU 못 만듦'
         WHEN EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.pnu = m.pnu) THEN N'대장 단지에 붙음'
         WHEN EXISTS (SELECT 1 FROM gold.v_newbuild n WHERE n.pnu = m.pnu)   THEN N'신축(대장전)에 붙음'
         WHEN NOT EXISTS (SELECT 1 FROM meta.v_lawd_scope s WHERE s.lawd_cd = m.lawd_cd)
              THEN N'그 법정동을 아직 안 봤다(SCOPE)'
         ELSE N'적재했는데 그 PNU 가 없다' END
 ORDER BY 건수 DESC;
GO
