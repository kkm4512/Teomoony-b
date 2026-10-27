/* 365 로그 파일 줄이기 (2026-10-28) — 실거래 다시 잇기(5,500만 줄 UPDATE)로 로그가 58GB 까지 컸고 지금 쓰는 건 0.1GB.
   C 가 21GB 라 줄인다. 데이터는 건드리지 않는다(빈 로그 공간만 돌려준다). 뒤에 fstrim 으로 C 에 돌아온다. */
CHECKPOINT;
DBCC SHRINKFILE (Teomoony_log, 8192);
SELECT name, 파일GB = size / 131072.0 FROM sys.database_files;
