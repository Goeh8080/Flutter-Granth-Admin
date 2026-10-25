// End-to-end checks against any deployed base URL (local `wrangler dev` or workers.dev). No browser involved: plain HTTP.
// usage: BASE=https://… PW_FILE=secrets/admin_password.txt PUBKEY=<b64> node scripts/e2e.mjs [steps…]
// steps: public auth bearer edit settings validate rollback sort admins contacts events newgranth ratelimit   (default: all except newgranth/ratelimit)
import { readFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { createPublicKey, verify, createHash } from 'node:crypto';
import { canonical } from '../src/util.js';

const BASE = (process.env.BASE || 'http://127.0.0.1:8787').replace(/\/$/, '');
// Goutam's password: GRANTH_PANEL_PASSWORD env var (preferred for the live run) or PW_FILE (default secrets/admin_password.txt).
const PW = (process.env.PW_FILE || !process.env.GRANTH_PANEL_PASSWORD) ? readFileSync(process.env.PW_FILE || 'secrets/admin_password.txt', 'utf8').trim() : process.env.GRANTH_PANEL_PASSWORD;
const PUB = process.env.PUBKEY || '';
const steps = process.argv.slice(2);
const want = (s) => (steps.length ? steps.includes(s) : !['newgranth', 'ratelimit'].includes(s));
let pass = 0, failn = 0; const failures = [];
const ok = (c, msg, extra) => { if (c) { pass++; console.log('  PASS', msg); } else { failn++; failures.push(msg); console.log('  FAIL', msg, extra !== undefined ? JSON.stringify(extra).slice(0, 400) : ''); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let cookie = '', csrf = '';
async function api(method, path, body, opts = {}) {
  const headers = { ...(opts.headers || {}) };
  if (!opts.nocookie && cookie) headers.cookie = cookie;
  if (!opts.nocsrf && csrf && method !== 'GET') headers['x-admin-csrf'] = csrf;
  if (body !== undefined) headers['content-type'] = 'application/json';
  const res = await fetch(BASE + path, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined, redirect: 'manual' });
  let j = null; const t = await res.text(); try { j = JSON.parse(t); } catch { /* */ }
  return { status: res.status, json: j, headers: res.headers, text: t };
}
async function login(pw = PW) {
  const t0 = Date.now();
  const res = await fetch(BASE + '/admin/api/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: 'goutam', password: pw }) });
  const sc = res.headers.get('set-cookie') || '';
  return { status: res.status, setCookie: sc, ms: Date.now() - t0, body: await res.text() };
}
async function cfg() { const r = await fetch(BASE + '/config.json?_=' + Math.random()); return { status: r.status, etag: r.headers.get('etag'), json: await r.json(), headers: r.headers }; }
async function waitCfg(minVersion) { for (let i = 0; i < 30; i++) { const c = await cfg(); if (c.json.version >= minVersion) return c; await sleep(1500); } return cfg(); }
async function session() {
  const l = await login(); ok(l.status === 204, `login ok → 204 (${l.ms} ms wall)`, l);
  const m = l.setCookie.match(/^(__Host-granth_sid=[0-9a-f]{64})/); cookie = m ? m[1] : '';
  ok(/HttpOnly/i.test(l.setCookie) && /Secure/i.test(l.setCookie) && /SameSite=Strict/i.test(l.setCookie) && /Path=\//.test(l.setCookie), 'session cookie flags HttpOnly; Secure; SameSite=Strict', l.setCookie.replace(/=[0-9a-f]{64}/, '=…'));
  const me = await api('GET', '/admin/api/me'); csrf = me.json?.csrf || '';
  ok(me.status === 200 && csrf, '/me returns csrf', me.json && { ...me.json, csrf: '…' });
  return me.json;
}
const day = (o = 0) => new Date(Date.now() + o * 864e5).toISOString().slice(0, 10);
const rid = () => 'e2e' + Math.random().toString(36).slice(2, 12);
const iid = () => [...crypto.getRandomValues(new Uint8Array(16))].map((x) => x.toString(16).padStart(2, '0')).join('');

if (want('public')) {
  console.log('# public: config.json');
  const r1 = await fetch(BASE + '/config.json'); const txt = await r1.text(); const c = JSON.parse(txt);
  ok(r1.status === 200, 'config.json 200');
  const etag = r1.headers.get('etag');
  ok(!!etag, 'ETag present: ' + etag);
  ok(r1.headers.get('cache-control') === 'public, max-age=60, stale-while-revalidate=600', 'Cache-Control header', r1.headers.get('cache-control'));
  ok(r1.headers.get('access-control-allow-origin') === '*', 'CORS *');
  ok(c.schema === 1 && Number.isInteger(c.version) && c.endpoints?.config && c.endpoints?.events && c.structure?.religions?.length >= 6 && Array.isArray(c.hidden_granth_ids) && c.overrides && c.flags && c.announcement, 'schema fields present', Object.keys(c));
  const r2 = await fetch(BASE + '/config.json', { headers: { 'if-none-match': etag } });
  ok(r2.status === 304, 'If-None-Match → 304', r2.status);
  const r3 = await fetch(BASE + '/config.json', { headers: { 'if-none-match': 'W/' + etag.replace(/^W\//, '') } });
  ok(r3.status === 304, 'weak If-None-Match → 304', r3.status);
  const r4 = await fetch(BASE + '/config.json', { headers: { 'if-none-match': '"nope"' } });
  ok(r4.status === 200, 'stale If-None-Match → 200', r4.status);
  const r5 = await fetch(BASE + '/config.json', { headers: { 'accept-encoding': 'gzip' } });
  ok(r5.status === 200, 'gzip accept ok; response etag after compression: ' + r5.headers.get('etag'));
  if (PUB && c.sig) {
    const { sig, ...rest } = c;
    const key = createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(PUB, 'base64')]), format: 'der', type: 'spki' });
    ok(verify(null, Buffer.from(canonical(rest)), key, Buffer.from(sig, 'base64')), 'Ed25519 signature verifies with public key');
  } else console.log('  (no sig / PUBKEY: signature not checked)', !!c.sig);
  ok(r1.headers.get('x-content-type-options') === 'nosniff', 'nosniff');
  const o = await fetch(BASE + '/config.json', { method: 'OPTIONS' }); ok(o.status === 204, 'OPTIONS /config.json 204');
}

if (want('auth')) {
  console.log('# auth');
  for (const [m, p] of [['GET', '/admin/api/me'], ['GET', '/admin/api/granths'], ['PUT', '/admin/api/granths/1'], ['POST', '/admin/api/publish'], ['GET', '/admin/api/stats/overview'], ['GET', '/admin/api/settings']]) {
    const r = await api(m, p, m === 'GET' ? undefined : {}, { nocookie: true, nocsrf: true }); ok(r.status === 401, `unauthenticated ${m} ${p} → 401`, r.status);
  }
  const bad = await login('definitely-wrong-password'); ok(bad.status === 401, `bad password → 401 (${bad.ms} ms)`, bad.status);
  const noCreds = await fetch(BASE + '/admin/api/login', { method: 'POST', body: '{}' }); ok(noCreds.status === 401, 'empty creds → 401');
  const me = await session();
  let r = await api('GET', '/admin/api/granths');
  if (r.status === 200 && r.json.items.length === 0) { const sy = await api('POST', '/admin/api/sync'); ok(sy.status === 200 && sy.json.ok, 'first catalog sync (baseline)', sy.json); r = await api('GET', '/admin/api/granths'); }
  ok(r.status === 200 && r.json.items.length > 50, `granths list (${r.json?.items?.length})`);
  const g = r.json.items[0];
  const noCsrf = await api('PUT', `/admin/api/granths/${g.id}`, { hidden: false }, { nocsrf: true }); ok(noCsrf.status === 403 && noCsrf.json?.error === 'csrf', 'PUT without X-Admin-Csrf → 403', noCsrf.json);
  const badCsrf = await api('PUT', `/admin/api/granths/${g.id}`, { hidden: false }, { nocsrf: true, headers: { 'x-admin-csrf': 'x'.repeat(32) } }); ok(badCsrf.status === 403, 'wrong CSRF → 403');
  const xo = await api('PUT', `/admin/api/granths/${g.id}`, { hidden: false }, { headers: { origin: 'https://evil.example' } }); ok(xo.status === 403, 'foreign Origin → 403', xo.status);
  const noCk = await fetch(BASE + '/admin/api/me', { headers: { cookie: '__Host-granth_sid=' + '0'.repeat(64) } }); ok(noCk.status === 401, 'forged session cookie → 401');
  const lo = await api('POST', '/admin/api/logout', {}); ok(lo.status === 204, 'logout 204');
  const after = await api('GET', '/admin/api/me'); ok(after.status === 401, 'session dead after logout');
  await session();
}

if (want('bearer')) {
  console.log('# mobile app bearer auth');
  const hdr = { 'content-type': 'application/json', 'x-client': 'app', 'x-client-name': 'e2e-app' };
  const bad = await fetch(BASE + '/admin/api/login', { method: 'POST', headers: hdr, body: JSON.stringify({ username: 'goutam', password: 'wrong-wrong' }) }); ok(bad.status === 401, 'app login bad password → 401', bad.status);
  const r = await fetch(BASE + '/admin/api/login', { method: 'POST', headers: hdr, body: JSON.stringify({ username: 'goutam', password: PW }) });
  const j = await r.json(); ok(r.status === 200 && /^[0-9a-f]{64}$/.test(j.token || '') && j.token_type === 'Bearer' && j.expires_in === 86400 && !r.headers.get('set-cookie'), 'app login → 200 JSON {token,token_type,expires_in}, no cookie', { ...j, token: '…', csrf: '…' });
  const B = { authorization: 'Bearer ' + j.token };
  const me = await fetch(BASE + '/admin/api/me', { headers: B }); const mj = await me.json(); ok(me.status === 200 && mj.auth === 'bearer', 'GET /me with bearer', { ...mj, csrf: '…' });
  const list = await (await fetch(BASE + '/admin/api/granths', { headers: B })).json(); ok(list.items?.length > 50, 'GET granths with bearer');
  const g = list.items[0];
  const put = await fetch(BASE + `/admin/api/granths/${g.id}`, { method: 'PUT', headers: { ...B, 'content-type': 'application/json' }, body: JSON.stringify({ hidden: g.hidden }) }); ok(put.status === 200, 'PUT with bearer and NO csrf header → 200', put.status);
  const nb = await fetch(BASE + '/admin/api/me', { headers: { authorization: 'Bearer ' + '0'.repeat(64) } }); ok(nb.status === 401, 'forged bearer → 401');
  const ck = await fetch(BASE + '/admin/api/me', { headers: { cookie: '__Host-granth_sid=' + j.token } }); ok(ck.status === 401, 'app token as cookie → 401 (separate kinds)');
  const noauth = await fetch(BASE + '/admin/api/granths/1', { method: 'PUT', headers: { 'content-type': 'application/json' }, body: '{"hidden":false}' }); ok(noauth.status === 401, 'no auth PUT → 401');
  const ss = await (await fetch(BASE + '/admin/api/sessions', { headers: B })).json(); ok(ss.items.some((x) => x.current && x.kind === 'app'), 'GET /sessions lists current app session', ss.items.map((x) => ({ ...x, sid: '…' })));
  const other = await (await fetch(BASE + '/admin/api/login', { method: 'POST', headers: hdr, body: JSON.stringify({ username: 'goutam', password: PW }) })).json();
  const ss2 = await (await fetch(BASE + '/admin/api/sessions', { headers: B })).json();
  const victim = ss2.items.find((x) => !x.current && x.kind === 'app');
  const del = await fetch(BASE + '/admin/api/sessions/' + victim.sid, { method: 'DELETE', headers: B }); ok(del.status === 200, 'revoke another app session');
  const dead = await fetch(BASE + '/admin/api/me', { headers: { authorization: 'Bearer ' + other.token } }); ok(dead.status === 401, 'revoked token → 401');
  const lo = await fetch(BASE + '/admin/api/logout', { method: 'POST', headers: B }); ok(lo.status === 204, 'logout with bearer → 204');
  const after = await fetch(BASE + '/admin/api/me', { headers: B }); ok(after.status === 401, 'token dead after logout');
  const acao = (await fetch(BASE + '/admin/api/me', { headers: { ...B, origin: 'https://evil.example' } })).headers.get('access-control-allow-origin'); ok(!acao, 'admin API sends no CORS allow-origin', acao);
}

let state = {};
if (want('edit') || want('settings') || want('sort') || want('admins') || want('contacts') || want('validate') || want('rollback') || want('events') || want('newgranth') || want('ratelimit')) { if (!cookie) await session(); }

if (want('edit')) {
  console.log('# edit → draft → publish');
  const before = await cfg();
  const list = (await api('GET', '/admin/api/granths')).json;
  const leaf = list.leaves.find((l) => l.key !== 'other' && l.key !== list.items[0].leaf);
  const a = list.items.find((g) => !g.hidden && g.leaf !== leaf.key), b = list.items.find((g) => !g.hidden && g.id !== a.id);
  state = { a: a.id, b: b.id, leaf: leaf.key, before };
  let r = await api('PUT', `/admin/api/granths/${a.id}`, { leaf: leaf.key }); ok(r.status === 200, `move granth ${a.id} → ${leaf.key}`, r.json);
  r = await api('PUT', `/admin/api/granths/${b.id}`, { hidden: true }); ok(r.status === 200, `hide granth ${b.id}`, r.json);
  const still = await cfg(); ok(still.json.version === before.json.version, 'draft does not change the published config');
  const d = await api('GET', '/admin/api/draft/diff'); ok(d.json?.diff?.granths?.length === 2, 'draft diff lists 2 granths', d.json?.diff);
  const p = await api('POST', '/admin/api/publish', { note: 'e2e: move+hide' }); ok(p.status === 200 && p.json.version === before.json.version + 1, `publish → v${p.json?.version}`, p.json);
  const c = await waitCfg(before.json.version + 1);
  ok(c.json.version === before.json.version + 1, 'config.json served the new version', c.json.version);
  ok(c.json.overrides[a.id]?.leaf === leaf.key, 'overrides reflects the move');
  ok(c.json.hidden_granth_ids.includes(b.id), 'hidden_granth_ids includes the hidden granth');
  ok(c.etag !== before.etag, 'ETag changed');
  const nm = await fetch(BASE + '/config.json', { headers: { 'if-none-match': before.etag } }); ok(nm.status === 200, 'old ETag → 200 (new content)');
  const again = await api('POST', '/admin/api/publish', {}); ok(again.status === 409, 'publish without draft → 409 no_changes', again.json);
  if (PUB && c.json.sig) { const { sig, ...rest } = c.json; const key = createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(PUB, 'base64')]), format: 'der', type: 'spki' }); ok(verify(null, Buffer.from(canonical(rest)), key, Buffer.from(sig, 'base64')), 'new version signature verifies'); }
  const vs = await api('GET', '/admin/api/versions'); ok(vs.json.items[0].version === c.json.version && vs.json.items.length <= 20, 'versions list', vs.json.items.length);
  const vd = await api('GET', `/admin/api/versions/${c.json.version}`); ok(vd.json?.diff?.granths?.length === 2, 'version diff vs previous', vd.json?.diff?.changed);
}

