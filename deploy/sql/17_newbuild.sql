SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   17_newbuild : 대장이 아직 없는 신축을 화면에 띄우기 위한 뷰

   ★ 왜
     장위자이레디언트는 2,840세대인데 **화면에 아예 없다.**
     gold.complex 는 건축물대장에서만 만들어지는데 대장이 아직 안 나왔다.
     단지가 없으니 검색에도 지도에도 안 나오고, 실거래 645건이 통째로 안 보인다.
     길음역 롯데캐슬 트윈골드(128건)도 같다.

     CONTEXT 4-13 의 세 번째 경우 — "지금은 못 붙지만 나중에 붙는다" — 를
     사용자에게 보여줄 수 있는 유일한 길이다.

   ★ gold.complex 에 넣지 않는 이유 (4-20, 정책.md 2장)
     단지코드는 대장의 ROOT_PK 로 재현된다. 출처가 다른 단지를 섞으면 재현성이
     깨지고, 나중에 대장이 올라오면 **같은 단지가 둘**이 된다.
     별도 축으로 두고 PNU 로 잇는다. 대장이 생기면 이 뷰에서 저절로 사라진다.

   ★ 판정
       K-apt 에 있다  +  그 PNU 에 표제부가 0  +  그 법정동은 적재 범위 안
     세 번째가 중요하다. 적재하지 않은 법정동은 "대장이 없는" 게 아니라
     "안 본" 것이다(4-21, 4-22). meta.v_lawd_scope 로 거른다.

   ★ 좌표
     K-apt 는 좌표를 주지 않는다. 연속지적도 필지의 중심을 쓴다.
     **필지가 적재되지 않은 법정동은 좌표가 NULL 이다.** 목록에는 나오고
     지도에만 못 그린다 — 기존 "필지 없는 단지" 와 같은 처리다.
   ============================================================ */
USE Teomoony;
GO

IF OBJECT_ID('gold.v_newbuild') IS NOT NULL DROP VIEW gold.v_newbuild;
GO
CREATE VIEW gold.v_newbuild
AS
SELECT k.kapt_code,
       k.kapt_name,
       k.pnu,
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
       거래          = ISNULL(t.cnt, 0),
       최근거래       = t.last_ymd,
       최고가         = t.max_amount,
       centroid_lat = p.centroid_lat,
       centroid_lng = p.centroid_lng,
       인허가         = ISNULL(a.cnt, 0)
FROM silver.kapt_complex k
/* 그 법정동 대장을 적재했는가. 안 했으면 "대장이 없다" 고 말할 수 없다. */
JOIN meta.v_lawd_scope sc ON sc.lawd_cd = k.bjd_code
LEFT JOIN meta.lawd_code l ON l.lawd_cd = k.bjd_code
LEFT JOIN gold.v_pnu_bld b ON b.pnu     = k.pnu
/* 한 PNU 에 필지가 여럿일 수 있다. 대표 하나만 집는다 —
   컬럼별 MAX 로 섞으면 4-16 의 실수를 반복한다. */
OUTER APPLY (
    SELECT TOP 1 centroid_lat, centroid_lng
    FROM silver.cadastral_parcel cp
    WHERE cp.is_current = 1 AND cp.pnu = k.pnu AND cp.centroid_lat IS NOT NULL
    ORDER BY cp.pnu
) p
OUTER APPLY (
    /* ★ 2026-10-21 QA: `cnt` 만 COUNT(*) 로 **해제(취소) 거래를 포함**하고 있었다.
       같은 APPLY 안의 last_ymd·max_amount 는 `is_canceled = 0` 으로 빼고 있었다 —
       **한 집계 안에서 기준이 어긋났으니 실수다.** 그래서 마커가 '거래 704' 인데
       신축 상세 합은 702 였다(장위자이레디언트, 차이 2건 전부 해제).
       정책은 "해제는 건수·범위에서 빼고 따로 센다"(CONTEXT 4-5) — 거기에 맞춘다.
       실측: 해제가 있는 신축이 **194곳**이다. 그만큼 마커와 상세가 어긋나 있었다.
       해제 건수는 버리지 않고 `해제` 로 같이 내보낸다 — 화면이 적을 수 있게. */
    SELECT cnt = SUM(CASE WHEN r.is_canceled = 0 THEN 1 ELSE 0 END),
           해제 = SUM(CAST(r.is_canceled AS INT)),
           last_ymd = MAX(CASE WHEN r.is_canceled = 0 THEN r.deal_ymd END),
           max_amount = MAX(CASE WHEN r.is_canceled = 0 AND r.is_rent = 0
                                 THEN r.deal_amount END)
    FROM silver.rtms_trade r
    WHERE r.match_pnu = k.pnu AND r.match_complex_id IS NULL
) t
OUTER APPLY (
    SELECT cnt = COUNT(*) FROM silver.arch_permit ap
    WHERE ap.is_current = 1 AND ap.pnu = k.pnu
) a
WHERE k.is_current = 1
  AND k.pnu IS NOT NULL
  AND ISNULL(b.표제부, 0) = 0;     -- 대장(표제부)이 아직 없다
