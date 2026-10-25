// Admin API (/admin/api/*), plan §6.2. Everything here runs behind session + CSRF checks (except login).
import { json, nowIso, nowSec, numCmp, ID_RE, safeEqual, todayUtc } from './util.js';
import { login, logout, getSession, changePassword } from './auth.js';
import { audit } from './audit.js';
import { getDraft, saveDraft, discardDraft, publish, rollback, latestVersion, ensureBootstrap, unassignedIds, catalogIdSet, baseUrl } from './config.js';
import { leaves, leafKeySet, placements, validateStructure, validateAnnouncement, validateEndpointUrl, normalizeState, OTHER, GROUP_ICONS, RELIGION_ICONS, TONES, ANNOUNCE_LEVELS } from './structure.js';
import * as stats from './stats.js';
import { syncCatalog } from './cron.js';
import { handleAdmins } from './admins.js';
import { handleContacts } from './contacts.js';

const CATALOG_ORIGIN = 'https://granth.wnmsolutions.com/';

let bootstrapped = false;
const fail = (status, error, extra = {}) => json({ error, ...extra }, status);

async function body(request) { try { const b = await request.json(); return b && typeof b === 'object' ? b : {}; } catch { return null; } }

async function allGranths(env) {
  return (await env.DB.prepare('SELECT id, title, author, cover, position, praman_count, active, created_at, first_seen, assigned_at, missing_runs, removed_at FROM granths_seen').all()).results;
}

// ---- granths sorting (GET /granths?sort=&order=) -------------------------------------------------
// "number" = the catalog's own `position` (1 = first granth on the wnm site / app). It is NOT the granth id.
export const SORT_ALIASES = { number: 'position', position: 'position', id: 'id', title: 'title', opens: 'opens', watch: 'watch', praman: 'praman', newest: 'newest' };
const DEFAULT_ORDER = { position: 'asc', id: 'asc', title: 'asc', opens: 'desc', watch: 'desc', praman: 'desc', newest: 'desc' };
const posOf = (p) => { const n = parseInt(p, 10); return Number.isFinite(n) && n > 0 ? n : null; };
const collator = new Intl.Collator('hi');
export function makeComparator(key, order) {
  const dir = order === 'desc' ? -1 : 1;
  const byPos = (a, b) => ((a.position ?? Infinity) - (b.position ?? Infinity)) || numCmp(a.id, b.id); // stable tiebreak: catalog order, then id
  const primary = {
    position: (a, b) => ((a.position ?? Infinity) === (b.position ?? Infinity) ? 0 : (a.position ?? Infinity) < (b.position ?? Infinity) ? -1 : 1),
    id: (a, b) => numCmp(a.id, b.id),
    title: (a, b) => collator.compare(a.title || '', b.title || ''),
    opens: (a, b) => a.opens_7d - b.opens_7d,
    watch: (a, b) => a.watch_s_7d - b.watch_s_7d,
    praman: (a, b) => a.praman_count - b.praman_count,
    newest: (a, b) => (a.created_at || '') < (b.created_at || '') ? -1 : (a.created_at || '') > (b.created_at || '') ? 1 : 0,
  }[key];
  return (a, b) => { const c = primary(a, b); return c ? c * dir : byPos(a, b); };
}

function structureLeafOptions(structure) {
  return leaves(structure).map((l) => ({ key: l.key, label: l.label, religion: l.religion.title, religion_id: l.religion.id, group: l.parent ? `${l.parent.title} › ${l.leaf.title}` : l.leaf.title, visible: l.religion.visible !== false && l.leaf.visible !== false })).concat([{ key: OTHER, label: 'अन्य', religion: 'अन्य', religion_id: OTHER, group: 'अन्य', visible: true }]);
}

