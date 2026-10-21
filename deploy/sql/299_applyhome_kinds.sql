/* 299 : 청약홈 공고 종류 — APT 말고 오피스텔·도시형 · 무순위·재공급 · 공공지원민간임대 · 임의공급 (2026-10-22, 사장님 "1,2,3 ㄱㄱ")
   ★ 같은 odcloud ApplyhomeInfoDetailSvc 의 다른 목록이다(키 그대로). 서울+안양 실측: APT 222 · URBTY 226 · REMNDR 336 · PBLPVT 44 · OPT 166.
     (관리번호, 공고번호)가 종류끼리 **겹치지 않는다**(실측) → 기본키는 그대로 두고 종류 칸만 더한다.
   ★ 공공지원민간임대(PBLPVT)의 SUPLY_AMOUNT 는 분양가가 아니다(임대 조건) — 분양가 칸(top_amount_man)에 넣지 않는다. 원문은 raw_json. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF COL_LENGTH('silver.applyhome_pblanc', '공고종류') IS NULL
    ALTER TABLE silver.applyhome_pblanc ADD 공고종류 VARCHAR(10) NOT NULL CONSTRAINT df_applyhome_kind DEFAULT 'APT';
GO