GO

/* 그 신축의 실거래를 평형별로. 단지 상세의 집계와 같은 규칙을 쓴다:
   평형은 FLOOR(전용면적), 해제 거래는 건수·범위에서 빼고 따로 센다
   (CONTEXT 4-5). 동/호 특정은 하지 않는다.

   ★★ 2026-10-21 QA: 그 약속이 **깨져 있었다.** 단지 상세(tradeStats·jeonse)는
     11-105 에서 `building_ar` 까지 보도록 고쳤는데 **이 뷰는 안 고쳤다.**
     그래서 building_ar 에만 면적이 있는 거래가 여기서 통째로 빠졌다 —
     실측 **170건 · 48단지**이고, 그 170건은 **전부** building_ar 을 갖고 있다.
     ※ 한 사실을 두 군데서 만들면 반드시 갈라진다 — 11-105 와 **같은 자리**다.
   ⚠ 아직 다른 점 하나: 단지 상세는 면적이 아예 없는 거래도 '면적 미상' 으로
     보여주는데 이 뷰는 `IS NOT NULL` 로 버린다. building_ar 을 넣은 지금
     해당 건수가 **0** 이라 차이가 없지만, 앞으로 생기면 조용히 사라진다.
     화면(신축 상세)이 null 평형을 그릴 수 있는지 확인한 뒤 따로 고친다. */
/* ⚠⚠ **이 블록은 옛 모양이다.** `gold.v_newbuild_trade` 의 최신 정의는
   `20_newbuild_seq.sql` 이고 거기에 `apt_seq`·`seq_nm` 이 있다.
   2026-10-21 에 이 파일만 다시 돌렸다가 그 두 칸이 사라져
   `/api/newbuilds/:code` 가 **500 (Invalid column name 'seq_nm')** 이 됐다 —
   공개 사이트의 신축 상세가 그 사이 안 열렸다.
   ★ **이 파일을 돌렸으면 반드시 20_newbuild_seq.sql 도 돌려라.**
   ★ 교훈: `deploy/sql` 의 번호가 작은 파일이 **현재 정의가 아닐 수 있다.**
     뷰를 고치기 전에 `grep -rln '<뷰이름>' deploy/sql/` 로 **누가 마지막에
     만드는지 먼저 확인한다.** */
IF OBJECT_ID('gold.v_newbuild_trade') IS NOT NULL DROP VIEW gold.v_newbuild_trade;
GO
CREATE VIEW gold.v_newbuild_trade
AS
SELECT r.match_pnu AS pnu,
       is_rent     = r.is_rent,
       area_grp    = CAST(FLOOR(COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar)) AS INT),
       cnt         = SUM(CASE WHEN r.is_canceled = 0 THEN 1 ELSE 0 END),
       canceled_cnt= SUM(CAST(r.is_canceled AS INT)),
       min_amount  = MIN(CASE WHEN r.is_canceled = 0 THEN r.deal_amount END),
       max_amount  = MAX(CASE WHEN r.is_canceled = 0 THEN r.deal_amount END),
       last_ymd    = MAX(CASE WHEN r.is_canceled = 0 THEN r.deal_ymd END),
       direct_cnt  = SUM(CASE WHEN r.is_canceled = 0 AND r.dealing_gbn LIKE N'%직거래%'
                              THEN 1 ELSE 0 END)
FROM silver.rtms_trade r
WHERE r.match_pnu IS NOT NULL
  AND r.match_complex_id IS NULL
  AND COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar) IS NOT NULL
GROUP BY r.match_pnu, r.is_rent,
         CAST(FLOOR(COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar)) AS INT);
GO
