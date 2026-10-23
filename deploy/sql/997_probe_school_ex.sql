SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT j = (SELECT s.school_id, s.school_nm, s.school_se, s.fond_type, s.fond_date, s.lnmadr, s.rdnmadr, s.oper_sttus,
       l.schul_code, l.근거, i.schul_nm, i.fond_sc, i.fond_ymd, 개교 = JSON_VALUE(i.raw_json, '$.FOAS_MEMRD'), i.adrcd_cd, i.road_addr, i.coedu, i.hmpg,
       t.pban_yr, t.class_cnt, t.stdnt_cnt, t.per_class, t.teach_cnt, t.per_teacher, t.excp_yn
  FROM silver.school s
  LEFT JOIN gold.school_link l ON l.school_id = s.school_id
  LEFT JOIN silver.schoolinfo i ON i.schul_code = l.schul_code
  LEFT JOIN silver.schoolinfo_stat t ON t.schul_code = l.schul_code
 WHERE s.is_current = 1 AND s.school_nm = N'서울장위초등학교' FOR JSON PATH);
GO
SELECT j = (SELECT 급 = s.school_se, 전체 = COUNT(*), 이음 = SUM(CASE WHEN l.school_id IS NOT NULL THEN 1 ELSE 0 END),
       학생있음 = SUM(CASE WHEN t.stdnt_cnt IS NOT NULL THEN 1 ELSE 0 END)
  FROM silver.school s LEFT JOIN gold.school_link l ON l.school_id = s.school_id
  LEFT JOIN silver.schoolinfo_stat t ON t.schul_code = l.schul_code
 WHERE s.is_current = 1 AND s.oper_sttus = N'운영' AND (s.lnmadr LIKE N'서울%' OR s.rdnmadr LIKE N'서울%') AND s.school_se IN (N'초등학교', N'중학교', N'고등학교')
 GROUP BY s.school_se FOR JSON PATH);
