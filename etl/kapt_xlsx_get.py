# -*- coding: utf-8 -*-
"""kapt_xlsx_get - K-apt 자료실(소통마당 › 자료실 › 관리비정보)의 연도별 '관리비공개의무단지 관리비정보' 엑셀을 받는다  2026-10-31

  py kapt_xlsx_get.py --board 123541            (2025년 글 · 첨부 1번)
  ★ 공식 자료실의 첨부파일 내려받기(게시판이 주 1회 다시 올림). 화면을 긁지 않는다 — 게시글 → 첨부 목록 → 첨부 받기, 사람이 누르는 것과 같은 세 번.
  ★ 받은 파일은 ../data/kapt_cost_xlsx/ 에 원래 이름 그대로. 덮어쓰지 않는다(같은 이름이 있으면 건너뜀).
"""
import argparse, os, re, sys, urllib.parse
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "data", "kapt_cost_xlsx")
BASE = "https://www.k-apt.go.kr"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--board", action="append", required=True)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    s = requests.Session()
    s.headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Teomoony-data (nayoun440@naver.com)"
    rc = 0
    for b in a.board:
        # 목록 쪽(토큰) → 글 보기(POST — 사람이 제목을 누를 때와 같다) → 첨부 목록 → 첨부
        l = s.get(f"{BASE}/web/board/webReference/boardList.do", timeout=60)
        tok = lambda h: (re.search(r'<meta\s+name="_csrf"\s+content="([^"]+)"', h) or re.search(r'name="_csrf"\s+value="([^"]+)"', h))
        m = tok(l.text); csrf = m.group(1) if m else ""
        v = s.post(f"{BASE}/web/board/webReference/boardView.do", data={"seq": b, "boardSecret": "0", "boardType": "03", "pageNo": "1", "keyword": "",
                   "board_pwd": "", "scodeT": "03", "_csrf": csrf}, headers={"Referer": l.url}, timeout=60)
        m = tok(v.text); csrf = m.group(1) if m else csrf
        form = {"boardType": "03", "pageNo": "1", "stype": "", "keyword": "", "seq": b, "scode": "03", "boardPwd": "", "_csrf": csrf}
        # 첨부 목록: 화면(KAPT.submit)처럼 JSON 본문 + X-CSRF-TOKEN 머리
        r = s.post(f"{BASE}/web/board/webReference/fileListData.do?seq=BOARD_FILE", json=form,
                   headers={"X-CSRF-TOKEN": csrf, "Referer": v.url, "Accept": "application/json, */*"}, timeout=60)
        try: files = r.json().get("data") or []
        except Exception: print(f"  !! {b} 첨부 목록 못 읽음 {r.status_code} {r.text[:200]}"); rc = 1; continue
        for f in files:
            name = f.get("fileName"); key = f.get("seq")
            dst = os.path.join(OUT, name)
            if os.path.exists(dst): print(f"  있음 {name}"); continue
            d = s.get(f"{BASE}/cmm/file/BOARD/fileDownload.do", params={"key": key, "fileName": name}, headers={"Referer": v.url}, timeout=600, stream=True)
            ct = d.headers.get("Content-Type", "")
            if d.status_code != 200 or "html" in ct:
                print(f"  !! {name} 받기 실패 {d.status_code} {ct}"); rc = 1; continue
            n = 0
            with open(dst + ".part", "wb") as w:
                for ch in d.iter_content(1 << 20): w.write(ch); n += len(ch)
            os.replace(dst + ".part", dst)
            print(f"  받음 {name} {n/1e6:.1f}MB", flush=True)
    sys.exit(rc)


if __name__ == "__main__":
    main()
