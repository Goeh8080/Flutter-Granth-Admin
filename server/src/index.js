import { serveConfig, CONFIG_HEADERS, ensureBootstrap } from './config.js';
import { ingest } from './events.js';
import { handleAdmin } from './admin.js';
import { scheduled, syncCatalog } from './cron.js';

const CSP = "default-src 'self'; img-src 'self' https://granth.wnmsolutions.com data:; style-src 'self' 'unsafe-inline'; script-src 'self'; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const p = url.pathname;
    try {
      if (p === '/config.json') {
        if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-methods': 'GET, HEAD, OPTIONS', 'access-control-allow-headers': 'if-none-match', 'access-control-max-age': '86400' } });
        if (request.method !== 'GET' && request.method !== 'HEAD') return new Response('method not allowed', { status: 405, headers: { allow: 'GET, HEAD, OPTIONS' } });
        return await serveConfig(request, env, ctx);
      }
      if (p === '/events') {
        if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-methods': 'POST, OPTIONS', 'access-control-allow-headers': 'content-type, content-encoding', 'access-control-max-age': '86400' } });
        return await ingest(request, env, ctx);
      }
      if (p === '/health') return new Response(JSON.stringify({ ok: true }), { headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
      if (p.startsWith('/admin/api/')) return await handleAdmin(request, env, ctx, url);
      if (p === '/') return Response.redirect(url.origin + '/admin/', 302);
      if (p === '/admin') return Response.redirect(url.origin + '/admin/', 302);
      if (p.startsWith('/admin/')) {
        const res = await env.ASSETS.fetch(request);
        const r = new Response(res.body, res);
        r.headers.set('content-security-policy', CSP);
        r.headers.set('x-frame-options', 'DENY');
        r.headers.set('x-content-type-options', 'nosniff');
        r.headers.set('referrer-policy', 'no-referrer');
        if (/\/(index\.html)?$/.test(p) || p.endsWith('.js') || p.endsWith('.css')) r.headers.set('cache-control', 'no-cache');
        return r;
      }
      return new Response('Not found', { status: 404 });
    } catch (e) {
      console.error('unhandled', e && e.stack || e);
      return new Response(JSON.stringify({ error: 'internal' }), { status: 500, headers: { 'content-type': 'application/json' } });
    }
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(scheduled(event, env));
  },
};
