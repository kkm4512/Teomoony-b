#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dqm_probe - DQM 실험(2026-11-11 사장님 ㄱㄱ): 키 없는 실거래에서 I · U · D 를 얼마나 잡을 수 있나 실측.

  방식(claude/DQM_실험_결정.md):
    1) 묶음 = 종목 × 시군구 × 계약월(국토부 API 를 받는 단위 그대로)
    2) 묶음 안에서 **줄 전체 해시**로 어제 · 오늘을 개수째 비교 → 똑같은 줄은 빠지고 −(어제만) · +(오늘만)만 남는다
    3) 남은 것끼리 **정체성 해시**(가격 · 해제 · 중개 같은 '값' 칸을 뺀 나머지)로 짝짓기
       −1 · +1 이 딱 맞으면 U, 짝 없는 − 는 D, 짝 없는 + 는 I, 같은 정체성에 여럿이면 '애매'(D + I 로 두고 표시)

  py dqm_probe.py snap [--sgg 11680,11710,11350] [--months 3] [--kinds APT_TRADE_DEV,APT_RENT]
       → data/dqm/snap/<YYYYMMDD_HHMM>/  원천 응답 그대로(묶음마다 JSON) + manifest.json(건수 · sha256)
  py dqm_probe.py diff <스냅샷A> <스냅샷B>      → 묶음별 · 종목별 I/U/D/애매 + U 에서 바뀐 칸
  py dqm_probe.py db <스냅샷>                   → 적재DB(silver.rtms_trade)와 nat_key 로 대조(원천에 없는 옛 줄 · 적재DB 에 없는 줄)

  읽기만 한다(적재DB 에 쓰지 않는다). 파일은 data/dqm/ 아래(깃에 안 올라감).
