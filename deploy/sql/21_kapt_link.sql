SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
/* ============================================================
   21_kapt_link : K-apt 상세 항목 + 단지와의 참고 연결

   ★ 상세 API 는 36개 필드를 준다. 우리는 5개만 쓰고 있었다.
     전기차 충전기는 **groundElChargerCnt / undergroundElChargerCnt** 다.
     `kaptdEcnt` 가 아니다 — 이름이 비슷해 헷갈리기 쉬운데 그쪽은 전기 계약 관련이다.
     뜻이 분명한 필드만 가져온다. 애매한 것은 안 가져오는 편이 낫다.

   ★ 왜 연결하는가 — 분모를 바꾸면 그림이 달라진다 (2026-10-15 실측)

       상호 1:1   58단지 / 54,064   =  0.11%
                  세대 29,741 / 155,591 = 19.1%
                  거래  9,520 /  52,609 = 18.1%

     단지 수로는 0.1% 지만 **세대와 거래로는 5분의 1**이다. 우리 단지의 절대다수가
     단독주택이라 단지 수 분모가 그걸 가린다. 사람이 사고파는 것은 아파트에 몰려 있다.

   ★ 그래도 이것은 **추정이다**
     K-apt 의 PNU 는 못 믿는다(정책.md 3-7). 법정동 + 사용승인일로 잇는데,
     148개 중 1:1 은 42% 뿐이고 36% 는 2개 이상에 걸린다.
     그래서 **양쪽 모두 1:1 인 것만** 쓴다.

     - `match_complex_id` 를 채우지 않는다. 화면에서만 보여준다.
       데이터에 쓰면 모든 집계·마커가 그걸 사실로 취급한다.
     - **대조 컬럼을 같이 내려보낸다.** K-apt 와 대장은 같은 사실(세대·동수·최고층)을
       각자 들고 있다. 매칭이 맞으면 맞아떨어지고 틀리면 어긋난다.
       **어긋나면 화면이 경고한다** — 조용히 틀리지 않게 하는 장치다.
   ============================================================ */
USE Teomoony;
GO

/* ---- 상세 항목 컬럼 ---- */
IF COL_LENGTH('silver.kapt_complex','el_charger_ground') IS NULL
    ALTER TABLE silver.kapt_complex ADD
        el_charger_ground INT NULL,     -- groundElChargerCnt       전기차 충전기(지상)
        el_charger_under  INT NULL,     -- undergroundElChargerCnt  전기차 충전기(지하)
        parking_ground    INT NULL,     -- kaptdPcnt                주차(지상)
        parking_under     INT NULL,     -- kaptdPcntu               주차(지하)
        cctv_cnt          INT NULL,     -- kaptdCccnt               CCTV
        sec_cnt           INT NULL,     -- kaptdScnt                경비 인원
        clean_cnt         INT NULL,     -- kaptdClcnt               청소 인원
        sec_company       NVARCHAR(200) NULL,  -- kaptdSecCom       경비업체
        clean_company     NVARCHAR(200) NULL,  -- kaptCcompany      청소업체
        code_sec_nm       NVARCHAR(100) NULL,  -- codeSec           경비 관리방식
        code_clean_nm     NVARCHAR(100) NULL,  -- codeClean         청소 관리방식
        code_garbage_nm   NVARCHAR(100) NULL,  -- codeGarbage       음식물 처리
        code_disinf_nm    NVARCHAR(100) NULL,  -- codeDisinf        소독 관리방식
        code_elev_nm      NVARCHAR(100) NULL,  -- codeElev          승강기 관리형태
        welfare_facility  NVARCHAR(1000) NULL, -- welfareFacility   부대복리시설
        convenient_facility NVARCHAR(1000) NULL, -- convenientFacility
        education_facility  NVARCHAR(1000) NULL; -- educationFacility
GO

/* ------------------------------------------------------------
   gold.v_complex_kapt — 단지 ↔ K-apt 참고 연결 (양쪽 1:1 만)

   p : 법정동 + 사용승인일로 이어지는 모든 쌍
   양쪽에서 각각 상대가 하나뿐인 쌍만 남긴다. 하나라도 여럿이면 버린다 —
   "어느 쪽인지 모르겠다" 를 추측으로 메우지 않는다.
   ------------------------------------------------------------ */
IF OBJECT_ID('gold.v_complex_kapt') IS NOT NULL DROP VIEW gold.v_complex_kapt;
GO
CREATE VIEW gold.v_complex_kapt
AS
WITH p AS (
    SELECT c.complex_id, c.hhld_cnt_sum, c.dong_cnt, c.max_floor, c.oldest_use_apr,
           k.kapt_code
    FROM gold.complex c
    JOIN silver.kapt_complex k
      ON k.is_current = 1
     AND k.bjd_code = c.sigungu_cd + c.bjdong_cd
     AND k.kapt_usedate = c.oldest_use_apr
     AND NULLIF(k.kapt_usedate, '') IS NOT NULL
)
SELECT p.complex_id,
       k.kapt_code, k.kapt_name, k.kapt_addr, k.doro_juso,
       /* 대조용 — 매칭이 맞으면 맞아떨어진다 */
       kapt_세대 = k.ho_cnt,       대장_세대 = p.hhld_cnt_sum,
       kapt_동수 = k.dong_cnt,     대장_동수 = p.dong_cnt,
       kapt_최고층 = k.top_floor,  대장_최고층 = p.max_floor,
       사용승인 = k.kapt_usedate,
       /* 본문 */
       난방 = k.code_heat_nm, 복도 = k.code_hall_nm, 관리 = k.code_mgr_nm,
       분양임대 = k.code_sale_nm, 유형 = k.code_apt_nm,
       시공 = k.bcompany, 시행 = k.acompany,
       관리인원 = k.mgr_cnt,
       지하철 = k.subway_station, 지하철노선 = k.subway_line,
       지하철도보 = k.wtime_sub, 버스도보 = k.wtime_bus,
       주차 = k.parking_cnt, 주차_지상 = k.parking_ground, 주차_지하 = k.parking_under,
       전기차_지상 = k.el_charger_ground, 전기차_지하 = k.el_charger_under,
       CCTV = k.cctv_cnt,
       경비인원 = k.sec_cnt, 경비업체 = k.sec_company, 경비방식 = k.code_sec_nm,
       청소인원 = k.clean_cnt, 청소업체 = k.clean_company, 청소방식 = k.code_clean_nm,
       음식물 = k.code_garbage_nm, 소독 = k.code_disinf_nm, 승강기관리 = k.code_elev_nm,
       부대복리시설 = k.welfare_facility, 편의시설 = k.convenient_facility,
       교육시설 = k.education_facility,
       연면적 = k.kapt_tarea, 전용면적합 = k.priv_area
FROM p
JOIN silver.kapt_complex k ON k.kapt_code = p.kapt_code AND k.is_current = 1
WHERE 1 = (SELECT COUNT(*) FROM p p2 WHERE p2.complex_id = p.complex_id)
  AND 1 = (SELECT COUNT(*) FROM p p3 WHERE p3.kapt_code  = p.kapt_code);
GO
