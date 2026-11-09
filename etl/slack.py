"""slack - 슬랙 채널로 메시지 보내기 (2026-11-09)

.env 의 SLACK_WEBHOOK_URL(앱 'Teomoony Report' 의 Incoming Webhook) 로 보낸다.
  python slack.py --test          시험 메시지 한 통
  python slack.py "보낼 글"        글 한 통

★ 웹후크 주소는 비밀이다 — 화면 · 로그에 찍지 않는다.
★ 예외를 밖으로 안 던진다(send 는 (성공여부, 설명) 을 돌려준다). 알림이 작업을 죽이면 안 된다.
"""
import json, os, sys, urllib.request, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.join(HERE, "..", ".env")


def _url():
    if not os.path.exists(ENV):
        return ""
    for line in open(ENV, encoding="utf-8"):
        line = line.strip()
        if line.startswith("SLACK_WEBHOOK_URL="):
            return line.split("=", 1)[1].strip()
    return ""


def send(text=None, blocks=None):
    """text 는 꼭 넣는다(알림 미리보기 · blocks 를 못 그리는 곳에서 쓰임)."""
    url = _url()
    if not url:
        return False, ".env 에 SLACK_WEBHOOK_URL 이 없음"
    body = {"text": (text or "")[:3000]}
    if blocks:
        body["blocks"] = blocks
    try:
        req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=20) as r:
            res = r.read().decode("utf-8", "replace")
        return (res.strip() == "ok"), res.strip()[:200]
    except Exception as e:
        detail = ""
        try: detail = e.read().decode("utf-8", "replace")[:200]
        except Exception: pass
        return False, f"{type(e).__name__} {detail}".strip()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9)))
        ok, why = send(f":white_check_mark: 터무니 리포트 시험 메시지 — {now:%Y-%m-%d %H:%M} KST\n"
                       "이 채널로 매일 한 번 API 상태 · 배치 결과 · 이용 현황이 옵니다.")
    elif len(sys.argv) > 1:
        ok, why = send(" ".join(sys.argv[1:]))
    else:
        sys.exit(__doc__)
    print("보냄" if ok else "못 보냄 - " + why)
    sys.exit(0 if ok else 1)
