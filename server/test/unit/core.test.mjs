import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sanitizeBatch, LIMITS } from '../../src/events.js';
import { bootstrapStructure, bootstrapState, validateConfig, validateStructure, placements, leafKeySet, leaves, validateAnnouncement, validateEndpointUrl } from '../../src/structure.js';
import { buildConfig } from '../../src/config.js';
import { canonical, clampInt } from '../../src/util.js';

const TODAY = '2026-10-25';
const leafKeys = leafKeySet(bootstrapStructure());
const ctx = { today: TODAY, leafKeys, granthIds: new Set(['44', '45', '46']) };
const batch = (x = {}) => ({ v: 1, batch_id: 'abcdefgh12', iid: 'a'.repeat(32), app: '1.0.0+1', os: 'android', sdk: 34, cfg: 1, day: TODAY, fg_s: 100, sessions: 1,
  open: { g: { 44: 2 }, f: { 'hindu/puran': 1 }, t: {}, p: {} }, watch_s: { g: { 44: 30 }, f: {}, scr: { reader: 20 } }, ...x });

test('sanitizeBatch accepts a valid batch', () => {
  const b = sanitizeBatch(batch(), ctx);
  assert.equal(b.drop, undefined); assert.equal(b.g['44'], 2); assert.equal(b.wg['44'], 30); assert.equal(b.f['hindu/puran'], 1); assert.equal(b.scr.reader, 20);
});
test('sanitizeBatch drops bad input', () => {
  for (const bad of [null, [], { ...batch(), v: 2 }, batch({ batch_id: 'x' }), batch({ iid: 'zz' }), batch({ app: 'a b' }), batch({ day: '2026-10-10' }), batch({ day: 'nope' }), batch({ open: 'x' })])
    assert.ok(sanitizeBatch(bad, ctx).drop, JSON.stringify(bad).slice(0, 60));
});
test('sanitizeBatch clamps and filters', () => {
  const b = sanitizeBatch(batch({ fg_s: 1e9, open: { g: { 44: 1e9, abc: 1, 123456789: 1, 99999: 1 }, f: { nope: 3 }, t: {}, p: {} }, watch_s: { g: { 44: 1e9 }, f: {}, scr: {} } }), ctx);
  assert.equal(b.fg_s, LIMITS.fg_s); assert.equal(b.g['44'], LIMITS.count); assert.equal(b.wg['44'], LIMITS.watch_s);
  assert.deepEqual(Object.keys(b.g), ['44']); assert.deepEqual(b.f, {});
});
test('sanitizeBatch: >200 keys dropped, day window ±2', () => {
  const many = Object.fromEntries(Array.from({ length: 201 }, (_, i) => [String(i), 1]));
  assert.ok(sanitizeBatch(batch({ open: { g: many } }), ctx).drop);
  assert.equal(sanitizeBatch(batch({ day: '2026-10-23' }), ctx).drop, undefined);
  assert.ok(sanitizeBatch(batch({ day: '2026-10-22' }), ctx).drop);
});

test('bundled structure validates and has jain', () => {
  const s = bootstrapStructure();
  assert.deepEqual(validateStructure(s), []);
  assert.ok(s.religions.some((r) => r.id === 'jain'));
});
test('placements follow override > id > forced > keyword > fallback', () => {
  const s = bootstrapStructure();
  const ls = leaves(s); const target = ls.find((l) => l.key !== 'other' && (l.leaf.granthIds || []).length);
  const id = target.leaf.granthIds[0];
  const rows = [{ id, title: 'x' }, { id: '99999', title: 'zzz unknown' }, { id: '7777', title: 'x' }];
  assert.equal(placements(s, {}, rows)[id].how, 'id');
  assert.equal(placements(s, {}, rows)['99999'].key, 'other');
  const ov = placements(s, { [id]: { leaf: 'other' } }, rows)[id]; assert.deepEqual(ov, { key: 'other', how: 'override' });
  const forced = s.other.forceIds[0]; assert.equal(placements(s, {}, [{ id: forced, title: 'q' }])[forced].how, 'forced');
});

