/* 356 tempdb 상한 · 로그 줄이기 (2026-10-26)
   새벽에 전유공용 1억 1천만 줄 정렬이 tempdb 를 수백 GB 로 키워 C 드라이브(Docker 디스크 파일이 거기 있다)가 가득 찼다 → DB 멈춤.
   상한을 두면 그런 질의는 '공간 없음' 오류로 그 질의만 실패하고, C 드라이브와 다른 적재는 산다.
   tempdb 파일 8개 × 6GB + 로그 12GB. 로그(Teomoony_log)는 55GB 중 0.03GB 만 쓰고 있어 8GB 로 줄인다(SIMPLE 복구 모델). */
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev,  MAXSIZE = 6GB);
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev2, MAXSIZE = 6GB);
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev3, MAXSIZE = 6GB);
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev4, MAXSIZE = 6GB);
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev5, MAXSIZE = 6GB);
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev6, MAXSIZE = 6GB);
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev7, MAXSIZE = 6GB);
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev8, MAXSIZE = 6GB);
ALTER DATABASE tempdb MODIFY FILE (NAME = templog,  MAXSIZE = 12GB);
GO
USE Teomoony;
DBCC SHRINKFILE (Teomoony_log, 8192);
GO
SELECT name, 크기GB = size / 131072.0, 상한GB = CASE WHEN max_size = -1 THEN NULL ELSE max_size / 131072.0 END FROM sys.master_files WHERE database_id IN (2, DB_ID('Teomoony'));
GO
