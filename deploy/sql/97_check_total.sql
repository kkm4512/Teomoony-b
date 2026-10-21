SET NOCOUNT ON;
/* run 10532 = getBrBasisOulnInfo 11380/10100.
   페이지마다 응답이 말한 totalCount 를 뽑는다. 값이 도중에 바뀌면
   api_total 을 덮어쓰는 적재기가 거기서 "다 받았다" 로 오판한다. */
SELECT 페이지 = TRY_CONVERT(INT, JSON_VALUE(req_params, '$.pageNo')),
       http   = http_status,
       코드   = result_code,
       totalCount = TRY_CONVERT(INT,
           CASE WHEN CHARINDEX('<totalCount>', body) > 0
                THEN SUBSTRING(body,
                       CHARINDEX('<totalCount>', body) + 12,
                       CHARINDEX('</totalCount>', body)
                       - CHARINDEX('<totalCount>', body) - 12)
           END),
       item수 = (LEN(body) - LEN(REPLACE(body, '<item>', ''))) / 6,
       본문길이 = LEN(body)
  FROM bronze.api_payload
 WHERE run_id = 10532
 ORDER BY 1;
