// "विशेष जानकार" contacts editor (/admin/api/contacts*). Edits go to the draft like everything else.
import { json } from './util.js';
import { getDraft, saveDraft, latestVersion } from './config.js';
import { audit } from './audit.js';
import { cleanContact, validateContacts, CONTACTS_MAX } from './structure.js';

const fail = (status, error, extra = {}) => json({ error, ...extra }, status);
async function body(request) { try { const b = await request.json(); return b && typeof b === 'object' && !Array.isArray(b) ? b : null; } catch { return null; } }
const genId = () => 'c' + [...crypto.getRandomValues(new Uint8Array(4))].map((x) => x.toString(16).padStart(2, '0')).join('');
const FIELDS = ['name', 'role', 'phone', 'whatsapp', 'visible'];

async function view(env, d, extra = {}) {
  const pub = await latestVersion(env);
  return { page: d.state.contacts_page, items: d.state.contacts, max_contacts: CONTACTS_MAX, has_draft: true, base_version: pub.version, next_version: pub.version + 1, ...extra };
}
function renumber(list) { return list.map((c, i) => ({ ...c, order: i + 1 })); }
async function commit(env, d, state, actor, action, detail) {
  const errs = validateContacts(state.contacts_page, state.contacts);
  if (errs.length) return fail(422, 'invalid_contacts', { errors: errs.slice(0, 10) });
  await saveDraft(env, state, actor);
  await audit(env, actor, 'contacts_edit', { action, ...detail }); // never log phone numbers
  return null;
}

/** Returns a Response, or null when path is not a /contacts route. */
export async function handleContacts(request, env, actor, path, method) {
  const m = path.match(/^\/contacts(?:\/([A-Za-z0-9_-]{1,40}))?$/);
  if (!m) return null;
  const id = m[1];
  const d = await getDraft(env); const st = d.state;

  if (!id && method === 'GET') {
    const pub = await latestVersion(env);
    return json({ page: st.contacts_page, items: st.contacts, max_contacts: CONTACTS_MAX, has_draft: d.exists, base_version: pub.version, next_version: pub.version + 1 });
  }
  if (!id && method === 'PUT') { // replace title and/or the whole list; array order = display order
    const b = await body(request); if (!b) return fail(400, 'bad_request');
    if (!('title' in b) && !('items' in b)) return fail(422, 'nothing_to_change');
    if ('title' in b) { if (typeof b.title !== 'string') return fail(422, 'invalid_contacts', { errors: ['title must be a string'] }); st.contacts_page = { ...st.contacts_page, title: b.title.trim() }; }
    if ('items' in b) {
      if (!Array.isArray(b.items)) return fail(422, 'invalid_contacts', { errors: ['items must be an array'] });
      if (b.items.length > CONTACTS_MAX) return fail(422, 'invalid_contacts', { errors: [`at most ${CONTACTS_MAX} contacts`] });
      const used = new Set(b.items.map((x) => x && typeof x.id === 'string' ? x.id.trim() : '').filter(Boolean));
      st.contacts = renumber(b.items.map((x, i) => { const c = cleanContact(x, i + 1); if (!c.id) { let g; do g = genId(); while (used.has(g)); used.add(g); c.id = g; } return c; }));
    }
    const bad = await commit(env, d, st, actor, 'replace', { count: st.contacts.length, title: st.contacts_page.title }); if (bad) return bad;
    return json({ ok: true, ...(await view(env, { state: st })) });
  }
  if (!id && method === 'POST') {
    const b = await body(request); if (!b) return fail(400, 'bad_request');
    if (st.contacts.length >= CONTACTS_MAX) return fail(422, 'invalid_contacts', { errors: [`at most ${CONTACTS_MAX} contacts`] });
    let gid; do gid = genId(); while (st.contacts.some((c) => c.id === gid));
    const c = cleanContact({ ...b, id: gid, order: st.contacts.length + 1 }, st.contacts.length + 1);
    st.contacts = [...st.contacts, c];
    const bad = await commit(env, d, st, actor, 'add', { id: c.id, name: c.name }); if (bad) return bad;
    return json({ ok: true, contact: c, ...(await view(env, { state: st })) }, 201);
  }
  if (id === 'reorder' && method === 'POST') {
    const b = await body(request);
    if (!b || !Array.isArray(b.ids)) return fail(400, 'bad_request');
    const cur = new Map(st.contacts.map((c) => [c.id, c]));
    if (b.ids.length !== cur.size || new Set(b.ids).size !== cur.size || b.ids.some((x) => !cur.has(x))) return fail(422, 'invalid_contacts', { errors: ['ids must list every contact id exactly once'] });
    st.contacts = renumber(b.ids.map((x) => cur.get(x)));
    const bad = await commit(env, d, st, actor, 'reorder', { count: st.contacts.length }); if (bad) return bad;
    return json({ ok: true, ...(await view(env, { state: st })) });
  }
  if (id && method === 'PUT') {
    const b = await body(request); if (!b) return fail(400, 'bad_request');
    const i = st.contacts.findIndex((c) => c.id === id); if (i < 0) return fail(404, 'contact_not_found');
    if (!FIELDS.some((f) => f in b)) return fail(422, 'nothing_to_change');
    const merged = { ...st.contacts[i] }; for (const f of FIELDS) if (f in b) merged[f] = b[f];
    st.contacts = st.contacts.map((c, k) => (k === i ? { ...cleanContact(merged, c.order), id } : c));
    const bad = await commit(env, d, st, actor, 'edit', { id, fields: FIELDS.filter((f) => f in b) }); if (bad) return bad;
    return json({ ok: true, contact: st.contacts[i], ...(await view(env, { state: st })) });
  }
  if (id && method === 'DELETE') {
    const i = st.contacts.findIndex((c) => c.id === id); if (i < 0) return fail(404, 'contact_not_found');
    const gone = st.contacts[i];
    st.contacts = renumber(st.contacts.filter((c) => c.id !== id));
    const bad = await commit(env, d, st, actor, 'delete', { id, name: gone.name }); if (bad) return bad;
    return json({ ok: true, ...(await view(env, { state: st })) });
  }
  return fail(405, 'method_not_allowed');
}
