"""Real textbook retrieval, typed AI citation and private R2 image checks."""
import hashlib
import json
from pathlib import Path
import secrets
import time

import httpx

LOCAL=Path(__file__).parent/'.local'
ENDPOINT='https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app'


def main():
    identity=json.loads((LOCAL/'smoke-device.json').read_text())
    headers={'X-Device-ID':identity['installation_id'],'Authorization':'Bearer '+identity['secret']}
    report={'tested_at_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
    with httpx.Client(base_url=ENDPOINT,headers=headers,timeout=180) as client:
        report['quota_before']=client.get('/v1/quota').json()
        books=client.get('/v1/textbooks').json()['books']
        assert len(books)==53
        book=next(b for b in books if b['title']=='医学免疫学')
        search=client.post('/v1/textbooks/search',json={'question':'MHC I类分子 CD8 T细胞','request_id':secrets.token_hex(16),'book_id':book['book_id']})
        search.raise_for_status()
        items=search.json()['items']
        assert items and all(i['kind']=='textbook' and i['book_id']==book['book_id'] for i in items)
        report['retrieval']={'book_count':len(books),'hits':len(items),'citations':[{k:v for k,v in i.items() if k!='snippet'} for i in items[:3]]}
        # This page was also independently reached through the App UI.
        citation=json.loads((LOCAL/'textbook-app-live.json').read_text())['citation']
        path=f"/v1/textbooks/{citation['book_id']}/{citation['source_version']}/pages/{citation['pdf_page']}"
        before=client.get('/v1/quota').json()['remaining']
        page=client.get(path)
        page.raise_for_status()
        signed=page.json()
        start=time.monotonic()
        download=httpx.get(signed['url'],timeout=60)
        download.raise_for_status()
        download_seconds=round(time.monotonic()-start,2)
        assert download.headers['content-type'].startswith('image/webp')
        local=Path('/Volumes/My PSSD/书籍/医不帮教材知识库/images')/signed['image_key']
        assert hashlib.sha256(download.content).digest()==hashlib.sha256(local.read_bytes()).digest()
        assert client.get('/v1/quota').json()['remaining']==before,'Reading consumed an AI search'
        anonymous=httpx.get(ENDPOINT+path,timeout=30).status_code
        unsigned=httpx.get(signed['url'].split('?')[0],timeout=30).status_code
        tampered=httpx.get(signed['url'].replace('signature=','signature=bad'),timeout=30).status_code
        assert (anonymous,unsigned,tampered)==(401,403,403)
        report['image']={'bytes':len(download.content),'image_key':signed['image_key'],
            'sha256':hashlib.sha256(download.content).hexdigest(),'seconds':download_seconds,
            'no_search_quota_spent':True,'anonymous_status':anonymous,'unsigned_status':unsigned,'tampered_status':tampered}
        question='请依据医学免疫学教材说明MHC I类分子与CD8 T细胞的联系，并标明教材引用。'
        event='';answer='';citations=[];events=[]
        with client.stream('POST','/v1/search',json={'question':question,'request_id':secrets.token_hex(16)}) as result:
            result.raise_for_status()
            for line in result.iter_lines():
                if line.startswith('event:'):event=line[6:].strip()
                elif line.startswith('data:'):
                    data=json.loads(line[5:]);events.append(event)
                    if event=='delta':answer+=data['text']
                    elif event=='citations':citations=data['items']
                    elif event=='error':raise RuntimeError(data['message'])
        assert events[-1]=='done'
        assert any(c.get('kind')=='textbook' and c.get('pdf_page',0)>0 for c in citations)
        assert '[' in answer
        report['ai']={'answer':answer,'citations':citations,'delta_count':events.count('delta')}
        report['quota_after']=client.get('/v1/quota').json()
        assert report['quota_before']['remaining']-report['quota_after']['remaining']==2
    report['status']='PASS'
    (LOCAL/'textbook-smoke.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps({k:v for k,v in report.items() if k!='ai'},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
