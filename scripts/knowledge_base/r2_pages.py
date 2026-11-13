#!/usr/bin/env python3
"""Deploy an isolated private page Worker; resume checksum-verified R2 uploads.

Uses a locally refreshed Wrangler OAuth credential, never copies it to an App.
"""
import argparse
from collections import deque
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3
import subprocess
import time

import httpx

ROOT=Path(__file__).resolve().parents[2]
LOCAL=ROOT/'ai_backend'/'.local'
ACCOUNT='d8ca70c45a2b0d30e885a2c3c6b6b7a7'
BUCKET='yibubang-textbooks'
WORKER='yibubang-textbook-pages'


def private_write(path, data):
    fd=os.open(path,os.O_CREAT|os.O_WRONLY|os.O_TRUNC,0o600)
    with os.fdopen(fd,'w') as f: json.dump(data,f)


def deploy():
    token=json.loads((LOCAL/'cloudflare-oauth.json').read_text())['access_token']
    client=httpx.Client(base_url='https://api.cloudflare.com/client/v4',
                        headers={'Authorization':'Bearer '+token},timeout=60)
    def api(method,path,**kwargs):
        response=client.request(method,f'/accounts/{ACCOUNT}'+path,**kwargs)
        if response.is_error:
            try:
                print(json.dumps(response.json().get('errors',[])),flush=True)
            except ValueError:
                print('Cloudflare error status '+str(response.status_code),flush=True)
        response.raise_for_status()
        data=response.json()
        if not data.get('success'): raise RuntimeError('Cloudflare API rejected '+path)
        return data.get('result')
    buckets=api('GET','/r2/buckets')['buckets']
    if not any(b['name']==BUCKET for b in buckets):
        api('POST','/r2/buckets',json={'name':BUCKET,'locationHint':'apac'})
    credentials=LOCAL/'textbook-worker.json'
    config=json.loads(credentials.read_text()) if credentials.exists() else {
        'account_id':ACCOUNT,'bucket':BUCKET,'worker':WORKER,
        'signing_key':secrets.token_hex(32),'upload_key':secrets.token_hex(32)}
    private_write(credentials,config)
    metadata={'main_module':'worker.js','compatibility_date':'2025-01-01',
              'bindings':[{'type':'r2_bucket','name':'PAGES','bucket_name':BUCKET}]}
    api('PUT',f'/workers/scripts/{WORKER}',files={
        'metadata':(None,json.dumps(metadata),'application/json'),
        'worker.js':('worker.js',(ROOT/'textbook_worker'/'worker.js').read_bytes(),'application/javascript+module')})
    for name,value in [('SIGNING_KEY',config['signing_key']),('UPLOAD_KEY',config['upload_key'])]:
        api('PUT',f'/workers/scripts/{WORKER}/secrets',json={'name':name,'text':value,'type':'secret_text'})
    subdomain=api('GET','/workers/subdomain')['subdomain']
    api('POST',f'/workers/scripts/{WORKER}/subdomain',json={'enabled':True})
    config['endpoint']=config.get('endpoint') or f'https://{WORKER}.{subdomain}.workers.dev'
    private_write(credentials,config)
    print(json.dumps({k:config[k] for k in ('bucket','worker','endpoint')}),flush=True)
    client.close()


def configure_cloud_run():
    config=json.loads((LOCAL/'textbook-worker.json').read_text())
    gcloud=str(Path.home()/'google-cloud-sdk'/'bin'/'gcloud')
    def run(*args,**kwargs):
        return subprocess.run([gcloud,*args,'--project=yibubang-search','--quiet'],check=True,**kwargs)
    run('services','enable','secretmanager.googleapis.com')
    name='yibubang-textbook-image-signing'
    existing=subprocess.run([gcloud,'secrets','describe',name,'--project=yibubang-search'],capture_output=True)
    if existing.returncode:
        run('secrets','create',name,'--replication-policy=automatic')
    keyfile=LOCAL/'textbook-signing-key'
    fd=os.open(keyfile,os.O_CREAT|os.O_WRONLY|os.O_TRUNC,0o600)
    with os.fdopen(fd,'w') as f: f.write(config['signing_key'])
    try:
        run('secrets','versions','add',name,'--data-file='+str(keyfile))
    finally:
        keyfile.unlink(missing_ok=True)
    run('secrets','add-iam-policy-binding',name,
        '--member=serviceAccount:yibubang-ai-runtime@yibubang-search.iam.gserviceaccount.com',
        '--role=roles/secretmanager.secretAccessor','--format=none')
    run('run','services','update','yibubang-ai-search','--region=asia-northeast1',
        '--update-env-vars=TEXTBOOK_IMAGE_ENDPOINT='+config['endpoint'],
        '--update-secrets=TEXTBOOK_IMAGE_SIGNING_KEY='+name+':latest')


