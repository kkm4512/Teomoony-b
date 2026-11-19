#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dqm_lake - DQM ④ + 제공 표준화 실험: 원천 스냅샷 → **버전 테이블**(Apache Iceberg) (2026-11-19 사장님 "4번을 먼저하자")

  재료: dqm_probe snap 이 매일 남기는 원천 그대로(data/dqm/snap/<날짜_시각>/ · 서울 강남 · 송파 · 노원 × 최근 3개월 × 아파트 매매 · 전월세)
  만드는 것(창고 data/dqm/lake/ · 카탈로그 SQLite):
    dqm.rtms_state     지금 상태 — 거래마다 한 줄. 버전 하나 = Iceberg 스냅샷 하나(+ 이름표 v<N>) → 시점 조회 · 복원
    dqm.rtms_changes   변경 이력 — 버전마다 I · U · D(애매 표시) 를 쌓기만 한다 → '버전 N 이후' 변경분(커서 = 버전 번호)
    dqm.rtms_versions  버전 목록 — 버전 · 스냅샷 폴더 · 건수 · 두 표의 Iceberg 스냅샷 번호
  ★ 원천에 거래 번호가 없어 **거래 번호(trade_id)를 우리가 매긴다**: 처음 본 줄에 새 번호, 같은 줄 · U 는 번호를 이어받는다(dqm_probe.묶음비교).
    그래서 변경분을 받는 쪽은 'trade_id 의 지금 값' 으로 덮어쓰기만 하면 된다.
  ★ 묶음이 최근 3개월 창에서 빠지면(달이 바뀜) 지우지 않고 그대로 둔다(사라진 게 아니라 안 보는 것). 받기가 OK 가 아닌 묶음도 그날은 그대로.

  python dqm_lake.py build                 아직 버전이 안 된 스냅샷을 차례로 버전으로(매일 snap 뒤에)
  python dqm_lake.py versions              버전 목록
  python dqm_lake.py asof (--version N | --date YYYYMMDD)   그 시점 상태(건수 · 예)
  python dqm_lake.py changes --since N     버전 N 뒤의 변경분(받는 쪽 화면)
  python dqm_lake.py check                 유실 검증: 상태(N-1) + 변경(N) = 상태(N) · 상태(N) = 원천 스냅샷 N (모든 버전)
  python dqm_lake.py restore --version N   버전 N 의 내용으로 **새 버전**을 만든다(되돌리기 · 기록은 남는다)
  python dqm_lake.py expire [--days 30]    보관 정책: 오래된 Iceberg 스냅샷 정리(결정 4: 1개월)
  python dqm_lake.py dashboard             터무니 관리자 화면(내정보 → DQM)용 요약 data/dqm/dashboard.json
