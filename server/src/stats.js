// Read-side analytics queries for the panel.
import { todayUtc } from './util.js';
import { leaves, OTHER } from './structure.js';

function rangeDays(url) { const d = Number(url.searchParams.get('days')); return [7, 30, 90].includes(d) ? d : 30; }
function since(days) { return todayUtc(-(days - 1)); }
function dayList(days) { const out = []; for (let i = days - 1; i >= 0; i--) out.push(todayUtc(-i)); return out; }

async function titles(env) {
  const r = await env.DB.prepare('SELECT id, title FROM granths_seen').all();
  return new Map(r.results.map((x) => [x.id, x.title]));
}
function folderLabels(state) {
  const m = new Map(leaves(state.structure).map((l) => [l.key, l.label]));
  m.set(OTHER, 'अन्य');
  return m;
}

export async function overview(env, url, state) {
  const days = rangeDays(url), s = since(days);
  const db = env.DB;
  const [dauR, appR, g, f, scr, kinds, users, mau, unassigned, lastApp, byGranth, byFolder, instTotal, instNew, instVer, instOs, act1, act7, act30, allTime] = await db.batch([
    db.prepare('SELECT day, SUM(dau) AS n, SUM(fg_s) AS fg_s FROM daily_app WHERE day >= ? GROUP BY day ORDER BY day').bind(s),
    db.prepare(`SELECT SUM(dau) AS dau, SUM(batches) AS batches, SUM(sessions) AS sessions, SUM(fg_s) AS fg_s, SUM(topic_opens) AS topic_opens, SUM(praman_opens) AS praman_opens,
      SUM(sync_ok) AS sync_ok, SUM(sync_fail) AS sync_fail, SUM(pdf_ok) AS pdf_ok, SUM(pdf_fail) AS pdf_fail, SUM(ai_asked) AS ai_asked, SUM(ai_answered) AS ai_answered, SUM(ai_cite) AS ai_cite
      FROM daily_app WHERE day >= ?`).bind(s),
    db.prepare('SELECT SUM(opens) AS opens, SUM(watch_s) AS watch_s FROM daily_granth WHERE day >= ?').bind(s),
    db.prepare('SELECT SUM(opens) AS opens, SUM(watch_s) AS watch_s FROM daily_folder WHERE day >= ?').bind(s),
    db.prepare('SELECT scr, SUM(watch_s) AS watch_s FROM daily_screen WHERE day >= ? GROUP BY scr ORDER BY watch_s DESC LIMIT 20').bind(s),
    db.prepare('SELECT kind, SUM(n) AS n FROM daily_kind WHERE day >= ? GROUP BY kind ORDER BY n DESC LIMIT 30').bind(s),
    db.prepare('SELECT COUNT(DISTINCT iid_hash) AS n FROM active WHERE day >= ?').bind(todayUtc(-(Math.min(days, 35) - 1))),
    db.prepare('SELECT COUNT(DISTINCT iid_hash) AS n FROM active WHERE day >= ?').bind(todayUtc(-29)),
    db.prepare("SELECT COUNT(*) AS n FROM granths_seen WHERE assigned_at IS NULL AND removed_at IS NULL AND active = 1"),
    db.prepare('SELECT app, SUM(dau) AS dau FROM daily_app WHERE day = (SELECT MAX(day) FROM daily_app WHERE day >= ?) GROUP BY app ORDER BY dau DESC').bind(s),
    db.prepare('SELECT gid, SUM(opens) AS opens, SUM(watch_s) AS watch_s FROM daily_granth WHERE day >= ? GROUP BY gid').bind(s),
    db.prepare('SELECT fkey, SUM(opens) AS opens, SUM(watch_s) AS watch_s FROM daily_folder WHERE day >= ? GROUP BY fkey').bind(s),
    db.prepare('SELECT COUNT(*) AS n, MIN(first_seen) AS first FROM installs'),
    db.prepare('SELECT first_seen AS day, COUNT(*) AS n FROM installs WHERE first_seen >= ? GROUP BY first_seen').bind(s),
    db.prepare('SELECT app_version AS app, COUNT(*) AS n FROM installs GROUP BY app_version ORDER BY n DESC LIMIT 20'),
    db.prepare('SELECT os, COUNT(*) AS n FROM installs GROUP BY os ORDER BY n DESC'),
    db.prepare('SELECT COUNT(DISTINCT iid_hash) AS n FROM active WHERE day >= ?').bind(todayUtc(0)),
    db.prepare('SELECT COUNT(DISTINCT iid_hash) AS n FROM active WHERE day >= ?').bind(todayUtc(-6)),
    db.prepare('SELECT COUNT(DISTINCT iid_hash) AS n FROM active WHERE day >= ?').bind(todayUtc(-29)),
    db.prepare('SELECT (SELECT SUM(fg_s) FROM daily_app) AS fg_s, (SELECT SUM(sessions) FROM daily_app) AS sessions, (SELECT SUM(opens) FROM daily_granth) AS granth_opens, (SELECT SUM(watch_s) FROM daily_granth) AS granth_watch_s, (SELECT SUM(watch_s) FROM daily_folder) AS folder_watch_s'),
  ]);
  const a = appR.results[0] || {};
  const nz = (v) => v || 0;
  const dm = new Map(dauR.results.map((r) => [r.day, r]));
  const dau = dayList(days).map((d) => ({ day: d, n: nz(dm.get(d)?.n), fg_s: nz(dm.get(d)?.fg_s) }));
  const tt = await titles(env), fl = folderLabels(state);
  const granths = byGranth.results.map((r) => ({ id: r.gid, title: tt.get(r.gid) || `#${r.gid}`, opens: r.opens, watch_s: r.watch_s, avg_watch_s: r.opens ? Math.round(r.watch_s / r.opens) : 0 }));
  const folders = byFolder.results.map((r) => ({ key: r.fkey, label: fl.get(r.fkey) || r.fkey, opens: r.opens, watch_s: r.watch_s }));
  const religions = {};
  for (const x of folders) { const rk = x.key.split('/')[0]; (religions[rk] ||= { key: rk, opens: 0, watch_s: 0 }); religions[rk].opens += x.opens; religions[rk].watch_s += x.watch_s; }
  const rTitle = new Map(state.structure.religions.map((r) => [r.id, r.title])); rTitle.set(OTHER, 'अन्य');
  const top = (arr, k, n = 10) => [...arr].sort((x, y) => y[k] - x[k]).filter((x) => x[k] > 0).slice(0, n);
  const im = new Map(instNew.results.map((r) => [r.day, r.n]));
  const newInstalls = dayList(days).map((d) => ({ day: d, n: im.get(d) || 0 }));
  const at = allTime.results[0] || {};
  const syncTotal = nz(a.sync_ok) + nz(a.sync_fail);
  return {
    days, since: s,
    totals: {
      users_in_range: users.results[0].n, mau_30d: mau.results[0].n, dau_today: dau[dau.length - 1].n,
      dau_avg: days ? Math.round(dau.reduce((x, y) => x + y.n, 0) / days) : 0,
      batches: nz(a.batches), sessions: nz(a.sessions), app_fg_s: nz(a.fg_s),
      granth_opens: nz(g.results[0].opens), granth_watch_s: nz(g.results[0].watch_s),
      folder_opens: nz(f.results[0].opens), folder_watch_s: nz(f.results[0].watch_s),
      topic_opens: nz(a.topic_opens), praman_opens: nz(a.praman_opens),
      total_installs: instTotal.results[0].n, first_install_day: instTotal.results[0].first || null,
      active_1d: act1.results[0].n, active_7d: act7.results[0].n, active_30d: act30.results[0].n,
      new_installs_in_range: newInstalls.reduce((x, y) => x + y.n, 0),
      total_fg_s: nz(a.fg_s), total_fg_s_all_time: nz(at.fg_s), sessions_all_time: nz(at.sessions),
      avg_fg_s_per_active_user: users.results[0].n ? Math.round(nz(a.fg_s) / users.results[0].n) : 0,
      avg_fg_s_per_active_user_day: nz(a.dau) ? Math.round(nz(a.fg_s) / a.dau) : 0,
      avg_sessions_per_active_user_day: nz(a.dau) ? +(nz(a.sessions) / a.dau).toFixed(2) : 0,
      granth_opens_all_time: nz(at.granth_opens), granth_watch_s_all_time: nz(at.granth_watch_s),
      watch_s_per_user_day: nz(a.dau) ? Math.round(nz(a.fg_s) / a.dau) : 0,
    },
    dau, new_installs: newInstalls,
    installs_by_version: instVer.results, installs_by_os: instOs.results,
    versions: Object.fromEntries(lastApp.results.map((r) => [r.app, r.dau])),
    sync: { ok: nz(a.sync_ok), fail: nz(a.sync_fail), fail_rate: syncTotal ? +(nz(a.sync_fail) / syncTotal).toFixed(4) : 0 },
    pdf: { ok: nz(a.pdf_ok), fail: nz(a.pdf_fail) },
    ai: { asked: nz(a.ai_asked), answered: nz(a.ai_answered), cite_tap: nz(a.ai_cite) },
    screens: scr.results, failure_kinds: kinds.results,
    top_granths_opens: top(granths, 'opens'), top_granths_watch: top(granths, 'watch_s'),
    top_folders: top(folders, 'opens'), top_folders_watch: top(folders, 'watch_s'), top_screens: scr.results.map((x) => ({ screen: x.scr, watch_s: x.watch_s })),
    religions: Object.values(religions).map((r) => ({ ...r, label: rTitle.get(r.key) || r.key })).sort((x, y) => y.opens - x.opens),
    new_granths_pending: unassigned.results[0].n,
  };
}

