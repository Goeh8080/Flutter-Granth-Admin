// Structure helpers: bundled baseline, leaf keys, the app's placement algorithm (ported from
// Flutter-Granth lib/models/structure.dart ShelfIndex.build) and validation (plan §5.2).
import bundled from './bundled_structure.json' with { type: 'json' };
import { ID_RE, numCmp } from './util.js';

export const OTHER = 'other';
export const GROUP_ICONS = ['scroll', 'book-red', 'book-green', 'book-blue', 'book-orange', 'swords', 'books', 'quran', 'hadees', 'granth-sahib', 'dasam', 'bible', 'tripitak', 'dhammapad', 'kabir-sagar', 'bijak', 'shabdavali', 'misc'];
export const RELIGION_ICONS = ['om', 'crescent', 'khanda', 'cross', 'dharma', 'ektara', 'misc'];
export const TONES = ['saffron', 'maroon', 'gold'];
const SLUG = /^[a-z0-9][a-z0-9_-]{0,39}$/;

/** Bundled structure.json + जैन (the only difference from the app's asset). */
export function bootstrapStructure() {
  const s = JSON.parse(JSON.stringify(bundled));
  if (!s.religions.some((r) => r.id === 'jain')) {
    s.religions.push({
      id: 'jain', title: 'जैन', tone: 'saffron', icon: 'misc',
      groups: [
        { id: 'agam', title: 'आगम', icon: 'scroll', granthIds: [], keywords: ['आगम', 'जैन', 'महावीर'] },
        { id: 'tattvarth', title: 'तत्त्वार्थ सूत्र', icon: 'book-blue', granthIds: [], keywords: ['तत्त्वार्थ', 'तत्वार्थ'] },
      ],
    });
  }
  return s;
}
export function bootstrapState() {
  return normalizeState({ structure: bootstrapStructure(), hidden_granth_ids: [], overrides: {}, flags: {} });
}
export const DEFAULT_AI_ENDPOINT = 'https://granth-ai.vedpuran8090.workers.dev';
export const ANNOUNCE_LEVELS = ['info', 'warn', 'critical'];
export function defaultAnnouncement() { return { enabled: false, text: '', id: 'a0', level: 'info' }; }
// ---- contacts ("विशेष जानकार") ---------------------------------------------------------------------
export const CONTACTS_MAX = 50;
export const CONTACT_ID_RE = /^[A-Za-z0-9_-]{1,40}$/;
export const PHONE_RE = /^(\+[0-9]{1,19}|[0-9]{1,20})?$/; // '' = no phone; else optional leading '+' then digits; ≤20 chars total
export function defaultContactsPage() { return { title: 'विशेष जानकार' }; }
export function defaultContacts() {
  return ['अमित दास', 'रामेश्वर दर', 'गौतम दास', 'अशोक दास'].map((name, i) => ({ id: `c${i + 1}`, name, role: '', phone: '', whatsapp: false, order: i + 1, visible: true }));
}
/** Canonical key order + defaults; trims strings. Does not validate (see validateContacts). */
export function cleanContact(c, fallbackOrder) {
  const x = c && typeof c === 'object' ? c : {};
  const str = (v) => (typeof v === 'string' ? v.trim() : v === undefined || v === null ? '' : v);
  return { id: str(x.id), name: str(x.name), role: str(x.role), phone: typeof x.phone === 'string' ? x.phone.replace(/[\s-]/g, '') : str(x.phone), whatsapp: x.whatsapp === undefined ? false : x.whatsapp, order: x.order === undefined ? fallbackOrder : x.order, visible: x.visible === undefined ? true : x.visible };
}
export function normalizeContacts(list) {
  const arr = Array.isArray(list) ? list : defaultContacts();
  return arr.map((c, i) => cleanContact(c, i + 1)).sort((a, b) => (a.order - b.order) || 0);
}
export function validateContacts(page, list) {
  const errs = [];
  if (!page || typeof page !== 'object') errs.push('contacts_page must be an object');
  else if (typeof page.title !== 'string' || !page.title.trim() || page.title.length > 60) errs.push('contacts_page.title must be a non-empty string ≤60 chars');
  if (!Array.isArray(list)) return [...errs, 'contacts must be an array'];
  if (list.length > CONTACTS_MAX) errs.push(`at most ${CONTACTS_MAX} contacts`);
  const ids = new Set(), orders = new Set();
  list.forEach((c, i) => {
    const w = `contacts[${i}]`;
    if (!c || typeof c !== 'object') { errs.push(`${w} must be an object`); return; }
    if (typeof c.id !== 'string' || !CONTACT_ID_RE.test(c.id)) errs.push(`${w}.id must match [A-Za-z0-9_-]{1,40}`);
    else if (c.id === 'reorder') errs.push(`${w}.id "reorder" is reserved`);
    else if (ids.has(c.id)) errs.push(`${w}.id "${c.id}" is duplicated`); else ids.add(c.id);
    if (typeof c.name !== 'string' || !c.name.trim() || c.name.length > 80) errs.push(`${w}.name is required (≤80 chars)`);
    if (typeof c.role !== 'string' || c.role.length > 80) errs.push(`${w}.role must be a string ≤80 chars`);
    if (typeof c.phone !== 'string' || !PHONE_RE.test(c.phone)) errs.push(`${w}.phone must be digits with an optional leading + (max 20 chars)`);
    if (typeof c.whatsapp !== 'boolean') errs.push(`${w}.whatsapp must be boolean`);
    else if (c.whatsapp && !c.phone) errs.push(`${w}.whatsapp needs a phone number`);
    if (!Number.isInteger(c.order) || c.order < 1) errs.push(`${w}.order must be an integer ≥1`);
    else if (orders.has(c.order)) errs.push(`${w}.order ${c.order} is duplicated`); else orders.add(c.order);
    if (typeof c.visible !== 'boolean') errs.push(`${w}.visible must be boolean`);
  });
  return errs;
}
/** Fill in defaults so every stored state has the full shape (older snapshots stay valid). */
export function normalizeState(st) {
  const flags = { ai_enabled: true, analytics_enabled: true, analytics_sample: 1, ...(st.flags || {}) };
  delete flags.max_hidden_pct; // derived at publish time
  return {
    structure: st.structure,
    hidden_granth_ids: st.hidden_granth_ids || [],
    overrides: st.overrides || {},
    flags,
    announcement: { ...defaultAnnouncement(), ...(st.announcement || {}) },
    ai_endpoint: st.ai_endpoint === undefined ? DEFAULT_AI_ENDPOINT : st.ai_endpoint,
    contacts_page: { ...defaultContactsPage(), ...(st.contacts_page || {}) },
    contacts: normalizeContacts(st.contacts), // older snapshots without contacts get the seeded list
  };
}
export function validateAnnouncement(a) {
  const errs = [];
  if (!a || typeof a !== 'object') return ['announcement must be an object'];
  if (typeof a.enabled !== 'boolean') errs.push('announcement.enabled must be boolean');
  if (typeof a.text !== 'string' || a.text.length > 280) errs.push('announcement.text must be a string ≤280 chars');
  if (a.enabled && !String(a.text).trim()) errs.push('announcement.text is empty but enabled');
  if (typeof a.id !== 'string' || !/^[A-Za-z0-9_-]{1,40}$/.test(a.id)) errs.push('announcement.id must match [A-Za-z0-9_-]{1,40}');
  if (!ANNOUNCE_LEVELS.includes(a.level)) errs.push(`announcement.level must be one of ${ANNOUNCE_LEVELS}`);
  if (a.expires_at !== undefined && a.expires_at !== null && (typeof a.expires_at !== 'string' || !Number.isFinite(Date.parse(a.expires_at)))) errs.push('announcement.expires_at must be an ISO-8601 string');
  return errs;
}
export function validateEndpointUrl(u, name) {
  if (u === '' || u === undefined || u === null) return [];
  if (typeof u !== 'string' || u.length > 200 || !/^https:\/\/[A-Za-z0-9.-]+(:\d+)?(\/[^\s?#]*)?$/.test(u)) return [`${name} must be an https URL (≤200 chars) or empty`];
  return [];
}

export function fold(e) {
  let s = String(e).normalize('NFD').replace(/\u093c/g, '').replace(/\u200c/g, '').replace(/\u200d/g, '').replace(/\u0901/g, '\u0902');
  return s.normalize('NFC').toLowerCase().replace(/\s+/g, ' ').trim();
}

/** [{key, religion, parent, leaf, label}] — leaf groups and sub-groups. */
export function leaves(structure) {
  const out = [];
  for (const r of structure.religions || []) {
    for (const g of r.groups || []) {
      if (g.subgroups && g.subgroups.length) {
        for (const s of g.subgroups) out.push({ key: `${r.id}/${g.id}/${s.id}`, religion: r, parent: g, leaf: s, label: `${r.title} › ${g.title} › ${s.title}` });
      } else out.push({ key: `${r.id}/${g.id}`, religion: r, parent: null, leaf: g, label: `${r.title} › ${g.title}` });
    }
  }
  return out;
}
export function leafKeySet(structure) { return new Set([OTHER, ...leaves(structure).map((l) => l.key)]); }

/** Where each granth sits: {id: {key, how}} how = override | id | forced | keyword | fallback. */
export function placements(structure, overrides, granthRows) {
  const ls = leaves(structure);
  const byId = new Map();
  for (const l of ls) for (const id of l.leaf.granthIds || []) if (!byId.has(String(id))) byId.set(String(id), l.key);
  const forced = new Set((structure.other?.forceIds || structure.other?.granthIds || []).map(String));
  const folded = ls.map((l) => ({ key: l.key, kw: (l.leaf.keywords || []).map(fold), no: (l.leaf.notKeywords || []).map(fold) }));
  const keys = leafKeySet(structure);
  const out = {};
  for (const g of granthRows) {
    const ov = overrides?.[g.id]?.leaf;
    if (ov && keys.has(ov)) { out[g.id] = { key: ov, how: 'override' }; continue; }
    if (byId.has(g.id)) { out[g.id] = { key: byId.get(g.id), how: 'id' }; continue; }
    if (forced.has(g.id)) { out[g.id] = { key: OTHER, how: 'forced' }; continue; }
    const t = fold(g.title || '');
    const hits = folded.filter((f) => f.kw.some((k) => k && t.includes(k)) && !f.no.some((k) => k && t.includes(k))).map((f) => f.key);
    out[g.id] = hits.length === 1 ? { key: hits[0], how: 'keyword' } : { key: OTHER, how: 'fallback' };
  }
  return out;
}
export function sourceLabel(how) { return how === 'id' || how === 'forced' ? 'bundled' : how; }

/** Validate a structure object. Returns an array of error strings (empty = ok). */
export function validateStructure(s) {
  const errs = [];
  if (!s || typeof s !== 'object' || !Array.isArray(s.religions)) return ['structure.religions missing'];
  if (s.religions.length === 0) errs.push('structure has 0 religions');
  const rIds = new Set();
  const title = (o, where) => {
    if (typeof o.title !== 'string' || !o.title.trim() || o.title.length > 60) errs.push(`${where}: title must be 1-60 chars`);
    if (o.visible !== undefined && typeof o.visible !== 'boolean') errs.push(`${where}: visible must be boolean`);
    if (o.coming_soon !== undefined && (typeof o.coming_soon !== 'string' || o.coming_soon.length > 200)) errs.push(`${where}: coming_soon must be a string ≤200 chars`);
  };
  for (const r of s.religions) {
    if (!r || typeof r.id !== 'string' || !SLUG.test(r.id) || r.id === OTHER) { errs.push(`religion id invalid: ${r && r.id}`); continue; }
    if (rIds.has(r.id)) errs.push(`duplicate religion id ${r.id}`);
    rIds.add(r.id);
    title(r, `religion ${r.id}`);
    if (r.tone !== undefined && !TONES.includes(r.tone)) errs.push(`religion ${r.id}: tone must be one of ${TONES}`);
    if (r.icon !== undefined && !RELIGION_ICONS.includes(r.icon)) errs.push(`religion ${r.id}: unknown icon ${r.icon}`);
    if (!Array.isArray(r.groups)) { errs.push(`religion ${r.id}: groups must be an array`); continue; }
    const gIds = new Set();
    for (const g of r.groups) {
      if (!g || typeof g.id !== 'string' || !SLUG.test(g.id)) { errs.push(`group id invalid in ${r.id}: ${g && g.id}`); continue; }
      if (gIds.has(g.id)) errs.push(`duplicate group id ${r.id}/${g.id}`);
      gIds.add(g.id);
      title(g, `group ${r.id}/${g.id}`);
      if (g.icon !== undefined && !GROUP_ICONS.includes(g.icon)) errs.push(`group ${r.id}/${g.id}: unknown icon ${g.icon}`);
      for (const k of ['granthIds', 'keywords', 'notKeywords']) if (g[k] !== undefined && !Array.isArray(g[k])) errs.push(`group ${r.id}/${g.id}: ${k} must be an array`);
      for (const id of g.granthIds || []) if (typeof id !== 'string' || !ID_RE.test(id)) errs.push(`group ${r.id}/${g.id}: bad granth id ${id}`);
      if (g.subgroups !== undefined) {
        if (!Array.isArray(g.subgroups)) { errs.push(`group ${r.id}/${g.id}: subgroups must be an array`); continue; }
        const sIds = new Set();
        for (const sg of g.subgroups) {
          if (!sg || typeof sg.id !== 'string' || !SLUG.test(sg.id)) { errs.push(`subgroup id invalid in ${r.id}/${g.id}`); continue; }
          if (sIds.has(sg.id)) errs.push(`duplicate subgroup id ${r.id}/${g.id}/${sg.id}`);
          sIds.add(sg.id);
          title(sg, `subgroup ${r.id}/${g.id}/${sg.id}`);
          if (sg.icon !== undefined && !GROUP_ICONS.includes(sg.icon)) errs.push(`subgroup ${sg.id}: unknown icon ${sg.icon}`);
          for (const id of sg.granthIds || []) if (typeof id !== 'string' || !ID_RE.test(id)) errs.push(`subgroup ${sg.id}: bad granth id ${id}`);
        }
      }
    }
  }
  if (s.religions.length && !s.religions.some((r) => r && r.visible !== false)) errs.push('at least one religion must be visible');
  if (!s.other || s.other.id !== OTHER) errs.push('structure.other (id "other") missing');
  else if (s.other.coming_soon !== undefined && (typeof s.other.coming_soon !== 'string' || s.other.coming_soon.length > 200)) errs.push('other.coming_soon must be a string ≤200 chars');
  if (s.other && s.other.id === OTHER) for (const id of s.other.forceIds || []) if (typeof id !== 'string' || !ID_RE.test(id)) errs.push(`other.forceIds: bad id ${id}`);
  return errs;
}

/**
 * Server-side validation of a full config object (plan §5.2). `catalogIds` = ids currently in Ashok's catalog.
 * prevVersion = highest published version (new version must be higher). Returns {errors, warnings}.
 */
export function validateConfig(cfg, { catalogIds, prevVersion, force = false }) {
  const errors = [], warnings = [];
  const text = JSON.stringify(cfg);
  if (new TextEncoder().encode(text).length > 64 * 1024) errors.push('config larger than 64 KB');
  if (cfg.schema !== 1) errors.push('schema must be 1');
  if (!Number.isInteger(cfg.version) || cfg.version <= (prevVersion || 0)) errors.push(`version ${cfg.version} must be higher than ${prevVersion}`);
  errors.push(...validateStructure(cfg.structure));
  const keys = new Set([OTHER]);
  if (cfg.structure && Array.isArray(cfg.structure.religions)) for (const l of leaves(cfg.structure)) keys.add(l.key);
  for (const [id, ov] of Object.entries(cfg.overrides || {})) {
    if (!ID_RE.test(id)) errors.push(`override id ${id} is not ≤8 digits`);
    if (!ov || typeof ov.leaf !== 'string' || !keys.has(ov.leaf)) errors.push(`override ${id}: leaf "${ov && ov.leaf}" not in structure`);
  }
  const hidden = cfg.hidden_granth_ids || [];
  if (!Array.isArray(hidden)) errors.push('hidden_granth_ids must be an array');
  else {
    for (const id of hidden) if (typeof id !== 'string' || !ID_RE.test(id)) errors.push(`hidden id ${id} invalid`);
    if (new Set(hidden).size !== hidden.length) errors.push('hidden_granth_ids has duplicates');
    const total = catalogIds.size || 0;
    if (total > 0) {
      const inCat = hidden.filter((id) => catalogIds.has(id)).length;
      const pct = (inCat / total) * 100;
      const limit = cfg.flags?.max_hidden_pct ?? 50;
      if (pct > 90) errors.push(`hides ${inCat} of ${total} granths (>90%) — never allowed`);
      else if (pct > 50 && !force) errors.push(`hides ${inCat} of ${total} granths (>50%) — needs force`);
      else if (pct > 50 && force && limit < 90) errors.push('force publish must set flags.max_hidden_pct to 90');
      if (hidden.length - inCat > 0) warnings.push(`${hidden.length - inCat} hidden id(s) are not in the current catalog`);
    }
  }
  for (const id of cfg.unassigned_seen || []) if (typeof id !== 'string' || !ID_RE.test(id)) errors.push(`unassigned_seen id ${id} invalid`);
  const f = cfg.flags || {};
  if (typeof f.ai_enabled !== 'boolean' || typeof f.analytics_enabled !== 'boolean') errors.push('flags.ai_enabled / analytics_enabled must be boolean');
  errors.push(...validateAnnouncement(cfg.announcement));
  errors.push(...validateContacts(cfg.contacts_page, cfg.contacts));
  errors.push(...validateEndpointUrl(cfg.endpoints?.ai, 'endpoints.ai'));
  if (typeof f.analytics_sample !== 'number' || f.analytics_sample < 0 || f.analytics_sample > 1) errors.push('flags.analytics_sample must be 0..1');
  return { errors, warnings };
}
export { numCmp };
