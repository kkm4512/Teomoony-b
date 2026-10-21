# -*- coding: utf-8 -*-
"""토지특성 적재 — VWorld NED (국가중점데이터)  2026-10-20

  py load_land_char.py --probe                     한 필지만 떠서 생김새를 본다
  py load_land_char.py --sgg 11140                 그 시군구의 필지 전부
  py load_land_char.py --skip-loaded               이미 받은 PNU 는 건너뛴다
  py load_land_char.py                             필지가 적재된 전부

★ API: https://api.vworld.kr/ned/data/getLandCharacteristics
  우리 VWorld 키로 **그냥 된다**(별도 신청 불필요, 2026-10-20 실측).

★★ 이 API 는 **PNU 전용**이다. 실측으로 확인했다:
     ldCode=1114015200 (법정동 코드) -> 행 0, resultCode 만 돌아온다.
     pnu=...            (연도 생략)  -> 행 18, 그 필지의 **전 연도**가 한 번에 온다.
  그래서 '법정동 단위로 페이지를 넘기는' 다른 적재기와 모양이 다르다.
  **필지 하나당 호출 하나** — 그래서 대상 수가 곧 호출 수다.

★ 연도 생략이 핵심이다. stdrYear 를 주면 그 해만 오므로 14번을 불러야 한다.
  빼면 2013~2026 이 한 번에 온다. 호출이 14배 줄어든다.

★ 같은 연도가 **여러 번** 올 수 있다(실측: 2023년 2건 · 2024년 2건 · 2025년 3건).
  공시지가가 정정된 것이다. **lastUpdtDt 가 가장 최신인 1건만** 남긴다 —
  어느 것이 맞는지 모른 채 둘 다 넣으면, 쓰는 쪽에서 아무거나 집게 된다.
  자연키는 (pnu, base_year) 다.

★ 실패를 삼키지 않는다. 필지 적재기가 fetch 실패를 조용히 건너뛰다가
  446,040 에서 멈췄는데 "OK" 로 보고될 뻔했다(CONTEXT 11-6x). 여기서는
  연속 실패가 쌓이면 **멈추고 말한다.**
"""
import argparse, hashlib, json, os, sys, time
from concurrent.futures import ThreadPoolExecutor
import requests
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.join(HERE, "..", ".env")
URL = "https://api.vworld.kr/ned/data/getLandCharacteristics"

# API 이름 -> 표 칸. 표(silver.land_char)는 이미 있다(02_silver.sql).
F = [("stdrYear", "base_year"), ("stdrMt", "base_month"),
     ("ldCodeNm", "ld_code_nm"), ("mnnmSlno", "mnnm_slno"),
     ("regstrSeCode", "regstr_se_code"),
     ("lndcgrCode", "lndcgr_code"), ("lndcgrCodeNm", "lndcgr_nm"),
     ("lndpclAr", "lndpcl_ar"),
     ("prposArea1Nm", "prpos_area1_nm"), ("prposArea2Nm", "prpos_area2_nm"),
     ("ladUseSittnNm", "lad_use_sittn_nm"),
     ("tpgrphHgCodeNm", "tpgrph_hg_code_nm"),
     ("tpgrphFrmCodeNm", "tpgrph_frm_code_nm"),
     ("roadSideCodeNm", "road_side_code_nm"),
     ("pblntfPclnd", "pblntf_pclnd"), ("lastUpdtDt", "last_updt_dt")]
숫자칸 = {"lndpcl_ar", "pblntf_pclnd"}


def load_env(path):
    d = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
    return d


# ★ VWorld 키는 **등록 도메인에 묶인다**. localhost 로 보내면 INCORRECT_KEY 가 난다.
#   하드코딩하지 않고 .env 의 VWORLD_DOMAIN 을 읽는다(필지 적재기와 같은 규칙).
def vworld_domain(env):
    return (env.get("VWORLD_DOMAIN") or "teomoony.com").strip()


def ts():
    return time.strftime("%H:%M:%S")


def num(v):
    if v is None or str(v).strip() == "":
        return None
    try:
        return float(str(v).replace(",", ""))
    except ValueError:
        return None          # 숫자가 아니면 **비워 둔다**. 0 으로 바꾸지 않는다


def ymd8(v):
    """'2025-08-06' -> '20250806'. 모양이 다르면 **NULL**(억지로 만들지 않는다)."""
    s = "".join(ch for ch in str(v or "") if ch.isdigit())
    return s if len(s) == 8 else None


