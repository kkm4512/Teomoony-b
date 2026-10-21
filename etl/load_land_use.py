# -*- coding: utf-8 -*-
"""load_land_use - 토지이용계획(VWorld NED getLandUseAttr) 적재  2026-10-21

  py load_land_use.py                       단지 대표 필지(세대 있는 단지) 중 아직 안 받은 것
  py load_land_use.py --all-complex-pnu     단지에 속한 모든 필지
  py load_land_use.py --limit 1000          앞에서 N 필지만(시험)
  py load_land_use.py --refresh-days 30     받은 지 30일 넘은 필지도 다시

★ API: https://api.vworld.kr/ned/data/getLandUseAttr?pnu=...  — VWORLD_NED_KEY(토지특성과 같은 키, 별도 신청 불필요).
  **필지 하나당 호출 하나** — 대상 수가 곧 호출 수다. 한 번에 1000행까지 받는다(보통 10~40행).
★ 이어받기: silver.land_use_done 에 받은 필지를 적는다. '0건' 도 받은 것이다.
★ 실패를 삼키지 않는다 — 에러 봉투(키·한도)는 즉시, 연속 실패 30번이면 멈추고 종료코드 1.
★ 사라진 지정은 is_current = 0 (지우지 않는다).
"""
import argparse, io, json, os, sys, threading, time
import urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
URL  = "https://api.vworld.kr/ned/data/getLandUseAttr"


