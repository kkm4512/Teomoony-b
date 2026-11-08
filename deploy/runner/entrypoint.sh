#!/bin/sh
# 1) 스크립트 수십 개가 .env 의 127.0.0.1:11433(MSSQL) · 15432(PG) · 16379(Redis) · localhost:5173(웹)으로 붙는다.
#    스크립트를 고치지 않으려고, 이 컨테이너 안의 그 주소를 같은 도커 망의 각 컨테이너로 잇는다(socat).
for p in "11433 mssql:1433" "15432 postgis:5432" "16379 redis:6379" "5173 web:5173"; do
  set -- $p
  socat TCP-LISTEN:$1,bind=127.0.0.1,fork,reuseaddr TCP:$2 &
done
# 2) git: 윈도우가 만든 저장소라 주인이 다르다고 막는다 → 이 두 폴더만 믿는다. 줄바꿈 · 실행권한 차이는 윈도우 git 과 같게 본다.
git config --global --add safe.directory /app/Teomoony
git config --global --add safe.directory /app/Teomoony-f
git config --global core.fileMode false
# 3) 감시기. watch.cmd 처럼 restart.job 이면 코드를 새로 읽고 다시 뜬다(stop.job 도 다시 뜬다 — 멈추려면 docker stop teomoony-runner).
Q="${TM_QUEUE:-_queue}"
while true; do
  python _job_runner.py
  rm -f "$Q/_restart.flag"
  echo "==== 감시기 다시 띄움 $(date '+%F %T') ===="
  sleep 3
done
