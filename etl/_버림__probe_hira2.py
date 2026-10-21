import io, json, urllib.parse, urllib.request
d={}
for l in io.open('../.env',encoding='utf-8-sig'):
    l=l.strip()
    if l and not l.startswith('#') and '=' in l:
        k,v=l.split('=',1); d[k.strip()]=v.strip()
key=d['DATA_GO_KR_KEY']; K=key if '%' in key else urllib.parse.quote(key)
def j(url,p):
    u=url+'?serviceKey='+K+'&'+urllib.parse.urlencode(p)
    with urllib.request.urlopen(u,timeout=30) as r: return json.loads(r.read().decode('utf-8'))
H='https://apis.data.go.kr/B551182/hospInfoServicev2/getHospBasisList'
for cd in ['01','10','11','12','13','14','49','80','23']:
    r=j(H,{'sidoCd':'110000','dgsbjtCd':cd,'numOfRows':'8','pageNo':'1','_type':'json'})
    b=r['response']['body']; it=b['items']['item'] if b.get('items') else []
    it=it if isinstance(it,list) else [it]
    print(cd, b.get('totalCount'), ' / '.join(f"{x['yadmNm']}({x['clCdNm']})" for x in it))
r=j('https://apis.data.go.kr/B551182/pharmacyInfoService/getParmacyBasisList',{'sidoCd':'110000','numOfRows':'1','pageNo':'1','_type':'json'})
print('약국 서울', r['response']['body']['totalCount'])
r=j(H,{'sidoCd':'310000','numOfRows':'1','pageNo':'1','_type':'json'}); print('경기 병원', r['response']['body']['totalCount'])
r=j(H,{'sidoCd':'110000','clCd':'31','numOfRows':'1','pageNo':'1','_type':'json'}); print('서울 의원(31)', r['response']['body']['totalCount'])
