# -*- coding: utf-8 -*-
"""_ned_vm - 연립·다세대 공동주택가격(NED)을 VM 에서 받아 SQL 파일로 (2026-10-22, 사장님 "너가 돌려 · 나 밖이야")
  python3 _ned_vm.py fetch [초] [병렬]   _export/ned_targets.txt 를 500필지씩 묶어, 안 받은 묶음만 받는다 → _ned_raw/bNNNN.json.gz
  python3 _ned_vm.py sql                 받은 묶음마다 deploy/sql/tned_NNNN.sql (이미 있으면 건너뜀)
★ 받기는 load_ned_aphus.fetch 그대로(원문). 한 필지라도 실패한 묶음은 그 필지를 빼고 적고, done 에도 안 적는다(다음에 다시).
★ 넣기 = 없는 키만 INSERT(표가 비어 있던 첫 적재). 같은 키가 원문에 두 번이면 값은 같고 갱신일만 달라서 — 가장 늦은 갱신일 행.
★ 한 필지의 done 은 **그 파일의 마지막 배치**에서 — 앞 배치가 실패하면 _apply 가 멈춰 done 이 안 적힌다."""
import gzip, io, json, os, sys, time
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import load_ned_aphus as N
RAW = os.path.join(HERE, "_ned_raw"); os.makedirs(RAW, exist_ok=True)
SQLD = os.path.join(HERE, "..", "deploy", "sql")
B = 500
T = [l.strip() for l in io.open(os.path.join(HERE, "_export", "ned_targets.txt"), encoding="utf-8") if l.strip()]
BATCHES = [T[i:i + B] for i in range(0, len(T), B)]
fn = lambda i: os.path.join(RAW, f"b{i:04d}.json.gz")


import _ned_dong as D


def one(p):
    # ★ 2026-10-22: N.fetch(1000행씩 쪽 넘김)는 1000행 넘는 필지에서 행이 빠진다 → 해마다 한 쪽(D.pnu_all). b0000~b0007 은 옛 방식 — redo 로 메운다.
    try: return p, D.pnu_all(p), None
    except Exception as e: return p, None, str(e)[:120]


def fetch(budget, par, mod=1, k=0):
    t0 = time.time(); done = 0
    with ThreadPoolExecutor(par) as ex:
        for i, b in enumerate(BATCHES):
            if i % mod != k or os.path.exists(fn(i)) or os.path.exists(fn(i) + f'.lock{k}'): continue
            if time.time() - t0 > budget: break
            got, err = {}, {}
            for p, rows, e in ex.map(one, b):
                if e is None: got[p] = rows
                else: err[p] = e
            with gzip.open(fn(i) + ".tmp", "wt", encoding="utf-8") as f: json.dump({"got": got, "err": err}, f, ensure_ascii=False)
            os.replace(fn(i) + ".tmp", fn(i)); done += 1
            print(f"  b{i:04d}: {len(got)} 필지 · 행 {sum(map(len, got.values())):,} · 실패 {len(err)}" + (f" ({next(iter(err.values()))})" if err else ""), flush=True)
    have = sum(os.path.exists(fn(i)) for i in range(len(BATCHES)))
    print(f"묶음 {have}/{len(BATCHES)} · 이번 {done} · {time.time() - t0:.0f}초")


def s(v):
    v = None if v is None else str(v).strip()
    return v or None


