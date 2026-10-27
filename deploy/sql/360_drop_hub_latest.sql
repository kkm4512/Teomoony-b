/* 360 허브 '최신 한 달' 원문 표(hub.l0304 층별 · l0306 전유공용 · l0308 공동주택가격) 내리기 (2026-10-27)
   C 드라이브가 21GB 까지 줄었다(사장님 "용량 막히는 거 있으면 필요 없는 건 지워도 돼").
   ★ 이 셋은 silver 대장 표(바꿔 끼운 것)로 이미 옮겼고, 다음 달에는 새 파일을 다시 받아 hub_latest.py 가 통째로 새로 만든다(그 달 것만 담는 표).
     원본은 국토부 허브 파일 그대로라 언제든 다시 만들 수 있다 — 우리 손으로 고친 기록이 아니다.
   ★ hubv 의 세 뷰(bld_flr_outline · bld_expos_pubuse_area · bld_hsprc)는 다음 달 hub_latest 뒤 353 을 다시 적용하면 다시 선다.
   ★ 지운 자리는 DB 파일 안에서 다시 쓴다 — 단지 구성이 새로 쓰는 만큼 C 드라이브가 더 줄지 않는다. */
IF OBJECT_ID('hub.l0304') IS NOT NULL DROP TABLE hub.l0304;
IF OBJECT_ID('hub.l0306') IS NOT NULL DROP TABLE hub.l0306;
IF OBJECT_ID('hub.l0308') IS NOT NULL DROP TABLE hub.l0308;
GO
SELECT 남은 = (SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID('hub') AND name LIKE 'l%'),
       데이터파일GB = (SELECT size / 131072.0 FROM sys.database_files WHERE type = 0),
       쓰는GB = (SELECT FILEPROPERTY(name, 'SpaceUsed') / 131072.0 FROM sys.database_files WHERE type = 0);
GO
