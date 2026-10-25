/* Granth admin SPA — vanilla JS, no build step. All text is inserted with textContent (never innerHTML). */
(() => {
'use strict';
const API = '/admin/api';
const S = { me: null, route: 'dashboard', range: 30, cache: {}, tmp: {} };
const $app = document.getElementById('app');

// ---------- tiny DOM helper ----------
function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  if (attrs) for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'style') el.style.cssText = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'value') el.value = v;
    else if (k === 'checked' || k === 'disabled' || k === 'selected') el[k] = !!v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of kids.flat(Infinity)) { if (c == null || c === false) continue; el.append(c.nodeType ? c : document.createTextNode(String(c))); }
  return el;
}
const ICONS = {
  home: '<rect width="7" height="9" x="3" y="3" rx="1"/><rect width="7" height="5" x="14" y="3" rx="1"/><rect width="7" height="9" x="14" y="12" rx="1"/><rect width="7" height="5" x="3" y="16" rx="1"/>',
  library: '<path d="m16 6 4 14"/><path d="M12 6v14"/><path d="M8 8v12"/><path d="M4 4v16"/>',
  folder: '<path d="m6 14 1.5-2.9A2 2 0 0 1 9.24 10H20a2 2 0 0 1 1.94 2.5l-1.54 6a2 2 0 0 1-1.95 1.5H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H18a2 2 0 0 1 2 2v2"/>',
  inbox: '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
  menu: '<path d="M4 12h16"/><path d="M4 18h16"/><path d="M4 6h16"/>',
  history: '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/>',
  chart: '<path d="M3 3v16a2 2 0 0 0 2 2h16"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
  settings: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
  refresh: '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>',
  eye: '<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  eyeoff: '<path d="M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49"/><path d="M14.084 14.158a3 3 0 0 1-4.242-4.242"/><path d="M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143"/><path d="m2 2 20 20"/>',
  trash: '<path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/>',
  edit: '<path d="M12 20h9"/><path d="M16.376 3.622a1 1 0 0 1 3.002 3.002L7.368 18.635a2 2 0 0 1-.855.506l-2.872.838a.5.5 0 0 1-.62-.62l.838-2.872a2 2 0 0 1 .506-.854z"/>',
  x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
  down: '<path d="m6 9 6 6 6-6"/>', right: '<path d="m9 18 6-6-6-6"/>',
  up2: '<path d="m5 12 7-7 7 7"/><path d="M12 19V5"/>', down2: '<path d="M12 5v14"/><path d="m19 12-7 7-7-7"/>',
  plus: '<path d="M5 12h14"/><path d="M12 5v14"/>', foldplus: '<path d="M12 10v6"/><path d="M9 13h6"/><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
  search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>', check: '<path d="M20 6 9 17l-5-5"/>',
  upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/>',
  logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/>',
  clock: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  book: '<path d="M12 7v14"/><path d="M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z"/>',
  sparkle: '<path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/>',
  alert: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
};
function ic(name) {
  const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  s.setAttribute('viewBox', '0 0 24 24'); s.setAttribute('class', 'ic'); s.setAttribute('aria-hidden', 'true');
  const doc = new DOMParser().parseFromString('<svg xmlns="http://www.w3.org/2000/svg">' + (ICONS[name] || '') + '</svg>', 'image/svg+xml');
  for (const n of [...doc.documentElement.childNodes]) s.appendChild(document.importNode(n, true));
  return s;
}
const svgEl = (tag, attrs) => { const e = document.createElementNS('http://www.w3.org/2000/svg', tag); for (const [k, v] of Object.entries(attrs || {})) e.setAttribute(k, v); return e; };

// ---------- formatting ----------
const nf = new Intl.NumberFormat('en-IN');
const fmtN = (n) => nf.format(Math.round(n || 0));
function fmtDur(s) {
  s = Math.round(s || 0);
  if (s < 60) return s + ' से';
  const m = Math.round(s / 60); if (m < 60) return m + ' मि';
  const hh = Math.floor(s / 3600), mm = Math.round((s % 3600) / 60);
  if (hh < 100) return hh + ' घं' + (mm ? ' ' + mm + ' मि' : '');
  return fmtN(hh) + ' घं';
}
function fmtTime(iso) {
  if (!iso) return '—';
  const d = new Date(String(iso).includes('T') || String(iso).endsWith('Z') ? iso : String(iso).replace(' ', 'T') + 'Z');
  if (isNaN(d)) return String(iso);
  return d.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: true }) + ' IST';
}
const pct = (x) => (x * 100).toFixed(1).replace(/\.0$/, '') + '%';

// ---------- API ----------
class ApiError extends Error { constructor(status, body) { super((body && body.error) || ('http ' + status)); this.status = status; this.body = body || {}; } }
async function api(method, path, body) {
  const headers = {};
  if (body !== undefined) headers['content-type'] = 'application/json';
  if (method !== 'GET' && S.me) headers['x-admin-csrf'] = S.me.csrf;
  let res;
  try { res = await fetch(API + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), credentials: 'same-origin', cache: 'no-store' }); }
  catch { throw new ApiError(0, { error: 'network' }); }
  let data = null; try { data = await res.json(); } catch { /* 204 etc. */ }
  if (res.status === 401 && path !== '/login' && path !== '/password') { S.me = null; renderLogin(); throw new ApiError(401, data); }
  if (!res.ok) throw new ApiError(res.status, data);
  return data;
}
const get = (p) => api('GET', p), post = (p, b) => api('POST', p, b || {}), put = (p, b) => api('PUT', p, b);
function errText(e) {
  const b = e.body || {};
  if (b.errors && b.errors.length) return b.errors.slice(0, 3).join(' · ');
  const m = { forbidden: 'यह काम सिर्फ़ owner कर सकता है', username_taken: 'यह username पहले से है', cannot_modify_self: 'आप ख़ुद को नहीं बदल/हटा सकते', last_owner: 'कम से कम एक चालू owner ज़रूरी है', weak_password: 'पासवर्ड कमज़ोर है (10+ अक्षर)', bad_username: 'username 3–32 अक्षर: a-z 0-9 . _ -', invalid_contacts: 'जानकारी जाँच में फेल', network: 'नेटवर्क दिक्कत', csrf: 'सुरक्षा टोकन पुराना है — पेज रीफ़्रेश करें', unknown_leaf: 'यह फ़ोल्डर मौजूद नहीं है', too_soon: 'थोड़ा रुकिए, फिर कोशिश करें', no_changes: 'प्रकाशित करने लायक बदलाव नहीं हैं', hide_too_many: 'आधे से ज़्यादा ग्रंथ छिपाने के लिए "force" ज़रूरी है', invalid_config: 'कॉन्फ़िग जाँच में फेल' };
  return m[b.error] || b.message || b.error || ('त्रुटि ' + e.status);
}
let toastT;
function toast(msg, bad) {
  document.querySelectorAll('.toast').forEach((n) => n.remove());
  const t = h('div', { class: 'toast' + (bad ? ' bad' : ''), role: 'status' }, msg); document.body.append(t);
  clearTimeout(toastT); toastT = setTimeout(() => t.remove(), bad ? 6000 : 2600);
}
const fail = (e) => { if (e.status !== 401) toast(errText(e), true); };
function setBusy(btn, on) { if (btn) btn.disabled = !!on; }

// ---------- modal ----------
function modal(title, content, actions) {
  const close = () => scrim.remove();
  const scrim = h('div', { class: 'scrim', onclick: (e) => { if (e.target === scrim) close(); } },
    h('div', { class: 'sheet', role: 'dialog', 'aria-modal': 'true' }, h('h3', null, title), content, h('div', { class: 'row', style: 'margin-top:16px;justify-content:flex-end' }, (actions || []).map((a) => h('button', { class: 'btn ' + (a.cls || ''), onclick: async (ev) => { if (a.fn) { const r = await a.fn(ev.currentTarget, close); if (r === false) return; } if (!a.keep) close(); } }, a.icon ? ic(a.icon) : null, a.label)))));
  document.body.append(scrim); return close;
}
const confirmBox = (title, msg, okLabel, cls) => new Promise((res) => { let done = false; const c = modal(title, h('p', null, msg), [{ label: 'रद्द करें', fn: () => { done = true; res(false); } }, { label: okLabel, cls: cls || 'primary', fn: () => { done = true; res(true); } }]); });