def fetch(key, domain, pnu, retries=3):
    """그 필지의 **전 연도**를 받는다. 돌려주는 것: (행목록, 오류문구).
       오류문구가 None 이 아니면 **실패**다 — 부르는 쪽이 세야 한다."""
    p = {"key": key, "domain": domain, "pnu": pnu,
         "format": "json", "numOfRows": 200, "pageNo": 1}
    last = None
    for a in range(retries):
        try:
            r = requests.get(URL, params=p, timeout=40)
            if r.status_code != 200:
                last = f"HTTP {r.status_code}"
            else:
                d = r.json()
                root = d.get("landCharacteristicss") or {}
                code = str(root.get("resultCode", ""))
                # ★ 키/도메인이 틀리면 여기서 걸린다. 조용히 0건으로 넘기지 않는다.
                if code and code not in ("00", "0", "NORMAL_SERVICE"):
                    msg = str(root.get("resultMsg", ""))
                    if "INCORRECT" in msg.upper() or "KEY" in msg.upper():
                        raise SystemExit(
                            f"\n★ 키/도메인 문제로 보입니다: {code} {msg}\n"
                            f"  .env 의 VWORLD_DOMAIN 을 확인하세요(지금 '{domain}').\n"
                            f"  키는 **등록한 도메인**에서만 동작합니다.")
                    return [], f"{code} {msg}"
                return (root.get("field") or []), None
        except SystemExit:
            raise
        except Exception as e:
            last = f"{type(e).__name__}: {str(e)[:80]}"
        time.sleep(0.8 * (a + 1))
    return [], last or "알 수 없음"


