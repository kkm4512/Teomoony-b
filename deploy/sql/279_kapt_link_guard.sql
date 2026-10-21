/* 279. gold.v_complex_kapt — 지번도 세대도 안 맞는 '추정 연결' 을 뺀다 (2026-10-21 QA)
   ★ 왜: 리얼파크2차(불광동 331-55, 16세대) 상세에 **셀립은평(불광동 272-5, 201세대)의 관리비**가 떴다.
     이 뷰는 '같은 법정동 + 같은 사용승인일이 양쪽에 하나씩' 이면 잇는데, 두 건물이 같은 날(2021-04-30) 승인을 받았다.
   ★ 실측(156 연결): 지번 같음 143 · 다름 13. 다른 13 중 10은 이름·세대가 같다(재개발로 지번이 바뀐 곳) — 맞는 연결이다.
     세대가 20% 넘게 다른 것 3: 리얼파크2차(16)↔셀립은평(201) · 성북힐스테이트(65)↔(285) · SK청암대(14)↔(0).
   ★ 규칙(정책 1-4 '근거 있고 거의 확실해야'): **K-apt 지번이 그 단지 지번이 아니고 + 세대도 20% 넘게 다르면(또는 0이면) 잇지 않는다.**
     이름으로는 판단하지 않는다(정책 1장). 지번이 같으면 세대가 달라도 그대로 둔다(묶음 차이일 수 있다).
   ★ 바탕은 DB 의 현재 정의 그대로 — 바꾼 곳은 맨 아래 WHERE 의 AND 하나. */
CREATE OR ALTER VIEW gold.v_complex_kapt
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
       /* ★ hoCnt 는 호수, kaptdaCnt 가 세대수다(래미안퍼스트하이 호수 1,568 / 세대수 1,562 = 대장 1,562). */
       kapt_세대 = COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt),
       kapt_호수 = k.ho_cnt,       대장_세대 = p.hhld_cnt_sum,
       kapt_동수 = k.dong_cnt,     대장_동수 = p.dong_cnt,
       kapt_최고층 = k.top_floor,  대장_최고층 = p.max_floor,
       사용승인 = k.kapt_usedate,
       난방 = k.code_heat_nm, 복도 = k.code_hall_nm, 관리 = k.code_mgr_nm,
       분양임대 = k.code_sale_nm, 유형 = k.code_apt_nm,
       시공 = k.bcompany, 시행 = k.acompany,
       관리인원 = k.mgr_cnt,
       지하철 = k.subway_station, 지하철노선 = k.subway_line,
       지하철도보 = k.wtime_sub, 버스도보 = k.wtime_bus,
       /* ★ parking_cnt 에 kaptdaCnt(세대수)가 들어가 있었다 — 지상+지하 합을 쓴다 */
       주차 = ISNULL(k.parking_ground, 0) + ISNULL(k.parking_under, 0),
       주차_원본 = k.parking_cnt,
       주차_지상 = k.parking_ground, 주차_지하 = k.parking_under,
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
  AND 1 = (SELECT COUNT(*) FROM p p3 WHERE p3.kapt_code  = p.kapt_code)
  /* 279: 지번도 세대도 안 맞으면 '거의 확실' 이 아니다 */
  AND NOT (k.pnu IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM gold.complex_pnu cp WHERE cp.complex_id = p.complex_id AND cp.pnu = k.pnu)
           AND (COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt, 0) = 0
                OR ABS(ISNULL(p.hhld_cnt_sum, 0) - COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt))
                   > 0.2 * COALESCE(NULLIF(k.hhld_cnt, 0), k.ho_cnt)));
GO
SELECT 연결 = COUNT(*), 리얼파크2차 = SUM(CASE WHEN complex_id = 96771 THEN 1 ELSE 0 END),
       장위퍼스트하이 = SUM(CASE WHEN complex_id = 49101 THEN 1 ELSE 0 END)
  FROM gold.v_complex_kapt;
