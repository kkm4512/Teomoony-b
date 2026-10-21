SET NOCOUNT ON;
/* ============================================================
   100_mark_partial — 잘린 적재를 RETRY 로 되돌린다 — 2026-10-17

   99_audit_scope 가 찾은 것 중 **95% 미만**만 손댄다.

   ★ 기준을 95% 로 둔 이유.
     99% 대에 1~62건씩 빠지는 계통 오차가 80건 넘게 있다. 원인을 아직 모르고
     (페이지 경계를 넘는 collapse? 자연키가 덜 유일한 것?), **재적재로 풀릴지
     알 수 없다.** 모르는 채로 다시 돌리면 일일 한도만 쓰고 같은 결과가 나온다.
     큰 구멍부터 메우고, 작은 것은 원인을 재고 나서 따로 다룬다.

   ★ getAp* (공동주택 대장) 는 제외한다. 99 의 db CTE 가 그 테이블을 안 세서
     0% 로 나올 뿐, 실제로 비었는지 확인되지 않았다. 모르는 것을 고치지 않는다.
   ============================================================ */
WITH one AS (
    SELECT p.run_id, pid = MIN(p.payload_id) FROM bronze.api_payload p GROUP BY p.run_id
),
x AS (
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
src AS (
    SELECT s.operation, r.scope_key, 원본 = MAX(x.totalCount)
      FROM meta.ingest_run r
      JOIN meta.api_source s ON s.source_id = r.source_id
      JOIN x ON x.run_id = r.run_id
     WHERE x.totalCount IS NOT NULL AND s.operation LIKE 'getBr%'
     GROUP BY s.operation, r.scope_key
),
db AS (
    SELECT operation='getBrBasisOulnInfo', scope_key=sigungu_cd+'/'+bjdong_cd, 현재=COUNT(*)
      FROM silver.bld_basis_outline WHERE is_current=1 GROUP BY sigungu_cd, bjdong_cd
    UNION ALL SELECT 'getBrTitleInfo', sigungu_cd+'/'+bjdong_cd, COUNT(*)
      FROM silver.bld_title WHERE is_current=1 GROUP BY sigungu_cd, bjdong_cd
    UNION ALL SELECT 'getBrRecapTitleInfo', sigungu_cd+'/'+bjdong_cd, COUNT(*)
      FROM silver.bld_recap_title WHERE is_current=1 GROUP BY sigungu_cd, bjdong_cd
    UNION ALL SELECT 'getBrExposInfo', sigungu_cd+'/'+bjdong_cd, COUNT(*)
      FROM silver.bld_expos WHERE is_current=1 GROUP BY sigungu_cd, bjdong_cd
    UNION ALL SELECT 'getBrHsprcInfo', sigungu_cd+'/'+bjdong_cd, COUNT(*)
      FROM silver.bld_hsprc WHERE is_current=1 GROUP BY sigungu_cd, bjdong_cd
    UNION ALL SELECT 'getBrAtchJibunInfo', b.sigungu_cd+'/'+b.bjdong_cd, COUNT(*)
      FROM silver.bld_atch_jibun a JOIN silver.bld_basis_outline b
        ON b.mgm_bldrgst_pk = a.mgm_bldrgst_pk AND b.is_current=1
     WHERE a.is_current=1 GROUP BY b.sigungu_cd, b.bjdong_cd
    UNION ALL SELECT 'getBrFlrOulnInfo', b.sigungu_cd+'/'+b.bjdong_cd, SUM(ISNULL(f.seg_cnt,1))
      FROM silver.bld_flr_outline f JOIN silver.bld_basis_outline b
        ON b.mgm_bldrgst_pk = f.mgm_bldrgst_pk AND b.is_current=1
     WHERE f.is_current=1 GROUP BY b.sigungu_cd, b.bjdong_cd
),
bad AS (
    SELECT s.operation, s.scope_key, s.원본, 현재 = ISNULL(d.현재,0)
      FROM src s LEFT JOIN db d
        ON d.operation=s.operation AND d.scope_key=s.scope_key
     WHERE ISNULL(d.현재,0) < s.원본 * 0.95
)
SELECT '바꿀 대상' AS 구분, b.operation, b.scope_key, b.원본, b.현재,
       퍼센트 = CONVERT(DECIMAL(5,1), 100.0*b.현재/NULLIF(b.원본,0)),
       바꿀run = COUNT(r.run_id)
  FROM bad b
  JOIN meta.api_source s ON s.operation = b.operation
  JOIN meta.ingest_run r ON r.source_id = s.source_id AND r.scope_key = b.scope_key
                        AND r.status = 'OK'
 GROUP BY b.operation, b.scope_key, b.원본, b.현재
 ORDER BY b.원본 - b.현재 DESC;
