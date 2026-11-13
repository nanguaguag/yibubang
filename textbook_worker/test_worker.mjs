import {webcrypto, createHash, createHmac} from 'node:crypto';
import fs from 'node:fs';
import assert from 'node:assert/strict';
globalThis.crypto = webcrypto;
const source=fs.readFileSync(new URL('./worker.js',import.meta.url),'utf8');
const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const key='textbooks/tb_123456789abc/123456789abcdef0/pages/0001.webp';
const objects=new Map();
let reads=0;
const env={SIGNING_KEY:'signing-secret',UPLOAD_KEY:'upload-secret',PAGES:{
  async put(key,bytes,options){objects.set(key,{bytes,options});},
  async get(key){reads++;const r=objects.get(key);return r ? {body:r.bytes,httpEtag:'etag',writeHttpMetadata(h){h.set('Content-Type','image/webp');}} : null;},
  async head(key){return this.get(key);},
}};
async function request(path,options={}){return worker.fetch(new Request('https://pages.example/'+path,options),env);}
assert.equal((await request(key)).status,403);
assert.equal(reads,0);
assert.equal((await request('../private.pdf')).status,404);
assert.equal((await request(key,{method:'PUT',headers:{Authorization:'Bearer wrong'}})).status,401);
const bytes=Buffer.from('RIFF0000WEBP');
const hash=createHash('sha256').update(bytes).digest('hex');
assert.equal((await request(key,{method:'PUT',headers:{Authorization:'Bearer upload-secret','Content-Length':String(bytes.length),'X-Content-SHA256':'wrong'},body:bytes})).status,400);
assert.equal(objects.size,0);
assert.equal((await request(key,{method:'PUT',headers:{Authorization:'Bearer upload-secret','Content-Length':String(bytes.length),'X-Content-SHA256':hash},body:bytes})).status,200);
const expires=Math.floor(Date.now()/1000)+300;
const sig=createHmac('sha256',env.SIGNING_KEY).update(key+'\n'+expires).digest('hex');
const good=await request(key+'?expires='+expires+'&signature='+sig);
assert.equal(good.status,200);
assert.equal(good.headers.get('Content-Type'),'image/webp');
assert.deepEqual(Buffer.from(await good.arrayBuffer()),bytes);
assert.equal((await request(key+'?expires='+expires+'&signature=wrong')).status,403);
assert.equal((await request(key+'?expires='+(expires+1000)+'&signature='+sig)).status,403);
const cacheObjects=new Map();
globalThis.caches={default:{
  async match(request){return cacheObjects.get(request.url)?.clone();},
  async put(request,response){cacheObjects.set(request.url,response.clone());},
}};
const address=key+'?expires='+expires+'&signature='+sig;
await request(address);
const previous=reads;
assert.equal((await request(address)).headers.get('X-Page-Cache'),'HIT');
assert.equal(reads,previous);
assert.equal((await request(key+'?expires='+expires+'&signature=wrong')).status,403);
assert.equal(reads,previous);
console.log('Worker authentication, expiry, bounds, upload checksum and signed image tests PASS');
