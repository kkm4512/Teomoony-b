# -*- coding: utf-8 -*-
"""
페이지 단위로 나눠 받는 드라이버  (2026-10-19)

왜 만들었나
  지금 병렬 단위는 **법정동**이다. 그런데 공시가격(hsprc)은 한 법정동이
  2,550 페이지를 넘는다. 남은 법정동이 5 개면 스레드를 10 개 줘도 4~5 개만
  일하고 나머지는 논다. 한 동 안에서 **페이지를 갈라** 받으면 그 벽이 없어진다.

  API 는 totalCount 를 주고 pageNo 로 아무 페이지나 집어 올 수 있으니
  원래부터 가능한 일이었다. 못 했던 이유는 **이어받기가 행 수 역산**이라
  순서가 섞이면 조용히 구멍이 나기 때문이었다 (정책 1장).
  meta.load_page 에 받은 페이지를 적게 되면서 그 제약이 풀렸다.

무엇을 하는가
  1. 각 (시군구, 법정동) 의 1 페이지를 받아 totalCount 를 알아낸다
  2. meta.load_page 를 보고 **아직 안 받은 페이지**만 추린다
  3. 그걸 구간으로 묶어 teomoony_ingest.py 에 --from-page/--max-pages/--range-mode
     로 넘긴다. 적재기 자체는 **한 줄도 안 고쳤다** - 빈 페이지 재시도, 교착
     재실행, 건너뛴 행 보고 같은 장치가 그대로 산다
  4. 끝나면 **빠진 페이지를 센다**. 0 이 아니면 그렇다고 말한다

쓰는 법
  py load_pages.py --op getBrHsprcInfo --workers 10
  py load_pages.py --op getBrHsprcInfo --sgg 41173 --bjdong 10100 --workers 10
"""
import argparse, json, os, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor, as_completed

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from teomoony_ingest import db_connect, q                 # noqa: E402

ROWS = 100            # API 상한
CHUNK = 60            # 한 작업이 받을 페이지 수. 작으면 프로세스 띄우는 값이 커진다
lock = threading.Lock()


def ts():
    return time.strftime("%H:%M:%S")


def hms(sec):
    sec = int(sec)
    return f"{sec//60}분{sec%60:02d}초" if sec >= 60 else f"{sec}초"


