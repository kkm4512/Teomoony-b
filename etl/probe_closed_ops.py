# -*- coding: utf-8 -*-
"""probe_closed_ops - 폐쇄말소대장(ShtRgstHubService) 오퍼레이션 이름·칸 확인용 (2026-10-23). 가락시영(송파 가락동 479) 한 곳만 묻는다. DB 에 안 쓴다.
   키 = .env DATA_GO_KR_KEY — 화면·로그에 안 찍는다."""
import io, json, os, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
E = {}
for line in io.open(os.path.join(HERE, "..", ".env"), encoding="utf-8-sig"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); E[k.strip()] = v.strip().strip('"')
KEY = E.get("DATA_GO_KR_KEY", "")
BASE = "https://apis.data.go.kr/1613000/ShtRgstHubService/"
OPS = ["getSrTitleInfo", "getSrRecapTitleInfo", "getSrBasisOulnInfo", "getSrFlrOulnInfo", "getSrAtchJibunInfo",
       "getSrExposPubuseAreaInfo", "getSrWclfInfo", "getSrHsprcInfo", "getSrExposInfo", "getSrJijiguInfo"]
for op in OPS:
    q = urllib.parse.urlencode({"sigunguCd": "11710", "bjdongCd": "10700", "platGbCd": "0", "bun": "0479", "ji": "0000",
                                "numOfRows": 3, "pageNo": 1, "_type": "json"})
    try:
        raw = urllib.request.urlopen(BASE + op + "?serviceKey=" + KEY + "&" + q, timeout=60).read().decode("utf-8", "replace")
        try:
            j = json.loads(raw); rsp = j.get("response") or {}; h = rsp.get("header") or {}; b = rsp.get("body") or {}
            it = (b.get("items") or {}).get("item") if isinstance(b.get("items"), dict) else None
            if isinstance(it, dict): it = [it]
            print(f"{op}: code={h.get('resultCode')} msg={h.get('resultMsg')} total={b.get('totalCount')} 칸={sorted((it or [{}])[0].keys())}")
            if it: print("   예:", json.dumps(it[0], ensure_ascii=False)[:600])
        except Exception:
            print(f"{op}: JSON 아님 {raw[:200].replace(KEY, '***')}")
    except Exception as ex:
        print(f"{op}: 실패 {str(ex).replace(KEY, '***')[:150]}")
