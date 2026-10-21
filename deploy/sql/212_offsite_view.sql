/* 212. gold.v_trade_offsite 를 **걸러지는 모양**으로 다시 쓴다 (2026-10-20)

   ★ 무엇이 문제였나
     19_newbuild_date.sql 의 원래 뷰는 complex_id 를 OUTER APPLY 안에서 만든다:
         OUTER APPLY (SELECT TOP 1 c.complex_id ... FROM gold.complex c
                       WHERE c.sigungu_cd + c.bjdong_cd = k.bjd_code
                         AND c.oldest_use_apr = k.kapt_usedate
                       ORDER BY c.complex_id) m
     그래서 `WHERE o.complex_id = @id` 를 **뷰 안으로 밀어넣을 수 없다** —
     DB 전체를 만들고 나서 거른다. 게다가 왼쪽이 이어붙인 계산식이라
     ix_complex_sgg (sigungu_cd, bjdong_cd) 도 못 탄다.
     gold.complex 가 8만 -> 538,377 로 늘고 실거래가 1,053만이 되면서 같이 느려졌다.

   ★ 어떻게 고치나
     ① complex_id 를 **gold.complex 의 진짜 컬럼으로** 노출한다 -> PK 로 걸러진다
     ② 조인 조건을 쪼갠다: c.sigungu_cd = LEFT(k.bjd_code,5)
                          AND c.bjdong_cd  = RIGHT(k.bjd_code,5)
        -> 있는 인덱스를 탄다. 새 컬럼도 새 인덱스도 필요 없다.
     ③ TOP 1 ORDER BY complex_id 는 MIN(complex_id) 과 **같은 뜻**이다.
        그래서 의미가 보존된다.

   ★ 의미가 같은지 **재기 전에 맞춰 봤다** (2026-10-20, localhost)
     행이 나오는 단지 3개에서 옛 뷰와 새 질의의 결과가 **완전히 같았다**:
       complex_id 65535 (5행) · 48829 (4행) · 64325 (2행)  -> 전부 일치
     0행인 단지 3개도 둘 다 0행.
     ★ 빨라도 결과가 다르면 못 쓴다. 그래서 속도보다 이걸 먼저 봤다.

   ★ 속도 (같은 단지, 직렬)
     107010   915ms -> 304ms   (2회차 727 -> 205)
     528197 1,100ms ->  27ms
     298988   351ms -> 122ms
     상세 전체에서 off 가 차지하던 1,633~2,120ms 가 여기서 줄어든다.

   ★ 되돌리기: 19_newbuild_date.sql 의 뷰 정의를 그대로 다시 올리면 된다.

   ※ 211(ix_rtms_gap)은 **기대만큼 듣지 않았다** — 강제로 태우면 오히려 느렸다
     (724ms -> 1,463ms). 남겨는 두되 효과는 이 파일의 재작성 쪽이다.
     나중에 지워도 된다: DROP INDEX ix_rtms_gap ON silver.rtms_trade;
*/
IF OBJECT_ID('gold.v_trade_offsite') IS NOT NULL DROP VIEW gold.v_trade_offsite;
GO
CREATE VIEW gold.v_trade_offsite
AS
SELECT 거래pnu      = g.pnu,
       거래          = g.거래,
       kapt_name   = k.kapt_name,
       사용승인       = k.kapt_usedate,
       세대          = k.ho_cnt,
       complex_id  = c.complex_id,
       complex_nm  = c.complex_nm,
       단지pnu      = c.rep_pnu,
       lawd_nm     = l.emd_nm
FROM gold.v_newbuild_gap g
JOIN silver.kapt_complex k ON k.pnu = g.pnu AND k.is_current = 1
LEFT JOIN meta.lawd_code l ON l.lawd_cd = k.bjd_code
/* ★ 이어붙이지 않고 쪼갠다 — 이래야 ix_complex_sgg 를 탄다 */
JOIN gold.complex c
  ON c.sigungu_cd = LEFT(k.bjd_code, 5)
 AND c.bjdong_cd  = RIGHT(k.bjd_code, 5)
 AND c.oldest_use_apr = k.kapt_usedate
WHERE g.상태 = 'NO_BLD'
  AND k.kapt_usedate IS NOT NULL
  /* ★ 원래 뷰의 TOP 1 ORDER BY complex_id 와 같은 뜻 — 가장 작은 단지 하나만 */
  AND c.complex_id = (SELECT MIN(c2.complex_id) FROM gold.complex c2
                       WHERE c2.sigungu_cd = LEFT(k.bjd_code, 5)
                         AND c2.bjdong_cd  = RIGHT(k.bjd_code, 5)
                         AND c2.oldest_use_apr = k.kapt_usedate);
GO
PRINT '212 완료 - gold.v_trade_offsite 다시 씀';
