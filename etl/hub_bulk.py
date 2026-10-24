# -*- coding: utf-8 -*-
"""hub_bulk - 건축HUB '대용량 제공 서비스' 전국 월별 파일 받기  2026-10-24

  사장님 "건대장 옛날걸 건축허브 사이트에서 엑셀로 다 주는데 확인해봐 → ㄱㄱ".
  확인: hub.go.kr 대용량 제공 = 세움터 현황을 **매달 그대로 뜬 전국 파일**(익월 20일). 목록에는 **최근 3개월**만 남는다.
  → 지난 3개월을 지금 받고, 다음부터는 매달 받아 쌓는다(그 자체가 월별 버전 = 변경 로그의 재료).

  py hub_bulk.py --list                                  목록만(분류 · 이름 · 월 · 파일)
  py hub_bulk.py --cat 건축물대장 폐쇄말소대장 건축인허가 주택인허가 --workers 4
  py hub_bulk.py --cat 건축물대장 --only 표제부 --month 2026-09

  ★ 사이트 절차 그대로: 목록 → 이용목적 기록(idx-srvc-hstry-insert, 목적 1 = 웹사이트개발) → 파일 받기(fileOpnDown).
  ★ 받는 곳: deploy/bulk/hub/<YYYYMM>/<원래 파일 이름>.zip — DB 컨테이너 안에서는 /bulk/hub/… (docker-compose 의 ./bulk)
  ★ 이미 같은 크기로 받은 파일은 건너뛴다. 덜 받은 파일(.part)은 처음부터 다시.
"""
import argparse, json, os, re, sys, threading, time, urllib.parse
from concurrent.futures import ThreadPoolExecutor
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "deploy", "bulk", "hub")
B = "https://www.hub.go.kr"
LIST = B + "/portal/opn/lps/idx-lgcpt-pvsn-srvc-list.do"
lock = threading.Lock()


def 세션():
    s = requests.Session()
    s.headers["User-Agent"] = "Mozilla/5.0 (Teomoony non-commercial)"
    r = s.get(LIST + "?pageIndex=1", timeout=60)
    t = re.search(r'name="_csrf" content="([^"]+)"', r.text).group(1)
    return s, t


def 목록(s):
    items, p = [], 1
    while True:
        h = s.get(LIST + f"?pageIndex={p}", timeout=60).text
        found = 0
        for li in re.findall(r"<li>(.*?)</li>", h, re.S):
            cat = re.search(r'class="tagset[^"]*">([^<]+)<', li)
            tit = re.search(r'<p class="tit">([^<]+)</p>', li)
            dl = re.search(r"fnDownloadPop\('(\d+)','(\d+)','(OPN\d+)'\)", li)
            if cat and tit and dl:
                m = re.search(r"\((\d{4})년 (\d{2})월\)", tit.group(1))
                items.append(dict(cat=cat.group(1).strip(), tit=tit.group(1).strip(),
                                  이름=re.sub(r"\s*\(.*\)\s*$", "", tit.group(1)).strip(),
                                  월=(m.group(1) + m.group(2)) if m else None, a=dl.group(1), b=dl.group(2), f=dl.group(3)))
                found += 1
        if not found:
            return items
        p += 1


def 받기(s, t, it):
    d = os.path.join(OUT, it["월"] or "기타"); os.makedirs(d, exist_ok=True)
    s.post(B + "/portal/opn/lps/idx-srvc-hstry-insert.do",
           data={"opnLgcptTaskSeCd": it["a"], "opnTaskCd": it["b"], "opnPrcusePrpsCd": "1", "_csrf": t},
           headers={"X-CSRF-TOKEN": t, "X-Requested-With": "XMLHttpRequest"}, timeout=60)
    with s.post(B + "/cmm/fms/fileOpnDown.do", data={"srvrFileNm": it["f"], "_csrf": t}, stream=True, timeout=(60, 600)) as r:
        r.raise_for_status()
        cd = r.headers.get("Content-Disposition", "")
        nm = urllib.parse.unquote_plus(cd.split("filename=")[-1].strip('"')) if "filename=" in cd else it["f"] + ".zip"
        n = int(r.headers.get("Content-Length") or 0)
        path = os.path.join(d, nm)
        if os.path.exists(path) and n and os.path.getsize(path) == n:
            with lock: print(f"  = 이미 받음  {it['cat']} {it['tit']}  {n/1e6:,.0f}MB", flush=True)
            return path, n, True
        t0 = time.time(); got = 0
        with open(path + ".part", "wb") as f:
            for ch in r.iter_content(1 << 20):
                f.write(ch); got += len(ch)
        if n and got != n:
            raise RuntimeError(f"크기 다름 {got} != {n}")
        os.replace(path + ".part", path)
        with lock: print(f"  ✔ {it['cat']} {it['tit']}  {got/1e6:,.0f}MB  {time.time()-t0:.0f}초", flush=True)
        return path, got, False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--cat", nargs="*", default=["건축물대장", "폐쇄말소대장", "건축인허가", "주택인허가"])
    ap.add_argument("--only", nargs="*", help="이름(표제부 · 전유부 …)만")
    ap.add_argument("--month", nargs="*", help="YYYY-MM (생략하면 목록에 있는 달 전부)")
    ap.add_argument("--workers", type=int, default=4)
    a = ap.parse_args()
    s, t = 세션()
    items = 목록(s)
    json.dump(items, open(os.path.join(HERE, "_export", "hub_items.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    want = [i for i in items if i["cat"] in a.cat and (not a.only or i["이름"] in a.only)
            and (not a.month or (i["월"] and f"{i['월'][:4]}-{i['월'][4:]}" in a.month))]
    print(f"목록 {len(items)} · 받을 것 {len(want)} · 스레드 {a.workers}", flush=True)
    if a.list:
        for i in want: print(f"  {i['월']} {i['cat']:8s} {i['이름']}")
        return
    bad = []
    def one(it):
        for k in range(3):
            try:
                ss, tt = 세션()     # 파일마다 새 세션(긴 다운로드 중 토큰이 만료되지 않게)
                return 받기(ss, tt, it)
            except Exception as e:
                with lock: print(f"  ! {it['cat']} {it['tit']} — {str(e)[:120]} (다시 {k+1})", flush=True)
                time.sleep(10 * (k + 1))
        bad.append(it)
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        res = [r for r in ex.map(one, want) if r]
    tot = sum(r[1] for r in res)
    print(f"\n끝 {(time.time()-t0)/60:.1f}분 · {len(res)}개 · {tot/1e9:,.1f}GB · 실패 {len(bad)}", flush=True)
    for b in bad: print(f"  !! {b['cat']} {b['tit']}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