if (want('settings')) {
  console.log('# folders / flags / announcement');
  const before = await cfg();
  const st = (await api('GET', '/admin/api/structure')).json.structure;
  const rel = st.religions.find((r) => r.id === 'jain') || st.religions[st.religions.length - 1];
  const hindu = st.religions.find((r) => r.id === 'hindu');
  hindu.groups[0].coming_soon = 'जल्द आ रहा है';
  rel.visible = false;
  const newRel = { id: 'e2etest', title: 'टेस्ट', tone: 'gold', icon: 'misc', groups: [{ id: 'g1', title: 'समूह', icon: 'books', granthIds: [], keywords: [] }] };
  st.religions.push(newRel);
  let r = await api('PUT', '/admin/api/structure', { structure: st }); ok(r.status === 200, 'structure PUT (coming_soon, visible=false, new religion)', r.json);
  r = await api('PUT', '/admin/api/settings', { flags: { ai_enabled: false, analytics_sample: 0.5 }, announcement: { enabled: true, text: 'परीक्षण घोषणा', id: 'e2e1', level: 'warn', expires_at: '2030-01-01T00:00:00Z' }, ai_endpoint: 'https://granth-ai.vedpuran8090.workers.dev' });
  ok(r.status === 200, 'settings PUT', r.json);
  r = await api('PUT', '/admin/api/settings', { announcement: { level: 'bogus' } }); ok(r.status === 422, 'bad announcement level → 422');
  r = await api('PUT', '/admin/api/settings', { ai_endpoint: 'http://insecure.example' }); ok(r.status === 422, 'non-https endpoint → 422');
  r = await api('POST', '/admin/api/publish', { note: 'e2e: structure+settings' }); ok(r.status === 200, 'publish', r.json);
  const c = await waitCfg(before.json.version + 1);
  const h = c.json.structure.religions.find((x) => x.id === 'hindu');
  ok(h.groups[0].coming_soon === 'जल्द आ रहा है', 'config: group.coming_soon');
  ok(c.json.structure.religions.find((x) => x.id === rel.id).visible === false, 'config: religion.visible=false');
  ok(c.json.structure.religions.some((x) => x.id === 'e2etest'), 'config: new religion present');
  ok(c.json.flags.ai_enabled === false && c.json.flags.analytics_sample === 0.5, 'config: flags', c.json.flags);
  ok(c.json.announcement.enabled && c.json.announcement.id === 'e2e1' && c.json.announcement.level === 'warn' && c.json.announcement.expires_at, 'config: announcement', c.json.announcement);
  ok(c.json.endpoints.ai === 'https://granth-ai.vedpuran8090.workers.dev', 'config: endpoints.ai', c.json.endpoints);
  ok(c.json.structure.version === before.json.structure.version + 1, 'structure.version bumped');
  // remove the test religion again, with an override pointing into it → 409
  const list = (await api('GET', '/admin/api/granths')).json; const gid = list.items[3].id;
  await api('PUT', `/admin/api/granths/${gid}`, { leaf: 'e2etest/g1' });
  await api('POST', '/admin/api/publish', { note: 'e2e: override into test folder' });
  const st2 = (await api('GET', '/admin/api/structure')).json.structure; st2.religions = st2.religions.filter((x) => x.id !== 'e2etest');
  r = await api('PUT', '/admin/api/structure', { structure: st2 }); ok(r.status === 409 && r.json.error === 'leaf_in_use', 'removing a folder that holds granths → 409 leaf_in_use', r.json);
  r = await api('PUT', '/admin/api/structure', { structure: st2, drop_overrides: true }); ok(r.status === 200, 'removal with drop_overrides ok');
  await api('POST', '/admin/api/publish', { note: 'e2e: remove test folder' });
}

