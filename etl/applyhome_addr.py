# -*- coding: utf-8 -*-
"""applyhome_addr - 청약 공고 주소(글자) → 법정동 코드 · 지번 조각 — **전국** (2026-10-29 사장님 "남은것도 너가해")
  정책 1장 '문자열 매칭을 허용하는 예외'(주소 → 코드)와 같은 길: 우리 법정동 마스터(meta.lawd_code)의 이름과 **글자 그대로** 맞을 때만.
  ★ 하나로 정해지지 않으면 NULL(추측하지 않는다): 같은 이름 둘 이상 · 읍·면인데 리가 없음(리가 있는 읍·면은 어느 리인지 모름 — 363 과 같은 규칙) ·
    일반구가 있는 시인데 구가 없음(그 시의 구들 중 동 이름이 하나뿐일 때만).
  ★ 옛 이름: 광주광역시 · 전라남도 → 전남광주통합특별시(마스터에 옛 이름 줄이 없다) · 강원도 → 강원특별자치도 · 전라북도 → 전북특별자치도."""
import re
SIDO = {"서울": "서울특별시", "서울시": "서울특별시", "서울특별시": "서울특별시", "부산": "부산광역시", "부산시": "부산광역시", "부산광역시": "부산광역시",
        "대구": "대구광역시", "대구시": "대구광역시", "대구광역시": "대구광역시", "인천": "인천광역시", "인천시": "인천광역시", "인천광역시": "인천광역시",
        "광주광역시": "전남광주통합특별시", "광주": "전남광주통합특별시", "전라남도": "전남광주통합특별시", "전남": "전남광주통합특별시", "전남광주통합특별시": "전남광주통합특별시",
        "대전": "대전광역시", "대전시": "대전광역시", "대전광역시": "대전광역시", "울산": "울산광역시", "울산시": "울산광역시", "울산광역시": "울산광역시",
        "세종": "세종특별자치시", "세종시": "세종특별자치시", "세종특별자치시": "세종특별자치시", "경기": "경기도", "경기도": "경기도",
        "강원": "강원특별자치도", "강원도": "강원특별자치도", "강원특별자치도": "강원특별자치도", "충북": "충청북도", "충청북도": "충청북도",
        "충남": "충청남도", "충청남도": "충청남도", "전북": "전북특별자치도", "전라북도": "전북특별자치도", "전북특별자치도": "전북특별자치도",
        "경북": "경상북도", "경상북도": "경상북도", "경남": "경상남도", "경상남도": "경상남도", "제주": "제주특별자치도", "제주도": "제주특별자치도", "제주특별자치도": "제주특별자치도"}
# ★ 시군구 개편 — 마스터(meta.lawd_code)에 옛 줄이 없다(2026-07 이후 판). 인천광역시 행정체제 개편(2026-07-01 시행):
#   중구 · 동구 → 제물포구 · 영종구, 서구 → 서해구 · 검단구. 옛 이름이면 새 구들에서 **동(리)이 하나로 정해질 때만** 쓴다.
SGG개편 = {("인천광역시", "중구"): ("제물포구", "영종구"), ("인천광역시", "동구"): ("제물포구",), ("인천광역시", "서구"): ("서해구", "검단구")}
EMD = r"[가-힣0-9·]+?(?:동\d*가|\d*동|가|읍|면)"
JIBUN = r"(산)?\s*(\d+)(?:\s*-\s*(\d+))?(?![\d.]|가)"   # ★ '영등포동3가' 의 3 을 지번으로 읽지 않게(뒤에 '가' 가 오면 동 이름의 일부)