const mkCfg = (mut = {}) => {
  const state = bootstrapState();
  const cfg = buildConfig({ state, version: 2, base: 'https://x.example', unassigned: [], forceHide: false });
  return Object.assign(cfg, mut);
};
const cat = new Set(Array.from({ length: 100 }, (_, i) => String(i + 1)));
test('validateConfig ok on bootstrap', () => {
  const r = validateConfig(mkCfg(), { catalogIds: cat, prevVersion: 1 });
  assert.deepEqual(r.errors, []);
});
test('validateConfig rejects bad leaf, low version, >50% hide, >90%', () => {
  assert.ok(validateConfig(mkCfg({ overrides: { 5: { leaf: 'nope/x' } } }), { catalogIds: cat, prevVersion: 1 }).errors.length);
  assert.ok(validateConfig(mkCfg(), { catalogIds: cat, prevVersion: 2 }).errors.some((e) => /higher/.test(e)));
  const ids = (n) => Array.from({ length: n }, (_, i) => String(i + 1));
  assert.ok(validateConfig(mkCfg({ hidden_granth_ids: ids(60) }), { catalogIds: cat, prevVersion: 1 }).errors.some((e) => />50%/.test(e)));
  const forced = mkCfg({ hidden_granth_ids: ids(60) }); forced.flags.max_hidden_pct = 90;
  assert.deepEqual(validateConfig(forced, { catalogIds: cat, prevVersion: 1, force: true }).errors, []);
  assert.ok(validateConfig(mkCfg({ hidden_granth_ids: ids(95) }), { catalogIds: cat, prevVersion: 1, force: true }).errors.some((e) => />90%/.test(e)));
});
test('validateConfig: announcement, endpoint, size, flags', () => {
  assert.ok(validateAnnouncement({ enabled: true, text: '', id: 'a1', level: 'info' }).length);
  assert.ok(validateAnnouncement({ enabled: false, text: 'x', id: 'a1', level: 'bogus' }).length);
  assert.deepEqual(validateEndpointUrl('https://granth-ai.vedpuran8090.workers.dev', 'e'), []);
  assert.ok(validateEndpointUrl('http://insecure', 'e').length);
  const big = mkCfg(); big.structure.note = 'x'.repeat(70000);
  assert.ok(validateConfig(big, { catalogIds: cat, prevVersion: 1 }).errors.some((e) => /64 KB/.test(e)));
  const f = mkCfg(); f.flags.analytics_sample = 2; assert.ok(validateConfig(f, { catalogIds: cat, prevVersion: 1 }).errors.length);
});
test('structure validation: ids immutable-format, dup ids, hide all', () => {
  const s = bootstrapStructure(); s.religions[0].id = 'Bad Id'; assert.ok(validateStructure(s).length);
  const d = bootstrapStructure(); d.religions[1].id = d.religions[0].id; assert.ok(validateStructure(d).some((e) => /duplicate/.test(e)));
  const h = bootstrapStructure(); h.religions.forEach((r) => { r.visible = false; }); assert.ok(validateStructure(h).some((e) => /visible/.test(e)));
});

test('canonical JSON sorts keys and is stable', () => {
  assert.equal(canonical({ b: 1, a: [2, { d: 1, c: undefined }], s: 'हिं' }), '{"a":[2,{"d":1}],"b":1,"s":"हिं"}');
  assert.equal(clampInt(NaN, 0, 5), null); assert.equal(clampInt(9.9, 0, 5), 5);
});
test('Ed25519 signature over canonical JSON verifies', async () => {
  const kp = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
  const cfg = mkCfg(); const bytes = new TextEncoder().encode(canonical(cfg));
  const sig = await crypto.subtle.sign({ name: 'Ed25519' }, kp.privateKey, bytes);
  // key order of the served JSON must not matter
  const shuffled = Object.fromEntries(Object.entries(cfg).reverse());
  assert.ok(await crypto.subtle.verify({ name: 'Ed25519' }, kp.publicKey, sig, new TextEncoder().encode(canonical(shuffled))));
  assert.ok(!(await crypto.subtle.verify({ name: 'Ed25519' }, kp.publicKey, sig, new TextEncoder().encode(canonical({ ...cfg, version: 3 })))));
});

