/* 210. 등기 스텁 폐기 (2026-10-20)
   사용자 결정: "5번은 폐기하고"

   왜 폐기하나
     * 공공데이터포털에 **등기부등본 오픈API 가 없다.**
     * 등기는 부동산고유번호(14)를 쓰고 PNU(19)와 직접 매칭이 안 된다.
       집합건물은 PNU+동+호, 토지/일반건물은 PNU 로 **주소 문자열 정규화 매칭**을
       거쳐야 하는데, 그건 정책 1장(코드로만 잇는다)에 어긋난다.
     * 스크래핑은 쓰지 않는다 (정책 1장).
   실측 2026-10-20: silver.registry_property **0건.** 비어 있는 채로 둘 표였다.

   ★ 02_silver.sql 의 8장에서 CREATE 를 **먼저 지웠다.** 이걸 지워도 그쪽이
     남아 있으면 다음 재적용 때 표가 되살아난다 — 둘을 같이 지워야 폐기다.
   ★ 되살리지 말 것. 공공 API 가 생기면 그때 새로 설계한다.
*/
IF OBJECT_ID('silver.registry_property') IS NOT NULL
BEGIN
    /* ★ 혹시라도 행이 있으면 지우지 않는다 — 0건인 것을 확인하고 왔지만,
       그 사이에 누가 넣었을 수 있다. 조용히 버리지 않는다. */
    DECLARE @n INT = (SELECT COUNT(*) FROM silver.registry_property);
    IF @n > 0
        THROW 50000, N'silver.registry_property 에 행이 있습니다 — 폐기를 멈춥니다. 내용을 확인하세요.', 1;
    DROP TABLE silver.registry_property;
    PRINT '210 완료 - silver.registry_property 폐기';
END
ELSE
    PRINT '210 - silver.registry_property 가 이미 없습니다 (할 일 없음)';