// ---- diff ---------------------------------------------------------------------------------------
function flatNodes(structure) {
  const out = new Map();
  (structure.religions || []).forEach((r, i) => {
    out.set(r.id, { path: r.id, kind: 'religion', title: r.title, icon: r.icon, tone: r.tone, visible: r.visible !== false, coming_soon: r.coming_soon || '', order: i, parent: '' });
    (r.groups || []).forEach((g, j) => {
      out.set(`${r.id}/${g.id}`, { path: `${r.id}/${g.id}`, kind: 'group', title: g.title, icon: g.icon, visible: g.visible !== false, coming_soon: g.coming_soon || '', order: j, parent: r.id });
      (g.subgroups || []).forEach((s, k) => out.set(`${r.id}/${g.id}/${s.id}`, { path: `${r.id}/${g.id}/${s.id}`, kind: 'subgroup', title: s.title, icon: s.icon, visible: s.visible !== false, coming_soon: s.coming_soon || '', order: k, parent: `${r.id}/${g.id}` }));
    });
  });
  return out;
}
export function diffStates(a, b, granthRows, catalogTotal) {
  const titles = new Map(granthRows.map((g) => [g.id, g.title]));
  const live = granthRows.filter((g) => !g.removed_at);
  const pa = placements(a.structure, a.overrides, live), pb = placements(b.structure, b.overrides, live);
  const lblA = new Map(leaves(a.structure).map((l) => [l.key, l.label])), lblB = new Map(leaves(b.structure).map((l) => [l.key, l.label]));
  lblA.set(OTHER, 'अन्य'); lblB.set(OTHER, 'अन्य');
  const hidA = new Set(a.hidden_granth_ids), hidB = new Set(b.hidden_granth_ids);
  const granths = [];
  for (const g of live) {
    const ch = {};
    if (pa[g.id].key !== pb[g.id].key) ch.folder = { from: lblA.get(pa[g.id].key) || pa[g.id].key, to: lblB.get(pb[g.id].key) || pb[g.id].key };
    if (hidA.has(g.id) !== hidB.has(g.id)) ch.hidden = { from: hidA.has(g.id), to: hidB.has(g.id) };
    if (Object.keys(ch).length) granths.push({ id: g.id, title: titles.get(g.id), ...ch });
  }
  const na = flatNodes(a.structure), nb = flatNodes(b.structure);
  const folders = [];
  for (const [k, n] of nb) {
    const o = na.get(k);
    if (!o) { folders.push({ path: k, change: 'added', title: n.title }); continue; }
    const d = [];
    for (const f of ['title', 'icon', 'tone', 'visible', 'coming_soon']) if (o[f] !== n[f]) d.push({ field: f, from: o[f], to: n[f] });
    if (o.order !== n.order) d.push({ field: 'order', from: o.order + 1, to: n.order + 1 });
    if (o.parent !== n.parent) d.push({ field: 'parent', from: o.parent, to: n.parent });
    if (d.length) folders.push({ path: k, change: 'edited', title: n.title, fields: d });
  }
  for (const [k, o] of na) if (!nb.has(k)) folders.push({ path: k, change: 'removed', title: o.title });
  const settings = [];
  for (const f of new Set([...Object.keys(a.flags), ...Object.keys(b.flags)])) if (JSON.stringify(a.flags[f]) !== JSON.stringify(b.flags[f])) settings.push({ field: `flags.${f}`, from: a.flags[f], to: b.flags[f] });
  for (const f of new Set([...Object.keys(a.announcement), ...Object.keys(b.announcement)])) if (JSON.stringify(a.announcement[f]) !== JSON.stringify(b.announcement[f])) settings.push({ field: `announcement.${f}`, from: a.announcement[f], to: b.announcement[f] });
  if (a.ai_endpoint !== b.ai_endpoint) settings.push({ field: 'endpoints.ai', from: a.ai_endpoint, to: b.ai_endpoint });
  const contacts = [];
  if (JSON.stringify(a.contacts_page) !== JSON.stringify(b.contacts_page)) settings.push({ field: 'contacts_page.title', from: a.contacts_page.title, to: b.contacts_page.title });
  const ca = new Map(a.contacts.map((c) => [c.id, c])), cb = new Map(b.contacts.map((c) => [c.id, c]));
  for (const [id, c] of cb) {
    const o = ca.get(id);
    if (!o) { contacts.push({ id, name: c.name, change: 'added' }); continue; }
    const fields = ['name', 'role', 'phone', 'whatsapp', 'visible', 'order'].filter((f) => o[f] !== c[f]).map((f) => ({ field: f, from: o[f], to: c[f] }));
    if (fields.length) contacts.push({ id, name: c.name, change: 'edited', fields });
  }
  for (const [id, o] of ca) if (!cb.has(id)) contacts.push({ id, name: o.name, change: 'removed' });
  const warnings = [];
  const inCat = b.hidden_granth_ids.filter((id) => live.some((g) => g.id === id)).length;
  if (catalogTotal && inCat / catalogTotal > 0.5) warnings.push(`This hides ${inCat} of ${catalogTotal} granths (>50%) — publishing needs the force checkbox.`);
  return { granths, folders, contacts, settings, hidden_count: inCat, catalog_total: catalogTotal, warnings, changed: granths.length + folders.length + contacts.length + settings.length };
}

