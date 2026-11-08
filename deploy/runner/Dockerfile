# 터무니 작업 감시기(watch.cmd → 컨테이너) — 2026-11-08 사장님 "ㄱㄱ: 윈도우에 PowerShell 창이 하나도 없게"
#   작업 큐(_job_runner.py) · 수집 일정(collect_cron.py) · 디스크 지킴이(disk_guard.py) 가 이 안에서 돈다.
#   소스는 굽지 않는다 — C:\Project\Teomoony 를 /app/Teomoony 에 붙여 그대로 돌린다(받기 = 반영).
FROM python:3.12-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
        git socat tzdata ca-certificates procps util-linux curl \
    && rm -rf /var/lib/apt/lists/*
# docker 명령(웹 다시 켜기 · SQL 적용 docker cp/exec · compose) — PC 의 도커 엔진에 소켓으로 붙는다
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:27-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
# PC(윈도우) 파이썬과 같은 판(pip freeze 2026-11-08)
RUN pip install --no-cache-dir pymssql==2.4.4 "psycopg[binary]==3.2.3" requests==2.34.2
ENV TZ=Asia/Seoul PYTHONUTF8=1 PYTHONIOENCODING=utf-8 PYTHONUNBUFFERED=1
COPY entrypoint.sh /entrypoint.sh
WORKDIR /app/Teomoony/etl
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