if (want('validate')) {
  console.log('# validation');
  let r = await api('PUT', '/admin/api/granths/1', { leaf: 'nope/zzz' }); ok([404, 422].includes(r.status), 'unknown granth or leaf rejected', r.status);
  const list = (await api('GET', '/admin/api/granths')).json;
  r = await api('PUT', `/admin/api/granths/${list.items[0].id}`, { leaf: 'nope/zzz' }); ok(r.status === 422 && r.json.error === 'unknown_leaf', 'bad leaf → 422 unknown_leaf', r.json);
  r = await api('PUT', `/admin/api/granths/${list.items[0].id}`, { hidden: 'yes' }); ok(r.status === 422, 'non-boolean hidden → 422');
  r = await api('POST', '/admin/api/granths/bulk', { ids: ['abc'], hidden: true }); ok(r.status === 422, 'bulk with bad id → 422');
  const st = (await api('GET', '/admin/api/structure')).json.structure; st.religions[0].id = 'Bad Id';
  r = await api('PUT', '/admin/api/structure', { structure: st }); ok(r.status === 422 && r.json.error === 'invalid_structure', 'structure with bad id → 422', r.json?.errors);
  const st3 = (await api('GET', '/admin/api/structure')).json.structure; st3.religions[0].title = ''; r = await api('PUT', '/admin/api/structure', { structure: st3 }); ok(r.status === 422, 'empty title → 422');
  const before = await cfg();
  const ids = list.items.slice(0, Math.ceil(list.items.length * 0.6)).map((g) => g.id);
  r = await api('POST', '/admin/api/granths/bulk', { ids, hidden: true }); ok(r.status === 200, `bulk hide ${ids.length}/${list.items.length} into draft`, r.json);
  const dd = await api('GET', '/admin/api/draft'); ok(dd.json.diff.warnings.length > 0, 'draft warns about hiding >50%', dd.json.diff.warnings);
  r = await api('POST', '/admin/api/publish', { note: 'e2e: hide too many' }); ok(r.status === 422 && JSON.stringify(r.json).includes('needs force'), 'publish hiding >50% rejected without force', r.json);
  const c = await cfg(); ok(c.json.version === before.json.version, 'version unchanged after rejected publish');
  r = await api('POST', '/admin/api/granths/bulk', { ids: list.items.map((g) => g.id), hidden: true });
  r = await api('POST', '/admin/api/publish', { force: true, note: 'e2e: hide all' }); ok(r.status === 422 && JSON.stringify(r.json).includes('>90%'), 'hiding >90% never allowed even with force', r.json);
  r = await api('POST', '/admin/api/draft/discard', {}); ok(r.status === 200, 'draft discarded');
  const d2 = await api('GET', '/admin/api/draft'); ok(d2.json.exists === false, 'no draft left');
}

