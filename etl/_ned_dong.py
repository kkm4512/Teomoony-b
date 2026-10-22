# -*- coding: utf-8 -*-
"""_ned_dong - NED 공동주택가격을 **법정동(10자리) 앞자리로** 받는다 (2026-10-22 실측: pnu=10자리도 받아 줌, 1000행 0.2초)
   필지 하나씩(1.7초/필지)보다 수십 배 빠르다. 받은 것 중 대상 필지(연립·다세대 호가 있는 필지)만 남긴다.
   ★ 한 동의 쪽을 다 모아 **원문 행 수 = totalCount** 가 아니면 그 동은 버린다(넣지 않음).
   ★ 쪽 순서가 흔들리면 행 수는 맞아도 빠지고 겹칠 수 있다 → 첫 동에서 필지별 받기와 **행 묶음이 같은지** 대조했다(CONTEXT)."""
import gzip, io, json, os, sys, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import load_ned_aphus as N
RAW = os.path.join(HERE, "_ned_dong"); os.makedirs(RAW, exist_ok=True)


def page(dong, p):
    q = urllib.parse.urlencode({"key": N.KEY, "domain": N.DOM, "pnu": dong, "format": "json", "numOfRows": "1000", "pageNo": str(p)})
    last = None
    for t in range(6):
        try:
            j = json.loads(urllib.request.urlopen(N.URL + "?" + q, timeout=90).read().decode("utf-8", "replace"))
            a = j.get("apartHousingPrices")
            if not a:
                if str((j.get("response") or {}).get("totalCount", "")) == "0": return 0, []
                raise RuntimeError("이상한 응답 " + json.dumps(j, ensure_ascii=False)[:80])
            f = a.get("field") or []
            return int(a.get("totalCount") or 0), ([f] if isinstance(f, dict) else f)
        except Exception as ex:
            last = str(ex).replace(N.KEY, "***")[:100]; time.sleep(1.5 * (t + 1))
    raise RuntimeError(last)


def dong_all(dong, ex):
    tot, rows = page(dong, 1)
    n = -(-tot // 1000)
    for _, r in ex.map(lambda p: page(dong, p), range(2, n + 1)): rows += r
    return tot, rows


def pnu_all(p):
    """한 필지. ★ 1000행이 넘으면 쪽 순서가 흔들려(같은 행이 두 쪽에 · 어떤 행은 안 옴 — 2026-10-22 실측: 3,150행 필지에서
       쪽 100이면 고유 키 2,575 · 300이면 2,631 · 1000이면 2,645, 합치면 2,646) **해(stdrYear)마다 한 쪽**으로 받는다.
       한 해가 1000행을 넘거나 해별 합이 totalCount 와 다르면 실패(넣지 않음)."""
    q = lambda **k: urllib.parse.urlencode({"key": N.KEY, "domain": N.DOM, "pnu": p, "format": "json", "numOfRows": "1000", "pageNo": "1", **k})
    def get(**k):
        last = None
        for t in range(6):
            try:
                j = json.loads(urllib.request.urlopen(N.URL + "?" + q(**k), timeout=90).read().decode("utf-8", "replace"), strict=False)   # 원문에 제어문자가 섞인 필지가 있다(2026-10-22, 3건) — 글자는 그대로 둔다
                a = j.get("apartHousingPrices")
                if not a:
                    if str((j.get("response") or {}).get("totalCount", "")) == "0": return 0, []
                    raise RuntimeError("이상한 응답 " + json.dumps(j, ensure_ascii=False)[:80])
                f = a.get("field") or []
                return int(a.get("totalCount") or 0), ([f] if isinstance(f, dict) else f)
            except Exception as ex:
                last = str(ex).replace(N.KEY, "***")[:100]; time.sleep(1.5 * (t + 1))
        raise RuntimeError(last)
    tot, rows = get()
    if tot <= 1000:
        if len(rows) != tot: raise RuntimeError(f"한 쪽 {len(rows)} ≠ {tot}")
        return rows
    yrs = sorted({x.get("stdrYear") for x in rows if x.get("stdrYear")})
    lo = min(int(min(yrs)), 2006) if yrs else 2006
    out = []; s = 0
    for y in range(lo, int(time.strftime("%Y")) + 1):
        t, r = get(stdrYear=str(y))
        if t > 1000: raise RuntimeError(f"{y}년 {t}행 > 1000 — 해 하나도 한 쪽에 안 들어감")
        if len(r) != t: raise RuntimeError(f"{y}년 {len(r)} ≠ {t}")
        out += r; s += t
    if s != tot: raise RuntimeError(f"해별 합 {s} ≠ totalCount {tot}")
    return out