"""
import argparse, collections, datetime as D, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "data", "pylib312"))   # pyiceberg · duckdb · pyarrow (작업 큐 컨테이너 파이썬 3.12 용)
sys.path.insert(0, HERE)
import pyarrow as pa                                                # noqa: E402
from pyiceberg.catalog.sql import SqlCatalog                       # noqa: E402
from pyiceberg.exceptions import NamespaceAlreadyExistsError, NoSuchTableError   # noqa: E402
from dqm_probe import ROOT as SNAP_ROOT, load, row_hash, id_hash, 묶음비교, 바뀐칸, norm   # noqa: E402

LAKE = os.path.abspath(os.path.join(HERE, "..", "data", "dqm", "lake"))
NS = "dqm"

# 원천 칸 가운데 따로 꺼내 두는 것(조회용) — 원래 줄은 row_json 에 그대로 남는다
칸 = {"umd_nm": ("umdNm",), "apt_nm": ("aptNm",), "apt_dong": ("aptDong",), "jibun": ("jibun",), "floor": ("floor",),
     "exclu_use_ar": ("excluUseAr",), "deal_date": None, "deal_amount": ("dealAmount",), "deposit": ("deposit",),
     "monthly_rent": ("monthlyRent",), "cdeal_type": ("cdealType",), "rgst_date": ("rgstDate",)}

STATE = pa.schema([("trade_id", pa.int64(), False), ("kind", pa.string()), ("sgg", pa.string()), ("ym", pa.string()),
                   ("row_hash", pa.string()), ("id_hash", pa.string())]
                  + [(k, pa.string()) for k in 칸] + [("row_json", pa.string()), ("since_version", pa.int64())])
CHANGES = pa.schema([("version", pa.int64(), False), ("snap", pa.string()), ("op", pa.string()), ("amb", pa.bool_()), ("late", pa.bool_()),
                     ("trade_id", pa.int64()), ("kind", pa.string()), ("sgg", pa.string()), ("ym", pa.string()),
                     ("changed_cols", pa.string()), ("before_json", pa.string()), ("after_json", pa.string()),
                     ("before_hash", pa.string()), ("after_hash", pa.string())])
VERSIONS = pa.schema([("version", pa.int64(), False), ("snap", pa.string()), ("snap_at", pa.string()), ("built_at", pa.string()),
                      ("rows", pa.int64()), ("n_i", pa.int64()), ("n_u", pa.int64()), ("n_d", pa.int64()), ("n_amb", pa.int64()),
                      ("bundles_ok", pa.int64()), ("bundles_kept", pa.int64()),
                      ("state_snapshot_id", pa.int64()), ("changes_snapshot_id", pa.int64())])


def 카탈로그():
    os.makedirs(os.path.join(LAKE, "wh"), exist_ok=True)
    cat = SqlCatalog("dqm", uri=f"sqlite:///{os.path.join(LAKE, 'catalog.db')}", warehouse=f"file://{os.path.join(LAKE, 'wh')}")
    try: cat.create_namespace(NS)
    except NamespaceAlreadyExistsError: pass
    return cat


def 표(cat, name, schema):
    try: return cat.load_table(f"{NS}.{name}")
    except NoSuchTableError: return cat.create_table(f"{NS}.{name}", schema=schema)


def 값(r, names):
    low = {k.lower(): v for k, v in r.items()}
    for n in names:
        v = low.get(n.lower())
        if v not in (None, ""): return str(v).strip()
    return None


def 상태줄(tid, kind, sgg, ym, r, ver):
    d = {"trade_id": tid, "kind": kind, "sgg": sgg, "ym": ym, "row_hash": row_hash(r), "id_hash": id_hash(r)}
    for k, names in 칸.items():
        if k == "deal_date":
            y, m, dd = 값(r, ("dealYear",)), 값(r, ("dealMonth",)), 값(r, ("dealDay",))
            d[k] = f"{y}{int(m):02d}{int(dd):02d}" if y and m and dd and m.isdigit() and dd.isdigit() else None
        else: d[k] = 값(r, names)
    d["row_json"] = json.dumps(r, ensure_ascii=False, sort_keys=True); d["since_version"] = ver
    return d


def 표로(rows, schema):
    return pa.Table.from_pylist(rows, schema=schema)


def 읽기(tbl, snapshot_id=None, row_filter=None):
    if tbl.current_snapshot() is None: return []
    sc = tbl.scan(snapshot_id=snapshot_id) if row_filter is None else tbl.scan(snapshot_id=snapshot_id, row_filter=row_filter)
    return sc.to_arrow().to_pylist()


def 버전목록(cat):
    return sorted(읽기(표(cat, "rtms_versions", VERSIONS)), key=lambda v: v["version"])


def 스냅샷들():
    return sorted(x for x in os.listdir(SNAP_ROOT) if os.path.exists(os.path.join(SNAP_ROOT, x, "manifest.json")))


def 묶음줄(d, name):
    return json.load(open(os.path.join(d, name + ".json"), encoding="utf-8"))


def cmd_build(a):
    cat = 카탈로그(); st = 표(cat, "rtms_state", STATE); ch = 표(cat, "rtms_changes", CHANGES); vt = 표(cat, "rtms_versions", VERSIONS)
    vs = 버전목록(cat); 된 = {v["snap"] for v in vs}
    진짜 = [v["snap"] for v in vs if not v["snap"].startswith("restore_")]
    할 = [s for s in 스냅샷들() if s not in 된 and (not 진짜 or s > 진짜[-1])]
    if not 할: print("새 스냅샷 없음 — 건너뜀"); sys.exit(3)
    for snap in 할:
        t0 = time.time()
        ver = (vs[-1]["version"] + 1) if vs else 1
        prev_snap = vs[-1]["snap"] if vs else None
        보관 = 30 * 86400 * 1000   # 이름표도 30일 지나면 풀린다(결정 4 · 보관 1개월)
        db, mb = load(snap)
        now = 읽기(st)                                         # 지금 상태(= 버전 ver-1)
        by_bundle = collections.defaultdict(list)
        for x in now: by_bundle[f"{x['kind']}_{x['sgg']}_{x['ym']}"].append(x)
        next_id = max((x["trade_id"] for x in now), default=0) + 1
        if vs:   # 지금까지 쓴 번호 중 가장 큰 것(지워진 거래 번호도 다시 쓰지 않는다)
            old = 읽기(ch); next_id = max([next_id] + [c["trade_id"] + 1 for c in old if c["trade_id"] is not None])
        새상태 = []; 변경 = []; c = collections.Counter()
        names = set(mb["parts"]) | set(by_bundle)
        for name in sorted(names):
            kind, sgg, ym = name.rsplit("_", 2)
            cur = by_bundle.get(name, [])
            part = mb["parts"].get(name)
            if not part or part["status"] != "OK":                  # 창 밖 · 받기 실패 → 그대로 둔다
                새상태 += cur; c["묶음_그대로"] += 1 if cur else 0; continue
            B = 묶음줄(db, name); c["묶음_OK"] += 1
            if not cur:                                              # 처음 보는 묶음 → 전부 I
                for r in B:
                    새상태.append(상태줄(next_id, kind, sgg, ym, r, ver))
                    변경.append(dict(version=ver, snap=snap, op="I", amb=False, late=False, trade_id=next_id, kind=kind, sgg=sgg, ym=ym,
                                     changed_cols=None, before_json=None, after_json=json.dumps(r, ensure_ascii=False, sort_keys=True),
                                     before_hash=None, after_hash=row_hash(r)))
                    next_id += 1; c["I"] += 1
                continue
            A = [json.loads(x["row_json"]) for x in cur]
            o = 묶음비교(A, B)
            ids = collections.defaultdict(list)                     # 옛 줄 해시 → 거래 번호들(똑같은 줄이 여럿일 수 있다)
            keep = {}
            for x in sorted(cur, key=lambda x: x["trade_id"]): ids[x["row_hash"]].append(x["trade_id"]); keep[x["trade_id"]] = x
            def 번호(ra): return ids[row_hash(ra)].pop(0)
            for ra, rb in o["same"]:
                tid = 번호(ra); 새상태.append(keep[tid])
            for ra, rb, tag in o["U"]:
                tid = 번호(ra); 새상태.append(상태줄(tid, kind, sgg, ym, rb, ver))
                변경.append(dict(version=ver, snap=snap, op="U", amb=False, late=tag != "U", trade_id=tid, kind=kind, sgg=sgg, ym=ym,
                                 changed_cols=",".join(바뀐칸(ra, rb)), before_json=json.dumps(ra, ensure_ascii=False, sort_keys=True),
                                 after_json=json.dumps(rb, ensure_ascii=False, sort_keys=True), before_hash=row_hash(ra), after_hash=row_hash(rb)))
                c["U"] += 1
            for ra, amb in o["D"]:
                tid = 번호(ra)
                변경.append(dict(version=ver, snap=snap, op="D", amb=amb, late=False, trade_id=tid, kind=kind, sgg=sgg, ym=ym,
                                 changed_cols=None, before_json=json.dumps(ra, ensure_ascii=False, sort_keys=True), after_json=None,
                                 before_hash=row_hash(ra), after_hash=None))
                c["D"] += 1; c["애매"] += amb
            for rb, amb in o["I"]:
                새상태.append(상태줄(next_id, kind, sgg, ym, rb, ver))
                변경.append(dict(version=ver, snap=snap, op="I", amb=amb, late=False, trade_id=next_id, kind=kind, sgg=sgg, ym=ym,
                                 changed_cols=None, before_json=None, after_json=json.dumps(rb, ensure_ascii=False, sort_keys=True),
                                 before_hash=None, after_hash=row_hash(rb)))
                next_id += 1; c["I"] += 1
            assert all(not v for v in ids.values()), f"{name}: 상태와 어제 스냅샷이 안 맞는다(남은 번호 {sum(len(v) for v in ids.values())})"
        props = {"dqm.version": str(ver), "dqm.snap": snap}
        st.overwrite(표로(새상태, STATE), snapshot_properties=props)
        if 변경: ch.append(표로(변경, CHANGES), snapshot_properties=props)
        st.refresh(); ch.refresh()
        sid = st.current_snapshot().snapshot_id; cid = ch.current_snapshot().snapshot_id if ch.current_snapshot() else None
        st.manage_snapshots().create_tag(sid, f"v{ver}", max_ref_age_ms=보관).commit()
        row = dict(version=ver, snap=snap, snap_at=mb.get("at"), built_at=D.datetime.now().isoformat(timespec="seconds"), rows=len(새상태),
                   n_i=c["I"], n_u=c["U"], n_d=c["D"], n_amb=c["애매"], bundles_ok=c["묶음_OK"], bundles_kept=c["묶음_그대로"],
                   state_snapshot_id=sid, changes_snapshot_id=cid)
        vt.append(표로([row], VERSIONS), snapshot_properties=props); vt.refresh()
        vs.append(row)
        print(f"  v{ver} {snap} (앞 {prev_snap}) · 상태 {len(새상태):,}줄 · I {c['I']:,} · U {c['U']:,} · D {c['D']:,}(애매 {c['애매']}) · "
              f"묶음 OK {c['묶음_OK']} · 그대로 {c['묶음_그대로']} · {time.time()-t0:.1f}초", flush=True)


def cmd_versions(a):
    for v in 버전목록(카탈로그()):
        print(f"  v{v['version']:<3} {v['snap']}  상태 {v['rows']:>6,}  I {v['n_i']:>5,}  U {v['n_u']:>3,}  D {v['n_d']:>3,}  애매 {v['n_amb']}  "
              f"묶음 {v['bundles_ok']}+{v['bundles_kept']}  (state {v['state_snapshot_id']})")


def 버전찾기(vs, version=None, date=None):
    if version is not None:
        m = [v for v in vs if v["version"] == version]
    else:   # 그 날짜까지의 마지막 버전(스냅샷 폴더 이름의 날짜 기준)
        m = [v for v in vs if v["snap"][:8] <= date][-1:]
    if not m: sys.exit(f"그런 버전이 없다: version={version} date={date}")
    return m[0]


def cmd_asof(a):
    cat = 카탈로그(); vs = 버전목록(cat); v = 버전찾기(vs, a.version, a.date)
    st = 표(cat, "rtms_state", STATE)
    rows = 읽기(st, snapshot_id=v["state_snapshot_id"])
    c = collections.Counter((x["kind"], x["ym"]) for x in rows)
    print(f"v{v['version']} ({v['snap']}) 시점 상태 {len(rows):,}줄 — Iceberg 스냅샷 {v['state_snapshot_id']}")
    for (k, ym), n in sorted(c.items()): print(f"   {k:14s} {ym}  {n:,}")
    if a.trade:
        for x in rows:
            if x["trade_id"] == a.trade: print("   거래", a.trade, {k: x[k] for k in ("apt_nm", "apt_dong", "floor", "deal_date", "deal_amount", "deposit", "monthly_rent", "cdeal_type", "rgst_date", "since_version")})


def cmd_changes(a):
    cat = 카탈로그(); ch = 표(cat, "rtms_changes", CHANGES)
    rows = [x for x in 읽기(ch) if x["version"] > a.since]
    vs = 버전목록(cat); last = vs[-1]["version"] if vs else 0
    c = collections.Counter((x["version"], x["op"] + ("(애매)" if x["amb"] else "") + ("(늦게채움)" if x["late"] else "")) for x in rows)
    print(f"버전 {a.since} 뒤 변경분 {len(rows):,}줄 · 다음 커서 = {last}")
    for (ver, op), n in sorted(c.items()): print(f"   v{ver} {op:12s} {n:,}")
    for x in [x for x in rows if x["op"] == "U"][:a.show]:
        print(f"   예) v{x['version']} U 거래 {x['trade_id']} {x['kind']} 바뀐 칸 {x['changed_cols']}")
    if a.out:
        json.dump(rows, open(a.out, "w", encoding="utf-8"), ensure_ascii=False); print("   →", a.out)


def 검증결과(cat):
    """유실 검증 두 가지(모든 버전): ① 상태(N-1) + 변경(N) = 상태(N)  ② 상태(N) 의 OK 묶음 = 원천 스냅샷 N(줄 해시 개수까지)
    돌려줌: [{version, snap, 줄, 원천줄, ok1, ok2(None = 되돌리기 버전)}]"""
    vs = 버전목록(cat); st = 표(cat, "rtms_state", STATE); ch = 표(cat, "rtms_changes", CHANGES)
    allch = collections.defaultdict(list)
    for x in 읽기(ch): allch[x["version"]].append(x)
    prev = {}; out = []
    for v in vs:
        rows = 읽기(st, snapshot_id=v["state_snapshot_id"])
        cur = {x["trade_id"]: x["row_hash"] for x in rows}
        exp = dict(prev)
        for x in allch[v["version"]]:
            if x["op"] == "D": exp.pop(x["trade_id"], None)
            else: exp[x["trade_id"]] = x["after_hash"]
        r = {"version": v["version"], "snap": v["snap"], "줄": len(cur), "원천줄": None, "ok1": exp == cur, "ok2": None}
        if not v["snap"].startswith("restore_"):
            db, mb = load(v["snap"]); src = collections.Counter(); mine = collections.Counter()
            okb = {n for n, p in mb["parts"].items() if p["status"] == "OK"}
            for n in okb:
                for rr in 묶음줄(db, n): src[(n, row_hash(rr))] += 1
            for x in rows:
                n = f"{x['kind']}_{x['sgg']}_{x['ym']}"
                if n in okb: mine[(n, x["row_hash"])] += 1
            r["원천줄"] = sum(src.values()); r["ok2"] = src == mine
        out.append(r); prev = cur
    return out


def cmd_check(a):
    bad = 0
    for r in 검증결과(카탈로그()):
        bad += (not r["ok1"]) + (r["ok2"] is False)
        둘 = "(되돌리기 버전 — 원천 없음)" if r["ok2"] is None else ("맞음" if r["ok2"] else "틀림")
        print(f"  v{r['version']:<3} {r['snap']}  ① 앞 상태 + 변경 = 이 상태: {'맞음' if r['ok1'] else '틀림'}  ② 이 상태 = 원천 스냅샷: {둘}"
              + (f"  ({r['줄']:,}줄 · 원천 {r['원천줄']:,}줄)" if r["원천줄"] is not None else ""))
    print("유실 없음" if not bad else f"!! 틀린 곳 {bad}"); sys.exit(1 if bad else 0)


def cmd_dashboard(a):
    """터무니 관리자 화면(내정보 → DQM)용 요약 → data/dqm/dashboard.json (웹은 이 파일만 읽는다 · Iceberg 는 작업 큐에서만 읽힘)."""
    cat = 카탈로그(); vs = 버전목록(cat); ch = 읽기(표(cat, "rtms_changes", CHANGES))
    검증 = {r["version"]: r for r in 검증결과(cat)}
    보는칸 = ("aptNm", "aptDong", "floor", "excluUseAr", "dealYear", "dealMonth", "dealDay", "dealAmount", "deposit", "monthlyRent", "cdealType", "cdealDay", "rgstDate")
    def 줄요약(js):
        if not js: return None
        r = json.loads(js); return {k: r.get(k) for k in 보는칸 if r.get(k) not in (None, "")}
    # ① 원천 스냅샷(최근 14개)
    스냅 = []
    for s in 스냅샷들()[-14:]:
        d, m = load(s); ps = m["parts"]
        스냅.append({"snap": s, "at": m.get("at"), "묶음": len(ps), "OK": sum(1 for p in ps.values() if p["status"] == "OK"),
                    "줄": sum(p["rows"] for p in ps.values()),
                    "전체수맞음": sum(1 for p in ps.values() if p.get("total") is not None and p["total"] == p["rows"]),
                    "전체수기록": sum(1 for p in ps.values() if p.get("total") is not None),
                    "묶음들": [{"name": n, "status": p["status"], "rows": p["rows"], "total": p.get("total"), "sha": p["sha256"][:12]} for n, p in sorted(ps.items())] if s == 스냅샷들()[-1] else None})
    # ④ 버전 · 검증 · 변경
    op수 = collections.defaultdict(collections.Counter)
    for x in ch: op수[x["version"]][x["op"] + ("_애매" if x["amb"] else "") + ("_늦게" if x["late"] else "")] += 1
    버전 = [{**{k: v[k] for k in ("version", "snap", "snap_at", "rows", "n_i", "n_u", "n_d", "n_amb", "bundles_ok", "bundles_kept")},
             "ok1": 검증[v["version"]]["ok1"], "ok2": 검증[v["version"]]["ok2"], "원천줄": 검증[v["version"]]["원천줄"], "op": dict(op수[v["version"]])} for v in vs]
    바뀐칸수 = collections.Counter()
    원천변경 = [x for x in ch if not str(x["snap"]).startswith("restore_")]   # 되돌리기 버전은 원천 변경이 아니라 뺀다(이력에는 남김)
    for x in 원천변경:
        if x["op"] == "U" and x["changed_cols"]: 바뀐칸수.update(x["changed_cols"].split(","))
    U예 = [{"version": x["version"], "trade_id": x["trade_id"], "kind": x["kind"], "sgg": x["sgg"], "late": x["late"], "cols": x["changed_cols"],
            "앞": 줄요약(x["before_json"]), "뒤": 줄요약(x["after_json"])} for x in sorted(원천변경, key=lambda x: (-x["version"], x["trade_id"])) if x["op"] == "U"][:60]
    # 거래 이력 찾기용: 거래마다 처음(I) 요약 + 이후 변경(U · D)
    이력 = collections.defaultdict(list)
    for x in sorted(ch, key=lambda x: (x["version"], x["op"] != "D")):
        e = {"v": x["version"], "op": x["op"]}
        if x["op"] == "I": e["값"] = 줄요약(x["after_json"])
        elif x["op"] == "U": a_, b_ = json.loads(x["before_json"]), json.loads(x["after_json"]); e["바뀜"] = {k: [a_.get(k), b_.get(k)] for k in (x["changed_cols"] or "").split(",") if k}
        이력[x["trade_id"]].append(e)
    원본예 = None
    if 스냅샷들():
        d0, m0 = load(스냅샷들()[-1]); n0 = sorted(n for n, p in m0["parts"].items() if p["status"] == "OK" and p["rows"])[0]
        원본예 = {"묶음": n0, "줄": 묶음줄(d0, n0)[0]}
    out = {"만든때": D.datetime.now().isoformat(timespec="seconds"), "범위": "서울 강남 · 송파 · 노원 × 최근 3개월 × 아파트 매매 · 전월세", "원본예": 원본예,
           "스냅샷": 스냅, "버전": 버전, "바뀐칸": 바뀐칸수.most_common(12), "U예": U예, "이력": {str(k): v for k, v in 이력.items()},
           "보관일": 30}
    p = os.path.abspath(os.path.join(LAKE, "..", "dashboard.json"))
    tmp = p + ".tmp"; json.dump(out, open(tmp, "w", encoding="utf-8"), ensure_ascii=False); os.replace(tmp, p)
    print(f"→ {p} · 버전 {len(버전)} · 스냅샷 {len(스냅)} · U 예 {len(U예)} · 거래 {len(이력):,} · {os.path.getsize(p)/1024:.0f}KB")


비교칸 = ("umd_nm", "jibun", "bld_nm", "bld_dong", "deal_ymd", "deal_amount", "deposit", "monthly_rent", "exclu_use_ar", "floor_no",
         "build_year", "dealing_gbn", "cdeal_type", "rgst_date")


def 적재될값(kind, sgg, r):
    """원천 줄 → load_rtms 가 적재DB 에 넣는 값(비교칸만). 키 칸은 load_rtms.키값 그대로 · 나머지는 load_rtms 의 같은 변환(money · num · pick)."""
    from load_rtms import 키값, pick, num
    v = 키값(kind, sgg, r)
    v.update(build_year=num(pick(r, "buildYear"), int), dealing_gbn=pick(r, "dealingGbn"), cdeal_type=pick(r, "cdealType"), rgst_date=pick(r, "rgstDate"))
    return {k: v.get(k) for k in 비교칸}


def 같은값(a, b):
    if a in (None, "") and b in (None, ""): return True
    if a is None or b is None: return False
    try: return abs(float(a) - float(b)) < 1e-6
    except (TypeError, ValueError): return str(a).strip() == str(b).strip()


def cmd_trace(a):
    """한 거래 따라가기 자료 → data/dqm/trace.json: 마지막 스냅샷의 원천 줄마다 ① 원천 값 · ② 적재DB 의 같은 줄(load_rtms 와 같은 순번 키) 칸 비교 · ④ 버전 테이블 거래 번호.
    ③ 등급은 화면이 적재 번호(trade_sk)로 그때그때 적재DB 에서 읽는다."""
    from load_rtms import 묶음키들
    from svc_publish import env as svc_env, ms_conn
    cat = 카탈로그(); st = 표(cat, "rtms_state", STATE)
    snap = 스냅샷들()[-1]; d, m = load(snap)
    ids = collections.defaultdict(lambda: collections.defaultdict(list))   # 묶음 → 줄해시 → 거래 번호들
    for x in sorted(읽기(st), key=lambda x: x["trade_id"]): ids[f"{x['kind']}_{x['sgg']}_{x['ym']}"][x["row_hash"]].append(x["trade_id"])
    cur = ms_conn(svc_env()).cursor(); cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")
    요약 = collections.defaultdict(collections.Counter); 거래 = {}; 다른예 = collections.defaultdict(list); 칸다름 = collections.Counter()
    for name, p in sorted(m["parts"].items()):
        if p["status"] != "OK": continue
        kind, sgg, ym = name.rsplit("_", 2)
        cur.execute(f"SELECT trade_sk, nat_key, {', '.join(비교칸)} FROM silver.rtms_trade WHERE trade_kind = %s AND sgg_cd = %s AND deal_ymd LIKE %s", (kind, sgg, ym + "%"))
        db = {bytes(x[1]): (x[0], dict(zip(비교칸, x[2:]))) for x in cur.fetchall()}
        c = 요약[kind]
        for r, base, nat, _ in 묶음키들(kind, sgg, 묶음줄(d, name)):
            c["원천줄"] += 1
            pool = ids[name][row_hash(r)]; tid = pool.pop(0) if pool else None
            c["버전테이블에있음"] += tid is not None
            e = {"k": kind, "s": sgg, "m": ym, "t": tid, "원천": {k: v for k, v in r.items() if v not in (None, "")}}
            if nat in db:
                sk, dv = db[nat]; c["적재에있음"] += 1; ev = 적재될값(kind, sgg, r)
                비교 = [[k, ev[k], (float(dv[k]) if hasattr(dv[k], "is_finite") else dv[k]), 같은값(ev[k], dv[k])] for k in 비교칸 if not (ev[k] in (None, "") and dv[k] in (None, ""))]
                다 = all(x[3] for x in 비교); c["칸모두같음" if 다 else "칸다름"] += 1
                if not 다:
                    for x in 비교:
                        if not x[3]: 칸다름[x[0]] += 1
                    if len(다른예[kind]) < 5: 다른예[kind].append(tid)
                e.update(sk=sk, 비교=비교)
            else: c["적재에없음"] += 1
            if tid is not None: 거래[str(tid)] = e
    out = {"만든때": D.datetime.now().isoformat(timespec="seconds"), "snap": snap, "요약": {k: dict(v) for k, v in 요약.items()},
           "칸다름": 칸다름.most_common(), "다른예": dict(다른예), "거래": 거래}
    p = os.path.abspath(os.path.join(LAKE, "..", "trace.json")); tmp = p + ".tmp"
    json.dump(out, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, default=str); os.replace(tmp, p)
    for k, v in 요약.items(): print(f"  {k}: {dict(v)}")
    print(f"→ {p} · 거래 {len(거래):,} · 칸 다름 {dict(칸다름)} · {os.path.getsize(p)/1024:.0f}KB")


def cmd_restore(a):
    """버전 N 의 내용으로 새 버전을 만든다(Iceberg 스냅샷을 되감지 않는다 — 되돌린 것도 이력에 남는다)."""
    cat = 카탈로그(); vs = 버전목록(cat); v = 버전찾기(vs, a.version)
    st = 표(cat, "rtms_state", STATE); ch = 표(cat, "rtms_changes", CHANGES); vt = 표(cat, "rtms_versions", VERSIONS)
    then = 읽기(st, snapshot_id=v["state_snapshot_id"]); now = {x["trade_id"]: x for x in 읽기(st)}
    ver = vs[-1]["version"] + 1; snap = f"restore_v{v['version']}"; props = {"dqm.version": str(ver), "dqm.snap": snap}
    th = {x["trade_id"]: x for x in then}; 변경 = []
    for tid, x in now.items():
        if tid not in th:
            변경.append(dict(version=ver, snap=snap, op="D", amb=False, late=False, trade_id=tid, kind=x["kind"], sgg=x["sgg"], ym=x["ym"], changed_cols=None,
                             before_json=x["row_json"], after_json=None, before_hash=x["row_hash"], after_hash=None))
        elif th[tid]["row_hash"] != x["row_hash"]:
            y = th[tid]
            변경.append(dict(version=ver, snap=snap, op="U", amb=False, late=False, trade_id=tid, kind=x["kind"], sgg=x["sgg"], ym=x["ym"],
                             changed_cols=",".join(바뀐칸(json.loads(x["row_json"]), json.loads(y["row_json"]))),
                             before_json=x["row_json"], after_json=y["row_json"], before_hash=x["row_hash"], after_hash=y["row_hash"]))
    for tid, y in th.items():
        if tid not in now:
            변경.append(dict(version=ver, snap=snap, op="I", amb=False, late=False, trade_id=tid, kind=y["kind"], sgg=y["sgg"], ym=y["ym"], changed_cols=None,
                             before_json=None, after_json=y["row_json"], before_hash=None, after_hash=y["row_hash"]))
    if a.dry:
        print(f"(미리보기) v{v['version']} 로 되돌리면 새 버전 v{ver}: " + str(collections.Counter(x["op"] for x in 변경))); return
    st.overwrite(표로(then, STATE), snapshot_properties=props)
    if 변경: ch.append(표로(변경, CHANGES), snapshot_properties=props)
    st.refresh(); ch.refresh(); sid = st.current_snapshot().snapshot_id
    st.manage_snapshots().create_tag(sid, f"v{ver}", max_ref_age_ms=30 * 86400 * 1000).commit()
    cnt = collections.Counter(x["op"] for x in 변경)
    vt.append(표로([dict(version=ver, snap=snap, snap_at=None, built_at=D.datetime.now().isoformat(timespec="seconds"), rows=len(then),
                        n_i=cnt["I"], n_u=cnt["U"], n_d=cnt["D"], n_amb=0, bundles_ok=0, bundles_kept=0,
                        state_snapshot_id=sid, changes_snapshot_id=ch.current_snapshot().snapshot_id)], VERSIONS), snapshot_properties=props)
    print(f"v{v['version']} 내용으로 새 버전 v{ver} 를 만들었다: {dict(cnt)}")


def cmd_expire(a):
    cat = 카탈로그(); cut = int((time.time() - a.days * 86400) * 1000); n = 0
    for name in ("rtms_state", "rtms_changes", "rtms_versions"):
        t = cat.load_table(f"{NS}.{name}"); old = [s for s in t.snapshots() if s.timestamp_ms < cut]
        if old and not a.dry:
            try: t.maintenance.expire_snapshots().older_than(D.datetime.fromtimestamp(cut / 1000)).commit()
            except Exception as e: print(f"  !! {name} 정리 실패: {e!r}"[:300])
        n += len(old); print(f"  {name}: {a.days}일 넘은 스냅샷 {len(old)}" + (" (미리보기)" if a.dry else ""))
    print("끝" if n else "정리할 것 없음")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("build"); sp.add_parser("versions"); sp.add_parser("check"); sp.add_parser("dashboard"); sp.add_parser("trace")
    s = sp.add_parser("asof"); s.add_argument("--version", type=int); s.add_argument("--date"); s.add_argument("--trade", type=int)
    s = sp.add_parser("changes"); s.add_argument("--since", type=int, default=0); s.add_argument("--show", type=int, default=5); s.add_argument("--out")
    s = sp.add_parser("restore"); s.add_argument("--version", type=int, required=True); s.add_argument("--dry", action="store_true")
    s = sp.add_parser("expire"); s.add_argument("--days", type=int, default=30); s.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    if a.cmd == "asof" and a.version is None and not a.date: ap.error("--version 이나 --date")
    globals()["cmd_" + a.cmd](a)
