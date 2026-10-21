SET NOCOUNT ON;
/* ============================================================
   99_audit_scope — **지금 DB 에 몇 행 있는지**로 잰다 — 2026-10-17

   이 감사를 세 번 고쳐 썼다. 앞의 둘은 근사치였고 둘 다 틀렸다:
     · run 하나하나를 봄        -> 나중에 다시 채운 것까지 "모자람" 으로 셌다
     · MAX(req_count*100)      -> 여러 번 나눠 채운 범위를 모자란 것으로 셌다
                                  (돈암동 전유부가 14,666 다 있는데 23.9% 로 나왔다)

   정직한 측정은 하나뿐이다 — **적재 결과 테이블의 실제 행 수**.
   적재기가 자기 입으로 뭐라 했는지는 안 믿는다. 오늘 그게 두 번 깨졌다.

   ★ 층별개요만 다르다. 적재기가 구획을 합치므로(collapse) 행 수가 원본보다
     적다. SUM(seg_cnt) 가 원본 건수에 해당한다.
   ★ 범위 컬럼이 없는 층별개요는 기본개요를 거쳐 법정동을 얻는다.
   ============================================================ */
WITH one AS (
    SELECT p.run_id, pid = MIN(p.payload_id) FROM bronze.api_payload p GROUP BY p.run_id
),
x AS (   -- run 별 원본 건수 (응답 꼬리에서 totalCount 만)
    SELECT o.run_id,
           totalCount = TRY_CONVERT(INT,
               CASE WHEN CHARINDEX('<totalCount>', RIGHT(p.body,300)) > 0
                    THEN SUBSTRING(RIGHT(p.body,300),
                           CHARINDEX('<totalCount>', RIGHT(p.body,300)) + 12,
                           CHARINDEX('</totalCount>', RIGHT(p.body,300))
                           - CHARINDEX('<totalCount>', RIGHT(p.body,300)) - 12)
               END)
      FROM one o JOIN bronze.api_payload p ON p.payload_id = o.pid
),
src AS (   -- (op, 범위) 별 원본 건수
    SELECT s.operation, r.scope_key,
           원본 = MAX(x.totalCount), 시도 = COUNT(*),
           상태들 = STRING_AGG(r.status, ','), 마지막 = MAX(r.started_at)
      FROM meta.ingest_run r
      JOIN meta.api_source s ON s.source_id = r.source_id
      JOIN x ON x.run_id = r.run_id
     WHERE x.totalCount IS NOT NULL
     GROUP BY s.operation, r.scope_key
),
db AS (    -- (op, 범위) 별 현재 행 수
    SELECT operation='getBrBasisOulnInfo', scope_key=sigungu_cd+'/'+bjdong_cd, 현재=COUNT(*)
      FROM silver.bld_basis_outline WHERE is_current=1 GROUP BY sigungu_cd, bjdong_cd
    UNION ALL
    SELECT 'getBrTitleInfo', sigungu_cd+'/'+bjdong_cd, COUNT(*)
      FROM silver.bld_title WHERE is_current=1 GROUP BY sigungu_cd, bjdong_cd
    UNION ALL
    SELECT 'getBrRecapTitleInfo', sigungu_cd+'/'+bjdong_cd, COUNT(*)
      FROM silver.bld_recap_title WHERE is_current=1 GROUP BY sigungu_cd, bjdong_cd
    UNION ALL
    /* ★ 부속지번은 atch_sigungu_cd 를 쓰면 안 된다 — 그건 **붙은 지번 쪽**
       법정동이라 호출 범위(본 건물의 법정동)와 다를 수 있다.
       기본개요를 거쳐 본 건물의 범위를 쓴다. */
    SELECT 'getBrAtchJibunInfo', b.sigungu_cd+'/'+b.bjdong_cd, COUNT(*)
      FROM silver.bld_atch_jibun a
      JOIN silver.bld_basis_outline b
        ON b.mgm_bldrgst_pk = a.mgm_bldrgst_pk AND b.is_current = 1
     WHERE a.is_current = 1
     GROUP BY b.sigungu_cd, b.bjdong_cd
    UNION ALL
    SELECT 'getBrExposInfo', sigungu_cd+'/'+bjdong_cd, COUNT(*)
      FROM silver.bld_expos WHERE is_current=1 GROUP BY sigungu_cd, bjdong_cd
    UNION ALL
    SELECT 'getBrHsprcInfo', sigungu_cd+'/'+bjdong_cd, COUNT(*)
      FROM silver.bld_hsprc WHERE is_current=1 GROUP BY sigungu_cd, bjdong_cd
    UNION ALL
    /* 층별개요: 범위 컬럼이 없어 기본개요를 거친다. 합쳐진 구획을 되돌린다. */
    SELECT 'getBrFlrOulnInfo', b.sigungu_cd+'/'+b.bjdong_cd, SUM(ISNULL(f.seg_cnt,1))
      FROM silver.bld_flr_outline f
      JOIN silver.bld_basis_outline b
        ON b.mgm_bldrgst_pk = f.mgm_bldrgst_pk AND b.is_current = 1
     WHERE f.is_current = 1
     GROUP BY b.sigungu_cd, b.bjdong_cd
)
SELECT s.operation, s.scope_key,
       원본 = s.원본, 현재 = ISNULL(d.현재, 0),
       모자람 = s.원본 - ISNULL(d.현재, 0),
       퍼센트 = CONVERT(DECIMAL(5,1), 100.0 * ISNULL(d.현재,0) / NULLIF(s.원본,0)),
       s.시도, s.상태들, s.마지막
  FROM src s
  LEFT JOIN db d ON d.operation = s.operation AND d.scope_key = s.scope_key
 WHERE ISNULL(d.현재, 0) < s.원본
 ORDER BY (s.원본 - ISNULL(d.현재,0)) DESC;
