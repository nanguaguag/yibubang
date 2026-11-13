// Private, immutable page images. Google only signs links; bytes stay on R2.
const encoder = new TextEncoder();
const validKey = /^textbooks\/tb_[a-f0-9]{12}\/[a-f0-9]{16}\/(pages|thumbnails)\/[0-9]{4}\.webp$/;
async function signature(secret, message) {
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), {name: 'HMAC', hash: 'SHA-256'}, false, ['sign']);
  const bytes = new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(message)));
  return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
}
function equal(a, b) {
  if (typeof a !== 'string' || a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const key = url.pathname.substring(1);
    if (!validKey.test(key)) return new Response('Not found', {status: 404});
    if (request.method === 'PUT') {
      // Only the local resumable uploader owns this separate administrative key.
      if (!env.UPLOAD_KEY || !equal(request.headers.get('Authorization'), 'Bearer '+env.UPLOAD_KEY)) return new Response('Unauthorized', {status: 401});
      const length = Number(request.headers.get('Content-Length'));
      if (!Number.isFinite(length) || length <= 0 || length > 8*1024*1024) return new Response('Invalid image size', {status: 413});
      const bytes = await request.arrayBuffer();
      if (bytes.byteLength !== length || String.fromCharCode(...new Uint8Array(bytes.slice(0,4))) !== 'RIFF' ||
          String.fromCharCode(...new Uint8Array(bytes.slice(8,12))) !== 'WEBP') return new Response('Invalid WebP', {status: 400});
      const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)), b => b.toString(16).padStart(2,'0')).join('');
      if (!equal(request.headers.get('X-Content-SHA256'),hash)) return new Response('Checksum mismatch', {status: 400});
      await env.PAGES.put(key,bytes,{httpMetadata:{contentType:'image/webp',cacheControl:'private, max-age=31536000, immutable'},customMetadata:{sha256:hash}});
      return Response.json({uploaded:true,sha256:hash});
    }
    if (request.method !== 'GET' && request.method !== 'HEAD') return new Response('Method not allowed', {status:405});
    if (!env.SIGNING_KEY) return new Response('Service unavailable',{status:503});
    const now = Math.floor(Date.now()/1000);
    const expires = url.searchParams.get('expires');
    if (!/^\d{10}$/.test(expires || '') || Number(expires)<now || Number(expires)>now+310) return new Response('Expired link',{status:403});
    const expected = await signature(env.SIGNING_KEY,key+'\n'+expires);
    if (!equal(url.searchParams.get('signature'),expected)) return new Response('Invalid signature',{status:403});
    // Authenticate first; cache by immutable object key, never by rotating token.
    const cache = globalThis.caches?.default;
    const cacheKey = new Request(url.origin+'/'+key);
    if (request.method === 'GET' && cache) {
      const cached = await cache.match(cacheKey);
      if (cached) {
        const headers = new Headers(cached.headers);
        headers.set('Cache-Control','private, max-age=300');
        headers.set('X-Page-Cache','HIT');
        return new Response(cached.body,{headers});
      }
    }
    const object = request.method === 'HEAD' ? await env.PAGES.head(key) : await env.PAGES.get(key);
    if (!object) return new Response('Not found',{status:404});
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('ETag',object.httpEtag);
    headers.set('Cache-Control','private, max-age=300');
    headers.set('X-Content-Type-Options','nosniff');
    const response = new Response(request.method === 'HEAD' ? null : object.body,{headers});
    if (request.method === 'GET' && cache) {
      const copy = response.clone();
      const cacheHeaders = new Headers(copy.headers);
      cacheHeaders.set('Cache-Control','public, max-age=86400');
      await cache.put(cacheKey,new Response(copy.body,{headers:cacheHeaders}));
    }
    return response;
  }
};