if (want('rollback')) {
  console.log('# rollback');
  const vs = (await api('GET', '/admin/api/versions')).json.items;
  const cur = vs[0].version;
  const r = await api('POST', '/admin/api/rollback', { to_version: 1 }); ok(r.status === 200 && r.json.version === cur + 1, `rollback to v1 creates v${cur + 1}`, r.json);
  const c = await waitCfg(cur + 1);
  ok(c.json.version === cur + 1 && Object.keys(c.json.overrides).length === 0 && c.json.hidden_granth_ids.length === 0, 'config after rollback = v1 content with a higher version', { v: c.json.version, ov: Object.keys(c.json.overrides).length, h: c.json.hidden_granth_ids.length });
  const bad = await api('POST', '/admin/api/rollback', { to_version: 999999 }); ok(bad.status === 404, 'rollback to missing version → 404');
}

if (want('sort')) {
  console.log('# granths sort');
  const L = async (q) => (await api('GET', '/admin/api/granths' + q)).json;
  const pos = (j) => j.items.map((g) => Number(g.position));
  const asc = (a) => a.every((x, i) => i === 0 || a[i - 1] <= x), desc = (a) => a.every((x, i) => i === 0 || a[i - 1] >= x);
  let d = await L(''); if (!d.items?.length) { await api('POST', '/admin/api/sync', {}); d = await L(''); }
  ok(d.sort === 'position' && d.order === 'asc', 'default sort=number (canonical key "position") order=asc', { sort: d.sort, order: d.order });
  ok(pos(d)[0] === 1 && asc(pos(d)), 'default list starts at #1 and ascends', pos(d).slice(0, 5));
  ok(d.items.every((g) => 'position' in g && 'created_at' in g), 'items carry position + created_at');
  const dd = await L('?sort=number&order=desc'); ok(desc(pos(dd)) && pos(dd)[0] === Math.max(...pos(d)), 'number desc');
  const idd = await L('?sort=id&order=asc'); const ids = idd.items.map((g) => Number(g.id)); ok(asc(ids), 'id asc'); const idx = await L('?sort=id&order=desc'); ok(desc(idx.items.map((g) => Number(g.id))), 'id desc');
  const t = await L('?sort=title'); const col = new Intl.Collator('hi'); ok(t.order === 'asc' && t.items.every((g, i) => i === 0 || col.compare(t.items[i - 1].title, g.title) <= 0), 'title A-Z (default asc)');
  const pr = await L('?sort=praman'); ok(pr.order === 'desc' && pr.items.every((g, i) => i === 0 || (pr.items[i - 1].praman_count ?? 0) >= (g.praman_count ?? 0)), 'praman count (default desc)', pr.items.slice(0, 3).map((g) => g.praman_count));
  const prA = await L('?sort=praman&order=asc'); ok(prA.items.every((g, i) => i === 0 || (prA.items[i - 1].praman_count ?? 0) <= (g.praman_count ?? 0)), 'praman asc override');
  const nw = await L('?sort=newest'); ok(nw.order === 'desc' && nw.items.every((g, i) => i === 0 || String(nw.items[i - 1].created_at || '') >= String(g.created_at || '')), 'newest first (catalog created_at)');
  for (const k of ['opens', 'watch']) { const o = await L('?sort=' + k); const key = Object.keys(o.items[0]).find((f) => (k === 'opens' ? /opens/ : /watch/).test(f)); ok(o.order === 'desc' && o.items.length === d.items.length && !!key, `${k} sort accepted (default desc), field ${key}`, Object.keys(o.items[0])); }
  ok((await api('GET', '/admin/api/granths?sort=bogus')).status === 422 && (await api('GET', '/admin/api/granths?order=up')).status === 422, 'bad sort/order → 422');
  const al = (await api('GET', '/admin/api/alerts')).json; ok(Array.isArray(al.new_granths) && asc(al.new_granths.map((g) => Number(g.position)).filter((x) => !isNaN(x))), 'alerts.new_granths ascending by position');
}

