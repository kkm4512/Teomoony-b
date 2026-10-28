# 새 전국 주소 해석을 지금 공고 994건(서울·안양)에 돌려 저장된 법정동 코드와 견준다 — DB 는 안 바꾼다
from svc_publish import env, ms_conn
from applyhome_addr import 사전, 조각
cur = ms_conn(env()).cursor()
cur.execute("SELECT lawd_cd, sido_nm, sgg_nm, emd_nm, ri_nm, is_abolished FROM meta.lawd_code"); dic = 사전(cur.fetchall())
cur.execute("SELECT hssply_adres, lawd_cd, 주소근거 FROM silver.applyhome_pblanc")
same = diff = new_only = old_only = both_none = 0; ex = []
for adr, old, why in cur.fetchall():
    d = 조각(adr, dic); new = d["cd"]
    if '도로명' in (why or '') and not new: continue          # 296 이 채운 것 — 파이썬 단계 비교 밖
    if old and new: (same := same + 1) if old == new else None
    if old and new and old != new: diff += 1; ex.append(("다름", adr, old, new, d["근거"]))
    elif new and not old: new_only += 1; ex.append(("새것만", adr, old, new, d["근거"]))
    elif old and not new: old_only += 1; ex.append(("옛것만", adr, old, new, d["근거"]))
    elif not old and not new: both_none += 1
print(f"같음 {same} · 다름 {diff} · 새것만 {new_only} · 옛것만 {old_only} · 둘다없음 {both_none}")
for e in [x for x in ex if x[0] == '다름'][:10] + [x for x in ex if x[0] == '옛것만'][:15] + [x for x in ex if x[0] == '새것만'][:5]: print(e)
tests = ["경기도 수원시 장안구 정자동 111", "충청남도 아산시 배방읍 장재리 1800", "충청남도 아산시 배방읍 1800", "세종특별자치시 산울동 123", "부산광역시 기장군 일광읍 삼성리 92-1",
         "광주광역시 북구 문흥동 1010-7", "전라남도 순천시 조례동 766", "경기도 용인시 수지구 풍덕천동 1167", "경기도 수원시 정자동 111", "강원도 춘천시 석사동 682-1", "대구광역시 중구 남산동 2477-1",
         "인천광역시 서구 당하동 1235(아라역 금강펜테리움 더 시글로 1차)", "인천광역시 중구 신흥동3가 7-79번지 외 25필지", "인천광역시 서구 불로동 864번지", "인천광역시 서구 청라동 1-1"]
for t in tests: d = 조각(t, dic); print(t, "→", d["cd"], d["sgg"], d["emd"], d["bun"], d["ji"], d["근거"])
