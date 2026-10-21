# -*- coding: utf-8 -*-
"""
서울 25개 구를 적재 목표에 넣는다  (2026-10-20)

★ 구만 넣으면 된다. meta.v_load_plan 이 meta.lawd_code 로 **법정동까지 펼친다**
  (load_target.bjdong_cd 가 NULL 이면 그 구의 모든 법정동).
★ 이미 있는 구는 ops 를 덮지 않는다 - cmd_add 와 같은 이유다. 사람이 적어 둔
  비고와 순위를 조용히 지우면 안 된다.
★ 넣기만 하고 **받지는 않는다.** 얼마나 되는 일인지는 --dry-run 으로 따로 잰다.
"""
import argparse, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from teomoony_ingest import db_connect, q            # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", default="base,ext")
    ap.add_argument("--priority", type=int, default=200,
                    help="기존 목표(기본 100)보다 뒤로 둔다 - 하던 것을 먼저 끝낸다")
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--add-ops", default=None,
                    help="서울 목표의 ops 에 이 축들을 **덧붙인다**(쉼표). "
                         "덮지 않는다 - 사람이 적어 둔 설정을 지우지 않으려고.")
    a = ap.parse_args()

    cfg = json.load(open(a.config, encoding="utf-8"))
    conn = db_connect(cfg); cur = conn.cursor()

    # ---- ops 덧붙이기 모드 ----
    if a.add_ops:
        더할것 = [x.strip() for x in a.add_ops.split(",") if x.strip()]
        q(cur, """SELECT target_id, sgg_cd, bjdong_cd, ops FROM meta.load_target
                   WHERE enabled = 1 AND sgg_cd LIKE '11%' ORDER BY sgg_cd""")
        rows = cur.fetchall()
        바꾼수 = 0
        for tid, sgg, bjd, ops in rows:
            있는것 = [x.strip() for x in (ops or "").split(",") if x.strip()]
            새것 = [x for x in 더할것 if x not in 있는것]
            if not 새것:
                continue
            새ops = ",".join(있는것 + 새것)
            print(f"  {sgg}/{bjd or '(전체)'}  {ops}  ->  {새ops}")
            if not a.dry_run:
                q(cur, "UPDATE meta.load_target SET ops = %s WHERE target_id = %s",
                  (새ops, tid))
            바꾼수 += 1
        if not a.dry_run:
            conn.commit()
        print(f"\n{바꾼수}개 목표의 ops 에 {','.join(더할것)} 를 "
              + ("붙일 예정 (--dry-run)" if a.dry_run else "붙였습니다"))
        conn.close(); return

    q(cur, """SELECT DISTINCT sgg_cd, sgg_nm
                FROM meta.lawd_code
               WHERE sgg_cd LIKE '11%' AND emd_nm IS NOT NULL AND ri_nm IS NULL
               ORDER BY sgg_cd""")
    gus = cur.fetchall()
    print(f"서울 시군구 {len(gus)}개")

    # ★ "그 구가 목표에 있나" 가 아니라 **"구 전체 행이 있나"** 를 본다
    #   (2026-10-20). sgg_cd 로만 비교했더니 성북구(돈암·장위 둘뿐)와
    #   서초구(양재동 하나뿐)가 "이미 목표" 로 넘어갔다. 법정동 하나만 걸린 구를
    #   다 된 것으로 치면 **그 구는 영영 반쪽으로 남는다.** 조용히 빠지는 쪽이다.
    q(cur, """SELECT sgg_cd,
                     전체행 = MAX(CASE WHEN bjdong_cd IS NULL THEN 1 ELSE 0 END),
                     동행 = SUM(CASE WHEN bjdong_cd IS NULL THEN 0 ELSE 1 END)
                FROM meta.load_target WHERE enabled = 1 GROUP BY sgg_cd""")
    상태 = {r[0]: (int(r[1]), int(r[2])) for r in cur.fetchall()}

    새로, 그대로, 반쪽 = [], [], []
    for sgg, nm in gus:
        전체, 동 = 상태.get(sgg, (0, 0))
        if 전체:
            그대로.append((sgg, nm))
        elif 동:
            반쪽.append((sgg, nm, 동)); 새로.append((sgg, nm))
        else:
            새로.append((sgg, nm))
    print(f"  구 전체가 이미 목표: {len(그대로)}개 — " + ", ".join(n for _, n in 그대로))
    if 반쪽:
        print(f"  ** 법정동 일부만 걸려 있던 구 {len(반쪽)}개 — 전체 행을 새로 넣습니다:")
        for sgg, nm, c in 반쪽:
            print(f"       {sgg} {nm} (지금 {c}개 법정동만)")
    print(f"  새로 넣을 것: {len(새로)}개 — " + ", ".join(n for _, n in 새로))
    if a.dry_run:
        print("\n(--dry-run 이라 넣지 않았습니다)"); return

    for sgg, nm in 새로:
        q(cur, """INSERT INTO meta.load_target (sgg_cd, bjdong_cd, ops, priority, note)
                  VALUES (%s, NULL, %s, %s, %s)""",
          (sgg, a.ops, a.priority, f"서울 확장 2026-10-20 ({nm})"))
    conn.commit()
    print(f"\n{len(새로)}개 넣었습니다 (ops={a.ops}, priority={a.priority})")

    # ---- 이제 할 일이 얼마나 되는지 ----
    q(cur, """SELECT op_alias, 상태, 건수 = COUNT(*)
                FROM meta.v_load_plan
               WHERE sgg_cd LIKE '11%'
               GROUP BY op_alias, 상태 ORDER BY op_alias, 상태""")
    print("\n--- 서울 할 일 (법정동 x 축) ---")
    cur_op, line = None, []
    for op, st, n in cur.fetchall():
        if op != cur_op:
            if line: print(f"  {cur_op:<8} " + " · ".join(line))
            cur_op, line = op, []
        line.append(f"{st} {n:,}")
    if line: print(f"  {cur_op:<8} " + " · ".join(line))
    conn.close()


if __name__ == "__main__":
    main()