// ---------- charts ----------
function barChart(points, key, color) {
  const W = 320, H = 130, pad = 18, n = points.length; if (!n) return h('div', { class: 'empty' }, 'डेटा नहीं');
  const max = Math.max(1, ...points.map((p) => p[key])); const bw = (W - pad) / n;
  const s = svgEl('svg', { viewBox: `0 0 ${W} ${H + 16}`, class: 'chart', role: 'img' });
  s.append(svgEl('line', { x1: pad, x2: W, y1: H, y2: H, class: 'gl' }), svgEl('line', { x1: pad, x2: W, y1: 6, y2: 6, class: 'gl' }));
  const t = svgEl('text', { x: 0, y: 12, class: 'ax' }); t.textContent = key === 'watch_s' ? fmtDur(max) : fmtN(max); s.append(t);
  points.forEach((p, i) => {
    const bh = Math.max(p[key] > 0 ? 2 : 0, (p[key] / max) * (H - 10));
    const r = svgEl('rect', { x: pad + i * bw + bw * 0.15, y: H - bh, width: Math.max(1, bw * 0.7), height: bh, rx: 2, class: color || 'bar' });
    const ti = svgEl('title'); ti.textContent = `${p.day}: ${key === 'watch_s' ? fmtDur(p[key]) : fmtN(p[key])}`; r.append(ti); s.append(r);
  });
  const l1 = svgEl('text', { x: pad, y: H + 13, class: 'ax' }); l1.textContent = points[0].day.slice(5);
  const l2 = svgEl('text', { x: W, y: H + 13, class: 'ax', 'text-anchor': 'end' }); l2.textContent = points[n - 1].day.slice(5); s.append(l1, l2);
  return s;
}
function barList(items, valKey, fmt, wcls, onTap) {
  if (!items || !items.length) return h('div', { class: 'empty' }, 'अभी कोई डेटा नहीं');
  const max = Math.max(1, ...items.map((i) => i[valKey]));
  return h('div', { class: 'bars ' + (wcls || '') }, items.map((i) => h('div', { class: 'b', style: onTap ? 'cursor:pointer' : null, onclick: onTap ? () => onTap(i) : null }, h('div', { class: 't' }, i.title || i.label), h('div', { class: 'n' }, fmt(i[valKey])), h('div', { class: 'm' }, h('i', { style: `width:${Math.max(2, (i[valKey] / max) * 100)}%` })))));
}

// ---------- layout ----------
const NAV = [['dashboard', 'डैशबोर्ड', 'home'], ['granths', 'ग्रंथ', 'library'], ['folders', 'फ़ोल्डर', 'folder'], ['inbox', 'नए ग्रंथ', 'inbox']];
const MORE = [['history', 'इतिहास / Rollback', 'history'], ['contacts', 'विशेष जानकार', 'users'], ['analytics', 'एनालिटिक्स', 'chart'], ['settings', 'सेटिंग्स', 'settings']];
function badgeN() { return S.tmp.inboxCount > 0 ? h('span', { class: 'badge' }, S.tmp.inboxCount) : null; }
function shell(content) {
  const on = S.route;
  const tabs = [...NAV, ...MORE].map(([k, l, i]) => h('a', { class: 'tab' + (on === k ? ' on' : ''), href: '#/' + k }, ic(i), l, k === 'inbox' ? badgeN() : null));
  const bn = NAV.map(([k, l, i]) => h('a', { class: on === k ? 'on' : '', href: '#/' + k }, ic(i), l, k === 'inbox' ? badgeN() : null));
  const moreOn = MORE.some((m) => m[0] === on);
  bn.push(h('button', { class: moreOn ? 'on' : '', onclick: openMore }, ic('menu'), 'और'));
  return h('div', null,
    h('header', { class: 'top' },
      h('div', { class: 'top-in' }, h('div', { class: 'logo', style: 'background-image:url(logo-192.png)' }), h('div', { class: 'brand' }, 'ग्रंथ एडमिन', h('small', null, 'v' + (S.me ? S.me.version : '?') + ' प्रकाशित')), h('div', { class: 'grow1' }),
        h('button', { class: 'btn sm icon', title: 'लॉग आउट', 'aria-label': 'लॉग आउट', style: 'background:transparent;color:#fff;border-color:rgba(255,255,255,.5)', onclick: doLogout }, ic('logout'))),
      h('nav', { class: 'tabs' }, tabs)),
    h('main', null, content), draftBar(), h('nav', { class: 'bnav' }, bn));
}
function openMore() {
  const c = modal('और', h('div', { class: 'menu' }, MORE.map(([k, l, i]) => h('a', { href: '#/' + k, onclick: () => document.querySelector('.scrim')?.remove() }, ic(i), l)), h('button', { class: 'm', onclick: () => { document.querySelector('.scrim')?.remove(); doLogout(); } }, ic('logout'), 'लॉग आउट')), [{ label: 'बंद करें' }]);
}
async function doLogout() { try { await post('/logout'); } catch { /* ignore */ } S.me = null; renderLogin(); }
function draftBar() {
  if (!S.me || !S.me.has_draft) return h('span');
  return h('div', { class: 'bar-pop', role: 'region', 'aria-label': 'unsaved changes' },
    h('div', { style: 'flex:1;min-width:140px' }, h('b', null, 'बिना प्रकाशित बदलाव (draft)'), h('div', { style: 'font-size:12.5px;opacity:.85' }, 'ऐप में तभी जाएँगे जब "प्रकाशित करें" दबाएँगे')),
    h('button', { class: 'btn sm', style: 'background:transparent;color:#fff', onclick: previewDiff }, ic('eye'), 'अंतर देखें'),
    h('button', { class: 'btn sm saffron', onclick: previewDiff }, ic('upload'), 'प्रकाशित करें'));
}
async function refreshMe() { S.me = await get('/me'); try { const a = await get('/alerts'); S.tmp.inboxCount = a.count; S.tmp.alerts = a; } catch (e) { if (e.status === 401) throw e; } }

// ---------- diff / publish ----------
function diffView(diff) {
  if (!diff) return h('div', { class: 'empty' }, 'तुलना उपलब्ध नहीं');
  const fieldTxt = (f) => `${f.field}: ${JSON.stringify(f.from)} → ${JSON.stringify(f.to)}`;
  const parts = [];
  if (diff.warnings && diff.warnings.length) parts.push(...diff.warnings.map((w) => h('div', { class: 'note warn' }, ic('alert'), ' ', w)));
  if (!diff.changed) parts.push(h('div', { class: 'empty' }, 'कोई बदलाव नहीं'));
  if (diff.granths.length) parts.push(h('div', { class: 'sec' }, h('b', null, `ग्रंथ (${diff.granths.length})`), h('ul', null, diff.granths.slice(0, 80).map((g) => h('li', null, `#${g.id} ${g.title || ''} — `, g.folder ? [h('del', null, g.folder.from), ' → ', h('ins', null, g.folder.to), ' '] : null, g.hidden ? h('ins', null, g.hidden.to ? 'छिपाया' : 'दिखाया') : null)), diff.granths.length > 80 ? h('li', null, `… और ${diff.granths.length - 80}`) : null)));
  if (diff.folders.length) parts.push(h('div', { class: 'sec' }, h('b', null, `फ़ोल्डर (${diff.folders.length})`), h('ul', null, diff.folders.map((f) => h('li', null, f.change === 'added' ? h('ins', null, 'नया: ') : f.change === 'removed' ? h('del', null, 'हटाया: ') : 'बदला: ', f.title, f.fields ? h('div', { class: 'sub' }, f.fields.map(fieldTxt).join(' · ')) : null)))));
  if ((diff.contacts || []).length) parts.push(h('div', { class: 'sec' }, h('b', null, `विशेष जानकार (${diff.contacts.length})`), h('ul', null, diff.contacts.map((c) => h('li', null, c.change === 'added' ? h('ins', null, 'नया: ') : c.change === 'removed' ? h('del', null, 'हटाया: ') : 'बदला: ', c.name, c.fields ? h('div', { class: 'sub' }, c.fields.map((f) => f.field === 'phone' ? 'phone बदला' : fieldTxt(f)).join(' · ')) : null)))));
  if (diff.settings.length) parts.push(h('div', { class: 'sec' }, h('b', null, 'सेटिंग्स'), h('ul', null, diff.settings.map((f) => h('li', null, fieldTxt(f))))));
  return h('div', { class: 'diff' }, parts);
}
async function previewDiff() {
  let d; try { d = await get('/draft'); } catch (e) { return fail(e); }
  const note = h('input', { type: 'text', placeholder: 'नोट (वैकल्पिक) — क्या बदला?', maxlength: 200 });
  const needForce = d.diff.warnings && d.diff.warnings.length > 0;
  const force = h('input', { type: 'checkbox', class: 'cb' });
  const body = h('div', null, h('div', { class: 'sub', style: 'margin-bottom:8px' }, `v${d.base_version} → v${d.next_version}`), diffView(d.diff),
    needForce ? h('label', { class: 'row', style: 'margin-top:12px' }, force, ' मैं जानता हूँ — फिर भी प्रकाशित करें (force)') : null, h('label', { class: 'f' }, 'नोट'), note);
  modal('प्रकाशित करने से पहले', body, [
    { label: 'Draft हटाएँ', cls: 'danger', icon: 'trash', fn: async () => { if (!(await confirmBox('Draft हटाएँ?', 'सारे बिना प्रकाशित बदलाव मिट जाएँगे।', 'हाँ, हटाएँ', 'danger'))) return false; try { await post('/draft/discard'); toast('Draft हटा दिया'); await refreshAndRender(); } catch (e) { fail(e); } } },
    { label: 'बंद करें' },
    { label: 'प्रकाशित करें', cls: 'primary', icon: 'upload', keep: true, fn: async (btn, close) => {
      setBusy(btn, true);
      try { const r = await post('/publish', { note: note.value.trim() || undefined, force: force.checked }); close(); toast('v' + r.version + ' प्रकाशित हुआ ✓ — ऐप अगले sync में ले लेगा'); await refreshAndRender(); }
      catch (e) { setBusy(btn, false); fail(e); }
      return false; } },
  ]);
}
async function refreshAndRender() { try { await refreshMe(); } catch (e) { return; } S.cache = {}; render(); }