// ---- helpers ------------------------------------------------------------------------------------
async function markAssigned(env, ids) {
  const now = nowIso();
  for (let i = 0; i < ids.length; i += 50) await env.DB.batch(ids.slice(i, i + 50).map((id) => env.DB.prepare('UPDATE granths_seen SET assigned_at = COALESCE(assigned_at, ?) WHERE id = ?').bind(now, id)));
}
function applyGranthEdit(state, ids, edit, keys) {
  const hidden = new Set(state.hidden_granth_ids);
  for (const id of ids) {
    if ('leaf' in edit) {
      if (edit.leaf === null) delete state.overrides[id];
      else state.overrides[id] = { leaf: edit.leaf };
    }
    if ('hidden' in edit) edit.hidden ? hidden.add(id) : hidden.delete(id);
  }
  state.hidden_granth_ids = [...hidden].sort(numCmp);
}
function checkEdit(b, keys) {
  const edit = {};
  if ('leaf' in b) {
    if (b.leaf !== null && (typeof b.leaf !== 'string' || !keys.has(b.leaf))) return { error: 'unknown_leaf', message: `folder "${b.leaf}" does not exist` };
    edit.leaf = b.leaf;
  }
  if ('hidden' in b) { if (typeof b.hidden !== 'boolean') return { error: 'bad_hidden' }; edit.hidden = b.hidden; }
  if (!Object.keys(edit).length) return { error: 'nothing_to_change' };
  return { edit };
}
const draftInfo = async (env) => { const pub = await latestVersion(env); const d = await getDraft(env); return { has_draft: d.exists, base_version: pub.version, next_version: pub.version + 1 }; };

function leafUsage(structure, overrides) {
  const keys = leafKeySet(structure);
  const bad = {};
  for (const [id, o] of Object.entries(overrides)) if (!keys.has(o.leaf)) (bad[o.leaf] ||= []).push(id);
  return bad;
}

// ---- router -------------------------------------------------------------------------------------
export async function handleAdmin(request, env, ctx, url) {
  const path = url.pathname.replace(/^\/admin\/api/, '') || '/';
  const method = request.method;
  const h = (res) => { res.headers.set('cache-control', 'no-store'); res.headers.set('x-content-type-options', 'nosniff'); return res; };
  try {
    const sameOrigin = () => { const o = request.headers.get('origin'); return !o || o === url.origin; };
    if (path === '/login' && method === 'POST') { if (!sameOrigin()) return h(fail(403, 'bad_origin')); return h(await login(request, env)); }
    const session = await getSession(request, env);
    if (!session) return h(fail(401, 'unauthorized'));
    if (method !== 'GET' && method !== 'HEAD' && !session.bearer) { // bearer (app) requests are not ambient credentials => no CSRF needed
      if (!sameOrigin()) return h(fail(403, 'bad_origin'));
      const t = request.headers.get('x-admin-csrf') || '';
      if (!t || !safeEqual(t, session.csrf)) return h(fail(403, 'csrf'));
    }
    if (!bootstrapped) { await ensureBootstrap(env, request); bootstrapped = true; }
    const res = await route(request, env, ctx, url, path, method, session);
    if (session.cookie) res.headers.append('set-cookie', session.cookie);
    return h(res);
  } catch (e) {
    if (e && e.status && e.body) return h(json(e.body, e.status));
    console.error('admin error', e && e.stack || e);
    return h(fail(500, 'internal'));
  }
}

