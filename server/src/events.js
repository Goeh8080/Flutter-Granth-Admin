// POST /events — anonymous analytics ingest (plan §7.4/§7.5). Always answers 204.
import { clampInt, sha256Hex, ID_RE, todayUtc } from './util.js';
import { currentConfigRow } from './config.js';
import { leafKeySet } from './structure.js';

export const LIMITS = { maxBodyBytes: 8192, maxGzipBytes: 8192, maxKeysPerMap: 200, fg_s: 21600, watch_s: 7200, count: 5000, batchesPerIidDay: 6, ipPerMinute: 60, dayWindow: 2 };
const IID_RE = /^[0-9a-f]{32}$/;
const BATCH_RE = /^[0-9a-zA-Z_-]{8,64}$/;
const APP_RE = /^[0-9A-Za-z.+_-]{1,24}$/;
const KIND_RE = /^[a-z0-9_]{1,24}$/;
const SCR_RE = /^[a-z0-9_-]{1,24}$/;
const LEAF_RE = /^[a-z0-9_-]{1,40}(\/[a-z0-9_-]{1,40}){0,2}$/;

const ipHits = new Map(); // per-isolate, best-effort; keys are salted hashes, never raw IPs, never persisted
let granthCache = { at: 0, ids: null };

function isObj(v) { return v && typeof v === 'object' && !Array.isArray(v); }

/** Pure validation/normalisation. Returns a normalised batch or {drop:'reason'}. */
export function sanitizeBatch(b, { today, leafKeys, granthIds }) {
  if (!isObj(b)) return { drop: 'not_object' };
  if (b.v !== 1) return { drop: 'bad_version' };
  if (typeof b.batch_id !== 'string' || !BATCH_RE.test(b.batch_id)) return { drop: 'batch_id' };
  if (typeof b.iid !== 'string' || !IID_RE.test(b.iid.toLowerCase())) return { drop: 'iid' };
  if (typeof b.app !== 'string' || !APP_RE.test(b.app)) return { drop: 'app' };
  if (typeof b.day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(b.day)) return { drop: 'day' };
  const dt = Date.parse(b.day + 'T00:00:00Z');
  const td = Date.parse(today + 'T00:00:00Z');
  if (!Number.isFinite(dt) || Math.abs(dt - td) > LIMITS.dayWindow * 864e5) return { drop: 'day_range' };
  for (const m of [b.open, b.open?.g, b.open?.f, b.open?.t, b.open?.p, b.watch_s, b.watch_s?.g, b.watch_s?.f, b.watch_s?.scr, b.sync?.kinds, b.pdf?.kinds]) {
    if (m !== undefined && !isObj(m)) return { drop: 'bad_map' };
    if (isObj(m) && Object.keys(m).length > LIMITS.maxKeysPerMap) return { drop: 'too_many_keys' };
  }
  const out = {
    batch_id: b.batch_id, iid: b.iid.toLowerCase(), app: b.app, day: b.day,
    os: ['android', 'ios', 'web'].includes(b.os) ? b.os : 'other',
    sdk: clampInt(b.sdk, 0, 99) ?? 0, cfg: clampInt(b.cfg, 0, 1e6) ?? 0,
    fg_s: clampInt(b.fg_s, 0, LIMITS.fg_s) ?? 0, sessions: clampInt(b.sessions, 0, LIMITS.count) ?? 0,
    g: {}, f: {}, wg: {}, wf: {}, scr: {}, topic_opens: 0, praman_opens: 0,
    sync: { ok: 0, fail: 0, kinds: {} }, pdf: { ok: 0, fail: 0, kinds: {} }, ai: { asked: 0, answered: 0, cite_tap: 0 },
  };
  const addCounts = (src, dst, keyOk, hi) => {
    if (!isObj(src)) return;
    for (const [k, v] of Object.entries(src)) {
      const n = clampInt(v, 0, hi);
      if (n === null || n === 0 || !keyOk(k)) continue;
      dst[k] = (dst[k] || 0) + n;
    }
  };
  const gOk = (k) => ID_RE.test(k) && (!granthIds || granthIds.has(k));
  const fOk = (k) => LEAF_RE.test(k) && (!leafKeys || leafKeys.has(k));
  addCounts(b.open?.g, out.g, gOk, LIMITS.count);
  addCounts(b.open?.f, out.f, fOk, LIMITS.count);
  addCounts(b.watch_s?.g, out.wg, gOk, LIMITS.watch_s);
  addCounts(b.watch_s?.f, out.wf, fOk, LIMITS.watch_s);
  addCounts(b.watch_s?.scr, out.scr, (k) => SCR_RE.test(k), LIMITS.watch_s);
  for (const [k, v] of Object.entries(b.open?.t || {})) if (ID_RE.test(k)) out.topic_opens += clampInt(v, 0, LIMITS.count) || 0;
  for (const [k, v] of Object.entries(b.open?.p || {})) if (ID_RE.test(k)) out.praman_opens += clampInt(v, 0, LIMITS.count) || 0;
  out.topic_opens = Math.min(out.topic_opens, 200000); out.praman_opens = Math.min(out.praman_opens, 200000);
  for (const [name, dst] of [['sync', out.sync], ['pdf', out.pdf]]) {
    const s = b[name];
    if (!isObj(s)) continue;
    dst.ok = clampInt(s.ok, 0, LIMITS.count) ?? 0; dst.fail = clampInt(s.fail, 0, LIMITS.count) ?? 0;
    addCounts(s.kinds, dst.kinds, (k) => KIND_RE.test(k), LIMITS.count);
    // keep at most 12 kinds
    const ks = Object.entries(dst.kinds).slice(0, 12); dst.kinds = Object.fromEntries(ks);
  }
  if (isObj(b.ai)) for (const k of ['asked', 'answered', 'cite_tap']) out.ai[k] = clampInt(b.ai[k], 0, LIMITS.count) ?? 0;
  out.scr = Object.fromEntries(Object.entries(out.scr).slice(0, 30));
  return out;
}

