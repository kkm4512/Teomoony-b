-- 11-03 이용현황 다시 세기 전 사본(되돌리기용 · 파생 표). 이미 있으면 그대로 둔다(처음 사본을 덮지 않는다)
CREATE TABLE IF NOT EXISTS app.usage_hour_bak_20261103 AS SELECT * FROM app.usage_hour;
