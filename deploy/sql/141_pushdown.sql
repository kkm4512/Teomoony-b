USE Teomoony;
GO
SET NOCOUNT ON;
SET STATISTICS TIME ON;
GO
PRINT '=== 지금 (호PK 로만 조인) ===';
SELECT COUNT(*) FROM gold.v_complex_ho h
  LEFT JOIN gold.v_complex_ho_price p ON p.호PK = h.호PK
 WHERE h.complex_id = 103835;
GO
PRINT '=== complex_id 조건을 조인에 같이 주면 ===';
SELECT COUNT(*) FROM gold.v_complex_ho h
  LEFT JOIN gold.v_complex_ho_price p ON p.호PK = h.호PK AND p.complex_id = 103835
 WHERE h.complex_id = 103835;
GO
PRINT '=== 다른 단지로 한 번 더 (우연 아닌지) ===';
SELECT COUNT(*) FROM gold.v_complex_ho h
  LEFT JOIN gold.v_complex_ho_price p ON p.호PK = h.호PK AND p.complex_id = 104475
 WHERE h.complex_id = 104475;
GO
SET STATISTICS TIME OFF;
GO
