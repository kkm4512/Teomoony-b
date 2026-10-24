# -*- coding: utf-8 -*-
"""학교알리미 적재 — 학교기본정보(apiType 0) + 학년별·학급별 학생수(apiType 09)   2026-10-23

  py load_schoolinfo.py                 서울 25개 구 · 초·중·고 · 올해 공시
  py load_schoolinfo.py --sgg 11290     고른 구만
  py load_schoolinfo.py --yr 2024 2025 2026   공시연도(여럿 — 최근 3년만 공시)
  py load_schoolinfo.py --stat-only     기본정보는 건너뛰고 학생(09) · 전출입(10)만
  py load_schoolinfo.py --probe         한 구 초등만 떠서 보여준다

출처 / 라이선스
  학교알리미 OpenAPI (한국교육학술정보원) https://www.schoolinfo.go.kr/openApi.do
  이용허락: 출처 표시 시 자유 이용. 요청 제한 없음. 공시 최근 3년만.
  키: .env SCHOOLINFO_KEY (사장님 발급)

★ apiType 은 **문자열 '09'** 다('9' 로 부르면 fail — 실측).
★ sidoCode 만 주면 0건이 온다(실측) → 구(sggCode)마다 부른다.
★ 2026-10-24: apiType 10(전·출입 및 학업중단 학생 수)도 받는다 — silver.schoolinfo_move.
★ 값은 **공시값 그대로** 저장한다 — 학급당 학생수 · 수업교원 1인당 학생수도 우리가 나누지 않는다.
★ 구조가 바뀌면 조용히 0건으로 끝내지 않고 받은 것을 찍고 멈춘다.
"""
import argparse, json, os, sys, time, datetime
import requests, pymssql

HERE = os.path.dirname(os.path.abspath(__file__))
ENV  = os.path.join(HERE, "..", ".env")
URL  = "https://www.schoolinfo.go.kr/openApi.do"
KR   = (32.0, 39.7, 124.0, 132.2)
KND  = ["02", "03", "04"]


