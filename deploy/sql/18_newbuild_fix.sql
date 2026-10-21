SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   18_newbuild_fix : v_newbuild 의 기준을 뒤집는다

   ★ 17 번이 틀렸다
     "K-apt 에 있는데 그 PNU 에 표제부가 0" 을 신축으로 봤다.
     **K-apt 의 PNU 를 못 믿는다**(4-22 ②, 정책.md 3-7)는 걸 알면서도
     그걸 축의 기준으로 삼았다. 결과:

       꿈의숲아이파크   2022년 준공, 같은 동에 대장 34건   -> 신축으로 분류됨
       보문파크뷰자이   2017년 준공, 같은 동에 대장 32건   -> 신축으로 분류됨
       동아에코빌      2003년 준공, 같은 동에 대장 37건   -> 신축으로 분류됨

     11건 중 9건이 가짜였다. **못 믿을 키를 기준으로 삼으면 목록 전체가 흔들린다.**

   ★ 기준을 바꾼다
     확실히 아는 것은 **"실거래가 붙을 데가 없다"** 이다.
     거래의 PNU 는 믿을 수 있다 — 보문파크뷰자이에서 실거래 458 · 대장 458 로
     정확히 맞는 것을 확인했다. K-apt 는 **그 PNU 에 이름과 세대수를 붙이는
     보조**로만 쓴다.

         기준:  gold.v_newbuild_gap 의 상태 = 'NO_BLD'   (미매칭 거래가 있는 PNU)
         보조:  silver.kapt_complex 를 그 PNU 로 조인

     거래가 0 인 K-apt 단지는 빠진다. 거래도 대장도 없으면 보여줄 이유가 없고,
     틀린 것을 보여주느니 안 보여주는 편이 낫다.

   ★ 이름 매칭은 판정에 쓰지 않는다
     제외 조건으로 써보려 했으나 양쪽으로 다 틀렸다:
       래미안퍼스트하이(K-apt)  vs  래미안 장위 퍼스트하이(대장)  -> 못 찾음
       길음역 롯데캐슬          같은 이름 대장 5건이나 거래는 미매칭
     `동일명대장` 컬럼으로 **드러내기만** 한다. 판정은 PNU 로만 한다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('gold.v_newbuild') IS NOT NULL DROP VIEW gold.v_newbuild;
GO
CREATE VIEW gold.v_newbuild
AS
SELECT k.kapt_code,
       k.kapt_name,
       g.pnu,
       k.bjd_code,
       lawd_nm      = l.emd_nm,
       k.kapt_addr,
       k.doro_juso,
       세대          = k.ho_cnt,
       동수          = k.dong_cnt,
       사용승인       = k.kapt_usedate,
       k.top_floor,
       난방          = k.code_heat_nm,
       시공          = k.bcompany,
       시행          = k.acompany,
       거래          = g.거래,
       최근거래       = t.last_ymd,
       최고가         = t.max_amount,
       centroid_lat = p.centroid_lat,
       centroid_lng = p.centroid_lng,
       인허가         = g.인허가,
       /* 참고용. 판정에 쓰지 않는다 — 문자열 매칭이라 양쪽으로 틀린다.
          0 보다 크면 "같은 법정동에 비슷한 이름의 대장이 있다" 는 뜻이고,
          그 단지는 다른 지번으로 이미 시스템에 있을 수 있다. */
       동일명대장 = (
           SELECT COUNT(*) FROM silver.bld_basis_outline b
            WHERE b.is_current = 1
              AND b.sigungu_cd + b.bjdong_cd = k.bjd_code
              AND b.regstr_kind_cd IN ('1','2','3')
              AND REPLACE(b.bld_nm, ' ', '')
                  LIKE '%' + REPLACE(REPLACE(k.kapt_name, '아파트', ''), ' ', '') + '%')
FROM gold.v_newbuild_gap g
JOIN silver.kapt_complex k ON k.pnu = g.pnu AND k.is_current = 1
LEFT JOIN meta.lawd_code l ON l.lawd_cd = k.bjd_code
OUTER APPLY (
    SELECT TOP 1 centroid_lat, centroid_lng
    FROM silver.cadastral_parcel cp
    WHERE cp.is_current = 1 AND cp.pnu = g.pnu AND cp.centroid_lat IS NOT NULL
    ORDER BY cp.pnu
) p
OUTER APPLY (
    SELECT last_ymd   = MAX(CASE WHEN r.is_canceled = 0 THEN r.deal_ymd END),
           max_amount = MAX(CASE WHEN r.is_canceled = 0 AND r.is_rent = 0
                                 THEN r.deal_amount END)
    FROM silver.rtms_trade r
    WHERE r.match_pnu = g.pnu AND r.match_complex_id IS NULL
) t
WHERE g.상태 = 'NO_BLD';
GO