async function readBody(request) {
  const len = Number(request.headers.get('content-length') || '0');
  if (len > LIMITS.maxGzipBytes * 2) return null;
  if (!request.body) return null;
  let stream = request.body;
  const ce = (request.headers.get('content-encoding') || '').toLowerCase();
  if (ce === 'gzip' || ce === 'x-gzip') stream = stream.pipeThrough(new DecompressionStream('gzip'));
  else if (ce && ce !== 'identity') return null;
  const reader = stream.getReader();
  const chunks = []; let total = 0;
  const cap = LIMITS.maxBodyBytes;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > cap) { await reader.cancel().catch(() => {}); return null; }
      chunks.push(value);
    }
  } catch { return null; }
  const u = new Uint8Array(total); let o = 0; for (const c of chunks) { u.set(c, o); o += c.length; }
  return new TextDecoder().decode(u);
}

async function knownGranthIds(env) {
  if (granthCache.ids && Date.now() - granthCache.at < 300000) return granthCache.ids;
  const r = await env.DB.prepare('SELECT id FROM granths_seen').all();
  const ids = new Set(r.results.map((x) => x.id));
  granthCache = { at: Date.now(), ids: ids.size ? ids : null };
  return granthCache.ids;
}

function upsertRows(env, table, cols, rows, setSql) {
  // multi-row upserts (D1 allows 100 bound params/statement)
  const stmts = [];
  const per = Math.floor(90 / cols.length);
  for (let i = 0; i < rows.length; i += per) {
    const chunk = rows.slice(i, i + per);
    const ph = chunk.map(() => '(' + cols.map(() => '?').join(',') + ')').join(',');
    stmts.push(env.DB.prepare(`INSERT INTO ${table} (${cols.join(',')}) VALUES ${ph} ON CONFLICT(${cols[0]},${cols[1]}) DO UPDATE SET ${setSql}`).bind(...chunk.flat()));
  }
  return stmts;
}