def upload(output,workers,watch=False,variant="pages"):
    # OS-managed lock releases even after a terminated uploader; a second
    # process must not duplicate traffic or race the successful-upload ledger.
    import fcntl
    lock=(output/'.r2-upload.lock').open('a')
    try:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:
        lock.close()
        raise RuntimeError('A page upload is already running')
    config=json.loads((LOCAL/'textbook-worker.json').read_text())
    db=sqlite3.connect(output/'r2-upload.sqlite')
    db.execute('CREATE TABLE IF NOT EXISTS uploaded(key TEXT PRIMARY KEY,hash TEXT,bytes INTEGER)')
    state=dict(db.execute('SELECT key,hash FROM uploaded'))
    files=sorted((output/'images'/'textbooks').glob(f'*/*/{variant}/*.webp'))
    expected=sum(b['page_count'] for b in json.loads((output/'catalog.json').read_text())['books']) if watch else len(files)
    client=httpx.Client(base_url=config['endpoint'],timeout=60,
        limits=httpx.Limits(max_connections=workers,max_keepalive_connections=workers))
    def send(path):
        key=path.relative_to(output/'images').as_posix()
        content=path.read_bytes()
        digest=hashlib.sha256(content).hexdigest()
        if state.get(key)==digest: return key,digest,len(content),False
        for retry in range(5):
            try:
                response=client.put('/'+key,content=content,
                    headers={'Authorization':'Bearer '+config['upload_key'],'X-Content-SHA256':digest,'Content-Type':'image/webp'})
                response.raise_for_status()
                if response.json().get('sha256')!=digest: raise RuntimeError('remote checksum mismatch')
                return key,digest,len(content),True
            except httpx.HTTPError:
                if retry==4: raise
                time.sleep(min(2**retry,10))
    uploaded=0
    completed=0
    queued=set(files)
    ready=deque(files)
    available=files
    started=last_print=time.monotonic()
    last_scan=started
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures=set()
        while completed<expected:
            if time.monotonic()-started>14400:
                raise RuntimeError('Some local images are still unavailable; resume upload after rendering finishes')
            if watch and time.monotonic()-last_scan>=5:
                available=sorted((output/'images'/'textbooks').glob(f'*/*/{variant}/*.webp'))
                for path in available:
                    if path not in queued:
                        queued.add(path);ready.append(path)
                last_scan=time.monotonic()
            while ready and len(futures)<workers*4:
                futures.add(pool.submit(send,ready.popleft()))
            if futures:
                done,futures=wait(futures,timeout=10,return_when=FIRST_COMPLETED)
                for future in done:
                    key,digest,size,changed=future.result()
                    if changed:
                        db.execute('INSERT OR REPLACE INTO uploaded VALUES(?,?,?)',(key,digest,size));db.commit();uploaded+=1
                    completed+=1
            else:
                time.sleep(5)
            if time.monotonic()-last_print>40:
                print(f'R2 verified {completed}/{expected}; local pages {len(available)}; new uploads {uploaded}',flush=True)
                last_print=time.monotonic()
    count,size=db.execute('SELECT COUNT(*),SUM(bytes) FROM uploaded').fetchone()
    db.close()
    client.close()
    print(json.dumps({'objects':count,'bytes':size,'uploaded_now':uploaded}),flush=True)
    lock.close()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['deploy','configure','upload'])
    p.add_argument('--output',type=Path,default=Path('/Volumes/My PSSD/书籍/医不帮教材知识库'))
    p.add_argument('--workers',type=int,default=8)
    p.add_argument('--watch',action='store_true',help='Upload completed pages while local rendering continues')
    p.add_argument('--variant',choices=['pages','thumbnails'],default='pages')
    a=p.parse_args()
    LOCAL.mkdir(exist_ok=True)
    if a.action=='deploy':deploy()
    elif a.action=='configure':configure_cloud_run()
    else:upload(a.output,a.workers,a.watch,a.variant)


if __name__=='__main__':main()