// ---- contacts ----
import { validateContacts, normalizeState, defaultContacts, PHONE_RE } from '../../src/structure.js';
import { makeComparator, SORT_ALIASES } from '../../src/admin.js';
import { passwordProblem } from '../../src/auth.js';
test('seeded contacts: 4 names in order, empty phones, whatsapp false, visible; config validates', () => {
  const c = defaultContacts();
  assert.deepEqual(c.map((x) => x.name), ['अमित दास', 'रामेश्वर दर', 'गौतम दास', 'अशोक दास']);
  assert.ok(c.every((x) => x.phone === '' && x.whatsapp === false && x.visible === true));
  assert.deepEqual(c.map((x) => x.order), [1, 2, 3, 4]);
  assert.deepEqual(validateConfig(mkCfg(), { catalogIds: cat, prevVersion: 1 }).errors, []);
  const cfg = mkCfg(); assert.equal(cfg.contacts_page.title, 'विशेष जानकार'); assert.equal(cfg.contacts.length, 4);
});
test('old snapshots without contacts normalise to the seeded list', () => {
  const st = normalizeState({ structure: bootstrapStructure(), hidden_granth_ids: [], overrides: {}, flags: {} });
  assert.equal(st.contacts.length, 4);
});
test('validateContacts: ids unique, name required ≤80, phone format, max 50, whatsapp needs phone', () => {
  const page = { title: 'x' }; const ok = defaultContacts();
  assert.deepEqual(validateContacts(page, ok), []);
  const withP = (p) => [{ ...ok[0], phone: p }];
  for (const good of ['', '9876543210', '+919876543210']) assert.deepEqual(validateContacts(page, withP(good)), [], good);
  for (const bad of ['98 76', 'abc', '98-76', '++91', '91+1', '1'.repeat(21), '+' + '1'.repeat(20)]) assert.ok(validateContacts(page, withP(bad)).length, bad);
  assert.ok(validateContacts(page, [ok[0], { ...ok[1], id: ok[0].id }]).some((e) => /duplicated/.test(e)));
  assert.ok(validateContacts(page, [{ ...ok[0], name: '' }]).length);
  assert.ok(validateContacts(page, [{ ...ok[0], name: 'a'.repeat(81) }]).length);
  assert.ok(validateContacts(page, [{ ...ok[0], whatsapp: true }]).some((e) => /whatsapp needs/.test(e)));
  assert.deepEqual(validateContacts(page, [{ ...ok[0], whatsapp: true, phone: '9876543210' }]), []);
  const many = Array.from({ length: 51 }, (_, i) => ({ ...ok[0], id: 'c' + i, order: i + 1 }));
  assert.ok(validateContacts(page, many).some((e) => /at most 50/.test(e)));
  assert.ok(validateContacts({ title: '' }, ok).length && validateContacts({ title: 'a'.repeat(61) }, ok).length);
});
// ---- sort ----
const G = (id, position, o = {}) => ({ id, position, title: 't' + id, praman_count: 0, opens_7d: 0, watch_s_7d: 0, created_at: '2026-01-01 00:00:00', ...o });
test('granth sort: default number asc starts at #1; desc reverses; ties and missing position are stable', () => {
  const items = [G('50', 1), G('4', 2), G('7', 3), G('55', 4), G('9', null), G('3', 10)];
  const sorted = (k, o) => [...items].sort(makeComparator(SORT_ALIASES[k], o)).map((x) => x.id);
  assert.deepEqual(sorted('number', 'asc'), ['50', '4', '7', '55', '3', '9']); // missing position last
  assert.deepEqual(sorted('position', 'asc'), sorted('number', 'asc'));
  assert.deepEqual(sorted('id', 'asc'), ['3', '4', '7', '9', '50', '55']);
  assert.deepEqual(sorted('id', 'desc'), ['55', '50', '9', '7', '4', '3']);
  const by = [G('1', 1, { opens_7d: 5, praman_count: 2, watch_s_7d: 9, created_at: '2026-03-01 00:00:00' }), G('2', 2, { opens_7d: 9, praman_count: 7, watch_s_7d: 1, created_at: '2026-02-01 00:00:00' }), G('3', 3, { opens_7d: 5, praman_count: 7, watch_s_7d: 5, created_at: '2026-04-01 00:00:00' })];
  const s2 = (k, o) => [...by].sort(makeComparator(SORT_ALIASES[k], o)).map((x) => x.id);
  assert.deepEqual(s2('opens', 'desc'), ['2', '1', '3']); // tie 1/3 → position asc
  assert.deepEqual(s2('praman', 'desc'), ['2', '3', '1']);
  assert.deepEqual(s2('watch', 'desc'), ['1', '3', '2']);
  assert.deepEqual(s2('newest', 'desc'), ['3', '1', '2']);
  assert.deepEqual(s2('newest', 'asc'), ['2', '1', '3']);
  assert.deepEqual(s2('title', 'asc'), ['1', '2', '3']);
});
test('password policy: min 10, ≤256, not the username', () => {
  assert.ok(passwordProblem('short', 'x')); assert.ok(passwordProblem('a'.repeat(257), 'x')); assert.ok(passwordProblem('Goutam1234', 'goutam1234'));
  assert.equal(passwordProblem('exactly-10', 'x'), null);
});
