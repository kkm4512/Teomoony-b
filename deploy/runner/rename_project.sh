#!/bin/sh
# 2026-11-08 묶음 이름 deploy → teomoony (사장님 ㄱㄱ). 작업 감시기(teomoony-runner)도 그 묶음 안이라, 이 스크립트는
# **바깥의 일회용 도우미 컨테이너**에서 돈다(작업 zd-rename-par 가 docker run -d 로 띄움). 데이터는 옛 저장공간(deploy_*) 그대로.
LOG=/app/Teomoony/logs/job_$(date +%Y%m%d_%H%M%S)_rename-project.log
exec >>"$LOG" 2>&1
echo "  시작 $(date '+%F %T')"
cd /app/Teomoony || exit 1
if [ "$(docker inspect teomoony-svc --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null)" = "teomoony" ]; then
  echo "이미 teomoony — 할 일 없음"; exit 0
fi
export TM_ROOT=/run/desktop/mnt/host/c/Project/Teomoony TM_ROOT_F=/run/desktop/mnt/host/c/Project/Teomoony-f
echo "== 1) 옛 묶음(deploy) 내리기 — 저장공간은 지우지 않는다"
docker compose -p deploy --env-file .env -f deploy/docker-compose.yml down
echo "== 2) 새 묶음(teomoony) 올리기"
docker compose --env-file .env -f deploy/docker-compose.yml up -d --no-build
sleep 20
for c in teomoony-mssql teomoony-svc teomoony-redis teomoony-web teomoony-runner; do
  if [ "$(docker inspect $c --format '{{.State.Running}}' 2>/dev/null)" != "true" ]; then
    echo "   $c 안 떠서 다시 시작(옛 문이 늦게 풀리는 경우)"; sleep 5; docker start $c
  fi
done
sleep 30
echo "== 3) 결과"
docker ps --filter label=com.docker.compose.project=teomoony --format '{{.Names}} | {{.Status}} | {{.Ports}}'
docker ps --filter label=com.docker.compose.project=deploy --format 'deploy 남음: {{.Names}}'
echo "  끝 $(date '+%F %T')  종료코드 0"
