# -*- coding: utf-8 -*-
"""juso_vm - 작업 줄이 막혔을 때 VM 에서 juso 를 물어 SQL 파일로 낸다(load_juso.py 와 같은 칸 · 같은 원문). (2026-10-23)
   py juso_vm.py 물을말.txt 출처 출력.sql   → /api/_apply?file=출력  로 넣는다. 키(.env JUSO_KEY)는 안 찍는다."""
import io, json, os, sys, time, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
E = {}
for line in io.open(os.path.join(HERE, "..", ".env"), encoding="utf-8-sig"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); E[k.strip()] = v.strip().strip('"')
KEY = E.get("JUSO_KEY", "")
src, 출처, out = sys.argv[1], sys.argv[2], sys.argv[3]
kws = [l.strip() for l in io.open(src, encoding="utf-8") if l.strip()]
def q(v):
    if v is None: return "NULL"
    if isinstance(v, int): return str(v)
    return "N'" + str(v).replace("'", "''") + "'"
def s(v):
    v = None if v is None else str(v).strip(); return v or None
def i(v):
    try: return int(str(v).strip())
    except Exception: return None
lines = ["SET NOCOUNT ON;"]
n0 = n1 = nm = 0
for kw in kws:
    p = urllib.parse.urlencode({"confmKey": KEY, "currentPage": "1", "countPerPage": "20", "keyword": kw, "resultType": "json"})
    for t in range(4):
        try:
            raw = urllib.request.urlopen("https://business.juso.go.kr/addrlink/addrLinkApi.do?" + p, timeout=30).read().decode("utf-8", "replace"); break
        except Exception:
            time.sleep(1.5 * (t + 1)); raw = None
    if raw is None: continue
    j = json.loads(raw); c = (j.get("results") or {}).get("common") or {}
    if s(c.get("errorCode")) != "0": print("멈춤", c.get("errorCode"), c.get("errorMessage")); break
    rows = (j.get("results") or {}).get("juso") or []
    n0 += not rows; n1 += len(rows) == 1; nm += len(rows) > 1
    lines.append(f"IF NOT EXISTS (SELECT 1 FROM silver.juso_lookup WHERE keyword = {q(kw)}) BEGIN "
                 f"INSERT INTO silver.juso_lookup (keyword, 출처, total_count, error_code, error_message, raw) VALUES ({q(kw)}, {q(출처)}, {i(c.get('totalCount')) or 0}, {q(s(c.get('errorCode')))}, {q(s(c.get('errorMessage')))}, {q(raw)});")
    for k, x in enumerate(rows, 1):
        lines.append(f"INSERT INTO silver.juso_result (keyword, 순, road_addr, jibun_addr, adm_cd, rn_mgt_sn, rn, udrt_yn, buld_mnnm, buld_slno, mt_yn, lnbr_mnnm, lnbr_slno, bd_mgt_sn, bd_nm, bd_kdcd) VALUES ("
                     + ", ".join([q(kw), str(k), q(s(x.get('roadAddr'))), q(s(x.get('jibunAddr'))), q(s(x.get('admCd'))), q(s(x.get('rnMgtSn'))), q(s(x.get('rn'))),
                                  q(s(x.get('udrtYn'))), q(i(x.get('buldMnnm'))), q(i(x.get('buldSlno'))), q(s(x.get('mtYn'))), q(i(x.get('lnbrMnnm'))),
                                  q(i(x.get('lnbrSlno'))), q(s(x.get('bdMgtSn'))), q(s(x.get('bdNm'))), q(s(x.get('bdKdcd')))]) + ");")
    lines.append("END")
lines.append("GO\nEXEC meta.usp_road_code_from_juso;")
io.open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print(f"물음 {len(kws)} · 0건 {n0} · 1건 {n1} · 여럿 {nm} → {out}")
