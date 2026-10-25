// Draft / publish / rollback / serving of config.json (plan §5, §6).
import { b64, unb64, canonical, nowIso, sha256Hex, numCmp, json } from './util.js';
import { bootstrapState, validateConfig, leaves, OTHER, normalizeState } from './structure.js';
import { audit } from './audit.js';

const KEEP_VERSIONS = 20;
let memCache = { at: 0, row: null };
const MEM_TTL_MS = 15000;
const CACHE_KEY = 'https://granth-admin.internal/config-cache-v1';

export function baseUrl(env, request) {
  const b = (env.BASE || '').replace(/\/+$/, '');
  return b || (request ? new URL(request.url).origin : '');
}

export async function latestVersion(env) {
  return env.DB.prepare('SELECT version, etag, json, state, created_at, kind, note FROM config_versions ORDER BY version DESC LIMIT 1').first();
}
export async function catalogIdSet(env) {
  const r = await env.DB.prepare('SELECT id FROM granths_seen WHERE removed_at IS NULL AND active = 1').all();
  return new Set(r.results.map((x) => x.id));
}
export async function unassignedIds(env) {
  const r = await env.DB.prepare('SELECT id FROM granths_seen WHERE assigned_at IS NULL AND removed_at IS NULL AND active = 1').all();
  return r.results.map((x) => x.id).sort(numCmp);
}

/** Make sure version 1 exists (bootstrap from bundled structure.json). */
export async function ensureBootstrap(env, request) {
  const row = await latestVersion(env);
  if (row) return row;
  return publish(env, { actor: 'system', note: 'bootstrap from bundled structure.json', kind: 'bootstrap', state: bootstrapState(), request, force: false });
}

export async function getDraft(env) {
  const d = await env.DB.prepare('SELECT state, base_version, force_hide, updated_at, updated_by FROM draft WHERE id = 1').first();
  if (d) return { state: normalizeState(JSON.parse(d.state)), base_version: d.base_version, force_hide: !!d.force_hide, updated_at: d.updated_at, updated_by: d.updated_by, exists: true };
  const pub = await latestVersion(env);
  return { state: normalizeState(JSON.parse(pub.state)), base_version: pub.version, force_hide: false, exists: false };
}
export async function saveDraft(env, state, actor, forceHide) {
  const pub = await latestVersion(env);
  const cur = await env.DB.prepare('SELECT force_hide FROM draft WHERE id = 1').first();
  const fh = forceHide === undefined ? (cur ? cur.force_hide : 0) : forceHide ? 1 : 0;
  await env.DB.prepare(`INSERT INTO draft (id, state, base_version, force_hide, updated_at, updated_by) VALUES (1, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET state = excluded.state, force_hide = excluded.force_hide, updated_at = excluded.updated_at, updated_by = excluded.updated_by`)
    .bind(JSON.stringify(state), pub.version, fh, nowIso(), actor).run();
}
export async function discardDraft(env) { await env.DB.prepare('DELETE FROM draft WHERE id = 1').run(); }

function sortedOverrides(o) { const out = {}; for (const k of Object.keys(o).sort(numCmp)) out[k] = { leaf: o[k].leaf }; return out; }

export function buildConfig({ state, version, base, unassigned, forceHide }) {
  const hidden = [...new Set(state.hidden_granth_ids)].sort(numCmp);
  const cfg = {
    schema: 1,
    version,
    generated_at: nowIso(),
    min_app: 1,
    endpoints: { config: `${base}/config.json`, events: `${base}/events`, ...(state.ai_endpoint ? { ai: state.ai_endpoint } : {}) },
    structure: state.structure,
    hidden_granth_ids: hidden,
    overrides: sortedOverrides(state.overrides || {}),
    unassigned_seen: unassigned,
    announcement: state.announcement,
    contacts_page: state.contacts_page,
    contacts: state.contacts,
    flags: { ...state.flags, max_hidden_pct: forceHide ? 90 : 50 },
  };
  return cfg;
}

async function signConfig(env, cfg) {
  if (!env.SIGNING_KEY_PKCS8) return null;
  const key = await crypto.subtle.importKey('pkcs8', unb64(env.SIGNING_KEY_PKCS8), { name: 'Ed25519' }, false, ['sign']);
  const sig = await crypto.subtle.sign({ name: 'Ed25519' }, key, new TextEncoder().encode(canonical(cfg)));
  return b64(sig);
}

/**
 * Validate and write a new version. `state` defaults to the draft. Throws {status, body} on validation failure.
 */