export async function granthStats(env, url) {
  const days = rangeDays(url), s = since(days);
  const [r, tt] = await Promise.all([env.DB.prepare('SELECT gid, SUM(opens) AS opens, SUM(watch_s) AS watch_s FROM daily_granth WHERE day >= ? GROUP BY gid ORDER BY opens DESC LIMIT 300').bind(s).all(), titles(env)]);
  return { days, items: r.results.map((x) => ({ id: x.gid, title: tt.get(x.gid) || `#${x.gid}`, opens: x.opens, watch_s: x.watch_s, avg_watch_s: x.opens ? Math.round(x.watch_s / x.opens) : 0 })) };
}
export async function folderStats(env, url, state) {
  const days = rangeDays(url), s = since(days), fl = folderLabels(state);
  const r = await env.DB.prepare('SELECT fkey, SUM(opens) AS opens, SUM(watch_s) AS watch_s FROM daily_folder WHERE day >= ? GROUP BY fkey ORDER BY opens DESC').bind(s).all();
  return { days, items: r.results.map((x) => ({ key: x.fkey, label: fl.get(x.fkey) || x.fkey, opens: x.opens, watch_s: x.watch_s, avg_watch_s: x.opens ? Math.round(x.watch_s / x.opens) : 0 })) };
}
export async function series(env, url) {
  const days = rangeDays(url), s = since(days);
  const kind = url.searchParams.get('kind'), id = url.searchParams.get('id') || '';
  const [table, col] = kind === 'folder' ? ['daily_folder', 'fkey'] : ['daily_granth', 'gid'];
  const r = await env.DB.prepare(`SELECT day, opens, watch_s FROM ${table} WHERE ${col} = ? AND day >= ? ORDER BY day`).bind(id, s).all();
  const m = new Map(r.results.map((x) => [x.day, x]));
  return { days, kind: kind === 'folder' ? 'folder' : 'granth', id, series: dayList(days).map((d) => ({ day: d, opens: m.get(d)?.opens || 0, watch_s: m.get(d)?.watch_s || 0 })) };
}