def 연도별최신(rows):
    """같은 연도가 여러 번 오면 lastUpdtDt 가 가장 최신인 1건만 남긴다.
       ★ 날짜가 없으면 '가장 오래된 것'으로 보고 뒤로 민다 — 날짜가 있는 쪽이
         정정본일 가능성이 높다. 모르는 값을 최신으로 올리지 않는다."""
    best = {}
    for r in rows:
        y = (r.get("stdrYear") or "").strip()
        if len(y) != 4 or not y.isdigit():
            continue                       # 연도를 모르면 **버린다**(자연키가 없다)
        k = ymd8(r.get("lastUpdtDt")) or ""
        if y not in best or k > best[y][0]:
            best[y] = (k, r)
    return [v[1] for v in best.values()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", nargs="*", help="시군구코드 5자리")
    ap.add_argument("--lawd", nargs="*", help="법정동코드 10자리")
    ap.add_argument("--skip-loaded", action="store_true",
                    help="이미 land_char 에 있는 PNU 는 건너뛴다")
    ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--sleep", type=float, default=0.03)
    ap.add_argument("--limit", type=int, help="대상 PNU 수 상한(시험용)")
    ap.add_argument("--probe", action="store_true", help="한 필지만 떠보고 끝낸다")
    ap.add_argument("--max-fail", type=int, default=50,
                    help="연속 실패가 이만큼 쌓이면 멈춘다")
    a = ap.parse_args()

    env = load_env(ENV)
    key = env.get("VWORLD_KEY", "").strip()
    if not key:
        sys.exit(".env 에 VWORLD_KEY 가 없습니다")
    domain = vworld_domain(env)
    print(f"[{ts()}] VWorld domain = {domain}", flush=True)

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()

    # ---- 대상 PNU ----
    # ★ 필지(silver.cadastral_parcel)가 **유일한 출처**다. 필지에 없는 PNU 는
    #   화면에서 쓸 데가 없다(지도에 못 그린다). 그래서 필지 적재가 끝난 만큼만 받는다.
    q = ["SELECT p.pnu FROM silver.cadastral_parcel p WHERE p.is_current = 1"]
    prm = []
    if a.lawd:
        q.append("AND LEFT(p.pnu,10) IN (" + ",".join(["%s"] * len(a.lawd)) + ")")
        prm += list(a.lawd)
    elif a.sgg:
        q.append("AND LEFT(p.pnu,5) IN (" + ",".join(["%s"] * len(a.sgg)) + ")")
        prm += list(a.sgg)
    if a.skip_loaded:
        q.append("""AND NOT EXISTS (SELECT 1 FROM silver.land_char lc
                                     WHERE lc.pnu = p.pnu AND lc.is_current = 1)""")
    q.append("ORDER BY p.pnu")
    cur.execute(" ".join(q), tuple(prm))
    pnus = [r[0] for r in cur.fetchall()]
    if a.limit:
        pnus = pnus[:a.limit]
    if not pnus:
        print("대상 PNU 가 없습니다 (필지가 적재돼 있는지, --skip-loaded 때문인지 확인)")
        conn.close(); return

    if a.probe:
        rows, err = fetch(key, domain, pnus[0], retries=1)
        print(f"PNU {pnus[0]} · 받은 행 {len(rows)} · 오류 {err}")
        keep = 연도별최신(rows)
        print(f"연도별 최신만 남기면 {len(keep)}건")
        if rows:
            print(json.dumps(rows[0], ensure_ascii=False, indent=1)[:1200])
        conn.close(); return

    print(f"[{ts()}] 대상 필지 {len(pnus):,}개 · 스레드 {a.workers} "
          f"(필지 하나당 호출 하나 — 이 API 는 PNU 전용이다)", flush=True)

    t0 = time.time()
    받음 = 넣음 = 바뀜 = 0
    빈것 = []          # 응답은 왔는데 행이 0 인 것(= 토지특성이 없는 필지. 실패 아님)
    실패 = []
    연속실패 = 0

    def 일(pnu):
        time.sleep(a.sleep)
        return pnu, *fetch(key, domain, pnu)

    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for i, (pnu, rows, err) in enumerate(ex.map(일, pnus), 1):
            if err:
                실패.append((pnu, err)); 연속실패 += 1
                if 연속실패 >= a.max_fail:
                    print(f"\n★ 연속 실패 {연속실패}회 — 여기서 멈춥니다.")
                    print(f"  마지막 오류: {err}")
                    print(f"  여기까지 {넣음:,}건 넣었습니다. 고친 뒤 "
                          f"--skip-loaded 로 이어가면 됩니다.")
                    break
                continue
            연속실패 = 0
            받음 += 1
            keep = 연도별최신(rows)
            if not keep:
                빈것.append(pnu)
                continue

            for r in keep:
                vals = {"pnu": pnu}
                for src, col in F:
                    v = r.get(src)
                    if col in 숫자칸:
                        vals[col] = num(v)
                    elif col == "last_updt_dt":
                        vals[col] = ymd8(v)
                    else:
                        v = (str(v).strip() if v is not None else "")
                        vals[col] = v or None
                rh = hashlib.sha256("\x1f".join(
                    str(vals[k]) for k in sorted(vals)).encode("utf-8")).digest()

                # SCD2 — 자연키는 (pnu, base_year)
                cur.execute("""UPDATE silver.land_char
                                  SET is_current = 0, valid_to = SYSDATETIME()
                                WHERE is_current = 1 AND pnu = %s AND base_year = %s
                                  AND row_hash <> %s""",
                            (pnu, vals["base_year"], rh))
                바뀜 += cur.rowcount if cur.rowcount and cur.rowcount > 0 else 0
                cols = list(vals.keys())
                cur.execute(
                    f"IF NOT EXISTS (SELECT 1 FROM silver.land_char "
                    f" WHERE is_current = 1 AND pnu = %s AND base_year = %s) "
                    f"INSERT INTO silver.land_char ({', '.join(cols)}, row_hash) "
                    f"VALUES ({', '.join(['%s'] * len(cols))}, %s)",
                    (pnu, vals["base_year"]) + tuple(vals[c] for c in cols) + (rh,))
                넣음 += 1

            if i % 500 == 0:
                conn.commit()
                걸린 = time.time() - t0
                속도 = i / 걸린 if 걸린 else 0
                남은 = (len(pnus) - i) / 속도 if 속도 else 0
                print(f"  [{ts()}] {i:,}/{len(pnus):,} 필지 · 행 {넣음:,} · "
                      f"{속도:.0f}필지/초 · 남은 {남은/60:.0f}분", flush=True)
    conn.commit()

    걸린 = time.time() - t0
    print(f"\n[{ts()}] 끝 — {걸린/60:.1f}분")
    print(f"  받은 필지 {받음:,} / 대상 {len(pnus):,}")
    print(f"  넣은 연도행 {넣음:,} (갱신 {바뀜:,})")
    # ★ '토지특성이 없는 필지' 와 '실패' 를 **갈라서** 적는다. 합치면 둘 다 뜻을 잃는다.
    print(f"  토지특성 없음 {len(빈것):,}건 (실패가 아니다 — 국공유지·도로 등)")
    if 실패:
        print(f"  ★ 실패 {len(실패):,}건 — 앞 5개:")
        for p_, e_ in 실패[:5]:
            print(f"     {p_}  {e_}")
        print("  --skip-loaded 로 다시 돌리면 실패분만 재시도합니다.")

    cur.execute("""SELECT 필지 = COUNT(DISTINCT pnu), 행 = COUNT(*),
                          연도 = COUNT(DISTINCT base_year),
                          처음 = MIN(base_year), 끝 = MAX(base_year)
                     FROM silver.land_char WHERE is_current = 1""")
    r = cur.fetchone()
    print(f"\n  표 전체: 필지 {r[0]:,} · 행 {r[1]:,} · 연도 {r[2]}개 ({r[3]}~{r[4]})")
    conn.close()
    sys.exit(1 if 실패 else 0)


if __name__ == "__main__":
    main()
