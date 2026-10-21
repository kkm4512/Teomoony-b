/* 193. 주안역 '거짓 변경 이력' 지우기 (2026-10-19)
   ★ 원본(15013205)에 주안역 경인선이 **모든 칸이 같은 줄로 두 번** 들어 있다.
     적재기가 둘 다 넣으면서 자연키가 같아, 두 번째가 첫 번째를
     is_current=0 으로 밀어냈다. 즉 **바뀐 적이 없는데 '변경 이력' 이 생겼다.**
     SCD2 이력은 '언제 무엇이 바뀌었나' 를 말해야 한다 - 거짓말을 남기지 않는다.
   ★ 적재기(load_transit.py)에는 그 뒤 자연키 중복 제거를 넣었다.
     다음 적재부터는 '자연키가 같은 줄 N건을 뺐습니다' 라고 **말하고** 넘어간다.
   ★ 지우는 대상을 좁게 적는다 - '이력 전부 지우기' 같은 건 하지 않는다. */
SET NOCOUNT ON;
SELECT 지울것 = COUNT(*) FROM silver.subway_station
 WHERE is_current = 0 AND sttn_nm = N'주안역' AND line_nm = N'경인선';

DELETE FROM silver.subway_station
 WHERE is_current = 0 AND sttn_nm = N'주안역' AND line_nm = N'경인선';
PRINT '지움: ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '건';

SELECT 현재행 = SUM(CASE WHEN is_current = 1 THEN 1 ELSE 0 END),
       이력행 = SUM(CASE WHEN is_current = 0 THEN 1 ELSE 0 END)
  FROM silver.subway_station;
