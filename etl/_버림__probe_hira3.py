import io, json, urllib.parse, urllib.request
d={}
for l in io.open('../.env',encoding='utf-8-sig'):
    l=l.strip()
    if l and not l.startswith('#') and '=' in l:
        k,v=l.split('=',1); d[k.strip()]=v.strip()
key=d['DATA_GO_KR_KEY']; K=key if '%' in key else urllib.parse.quote(key)
def j(p):
    u='https://apis.data.go.kr/B551182/hospInfoServicev2/getHospBasisList?serviceKey='+K+'&'+urllib.parse.urlencode(p)
    with urllib.request.urlopen(u,timeout=60) as r: return json.loads(r.read().decode('utf-8'))
W={'01':'내과','03':'정신','05':'정형','10':'산부인','11':'소아','12':'안과','13':'이비인후','14':'피부','15':'비뇨','21':'재활','23':'가정','49':'치과','80':'한'}
for cd,w in W.items():
    r=j({'sidoCd':'110000','sgguCd':'110005','clCd':'31' if cd not in('49','80') else ('51' if cd=='49' else '93'),'dgsbjtCd':cd,'numOfRows':'1000','pageNo':'1','_type':'json'})
    b=r['response']['body']; it=b['items']['item'] if b.get('items') else []
    it=it if isinstance(it,list) else [it]
    hit=sum(1 for x in it if w in x['yadmNm'])
    print(cd,w,'n',b.get('totalCount'),'이름에',hit, ' 예:', ' / '.join(x['yadmNm'] for x in it[:5]))
r=j({'sidoCd':'110000','numOfRows':'1000','pageNo':'1','_type':'json'}); it=r['response']['body']['items']['item']
from collections import Counter
print(Counter(f"{x['clCd']}{x['clCdNm']}" for x in it).most_common(20))
print(sorted({(x['sgguCd'],x['sgguCdNm']) for x in it})[:30])
