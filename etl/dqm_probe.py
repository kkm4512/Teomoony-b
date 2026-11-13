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
from load_rtms import KINDS, ENV, fetch, load_env, money, num, pick, months   # noqa: E402

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
    """load_rtms.py 와 똑같이(적재DB nat_key 대조용)."""
    yr, mo, dy = pick(r, "dealYear"), pick(r, "dealMonth"), pick(r, "dealDay")
    ymd = (f"{yr}{int(mo):02d}{int(dy):02d}" if yr and mo and dy and str(mo).isdigit() and str(dy).isdigit() else None)
    vals = dict(trade_kind=kind, sgg_cd=pick(r, "sggCd") or sgg, umd_nm=pick(r, "umdNm"), jibun=pick(r, "jibun"),
                bld_nm=pick(r, "aptNm", "mhouseNm", "offiNm"), bld_dong=pick(r, "aptDong"), deal_ymd=ymd,
                deal_amount=money(pick(r, "dealAmount")), deposit=money(pick(r, "deposit")), monthly_rent=money(pick(r, "monthlyRent")),
                exclu_use_ar=num(pick(r, "excluUseAr")), total_floor_ar=num(pick(r, "totalFloorAr")), floor_no=num(pick(r, "floor"), int))
    return hashlib.sha256("\x1f".join(str(vals[k]) for k in (
        "trade_kind", "sgg_cd", "umd_nm", "jibun", "bld_nm", "bld_dong", "deal_ymd",
        "deal_amount", "deposit", "monthly_rent", "exclu_use_ar", "total_floor_ar", "floor_no")).encode()).digest()


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
                man["parts"][name] = {"status": st, "rows": len(rows), "sha256": hashlib.sha256(body.encode()).hexdigest()}
                print(f"  {name}: {st} · {len(rows):,}줄", flush=True)
                if st != "OK": print(f"  !! {name} 받기 실패 — 이 묶음은 비교에서 뺀다", flush=True)
                time.sleep(0.2)
    json.dump(man, open(os.path.join(out, "manifest.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"스냅샷 {out} · 묶음 {len(man['parts'])} · 줄 {sum(p['rows'] for p in man['parts'].values()):,}")
    if getattr(a, "diff", False):   # 11-13: 스냅샷 바로 뒤에 비교(일정 두 줄이 밀려 함께 걸리면 비교가 먼저 돌던 것)
        print(); a.a, a.b = "prev", "latest"; cmd_diff(a)


def load(snap):
    """스냅샷 폴더 이름 · 절대 경로 · latest(맨 나중) · prev(그 앞)"""
    if snap in ("latest", "prev"):
        ds = sorted(x for x in os.listdir(ROOT) if os.path.exists(os.path.join(ROOT, x, "manifest.json")))
        snap = ds[-1] if snap == "latest" else ds[-2]
    d = snap if os.path.isabs(snap) else os.path.join(ROOT, snap)
    man = json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))
    return d, man


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
        ca = collections.Counter(row_hash(r) for r in A); cb = collections.Counter(row_hash(r) for r in B)
        byh_a = {row_hash(r): r for r in A}; byh_b = {row_hash(r): r for r in B}
        minus = ca - cb; plus = cb - ca
        kind = name.rsplit("_", 2)[0]
        c = per[kind]; c["어제줄"] += len(A); c["오늘줄"] += len(B); c["같음"] += sum((ca & cb).values())
        g = collections.defaultdict(lambda: [[], []])
        for h, n in minus.items(): g[id_hash(byh_a[h])][0] += [h] * n
        for h, n in plus.items(): g[id_hash(byh_b[h])][1] += [h] * n
        def u(ra, rb, tag="U"):
            c[tag] += 1
            ch = sorted(k for k in set(ra) | set(rb) if norm(ra.get(k)) != norm(rb.get(k)))
            for k in ch: fields[k] += 1
            if len(ex) < 8: ex.append((name, {k: (ra.get(k), rb.get(k)) for k in ch}))
        left_m, left_p = [], []
        for idh, (m, p) in g.items():
            if len(m) == 1 and len(p) == 1: u(byh_a[m[0]], byh_b[p[0]])
            elif m and not p: left_m += m
            elif p and not m: left_p += p
            else:
                k2 = min(len(m), len(p)); c["애매(짝 후보 여럿)"] += k2; c["D"] += len(m) - k2; c["I"] += len(p) - k2
        # 2차 짝: 늦게 채워지는 칸(LATE)이 옛 줄에서 비어 있던 것만, 그 칸을 빼고 다시
        g2 = collections.defaultdict(lambda: [[], []])
        for h in left_m:
            r = byh_a[h]
            if all(not norm(r.get(k) or next((v for kk, v in r.items() if kk.lower() == k), "")) for k in LATE):
                g2[id_hash(r, LATE)][0].append(h)
            else: c["D"] += 1
        for h in left_p: g2[id_hash(byh_b[h], LATE)][1].append(h)
        for idh, (m, p) in g2.items():
            if len(m) == 1 and len(p) == 1: u(byh_a[m[0]], byh_b[p[0]], "U(늦게 채워진 칸)")
            elif m and not p: c["D"] += len(m)
            elif p and not m: c["I"] += len(p)
            else:
                k2 = min(len(m), len(p)); c["애매(짝 후보 여럿)"] += k2; c["D"] += len(m) - k2; c["I"] += len(p) - k2
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
        api = collections.Counter(nat_key(kind, sgg, r) for r in rows)
        cur.execute("SELECT nat_key, is_canceled, deal_ymd, bld_nm, deal_amount, deposit, monthly_rent, loaded_at, umd_nm, jibun, bld_dong, exclu_use_ar, total_floor_ar, floor_no "
                    "FROM silver.rtms_trade WHERE trade_kind = %s AND sgg_cd = %s AND deal_ymd LIKE %s", (kind, sgg, ym + "%"))
        dbr = cur.fetchall(); dbk = {bytes(r[0]): r for r in dbr}
        c = per[kind]; c["원천줄"] += len(rows); c["원천_nat_key_겹침(합쳐짐)"] += sum(n - 1 for n in api.values() if n > 1)
        c["적재DB줄"] += len(dbr)
        c["둘다"] += sum(1 for k in api if k in dbk)
        c["원천에만(아직 안 들어옴)"] += sum(1 for k in api if k not in dbk)
        stale = [r for k, r in dbk.items() if k not in api]
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