"""
import argparse, collections, datetime as D, hashlib, json, os, re, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from load_rtms import KINDS, ENV, fetch, load_env, money, num, pick, months, 순번키, 줄순서, 키값, 기본키   # noqa: E402

ROOT = os.path.join(HERE, "..", "data", "dqm", "snap")

# '값' 칸 — 같은 거래라도 바뀔 수 있는 것(가격 · 해제 · 중개 · 등기 · 계약 조건). 정체성 해시에서 뺀다.
VALUE = {k.lower() for k in (
    "dealAmount", "deposit", "monthlyRent", "preDeposit", "preMonthlyRent",
    "contractTerm", "contractType", "useRRRight",
    "cdealType", "cdealDay", "dealingGbn", "buyerGbn", "slerGbn", "estateAgentSggNm",
    "rgstDate", "landLeaseholdGbn", "shareDealingType", "ownershipGbn")}


# '늦게 채워지는' 칸 — 등기가 끝나면 원천이 동(aptDong)을 채운다(2026-11-13 실측: 하루 −17 중 13건이 동 '' → '213' 같은 꼴).
# 1차 짝(정체성 전부)에서 남은 것 중 **옛 값이 비어 있던** 이 칸만 빼고 다시 짝지어 U 로 본다(채워진 값을 바꾼 것은 U 로 안 본다).
LATE = {"aptdong"}


def norm(v):
    """해시 전 정규화: 앞뒤 공백 · 겹친 공백 · 숫자의 쉼표 · 숫자 앞 0(지번 본번 같은 코드 칸은 글자 그대로)"""
    s = re.sub(r"\s+", " ", (v or "").strip())
    if re.fullmatch(r"-?[\d,]+(\.\d+)?", s):
        s = s.replace(",", "")
    return s


def row_hash(r):
    return hashlib.sha256("\x1f".join(f"{k.lower()}={norm(v)}" for k, v in sorted(r.items(), key=lambda x: x[0].lower())).encode()).hexdigest()


def id_hash(r, skip=()):
    return hashlib.sha256("\x1f".join(f"{k.lower()}={norm(v)}" for k, v in sorted(r.items(), key=lambda x: x[0].lower())
                                      if k.lower() not in VALUE and k.lower() not in skip).encode()).hexdigest()


def nat_key(kind, sgg, r):
    """load_rtms 의 키(11-19 부터 load_rtms.키값 · 기본키 한 곳)."""
    return 기본키(키값(kind, sgg, r))


def cmd_snap(a):
    key = load_env(ENV).get("DATA_GO_KR_KEY", "").strip()
    if not key: sys.exit(".env 의 DATA_GO_KR_KEY 가 비어 있다")
    now = D.datetime.now(); to = now.strftime("%Y%m")
    y, m = now.year, now.month
    for _ in range(a.months - 1):
        m -= 1
        if m == 0: y, m = y - 1, 12
    ms = months(f"{y}{m:02d}", to)
    out = os.path.join(ROOT, now.strftime("%Y%m%d_%H%M")); os.makedirs(out, exist_ok=True)
    man = {"at": now.isoformat(timespec="seconds"), "months": ms, "parts": {}}
    for kind in a.kinds.split(","):
        url = KINDS[kind][0]
        for sgg in a.sgg.split(","):
            for ym in ms:
                rows, st = fetch(url, key, sgg, ym)
                name = f"{kind}_{sgg}_{ym}"
                body = json.dumps(rows, ensure_ascii=False, sort_keys=True)
                open(os.path.join(out, name + ".json"), "w", encoding="utf-8").write(body)
                man["parts"][name] = {"status": st, "rows": len(rows), "sha256": hashlib.sha256(body.encode()).hexdigest(),
                                      "total": getattr(fetch, "전체", None)}   # 11-20: 원천이 말한 전체 건수(받은 줄 수와 같아야 한다)
                print(f"  {name}: {st} · {len(rows):,}줄", flush=True)
                if st != "OK": print(f"  !! {name} 받기 실패 — 이 묶음은 비교에서 뺀다", flush=True)
                time.sleep(0.2)
    json.dump(man, open(os.path.join(out, "manifest.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"스냅샷 {out} · 묶음 {len(man['parts'])} · 줄 {sum(p['rows'] for p in man['parts'].values()):,}")
    if getattr(a, "diff", False):   # 11-13: 스냅샷 바로 뒤에 비교(일정 두 줄이 밀려 함께 걸리면 비교가 먼저 돌던 것)
        print(); a.a, a.b = "prev", "latest"; cmd_diff(a)
        # 11-19: 이어서 버전 테이블에 이 스냅샷을 버전 하나로 쌓는다(dqm_lake build · DQM ④). 실패해도 스냅샷 · 비교는 남는다.
        import subprocess
        print("\n버전 테이블(dqm_lake build):", flush=True)
        for 할 in (["build"], ["check"], ["expire", "--days", "30"], ["dashboard"], ["trace"]):   # 쌓기 → 유실 검증 → 보관 1개월 정리 → 관리자 화면 요약 → 한 거래 따라가기
            r = subprocess.run([sys.executable, os.path.join(HERE, "dqm_lake.py")] + 할, cwd=HERE)
            if r.returncode not in (0, 3): print(f"  !! dqm_lake {할[0]} 종료코드 {r.returncode}", flush=True)


def load(snap):
    """스냅샷 폴더 이름 · 절대 경로 · latest(맨 나중) · prev(그 앞)"""
    if snap in ("latest", "prev"):
        ds = sorted(x for x in os.listdir(ROOT) if os.path.exists(os.path.join(ROOT, x, "manifest.json")))
        snap = ds[-1] if snap == "latest" else ds[-2]
    d = snap if os.path.isabs(snap) else os.path.join(ROOT, snap)
    man = json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))
    return d, man


def 묶음비교(A, B):
    """한 묶음의 어제 줄들 A · 오늘 줄들 B → 같음 · U · D · I (2026-11-19 — cmd_diff 와 dqm_lake 가 같이 쓴다).
    돌려줌: {"same": [(ra, rb)], "U": [(ra, rb, tag)], "D": [(ra, 애매)], "I": [(rb, 애매)]}
      tag = "U" | "U(늦게 채워진 칸)" · 애매 = 같은 정체성에 짝 후보가 여럿이라 D + I 로 둔 것(정정 후보)."""
    ca = collections.Counter(row_hash(r) for r in A); cb = collections.Counter(row_hash(r) for r in B)
    byh_a = {row_hash(r): r for r in A}; byh_b = {row_hash(r): r for r in B}
    out = {"same": [], "U": [], "D": [], "I": []}
    for h, n in (ca & cb).items(): out["same"] += [(byh_a[h], byh_b[h])] * n
    minus = ca - cb; plus = cb - ca
    g = collections.defaultdict(lambda: [[], []])
    for h, n in minus.items(): g[id_hash(byh_a[h])][0] += [h] * n
    for h, n in plus.items(): g[id_hash(byh_b[h])][1] += [h] * n
    def 애매로(m, p):
        k2 = min(len(m), len(p))
        out["D"] += [(byh_a[h], i < k2) for i, h in enumerate(m)]; out["I"] += [(byh_b[h], i < k2) for i, h in enumerate(p)]
    left_m, left_p = [], []
    for idh, (m, p) in g.items():
        if len(m) == 1 and len(p) == 1: out["U"].append((byh_a[m[0]], byh_b[p[0]], "U"))
        elif m and not p: left_m += m
        elif p and not m: left_p += p
        else: 애매로(m, p)
    # 2차 짝: 늦게 채워지는 칸(LATE)이 옛 줄에서 비어 있던 것만, 그 칸을 빼고 다시
    g2 = collections.defaultdict(lambda: [[], []])
    for h in left_m:
        r = byh_a[h]
        if all(not norm(r.get(k) or next((v for kk, v in r.items() if kk.lower() == k), "")) for k in LATE):
            g2[id_hash(r, LATE)][0].append(h)
        else: out["D"].append((r, False))
    for h in left_p: g2[id_hash(byh_b[h], LATE)][1].append(h)
    for idh, (m, p) in g2.items():
        if len(m) == 1 and len(p) == 1: out["U"].append((byh_a[m[0]], byh_b[p[0]], "U(늦게 채워진 칸)"))
        elif m and not p: out["D"] += [(byh_a[h], False) for h in m]
        elif p and not m: out["I"] += [(byh_b[h], False) for h in p]
        else: 애매로(m, p)
    return out


def 바뀐칸(ra, rb):
    return sorted(k for k in set(ra) | set(rb) if norm(ra.get(k)) != norm(rb.get(k)))


def cmd_diff(a):
    ds = sorted(x for x in os.listdir(ROOT) if os.path.exists(os.path.join(ROOT, x, "manifest.json"))) if os.path.isdir(ROOT) else []
    if len(ds) < 2: print("스냅샷이 2개 안 된다 — 건너뜀"); sys.exit(3)
    da, ma = load(a.a); db, mb = load(a.b)
    tot = collections.Counter(); per = collections.defaultdict(collections.Counter); fields = collections.Counter()
    ex = []
    for name in sorted(set(ma["parts"]) & set(mb["parts"])):
        if ma["parts"][name]["status"] != "OK" or mb["parts"][name]["status"] != "OK":
            tot["묶음_뺌(받기실패)"] += 1; continue
        A = json.load(open(os.path.join(da, name + ".json"), encoding="utf-8"))
        B = json.load(open(os.path.join(db, name + ".json"), encoding="utf-8"))
        kind = name.rsplit("_", 2)[0]
        c = per[kind]; c["어제줄"] += len(A); c["오늘줄"] += len(B)
        o = 묶음비교(A, B)
        c["같음"] += len(o["same"])
        for ra, rb, tag in o["U"]:
            c[tag] += 1; ch = 바뀐칸(ra, rb)
            for k in ch: fields[k] += 1
            if len(ex) < 8: ex.append((name, {k: (ra.get(k), rb.get(k)) for k in ch}))
        c["애매(짝 후보 여럿)"] += sum(1 for _, amb in o["D"] if amb)
        c["D"] += sum(1 for _, amb in o["D"] if not amb); c["I"] += sum(1 for _, amb in o["I"] if not amb)
    print(f"A {ma['at']}  →  B {mb['at']}")
    for kind, c in sorted(per.items()):
        print(f"  {kind}: 어제 {c['어제줄']:,} · 오늘 {c['오늘줄']:,} · 같음 {c['같음']:,} · I {c['I']:,} · U {c['U']:,} + 늦게채움 {c['U(늦게 채워진 칸)']:,} · D {c['D']:,} · 애매 {c['애매(짝 후보 여럿)']:,}")
    if tot: print("  ", dict(tot))
    print("U 에서 바뀐 칸:", fields.most_common(15))
    for name, chg in ex: print("  예)", name, json.dumps(chg, ensure_ascii=False)[:300])


def cmd_db(a):
    import pymssql
    d, man = load(a.snap); e = load_env(ENV)
    conn = pymssql.connect(server=e.get("DB_HOST", "127.0.0.1"), port=int(e.get("DB_PORT", 11433)), user=e.get("DB_USER", "sa"),
                           password=e.get("DB_PASSWORD", ""), database=e.get("DB_NAME", "Teomoony"), charset="UTF-8")
    cur = conn.cursor(); cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")
    per = collections.defaultdict(collections.Counter); ex = []
    for name, p in sorted(man["parts"].items()):
        if p["status"] != "OK": continue
        kind, sgg, ym = name.rsplit("_", 2)
        rows = json.load(open(os.path.join(d, name + ".json"), encoding="utf-8"))
        api = collections.Counter(nat_key(kind, sgg, r) for r in rows)      # 옛 키(같은 키 몇 줄인지)
        몇 = collections.Counter(); 지금키 = set()                              # 11-18 load_rtms 와 같은 순번 키
        for r in sorted(rows, key=줄순서):
            b = nat_key(kind, sgg, r); 몇[b] += 1; 지금키.add(순번키(b, 몇[b]))
        cur.execute("SELECT nat_key, is_canceled, deal_ymd, bld_nm, deal_amount, deposit, monthly_rent, loaded_at, umd_nm, jibun, bld_dong, exclu_use_ar, total_floor_ar, floor_no "
                    "FROM silver.rtms_trade WHERE trade_kind = %s AND sgg_cd = %s AND deal_ymd LIKE %s", (kind, sgg, ym + "%"))
        dbr = cur.fetchall(); dbk = {bytes(r[0]): r for r in dbr}
        c = per[kind]; c["원천줄"] += len(rows); c["원천_nat_key_겹침(합쳐짐)"] += sum(n - 1 for n in api.values() if n > 1)
        c["적재DB줄"] += len(dbr)
        c["둘다"] += sum(1 for k in 지금키 if k in dbk)
        c["원천에만(아직 안 들어옴)"] += sum(1 for k in 지금키 if k not in dbk)
        stale = [r for k, r in dbk.items() if k not in 지금키]
        c["적재DB에만(원천에서 사라진 옛 줄)"] += len(stale)
        c["그중_해제표시"] += sum(1 for r in stale if r[1])
        # 원천 안 nat_key 겹침이 '완전히 같은 줄'인지(원천 중복) · 다른 칸만 다른지(서로 다른 거래가 하나로 합쳐짐)
        byk = collections.defaultdict(set)
        for r in rows: byk[nat_key(kind, sgg, r)].add(row_hash(r))
        for k, hs in byk.items():
            n = api[k]
            if n > 1: c["  겹침_원천에서도_똑같은줄"] += n - len(hs); c["  겹침_다른칸이_다른줄(합쳐져_사라짐)"] += len(hs) - 1
        # 원천에서 사라진 옛 줄이 '가격만 바뀐 같은 거래'로 보이나(가격 뺀 칸이 같은 원천 줄이 딱 하나)
        def f(x): return None if x in (None, "") else float(x)
        def idk(umd, jib, nm, dong, ymd, ar, tfa, fl): return (umd or None, jib or None, nm or None, dong or None, ymd, f(ar), f(tfa), None if fl in (None, "") else int(float(fl)))
        src_id = collections.Counter()
        for r in rows:
            yr, mo, dy = pick(r, "dealYear"), pick(r, "dealMonth"), pick(r, "dealDay")
            ymd = f"{yr}{int(mo):02d}{int(dy):02d}" if yr and mo and dy else None
            src_id[idk(pick(r, "umdNm"), pick(r, "jibun"), pick(r, "aptNm", "mhouseNm", "offiNm"), pick(r, "aptDong"), ymd,
                       pick(r, "excluUseAr"), pick(r, "totalFloorAr"), pick(r, "floor"))] += 1
        for r in stale:
            n = src_id.get(idk(r[8], r[9], r[3], r[10], r[2], r[11], r[12], r[13]), 0)
            c["  옛줄_가격만다른_같은거래_1개" if n == 1 else ("  옛줄_후보여럿" if n > 1 else "  옛줄_원천에_같은정체성없음")] += 1
        for r in stale[:2]:
            if len(ex) < 8 and kind.endswith("TRADE_DEV"): ex.append((name, str(r[2]), r[3], r[4], bool(r[1]), str(r[7])[:16], r[13]))
    for kind, c in sorted(per.items()):
        print(f"  {kind}:")
        for k, v in c.items(): print(f"     {k} {v:,}")
    for x in ex: print("  예) 적재DB에만:", x[:7])


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("snap"); s.add_argument("--sgg", default="11680,11710,11350"); s.add_argument("--months", type=int, default=3)
    s.add_argument("--kinds", default="APT_TRADE_DEV,APT_RENT"); s.add_argument("--diff", action="store_true", help="받은 뒤 바로 어제와 비교")
    s2 = sp.add_parser("diff"); s2.add_argument("a"); s2.add_argument("b")
    s3 = sp.add_parser("db"); s3.add_argument("snap")
    a = ap.parse_args()
    {"snap": cmd_snap, "diff": cmd_diff, "db": cmd_db}[a.cmd](a)
