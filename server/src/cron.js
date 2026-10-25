// Scheduled work: catalog diff (every 15 min) and daily prune.
import { nowIso, todayUtc, nowSec, ID_RE } from './util.js';

const UA = 'granth-admin/1.0 (anonymous read-only catalog diff; contact: admin panel owner)';

async function raiseAlert(env, kind, ref, message) {
  const open = await env.DB.prepare('SELECT id FROM alerts WHERE kind = ? AND ref IS ? AND acked_at IS NULL AND created_at > ?').bind(kind, ref, new Date(Date.now() - 6 * 3600e3).toISOString()).first();
  if (!open) await env.DB.prepare('INSERT INTO alerts (kind, ref, message, created_at) VALUES (?,?,?,?)').bind(kind, ref, String(message).slice(0, 300), nowIso()).run();
}
async function setMeta(env, k, v) { await env.DB.prepare('INSERT INTO meta (k, v) VALUES (?,?) ON CONFLICT(k) DO UPDATE SET v = excluded.v').bind(k, String(v)).run(); }

export function parseCatalog(text) {
  const j = JSON.parse(text);
  if (!j || !Array.isArray(j.data)) throw new Error('unexpected response shape');
  const items = [];
  for (const g of j.data) {
    const id = String(g.id ?? '');
    if (!ID_RE.test(id)) continue;
    items.push({
      id, title: String(g.title ?? '').trim().slice(0, 300), author: String(g.author ?? '').trim().slice(0, 200),
      cover: String(g.imagePath ?? '').slice(0, 300), position: String(g.position ?? '').slice(0, 20),
      praman_count: parseInt(g.pramanCount, 10) || 0, active: String(g.isActive ?? '1') === '0' ? 0 : 1, created_at: String(g.created_at ?? '').slice(0, 30),
    });
  }
  return items;
}

/** Fetches getGranths (read-only GET) and diffs against granths_seen. Returns a summary. */
export async function syncCatalog(env) {
  const url = env.CATALOG_URL || 'https://granth.wnmsolutions.com/api/index.php?request=getGranths';
  let items;
  try {
    const res = await fetch(url, { headers: { 'user-agent': UA, accept: 'application/json' }, signal: AbortSignal.timeout(9000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    items = parseCatalog(await res.text());
  } catch (e) {
    await setMeta(env, 'sync_last_error', `${nowIso()} ${String(e.message || e)}`.slice(0, 200));
    await raiseAlert(env, 'sync_error', 'getGranths', `Catalog fetch failed: ${String(e.message || e)}`);
    return { ok: false, error: String(e.message || e) };
  }
  const now = nowIso();
  const rows = (await env.DB.prepare('SELECT id, title, author, cover, position, praman_count, active, assigned_at, missing_runs, removed_at FROM granths_seen').all()).results;
  const known = new Map(rows.map((r) => [r.id, r]));
  const knownActive = rows.filter((r) => !r.removed_at).length;
  if (rows.length && (items.length === 0 || items.length < knownActive * 0.5)) {
    const msg = `suspicious catalog size ${items.length} (known ${knownActive}) — ignored`;
    await setMeta(env, 'sync_last_error', `${now} ${msg}`);
    await raiseAlert(env, 'sync_error', 'getGranths', msg);
    return { ok: false, error: msg };
  }
  const baseline = rows.length === 0;
  const stmts = [];
  const added = [], changed = [], removed = [];
  const seenIds = new Set();
  for (const it of items) {
    seenIds.add(it.id);
    const old = known.get(it.id);
    if (!old) {
      added.push(it.id);
      stmts.push(env.DB.prepare(`INSERT INTO granths_seen (id, title, author, cover, position, praman_count, active, created_at, first_seen, last_seen, assigned_at, missing_runs) VALUES (?,?,?,?,?,?,?,?,?,?,?,0)`)
        .bind(it.id, it.title, it.author, it.cover, it.position, it.praman_count, it.active, it.created_at, now, now, baseline ? 'baseline' : null));
    } else if (old.title !== it.title || old.author !== it.author || old.cover !== it.cover || old.position !== it.position || old.praman_count !== it.praman_count || old.active !== it.active || old.removed_at || old.missing_runs) {
      changed.push(it.id);
      stmts.push(env.DB.prepare('UPDATE granths_seen SET title=?, author=?, cover=?, position=?, praman_count=?, active=?, last_seen=?, missing_runs=0, removed_at=NULL WHERE id=?')
        .bind(it.title, it.author, it.cover, it.position, it.praman_count, it.active, now, it.id));
    }
  }
  for (const r of rows) {
    if (seenIds.has(r.id) || r.removed_at) continue;
    const runs = r.missing_runs + 1;
    if (runs >= 3) {
      removed.push(r.id);
      stmts.push(env.DB.prepare('UPDATE granths_seen SET missing_runs=?, removed_at=? WHERE id=?').bind(runs, now, r.id));
      stmts.push(env.DB.prepare('INSERT INTO alerts (kind, ref, message, created_at) VALUES (?,?,?,?)').bind('removed_granth', r.id, `Granth ${r.id} (${r.title}) is no longer in Ashok's catalog`, now));
    } else stmts.push(env.DB.prepare('UPDATE granths_seen SET missing_runs=? WHERE id=?').bind(runs, r.id));
  }
  for (let i = 0; i < stmts.length; i += 50) await env.DB.batch(stmts.slice(i, i + 50));
  await setMeta(env, 'sync_last_ok', now);
  await setMeta(env, 'sync_last_count', items.length);
  return { ok: true, count: items.length, baseline, added, changed: changed.length, removed };
}

export async function dailyPrune(env) {
  const day35 = todayUtc(-35), day4 = todayUtc(-4), day400 = todayUtc(-400), now = nowSec();
  await env.DB.batch([
    env.DB.prepare('DELETE FROM active WHERE day < ?').bind(day35),
    env.DB.prepare('DELETE FROM installs WHERE last_seen < ?').bind(todayUtc(-800)),
    env.DB.prepare('DELETE FROM batch_seen WHERE day < ?').bind(day4),
    env.DB.prepare('DELETE FROM daily_granth WHERE day < ?').bind(day400),
    env.DB.prepare('DELETE FROM daily_folder WHERE day < ?').bind(day400),
    env.DB.prepare('DELETE FROM daily_screen WHERE day < ?').bind(day400),
    env.DB.prepare('DELETE FROM daily_app WHERE day < ?').bind(day400),
    env.DB.prepare('DELETE FROM daily_kind WHERE day < ?').bind(day400),
    env.DB.prepare('DELETE FROM sessions WHERE expires_at < ?').bind(now),
    env.DB.prepare('DELETE FROM rl WHERE expires_at < ?').bind(now),
    env.DB.prepare("DELETE FROM alerts WHERE acked_at IS NOT NULL AND acked_at < ?").bind(new Date(Date.now() - 90 * 864e5).toISOString()),
    env.DB.prepare("DELETE FROM audit_log WHERE ts < ?").bind(new Date(Date.now() - 400 * 864e5).toISOString()),
  ]);
  await setMeta(env, 'prune_last', nowIso());
}

export async function scheduled(event, env) {
  if (event.cron === '30 21 * * *') return dailyPrune(env);
  return syncCatalog(env);
}
