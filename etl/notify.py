#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
notify - 배치가 끝나면 카카오톡 '나와의 채팅'으로 알린다

왜 이걸로 하나
---------------------------------------------------------------
적재가 한두 시간씩 걸리는데 사람이 터미널을 보고 있을 이유가 없다.
Claude 쪽 푸시를 먼저 시도했으나 **전달됐는지 확인할 방법이 없어** 접었다.
이쪽은 이 PC 에서 직접 쏘고 **응답 코드로 성공을 확인**할 수 있다.

준비 (한 번만)
---------------------------------------------------------------
  1. https://developers.kakao.com 에서 앱 생성
  2. 카카오 로그인 활성화 + Redirect URI 등록 (예: https://localhost)
  3. 동의항목에서 **카카오톡 메시지 전송(talk_message)** 켜기
  4. py notify.py --auth            <- 주소가 나온다. 브라우저로 열고 로그인
  5. 돌아온 주소의 code= 값을 복사해서
     py notify.py --code <코드>     <- .env 에 리프레시 토큰을 적어 준다
  6. py notify.py --test            <- 카톡이 오면 끝

텔레그램도 쓸 수 있다 (더 간단하다)
---------------------------------------------------------------
  1. 텔레그램에서 @BotFather 에게 /newbot  -> 토큰을 준다
  2. .env 에 TELEGRAM_BOT_TOKEN=<토큰>
  3. 만든 봇과 대화를 열고 아무 말이나 한 번 보낸다 (이게 있어야 chat_id 가 생긴다)
  4. py notify.py --tg-chat        <- chat_id 를 찾아 .env 에 적는다
  5. py notify.py --test

★ 카카오와 달리 **토큰이 만료되지 않는다.** 갱신 로직이 필요 없다.
★ 둘 다 설정돼 있으면 **둘 다** 보낸다. 하나만 있으면 그것만 보낸다.

.env 에 들어가는 것
  KAKAO_REST_API_KEY=...
  KAKAO_REDIRECT_URI=https://localhost
  KAKAO_CLIENT_SECRET=...        (콘솔에서 켰다면. 기본 활성이다)
  KAKAO_REFRESH_TOKEN=...        (--code 가 적어 준다)
  TELEGRAM_BOT_TOKEN=...         (BotFather 가 준다)
  TELEGRAM_CHAT_ID=...           (--tg-chat 이 적어 준다)

★ 액세스 토큰은 몇 시간이면 만료된다. 그래서 **리프레시 토큰만 보관**하고
  보낼 때마다 갱신한다. 갱신된 액세스 토큰은 .kakao_token.json 에 캐시한다.
★ 리프레시 토큰도 60일이면 만료된다. 남은 기간이 한 달 미만이면 갱신 응답에
  새 리프레시 토큰이 같이 오므로, 그때 .env 를 갱신한다.
★ 알림이 적재를 죽이면 안 된다. 이 모듈은 **어떤 예외도 밖으로 안 던진다.**
"""
import json, os, sys, time, urllib.parse, urllib.request

HERE  = os.path.dirname(os.path.abspath(__file__))
ENV   = os.path.join(HERE, "..", ".env")
CACHE = os.path.join(HERE, ".kakao_token.json")

AUTH_URL  = "https://kauth.kakao.com/oauth/authorize"
TOKEN_URL = "https://kauth.kakao.com/oauth/token"
SEND_URL  = "https://kapi.kakao.com/v2/api/talk/memo/default/send"
TG_API    = "https://api.telegram.org/bot{token}/{method}"


def load_env():
    d = {}
    if os.path.exists(ENV):
        for line in open(ENV, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def set_env(key, value):
    """`.env` 의 한 줄만 바꾼다. 없으면 끝에 붙인다."""
    lines = []
    if os.path.exists(ENV):
        lines = open(ENV, encoding="utf-8").read().split("\n")
    hit = False
    for i, l in enumerate(lines):
        if l.strip().startswith(key + "="):
            lines[i] = f"{key}={value}"; hit = True; break
    if not hit:
        if lines and lines[-1].strip() != "":
            lines.append("")
        lines.append(f"{key}={value}")
    open(ENV, "w", encoding="utf-8").write("\n".join(lines))


def _post(url, data):
    body = urllib.parse.urlencode(data).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type",
                   "application/x-www-form-urlencoded;charset=utf-8")
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.status, json.loads(r.read().decode("utf-8") or "{}")


def _access_token(env):
    """캐시가 살아 있으면 쓰고, 아니면 리프레시 토큰으로 새로 받는다."""
    try:
        if os.path.exists(CACHE):
            c = json.load(open(CACHE, encoding="utf-8"))
            if c.get("expires_at", 0) > time.time() + 60:
                return c["access_token"]
    except Exception:
        pass

    rt = env.get("KAKAO_REFRESH_TOKEN", "")
    key = env.get("KAKAO_REST_API_KEY", "")
    if not rt or not key:
        raise RuntimeError("KAKAO_REST_API_KEY / KAKAO_REFRESH_TOKEN 이 .env 에 없습니다. "
                           "py notify.py --auth 부터 하세요.")

    data = {"grant_type": "refresh_token", "client_id": key, "refresh_token": rt}
    if env.get("KAKAO_CLIENT_SECRET"):
        data["client_secret"] = env["KAKAO_CLIENT_SECRET"]
    _, body = _post(TOKEN_URL, data)

    at = body.get("access_token")
    if not at:
        raise RuntimeError(f"토큰 갱신 실패: {body}")
    json.dump({"access_token": at,
               "expires_at": time.time() + int(body.get("expires_in", 3600))},
              open(CACHE, "w", encoding="utf-8"))

    # ★ 리프레시 토큰은 남은 기간이 한 달 미만일 때만 새로 온다. 오면 갈아 끼운다.
    if body.get("refresh_token"):
        set_env("KAKAO_REFRESH_TOKEN", body["refresh_token"])
        print("  (리프레시 토큰이 갱신되어 .env 에 반영했습니다)")
    return at


def _tg(env, method, data):
    token = env.get("TELEGRAM_BOT_TOKEN", "")
    body = urllib.parse.urlencode(data).encode("utf-8")
    req = urllib.request.Request(TG_API.format(token=token, method=method),
                                 data=body, method="POST")
    req.add_header("Content-Type",
                   "application/x-www-form-urlencoded;charset=utf-8")
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode("utf-8") or "{}")


def send_telegram(text):
    """텔레그램 보내기. 돌려주는 것: (성공여부, 설명)"""
    try:
        env = load_env()
        if not env.get("TELEGRAM_BOT_TOKEN") or not env.get("TELEGRAM_CHAT_ID"):
            return None, "텔레그램 설정 없음"
        res = _tg(env, "sendMessage",
                  {"chat_id": env["TELEGRAM_CHAT_ID"], "text": text[:4000]})
        if res.get("ok"):
            return True, "전송됨"
        return False, f"응답이 성공이 아님: {res}"
    except Exception as e:
        detail = ""
        try: detail = e.read().decode("utf-8")[:300]
        except Exception: pass
        return False, f"{type(e).__name__}: {e} {detail}".strip()


def send(text, link=None, quiet=True):
    """설정된 **모든** 경로로 보낸다. 돌려주는 것: (하나라도 성공했나, 설명)

    ★ 예외를 밖으로 안 던진다. 알림이 적재를 죽이면 안 된다.
    ★ 하나가 실패해도 다른 경로는 시도한다 — 알림은 중복이 누락보다 낫다.
    """
    results = []
    ok_any = False
    for name, fn in (("카톡", lambda: send_kakao(text, link)),
                     ("텔레그램", lambda: send_telegram(text))):
        ok, why = fn()
        if ok is None:          # 설정 자체가 없음 — 실패로 치지 않는다
            continue
        results.append(f"{name} {'성공' if ok else '실패(' + why + ')'}")
        ok_any = ok_any or ok
    if not results:
        return False, "설정된 알림 경로가 없습니다 (py notify.py --auth 또는 --tg-chat)"
    return ok_any, " · ".join(results)


def send_kakao(text, link=None):
    """카톡 보내기. 돌려주는 것: (성공여부, 설명). 설정이 없으면 (None, 사유)."""
    try:
        env = load_env()
        if not env.get("KAKAO_REFRESH_TOKEN"):
            return None, "카카오 설정 없음 (py notify.py --auth)"
        at = _access_token(env)
        obj = {"object_type": "text",
               "text": text[:900],
               "link": {"web_url": link or "https://developers.kakao.com",
                        "mobile_web_url": link or "https://developers.kakao.com"}}
        body = urllib.parse.urlencode(
            {"template_object": json.dumps(obj, ensure_ascii=False)}).encode("utf-8")
        req = urllib.request.Request(SEND_URL, data=body, method="POST")
        req.add_header("Authorization", f"Bearer {at}")
        req.add_header("Content-Type",
                       "application/x-www-form-urlencoded;charset=utf-8")
        with urllib.request.urlopen(req, timeout=15) as r:
            res = json.loads(r.read().decode("utf-8") or "{}")
        # 문서상 성공이면 result_code 가 0 이다.
        if res.get("result_code") == 0:
            return True, "전송됨"
        return False, f"응답이 성공이 아님: {res}"
    except Exception as e:
        detail = ""
        try:
            detail = e.read().decode("utf-8")[:300]     # HTTPError 본문
        except Exception:
            pass
        return False, f"{type(e).__name__}: {e} {detail}".strip()


# ============================================================
def main():
    import argparse
    ap = argparse.ArgumentParser(description="카카오톡 '나에게 보내기'")
    ap.add_argument("--auth", action="store_true", help="로그인 주소를 만든다")
    ap.add_argument("--code", help="돌아온 주소의 code= 값")
    ap.add_argument("--test", action="store_true", help="시험 발송")
    ap.add_argument("--tg-chat", action="store_true",
                    help="텔레그램 chat_id 를 찾아 .env 에 적는다")
    ap.add_argument("--text", help="보낼 내용")
    a = ap.parse_args()
    env = load_env()

    if a.auth:
        key = env.get("KAKAO_REST_API_KEY", "")
        uri = env.get("KAKAO_REDIRECT_URI", "https://localhost")
        if not key:
            sys.exit(".env 에 KAKAO_REST_API_KEY 를 먼저 넣으세요.")
        q = urllib.parse.urlencode({"client_id": key, "redirect_uri": uri,
                                    "response_type": "code",
                                    "scope": "talk_message"})
        print("\n아래 주소를 브라우저로 여세요. 로그인하면 주소창에 code= 가 붙습니다.\n")
        print(f"  {AUTH_URL}?{q}\n")
        print("그 code 값을 복사해서:  py notify.py --code <코드>\n")
        return

    if a.code:
        data = {"grant_type": "authorization_code",
                "client_id": env.get("KAKAO_REST_API_KEY", ""),
                "redirect_uri": env.get("KAKAO_REDIRECT_URI", "https://localhost"),
                "code": a.code}
        if env.get("KAKAO_CLIENT_SECRET"):
            data["client_secret"] = env["KAKAO_CLIENT_SECRET"]
        try:
            _, body = _post(TOKEN_URL, data)
        except Exception as e:
            detail = ""
            try: detail = e.read().decode("utf-8")[:400]
            except Exception: pass
            sys.exit(f"토큰 발급 실패: {e} {detail}")
        if not body.get("refresh_token"):
            sys.exit(f"리프레시 토큰이 안 왔습니다: {body}")
        set_env("KAKAO_REFRESH_TOKEN", body["refresh_token"])
        json.dump({"access_token": body["access_token"],
                   "expires_at": time.time() + int(body.get("expires_in", 3600))},
                  open(CACHE, "w", encoding="utf-8"))
        print(".env 에 KAKAO_REFRESH_TOKEN 을 적었습니다.")
        print("이제:  py notify.py --test")
        return

    if a.tg_chat:
        token = env.get("TELEGRAM_BOT_TOKEN", "")
        if not token:
            sys.exit(".env 에 TELEGRAM_BOT_TOKEN 을 먼저 넣으세요.\n"
                     "  텔레그램에서 @BotFather 에게 /newbot 하면 줍니다.")
        try:
            res = _tg(env, "getUpdates", {})
        except Exception as e:
            sys.exit(f"조회 실패: {e}")
        chats = {}
        for u in res.get("result", []):
            m = u.get("message") or u.get("channel_post") or {}
            c = m.get("chat") or {}
            if c.get("id"):
                nm = c.get("title") or " ".join(
                    x for x in (c.get("first_name"), c.get("last_name")) if x) \
                    or c.get("username") or "?"
                chats[c["id"]] = nm
        if not chats:
            sys.exit("대화 기록이 없습니다.\n"
                     "  ★ 만든 봇을 텔레그램에서 찾아 **먼저 아무 말이나 한 번 보내세요.**\n"
                     "    봇은 먼저 말을 걸 수 없어서, 사용자가 말을 걸어야 chat_id 가 생깁니다.")
        for cid, nm in chats.items():
            print(f"  {cid}  {nm}")
        cid = list(chats)[0]
        set_env("TELEGRAM_CHAT_ID", str(cid))
        print(f"\n.env 에 TELEGRAM_CHAT_ID={cid} 를 적었습니다.")
        print("이제:  py notify.py --test")
        return

    text = a.text or "터무니 알림 시험입니다. 이게 보이면 설정이 끝난 겁니다."
    ok, why = send(text)
    print(("성공 — " if ok else "실패 — ") + why)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