def to_sql(i, src=None, out=None):
    src = src or fn(i); out = out or os.path.join(SQLD, f"tned_{i:04d}.sql")
    if os.path.exists(out) or not os.path.exists(src): return None
    d = json.load(gzip.open(src, "rt", encoding="utf-8"))
    rows = {}
    for p, rr in d["got"].items():
        for x in rr:
            k = (p, s(x.get("aphusCode")) or "?", (x.get("dongNm") or "").strip(), (x.get("hoNm") or "").strip(),
                 s(x.get("stdrYear")) or "?", s(x.get("stdrMt")) or "01")
            try: 가 = int(float(x.get("pblntfPc")))
            except Exception: 가 = None
            try: 면 = float(x.get("prvuseAr"))
            except Exception: 면 = None
            v = list(k) + [s(x.get("floorNm")), 면, 가, s(x.get("aphusNm")), s(x.get("aphusSeCodeNm")), s(x.get("regstrSeCodeNm")),
                                 s(x.get("spclLandNm")), s(x.get("lastUpdtDt"))]
            # ★ 같은 키가 두 번 오면(b0000 실측 13,949쌍) 값은 같고 **원문갱신일만** 다르다 → 가장 늦은 갱신일 행을 둔다(순서에 기대지 않는다).
            if k not in rows or (v[13] or "") > (rows[k][13] or ""): rows[k] = v
    rs = list(rows.values())
    sql = ["SET NOCOUNT ON;\nGO\n"]
    W = ("pnu CHAR(19) '$[0]', 공동주택코드 VARCHAR(20) '$[1]', 동명 NVARCHAR(100) '$[2]', 호명 NVARCHAR(100) '$[3]', 기준연도 CHAR(4) '$[4]', "
         "기준월 CHAR(2) '$[5]', 층 NVARCHAR(20) '$[6]', 전용면적 DECIMAL(12,4) '$[7]', 공시가격 BIGINT '$[8]', 공동주택명 NVARCHAR(200) '$[9]', "
         "구분 NVARCHAR(20) '$[10]', 대장구분 NVARCHAR(20) '$[11]', 특수지명 NVARCHAR(100) '$[12]', 원문갱신일 CHAR(10) '$[13]'")
    C = "pnu, 공동주택코드, 동명, 호명, 기준연도, 기준월, 층, 전용면적, 공시가격, 공동주택명, 구분, 대장구분, 특수지명, 원문갱신일"
    for j in range(0, len(rs), 4000):
        js = json.dumps(rs[j:j + 4000], ensure_ascii=False, separators=(",", ":")).replace("'", "''")
        sql.append(f"DECLARE @j NVARCHAR(MAX) = N'{js}';\nINSERT silver.ned_aphus_price ({C})\nSELECT {C} FROM OPENJSON(@j) WITH ({W}) s\n"
                   f"WHERE NOT EXISTS (SELECT 1 FROM silver.ned_aphus_price t WHERE t.pnu = s.pnu AND t.공동주택코드 = s.공동주택코드 AND t.동명 = s.동명 "
                   f"AND t.호명 = s.호명 AND t.기준연도 = s.기준연도 AND t.기준월 = s.기준월);\nGO\n")
    dn = json.dumps([[p, len(rr)] for p, rr in d["got"].items()], separators=(",", ":"))
    sql.append(f"DECLARE @d NVARCHAR(MAX) = N'{dn}';\nMERGE silver.ned_aphus_done AS t USING (SELECT pnu, n FROM OPENJSON(@d) WITH (pnu CHAR(19) '$[0]', n INT '$[1]')) k "
               f"ON t.pnu = k.pnu\nWHEN MATCHED THEN UPDATE SET 건수 = k.n, 받은시각 = SYSDATETIME()\nWHEN NOT MATCHED THEN INSERT (pnu, 건수) VALUES (k.pnu, k.n);\n"
               f"SELECT 묶음 = {i}, 필지 = {len(d['got'])}, 행 = {len(rs)};\nGO\n")
    io.open(out + ".tmp", "w", encoding="utf-8").write("".join(sql)); os.replace(out + ".tmp", out)
    return len(rs)


if __name__ == "__main__":
    if sys.argv[1] == "fetch": fetch(float(sys.argv[2]) if len(sys.argv) > 2 else 140, int(sys.argv[3]) if len(sys.argv) > 3 else 16, *(int(x) for x in sys.argv[4:6]))
    elif sys.argv[1] == "redo":
        # 옛 방식으로 받은 묶음(0~7)에서 1000행 넘던 필지만 다시 받아 r 묶음으로
        for i in range(8):
            src = os.path.join(RAW, f"r{i:04d}.json.gz")
            if os.path.exists(src): continue
            d = json.load(gzip.open(fn(i), "rt", encoding="utf-8"))
            ps = [p for p, rr in d["got"].items() if len(rr) > 1000] + list(d["err"])
            got, err = {}, {}
            with ThreadPoolExecutor(16) as ex:
                for p, rows, e in ex.map(one, ps):
                    if e is None: got[p] = rows
                    else: err[p] = e
            with gzip.open(src + ".tmp", "wt", encoding="utf-8") as f: json.dump({"got": got, "err": err}, f, ensure_ascii=False)
            os.replace(src + ".tmp", src)
            print(f"  r{i:04d}: {len(got)} 필지 · 실패 {len(err)}", flush=True)
            to_sql(900 + i, src, os.path.join(SQLD, f"tned_r{i:04d}.sql"))
    elif sys.argv[1] == "sql":
        n = 0
        for i in range(len(BATCHES)):
            r = to_sql(i)
            if r is not None: n += 1
        print("SQL 파일", n)