def load_env(p):
    d = {}
    for line in open(p, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line: continue
        k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d


def num(s):
    try: return float(str(s).strip())
    except (TypeError, ValueError): return None


def i(s):
    v = num(s)
    return int(v) if v is not None else None


def call(key, typ, sgg, knd, yr=None):
    p = {"apiKey": key, "apiType": typ, "sidoCode": sgg[:2], "sggCode": sgg, "schulKndCode": knd}
    if yr: p["pbanYr"] = str(yr)
    for a in range(4):
        try:
            r = requests.get(URL, params=p, timeout=40)
            d = r.json()
            if d.get("resultCode") != "success":
                # 그 구에 그 학교급이 없으면 fail 이 오기도 한다 — 메시지를 그대로 찍는다
                return None, d.get("resultMsg")
            L = d.get("list")
            if not isinstance(L, list):
                sys.exit(f"구조가 바뀜: {list(d.keys())}")
            return L, None
        except (requests.RequestException, ValueError) as e:
            time.sleep(2 + a * 3)
            last = str(e)
    return None, "호출 실패: " + last


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sgg", nargs="*")
    ap.add_argument("--yr", type=int, nargs="*", default=[datetime.date.today().year])
    ap.add_argument("--stat-only", action="store_true")
    ap.add_argument("--probe", action="store_true")
    a = ap.parse_args()
    env = load_env(ENV)
    key = env.get("SCHOOLINFO_KEY", "").strip()
    if not key: sys.exit(".env 에 SCHOOLINFO_KEY 가 없습니다")

    conn = pymssql.connect(server=env.get("DB_HOST", "127.0.0.1"), port=int(env.get("DB_PORT", 11433)),
                           user=env.get("DB_USER", "sa"), password=env.get("DB_PASSWORD", ""),
                           database=env.get("DB_NAME", "Teomoony"), charset="UTF-8", autocommit=False)
    cur = conn.cursor()
    if a.sgg: sggs = list(a.sgg)
    else:
        cur.execute("SELECT DISTINCT sigungu_cd FROM gold.complex WHERE is_active = 1 AND sigungu_cd LIKE '11%' ORDER BY sigungu_cd")
        sggs = [r[0] for r in cur.fetchall()]
    if a.probe: sggs = sggs[:1]
    print(f"대상 구 {len(sggs)}개 · 공시연도 {a.yr}", flush=True)
    nm = 0

    nb = ns = nogeo = 0; 실패 = []
    for sgg in sggs:
        for knd in (KND[:1] if a.probe else KND):
            L, err = ([], None) if a.stat_only else call(key, "0", sgg, knd)
            if L is None: 실패.append((sgg, knd, "기본", err)); continue
            if a.probe: print(json.dumps(L[:1], ensure_ascii=False)[:1500])
            for d in L:
                lat, lng = num(d.get("LTTUD")), num(d.get("LGTUD"))
                if lat is None or lng is None or not (KR[0] <= lat <= KR[1] and KR[2] <= lng <= KR[3]):
                    lat = lng = None; nogeo += 1
                code = d.get("SCHUL_CODE")
                if not code: continue
                cur.execute("DELETE FROM silver.schoolinfo WHERE schul_code = %s", (code,))
                cur.execute("""INSERT INTO silver.schoolinfo (schul_code, schul_nm, knd_code, fond_sc, fond_ymd, adrcd_cd, road_addr,
                                 addr_brkdn, dtlad_brkdn, lat, lng, close_yn, bnhh_yn, coedu, hmpg, raw_json, collected_at)
                               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s, CONVERT(date, SYSDATETIME()))""",
                            (code, d.get("SCHUL_NM"), d.get("SCHUL_KND_SC_CODE"), d.get("FOND_SC_CODE"), d.get("FOND_YMD"),
                             d.get("ADRCD_CD"), d.get("SCHUL_RDNMA"), d.get("ADRES_BRKDN"), d.get("DTLAD_BRKDN"),
                             lat, lng, d.get("CLOSE_YN"), d.get("BNHH_YN"), d.get("COEDU_SC_CODE"), d.get("HMPG_ADRES"),
                             json.dumps(d, ensure_ascii=False)))
                nb += 1
            for yr in a.yr:
                S, err = call(key, "09", sgg, knd, yr)
                if S is None: 실패.append((sgg, knd, f"학생{yr}", err)); continue
                if a.probe: print(json.dumps(S[:1], ensure_ascii=False)[:800])
                for d in S:
                    code = d.get("SCHUL_CODE")
                    if not code: continue
                    cur.execute("DELETE FROM silver.schoolinfo_stat WHERE schul_code = %s AND pban_yr = %s", (code, yr))
                    cur.execute("""INSERT INTO silver.schoolinfo_stat (schul_code, pban_yr, class_cnt, stdnt_cnt, per_class, teach_cnt,
                                     per_teacher, excp_yn, excp_rsn, raw_json, collected_at)
                                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s, CONVERT(date, SYSDATETIME()))""",
                                (code, yr, i(d.get("COL_C_SUM")), i(d.get("COL_S_SUM")), num(d.get("COL_SUM")),
                                 i(d.get("TEACH_CNT")), num(d.get("TEACH_CAL")), d.get("PBAN_EXCP_YN"), d.get("PBAN_EXCP_RSN"),
                                 json.dumps(d, ensure_ascii=False)))
                    ns += 1
                M, err = call(key, "10", sgg, knd, yr)
                if M is None: 실패.append((sgg, knd, f"전출입{yr}", err)); continue
                for d in M:
                    code = d.get("SCHUL_CODE")
                    if not code: continue
                    cur.execute("DELETE FROM silver.schoolinfo_move WHERE schul_code = %s AND pban_yr = %s", (code, yr))
                    cur.execute("""INSERT INTO silver.schoolinfo_move (schul_code, pban_yr, mvin_cnt, mvt_cnt, stdnt_cnt, excp_yn, raw_json, collected_at)
                                   VALUES (%s,%s,%s,%s,%s,%s,%s, CONVERT(date, SYSDATETIME()))""",
                                (code, yr, i(d.get("MVIN_SUM")), i(d.get("MVT_SUM")), i(d.get("STDNT_SUM")), d.get("PBAN_EXCP_YN"),
                                 json.dumps(d, ensure_ascii=False)))
                    nm += 1
                conn.commit()
            conn.commit()
        print(f"  {sgg}  누적 기본 {nb:,} · 학생 {ns:,} · 전출입 {nm:,}", flush=True)
        if a.probe: break
    print(f"\n기본정보 {nb:,} · 학생·교원 {ns:,} · 전출입 {nm:,} · 좌표없음 {nogeo} · 실패 {len(실패)}")
    for f in 실패[:20]: print("   실패", f)
    conn.close()


if __name__ == "__main__":
    main()