class 사전:
    """meta.lawd_code 지금 줄(ri 포함) → 찾기 표"""
    def __init__(self, rows):   # rows: (lawd_cd, sido_nm, sgg_nm, emd_nm, ri_nm[, is_abolished])
        self.sgg = {}; self.emd = {}; self.ri읍면 = set(); self.옛sgg = {}; self.옛emd = set()
        for row in rows:
            cd, sd, sg, em, ri = row[:5]
            if not sd or not sg: continue
            sg = sg.replace(" ", "")
            if len(row) > 5 and row[5]:          # 없어진 줄 — 개편 전 이름을 알아보는 데만 쓴다(코드로는 안 쓴다)
                self.옛sgg.setdefault(sd, set()).add(sg)
                if em: self.옛emd.add((sd, sg, em, ri or None))
                continue
            self.sgg.setdefault(sd, {}).setdefault(sg, set()).add(cd[:5])
            if em:
                self.emd.setdefault((sd, sg, em, ri or None), set()).add(cd)
                if ri: self.ri읍면.add((sd, sg, em))
    def 시군구(self, sd, toks):
        """→ (sgg_nm 또는 시 접두, 쓴 토큰 수, 접두냐)"""
        c = self.sgg.get(sd, {})
        if sd == "세종특별자치시": return ("세종시", 1 if toks and toks[0] == "세종시" else 0, False)
        if len(toks) >= 2 and toks[0] + toks[1] in c: return (toks[0] + toks[1], 2, False)
        # 일반구가 있는 시인데 구가 없음('안양시 박달동') — 시 줄(동 없음)만 있으므로 그 시의 구들에서 찾는다(동이 하나뿐일 때만)
        if toks and toks[0].endswith("시") and any(k != toks[0] and k.startswith(toks[0]) for k in c): return (toks[0], 1, True)
        if toks and toks[0] in c: return (toks[0], 1, False)
        if toks and toks[0].endswith("시") and any(k.startswith(toks[0]) for k in c): return (toks[0], 1, True)   # 수원시(구 없음)
        o = self.옛sgg.get(sd, set())
        if len(toks) >= 2 and toks[0] + toks[1] in o: return (toks[0] + toks[1], 2, False)
        if toks and toks[0] in o: return (toks[0], 1, False)            # 개편으로 없어진 시군구(인천 중구 2026-07 등) — 동은 아래 '개편' 길로만
        return (None, 0, False)
    def 개편(self, sd, sg, em, ri):
        """옛 시군구(sg)에 그 동(리)이 있었고, 지금 같은 시도에 그 동(리) 이름이 **하나뿐**이면 그 코드. (2026-10-29 인천 개편: 서구 당하동 → 검단구)"""
        if (sd, sg, em, ri or None) not in self.옛emd: return None
        hit = set()
        for (s1, g1, e1, r1), cds in self.emd.items():
            if s1 == sd and e1 == em and (r1 or None) == (ri or None): hit |= cds
        return min(hit) if len(hit) == 1 else None
    def 코드(self, sd, sg, 접두, em, ri):
        hit = set()
        for (s1, g1, e1, r1), cds in self.emd.items():
            if s1 != sd or e1 != em or (r1 or None) != (ri or None): continue
            if (g1.startswith(sg) if 접두 else g1 == sg): hit |= cds
        return min(hit) if len(hit) == 1 else None, len(hit)