// ---------- router ----------
const ROUTES = {};
function parseHash() { const m = location.hash.replace(/^#\/?/, '').split('?'); return { name: m[0] || 'dashboard', q: new URLSearchParams(m[1] || '') }; }
async function render() {
  if (!S.me) return renderLogin();
  const { name, q } = parseHash(); S.route = ROUTES[name] ? name : 'dashboard'; S.q = q;
  const holder = h('div', { class: 'empty' }, h('span', { class: 'spin' }));
  $app.replaceChildren(shell(holder));
  try { const view = await ROUTES[S.route](); holder.replaceWith(view); }
  catch (e) { if (e.status !== 401) holder.replaceChildren(h('div', { class: 'note bad' }, 'लोड नहीं हुआ: ' + errText(e), h('div', null, h('button', { class: 'btn sm', style: 'margin-top:8px', onclick: render }, 'फिर कोशिश करें')))); }
}
window.addEventListener('hashchange', () => { if (S.me) render(); });

// ---------- login ----------
function renderLogin() {
  document.querySelectorAll('.scrim,.toast').forEach((n) => n.remove());
  const u = h('input', { type: 'text', value: 'goutam', autocomplete: 'username', autocapitalize: 'none', spellcheck: 'false' });
  const p = h('input', { type: 'password', autocomplete: 'current-password' });
  const err = h('div', { class: 'err', role: 'alert' });
  const btn = h('button', { class: 'btn primary', type: 'submit', style: 'width:100%;margin-top:16px' }, 'लॉग इन');
  const form = h('form', { onsubmit: async (e) => {
    e.preventDefault(); err.textContent = ''; setBusy(btn, true);
    try {
      await post('/login', { username: u.value.trim(), password: p.value });
      p.value = ''; await refreshMe(); if (!location.hash) location.hash = '#/dashboard'; render();
    } catch (ex) {
      setBusy(btn, false);
      if (ex.status === 429) { const s = Number(ex.body.retry_after) || 600; err.textContent = `बहुत ज़्यादा कोशिशें — ${Math.ceil(s / 60)} मिनट बाद फिर कोशिश करें`; }
      else if (ex.status === 401) err.textContent = 'यूज़रनेम या पासवर्ड ग़लत है';
      else err.textContent = errText(ex);
    }
  } }, h('label', { class: 'f' }, 'यूज़रनेम'), u, h('label', { class: 'f' }, 'पासवर्ड'), p, btn, err);
  $app.replaceChildren(h('div', { class: 'login' }, h('div', { class: 'card' }, h('div', { class: 'logo', style: 'background-image:url(logo-192.png)' }), h('h1', null, 'ग्रंथ एडमिन'), h('p', { class: 'sub', style: 'text-align:center;margin:4px 0 10px' }, 'केवल एडमिन के लिए'), form)));
}

// ---------- dashboard ----------
function rangeChips(onPick) {
  return h('div', { class: 'range' }, [7, 30, 90].map((d) => h('button', { class: 'chip' + (S.range === d ? ' on' : ''), onclick: () => { S.range = d; onPick(); } }, d + ' दिन')));
}
function stat(icon, tone, label, value, sub, cls) { return h('div', { class: 'card stat ' + (cls || '') }, h('div', { class: 'k' }, h('span', { class: 'ibox ' + tone }, ic(icon)), label), h('div', { class: 'v' }, value), sub ? h('div', { class: 's' }, sub) : null); }
ROUTES.dashboard = async () => {
  const o = await get('/stats/overview?days=' + S.range);
  const t = o.totals;
  const root = h('div', null);
  root.append(h('div', { class: 'row space' }, h('div', { class: 'page-title' }, 'डैशबोर्ड'), rangeChips(render)));
  const newN = o.new_granths_pending;
  const cards = [];
  if (newN > 0) cards.push(h('a', { class: 'card link alertcard wide', href: '#/inbox' }, h('div', { class: 'row space' }, h('div', { class: 'row' }, h('span', { class: 'ibox saffron' }, ic('sparkle')), h('b', { style: 'font-size:17px' }, `${fmtN(newN)} नए ग्रंथ को फ़ोल्डर चाहिए`)), h('span', { class: 'btn sm primary' }, 'देखें', ic('right')))));
  cards.push(
    stat('users', 'maroon', 'कुल इंस्टॉल (अब तक)', fmtN(t.total_installs), t.first_install_day ? 'पहला: ' + t.first_install_day : 'अभी कोई नहीं'),
    stat('users', 'saffron', 'आज सक्रिय', fmtN(t.active_1d), `7 दिन: ${fmtN(t.active_7d)} · 30 दिन: ${fmtN(t.active_30d)}`),
    stat('plus', 'gold', 'नए इंस्टॉल', fmtN(t.new_installs_in_range), `पिछले ${o.days} दिन में`),
    stat('book', 'saffron', 'ग्रंथ खुले', fmtN(t.granth_opens), `कुल (अब तक) ${fmtN(t.granth_opens_all_time)} · ${fmtN(t.topic_opens)} विषय · ${fmtN(t.praman_opens)} प्रमाण`),
    stat('clock', 'gold', 'ऐप पर कुल समय', fmtDur(t.total_fg_s), `अब तक कुल: ${fmtDur(t.total_fg_s_all_time)}`),
    stat('clock', 'maroon', 'औसत समय / यूज़र', fmtDur(t.avg_fg_s_per_active_user), `प्रति सक्रिय यूज़र/दिन ≈ ${fmtDur(t.avg_fg_s_per_active_user_day)}`),
    stat('home', 'saffron', 'सेशन', fmtN(t.sessions), `अब तक ${fmtN(t.sessions_all_time)} · ${t.avg_sessions_per_active_user_day}/यूज़र/दिन`),
    stat('eye', 'maroon', 'ग्रंथ देखने का समय', fmtDur(t.granth_watch_s), `फ़ोल्डर में: ${fmtDur(t.folder_watch_s)}`));
  const dauCard = h('div', { class: 'card wide w2' }, h('h3', null, ic('users'), 'रोज़ के सक्रिय यूज़र'), barChart(o.dau, 'n'));
  const fgCard = h('div', { class: 'card wide w2' }, h('h3', null, ic('clock'), 'रोज़ का कुल समय'), barChart(o.dau, 'fg_s', 'bar2'));
  cards.push(dauCard, fgCard, h('div', { class: 'card wide w2' }, h('h3', null, ic('plus'), 'रोज़ के नए इंस्टॉल'), barChart(o.new_installs, 'n')),
    h('div', { class: 'card wide w2' }, h('h3', null, ic('settings'), 'ऐप वर्ज़न के हिसाब से इंस्टॉल'), o.installs_by_version.length ? barList(o.installs_by_version.map((v) => ({ label: v.app, n: v.n })), 'n', fmtN) : h('div', { class: 'empty' }, 'अभी कोई डेटा नहीं')));
  const goA = (kind) => () => { location.hash = '#/analytics?kind=' + kind; };
  cards.push(
    h('div', { class: 'card wide w2' }, h('h3', null, ic('library'), 'टॉप ग्रंथ (ओपन)'), barList(o.top_granths_opens.slice(0, 8), 'opens', fmtN, '', (i) => { location.hash = '#/analytics?kind=granth&id=' + i.id; })),
    h('div', { class: 'card wide w2' }, h('h3', null, ic('clock'), 'टॉप ग्रंथ (देखने का समय)'), barList(o.top_granths_watch.slice(0, 8), 'watch_s', fmtDur, 'w', (i) => { location.hash = '#/analytics?kind=granth&id=' + i.id; })),
    h('div', { class: 'card wide w2' }, h('h3', null, ic('folder'), 'टॉप फ़ोल्डर (ओपन)'), barList(o.top_folders.slice(0, 8), 'opens', fmtN, '', (i) => { location.hash = '#/analytics?kind=folder&id=' + encodeURIComponent(i.key); })),
    h('div', { class: 'card wide w2' }, h('h3', null, ic('folder'), 'फ़ोल्डर में समय'), barList(o.top_folders_watch.slice(0, 8), 'watch_s', fmtDur, 'w', (i) => { location.hash = '#/analytics?kind=folder&id=' + encodeURIComponent(i.key); })),
    h('div', { class: 'card wide w2' }, h('h3', null, ic('folder'), 'धर्म-वार ओपन'), barList(o.religions.slice(0, 8), 'opens', fmtN)),
    h('div', { class: 'card wide w2' }, h('h3', null, ic('home'), 'स्क्रीन-वार समय'), barList(o.top_screens.map((s) => ({ label: s.screen, watch_s: s.watch_s })).slice(0, 8), 'watch_s', fmtDur, 'w')),
    stat('refresh', o.sync.fail_rate > 0.1 ? 'maroon' : 'gold', 'Sync फेल %', pct(o.sync.fail_rate), `${fmtN(o.sync.ok)} ठीक · ${fmtN(o.sync.fail)} फेल`),
    stat('book', o.pdf.fail ? 'maroon' : 'gold', 'PDF फेल', fmtN(o.pdf.fail), `${fmtN(o.pdf.ok)} सफल`),
    h('div', { class: 'card wide w2' }, h('h3', null, ic('settings'), 'ऐप वर्ज़न (आख़िरी दिन)'), Object.keys(o.versions).length ? barList(Object.entries(o.versions).map(([k, v]) => ({ label: k, n: v })), 'n', fmtN) : h('div', { class: 'empty' }, 'अभी कोई डेटा नहीं')),
    o.ai.asked ? stat('sparkle', 'saffron', 'AI सवाल', fmtN(o.ai.asked), `${fmtN(o.ai.answered)} जवाब · ${fmtN(o.ai.cite_tap)} स्रोत-टैप`) : null);
  if (o.failure_kinds.length) cards.push(h('div', { class: 'card wide' }, h('h3', null, ic('alert'), 'फेल के प्रकार'), h('div', { class: 'row' }, o.failure_kinds.map((k) => h('span', { class: 'pill bad' }, `${k.kind}: ${fmtN(k.n)}`)))));
  root.append(h('div', { class: 'grid' }, cards));
  if (!t.batches) root.append(h('div', { class: 'note', style: 'margin-top:12px' }, 'अभी तक ऐप से कोई एनालिटिक्स नहीं आया। ऐप का नया वर्ज़न /events पर भेजना शुरू करेगा तो यहाँ दिखेगा।'));
  return root;
};

// ---------- granths ----------
const SORTS = [['number', 'क्रम (#1 से)'], ['id', 'ID'], ['title', 'नाम (अ–ह)'], ['opens', 'ओपन (7d)'], ['watch', 'देखने का समय (7d)'], ['praman', 'प्रमाण संख्या'], ['newest', 'नया पहले']];
const SORT_DEFAULT_ORDER = { number: 'asc', id: 'asc', title: 'asc', opens: 'desc', watch: 'desc', praman: 'desc', newest: 'desc' };
const FILTERS = [['new', 'नया'], ['other', 'अन्य'], ['hidden', 'छिपा'], ['nopraman', 'बिना प्रमाण'], ['changed', 'बदला हुआ']];
ROUTES.granths = async () => {
  const st = S.tmp.gr || (S.tmp.gr = { q: '', f: new Set(), sel: new Set(), limit: 60 });
  st.sort = st.sort || 'number'; st.order = st.order || 'asc'; // default: catalog number (position) ascending, #1 first
  const data = await get(`/granths?sort=${st.sort}&order=${st.order}`);
  const byId = new Map(data.items.map((g) => [g.id, g]));
  const root = h('div', null);
  const listEl = h('div', { class: 'glist' });
  const countEl = h('span', { class: 'sub' });
  const bulkEl = h('div');
  const moreEl = h('div', { style: 'text-align:center;margin:12px' });

  const leafSelect = (value, onchange, includeDefault) => {
    const sel = h('select', { 'aria-label': 'फ़ोल्डर', onchange: (e) => onchange(e.target.value, e.target) });
    if (includeDefault) sel.append(h('option', { value: '' }, 'फ़ोल्डर चुनें…'));
    const byRel = new Map();
    for (const l of data.leaves) { if (!byRel.has(l.religion_id)) byRel.set(l.religion_id, { title: l.religion, items: [] }); byRel.get(l.religion_id).items.push(l); }
    for (const [, r] of byRel) sel.append(h('optgroup', { label: r.title }, r.items.map((l) => h('option', { value: l.key, selected: l.key === value }, l.group + (l.visible ? '' : ' (छिपा फ़ोल्डर)')))));
    if (value) sel.value = value;
    return sel;
  };
  const match = (g) => {
    if (st.q) { const q = st.q.toLowerCase(); if (!(g.title.toLowerCase().includes(q) || (g.author || '').toLowerCase().includes(q) || g.id === q || String(g.position) === q)) return false; }
    for (const f of st.f) {
      if (f === 'new' && !g.is_new) return false; if (f === 'other' && g.leaf !== 'other') return false;
      if (f === 'hidden' && !g.hidden) return false; if (f === 'nopraman' && !g.no_praman) return false;
      if (f === 'changed' && !(g.source === 'override' || g.hidden)) return false;
    }
    return true;
  };
  const rowFor = (g) => {
    const cb = h('input', { type: 'checkbox', class: 'cb', 'aria-label': 'चुनें', checked: st.sel.has(g.id), onchange: (e) => { e.target.checked ? st.sel.add(g.id) : st.sel.delete(g.id); drawBulk(); } });
    const sw = h('button', { class: 'sw' + (g.hidden ? '' : ' on'), role: 'switch', 'aria-checked': String(!g.hidden), 'aria-label': 'ऐप में दिखाएँ', title: g.hidden ? 'छिपा है' : 'दिख रहा है', onclick: async () => {
      const to = !g.hidden; try { await put('/granths/' + g.id, { hidden: to }); g.hidden = to; S.me.has_draft = true; drawList(); drawDraftOnly(); } catch (e) { fail(e); } } });
    const sel = leafSelect(g.leaf, async (val, el) => {
      try { await put('/granths/' + g.id, { leaf: val === g.default_leaf ? null : val }); g.leaf = val; g.source = val === g.default_leaf ? 'auto' : 'override'; g.is_new = false; S.me.has_draft = true; drawList(); drawDraftOnly(); toast('फ़ोल्डर बदला (draft)'); }
      catch (e) { el.value = g.leaf; fail(e); } });
    return h('div', { class: 'grow' + (g.hidden ? ' hid' : '') + (g.source === 'override' ? ' chg' : '') },
      h('div', { class: 'c-cb' }, cb),
      h('div', { class: 'cv', style: g.cover ? `background-image:url("${g.cover}")` : null }),
      h('div', { class: 'c-tt' }, h('div', { class: 'tt' }, g.title), h('div', { class: 'au' }, `क्र. ${g.position ?? '—'} · ID ${g.id}`, g.author ? ' · ' + g.author : ''), h('div', { class: 'row', style: 'gap:4px;margin-top:3px' }, g.is_new ? h('span', { class: 'pill new' }, 'नया') : null, g.no_praman ? h('span', { class: 'pill' }, 'बिना प्रमाण') : null, g.leaf === 'other' ? h('span', { class: 'pill' }, 'अन्य') : null, g.hidden ? h('span', { class: 'pill hid' }, 'छिपा') : null)),
      h('div', { class: 'c-fo' }, sel), h('div', { class: 'c-sw' }, sw), h('div', { class: 'op' }, fmtN(g.opens_7d), h('div', null, '7d ओपन')));
  };
  const filtered = () => data.items.filter(match);
  function drawList() {
    const f = filtered(); countEl.textContent = `${f.length} / ${data.items.length} ग्रंथ`;
    listEl.replaceChildren(...f.slice(0, st.limit).map(rowFor));
    if (!f.length) listEl.append(h('div', { class: 'empty' }, 'कोई ग्रंथ नहीं मिला'));
    moreEl.replaceChildren(f.length > st.limit ? h('button', { class: 'btn', onclick: () => { st.limit += 60; drawList(); } }, `और दिखाएँ (${f.length - st.limit})`) : '');
    drawBulk();
  }
  function drawDraftOnly() { document.querySelectorAll('.bar-pop:not(.bulkbar)').forEach((n) => n.remove()); $app.firstElementChild.append(draftBar()); }
  function drawBulk() {
    const n = st.sel.size;
    if (!n) { bulkEl.replaceChildren(); return; }
    const ids = [...st.sel];
    const bulk = async (payload, msg) => { try { const r = await post('/granths/bulk', { ids, ...payload }); S.me.has_draft = true; await refreshAndRender(); toast(`${r.changed} ग्रंथ: ${msg} (draft)`); } catch (e) { fail(e); } };
    const sel = leafSelect('', async (val) => { if (val) await bulk({ leaf: val }, 'फ़ोल्डर बदला'); }, true);
    bulkEl.replaceChildren(h('div', { class: 'bar-pop bulkbar' }, h('b', null, n + ' चुने'), sel,
      h('button', { class: 'btn sm', style: 'background:transparent;color:#fff', onclick: () => bulk({ hidden: true }, 'छिपाए') }, ic('eyeoff'), 'छिपाएँ'),
      h('button', { class: 'btn sm', style: 'background:transparent;color:#fff', onclick: () => bulk({ hidden: false }, 'दिखाए') }, ic('eye'), 'दिखाएँ'),
      h('button', { class: 'btn sm icon', 'aria-label': 'चयन हटाएँ', style: 'background:transparent;color:#fff', onclick: () => { st.sel.clear(); drawList(); } }, ic('x'))));
  }
  const reSort = async () => { try { const nd = await get(`/granths?sort=${st.sort}&order=${st.order}`); data.items = nd.items; st.limit = 60; drawList(); } catch (e) { fail(e); } };
  const sortSel = h('select', { 'aria-label': 'क्रम चुनें', onchange: (e) => { st.sort = e.target.value; st.order = SORT_DEFAULT_ORDER[st.sort]; orderBtn.textContent = st.order === 'asc' ? '↑ बढ़ता' : '↓ घटता'; reSort(); } }, SORTS.map(([k, l]) => h('option', { value: k, selected: k === st.sort }, l)));
  const orderBtn = h('button', { class: 'btn sm', 'aria-label': 'क्रम की दिशा', onclick: () => { st.order = st.order === 'asc' ? 'desc' : 'asc'; orderBtn.textContent = st.order === 'asc' ? '↑ बढ़ता' : '↓ घटता'; reSort(); } }, st.order === 'asc' ? '↑ बढ़ता' : '↓ घटता');
  const search = h('input', { type: 'search', placeholder: 'ग्रंथ, लेखक या ID खोजें…', value: st.q, oninput: (e) => { st.q = e.target.value.trim(); st.limit = 60; drawList(); } });
  const chips = h('div', { class: 'chips' }, FILTERS.map(([k, l]) => h('button', { class: 'chip' + (st.f.has(k) ? ' on' : ''), onclick: (e) => { st.f.has(k) ? st.f.delete(k) : st.f.add(k); e.currentTarget.classList.toggle('on'); st.limit = 60; drawList(); } }, l, k === 'hidden' ? ` (${data.hidden_count})` : '')));
  root.append(h('div', { class: 'page-title' }, 'ग्रंथ'),
    h('div', { class: 'toolbar' }, search, h('div', { class: 'row' }, h('span', { class: 'sub' }, 'क्रम:'), sortSel, orderBtn), chips, h('div', { class: 'row space' }, countEl, h('div', { class: 'row' },
      h('button', { class: 'btn sm', onclick: () => { for (const g of filtered()) st.sel.add(g.id); drawList(); } }, ic('check'), 'सब चुनें'),
      h('button', { class: 'btn sm', onclick: () => { st.sel.clear(); drawList(); } }, 'चयन साफ़')))),
    listEl, moreEl, bulkEl);
  drawList();
  return root;
};

// ---------- folders (tree editor) ----------
function slug() { return 'n' + Math.random().toString(36).slice(2, 8); }
ROUTES.folders = async () => {
  const data = await get('/structure');
  let st = JSON.parse(JSON.stringify(data.structure));
  let dirty = false;
  const counts = data.counts, icons = data.icons;
  const root = h('div', null);
  const treeEl = h('div');
  const saveBtn = h('button', { class: 'btn primary', onclick: save }, ic('check'), 'Draft में सेव करें');
  const open = S.tmp.open || (S.tmp.open = new Set());
  const mark = () => { dirty = true; saveBtn.classList.add('saffron'); saveBtn.firstChild.nextSibling.textContent = 'Draft में सेव करें •'; };
  const cnt = (key) => counts[key] != null ? h('span', { class: 'cnt' }, counts[key] + ' ग्रंथ') : null;
  const move = (arr, i, d) => { const j = i + d; if (j < 0 || j >= arr.length) return; [arr[i], arr[j]] = [arr[j], arr[i]]; mark(); draw(); };
  const vis = (n) => n.visible !== false;

  function nodeCard(n, arr, i, kind, parentKeys, iconList, depth) {
    const key = parentKeys.concat(n.id).join('/');
    const isOpen = open.has(key);
    const ti = h('input', { type: 'text', class: 'nt', value: n.title, maxlength: 60, 'aria-label': 'नाम', onchange: (e) => { n.title = e.target.value.trim() || n.title; mark(); } });
    const kids = kind === 'religion' ? n.groups : kind === 'group' ? n.subgroups : null;
    const hasOwnIds = kind === 'group' && !(n.subgroups && n.subgroups.length) && (n.granthIds || []).length > 0;
    const head = h('div', { class: 'nh' },
      h('span', { class: 'ibox ' + (n.tone || 'gold') }, ic(kind === 'religion' ? 'library' : 'folder')),
      ti,
      kind !== 'subgroup' ? null : null,
      kind === 'religion' || kind === 'group' ? h('span', { class: 'cnt' }, `${(kids || []).length} ${kind === 'religion' ? 'ग्रुप' : 'उप-ग्रुप'}`) : cnt(key),
      h('button', { class: 'sw' + (vis(n) ? ' on' : ''), role: 'switch', 'aria-checked': String(vis(n)), title: 'ऐप में दिखाएँ', 'aria-label': 'ऐप में दिखाएँ', onclick: () => { n.visible = !vis(n); mark(); draw(); } }),
      h('button', { class: 'btn icon sm', 'aria-label': 'ऊपर', onclick: () => move(arr, i, -1) }, ic('up2')),
      h('button', { class: 'btn icon sm', 'aria-label': 'नीचे', onclick: () => move(arr, i, 1) }, ic('down2')),
      h('button', { class: 'btn icon sm', 'aria-label': 'विकल्प', onclick: () => { isOpen ? open.delete(key) : open.add(key); draw(); } }, ic(isOpen ? 'down' : 'edit')),
      h('button', { class: 'btn icon sm danger', 'aria-label': 'हटाएँ', onclick: async () => {
        if (!(await confirmBox('हटाएँ?', `"${n.title}" और उसके अंदर के सब फ़ोल्डर हटेंगे। उनके ग्रंथ अपनी डिफ़ॉल्ट जगह या "अन्य" में जाएँगे।`, 'हाँ, हटाएँ', 'danger'))) return;
        arr.splice(i, 1); mark(); draw(); } }, ic('trash')));
    const iconSel = h('select', { 'aria-label': 'आइकन', onchange: (e) => { n.icon = e.target.value; mark(); } }, iconList.map((x) => h('option', { value: x, selected: n.icon === x }, x)));
    const toneSel = kind === 'religion' ? h('select', { 'aria-label': 'रंग', onchange: (e) => { n.tone = e.target.value; mark(); draw(); } }, icons.tones.map((x) => h('option', { value: x, selected: n.tone === x }, x))) : null;
    const cs = h('input', { type: 'text', maxlength: 200, value: n.coming_soon || '', placeholder: 'जैसे: जल्द आ रहा है…', onchange: (e) => { const v = e.target.value.trim(); if (v) n.coming_soon = v; else delete n.coming_soon; mark(); } });
    const extra = h('div', { class: 'nx' + (isOpen ? ' open' : '') },
      h('div', null, h('label', { class: 'f' }, 'आइकन'), iconSel), toneSel ? h('div', null, h('label', { class: 'f' }, 'रंग'), toneSel) : h('div', null, h('label', { class: 'f' }, 'ID (बदलता नहीं)'), h('div', { class: 'mono', style: 'padding:10px 0' }, key)),
      h('div', { class: 'full' }, h('label', { class: 'f' }, '"जल्द आ रहा है" संदेश (ख़ाली = बंद)'), cs));
    const wrap = h('div', { class: 'node' + (vis(n) ? '' : ' off') }, head, extra);
    if (kids) {
      const kc = h('div', { class: 'kids' });
      kids.forEach((k, j) => kc.append(nodeCard(k, kids, j, kind === 'religion' ? 'group' : 'subgroup', parentKeys.concat(n.id), icons.group, depth + 1)));
      if (kind !== 'group' || !hasOwnIds) kc.append(h('button', { class: 'btn sm', style: 'margin-top:4px', onclick: () => addChild(n, kind) }, ic('foldplus'), kind === 'religion' ? 'ग्रुप जोड़ें' : 'उप-ग्रुप जोड़ें'));
      else kc.append(h('div', { class: 'sub' }, 'इस ग्रुप में सीधे ग्रंथ हैं — उप-ग्रुप जोड़ने के लिए पहले इन्हें दूसरे फ़ोल्डर में भेजें'));
      wrap.append(kc);
    }
    return wrap;
  }
  async function addChild(n, kind) {
    const title = await askText(kind === 'religion' ? 'नए ग्रुप का नाम' : 'नए उप-ग्रुप का नाम');
    if (!title) return;
    if (kind === 'religion') { n.groups.push({ id: slug(), title, icon: 'books', granthIds: [], keywords: [] }); }
    else { (n.subgroups ||= []).push({ id: slug(), title, icon: 'books', granthIds: [], keywords: [] }); delete n.granthIds; delete n.keywords; delete n.notKeywords; }
    mark(); draw();
  }
  function askText(title) {
    return new Promise((res) => { const inp = h('input', { type: 'text', maxlength: 60, placeholder: 'नाम…' }); let ok = false;
      modal(title, inp, [{ label: 'रद्द करें', fn: () => res(null) }, { label: 'जोड़ें', cls: 'primary', fn: () => { const v = inp.value.trim(); if (!v) { inp.focus(); return false; } res(v); } }]); setTimeout(() => inp.focus(), 50); });
  }
  function draw() {
    treeEl.replaceChildren();
    st.religions.forEach((r, i) => treeEl.append(nodeCard(r, st.religions, i, 'religion', [], icons.religion, 0)));
    const o = st.other;
    const cs = h('input', { type: 'text', maxlength: 200, value: o.coming_soon || '', placeholder: '"जल्द आ रहा है" संदेश', onchange: (e) => { const v = e.target.value.trim(); if (v) o.coming_soon = v; else delete o.coming_soon; mark(); } });
    treeEl.append(h('div', { class: 'node' }, h('div', { class: 'nh' }, h('span', { class: 'ibox gold' }, ic('folder')), h('b', { style: 'flex:1' }, 'अन्य'), cnt('other'), h('span', { class: 'sub' }, '(स्थायी)')), h('div', { class: 'nx open' }, h('div', { class: 'full' }, h('label', { class: 'f' }, '"जल्द आ रहा है" संदेश'), cs))));
  }
  async function save(btn) {
    const b = saveBtn; setBusy(b, true);
    try {
      let r;
      try { r = await put('/structure', { structure: st }); }
      catch (e) {
        if (e.status === 409 && e.body.error === 'leaf_in_use') {
          const n = Object.values(e.body.leaves).flat().length;
          if (!(await confirmBox('ग्रंथ अटके हैं', `${n} ग्रंथ उन फ़ोल्डरों में रखे हैं जो आपने हटा दिए। उन्हें डिफ़ॉल्ट जगह पर भेजकर सेव करें?`, 'हाँ, सेव करें'))) { setBusy(b, false); return; }
          r = await put('/structure', { structure: st, drop_overrides: true });
        } else throw e;
      }
      dirty = false; S.me.has_draft = true; toast('फ़ोल्डर draft में सेव — अब "प्रकाशित करें" दबाएँ'); await refreshAndRender();
    } catch (e) { setBusy(b, false); fail(e); }
  }
  root.append(h('div', { class: 'row space' }, h('div', { class: 'page-title' }, 'फ़ोल्डर'), saveBtn),
    h('div', { class: 'note', style: 'margin-bottom:12px' }, 'नाम बदलें, ↑↓ से क्रम, स्विच से ऐप में दिखाएँ/छिपाएँ, ✎ से आइकन और "जल्द आ रहा है" संदेश। बदलाव सेव करने के बाद ही draft में जाते हैं।'), treeEl,
    h('div', { class: 'row', style: 'margin-top:8px' }, h('button', { class: 'btn', onclick: async () => { const t = await askText('नए धर्म/फ़ोल्डर का नाम'); if (!t) return; st.religions.push({ id: slug(), title: t, icon: 'misc', tone: 'gold', groups: [{ id: slug(), title: t, icon: 'books', granthIds: [], keywords: [] }] }); mark(); draw(); } }, ic('foldplus'), 'नया धर्म जोड़ें')));
  draw();
  return root;
};

// ---------- inbox ----------
ROUTES.inbox = async () => {
  const [a, data] = await Promise.all([get('/alerts'), get('/granths')]);
  S.tmp.inboxCount = a.count;
  const root = h('div', null);
  const syncBtn = h('button', { class: 'btn sm', onclick: async () => { setBusy(syncBtn, true); try { const r = await post('/sync'); toast(r.ok ? `जाँच पूरी — ${(r.added || []).length} नए` : 'कैटलॉग नहीं मिला', !r.ok); await refreshAndRender(); } catch (e) { setBusy(syncBtn, false); fail(e); } } }, ic('refresh'), 'अभी जाँचें');
  root.append(h('div', { class: 'row space' }, h('div', { class: 'page-title' }, 'नए ग्रंथ'), syncBtn),
    h('div', { class: 'sub', style: 'margin-bottom:10px' }, `हर 15 मिनट में कैटलॉग जाँचा जाता है. आख़िरी: ${fmtTime(data.sync.sync_last_ok)}`));
  const act = async (fn, msg) => { try { await fn(); S.me.has_draft = true; toast(msg); await refreshAndRender(); } catch (e) { fail(e); } };
  const sel = (g) => {
    const s = h('select', { 'aria-label': 'फ़ोल्डर' }); const byRel = new Map();
    for (const l of data.leaves) { if (!byRel.has(l.religion_id)) byRel.set(l.religion_id, { t: l.religion, i: [] }); byRel.get(l.religion_id).i.push(l); }
    for (const [, r] of byRel) s.append(h('optgroup', { label: r.t }, r.i.map((l) => h('option', { value: l.key }, l.group))));
    s.value = g.suggested_leaf; return s;
  };
  if (!a.new_granths.length && !a.alerts.length) root.append(h('div', { class: 'card empty' }, '🙏 सब ठीक है — कोई नया ग्रंथ या अलर्ट नहीं'));
  const list = h('div', { class: 'glist' });
  for (const g of a.new_granths) {
    const s = sel(g);
    list.append(h('div', { class: 'card' }, h('div', { class: 'row', style: 'align-items:flex-start;flex-wrap:nowrap' }, h('div', { class: 'cv', style: `width:52px;height:66px;flex:none;border-radius:6px;background:var(--cream-dark) center/cover;${g.cover ? `background-image:url("${g.cover}")` : ''}` }), h('div', { style: 'min-width:0;flex:1' }, h('b', null, g.title), h('div', { class: 'sub' }, `क्र. ${g.position ?? '—'} · ID ${g.id}`, g.author ? ' · ' + g.author : '', ` · ${fmtTime(g.first_seen)}`), h('div', { class: 'sub' }, 'सुझाव: ', h('b', null, g.suggested_label), g.suggestion_source === 'auto' ? '' : ''))),
      h('label', { class: 'f' }, 'फ़ोल्डर'), s,
      h('div', { class: 'row', style: 'margin-top:10px' },
        h('button', { class: 'btn sm primary', onclick: () => act(() => put('/granths/' + g.id, { leaf: s.value }), 'फ़ोल्डर तय (draft)') }, ic('check'), 'यहाँ रखें'),
        h('button', { class: 'btn sm', onclick: () => act(() => put('/granths/' + g.id, { leaf: 'other' }), 'अन्य में रखा (draft)') }, 'अन्य में रखें'),
        h('button', { class: 'btn sm', onclick: () => act(() => put('/granths/' + g.id, { hidden: true }), 'छिपाया (draft)') }, ic('eyeoff'), 'छिपाएँ'),
        h('button', { class: 'btn sm', onclick: () => act(() => post('/alerts/g:' + g.id + '/ack'), 'ठीक है, जैसा है वैसा') }, 'जैसा है ठीक'))));
  }
  root.append(list);
  if (a.alerts.length) root.append(h('h3', { class: 'page-title', style: 'font-size:20px;margin-top:18px' }, 'अलर्ट'), h('div', { class: 'glist' }, a.alerts.map((x) => h('div', { class: 'card row space' }, h('div', null, h('span', { class: 'pill ' + (x.kind === 'sync_error' ? 'bad' : '') }, x.kind), ' ', x.message, h('div', { class: 'sub' }, fmtTime(x.created_at))), h('button', { class: 'btn sm', onclick: () => act(() => post('/alerts/a:' + x.id + '/ack'), 'अलर्ट बंद') }, 'बंद करें')))));
  return root;
};

// ---------- history ----------
ROUTES.history = async () => {
  const v = await get('/versions');
  const root = h('div', null, h('div', { class: 'page-title' }, 'इतिहास'), h('div', { class: 'sub', style: 'margin-bottom:10px' }, 'आख़िरी 20 वर्ज़न रखे जाते हैं. Rollback पुराने कंटेंट को नए (ऊँचे) वर्ज़न नंबर से प्रकाशित करता है.'));
  const list = h('div', { class: 'glist' });
  for (const it of v.items) {
    const cur = it.version === v.current;
    list.append(h('div', { class: 'card ver' + (cur ? ' cur' : '') }, h('div', { class: 'vn' }, 'v' + it.version),
      h('div', { style: 'flex:1;min-width:0' }, h('div', { class: 'row' }, h('span', { class: 'pill' + (cur ? ' ok' : '') }, cur ? 'चालू' : it.kind), it.note ? h('b', null, it.note) : null), h('div', { class: 'sub' }, `${it.author || '—'} · ${fmtTime(it.created_at)} · ${(it.bytes / 1024).toFixed(1)} KB`),
        h('div', { class: 'row', style: 'margin-top:8px' },
          h('button', { class: 'btn sm', onclick: () => showVersion(it.version) }, ic('eye'), 'बदलाव'),
          cur ? null : h('button', { class: 'btn sm danger', onclick: () => doRollback(it.version) }, ic('history'), 'Rollback')))));
  }
  root.append(list); return root;
};
async function showVersion(n) {
  let d; try { d = await get('/versions/' + n); } catch (e) { return fail(e); }
  modal(`v${n} में क्या बदला`, h('div', null, h('div', { class: 'sub' }, d.against ? `v${d.against} के मुकाबले` : 'पहला वर्ज़न'), diffView(d.diff), h('details', { style: 'margin-top:12px' }, h('summary', null, 'पूरा config.json'), h('pre', { class: 'mono', style: 'white-space:pre-wrap;max-height:260px;overflow:auto' }, JSON.stringify(d.config, null, 2)))), [{ label: 'बंद करें' }]);
}
async function doRollback(n) {
  if (!(await confirmBox('Rollback?', `v${n} का कंटेंट नए वर्ज़न की तरह प्रकाशित होगा. मौजूदा draft हट सकता है.`, 'हाँ, Rollback करें', 'danger'))) return;
  try { const r = await post('/rollback', { to_version: n }); toast(`v${r.version} प्रकाशित (v${n} का कंटेंट)`); await refreshAndRender(); } catch (e) { fail(e); }
}

// ---------- analytics detail ----------
ROUTES.analytics = async () => {
  const kind = S.q.get('kind') === 'folder' ? 'folder' : 'granth', id = S.q.get('id');
  const root = h('div', null);
  const tabs = h('div', { class: 'chips' }, [['granth', 'ग्रंथ'], ['folder', 'फ़ोल्डर']].map(([k, l]) => h('a', { class: 'chip' + (kind === k && !id ? ' on' : ''), href: '#/analytics?kind=' + k, style: 'text-decoration:none' }, l)));
  root.append(h('div', { class: 'row space' }, h('div', { class: 'page-title' }, 'एनालिटिक्स'), rangeChips(render)), tabs);
  if (id) {
    const s = await get(`/stats/series?kind=${kind}&id=${encodeURIComponent(id)}&days=${S.range}`);
    const label = (kind === 'granth' ? (S.cache['t' + id] || `#${id}`) : id);
    const tot = s.series.reduce((a, b) => ({ o: a.o + b.opens, w: a.w + b.watch_s }), { o: 0, w: 0 });
    root.append(h('a', { href: '#/analytics?kind=' + kind, class: 'btn sm', style: 'text-decoration:none;margin:8px 0' }, '← वापस'),
      h('div', { class: 'card', style: 'margin-top:8px' }, h('h3', null, label), h('div', { class: 'row' }, h('span', { class: 'pill' }, fmtN(tot.o) + ' ओपन'), h('span', { class: 'pill' }, fmtDur(tot.w) + ' समय'))),
      h('div', { class: 'card', style: 'margin-top:12px' }, h('h3', null, 'रोज़ के ओपन'), barChart(s.series, 'opens')),
      h('div', { class: 'card', style: 'margin-top:12px' }, h('h3', null, 'रोज़ का समय'), barChart(s.series, 'watch_s', 'bar2')));
    return root;
  }
  const d = await get(`/stats/${kind}s?days=${S.range}`);
  if (kind === 'granth') for (const i of d.items) S.cache['t' + i.id] = i.title;
  const list = h('div', { class: 'glist', style: 'margin-top:8px' });
  if (!d.items.length) list.append(h('div', { class: 'card empty' }, 'इस अवधि में कोई डेटा नहीं'));
  for (const i of d.items) list.append(h('a', { class: 'card link', href: `#/analytics?kind=${kind}&id=${encodeURIComponent(kind === 'granth' ? i.id : i.key)}` }, h('div', { class: 'row space' }, h('b', null, i.title || i.label), h('span', { class: 'pill' }, fmtN(i.opens) + ' ओपन')), h('div', { class: 'sub' }, `समय ${fmtDur(i.watch_s)} · औसत ${fmtDur(i.avg_watch_s)}/ओपन`)));
  root.append(list); return root;
};

// ---------- settings ----------
ROUTES.settings = async () => {
  const [s, au, ses, adm] = await Promise.all([get('/settings'), get('/audit?limit=60'), get('/sessions'), S.me.role === 'owner' ? get('/admins') : Promise.resolve(null)]);
  const root = h('div', { class: 'stack' }, h('div', { class: 'page-title' }, 'सेटिंग्स'));
  const sw = (on, fn) => { const b = h('button', { class: 'sw' + (on ? ' on' : ''), role: 'switch', 'aria-checked': String(on), onclick: () => { on = !on; b.classList.toggle('on', on); b.setAttribute('aria-checked', String(on)); fn(on); } }); return b; };
  const flags = { ...s.flags };
  const sample = h('input', { type: 'number', min: 0, max: 1, step: 0.05, value: flags.analytics_sample });
  const ann = { ...s.announcement };
  const annText = h('textarea', { maxlength: 280, placeholder: 'ऐप में दिखने वाला संदेश (280 अक्षर तक)' }, ann.text || '');
  const annLevel = h('select', null, s.levels.map((l) => h('option', { value: l, selected: ann.level === l }, l)));
  const annExp = h('input', { type: 'datetime-local', value: ann.expires_at ? toLocalIst(ann.expires_at) : '' });
  const annId = h('input', { type: 'text', value: ann.id, maxlength: 40 });
  const ai = h('input', { type: 'text', value: s.ai_endpoint || '', placeholder: 'https://…', autocapitalize: 'none' });
  const saveAll = h('button', { class: 'btn primary', onclick: async () => {
    setBusy(saveAll, true);
    try {
      const a = { enabled: ann.enabled, text: annText.value, level: annLevel.value, id: annId.value.trim() || ann.id };
      if (annExp.value) a.expires_at = new Date(annExp.value + '+05:30').toISOString(); else a.expires_at = null;
      await put('/settings', { flags: { ai_enabled: flags.ai_enabled, analytics_enabled: flags.analytics_enabled, analytics_sample: Number(sample.value) }, announcement: a, ai_endpoint: ai.value.trim() });
      S.me.has_draft = true; toast('सेटिंग्स draft में सेव'); await refreshAndRender();
    } catch (e) { setBusy(saveAll, false); fail(e); }
  } }, ic('check'), 'Draft में सेव करें');
  root.append(
    h('div', { class: 'card' }, h('h3', null, ic('settings'), 'ऐप फ़्लैग'),
      h('div', { class: 'sw-wrap' }, h('div', null, h('b', null, 'AI सहायक चालू'), h('div', { class: 'sub' }, 'ai_enabled')), sw(flags.ai_enabled, (v) => { flags.ai_enabled = v; })),
      h('div', { class: 'sw-wrap' }, h('div', null, h('b', null, 'एनालिटिक्स चालू'), h('div', { class: 'sub' }, 'analytics_enabled — बंद करने पर ऐप डेटा भेजना रोक देता है')), sw(flags.analytics_enabled, (v) => { flags.analytics_enabled = v; })),
      h('label', { class: 'f' }, 'एनालिटिक्स sample (0 से 1; 1 = सब यूज़र)'), sample),
    h('div', { class: 'card' }, h('h3', null, ic('alert'), 'घोषणा (announcement)'),
      h('div', { class: 'sw-wrap' }, h('b', null, 'बैनर दिखाएँ'), sw(ann.enabled, (v) => { ann.enabled = v; })),
      h('label', { class: 'f' }, 'संदेश'), annText, h('label', { class: 'f' }, 'स्तर'), annLevel,
      h('label', { class: 'f' }, 'समाप्ति (IST, वैकल्पिक)'), annExp,
      h('label', { class: 'f' }, 'ID (नई घोषणा के लिए बदलें ताकि फिर से दिखे)'), h('div', { class: 'row', style: 'flex-wrap:nowrap' }, annId, h('button', { class: 'btn sm', onclick: () => { annId.value = 'a' + Date.now().toString(36); } }, 'नई ID'))),
    h('div', { class: 'card' }, h('h3', null, ic('sparkle'), 'AI endpoint'), h('div', { class: 'sub' }, 'सिर्फ़ एक सेव किया हुआ स्ट्रिंग — ऐप इसे config.json से पढ़ता है.'), h('label', { class: 'f' }, 'endpoints.ai'), ai),
    h('div', { class: 'row' }, saveAll, h('span', { class: 'sub' }, 'सेव के बाद "प्रकाशित करें" दबाना होगा')),
    h('div', { class: 'card' }, h('h3', null, 'जानकारी'), h('div', { class: 'sub' }, 'प्रकाशित वर्ज़न: v' + s.info.published_version), h('div', { class: 'sub' }, 'Base: ', h('span', { class: 'mono' }, s.info.base)),
      h('div', { class: 'sub' }, 'Config: ', h('span', { class: 'mono' }, s.info.base + '/config.json')), h('div', { class: 'sub' }, 'Events: ', h('span', { class: 'mono' }, s.info.base + '/events')),
      h('div', { class: 'sub' }, 'साइनिंग: ', s.info.signed ? 'चालू (Ed25519)' : 'बंद'), s.info.signing_public_key ? h('div', { class: 'mono' }, s.info.signing_public_key) : null),
    passwordCard(),
    adm ? adminsCard(adm) : null,
    sessionsCard(ses.items),
    h('div', { class: 'card' }, h('h3', null, ic('history'), 'ऑडिट लॉग'), au.items.length ? au.items.map((a) => h('div', { class: 'aud' }, h('b', null, a.action), ' · ', a.actor, h('div', { class: 'sub' }, fmtTime(a.ts)), h('div', { class: 'd' }, String(a.detail || '').slice(0, 160)))) : h('div', { class: 'empty' }, 'कुछ नहीं')));
  return root;
};
function sessionsCard(items) {
  return h('div', { class: 'card' }, h('h3', null, ic('users'), 'लॉगिन सेशन'), items.map((x) => h('div', { class: 'row space aud' }, h('div', null, h('b', null, x.kind === 'app' ? 'ऐप: ' + x.client : 'वेब'), x.current ? h('span', { class: 'pill ok', style: 'margin-left:6px' }, 'यह डिवाइस') : null, h('div', { class: 'sub' }, 'आख़िरी: ' + fmtTime(x.last_seen))),
    x.current ? null : h('button', { class: 'btn sm danger', onclick: async () => { try { await api('DELETE', '/sessions/' + x.sid); toast('सेशन बंद'); render(); } catch (e) { fail(e); } } }, 'बंद करें'))),
    items.length > 1 ? h('button', { class: 'btn sm danger', style: 'margin-top:10px', onclick: async () => { try { await post('/sessions/revoke_all'); toast('बाकी सब सेशन बंद'); render(); } catch (e) { fail(e); } } }, 'बाकी सब बंद करें') : null);
}
function toLocalIst(iso) { const d = new Date(new Date(iso).getTime() + 5.5 * 3600e3); return d.toISOString().slice(0, 16); }
function adminsCard(adm) {
  const root = h('div', { class: 'card' }, h('h3', null, ic('users'), 'एडमिन (admins)'), h('div', { class: 'sub' }, 'owner = एडमिन संभाल सकता है · admin = बदलाव/प्रकाशन कर सकता है, एडमिन नहीं संभाल सकता.'));
  const ask = (title, label) => new Promise((res) => { const inp = h('input', { type: 'password', autocomplete: 'new-password', placeholder: label }); const err = h('div', { class: 'err' }); let fin = false;
    modal(title, h('div', null, inp, err), [{ label: 'रद्द करें', fn: () => { if (!fin) res(null); } }, { label: 'ठीक है', cls: 'primary', keep: true, fn: (b, close) => { if (inp.value.length < 10) { err.textContent = 'कम से कम 10 अक्षर'; return false; } fin = true; res(inp.value); close(); } }]); });
  const run = async (fn, msg) => { try { await fn(); toast(msg); render(); } catch (e) { fail(e); } };
  for (const a of adm.items) {
    const u = encodeURIComponent(a.username);
    root.append(h('div', { class: 'aud' }, h('div', { class: 'row space' }, h('div', null, h('b', null, a.username), ' ', h('span', { class: 'pill' }, a.role), a.you ? h('span', { class: 'pill ok', style: 'margin-left:4px' }, 'आप') : null, a.disabled ? h('span', { class: 'pill bad', style: 'margin-left:4px' }, 'बंद') : null,
      h('div', { class: 'sub' }, `सेशन: ${a.active_sessions}` + (a.last_seen ? ' · आख़िरी: ' + fmtTime(a.last_seen) : '')))),
      a.you ? null : h('div', { class: 'row', style: 'margin-top:6px' },
        h('button', { class: 'btn sm', onclick: async () => { const pw = await ask('नया पासवर्ड — ' + a.username, 'नया पासवर्ड (10+)'); if (pw) run(() => post('/admins/' + u + '/password', { password: pw }), 'पासवर्ड रीसेट (उसके सेशन बंद)'); } }, 'पासवर्ड रीसेट'),
        h('button', { class: 'btn sm', onclick: () => run(() => put('/admins/' + u, { disabled: !a.disabled }), a.disabled ? 'चालू किया' : 'बंद किया') }, a.disabled ? 'चालू करें' : 'बंद करें'),
        h('button', { class: 'btn sm', onclick: () => run(() => put('/admins/' + u, { role: a.role === 'owner' ? 'admin' : 'owner' }), 'रोल बदला') }, a.role === 'owner' ? 'admin बनाएँ' : 'owner बनाएँ'),
        h('button', { class: 'btn sm danger', onclick: async () => { if (await confirmBox('एडमिन हटाएँ?', `${a.username} हमेशा के लिए हट जाएगा.`, 'हाँ, हटाएँ', 'danger')) run(() => api('DELETE', '/admins/' + u), 'हटाया'); } }, 'हटाएँ'))));
  }
  const un = h('input', { type: 'text', autocapitalize: 'none', autocomplete: 'off', placeholder: 'username (a-z 0-9 . _ -)' }), pw = h('input', { type: 'password', autocomplete: 'new-password', placeholder: 'पासवर्ड (10+ अक्षर)' });
  const role = h('select', null, adm.roles.slice().reverse().map((r) => h('option', { value: r }, r)));
  const msg = h('div', { class: 'err' });
  const add = h('button', { class: 'btn primary', onclick: async () => { msg.textContent = ''; setBusy(add, true); try { await post('/admins', { username: un.value.trim(), password: pw.value, role: role.value }); un.value = pw.value = ''; toast('एडमिन बना'); render(); } catch (e) { msg.textContent = errText(e); } setBusy(add, false); } }, ic('check'), 'एडमिन जोड़ें');
  root.append(h('h4', { style: 'margin:14px 0 4px' }, 'नया एडमिन'), un, h('div', { style: 'height:6px' }), pw, h('div', { style: 'height:6px' }), role, msg, h('div', { style: 'margin-top:10px' }, add));
  return root;
}
function passwordCard() {
  const cur = h('input', { type: 'password', autocomplete: 'current-password' }), n1 = h('input', { type: 'password', autocomplete: 'new-password' }), n2 = h('input', { type: 'password', autocomplete: 'new-password' });
  const msg = h('div', { class: 'err' });
  const btn = h('button', { class: 'btn', onclick: async () => {
    msg.textContent = '';
    if (n1.value.length < 10) { msg.textContent = 'नया पासवर्ड कम से कम 10 अक्षर का हो'; return; }
    if (n1.value !== n2.value) { msg.textContent = 'दोनों नए पासवर्ड एक जैसे नहीं'; return; }
    setBusy(btn, true);
    try { await post('/password', { current: cur.value, new: n1.value }); cur.value = n1.value = n2.value = ''; toast('पासवर्ड बदल गया (बाकी सेशन बंद)'); }
    catch (e) { msg.textContent = e.status === 401 ? 'मौजूदा पासवर्ड ग़लत है' : e.status === 429 ? 'बहुत कोशिशें — बाद में' : errText(e); }
    setBusy(btn, false);
  } }, 'पासवर्ड बदलें');
  return h('div', { class: 'card' }, h('h3', null, 'पासवर्ड बदलें'), h('label', { class: 'f' }, 'मौजूदा पासवर्ड'), cur, h('label', { class: 'f' }, 'नया पासवर्ड (10+ अक्षर)'), n1, h('label', { class: 'f' }, 'नया फिर से'), n2, msg, h('div', { style: 'margin-top:10px' }, btn));
}

// ---------- contacts (विशेष जानकार) ----------
ROUTES.contacts = async () => {
  const d = await get('/contacts');
  const items = d.items.map((c) => ({ id: c.id, name: c.name, role: c.role, phone: c.phone, whatsapp: c.whatsapp, visible: c.visible }));
  const titleIn = h('input', { type: 'text', maxlength: 60, value: d.page.title, 'aria-label': 'पेज का शीर्षक' });
  const listEl = h('div', { class: 'glist' }), msg = h('div', { class: 'err' });
  const swBtn = (on, fn, label) => { const b = h('button', { class: 'sw' + (on ? ' on' : ''), role: 'switch', 'aria-checked': String(on), 'aria-label': label, onclick: () => { on = !on; b.classList.toggle('on', on); b.setAttribute('aria-checked', String(on)); fn(on); } }); return b; };
  const move = (i, dlt) => { const j = i + dlt; if (j < 0 || j >= items.length) return; [items[i], items[j]] = [items[j], items[i]]; draw(); };
  const rowFor = (c, i) => h('div', { class: 'card' + (c.visible ? '' : ' hid') },
    h('div', { class: 'row space' }, h('b', null, `${i + 1}.`), h('div', { class: 'row' },
      h('button', { class: 'btn sm icon', 'aria-label': 'ऊपर', disabled: i === 0, onclick: () => move(i, -1) }, '↑'),
      h('button', { class: 'btn sm icon', 'aria-label': 'नीचे', disabled: i === items.length - 1, onclick: () => move(i, 1) }, '↓'),
      h('button', { class: 'btn sm danger', onclick: async () => { if (await confirmBox('हटाएँ?', `${c.name || 'यह नाम'} सूची से हट जाएगा (draft में).`, 'हाँ, हटाएँ', 'danger')) { items.splice(i, 1); draw(); } } }, ic('x'), 'हटाएँ'))),
    h('label', { class: 'f' }, 'नाम (ज़रूरी)'), h('input', { type: 'text', maxlength: 80, value: c.name, oninput: (e) => { c.name = e.target.value; } }),
    h('label', { class: 'f' }, 'भूमिका (वैकल्पिक)'), h('input', { type: 'text', maxlength: 80, value: c.role, oninput: (e) => { c.role = e.target.value; } }),
    h('label', { class: 'f' }, 'फ़ोन (सिर्फ़ अंक, शुरू में + चल सकता है)'), h('input', { type: 'tel', inputmode: 'tel', maxlength: 20, autocomplete: 'off', value: c.phone, oninput: (e) => { c.phone = e.target.value.replace(/[\s-]/g, ''); } }),
    h('div', { class: 'sw-wrap' }, h('b', null, 'WhatsApp'), swBtn(c.whatsapp, (v) => { c.whatsapp = v; }, 'WhatsApp')),
    h('div', { class: 'sw-wrap' }, h('b', null, 'ऐप में दिखाएँ'), swBtn(c.visible, (v) => { c.visible = v; draw(); }, 'दिखाएँ')));
  function draw() { listEl.replaceChildren(...items.map(rowFor)); if (!items.length) listEl.append(h('div', { class: 'card empty' }, 'कोई नाम नहीं')); }
  const addBtn = h('button', { class: 'btn', onclick: () => { if (items.length >= d.max_contacts) { toast(`अधिकतम ${d.max_contacts}`, true); return; } items.push({ id: '', name: '', role: '', phone: '', whatsapp: false, visible: true }); draw(); } }, ic('check'), 'नाम जोड़ें');
  const save = h('button', { class: 'btn primary', onclick: async () => {
    msg.textContent = ''; setBusy(save, true);
    try { await put('/contacts', { title: titleIn.value, items: items.map((c) => ({ ...(c.id ? { id: c.id } : {}), name: c.name, role: c.role, phone: c.phone, whatsapp: c.whatsapp, visible: c.visible })) }); S.me.has_draft = true; toast('विशेष जानकार draft में सेव'); await refreshAndRender(); }
    catch (e) { msg.textContent = errText(e); setBusy(save, false); }
  } }, ic('check'), 'Draft में सेव करें');
  draw();
  return h('div', { class: 'stack' }, h('div', { class: 'page-title' }, 'विशेष जानकार'),
    h('div', { class: 'card' }, h('label', { class: 'f' }, 'पेज का शीर्षक'), titleIn, h('div', { class: 'sub' }, 'फ़ोन नंबर आप ख़ुद यहाँ भरें. सेव के बाद "प्रकाशित करें" दबाना होगा.')),
    listEl, h('div', { class: 'row' }, addBtn, save), msg);
};

// ---------- boot ----------
(async () => {
  try { await refreshMe(); if (!location.hash) location.hash = '#/dashboard'; render(); }
  catch (e) { if (e.status !== 401) renderLogin(); }
})();
})();