if (want('admins')) {
  console.log('# multiple admins');
  const rpw = () => 'T' + [...crypto.getRandomValues(new Uint8Array(12))].map((x) => x.toString(16).padStart(2, '0')).join('') + 'x!';
  const U1 = 'e2eadm' + Math.random().toString(36).slice(2, 7), U2 = 'e2eown' + Math.random().toString(36).slice(2, 7);
  const P1 = rpw(), P2 = rpw();
  const j = (method, path, body, h = {}) => api(method, '/admin/api' + path, body, h);
  const me0 = (await j('GET', '/me')).json; ok(me0.role === 'owner' && me0.can_manage_admins === true && me0.username === 'goutam', 'goutam is owner', { role: me0.role, u: me0.username });
  const list0 = await j('GET', '/admins'); ok(list0.status === 200 && list0.json.items.some((a) => a.username === 'goutam' && a.role === 'owner' && a.you) && list0.json.min_password_length === 10, 'GET /admins lists goutam (owner, you)');
  ok(!JSON.stringify(list0.json).match(/pw_hash|salt|iters|"password"/i), 'admin list never exposes hash/salt/password');
  const bad = [['ab', P1, 'admin'], ['Bad Name', P1, 'admin'], [U1, 'short', 'admin'], [U1, P1, 'god'], ['goutam', P1, 'admin']];
  const bc = []; for (const [u, p, r] of bad) bc.push((await j('POST', '/admins', { username: u, password: p, role: r })).status); ok(bc.join() === '422,422,422,422,409', 'create validation: bad_username/weak_password/bad_role → 422, duplicate → 409', bc);
  const c1 = await j('POST', '/admins', { username: U1, password: P1 }); ok(c1.status === 201 && c1.json.admin.role === 'admin' && c1.json.admin.username === U1 && !JSON.stringify(c1.json).includes(P1), 'create admin (default role admin) → 201, no password in response');
  const c2 = await j('POST', '/admins', { username: U2, password: P2, role: 'owner' }); ok(c2.status === 201 && c2.json.admin.role === 'owner', 'create owner → 201');
  // new admin can log in (bearer + cookie)
  const hdr = { 'content-type': 'application/json', 'x-client': 'app', 'x-client-name': 'e2e-admin' };
  const app = async (u, p) => { const r = await fetch(BASE + '/admin/api/login', { method: 'POST', headers: hdr, body: JSON.stringify({ username: u, password: p }) }); return { status: r.status, j: await r.json().catch(() => ({})) }; };
  const l1 = await app(U1, P1); ok(l1.status === 200 && l1.j.role === 'admin' && /^[0-9a-f]{64}$/.test(l1.j.token), 'new admin app login → token + role admin');
  const B1 = { authorization: 'Bearer ' + l1.j.token };
  const cookieLogin = await fetch(BASE + '/admin/api/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: U1.toUpperCase(), password: P1 }) });
  ok(cookieLogin.status === 204 && /__Host-granth_sid=/.test(cookieLogin.headers.get('set-cookie') || ''), 'new admin cookie login (username case-insensitive) → 204');
  const m1 = await (await fetch(BASE + '/admin/api/me', { headers: B1 })).json(); ok(m1.role === 'admin' && m1.can_manage_admins === false && m1.username === U1, '/me for admin: role admin, cannot manage admins');
  // role restrictions
  const fb = []; for (const [m, p, b] of [['GET', '/admins'], ['POST', '/admins', { username: 'zzz123', password: P1 }], ['PUT', `/admins/${U2}`, { disabled: true }], ['POST', `/admins/${U2}/password`, { password: P1 }], ['DELETE', `/admins/${U2}`]]) { const r = await fetch(BASE + '/admin/api' + p, { method: m, headers: { ...B1, 'content-type': 'application/json' }, body: b ? JSON.stringify(b) : undefined }); fb.push(r.status); }
  ok(fb.every((x) => x === 403), 'admin role: every /admins endpoint → 403', fb);
  const edit = await fetch(BASE + '/admin/api/granths', { headers: B1 }); ok(edit.status === 200, 'admin role can still use normal endpoints (list granths)');
  const pw = await fetch(BASE + '/admin/api/password', { method: 'POST', headers: { ...B1, 'content-type': 'application/json' }, body: JSON.stringify({ current: P1, new: 'short9chr' }) }); ok(pw.status === 422, 'change-password: 9 chars rejected', pw.status);
  // audit actor
  const mk = await fetch(BASE + '/admin/api/granths', { headers: B1 }); const gl = (await mk.json()).items[0];
  const hidePut = await fetch(BASE + `/admin/api/granths/${gl.id}`, { method: 'PUT', headers: { ...B1, 'content-type': 'application/json' }, body: JSON.stringify({ hidden: !!gl.hidden }) }); ok(hidePut.status === 200, 'admin edit works');
  const au = (await j('GET', '/audit?limit=100')).json.items; const ents = au.filter((a) => a.actor === U1); ok(ents.length > 0, 'audit records the acting admin', ents.slice(0, 2).map((e) => e.action));
  ok(au.some((a) => a.actor === 'goutam' && a.action === 'admin_create'), 'audit: admin_create by goutam');
  ok(!JSON.stringify(au).includes(P1) && !JSON.stringify(au).includes(P2), 'audit never contains passwords');
  // self protection + last owner
  const sd = await j('PUT', '/admins/goutam', { disabled: true }); const sx = await j('DELETE', '/admins/goutam'); const sr = await j('PUT', '/admins/goutam', { role: 'admin' }); const sp = await j('POST', '/admins/goutam/password', { password: rpw() });
  ok([sd, sx, sr, sp].every((r) => r.status === 409), 'cannot disable/delete/demote/reset-via-admin-endpoint yourself → 409', [sd, sx, sr, sp].map((r) => r.json?.error));
  // reset another admin's password, sessions revoked
  const P1b = rpw(); const rs = await j('POST', `/admins/${U1}/password`, { password: P1b }); ok(rs.status === 200 && rs.json.ok === true && !JSON.stringify(rs.json).includes(P1b), 'reset other admin password → 200');
  ok((await fetch(BASE + '/admin/api/me', { headers: B1 })).status === 401, 'reset revokes that admin sessions (old token → 401)');
  // NB: failed logins count toward the per-IP limit (5 / 10 min) — this step deliberately makes only 2.
  const l1b = await app(U1, P1b); ok(l1b.status === 200, 'new password works'); const B1b = { authorization: 'Bearer ' + l1b.j.token };
  ok((await j('POST', `/admins/${U1}/password`, { password: 'tooshort' })).status === 422, 'reset with <10 chars → 422');
  // disable → login refused, sessions dead; enable → works
  const dis = await j('PUT', `/admins/${U1}`, { disabled: true }); ok(dis.status === 200 && dis.json.admin.disabled === true, 'disable admin');
  ok((await fetch(BASE + '/admin/api/me', { headers: B1b })).status === 401, 'disabled admin: live session dead');
  ok((await app(U1, P1b)).status === 401, 'disabled admin cannot log in (same 401 as bad creds)');
  const en = await j('PUT', `/admins/${U1}`, { disabled: false }); ok(en.status === 200 && en.json.admin.disabled === false, 're-enable admin');
  const l1c = await app(U1, P1b); ok(l1c.status === 200, 'enabled admin logs in again');
  // old goutam session unaffected throughout
  ok((await j('GET', '/me')).status === 200, "goutam's pre-existing session unaffected by all admin operations");
  // second owner promotion + last-owner rules
  const L2 = await app(U2, P2); ok(L2.status === 200 && L2.j.role === 'owner', 'second owner logs in');
  const B2 = { authorization: 'Bearer ' + L2.j.token };
  const o2 = (m, p, b) => fetch(BASE + '/admin/api' + p, { method: m, headers: { ...B2, 'content-type': 'application/json' }, body: b ? JSON.stringify(b) : undefined });
  ok((await o2('GET', '/admins')).status === 200, 'second owner can manage admins');
  const promote = await j('PUT', `/admins/${U1}`, { role: 'owner' }); ok(promote.status === 200 && promote.json.admin.role === 'owner', 'promote admin → owner');
  ok((await fetch(BASE + '/admin/api/admins', { headers: { authorization: 'Bearer ' + l1c.j.token } })).status === 200, 'role is live: promoted admin can now list admins with the old token');
  const demote = await j('PUT', `/admins/${U1}`, { role: 'admin' }); ok(demote.status === 200, 'demote back');
  // last active owner: goutam disabled by U2 → then U2 tries to disable/delete itself or ... ; also goutam cannot be removed as last owner
  const dg = await o2('PUT', '/admins/goutam', { disabled: true }); ok(dg.status === 200, 'owner2 can disable goutam (another owner remains)');
  ok((await j('GET', '/me')).status === 401, "disabled goutam's session dies immediately"); cookie = ''; csrf = '';
  const sd2 = await o2('PUT', `/admins/${U2}`, { disabled: true }); ok(sd2.status === 409, 'owner2 cannot disable self', sd2.status);
  const dlast = await o2('DELETE', `/admins/${U2}`); ok(dlast.status === 409, 'owner2 cannot delete self', dlast.status);
  const lst = await (await o2('GET', '/admins')).json(); ok(lst.items.some((a) => a.username === 'goutam'), 'goutam must still exist (we never delete him in tests)', lst.items.map((a) => a.username));
  const en2 = await o2('PUT', '/admins/goutam', { disabled: false }); ok(en2.status === 200, 'owner2 re-enables goutam');
  await session();
  const lastOwnerTry = await o2('PUT', `/admins/${U2}`, { role: 'admin' }); ok(lastOwnerTry.status === 409, 'owner2 cannot demote self', lastOwnerTry.status);
  // delete test admins
  ok((await j('DELETE', `/admins/${U1}`)).status === 200, 'delete admin 1'); ok((await fetch(BASE + '/admin/api/me', { headers: { authorization: 'Bearer ' + l1c.j.token } })).status === 401, 'deleted admin session dead');
  ok((await j('DELETE', `/admins/${U2}`)).status === 200, 'delete owner 2'); ok((await app(U2, P2)).status === 401, 'deleted admin cannot log in');
  ok((await j('GET', '/admins/' + U1)).status === 404, 'GET deleted admin → 404');
  const fin = (await j('GET', '/admins')).json; ok(fin.items.length === 1 && fin.items[0].username === 'goutam' && fin.items[0].role === 'owner', 'only goutam (owner) remains', fin.items.map((a) => a.username));
  // last-owner protection when the only owner is a different, not-you owner is covered by unit + above; direct check of last active owner:
  const only = await j('DELETE', '/admins/goutam'); ok(only.status === 409, 'cannot delete yourself / the last admin', only.json?.error);
}

if (want('contacts')) {
  console.log('# contacts (विशेष जानकार)');
  const j = (method, path, body) => api(method, '/admin/api' + path, body);
  const c0 = await cfg(); const v0 = c0.json.version;
  const g0 = (await j('GET', '/contacts')).json;
  ok(g0.page?.title && g0.max_contacts === 50 && Array.isArray(g0.items), 'GET /contacts shape', Object.keys(g0));
  const names0 = g0.items.map((c) => c.name);
  const publishedNow = c0.json.contacts?.map((c) => c.name) || null;
  console.log('    (current published contacts:', publishedNow ? publishedNow.length : 'none', ')');
  // validation
  const v = async (b) => (await j('POST', '/contacts', b)).status;
  const vs = [await v({ name: '' }), await v({ name: 'x'.repeat(81) }), await v({ name: 'A', phone: '12.34' }), await v({ name: 'A', phone: '1'.repeat(21) }), await v({ name: 'A', phone: 'abc' }), await v({ name: 'A', whatsapp: true }), await v({ name: 'A', whatsapp: 'yes', phone: '123' })];
  ok(vs.every((x) => x === 422), 'POST validation: empty/long name, bad phone, whatsapp without phone → 422', vs);
  const dup = await j('PUT', '/contacts', { items: [{ id: 'a', name: 'A' }, { id: 'a', name: 'B' }] }); ok(dup.status === 422, 'duplicate ids → 422');
  const many = await j('PUT', '/contacts', { items: Array.from({ length: 51 }, (_, i) => ({ id: 'm' + i, name: 'N' + i })) }); ok(many.status === 422, '51 contacts → 422');
  ok((await j('PUT', '/contacts', { title: '' })).status === 422, 'empty title → 422');
  // CRUD (draft only — published config must not change)
  const add = await j('POST', '/contacts', { name: 'टेस्ट व्यक्ति', role: 'परीक्षण', phone: '+919999999999', whatsapp: true }); ok(add.status === 201 && add.json.contact.id && add.json.has_draft === true, 'add contact → 201 into draft', add.json?.contact);
  const cid = add.json.contact.id;
  ok((await cfg()).json.version === v0, 'draft edits do not change the published config');
  const up = await j('PUT', `/contacts/${cid}`, { name: 'टेस्ट 2', visible: false }); ok(up.status === 200 && up.json.items.find((c) => c.id === cid)?.visible === false, 'edit contact (hide)');
  const ids = up.json.items.map((c) => c.id); const rev = ids.slice().reverse();
  const ro = await j('POST', '/contacts/reorder', { ids: rev }); ok(ro.status === 200 && ro.json.items.map((c) => c.id).join() === rev.join() && ro.json.items.every((c, i) => c.order === i + 1), 'reorder → order = 1..n in new sequence');
  ok((await j('POST', '/contacts/reorder', { ids: rev.slice(1) })).status === 422, 'reorder with missing ids → 422');
  const sp = await j('POST', '/contacts', { name: 'स्पेस', phone: '98 76-54' }); ok(sp.status === 201 && sp.json.contact.phone === '987654', 'spaces/hyphens in phone are stripped on save', sp.json?.contact); await j('DELETE', `/contacts/${sp.json.contact.id}`);
  const t = await j('PUT', '/contacts', { title: 'विशेष जानकार (e2e)' }); ok(t.status === 200 && t.json.page.title === 'विशेष जानकार (e2e)', 'edit page title');
  const df = (await j('GET', '/draft')).json; ok(df.exists && (df.diff.contacts || []).some((x) => x.id === cid && x.change === 'added') && df.diff.settings.some((x) => /contacts_page/.test(x.field || x.key || JSON.stringify(x))), 'draft diff lists contacts + title', df.diff.contacts);
  const pub = await j('POST', '/publish', { note: 'e2e contacts' }); ok(pub.status === 200 && pub.json.version === v0 + 1, 'publish contacts', pub.json);
  const c1 = await waitCfg(v0 + 1);
  const cc = c1.json.contacts; ok(Array.isArray(cc) && cc.length === ids.length && cc.every((c) => ['id', 'name', 'role', 'phone', 'whatsapp', 'order', 'visible'].every((k) => k in c)), 'config.json contacts have all fields', cc?.[0]);
  ok(c1.json.contacts_page?.title === 'विशेष जानकार (e2e)', 'config.json contacts_page.title updated');
  ok(cc.find((c) => c.id === cid)?.visible === false && cc.find((c) => c.id === cid)?.phone === '+919999999999', 'hidden contact still in config with visible:false');
  // delete + restore seeded state
  const del = await j('DELETE', `/contacts/${cid}`); ok(del.status === 200 && !del.json.items.some((c) => c.id === cid), 'delete contact');
  ok((await j('DELETE', '/contacts/nope')).status === 404, 'delete unknown → 404');
  const back = await j('PUT', '/contacts', { title: 'विशेष जानकार' }); ok(back.status === 200, 'title restored');
  const pub2 = await j('POST', '/publish', { note: 'e2e contacts cleanup' }); ok(pub2.status === 200, 'publish cleanup');
  const c2 = await waitCfg(v0 + 2); ok(c2.json.contacts.length === ids.length - 1 && !c2.json.contacts.some((c) => c.id === cid), 'contact removed in config');
  // rollback restores the earlier contact list
  const rb = await j('POST', '/rollback', { to_version: v0 + 1 }); ok(rb.status === 200, 'rollback to the version with the test contact'); const c3 = await waitCfg(v0 + 3); ok(c3.json.contacts.some((c) => c.id === cid), 'rollback restores contacts');
  const au = (await j('GET', '/audit?limit=60')).json.items; ok(au.some((a) => a.action === 'contacts_edit') && !JSON.stringify(au).includes('9999999999'), 'audit has contacts_edit and never a phone number');
  // leave the draft/config clean for later steps: restore seeded list via PUT + publish
  const seedBack = await j('PUT', '/contacts', { title: 'विशेष जानकार', items: names0.map((n, i) => ({ id: g0.items[i].id, name: n, role: g0.items[i].role, phone: g0.items[i].phone, whatsapp: g0.items[i].whatsapp, visible: g0.items[i].visible })) });
  ok(seedBack.status === 200, 'contacts list reset to the pre-test list');
  await j('POST', '/publish', { note: 'e2e contacts reset', allow_empty: true });
}

if (want('events')) {
  console.log('# events');
  const list = (await api('GET', '/admin/api/granths')).json;
  const [g1, g2] = list.items.slice(5, 7).map((g) => g.id);
  const folder = list.items[5].leaf === 'other' ? 'other' : list.items[5].leaf;
  const post = async (obj, o = {}) => {
    const raw = typeof obj === 'string' ? obj : JSON.stringify(obj);
    const body = o.gzip ? gzipSync(raw) : raw;
    const res = await fetch(BASE + '/events', { method: 'POST', headers: { 'content-type': 'application/json', ...(o.gzip ? { 'content-encoding': 'gzip' } : {}) }, body });
    return res.status;
  };
  const ov = async () => (await api('GET', '/admin/api/stats/overview?days=7')).json;
  const mk = (extra = {}) => ({ v: 1, batch_id: rid(), iid: iid(), app: '1.0.0+1', os: 'android', sdk: 34, cfg: 1, day: day(), fg_s: 600, sessions: 2,
    open: { g: { [g1]: 3, [g2]: 1 }, f: { [folder]: 4 }, t: { 5: 1 }, p: { 7: 2 } }, watch_s: { g: { [g1]: 200, [g2]: 50 }, f: { [folder]: 250 }, scr: { reader: 400, home: 100 } },
    sync: { ok: 3, fail: 1, kinds: { timeout: 1 } }, pdf: { ok: 2, fail: 1, kinds: { nospace: 1 } }, ai: { asked: 2, answered: 1, cite_tap: 1 }, ...extra });
  const s0 = await ov();
  const b1 = mk(); ok((await post(b1)) === 204, 'valid batch → 204');
  const s1 = await ov();
  ok(s1.totals.granth_opens - s0.totals.granth_opens === 4, 'granth opens rolled up (+4)', [s0.totals.granth_opens, s1.totals.granth_opens]);
  ok(s1.totals.granth_watch_s - s0.totals.granth_watch_s === 250, 'granth watch_s rolled up (+250)');
  ok(s1.totals.app_fg_s - s0.totals.app_fg_s === 600, 'app foreground seconds (+600)');
  ok(s1.totals.dau_today - s0.totals.dau_today === 1, 'DAU +1');
  ok(s1.sync.fail - s0.sync.fail === 1 && s1.pdf.fail - s0.pdf.fail === 1 && s1.ai.asked - s0.ai.asked === 2, 'sync/pdf/ai counters');
  ok(s1.totals.total_installs - s0.totals.total_installs === 1 && s1.totals.active_1d - s0.totals.active_1d === 1 && s1.totals.active_7d >= s1.totals.active_1d && s1.totals.active_30d >= s1.totals.active_7d, 'installs +1, active 1d/7d/30d consistent', [s0.totals, s1.totals].map((t) => [t.total_installs, t.active_1d, t.active_7d, t.active_30d]));
  ok(s1.new_installs.length === 7 && s1.new_installs.at(-1).n >= 1 && s1.installs_by_version.some((x) => x.app === '1.0.0+1') && s1.installs_by_os.some((x) => x.os === 'android'), 'new_installs series, installs_by_version/os');
  ok(s1.totals.total_fg_s_all_time >= s1.totals.total_fg_s && s1.totals.avg_fg_s_per_active_user > 0 && s1.totals.sessions_all_time >= 2 && s1.top_screens.some((x) => x.screen === 'reader'), 'fg totals, averages, sessions, top_screens');
  ok(s1.top_granths_opens.some((x) => x.id === g1), 'top granths include posted id');
  ok(s1.top_folders.some((x) => x.key === folder), 'top folders include posted leaf');
  ok((await post(b1)) === 204, 'duplicate batch_id → 204'); const s2 = await ov(); ok(s2.totals.granth_opens === s1.totals.granth_opens, 'duplicate batch ignored (no double count)');
  ok((await post(mk(), { gzip: true })) === 204, 'gzip body → 204'); const s3 = await ov(); ok(s3.totals.granth_opens - s2.totals.granth_opens === 4, 'gzip batch counted (+4)', [s2.totals.granth_opens, s3.totals.granth_opens]);
  ok((await post('{not json')) === 204 && (await post('')) === 204, 'garbage body → 204');
  const big = mk({ pad: 'x'.repeat(9000) }); ok((await post(big)) === 204, 'oversized (>8KB) → 204'); const s4 = await ov(); ok(s4.totals.granth_opens === s3.totals.granth_opens, 'oversized batch ignored');
  const gz = gzipSync(JSON.stringify(mk({ pad: 'y'.repeat(20000) }))); ok(gz.length < 8192, 'bomb precondition (gz small)', gz.length);
  await fetch(BASE + '/events', { method: 'POST', headers: { 'content-encoding': 'gzip' }, body: gz }); const s5 = await ov(); ok(s5.totals.granth_opens === s4.totals.granth_opens, 'gzip expanding to >8KB ignored');
  ok((await post(mk({ day: day(-9) }))) === 204 && (await ov()).totals.granth_opens === s5.totals.granth_opens, 'day out of ±2 range ignored');
  ok((await post(mk({ iid: 'nothex' }))) === 204 && (await ov()).totals.granth_opens === s5.totals.granth_opens, 'bad iid ignored');
  const clamp = mk({ fg_s: 9999999, open: { g: { [g2]: 9999999 }, f: {}, t: {}, p: {} }, watch_s: { g: { [g2]: 9999999 }, f: {}, scr: {} } });
  const s6a = await ov(); await post(clamp); const s6 = await ov();
  ok(s6.totals.app_fg_s - s6a.totals.app_fg_s === 21600, 'fg_s clamped to 21600', s6.totals.app_fg_s - s6a.totals.app_fg_s);
  ok(s6.totals.granth_opens - s6a.totals.granth_opens === 5000 && s6.totals.granth_watch_s - s6a.totals.granth_watch_s === 7200, 'opens clamped 5000, watch_s clamped 7200');
  const junk = mk({ open: { g: { 'abc': 5, '123456789': 5, [g1]: 1 }, f: { 'not/a/folder/x': 9 }, t: {}, p: {} }, watch_s: { g: {}, f: {}, scr: {} } });
  const s7a = await ov(); await post(junk); const s7 = await ov();
  ok(s7.totals.granth_opens - s7a.totals.granth_opens === 1 && s7.totals.folder_opens === s7a.totals.folder_opens, 'invalid granth ids / unknown folder keys dropped');
  const gg = (await api('GET', '/admin/api/stats/granths?days=7')).json; ok(gg.items.some((x) => x.id === g1 && x.opens > 0), 'stats/granths lists the granth');
  const ff = (await api('GET', '/admin/api/stats/folders?days=7')).json; ok(ff.items.some((x) => x.key === folder), 'stats/folders lists the folder');
  const se = (await api('GET', `/admin/api/stats/series?kind=granth&id=${g1}&days=7`)).json; ok(se.series.length === 7 && se.series.some((x) => x.opens > 0), 'stats/series 7 points');
  const pre = await fetch(BASE + '/events', { method: 'OPTIONS' }); ok(pre.status === 204 && pre.headers.get('access-control-allow-origin') === '*', 'OPTIONS /events CORS *');
  const get = await fetch(BASE + '/events'); ok(get.status === 204, 'GET /events → 204');
}

if (want('newgranth')) {
  console.log('# new granth detection (id via NEWID env; the seen row must have been deleted beforehand)');
  const id = process.env.NEWID;
  const r = await api('POST', '/admin/api/sync', {}); ok(r.status === 200 && r.json.ok, 'sync ran', r.json);
  ok(r.json.added?.includes(id), `sync detected ${id} as added`, r.json);
  const a = (await api('GET', '/admin/api/alerts')).json; ok(a.new_granths.some((g) => g.id === id), 'alert lists the new granth', a.new_granths.map((g) => g.id));
  const me = (await api('GET', '/admin/api/stats/overview')).json; ok(me.new_granths_pending >= 1, 'dashboard card count ≥ 1', me.new_granths_pending);
  const pub = await api('POST', '/admin/api/publish', { allow_empty: true, note: 'e2e: unassigned_seen check' }); ok(pub.status === 200, 'publish allow_empty', pub.json);
  const c = await waitCfg(pub.json.version); ok(c.json.unassigned_seen.includes(id), 'config.unassigned_seen includes it', c.json.unassigned_seen);
  const ack = await api('POST', `/admin/api/alerts/g:${id}/ack`, {}); ok(ack.status === 200, 'ack (keep default placement)');
  const a2 = (await api('GET', '/admin/api/alerts')).json; ok(!a2.new_granths.some((g) => g.id === id), 'no longer pending');
}

if (want('ratelimit')) {
  console.log('# login rate limit (locks this IP out of login for 10+ min; existing session unaffected)');
  const codes = [];
  for (let i = 0; i < 7; i++) codes.push((await login('wrong-' + i)).status);
  ok(codes.slice(0, 5).every((c) => c === 401) && codes[5] === 429, 'five 401s then 429', codes);
  const good = await login(); ok(good.status === 429, 'even the correct password is refused while locked', good.status);
}
console.log(`\n${pass} passed, ${failn} failed`); if (failn) { console.log('FAILED:\n - ' + failures.join('\n - ')); process.exit(1); }
