import io, json, urllib.parse, urllib.request
d={}
for l in io.open('../.env',encoding='utf-8-sig'):
    l=l.strip()
    if l and not l.startswith('#') and '=' in l:
        k,v=l.split('=',1); d[k.strip()]=v.strip()
key=d['DATA_GO_KR_KEY']
def go(url, p):
    q=urllib.parse.urlencode(p)
    sep='&' if '?' in url else '?'
    u=url+sep+'serviceKey='+(key if '%' in key else urllib.parse.quote(key))+'&'+q
    try:
        with urllib.request.urlopen(u, timeout=30) as r: t=r.read().decode('utf-8','replace')
    except Exception as e: t='ERR '+str(e)
    return t.replace(key,'<KEY>')
for name,url,p in [
 ('병원 소아과 성북', 'https://apis.data.go.kr/B551182/hospInfoServicev2/getHospBasisList', {'sidoCd':'110000','sgguCd':'110017','dgsbjtCd':'11','numOfRows':'3','pageNo':'1','_type':'json'}),
 ('병원 전체 서울 건수', 'https://apis.data.go.kr/B551182/hospInfoServicev2/getHospBasisList', {'sidoCd':'110000','numOfRows':'1','pageNo':'1','_type':'json'}),
 ('약국 서울', 'https://apis.data.go.kr/B551182/pharmacyInfoService/getParmacyBasisList', {'sidoCd':'110000','numOfRows':'2','pageNo':'1','_type':'json'}),
]:
    print('==',name); print(go(url,p)[:900])
