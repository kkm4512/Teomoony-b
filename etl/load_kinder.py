# -*- coding: utf-8 -*-
"""유치원 적재 — 유치원알리미 (교육부 / 한국교육학술정보원)  2026-10-19

  py load_kinder.py                    목표에 있는 시군구 전부
  py load_kinder.py --sgg 11380 41171  고른 시군구만
  py load_kinder.py --probe            한 구만 떠서 구조를 보여준다

★ **basicInfo2.do 를 쓴다.** basicInfo.do 에는 **좌표가 없다**(실측).
  data.go.kr 설명에는 '위치정보' 가 있다고 적혀 있지만 그건 2 쪽 이야기다.
  설명을 믿지 말고 찍어 보라는 교훈이 또 맞았다.

★ 래퍼는 `kinderInfo` 다. `response` 가 아니다 - 학교 API 와 또 다르다.
  구조가 바뀌면 **조용히 0건으로 끝내지 않고** 받은 키를 찍고 멈춘다.

★ 공시 데이터라 **1년에 2회**만 갱신된다. 응답의 pbnttmng(예: 20261 =
  2026년 1차)를 **그대로 저장**한다. 화면이 '언제 기준인지' 를 말할 수 있게.

★ 좌표는 한반도 밖이면 **좌표만 비운다**(고치지 않는다). 위경도가 뒤바뀐
  6건 때문에 적재가 통째로 죽은 적이 있다(CONTEXT 11-50).
"""
import argparse, json, os, sys, time
import requests, pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
URL  = "https://e-childschoolinfo.moe.go.kr/api/notice/basicInfo2.do"
KR   = (32.0, 39.7, 124.0, 132.2)          # lat_min, lat_max, lon_min, lon_max


def load_env(p):
    d = {}
    if not os.path.exists(p): return d
    for line in open(p, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line: continue
        k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def num(s):
    try: return float(str(s).strip())
    except (TypeError, ValueError): return None


def i(s):
    try: return int(float(str(s).strip()))
    except (TypeError, ValueError): return None


def xy(lat_s, lon_s):
    """한반도 밖이면 좌표만 비운다. 고치려 들지 않는다."""
    lat, lon = num(lat_s), num(lon_s)
    if lat is None or lon is None: return None, None, "없음"
    if not (KR[0] <= lat <= KR[1] and KR[2] <= lon <= KR[3]):
        return None, None, "범위밖"
    return lat, lon, None


def fetch(key, sido, sgg):
    for a in range(3):
        try:
            r = requests.get(URL, params={"key": key, "sidoCode": sido, "sggCode": sgg},
                             timeout=40)
            r.raise_for_status()
            j = r.json()
            break
        except Exception as e:
            if a == 2: raise
            time.sleep(1.5 * (a + 1))
    if j.get("status") != "SUCCESS":
        raise SystemExit(f"  응답이 SUCCESS 가 아니다: {j.get('status')} — 멈춥니다")
    items = j.get("kinderInfo")
    if items is None:
        raise SystemExit("  래퍼 'kinderInfo' 가 없다 — 응답 구조가 바뀌었는지 확인하라.\n"
                         "  받은 최상위 키: " + ", ".join(sorted(j.keys())))
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", nargs="*")
    ap.add_argument("--probe", action="store_true")
    a = ap.parse_args()

    env = load_env(ENV)
    key = env.get("KINDER_KEY", "").strip()
    if not key:
        sys.exit(".env 에 KINDER_KEY 가 없습니다 (유치원알리미 인증키)")

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"),
                           port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"),
                           password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"),
                           charset="UTF-8", autocommit=False)
    cur = conn.cursor()

    if a.sgg:
        sggs = list(a.sgg)
    else:
        cur.execute("SELECT DISTINCT sigungu_cd FROM gold.complex "
                    "WHERE is_active = 1 AND sigungu_cd IS NOT NULL ORDER BY sigungu_cd")
        sggs = [r[0] for r in cur.fetchall()]
    if a.probe: sggs = sggs[:1]
    print(f"대상 시군구 {len(sggs)}개: {', '.join(sggs)}")

    tot = ok = nogeo = 0
    for sgg in sggs:
        sido = sgg[:2]
        items = fetch(key, sido, sgg)
        tot += len(items)
        if a.probe:
            print(json.dumps(items[0], ensure_ascii=False, indent=2)[:1200]); return

        rows = []
        for d in items:
            lat, lng, why = xy(d.get("lttdcdnt"), d.get("lngtcdnt"))
            if lat is None: nogeo += 1
            rows.append((
                d.get("kindercode"), d.get("kindername"), d.get("establish"),
                d.get("officeedu"), d.get("subofficeedu"), sgg,
                d.get("addr"), d.get("telno"), d.get("hpaddr"), d.get("opertime"),
                d.get("edate"), d.get("odate"), d.get("pbnttmng"),
                i(d.get("prmstfcnt")),
                (i(d.get("ppcnt3")) or 0) + (i(d.get("ppcnt4")) or 0)
                + (i(d.get("ppcnt5")) or 0) + (i(d.get("mixppcnt")) or 0)
                + (i(d.get("shppcnt")) or 0),
                (i(d.get("clcnt3")) or 0) + (i(d.get("clcnt4")) or 0)
                + (i(d.get("clcnt5")) or 0) + (i(d.get("mixclcnt")) or 0)
                + (i(d.get("shclcnt")) or 0),
                lat, lng))

        for r in rows:
            cur.execute("DELETE FROM silver.kindergarten WHERE kinder_cd = %s", (r[0],))
            cur.execute("""
              INSERT INTO silver.kindergarten
                (kinder_cd, kinder_nm, establish, office_edu, suboffice_edu, sgg_cd,
                 addr, tel_no, hp_addr, oper_time, est_date, open_date, pbnt_tmng,
                 cap_cnt, pupil_cnt, class_cnt, lat, lng, geog, collected_at)
              SELECT %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
                     CASE WHEN %s IS NOT NULL
                          THEN geography::Point(%s, %s, 4326) END,
                     CONVERT(date, SYSDATETIME())""",
              (r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9],
               r[10], r[11], r[12], r[13], r[14], r[15], r[16], r[17],
               r[16], r[16], r[17]))
            ok += 1
        conn.commit()
        print(f"  {sgg}  {len(items):4d}곳 -> {len(rows)} 적재")

    cur.execute("SELECT COUNT(*) FROM silver.kindergarten")
    print(f"\n유치원 {ok:,}건 넣음 (총 {cur.fetchone()[0]:,}) · 좌표없음 {nogeo}")
    if nogeo:
        print("  ★ 좌표가 없는 곳은 지도·거리에서 빠집니다 — 없는 게 아니라 못 보는 것입니다")
    cur.execute("SELECT DISTINCT pbnt_tmng FROM silver.kindergarten ORDER BY pbnt_tmng")
    print("  공시 차수:", ", ".join(str(r[0]) for r in cur.fetchall() if r[0]))
    conn.close()


if __name__ == "__main__":
    main()