def 조각(adr, dic):
    a = re.sub(r'([가-힣]+로)\s+(\d+가)(?=\s)', r'\1\2', adr or '')
    a = re.sub(r'([가-힣]+동)\s+(\d+가)(?=\s)', r'\1\2', a).replace(",", " , ")     # '당산동 6가 280-1' → '당산동6가 280-1'
    d = dict(sgg=None, sgg_cd=None, emd=None, san=None, bun=None, ji=None, 도로=None, 건물본번=None, 건물부번=None, 근거="못 품", cd=None)
    toks = a.split()
    if not toks or toks[0] not in SIDO: return d
    sd = SIDO[toks[0]]
    if len(toks) > 1 and (sd, toks[1]) in SGG개편 and toks[1] not in dic.sgg.get(sd, {}):
        got = [(n, 조각(" ".join([toks[0], n] + toks[2:]), dic)) for n in SGG개편[(sd, toks[1])]]
        ok = [(n, x) for n, x in got if x["cd"]]
        if len({x["cd"] for _, x in ok}) == 1:
            n, x = ok[0]; x["근거"] = f"시군구 개편({toks[1]} → {n}) · " + x["근거"]; return x
        d["근거"] = f"못 품 · 시군구 개편({toks[1]}) — 새 구가 하나로 안 정해짐"; return d
    sg, used, 접두 = dic.시군구(sd, toks[1:])
    if not sg:
        # '서울특별시 고덕강일 공공주택지구 1블록(서울특별시 강동구 고덕동 136 일원)' — 괄호 안 주소를 처음부터 다시
        for k in re.finditer(r"[(,]\s*(\S+)", a):
            if k.group(1) in SIDO:
                d2 = 조각(a[k.start(1):], dic)
                if d2["cd"]: d2["근거"] = "괄호 안 주소 · " + d2["근거"]; return d2
        d["근거"] = "못 품 · 시군구 못 찾음"; return d
    d["sgg"] = sg
    if not 접두:
        cds = dic.sgg[sd].get(sg, set())
        if len(cds) == 1: d["sgg_cd"] = next(iter(cds))
    rest = " ".join(toks[1 + used:])
    def 찾기(em, ri):
        if not ri and any(k[0] == sd and (k[1].startswith(sg) if 접두 else k[1] == sg) and k[2] == em for k in dic.ri읍면):
            return None, " · 리 있는 읍·면인데 리 없음"      # 읍·면 줄 자체(리 없음)에 붙이지 않는다 — 지번은 어느 리의 것인지 모름
        cd, n = dic.코드(sd, sg, 접두, em, ri)
        if not cd and n == 0 and not 접두:
            cd2 = dic.개편(sd, sg, em, ri)
            if cd2: return cd2, " · 행정구역 개편(옛 시군구의 같은 동 — 지금 시도에 하나)"
        if not cd and not ri and re.search(r"\d+동$", em):
            cd2, n2 = dic.코드(sd, sg, 접두, re.sub(r"\d+동$", "동", em), None)
            if cd2: return cd2, " · 행정동 이름에서 숫자 뗌"
        return cd, ("" if cd else (" · 법정동 여럿" if n > 1 else " · 법정동 못 찾음"))
    m = re.match(rf"({EMD})\s*(?:([가-힣0-9]+리)\s*)?{JIBUN}", rest)   # '자곡동347-5' 처럼 붙여 쓴 것도
    if m:
        em, ri = m.group(1), m.group(2)
        cd, why = 찾기(em, ri)
        d.update(emd=em + (" " + ri if ri else ""), san="1" if m.group(3) else "0", bun=m.group(4), ji=m.group(5) or "0", 근거="법정동 그대로" + why, cd=cd)
        if cd: d["sgg_cd"] = cd[:5]
        return d
    # 괄호 · 쉼표 뒤 '(… 시도 시군구 동 지번)' 처럼 주소가 통째로 다시 오면 그것을 처음부터 다시 읽는다
    for k in re.finditer(r"[(,]\s*(\S+)", rest):
        if k.group(1) in SIDO:
            d2 = 조각(rest[k.start(1):], dic)
            if d2["cd"]: d2["근거"] = "괄호 안 주소 · " + d2["근거"]; return d2
    p = re.search(rf"(?:\(|,\s*)\s*(?:[가-힣]+[구군시]\s+)?({EMD})(?:\s+([가-힣0-9]+리))?\s*{JIBUN}", rest)
    if p:
        em, ri = p.group(1), p.group(2)
        cd, why = 찾기(em, ri)
        d.update(emd=em + (" " + ri if ri else ""), san="1" if p.group(3) else "0", bun=p.group(4), ji=p.group(5) or "0", 근거="괄호 안 지번" + why, cd=cd)
        if cd: d["sgg_cd"] = cd[:5]
        return d
    r = re.match(r"([가-힣0-9.]+?(?:대로|로|길)(?:\s*\d+(?:번)?(?:가)?길)?)\s*(\d+)(?:-(\d+))?(?=$|[\s(,일번])", rest)
    if r:
        d.update(도로=re.sub(r"\s+", "", r.group(1)), 건물본번=int(r.group(2)), 건물부번=int(r.group(3)) if r.group(3) else None, 근거="도로명만 — 대장 대조 대기")
        q = re.search(rf"\(\s*({EMD})", rest)     # 괄호 안 동 이름(지번 없이) — 296 ① 이 시군구 + 동으로 한 번 더
        if q: d["emd"] = q.group(1)
    return d
