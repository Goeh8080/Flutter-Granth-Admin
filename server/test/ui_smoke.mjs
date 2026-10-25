// Loads the SPA in jsdom against a running server (BASE) and walks every screen. Not a real browser: no layout/CSS checks.
import { JSDOM, VirtualConsole } from 'jsdom';
import fs from 'node:fs';
const BASE = process.env.BASE || 'http://localhost:8787';
const PW = process.env.PW_FILE ? fs.readFileSync(process.env.PW_FILE, 'utf8').trim() : process.env.GRANTH_PANEL_PASSWORD;
let cookie = '';
const errors = [];
const vc = new VirtualConsole(); vc.on('jsdomError', (e) => errors.push('jsdomError ' + e.message)); vc.on('error', (e) => errors.push('console.error ' + e));
const html = await (await fetch(BASE + '/admin/')).text();
const dom = new JSDOM(html, { url: BASE + '/admin/', runScripts: 'outside-only', pretendToBeVisual: true, virtualConsole: vc });
const w = dom.window;
w.fetch = async (url, opts = {}) => {
  const u = new URL(url, BASE + '/admin/');
  const headers = { ...(opts.headers || {}) }; if (cookie) headers.cookie = cookie;
  const r = await fetch(u, { ...opts, headers, redirect: 'manual' });
  for (const c of r.headers.getSetCookie?.() || []) cookie = c.split(';')[0];
  return r;
};
w.eval(fs.readFileSync(new URL('../public/admin/app.js', import.meta.url), 'utf8'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const doc = w.document;
let fails = 0; const ok = (c, m) => { console.log((c ? '  PASS ' : '  FAIL ') + m); if (!c) fails++; };
await sleep(300);
ok(!!doc.querySelector('.login form'), 'login form rendered');
const inputs = doc.querySelectorAll('.login input'); inputs[1].value = PW;
doc.querySelector('.login form').dispatchEvent(new w.Event('submit', { cancelable: true }));
await sleep(1500);
ok(!!doc.querySelector('.top'), 'logged in, shell rendered');
for (const [route, needle] of [['dashboard', 'डैशबोर्ड'], ['granths', 'ग्रंथ'], ['folders', 'जल्द'], ['inbox', 'नए ग्रंथ'], ['history', 'v1'], ['analytics', 'एनालिटिक्स'], ['settings', 'ऐप फ़्लैग']]) {
  w.location.hash = '#/' + route; await sleep(700);
  const main = doc.querySelector('main').textContent;
  ok(main.includes(needle) && !main.includes('लोड नहीं हुआ'), `route ${route}`);
}
w.location.hash = '#/granths'; await sleep(700);
ok(doc.querySelectorAll('.grow').length >= 50, 'granths rows: ' + doc.querySelectorAll('.grow').length);
// hide first granth via switch, check draft bar, then discard
doc.querySelector('.grow .sw').click(); await sleep(600);
ok(!!doc.querySelector('.bar-pop'), 'draft bar appears after edit');
doc.querySelector('.bar-pop .btn.saffron').click(); await sleep(600);
ok(!!doc.querySelector('.sheet .diff'), 'diff modal opens');
const discard = [...doc.querySelectorAll('.sheet .btn')].find((b) => b.textContent.includes('Draft हटाएँ'));
discard.click(); await sleep(300);
[...doc.querySelectorAll('.sheet .btn')].find((b) => b.textContent.includes('हाँ, हटाएँ'))?.click(); await sleep(800);
await sleep(1000); ok(!doc.querySelector('.bar-pop'), 'draft discarded');
// --- sort control: default #1 first, switching to title re-orders
w.location.hash = '#/granths'; await sleep(700);
ok(/क्र\. 1 · ID/.test(doc.querySelector('.grow')?.textContent || ''), 'granths default list starts at क्र. 1');
const sel = doc.querySelector('main select'); const first0 = doc.querySelector('.grow')?.textContent;
sel.value = 'title'; sel.dispatchEvent(new w.Event('change')); await sleep(900);
ok(doc.querySelector('.grow')?.textContent !== first0, 'sort by title re-orders the list');
sel.value = 'number'; sel.dispatchEvent(new w.Event('change')); await sleep(900);
ok(/क्र\. 1 · ID/.test(doc.querySelector('.grow')?.textContent || ''), 'back to number ascending');
// --- contacts screen
w.location.hash = '#/contacts'; await sleep(900);
const cards = doc.querySelectorAll('main .card input[type=tel]'); ok(cards.length === 4, 'contacts screen shows the 4 seeded names (empty phones)');
ok([...doc.querySelectorAll('main input[type=text]')].some((i) => i.value === 'अमित दास'), 'seed name अमित दास present');
[...doc.querySelectorAll('main .btn')].find((b) => b.textContent.includes('नाम जोड़ें')).click(); await sleep(200);
const nameInputs = [...doc.querySelectorAll('main input[type=text]')]; const newName = nameInputs[nameInputs.length - 2];
newName.value = 'UI टेस्ट'; newName.dispatchEvent(new w.Event('input'));
[...doc.querySelectorAll('main .btn')].find((b) => b.textContent.includes('Draft में सेव')).click(); await sleep(1200);
ok(!!doc.querySelector('.bar-pop'), 'saving contacts creates a draft (draft bar)');
doc.querySelector('.bar-pop .btn.saffron').click(); await sleep(600);
ok(/UI टेस्ट|विशेष जानकार/.test(doc.querySelector('.sheet .diff')?.textContent || ''), 'diff modal lists the contact change');
[...doc.querySelectorAll('.sheet .btn')].find((b) => b.textContent.includes('Draft हटाएँ'))?.click(); await sleep(300);
[...doc.querySelectorAll('.sheet .btn')].find((b) => b.textContent.includes('हाँ, हटाएँ'))?.click(); await sleep(1200);
ok(!doc.querySelector('.bar-pop'), 'contacts draft discarded');
// --- settings: admins card (owner)
w.location.hash = '#/settings'; await sleep(900);
ok(doc.querySelector('main').textContent.includes('एडमिन (admins)') && doc.querySelector('main').textContent.includes('goutam'), 'settings shows the Admins card with goutam');
ok(doc.querySelector('main').textContent.includes('10+ अक्षर'), 'password rule shows 10+');
ok(errors.length === 0, 'no script errors ' + errors.join(' | '));
console.log(fails ? `\n${fails} FAILED` : '\nall ui smoke checks passed');
process.exit(fails ? 1 : 0);