export async function publish(env, { actor, note, kind = 'publish', state, request, force }) {
  const prev = await latestVersion(env);
  const prevVersion = prev ? prev.version : 0;
  let forceHide = !!force;
  if (state) state = normalizeState(state);
  if (!state) { const d = await getDraft(env); state = d.state; if (force === undefined) forceHide = d.force_hide; }
  const version = prevVersion + 1;
  const unassigned = prev ? await unassignedIds(env) : [];
  const cfg = buildConfig({ state, version, base: baseUrl(env, request), unassigned, forceHide });
  const catalogIds = prev ? await catalogIdSet(env) : new Set();
  const { errors, warnings } = validateConfig(cfg, { catalogIds, prevVersion, force: forceHide });
  if (errors.length) throw { status: 422, body: { error: 'validation_failed', errors, warnings } };
  const sig = await signConfig(env, cfg);
  const finalCfg = sig ? { ...cfg, sig } : cfg;
  const text = JSON.stringify(finalCfg);
  const etag = '"' + (await sha256Hex(text)).slice(0, 32) + '"';
  const created = nowIso();
  await env.DB.batch([
    env.DB.prepare('INSERT INTO config_versions (version, etag, json, state, kind, note, author, created_at) VALUES (?,?,?,?,?,?,?,?)')
      .bind(version, etag, text, JSON.stringify(state), kind, note || null, actor, created),
    env.DB.prepare('DELETE FROM config_versions WHERE version <= ?').bind(version - KEEP_VERSIONS),
    env.DB.prepare('DELETE FROM draft WHERE id = 1'),
  ]);
  await invalidateCache();
  await audit(env, actor, kind, { version, note: note || null, etag, signed: !!sig, hidden: finalCfg.hidden_granth_ids.length, overrides: Object.keys(finalCfg.overrides).length });
  return { version, etag, published_at: created, signed: !!sig, warnings };
}

export async function rollback(env, { actor, toVersion, request, note }) {
  const row = await env.DB.prepare('SELECT state, json, version FROM config_versions WHERE version = ?').bind(toVersion).first();
  if (!row) throw { status: 404, body: { error: 'version_not_found' } };
  const state = normalizeState(JSON.parse(row.state));
  const wasForced = JSON.parse(row.json).flags?.max_hidden_pct === 90;
  const res = await publish(env, { actor, note: note || `rollback to v${toVersion}`, kind: 'rollback', state, request, force: wasForced });
  return { ...res, rolled_back_to: toVersion };
}

async function invalidateCache() {
  memCache = { at: 0, row: null };
  try { await caches.default.delete(new Request(CACHE_KEY)); } catch { /* cache API not available */ }
}

/** Current published row, via isolate memory (15 s) -> Cache API (60 s) -> D1. Returns {version, etag, json}. */
export async function currentConfigRow(env, ctx, request) {
  if (memCache.row && Date.now() - memCache.at < MEM_TTL_MS) return memCache.row;
  try {
    const hit = await caches.default.match(new Request(CACHE_KEY));
    if (hit) {
      const row = { version: Number(hit.headers.get('x-cfg-version')), etag: hit.headers.get('x-cfg-etag'), json: await hit.text() };
      memCache = { at: Date.now(), row };
      return row;
    }
  } catch { /* ignore */ }
  let row = await env.DB.prepare('SELECT version, etag, json FROM config_versions ORDER BY version DESC LIMIT 1').first();
  if (!row) row = await ensureBootstrap(env, request).then(() => env.DB.prepare('SELECT version, etag, json FROM config_versions ORDER BY version DESC LIMIT 1').first());
  memCache = { at: Date.now(), row };
  try {
    const put = caches.default.put(new Request(CACHE_KEY), new Response(row.json, { headers: { 'cache-control': 'max-age=60', 'x-cfg-version': String(row.version), 'x-cfg-etag': row.etag } }));
    ctx && ctx.waitUntil ? ctx.waitUntil(put.catch(() => {})) : await put.catch(() => {});
  } catch { /* ignore */ }
  return row;
}

export const CONFIG_HEADERS = {
  'cache-control': 'public, max-age=60, stale-while-revalidate=600',
  'access-control-allow-origin': '*',
  'access-control-expose-headers': 'ETag',
  'content-type': 'application/json; charset=utf-8',
  'x-content-type-options': 'nosniff',
};

function etagMatches(inm, etag) {
  if (!inm) return false;
  const norm = (s) => s.trim().replace(/^W\//, '');
  if (inm.trim() === '*') return true;
  return inm.split(',').some((t) => norm(t) === norm(etag));
}

export async function serveConfig(request, env, ctx) {
  const row = await currentConfigRow(env, ctx, request);
  const headers = { ...CONFIG_HEADERS, etag: row.etag, 'x-config-version': String(row.version) };
  if (etagMatches(request.headers.get('if-none-match'), row.etag)) {
    const h304 = { ...headers };
    delete h304['content-type'];
    return new Response(null, { status: 304, headers: h304 });
  }
  return new Response(request.method === 'HEAD' ? null : row.json, { status: 200, headers });
}

export function effectiveLeafList(state) { return leaves(state.structure).map((l) => ({ key: l.key, label: l.label })).concat([{ key: OTHER, label: 'अन्य' }]); }
export { json };
