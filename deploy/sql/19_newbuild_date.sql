SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   19_newbuild_date : 사용승인일로 "이미 등록된 단지" 를 걸러낸다

   ★ 18 번도 아직 섞여 있었다
     길음역 롯데캐슬 트윈골드(거래 128)가 신축으로 남아 있었는데, 실제로는
     **이미 단지 65535 로 등록돼 있다.**

         대장 PNU   1129013400112900000  (지번 1290)   단지 65535
         거래 PNU   1129013400105420001  (지번 542-1)
         K-apt PNU  1129013400105420001  (지번 542-1)

     한 단지가 여러 필지에 걸쳐 있고 소스마다 다른 필지를 대표로 골랐다
     (CONTEXT 4-18 의 "번지 일대"). 실거래·K-apt 는 542-1, 대장은 1290.

   ★ 거르는 신호를 이름이 아니라 **사용승인일**로 한다
     이름 매칭은 양쪽으로 틀렸다:
       래미안퍼스트하이(K-apt) vs 래미안 장위 퍼스트하이(대장)  -> 못 찾음
       길음역 롯데캐슬                                        -> 5건 찾았으나 거래는 미매칭
     사용승인일은 흐릿하지 않다. 같은 법정동 + 같은 사용승인일이면 같은 단지다.

         장위자이레디언트  20250331  ->  0건    진짜 신축
         길음역 롯데캐슬   20240429  ->  1건    단지 65535

     한계: 같은 법정동에서 같은 날 사용승인된 다른 단지가 있으면 오탐이다.
     드물고, 오탐의 방향이 **"신축 목록에서 빠지는" 쪽**이라 안전하다.
     틀린 것을 보여주느니 빠지는 편이 낫다.

   ★ 버리지 않는다 — 네 번째 경우로 남긴다
     gold.v_trade_offsite : 단지는 있는데 거래 신고 지번이 달라 안 붙은 것.
     128건이 어느 단지 것인지 알면서 버릴 이유가 없다.

     **자동으로 잇지는 않는다.** 날짜 + 법정동은 충돌할 수 있고,
     match_complex_id 를 추정으로 채우면 "조용히 틀린 결과" 가 된다.
     드러내서 사람이 보게 한다.
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
                  LIKE '%' + REPLACE(REPLACE(k.kapt_name, '아파트', ''), ' ', '') + '%'),
       기등록단지   = m.complex_id,
       기등록단지명  = m.complex_nm
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
OUTER APPLY (
    /* 같은 법정동 + 같은 사용승인일 = 같은 단지. 이름이 아니라 날짜로 본다. */
    SELECT TOP 1 c.complex_id, c.complex_nm
    FROM gold.complex c
    WHERE c.sigungu_cd + c.bjdong_cd = k.bjd_code
      AND c.oldest_use_apr = k.kapt_usedate
      AND k.kapt_usedate IS NOT NULL
    ORDER BY c.complex_id
) m
WHERE g.상태 = 'NO_BLD'
  AND m.complex_id IS NULL;
GO

/* ------------------------------------------------------------
   gold.v_trade_offsite — 단지는 있는데 거래가 다른 지번으로 신고된 것

   추정이다. 자동으로 잇지 않는다. 화면에 "이 단지 것으로 보이는 거래 N건이
   다른 지번으로 신고돼 연결되지 않았습니다" 라고 드러내는 용도다.
   ------------------------------------------------------------ */
IF OBJECT_ID('gold.v_trade_offsite') IS NOT NULL DROP VIEW gold.v_trade_offsite;
GO
CREATE VIEW gold.v_trade_offsite
AS
SELECT 거래pnu      = g.pnu,
       거래          = g.거래,
       kapt_name   = k.kapt_name,
       사용승인       = k.kapt_usedate,
       세대          = k.ho_cnt,
       complex_id  = m.complex_id,
       complex_nm  = m.complex_nm,
       단지pnu      = m.rep_pnu,
       lawd_nm     = l.emd_nm
FROM gold.v_newbuild_gap g
JOIN silver.kapt_complex k ON k.pnu = g.pnu AND k.is_current = 1
LEFT JOIN meta.lawd_code l ON l.lawd_cd = k.bjd_code
OUTER APPLY (
    SELECT TOP 1 c.complex_id, c.complex_nm, c.rep_pnu
    FROM gold.complex c
    WHERE c.sigungu_cd + c.bjdong_cd = k.bjd_code
      AND c.oldest_use_apr = k.kapt_usedate
      AND k.kapt_usedate IS NOT NULL
    ORDER BY c.complex_id
) m
WHERE g.상태 = 'NO_BLD'
  AND m.complex_id IS NOT NULL;
GO