def env():
    d = {}
    for line in io.open(ENV, encoding="utf-8-sig"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


class 멈춤(Exception):
    pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all-complex-pnu", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--refresh-days", type=int, default=0)
    ap.add_argument("--workers", type=int, default=6)
    a = ap.parse_args()
    e = env(); key = e.get("VWORLD_NED_KEY", ""); dom = (e.get("VWORLD_DOMAIN") or "teomoony.com").strip()
    if not key: sys.exit(".env 의 VWORLD_NED_KEY 가 비어 있습니다")

    def conn():
        return pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)),
                               user=e.get("DB_USER", "sa"), password=e.get("DB_PASSWORD", ""),
                               database=e.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    c0 = conn(); cur = c0.cursor()
    대상 = ("SELECT DISTINCT cp.pnu FROM gold.complex_pnu cp JOIN gold.complex c ON c.complex_id = cp.complex_id "
           "WHERE c.merged_into IS NULL" if a.all_complex_pnu else
           "SELECT DISTINCT c.rep_pnu FROM gold.complex c WHERE c.merged_into IS NULL AND c.rep_pnu IS NOT NULL "
           "AND c.hhld_cnt_sum > 0")
    덜 = ("AND NOT EXISTS (SELECT 1 FROM silver.land_use_done d WHERE d.pnu = x.pnu"
         + (f" AND d.받은시각 > DATEADD(DAY, -{int(a.refresh_days)}, SYSDATETIME())" if a.refresh_days else "") + ")")
    cur.execute(f"SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT x.pnu FROM ({대상}) x(pnu) WHERE x.pnu IS NOT NULL {덜} ORDER BY x.pnu")
    pnus = [r[0] for r in cur.fetchall()]
    if a.limit: pnus = pnus[:a.limit]
    c0.close()
    print(f"대상 필지 {len(pnus):,} ({'단지의 모든 필지' if a.all_complex_pnu else '세대 있는 단지의 대표 필지'}) · 스레드 {a.workers}", flush=True)
    if not pnus: return

    lock = threading.Lock(); st = {"n": 0, "rows": 0, "fail": 0, "연속": 0, "t0": time.monotonic()}
    local = threading.local()

    def db():
        if not getattr(local, "c", None): local.c = conn()
        return local.c

    def one(pnu):
        if st.get("멈춤"): return
        p = {"key": key, "pnu": pnu, "format": "json", "numOfRows": "1000", "pageNo": "1", "domain": dom}
        j = None
        for t in range(3):
            try:
                with urllib.request.urlopen(URL + "?" + urllib.parse.urlencode(p), timeout=30) as r:
                    j = json.loads(r.read().decode("utf-8")); break
            except Exception as ex:
                err = str(ex); time.sleep(1.5 * (t + 1))
        lu = (j or {}).get("landUses") if isinstance(j, dict) else None
        # ★ 2026-10-22: 지정이 하나도 없는 필지는 landUses 대신 빈 봉투 {"response": {"totalCount": "0", "resultCode": ""}} 가 온다
        #   (실패 178 필지가 전부 이 꼴). 에러 코드가 비어 있고 totalCount 가 0 일 때만 '0건 받음' 으로 본다 — 에러 봉투는 그대로 실패.
        rsp = (j or {}).get("response") if isinstance(j, dict) else None
        if not isinstance(lu, dict) and isinstance(rsp, dict) and str(rsp.get("totalCount")) == "0" \
                and not (rsp.get("resultCode") or "").strip() and not (rsp.get("resultMsg") or "").strip():
            lu = {"field": []}
        if not isinstance(lu, dict):
            msg = json.dumps(j, ensure_ascii=False)[:200] if j else err
            with lock:
                st["fail"] += 1; st["연속"] += 1
                if any(w in msg for w in ("INCORRECT_KEY", "LIMIT", "한도", "UNREGISTERED", "OVER")):
                    st["멈춤"] = f"에러 봉투: {msg}"
                elif st["연속"] >= 30:
                    st["멈춤"] = f"연속 실패 30 — 마지막: {msg}"
            return
        rows = lu.get("field") or []
        c = db(); cu = c.cursor()
        seen = []
        for x in rows:
            mno = (x.get("manageNo") or "").strip() or f"{x.get('prposAreaDstrcCode')}|{x.get('cnflcAt')}"
            seen.append(mno)
            vals = (x.get("prposAreaDstrcCode"), x.get("prposAreaDstrcCodeNm"), x.get("cnflcAt"), x.get("cnflcAtNm"),
                    x.get("regstrSeCodeNm"), x.get("registDt"), x.get("lastUpdtDt"))
            cu.execute("""UPDATE silver.land_use_plan SET 코드=%s, 이름=%s, 저촉=%s, 저촉이름=%s, 대장구분=%s, 등록일=%s, 갱신일=%s,
                            is_current=1, 마지막본시각=SYSDATETIME(), 사라진시각=NULL WHERE pnu=%s AND manage_no=%s""", vals + (pnu, mno))
            if cu.rowcount == 0:
                cu.execute("""INSERT INTO silver.land_use_plan (코드, 이름, 저촉, 저촉이름, 대장구분, 등록일, 갱신일, pnu, manage_no)
                              VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""", vals + (pnu, mno))
        if seen:
            cu.execute("UPDATE silver.land_use_plan SET is_current=0, 사라진시각=SYSDATETIME() WHERE pnu=%s AND is_current=1 AND manage_no NOT IN ("
                       + ",".join(["%s"] * len(seen)) + ")", (pnu,) + tuple(seen))
        else:
            cu.execute("UPDATE silver.land_use_plan SET is_current=0, 사라진시각=SYSDATETIME() WHERE pnu=%s AND is_current=1", (pnu,))
        cu.execute("""UPDATE silver.land_use_done SET 건수=%s, 받은시각=SYSDATETIME() WHERE pnu=%s;
                      IF @@ROWCOUNT = 0 INSERT INTO silver.land_use_done (pnu, 건수) VALUES (%s, %s)""", (len(rows), pnu, pnu, len(rows)))
        c.commit()
        with lock:
            st["n"] += 1; st["rows"] += len(rows); st["연속"] = 0
            if st["n"] % 2000 == 0:
                el = time.monotonic() - st["t0"]; rate = st["n"] / el
                print(f"  {st['n']:,}/{len(pnus):,} 필지 · {st['rows']:,}행 · 실패 {st['fail']} · 초당 {rate:.1f} · "
                      f"남은 {int((len(pnus) - st['n']) / max(rate, 0.1) / 60)}분", flush=True)

    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        list(ex.map(one, pnus))
    el = time.monotonic() - st["t0"]
    print(f"끝 · {st['n']:,}/{len(pnus):,} 필지 · {st['rows']:,}행 · 실패 {st['fail']} · {int(el)}초", flush=True)
    if st.get("멈춤"):
        print(f"! 멈춤: {st['멈춤']} — 다시 돌리면 이어서 받는다", flush=True); sys.exit(1)
    if st["fail"]:
        print(f"! 실패 {st['fail']} 필지 — 다시 돌리면 그 필지만 받는다", flush=True); sys.exit(1)


if __name__ == "__main__":
    main()
