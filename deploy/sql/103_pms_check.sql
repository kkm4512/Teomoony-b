/* ============================================================
   103_pms_check  -  건축인허가 현황 확인                 2026-10-17
   ------------------------------------------------------------
   30_load_target 을 다시 돌린 뒤 이걸 본다.

   ★ 왜 이 확인이 필요한가
     ingest_run.scope_key 는 `시군구/법정동` 이다. --bun 을 줘서 **한 번지만**
     떠본 것도 그 법정동 전체가 OK 인 것처럼 남는다(run_mode='SINGLE').
     인허가 필드는 "장위동 62-1 실응답" 으로 확인했으니, 장위동은 **번지 하나만
     떠본 기록이 DONE 으로 보일 수 있다.** 그러면 러너는 영원히 건너뛴다.
     run_mode 를 같이 봐야 구별된다 - 적게 보고 넘어가면 또 속는다.
   ============================================================ */
SET NOCOUNT ON;

PRINT '--- 1. op 카탈로그 (domain/base_url) ---';
SELECT op_alias, grp, sort_no, domain, operation, base_url
  FROM meta.load_op ORDER BY sort_no;

PRINT '--- 2. 인허가 적재 기록 (법정동별) ---';
SELECT 시군구 = LEFT(r.scope_key,5), 스코프 = r.scope_key,
       법정동 = l.emd_nm, s.operation, r.run_mode, r.status,
       호출 = r.req_count, 행 = r.row_count, r.started_at
  FROM meta.ingest_run r
  JOIN meta.api_source s ON s.source_id = r.source_id
  LEFT JOIN meta.lawd_code l ON l.lawd_cd = REPLACE(r.scope_key,'/','')
 WHERE s.operation IN ('getApBasisOulnInfo','getApDongOulnInfo')
 ORDER BY r.started_at;

PRINT '--- 3. 실제 행 수 (시군구별) ---';
SELECT 시군구 = p.sigungu_cd,
       인허가 = COUNT(*),
       법정동수 = COUNT(DISTINCT p.bjdong_cd),
       최근허가일 = MAX(p.arch_pms_day)
  FROM silver.arch_permit p
 WHERE p.is_current = 1
 GROUP BY p.sigungu_cd ORDER BY p.sigungu_cd;

SELECT 시군구 = d.sigungu_cd, 인허가동 = COUNT(*)
  FROM silver.arch_permit_dong d
 WHERE d.is_current = 1
 GROUP BY d.sigungu_cd ORDER BY d.sigungu_cd;

PRINT '--- 4. 남은 일 (인허가만) ---';
SELECT sgg_cd, op_alias, 법정동수, 완료, 재시도, 남음, 선행미완
  FROM meta.v_load_progress WHERE grp = 'pms' ORDER BY sgg_cd, op_alias;

PRINT '--- 5. 아파트 단지에 인허가가 0건인 이유를 가른다 ---';
/* 화면에서 종로·은평 아파트 단지가 전부 **인허가 0건**으로 나온다.
   이유가 둘인데 **아직 어느 쪽인지 모른다.**
     ① 재개발·재건축은 주택법 사업계획승인 대상이라 이 체계에 아예 안 들어온다
        (CONTEXT 4-14). 그렇다면 0건이 맞다.
     ② 상세 조회가 `arch_permit.pnu = 단지필지.pnu` **정확일치**로 조인한다.
        허가가 합필 전 지번으로 들어왔거나 단지 필지가 여러 개면 놓친다.
        그렇다면 0건은 **조인이 만든 거짓말**이다.
   아래가 둘을 가른다 — 법정동 안에 허가는 있는데 단지 필지와 안 붙는 양. */
WITH c AS (
    SELECT complex_id, 단지 = complex_nm,
           lawd = sigungu_cd + bjdong_cd
      FROM gold.complex
     WHERE sigungu_cd IN ('11110','11380') AND hhld_cnt_sum >= 300
)
SELECT TOP 20 c.complex_id, c.단지,
       법정동내허가 = (SELECT COUNT(*) FROM silver.arch_permit a
                        WHERE a.is_current = 1 AND a.pnu LIKE c.lawd + '%'),
       /* 화면이 쓰는 조인 그대로다 (server.js 의 permits 질의) */
       단지필지허가 = (SELECT COUNT(*)
                         FROM gold.complex_pnu cp
                         JOIN silver.arch_permit a
                           ON a.pnu = cp.pnu AND a.is_current = 1
                        WHERE cp.complex_id = c.complex_id),
       단지필지수   = (SELECT COUNT(*) FROM gold.complex_pnu cp
                        WHERE cp.complex_id = c.complex_id)
  FROM c ORDER BY 법정동내허가 DESC;
