/* 236_scope_check : 장부 뷰 두 개가 진짜 없나 — 직접 쳐 본다 (2026-10-21) 읽기만 */
USE Teomoony;
GO
SELECT 있나 = CASE WHEN OBJECT_ID('meta.v_load_plan')     IS NULL THEN N'없음' ELSE N'있음' END,
       뭐   = N'meta.v_load_plan';
GO
SELECT 있나 = CASE WHEN OBJECT_ID('meta.v_load_page_gap') IS NULL THEN N'없음' ELSE N'있음' END,
       뭐   = N'meta.v_load_page_gap';
GO
SELECT 있나 = CASE WHEN OBJECT_ID('meta.v_load_progress') IS NULL THEN N'없음' ELSE N'있음' END,
       뭐   = N'meta.v_load_progress';
GO
