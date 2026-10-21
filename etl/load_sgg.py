#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
load_sgg - 시군구 하나를 끝까지 적재하는 드라이버

★ 여러 지역을 반복해서 넓힐 거라면 **run_plan.py 를 쓴다** (2026-10-17).
  이쪽은 "이 시군구를 지금 처음부터 끝까지" 용이다. run_plan 은 목표를 DB 에
  선언해 두고 **남은 일을 계산해서** 돌린다 — 끊겨도 그냥 다시 돌리면 되고,
  지역이 늘어도 명령이 안 는다. 둘이 같은 적재기를 부르므로 결과는 같다.


  py load_sgg.py --sgg 11380                      # 은평구 전체
  py load_sgg.py --sgg 11110 --only ext           # 종로구에 동 아래 세 축만
  py load_sgg.py --sgg 11290 --only ext --bjdong 13800     # 장위동만
  py load_sgg.py --sgg 11380 --ext-ops flr,expos  # 주택가격은 빼고

순서가 중요하다
---------------------------------------------------------------
  1 lawd       법정동코드          <- 없으면 실거래가가 못 붙는다
  2 bld        건축물대장 4종      <- 기본개요가 먼저여야 단지가 묶인다
  3 build      단지 구성
  4 ext        층별개요·전유부·주택가격   <- 동 아래. 배치도가 이걸 쓴다
  5 cadastral  연속지적도(필지)
  6 building   건물 외곽선
  7 rtms       실거래가 10종
  8 kapt       K-apt 단지
  9 cost       관리비

건너뛰기 판정 (2026-10-17 교체)
---------------------------------------------------------------
★ 예전에는 `silver.bld_basis_outline` 에 행이 있으면 **그 법정동의 대장 4종을
  통째로 건너뛰었다.** 두 가지가 틀렸다:

    · 기본개요만 들어가고 표제부가 끊긴 법정동을 영영 다시 안 받는다
      (정릉동 표제부가 1,700/6,029 에서 멈춰 있던 것이 이 경우다)
    · 나중에 op 를 추가하면 **이미 적재된 지역에는 영영 안 들어간다**
      — 층별개요·전유부·주택가격이 딱 이 상황이었다

  이제 `meta.ingest_run` 을 본다. op 하나하나에 대해 그 법정동에서
  `status='OK'` 로 끝난 기록이 있을 때만 건너뛴다. 정책 6장이 정한 근거다.