async function route(request, env, ctx, url, path, method, session) {
  const actor = session.username;
  let m;
  if (path === '/logout' && method === 'POST') return logout(session, env);
  if (path === '/me' && method === 'GET') {
    const pub = await latestVersion(env);
    return json({ username: actor, role: session.role, can_manage_admins: session.role === 'owner', auth: session.bearer ? 'bearer' : 'cookie', csrf: session.csrf, version: pub.version, base: baseUrl(env, request), ...(await draftInfo(env)) });
  }
  if (path === '/sessions' && method === 'GET') {
    const r = await env.DB.prepare('SELECT id_hash, client, created_at, last_seen, expires_at FROM sessions WHERE username = ? AND expires_at > ? ORDER BY last_seen DESC').bind(actor, nowSec()).all();
    return json({ items: r.results.map((x) => ({ sid: x.id_hash.slice(0, 16), client: x.client, kind: x.client === 'web' ? 'web' : 'app', created_at: new Date(x.created_at * 1000).toISOString(), last_seen: new Date(x.last_seen * 1000).toISOString(), current: x.id_hash === session.idHash })) });
  }
  if (path === '/sessions/revoke_all' && method === 'POST') {
    const r = await env.DB.prepare('DELETE FROM sessions WHERE username = ? AND id_hash != ?').bind(actor, session.idHash).run();
    await audit(env, actor, 'sessions_revoke_all', { n: r.meta?.changes ?? null });
    return json({ ok: true });
  }
  if ((m = path.match(/^\/sessions\/([0-9a-f]{16})$/)) && method === 'DELETE') {
    const r = await env.DB.prepare('DELETE FROM sessions WHERE username = ? AND substr(id_hash, 1, 16) = ? AND id_hash != ?').bind(actor, m[1], session.idHash).run();
    if (!(r.meta?.changes > 0)) return fail(404, 'session_not_found');
    await audit(env, actor, 'session_revoke', { sid: m[1] });
    return json({ ok: true });
  }
  if (path === '/password' && method === 'POST') return changePassword(request, env, session);
  { const r = await handleAdmins(request, env, session, path, method); if (r) return r; }
  { const r = await handleContacts(request, env, actor, path, method); if (r) return r; }

  // --- granths
  if (path === '/granths' && method === 'GET') {
    const [rows, d, pub, o7] = await Promise.all([allGranths(env), getDraft(env), latestVersion(env), env.DB.prepare('SELECT gid, SUM(opens) AS opens, SUM(watch_s) AS watch_s FROM daily_granth WHERE day >= ? GROUP BY gid').bind(todayUtc(-6)).all()]);
    const live = rows.filter((g) => !g.removed_at);
    const pl = placements(d.state.structure, d.state.overrides, live);
    const plNo = placements(d.state.structure, {}, live);
    const lbl = new Map(leaves(d.state.structure).map((l) => [l.key, l.label])); lbl.set(OTHER, 'अन्य');
    const hidden = new Set(d.state.hidden_granth_ids), use = new Map(o7.results.map((x) => [x.gid, x]));
    const meta = Object.fromEntries((await env.DB.prepare("SELECT k, v FROM meta WHERE k LIKE 'sync_%'").all()).results.map((x) => [x.k, x.v]));
    const sortKey = SORT_ALIASES[url.searchParams.get('sort') || 'number'];
    if (!sortKey) return fail(422, 'bad_sort', { message: `sort must be one of ${Object.keys(SORT_ALIASES).join(', ')}` });
    const ordQ = url.searchParams.get('order');
    if (ordQ !== null && ordQ !== 'asc' && ordQ !== 'desc') return fail(422, 'bad_order', { message: 'order must be asc or desc' });
    const order = ordQ || DEFAULT_ORDER[sortKey];
    const comparator = makeComparator(sortKey, order);
    const items = live.map((g) => ({
      id: g.id, position: posOf(g.position), created_at: g.created_at || null, title: g.title, author: g.author, cover: g.cover ? CATALOG_ORIGIN + g.cover : null, praman_count: g.praman_count, active: !!g.active,
      leaf: pl[g.id].key, leaf_label: lbl.get(pl[g.id].key) || pl[g.id].key, source: pl[g.id].how, default_leaf: plNo[g.id].key,
      hidden: hidden.has(g.id), is_new: !g.assigned_at, first_seen: g.first_seen, no_praman: g.praman_count === 0,
      opens_7d: use.get(g.id)?.opens || 0, watch_s_7d: use.get(g.id)?.watch_s || 0,
    }));
    items.sort(comparator);
    return json({ sort: sortKey, order, items, leaves: structureLeafOptions(d.state.structure), draft: d.exists, base_version: pub.version, sync: meta, total: items.length, hidden_count: items.filter((x) => x.hidden).length });
  }
  if ((m = path.match(/^\/granths\/(\d{1,8})$/)) && method === 'PUT') {
    const id = m[1];
    const b = await body(request); if (!b) return fail(400, 'bad_request');
    if (!(await env.DB.prepare('SELECT 1 AS x FROM granths_seen WHERE id = ? AND removed_at IS NULL').bind(id).first())) return fail(404, 'granth_not_found');
    const d = await getDraft(env);
    const c = checkEdit(b, leafKeySet(d.state.structure)); if (c.error) return fail(422, c.error, c);
    applyGranthEdit(d.state, [id], c.edit);
    await saveDraft(env, d.state, actor);
    await markAssigned(env, [id]);
    await audit(env, actor, 'granth_edit', { id, ...c.edit });
    return json({ ok: true, ...(await draftInfo(env)) });
  }
  if (path === '/granths/bulk' && method === 'POST') {
    const b = await body(request); if (!b || !Array.isArray(b.ids)) return fail(400, 'bad_request');
    const ids = [...new Set(b.ids.map(String))];
    if (!ids.length || ids.length > 300 || ids.some((i) => !ID_RE.test(i))) return fail(422, 'bad_ids');
    const rows = new Set((await allGranths(env)).filter((g) => !g.removed_at).map((g) => g.id));
    const unknown = ids.filter((i) => !rows.has(i)); if (unknown.length) return fail(404, 'granth_not_found', { ids: unknown });
    const d = await getDraft(env);
    const c = checkEdit(b, leafKeySet(d.state.structure)); if (c.error) return fail(422, c.error, c);
    applyGranthEdit(d.state, ids, c.edit);
    await saveDraft(env, d.state, actor);
    await markAssigned(env, ids);
    await audit(env, actor, 'granth_bulk_edit', { count: ids.length, ids: ids.slice(0, 40), ...c.edit });
    return json({ ok: true, changed: ids.length, ...(await draftInfo(env)) });
  }

  // --- structure (folders)
  if (path === '/structure' && method === 'GET') {
    const d = await getDraft(env);
    const rows = (await allGranths(env)).filter((g) => !g.removed_at);
    const pl = placements(d.state.structure, d.state.overrides, rows);
    const counts = {}; for (const g of rows) counts[pl[g.id].key] = (counts[pl[g.id].key] || 0) + 1;
    return json({ structure: d.state.structure, counts, leaves: structureLeafOptions(d.state.structure), icons: { group: GROUP_ICONS, religion: RELIGION_ICONS, tones: TONES }, draft: d.exists, base_version: d.base_version });
  }
  if (path === '/structure' && method === 'PUT') {
    const b = await body(request); if (!b || !b.structure) return fail(400, 'bad_request');
    const d = await getDraft(env);
    const next = JSON.parse(JSON.stringify(b.structure));
    next.other = { ...d.state.structure.other, ...(typeof b.structure.other?.coming_soon === 'string' ? { coming_soon: b.structure.other.coming_soon } : {}) };
    if (next.other.coming_soon === '') delete next.other.coming_soon;
    next.version = (d.state.structure.version || 1) + 1;
    const errs = validateStructure(next);
    if (errs.length) return fail(422, 'invalid_structure', { errors: errs });
    const bad = leafUsage(next, d.state.overrides);
    if (Object.keys(bad).length) {
      if (b.drop_overrides !== true) return fail(409, 'leaf_in_use', { message: 'Some granths are assigned to folders you removed. Re-send with drop_overrides:true to send them back to their default place.', leaves: bad });
      for (const ids of Object.values(bad)) for (const id of ids) delete d.state.overrides[id];
    }
    d.state.structure = next;
    await saveDraft(env, d.state, actor);
    await audit(env, actor, 'structure_edit', { religions: next.religions.length, dropped_overrides: Object.values(bad).flat().length });
    return json({ ok: true, ...(await draftInfo(env)) });
  }

  // --- draft / publish
  if (path === '/draft' && method === 'GET') {
    const [d, pub, rows, cat] = await Promise.all([getDraft(env), latestVersion(env), allGranths(env), catalogIdSet(env)]);
    return json({ exists: d.exists, base_version: pub.version, next_version: pub.version + 1, updated_at: d.updated_at || null, diff: diffStates(normalizeState(JSON.parse(pub.state)), d.state, rows, cat.size) });
  }
  if (path === '/draft/diff' && method === 'GET') {
    const [d, pub, rows, cat] = await Promise.all([getDraft(env), latestVersion(env), allGranths(env), catalogIdSet(env)]);
    return json({ exists: d.exists, from_version: pub.version, diff: diffStates(normalizeState(JSON.parse(pub.state)), d.state, rows, cat.size) });
  }
  if (path === '/draft/discard' && method === 'POST') { await discardDraft(env); await audit(env, actor, 'draft_discard', {}); return json({ ok: true }); }
  if (path === '/publish' && method === 'POST') {
    const b = (await body(request)) || {};
    const d = await getDraft(env), pub = await latestVersion(env);
    if (!d.exists || JSON.stringify(d.state) === JSON.stringify(normalizeState(JSON.parse(pub.state)))) {
      if (b.allow_empty !== true) return fail(409, 'no_changes', { message: 'Nothing to publish.' });
    }
    const res = await publish(env, { actor, note: typeof b.note === 'string' ? b.note.slice(0, 200) : null, state: d.state, request, force: b.force === true });
    return json({ ok: true, ...res });
  }
  if (path === '/rollback' && method === 'POST') {
    const b = await body(request); const v = Number(b && b.to_version);
    if (!Number.isInteger(v)) return fail(422, 'bad_version');
    const res = await rollback(env, { actor, toVersion: v, request, note: typeof b.note === 'string' ? b.note.slice(0, 200) : undefined });
    return json({ ok: true, ...res });
  }
  if (path === '/versions' && method === 'GET') {
    const r = await env.DB.prepare('SELECT version, etag, kind, note, author, created_at, length(json) AS bytes FROM config_versions ORDER BY version DESC').all();
    return json({ items: r.results, current: r.results[0]?.version || 0 });
  }
  if ((m = path.match(/^\/versions\/(\d+)$/)) && method === 'GET') {
    const v = Number(m[1]);
    const row = await env.DB.prepare('SELECT version, etag, kind, note, author, created_at, json, state FROM config_versions WHERE version = ?').bind(v).first();
    if (!row) return fail(404, 'version_not_found');
    const against = url.searchParams.get('against') ? Number(url.searchParams.get('against')) : v - 1;
    const prev = await env.DB.prepare('SELECT state FROM config_versions WHERE version = ?').bind(against).first();
    const [rows, cat] = await Promise.all([allGranths(env), catalogIdSet(env)]);
    return json({ version: row.version, etag: row.etag, kind: row.kind, note: row.note, author: row.author, created_at: row.created_at, against: prev ? against : null, diff: prev ? diffStates(normalizeState(JSON.parse(prev.state)), normalizeState(JSON.parse(row.state)), rows, cat.size) : null, config: JSON.parse(row.json) });
  }

  // --- alerts / inbox
  if (path === '/alerts' && method === 'GET') {
    const d = await getDraft(env);
    const newRows = (await env.DB.prepare('SELECT id, title, author, cover, position, praman_count, first_seen FROM granths_seen WHERE assigned_at IS NULL AND removed_at IS NULL AND active = 1').all()).results;
    newRows.sort((a, b) => ((posOf(a.position) ?? Infinity) - (posOf(b.position) ?? Infinity)) || numCmp(a.id, b.id)); // ascending catalog number
    const pl = placements(d.state.structure, d.state.overrides, newRows);
    const lbl = new Map(leaves(d.state.structure).map((l) => [l.key, l.label])); lbl.set(OTHER, 'अन्य');
    const other = (await env.DB.prepare('SELECT id, kind, ref, message, created_at FROM alerts WHERE acked_at IS NULL ORDER BY id DESC LIMIT 50').all()).results;
    return json({
      new_granths: newRows.map((g) => ({ id: g.id, position: posOf(g.position), title: g.title, author: g.author, cover: g.cover ? CATALOG_ORIGIN + g.cover : null, praman_count: g.praman_count, first_seen: g.first_seen, suggested_leaf: pl[g.id].key, suggested_label: lbl.get(pl[g.id].key), suggestion_source: pl[g.id].how })),
      alerts: other, count: newRows.length + other.length,
    });
  }
  if ((m = path.match(/^\/alerts\/(g:\d{1,8}|a:\d+)\/ack$/)) && method === 'POST') {
    const [kind, ref] = m[1].split(':');
    if (kind === 'g') { await markAssigned(env, [ref]); await audit(env, actor, 'new_granth_ack', { id: ref }); }
    else { await env.DB.prepare('UPDATE alerts SET acked_at = ? WHERE id = ?').bind(nowIso(), Number(ref)).run(); await audit(env, actor, 'alert_ack', { id: Number(ref) }); }
    return json({ ok: true });
  }
  if (path === '/sync' && method === 'POST') {
    const last = await env.DB.prepare("SELECT v FROM meta WHERE k = 'manual_sync_at'").first();
    if (last && Date.now() - Number(last.v) < 30000) return fail(429, 'too_soon');
    await env.DB.prepare("INSERT INTO meta (k, v) VALUES ('manual_sync_at', ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v").bind(String(Date.now())).run();
    const r = await syncCatalog(env);
    await audit(env, actor, 'catalog_sync', { ok: r.ok, added: r.added?.length, removed: r.removed?.length });
    return json(r);
  }

  // --- stats
  if (method === 'GET' && path.startsWith('/stats/')) {
    const sub = path.slice(7);
    if (sub === 'overview') return json(await stats.overview(env, url, (await getDraft(env)).state));
    if (sub === 'granths') return json(await stats.granthStats(env, url));
    if (sub === 'folders') return json(await stats.folderStats(env, url, (await getDraft(env)).state));
    if (sub === 'series') return json(await stats.series(env, url));
  }

  // --- settings
  if (path === '/settings' && method === 'GET') {
    const d = await getDraft(env), pub = await latestVersion(env);
    const admins = (await env.DB.prepare('SELECT username, iters FROM admins').all()).results;
    return json({
      flags: d.state.flags, announcement: d.state.announcement, ai_endpoint: d.state.ai_endpoint, levels: ANNOUNCE_LEVELS,
      info: { base: baseUrl(env, request), published_version: pub.version, signing_public_key: env.SIGNING_PUBLIC_KEY || null, signed: !!env.SIGNING_KEY_PKCS8, pbkdf2_iterations: admins[0]?.iters, admins: admins.map((a) => a.username) },
      draft: d.exists,
    });
  }
  if (path === '/settings' && method === 'PUT') {
    const b = await body(request); if (!b) return fail(400, 'bad_request');
    const d = await getDraft(env), st = d.state;
    if (b.flags) {
      const f = b.flags;
      if ('ai_enabled' in f) st.flags.ai_enabled = f.ai_enabled === true;
      if ('analytics_enabled' in f) st.flags.analytics_enabled = f.analytics_enabled === true;
      if ('analytics_sample' in f) { const n = Number(f.analytics_sample); if (!(n >= 0 && n <= 1)) return fail(422, 'bad_sample'); st.flags.analytics_sample = n; }
    }
    if (b.announcement) {
      const a = { ...st.announcement, ...b.announcement };
      const keep = { enabled: a.enabled === true, text: String(a.text ?? '').trim(), id: String(a.id ?? ''), level: a.level };
      if (a.expires_at) keep.expires_at = a.expires_at;
      const errs = validateAnnouncement(keep); if (errs.length) return fail(422, 'invalid_announcement', { errors: errs });
      st.announcement = keep;
    }
    if ('ai_endpoint' in b) {
      const v = String(b.ai_endpoint || '').trim().replace(/\/+$/, '');
      const errs = validateEndpointUrl(v, 'endpoints.ai'); if (errs.length) return fail(422, 'invalid_endpoint', { errors: errs });
      st.ai_endpoint = v;
    }
    await saveDraft(env, st, actor);
    await audit(env, actor, 'settings_edit', { flags: st.flags, announcement: st.announcement.enabled, ai_endpoint_set: !!st.ai_endpoint });
    return json({ ok: true, ...(await draftInfo(env)) });
  }
  if (path === '/audit' && method === 'GET') {
    const lim = Math.min(Number(url.searchParams.get('limit')) || 100, 300);
    const r = await env.DB.prepare('SELECT id, ts, actor, action, detail FROM audit_log ORDER BY id DESC LIMIT ?').bind(lim).all();
    return json({ items: r.results });
  }
  return fail(404, 'not_found');
}