def load_cfg(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def units_from_plan(cur, op, sgg=None, bjdong=None):
    """어느 (시군구, 법정동) 을 받을지.

    ★ meta.v_load_plan 을 쓴다(2026-10-19). load_target.ops 에는 별칭 말고
      **그룹**(base, ext)이 들어 있을 수 있어서, 직접 LIKE 로 찾으면 조용히
      0 건이 된다. 그 뷰가 이미 그룹을 별칭으로 풀어 준다 - 러너와 같은 눈으로
      봐야 "러너는 할 일이 있다는데 이쪽은 없다" 는 일이 안 생긴다.
    ★ 선행='OK' 를 지킨다. 기본개요가 계층의 단일 진실 공급원이라 그게 먼저다.
    """
    if sgg and bjdong:
        return [(sgg, bjdong, None)]
    sql = """SELECT sgg_cd, bjdong_cd, 법정동
               FROM meta.v_load_plan
              WHERE operation = %s AND 선행 = 'OK'
                AND bjdong_cd IS NOT NULL AND bjdong_cd <> '00000'"""
    prm = [op]
    if sgg:
        sql += " AND sgg_cd = %s"; prm.append(sgg)
    sql += " ORDER BY priority, sgg_cd, bjdong_cd"
    q(cur, sql, tuple(prm))
    seen, out = set(), []
    for r in cur.fetchall():
        k = (r[0], r[1])
        if k in seen:
            continue
        seen.add(k); out.append((r[0], r[1], r[2]))
    return out


def got_pages(cur, sgg, bjd, op):
    """이미 받은 페이지와 그때의 totalCount."""
    q(cur, """SELECT page, status, api_total FROM meta.load_page
               WHERE sgg_cd=%s AND bjdong_cd=%s AND op=%s""", (sgg, bjd, op))
    ok, tot = set(), None
    for pg, st, at in cur.fetchall():
        if st == "OK":
            ok.add(int(pg))
        if at is not None:
            tot = max(tot or 0, int(at))
    return ok, tot


def run_ingest(op, sgg, bjd, frm, to, cfg_path):
    """적재기를 한 구간만 돌린다. 되돌려 주는 것: (성공?, 마지막 줄들)"""
    cmd = [sys.executable, os.path.join(HERE, "teomoony_ingest.py"), "load",
           "--op", op, "--sigungu", sgg, "--bjdong", bjd,
           "--from-page", str(frm), "--max-pages", str(to), "--range-mode",
           "--config", cfg_path]
    p = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    out = (p.stdout or "") + (p.stderr or "")
    return p.returncode == 0, out.strip().splitlines()[-3:]


# ★ 화면에 찍는 **사람이 읽는 이름**. 전에는 "주택가격" 이 박혀 있어서
#   전유공용면적을 받으면서도 "주택가격이 없는 법정동" 이라고 찍었다(2026-10-21 고침).
#   한 글자 틀린 로그는 **틀린 로그**다 — 다음 사람이 그걸 믿고 엉뚱한 데를 판다.
#   size_ops.py 의 OPS 와 같은 표다. 모르는 op 는 op 이름 그대로 쓴다(지어내지 않는다).
작업이름표 = {
    "getBrBasisOulnInfo":       "기본개요",
    "getBrTitleInfo":           "표제부",
    "getBrRecapTitleInfo":      "총괄표제부",
    "getBrAtchJibunInfo":       "부속지번",
    "getBrFlrOulnInfo":         "층별개요",
    "getBrExposInfo":           "전유부",
    "getBrExposPubuseAreaInfo": "전유공용면적",
    "getBrHsprcInfo":           "주택가격",
    "getBrJijiguInfo":          "지역지구",
    "getBrPmsInfo":             "건축허가",
}


def 작업이름(op):
    return 작업이름표.get(op, op)


def 구멍보고(cur, a, t0=None, bad=None):
    """빠진 페이지를 센다. **이 도구의 존재 이유다.**

    ★ 받을 게 없을 때도 부른다 - '다 됐다' 와 '모른다' 는 다르다.
    ★ t0/bad 는 **없을 수 있다**(받을 게 없어 바로 보고만 할 때).
      함수로 빼면서 main 의 지역변수를 그대로 참조해 NameError 를 냈다 -
      "쓰는 쪽에서 안 보이는 이름"을 함수 안에 남겨 두면 그 자리에서 죽는다.
    """
    if t0 is not None:
        print(f"\n[{ts()}] 끝. {hms(time.time()-t0)} · 실패 작업 {bad or 0}개")
    print("--- 빠진 페이지 ---")
    q(cur, """SELECT sgg_cd, bjdong_cd, 받은페이지, 최대페이지, 빠진페이지,
                     빈쪽, 실패, api_total, 받은건수
                FROM meta.v_load_page_gap WHERE op=%s
               ORDER BY 빠진페이지 DESC, 실패 DESC, sgg_cd, bjdong_cd""", (a.op,))
    구멍 = 0; 빈동 = 0
    for sgg, bjd, 받, 최, 빠, 빔, 실, tot, 건 in cur.fetchall():
        기대 = max(1, -(-int(tot or 0) // ROWS)) if tot else None
        부족 = (기대 - 받) if 기대 else None
        구멍 += (빠 or 0) + max(0, 부족 or 0) + (실 or 0)
        # ★ 건수 0 인 동은 **없는 것**이지 실패가 아니다. 한 줄로 접는다.
        if not 건 and not (빠 or 0) and not (실 or 0):
            빈동 += 1
            continue
        flag = "  <-- 확인" if (빠 or 0) or (실 or 0) or (부족 or 0) > 0 else ""
        print(f"  {sgg}/{bjd} 받은 {받:,}쪽 / 기대 {기대 or '?'}쪽 "
              f"· 중간빠짐 {빠} · 빈쪽 {빔} · 실패 {실} · 건수 {건:,}{flag}")
    if 빈동:
        print(f"  ({작업이름(a.op)}이(가) **없는** 법정동 {빈동}곳은 접었습니다 — 실패가 아닙니다)")
    print(f"  => 구멍 합계 {구멍}  " + ("(정상)" if 구멍 == 0 else "** 확인 필요 **"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", default="getBrHsprcInfo")
    ap.add_argument("--sgg", default=None)
    ap.add_argument("--bjdong", default=None)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--chunk", type=int, default=CHUNK)
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--dry-run", action="store_true", help="무엇을 받을지만 보여준다")
    a = ap.parse_args()

    cfg = load_cfg(a.config)
    conn = db_connect(cfg); cur = conn.cursor()
    units = units_from_plan(cur, a.op, a.sgg, a.bjdong)
    if not units:
        sys.exit(f"받을 법정동이 없습니다 (op={a.op})")
    print(f"[{ts()}] {a.op} · 법정동 {len(units)}곳 · 스레드 {a.workers} · "
          f"구간 {a.chunk}쪽")

    # ---- 1) totalCount 를 모르는 곳은 1 페이지를 받아 알아낸다 ----
    모름 = []
    for sgg, bjd, nm in units:
        ok, tot = got_pages(cur, sgg, bjd, a.op)
        if tot is None:
            모름.append((sgg, bjd, nm))
    if 모름:
        print(f"[{ts()}] totalCount 를 모르는 {len(모름)}곳 — 1페이지만 먼저 받습니다")
        with ThreadPoolExecutor(max_workers=min(a.workers, len(모름))) as ex:
            futs = {ex.submit(run_ingest, a.op, s, b, 1, 1, a.config): (s, b, n)
                    for s, b, n in 모름}
            for f in as_completed(futs):
                s, b, n = futs[f]
                ok2, tail = f.result()
                print(f"  [{ts()}] {'OK' if ok2 else '!!'} {s}/{b} {n or ''} 1쪽")

    # ---- 2) 안 받은 페이지를 구간으로 묶는다 ----
    일감 = []
    요약 = []
    for sgg, bjd, nm in units:
        ok, tot = got_pages(cur, sgg, bjd, a.op)
        if tot is None:
            요약.append((sgg, bjd, nm, None, 0, 0))
            continue
        전체쪽 = max(1, -(-int(tot) // ROWS))      # 올림
        남은 = [p for p in range(1, 전체쪽 + 1) if p not in ok]
        요약.append((sgg, bjd, nm, tot, 전체쪽, len(남은)))
        # 이어진 번호끼리 묶고, 묶음이 너무 길면 chunk 로 자른다
        run = []
        for p in 남은:
            if run and p == run[-1] + 1 and len(run) < a.chunk:
                run.append(p)
            else:
                if run:
                    일감.append((sgg, bjd, run[0], run[-1]))
                run = [p]
        if run:
            일감.append((sgg, bjd, run[0], run[-1]))

    print(f"\n[{ts()}] 받을 것")
    for sgg, bjd, nm, tot, 전체, 남 in 요약:
        if tot is None:
            print(f"  {sgg}/{bjd} {nm or '':<8} totalCount 모름 — 건너뜀")
        else:
            print(f"  {sgg}/{bjd} {nm or '':<8} 전체 {전체:,}쪽 "
                  f"(건수 {int(tot):,}) · 남은 {남:,}쪽")
    print(f"  -> 작업 {len(일감):,}개\n")
    if a.dry_run:
        return
    if not 일감:
        # ★ 받을 게 없어도 **구멍 보고서는 찍는다**(2026-10-20). 전에는 그냥
        #   return 해서 체인 요약에 '구멍 ?' 가 떴다 - 다 됐다는 뜻인데
        #   모른다는 뜻으로 보였다. 둘은 다르다.
        print(f"\n[{ts()}] 받을 것이 없습니다 (이미 다 받았습니다)")
        구멍보고(cur, a)
        conn.close()
        return

    # ---- 3) 돌린다 ----
    t0 = time.time()
    done = {"n": 0, "bad": 0}
    PAUSE = os.path.join(HERE, "_pause.flag")

    def one(job):
        sgg, bjd, frm, to = job
        if os.path.exists(PAUSE):
            return False          # 일시정지 - 조용히 건너뛴다(구멍 보고서가 잡는다)
        st = time.time()
        ok2, tail = run_ingest(a.op, sgg, bjd, frm, to, a.config)
        with lock:
            done["n"] += 1
            if not ok2:
                done["bad"] += 1
            print(f"  [{ts()}] {'OK' if ok2 else '!!'} "
                  f"[{done['n']}/{len(일감)}] {sgg}/{bjd} p{frm}~{to} "
                  f"{hms(time.time()-st)}  (전체 {hms(time.time()-t0)})")
            if not ok2:
                for ln in tail:
                    print(f"       {ln}")
        return ok2

    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        list(ex.map(one, 일감))

    구멍보고(cur, a, t0, done['bad'])
    conn.close()


if __name__ == "__main__":
    main()
