# -*- coding: utf-8 -*-
"""load_lawd_api - 법정동코드 목록(meta.lawd_code)을 **행정안전부 법정동코드 API**(StanReginCd, data.go.kr 15077871)로 맞춘다 (2026-10-28)
  사장님 "대구 구지면이 없어" — 구지면 → 구지읍(2026-09-30 시행, 코드 2771038000 → 2771026800). 국토부 파일(data.go.kr 15063424)은
  아직 2026-06-30 판이라 새 코드가 없고, 건축물대장(허브)은 이미 새 코드로 온다(68개 코드 · 대장 15,654줄이 목록 밖).
  ★ API = 지금 살아 있는 코드 전부. 없던 코드는 넣고, 목록에는 있는데 API 에 없는 코드는 is_abolished = 1(지우지 않는다).
  ★ 시도 · 시군구 이름은 DB 에 이미 있는 그 시군구 행 이름을 쓴다(일반구 '수원시영통구' 처럼 지금 표기와 같게). 읍면동 · 리 이름은 API 그대로.
  py load_lawd_api.py            미리 보기(바꾸지 않음)
  py load_lawd_api.py --apply    넣기"""
import json, sys, time, urllib.request, urllib.parse
from svc_publish import env, ms_conn
APPLY = "--apply" in sys.argv
k = env().get("DATA_GO_KR_KEY")
def 쪽(n):
    u = "https://apis.data.go.kr/1741000/StanReginCd/getStanReginCdList?" + urllib.parse.urlencode({"serviceKey": k, "type": "json", "pageNo": n, "numOfRows": 1000})
    for 번 in range(5):
        try:
            j = json.loads(urllib.request.urlopen(u, timeout=60).read().decode("utf-8"))
            return int(j["StanReginCd"][0]["head"][0]["totalCount"]), j["StanReginCd"][1]["row"]
        except Exception as e:
            time.sleep(3 * (번 + 1)); err = e
    raise RuntimeError(f"{n}쪽 실패: {err}")
tot, rows = 쪽(1); n = 1
while len(rows) < tot:
    n += 1; _, r = 쪽(n); rows += r
    if not r: break
api = {r["region_cd"]: r for r in rows}
print(f"API 코드 {len(api):,} (totalCount {tot:,}) · {n}쪽", flush=True)
if len(api) != tot: print("!! 받은 수가 totalCount 와 다름 — 폐지 표시는 안 한다", flush=True)
cur = ms_conn(env()).cursor()
cur.execute("SELECT lawd_cd, sido_nm, sgg_nm, emd_nm, ri_nm, CAST(is_abolished AS INT) FROM meta.lawd_code")
db = {r[0]: r for r in cur.fetchall()}
새 = [c for c in api if c not in db]
없어짐 = [c for c, r in db.items() if c not in api and not r[5] and not c.endswith("00000000")] if len(api) == tot else []   # 시도 행은 건드리지 않는다(세종 3600000000 은 API 에 3611 로만 있다)
되살 = [c for c, r in db.items() if c in api and r[5]]
def 이름(c):
    r = api[c]; 시군구행 = db.get(c[:5] + "00000") or (api.get(c[:5] + "00000") and None)
    sido = (db.get(c[:2] + "00000000") or [None, None])[1]
    sgg = 시군구행[2] if 시군구행 else None
    if not sido or (c[2:5] != "000" and not sgg):   # DB 에 시도 · 시군구 행이 없으면 API 주소를 나눈다
        p = r["locatadd_nm"].split(); sido = sido or p[0]
        if c[2:5] != "000" and not sgg: sgg = "".join(p[1:len(p) - (c[5:8] != "000") - (c[8:] != "00")]) or None
    emd = ri = None
    if c[5:8] != "000":
        if c[8:] == "00": emd = r["locallow_nm"]
        else:
            ri = r["locallow_nm"]; e = api.get(c[:8] + "00"); emd = e["locallow_nm"] if e else (db.get(c[:8] + "00") or [None]*4)[3]
    if c[2:5] == "000": sgg = None
    return sido, sgg, emd, ri, " ".join(x for x in (sido, sgg, emd, ri) if x)
print(f"새 코드 {len(새)} · 목록엔 있는데 API 에 없음(폐지로 표시) {len(없어짐)} · 폐지였다가 다시 살아 있음 {len(되살)}", flush=True)
for c in 새[:15]: print("  +", c, 이름(c)[4], api[c].get("adpt_de"))
for c in 없어짐[:10]: print("  -", c, db[c][1], db[c][2], db[c][3], db[c][4])
if APPLY:
    for c in 새:
        sido, sgg, emd, ri, full = 이름(c)
        cur.execute("INSERT INTO meta.lawd_code (lawd_cd, sido_nm, sgg_nm, emd_nm, ri_nm, full_nm, loaded_at) VALUES (%s,%s,%s,%s,%s,%s,SYSDATETIME())", (c, sido, sgg, emd, ri, full))
    for c in 없어짐: cur.execute("UPDATE meta.lawd_code SET is_abolished = 1 WHERE lawd_cd = %s", (c,))
    print(f"넣음 {len(새)} · 폐지 표시 {len(없어짐)}", flush=True)