"""
import argparse, os, subprocess, sys, time
import progress
import pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")

BLD_OPS = ["getBrBasisOulnInfo", "getBrTitleInfo",
           "getBrRecapTitleInfo", "getBrAtchJibunInfo"]

# 동 아래 세 축. 이름 -> op
EXT_ALIAS = {"flr":   "getBrFlrOulnInfo",
             "expos": "getBrExposInfo",
             "hsprc": "getBrHsprcInfo"}


def load_env(p):
    d = {}
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def conn(env):
    return pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=True)


def run(script, *args):
    cmd = [sys.executable, os.path.join(HERE, script), *map(str, args)]
    r = subprocess.run(cmd, cwd=HERE)
    return r.returncode == 0


def ok_ops(cur, sgg, bjd):
    """이 법정동에서 status='OK' 로 끝난 operation 집합.

    scope_key 는 적재기가 'sigungu/bjdong' 으로 넣는다(teomoony_ingest.cmd_load).
    """
    cur.execute("""
        SELECT DISTINCT s.operation
          FROM meta.ingest_run r
          JOIN meta.api_source s ON s.source_id = r.source_id
         WHERE r.status = 'OK' AND r.scope_key = %s""", (f"{sgg}/{bjd}",))
    return {row[0] for row in cur.fetchall()}


def run_ops(cur, sgg, lawds, ops, label, force):
    """법정동 x op 를 돌리되, 이미 OK 인 op 는 건너뛴다."""
    print("\n" + "="*64 + f"\n{label} ({len(lawds)}개 법정동 x {len(ops)}종)\n" + "="*64)
    did = skipped = failed = 0
    pg = progress.Progress(len(lawds), label)
    for lawd, nm in lawds:
        bjd = lawd[5:]
        have = set() if force else ok_ops(cur, sgg, bjd)
        todo = [o for o in ops if o not in have]
        if not todo:
            skipped += 1
            pg.tick(f"{nm or lawd} 건너뜀")
            continue
        print(f"\n  {nm or lawd} ({lawd})  할 일 {len(todo)}종: {', '.join(o[5:] for o in todo)}")
        ok = True
        for op in todo:
            if not run("teomoony_ingest.py", "load", "--op", op,
                       "--sigungu", sgg, "--bjdong", bjd):
                ok = False
                print(f"    ! {op} 실패")
        did += ok; failed += (not ok)
        pg.tick(f"{nm or lawd}" + ("" if ok else "  ! 실패"))
    pg.done(f"적재 {did} / 건너뜀 {skipped} / 실패 {failed}")
    return failed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", required=True)
    ap.add_argument("--bjdong", nargs="*",
                    help="법정동 5자리만 골라서. 생략하면 시군구 전체")
    ap.add_argument("--from", dest="ym_from", default="202401")
    ap.add_argument("--to", dest="ym_to", default="202512")
    ap.add_argument("--only", action="append",
                    choices=["lawd","bld","build","ext","cadastral",
                             "building","rtms","kapt","cost"])
    ap.add_argument("--ext-ops", default="flr,expos,hsprc",
                    help="동 아래 축 중 고르기. 주택가격(hsprc)이 전체 분량의 60%% 를 먹는다")
    ap.add_argument("--skip-building", action="store_true")
    ap.add_argument("--force", action="store_true", help="OK 로 끝난 것도 다시")
    args = ap.parse_args()
    only = set(args.only or [])
    want = lambda s: (not only) or (s in only)

    bad = [k for k in args.ext_ops.split(",") if k.strip() and k.strip() not in EXT_ALIAS]
    if bad:
        sys.exit(f"--ext-ops 에 모르는 이름: {', '.join(bad)}  (쓸 수 있는 것: {', '.join(EXT_ALIAS)})")
    ext_ops = [EXT_ALIAS[k.strip()] for k in args.ext_ops.split(",") if k.strip()]

    env = load_env(ENV)
    t0 = time.time()

    # ---------- 1. 법정동코드 ----------
    if want("lawd"):
        print("\n" + "="*64 + "\n[1/9] 법정동코드\n" + "="*64)
        if not run("load_lawd.py", "--sgg", args.sgg):
            sys.exit("법정동코드 적재 실패")

    c = conn(env); cur = c.cursor()
    cur.execute("SELECT lawd_cd, emd_nm FROM meta.lawd_code WHERE sgg_cd=%s ORDER BY lawd_cd",
                (args.sgg,))
    lawds = cur.fetchall()
    if not lawds:
        sys.exit(f"시군구 {args.sgg} 의 법정동코드가 없습니다. --only lawd 로 먼저 채우세요.")
    if args.bjdong:
        keep = set(args.bjdong)
        lawds = [(l, n) for l, n in lawds if l[5:] in keep]
        if not lawds:
            sys.exit(f"지정한 법정동이 {args.sgg} 에 없습니다: {', '.join(args.bjdong)}")
    print(f"\n대상 법정동 {len(lawds)}개")

    # ---------- 2. 건축물대장 ----------
    if want("bld"):
        run_ops(cur, args.sgg, lawds, BLD_OPS, "[2/9] 건축물대장", args.force)

    # ---------- 3. 단지 구성 ----------
    if want("build"):
        print("\n" + "="*64 + "\n[3/9] 단지 구성\n" + "="*64)
        # 여기서 실패하면 뒤 단계가 "옛 단지" 로 돌아 조용히 틀린 결과를 낸다.
        if not run("teomoony_ingest.py", "build", "--sigungu", args.sgg):
            sys.exit("\n단지 구성 실패. 이후 단계는 옛 단지 데이터로 돌게 되므로 중단합니다.")

    # ---------- 4. 동 아래 세 축 ----------
    if want("ext"):
        run_ops(cur, args.sgg, lawds, ext_ops, "[4/9] 층별개요·전유부·주택가격", args.force)

    # ---------- 5~6. 지적/건물 ----------
    # ★ --lawd 를 반드시 넘긴다. 빼면 두 적재기가 **DB 에 적재된 전 법정동**을
    #   다시 내려받는다(각 스크립트의 기본값). 시군구 하나를 넣는데 다른 시군구까지
    #   전부 재다운로드되고, 범위를 넓힐수록 비용이 선형으로 는다.
    lawd_cds = [l for l, _ in lawds]

    if want("cadastral"):
        print("\n" + "="*64 + "\n[5/9] 연속지적도 (필지 폴리곤)\n" + "="*64)
        run("load_cadastral.py", "--lawd", *lawd_cds)

    if want("building") and not args.skip_building:
        print("\n" + "="*64 + "\n[6/9] 건물 외곽선\n" + "="*64)
        run("load_building.py", "--lawd", *lawd_cds)

    # ---------- 7. 실거래가 ----------
    if want("rtms"):
        print("\n" + "="*64 + "\n[7/9] 실거래가\n" + "="*64)
        run("load_rtms.py", "--sgg", args.sgg, "--from", args.ym_from, "--to", args.ym_to)

    # ---------- 8~9. K-apt / 관리비 ----------
    # ★ 예전에는 드라이버 밖에 있었다. 그래서 시군구를 통째로 넣어도
    #   K-apt 가 비어 관리비가 안 붙었다 — 종로구가 그 상태였다.
    if want("kapt"):
        print("\n" + "="*64 + "\n[8/9] K-apt 단지\n" + "="*64)
        run("load_kapt.py", "--sgg", args.sgg)

    if want("cost"):
        print("\n" + "="*64 + "\n[9/9] 관리비\n" + "="*64)
        run("load_kapt_cost.py", "--sgg", args.sgg,
            "--from", args.ym_from, "--to", args.ym_to)

    # ---------- 결과 ----------
    print("\n" + "="*64 + "\n결과\n" + "="*64)
    for label, sql in [
        ("법정동코드",  "SELECT COUNT(*) FROM meta.lawd_code WHERE sgg_cd='%s'" % args.sgg),
        ("기본개요",    "SELECT COUNT(*) FROM silver.bld_basis_outline WHERE is_current=1"),
        ("단지",        "SELECT COUNT(*) FROM gold.complex"),
        ("층별개요",    "SELECT COUNT(*) FROM silver.bld_flr_outline WHERE is_current=1"),
        ("전유부",      "SELECT COUNT(*) FROM silver.bld_expos WHERE is_current=1"),
        ("주택가격",    "SELECT COUNT(*) FROM silver.bld_hsprc WHERE is_current=1"),
        ("필지",        "SELECT COUNT(*) FROM silver.cadastral_parcel WHERE is_current=1"),
        ("건물",        "SELECT COUNT(*) FROM silver.building_footprint WHERE is_current=1"),
        ("실거래",      "SELECT COUNT(*) FROM silver.rtms_trade"),
    ]:
        try:
            cur.execute(sql)
            print(f"  {label:12s} {cur.fetchone()[0]:>12,}")
        except Exception as e:
            print(f"  {label:12s} {'(미생성)':>12}  {str(e)[:60]}")

    # ★ 이번 시군구에서 OK 로 못 끝난 적재를 드러낸다.
    #   '조용히 성공' 을 막는 장치다 (정책 7장).
    cur.execute("""
        SELECT s.operation, r.status, COUNT(*)
          FROM meta.ingest_run r
          JOIN meta.api_source s ON s.source_id = r.source_id
         WHERE r.scope_key LIKE %s AND r.status <> 'OK'
         GROUP BY s.operation, r.status ORDER BY 3 DESC""", (f"{args.sgg}/%",))
    bad_runs = cur.fetchall()
    if bad_runs:
        print(f"\n  ** OK 가 아닌 적재 ** (다시 돌리면 이어서 채운다)")
        for op, st, n in bad_runs:
            print(f"    {op:24s} {st:8s} {n:>5,}건")
    else:
        print(f"\n  이 시군구의 적재 기록은 전부 OK 입니다.")

    cur.execute("""SELECT COUNT(*), SUM(CASE WHEN match_complex_id IS NOT NULL THEN 1 ELSE 0 END),
                          SUM(CASE WHEN match_pnu IS NOT NULL THEN 1 ELSE 0 END),
                          SUM(CASE WHEN match_method='MASKED' THEN 1 ELSE 0 END)
                     FROM silver.rtms_trade""")
    tot, cx, pnu, msk = cur.fetchone()
    if tot:
        print(f"\n  실거래 매칭")
        print(f"    PNU 조립  {pnu or 0:>8,} / {tot:,}  ({100.0*(pnu or 0)/tot:5.1f}%)")
        print(f"    단지 매칭  {cx or 0:>8,} / {tot:,}  ({100.0*(cx or 0)/tot:5.1f}%)")
        print(f"    마스킹    {msk or 0:>8,} / {tot:,}  ({100.0*(msk or 0)/tot:5.1f}%)  <- 구조적 불가")
        able = tot - (msk or 0)
        if able:
            print(f"    마스킹 제외 단지 매칭률: {100.0*(cx or 0)/able:.1f}%")
    print(f"\n  총 소요 {(time.time()-t0)/60:.1f}분")
    c.close()


if __name__ == "__main__":
    main()