export async function ingest(request, env, ctx) {
  const done = new Response(null, { status: 204, headers: { 'access-control-allow-origin': '*', 'cache-control': 'no-store' } });
  try {
    if (request.method !== 'POST') return done;
    const ih = (await sha256Hex(`${env.PEPPER || 'dev'}|ev|${request.headers.get('cf-connecting-ip') || 'unknown'}`)).slice(0, 16);
    const minute = Math.floor(Date.now() / 60000);
    const hk = `${ih}:${minute}`;
    if (ipHits.size > 5000) ipHits.clear();
    const hits = (ipHits.get(hk) || 0) + 1;
    ipHits.set(hk, hits);
    if (hits > LIMITS.ipPerMinute) return done;
    const text = await readBody(request);
    if (!text) return done;
    let raw; try { raw = JSON.parse(text); } catch { return done; }
    const cfg = await currentConfigRow(env, ctx, request);
    const state = JSON.parse(cfg.json);
    if (state.flags && state.flags.analytics_enabled === false) return done;
    const b = sanitizeBatch(raw, { today: todayUtc(), leafKeys: leafKeySet(state.structure), granthIds: await knownGranthIds(env) });
    if (b.drop) return done;
    const iidHash = (await sha256Hex(`${env.PEPPER || 'dev'}|iid|${b.iid}`)).slice(0, 16);
    const [seen, act] = await env.DB.batch([
      env.DB.prepare('SELECT 1 AS x FROM batch_seen WHERE batch_id = ?').bind(b.batch_id),
      env.DB.prepare('SELECT batches FROM active WHERE iid_hash = ? AND day = ?').bind(iidHash, b.day),
    ]);
    if (seen.results.length) return done;
    const prior = act.results[0];
    if (prior && prior.batches >= LIMITS.batchesPerIidDay) return done;
    const dau = prior ? 0 : 1;
    const stmts = [
      env.DB.prepare('INSERT INTO batch_seen (batch_id, day) VALUES (?, ?)').bind(b.batch_id, b.day), // PK conflict (a race duplicate) aborts the whole batch
      env.DB.prepare('INSERT INTO active (iid_hash, day, batches) VALUES (?,?,1) ON CONFLICT(iid_hash, day) DO UPDATE SET batches = batches + 1').bind(iidHash, b.day),
      env.DB.prepare(`INSERT INTO daily_app (day, app, dau, batches, sessions, fg_s, topic_opens, praman_opens, sync_ok, sync_fail, pdf_ok, pdf_fail, ai_asked, ai_answered, ai_cite)
        VALUES (?,?,?,1,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(day, app) DO UPDATE SET dau = dau + excluded.dau, batches = batches + 1, sessions = sessions + excluded.sessions,
        fg_s = fg_s + excluded.fg_s, topic_opens = topic_opens + excluded.topic_opens, praman_opens = praman_opens + excluded.praman_opens,
        sync_ok = sync_ok + excluded.sync_ok, sync_fail = sync_fail + excluded.sync_fail, pdf_ok = pdf_ok + excluded.pdf_ok, pdf_fail = pdf_fail + excluded.pdf_fail,
        ai_asked = ai_asked + excluded.ai_asked, ai_answered = ai_answered + excluded.ai_answered, ai_cite = ai_cite + excluded.ai_cite`)
        .bind(b.day, b.app, dau, b.sessions, b.fg_s, b.topic_opens, b.praman_opens, b.sync.ok, b.sync.fail, b.pdf.ok, b.pdf.fail, b.ai.asked, b.ai.answered, b.ai.cite_tap),
    ];
    stmts.push(env.DB.prepare(`INSERT INTO installs (iid_hash, first_seen, last_seen, app_version, os) VALUES (?,?,?,?,?)
      ON CONFLICT(iid_hash) DO UPDATE SET first_seen = MIN(first_seen, excluded.first_seen),
        app_version = CASE WHEN excluded.last_seen >= last_seen THEN excluded.app_version ELSE app_version END,
        os = CASE WHEN excluded.last_seen >= last_seen THEN excluded.os ELSE os END,
        last_seen = MAX(last_seen, excluded.last_seen)`).bind(iidHash, b.day, b.day, b.app, b.os));
    const gids = new Set([...Object.keys(b.g), ...Object.keys(b.wg)]);
    stmts.push(...upsertRows(env, 'daily_granth', ['day', 'gid', 'opens', 'watch_s'], [...gids].map((g) => [b.day, g, b.g[g] || 0, b.wg[g] || 0]), 'opens = opens + excluded.opens, watch_s = watch_s + excluded.watch_s'));
    const fk = new Set([...Object.keys(b.f), ...Object.keys(b.wf)]);
    stmts.push(...upsertRows(env, 'daily_folder', ['day', 'fkey', 'opens', 'watch_s'], [...fk].map((k) => [b.day, k, b.f[k] || 0, b.wf[k] || 0]), 'opens = opens + excluded.opens, watch_s = watch_s + excluded.watch_s'));
    stmts.push(...upsertRows(env, 'daily_screen', ['day', 'scr', 'watch_s'], Object.entries(b.scr).map(([k, v]) => [b.day, k, v]), 'watch_s = watch_s + excluded.watch_s'));
    const kinds = [];
    for (const [k, v] of Object.entries(b.sync.kinds)) kinds.push([b.day, `sync:${k}`, v]);
    for (const [k, v] of Object.entries(b.pdf.kinds)) kinds.push([b.day, `pdf:${k}`, v]);
    stmts.push(...upsertRows(env, 'daily_kind', ['day', 'kind', 'n'], kinds, 'n = n + excluded.n'));
    await env.DB.batch(stmts);
  } catch (e) {
    // never leak anything to the app; duplicate-race failures land here too
  }
  return done;
}
