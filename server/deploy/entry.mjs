// Deploy entry used when the Worker is uploaded through the Cloudflare API without the Workers-static-assets upload
// (that step needs a per-upload JWT header that the MCP connector cannot send). The SPA files are embedded in the
// bundle (deploy/embedded_assets.generated.mjs, produced by scripts/build_deploy.mjs) and exposed via an env.ASSETS shim
// with the same fetch() contract the Worker uses. With normal `wrangler deploy` (wrangler.toml) this file is NOT used.
import worker from '../src/index.js';
import { FILES } from './embedded_assets.generated.mjs';

function unb64(s) { const bin = atob(s); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u; }

const assets = {
  async fetch(request) {
    if (request.method !== 'GET' && request.method !== 'HEAD') return new Response('Method not allowed', { status: 405 });
    let p = new URL(request.url).pathname;
    if (p.endsWith('/')) p += 'index.html';
    const f = FILES[p];
    if (!f) return new Response('Not found', { status: 404 });
    const etag = `"${f.hash}"`;
    const headers = { 'content-type': f.type, etag, 'cache-control': 'public, max-age=0, must-revalidate' };
    if (request.headers.get('if-none-match') === etag) return new Response(null, { status: 304, headers });
    return new Response(request.method === 'HEAD' ? null : unb64(f.b64), { status: 200, headers });
  },
};

export default {
  fetch: (request, env, ctx) => worker.fetch(request, { ...env, ASSETS: assets }, ctx),
  scheduled: (event, env, ctx) => worker.scheduled(event, env, ctx),
};
