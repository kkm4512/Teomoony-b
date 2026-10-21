SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   20_newbuild_seq : 신축의 실거래를 aptSeq(단지) 단위로 쪼갠다

   ★ 동은 못 보여준다
     장위자이레디언트 31개 동의 이름을 아는 공공데이터가 없다.
       건축물대장 표제부  아직 없음 (그래서 신축이다)
       K-apt             개수(31)만. 목록 없음
       건축인허가          동별개요 29건 전부 가설건축물(컨테이너조 · 세대 0)
       건물 외곽선         철거 전 빌라 12동 (4-18)
       실거래 aptDong     전월세에는 필드 자체가 없다 (4-2)
     네이버가 동을 보여주는 것은 **중개 매물**(중개사 입력)에서 오는 것이다.
     공공 API 에는 없는 축이다. 단지 사진과 같은 성격의 공백.

   ★ 대신 단지(aptSeq)는 갈린다 — 4-15 가 기록한 그 키
     지번은 62-1 하나인데 실거래가 네 단지로 갈린다. 실측(645건, NULL 0):

         11290-5988  380건  5평형   장위자이레디언트(2단지)
         11290-5983  120건  3평형   장위자이레디언트(4단지)
         11290-5987   79건  4평형   장위자이레디언트(1단지)
         11290-5989   66건  2평형   장위자이레디언트(3단지)

     **bld_nm 에 단지명이 그대로 들어 있다.** aptSeq 는 코드일 뿐이라
     화면에는 못 쓰는데, 이름이 같이 와서 쓸 수 있게 됐다.

     "2단지 84㎡ 전세" 는 사람들이 실제로 쓰는 단위다. 동보다 쓸모가 클 수 있다.

   ★ gold.complex 에는 넣지 않는다 (4-15, 정책.md 2장)
     단지코드는 대장 ROOT_PK 로 재현된다. aptSeq 유래 단지를 섞으면 재현성이
     깨지고, 대장이 올라왔을 때 같은 단지가 둘이 된다. 표시 단위로만 쓴다.
   ============================================================ */
USE Teomoony;
GO

/* ★★ 이 파일이 `gold.v_newbuild_trade` 의 **최신 정의**다(apt_seq·seq_nm 포함).
   17_newbuild.sql 에도 같은 이름의 뷰가 있지만 그것은 **옛 모양**이다.
   ⚠ 2026-10-21 에 17 만 다시 돌렸다가 apt_seq·seq_nm 이 사라져
     `/api/newbuilds/:code` 가 **500 (Invalid column name 'seq_nm')** 이 됐다.
     공개 사이트가 그 사이 깨져 있었다. **17 을 돌렸으면 20 도 돌려라.**
   ★ 2026-10-21: `building_ar` 을 COALESCE 에 넣었다 — 단지 상세(tradeStats·jeonse)가
     11-105 에서 이미 그렇게 고쳐졌는데 이 뷰만 안 고쳐져 있었다.
     실측 **170건 · 48단지**가 여기서 빠지고 있었고, 그 170건은 전부 building_ar 을 갖는다. */
IF OBJECT_ID('gold.v_newbuild_trade') IS NOT NULL DROP VIEW gold.v_newbuild_trade;
GO
CREATE VIEW gold.v_newbuild_trade
AS
SELECT pnu          = r.match_pnu,
       apt_seq      = r.apt_seq,
       /* 한 aptSeq 안에서 이름은 같다. 화면에 띄울 대표 이름 하나만 집는다. */
       seq_nm       = MIN(r.bld_nm),
       is_rent      = r.is_rent,
       area_grp     = CAST(FLOOR(COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar)) AS INT),
       cnt          = SUM(CASE WHEN r.is_canceled = 0 THEN 1 ELSE 0 END),
       canceled_cnt = SUM(CAST(r.is_canceled AS INT)),
       min_amount   = MIN(CASE WHEN r.is_canceled = 0 THEN r.deal_amount END),
       max_amount   = MAX(CASE WHEN r.is_canceled = 0 THEN r.deal_amount END),
       last_ymd     = MAX(CASE WHEN r.is_canceled = 0 THEN r.deal_ymd END),
       direct_cnt   = SUM(CASE WHEN r.is_canceled = 0 AND r.dealing_gbn LIKE N'%직거래%'
                               THEN 1 ELSE 0 END)
FROM silver.rtms_trade r
WHERE r.match_pnu IS NOT NULL
  AND r.match_complex_id IS NULL
  AND COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar) IS NOT NULL
GROUP BY r.match_pnu, r.apt_seq, r.is_rent,
         CAST(FLOOR(COALESCE(r.exclu_use_ar, r.total_floor_ar, r.building_ar)) AS INT);
GO
