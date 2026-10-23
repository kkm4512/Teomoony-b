# -*- coding: utf-8 -*-
"""probe_closed_ops2 - 폐쇄 기본개요 · 주택가격의 칸을 **여러 줄 · XML 원문**으로 다시 확인 (2026-10-23 사장님 "정말 확실해?"). DB 에 안 쓴다. 키는 안 찍는다."""
import io, json, os, re, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
E = {}
for line in io.open(os.path.join(HERE, "..", ".env"), encoding="utf-8-sig"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); E[k.strip()] = v.strip().strip('"')
KEY = E.get("DATA_GO_KR_KEY", "")
def get(base, op, typ, rows=100, page=1, **kw):
    p = {"sigunguCd": "11710", "bjdongCd": "10700", "platGbCd": "0", "bun": "0479", "ji": "0000", "numOfRows": rows, "pageNo": page}
    p.update(kw)
    if typ: p["_type"] = typ
    return urllib.request.urlopen(base + op + "?serviceKey=" + KEY + "&" + urllib.parse.urlencode(p), timeout=60).read().decode("utf-8", "replace")
SR = "https://apis.data.go.kr/1613000/ShtRgstHubService/"
BR = "https://apis.data.go.kr/1613000/BldRgstHubService/"
for op in ["getSrBasisOulnInfo", "getSrHsprcInfo"]:
    keys = {}; kinds = {}
    for page in (1, 2, 30, 70):
        j = json.loads(get(SR, op, "json", 100, page))
        it = ((j.get("response") or {}).get("body") or {}).get("items") or {}
        it = it.get("item", []) if isinstance(it, dict) else []
        if isinstance(it, dict): it = [it]
        for x in it:
            for k, v in x.items():
                keys.setdefault(k, set()).add(str(v)[:30])
            kinds[x.get("regstrKindCdNm")] = kinds.get(x.get("regstrKindCdNm"), 0) + 1
    print(f"== {op} JSON 칸 {len(keys)}개 · 종류 {kinds}")
    for k in sorted(keys): print(f"   {k}: {sorted(keys[k])[:4]}")
    x = get(SR, op, None, 2, 1)
    tags = sorted(set(re.findall(r"<([A-Za-z]+)>", x)))
    print(f"== {op} XML 태그: {tags}")
    print("   XML 앞:", x[:900].replace(KEY, "***"))
# 지금 대장 같은 오퍼레이션 — 비교용(가락동 479 지금 대장 = 헬리오시티)
for op in ["getBrBasisOulnInfo", "getBrHsprcInfo"]:
    try:
        x = get(BR, op, None, 2, 1)
        print(f"== (비교) {op} XML 태그: {sorted(set(re.findall(r'<([A-Za-z]+)>', x)))}")
    except Exception as ex:
        print(f"== (비교) {op} 실패 {str(ex)[:100]}")
