// Admin account management (/admin/api/admins*). Owner role only. Passwords are never returned or logged.
import { json, nowIso, nowSec } from './util.js';
import { makePasswordRecord, passwordProblem } from './auth.js';
import { audit } from './audit.js';

const ROLES = ['owner', 'admin'];
const USERNAME_RE = /^[a-z0-9][a-z0-9_.-]{2,31}$/;
const fail = (status, error, extra = {}) => json({ error, ...extra }, status);
async function body(request) { try { const b = await request.json(); return b && typeof b === 'object' && !Array.isArray(b) ? b : null; } catch { return null; } }

const shape = (r, me) => ({
  username: r.username, role: r.role, disabled: !!r.disabled, created_at: r.created_at, updated_at: r.updated_at, created_by: r.created_by || null,
  active_sessions: r.active_sessions || 0, last_seen: r.last_seen ? new Date(r.last_seen * 1000).toISOString() : null, you: r.username === me,
});
async function getOne(env, username, me) {
  const r = await env.DB.prepare(`SELECT a.username, a.role, a.disabled, a.created_at, a.updated_at, a.created_by,
    (SELECT COUNT(*) FROM sessions s WHERE s.username = a.username AND s.expires_at > ?) AS active_sessions,
    (SELECT MAX(s.last_seen) FROM sessions s WHERE s.username = a.username) AS last_seen FROM admins a WHERE a.username = ?`).bind(nowSec(), username).first();
  return r ? shape(r, me) : null;
}
const otherActiveOwners = async (env, username) => (await env.DB.prepare("SELECT COUNT(*) AS n FROM admins WHERE role = 'owner' AND disabled = 0 AND username != ?").bind(username).first()).n;

/** Returns a Response, or null when the path is not an /admins route. */
export async function handleAdmins(request, env, session, path, method) {
  const isList = path === '/admins';
  const mOne = path.match(/^\/admins\/([a-z0-9][a-z0-9_.-]{0,40})$/), mPw = path.match(/^\/admins\/([a-z0-9][a-z0-9_.-]{0,40})\/password$/), mRev = path.match(/^\/admins\/([a-z0-9][a-z0-9_.-]{0,40})\/revoke_sessions$/);
  if (!(path === '/admins' || mOne || mPw || mRev)) return null;
  if (session.role !== 'owner') return fail(403, 'forbidden', { message: 'only an owner can manage admins' });
  const me = session.username;

  if (isList && method === 'GET') {
    const r = await env.DB.prepare(`SELECT a.username, a.role, a.disabled, a.created_at, a.updated_at, a.created_by,
      (SELECT COUNT(*) FROM sessions s WHERE s.username = a.username AND s.expires_at > ?) AS active_sessions,
      (SELECT MAX(s.last_seen) FROM sessions s WHERE s.username = a.username) AS last_seen
      FROM admins a ORDER BY (a.role = 'owner') DESC, a.created_at ASC, a.username ASC`).bind(nowSec()).all();
    return json({ items: r.results.map((x) => shape(x, me)), count: r.results.length, roles: ROLES, min_password_length: 10 });
  }
  if (isList && method === 'POST') {
    const b = await body(request); if (!b) return fail(400, 'bad_request');
    const username = typeof b.username === 'string' ? b.username.trim().toLowerCase() : '';
    if (!USERNAME_RE.test(username)) return fail(422, 'bad_username', { message: 'username: 3–32 chars, a-z 0-9 . _ - (start with a letter or digit)' });
    const role = b.role === undefined ? 'admin' : b.role;
    if (!ROLES.includes(role)) return fail(422, 'bad_role', { message: `role must be one of ${ROLES.join(', ')}` });
    const weak = passwordProblem(b.password, username); if (weak) return fail(422, 'weak_password', { message: weak });
    if (await env.DB.prepare('SELECT 1 AS x FROM admins WHERE username = ?').bind(username).first()) return fail(409, 'username_taken');
    const rec = await makePasswordRecord(b.password, Number(env.PBKDF2_ITERS) || 50000), now = nowIso();
    try {
      await env.DB.prepare('INSERT INTO admins (username, pw_hash, salt, iters, created_at, updated_at, role, disabled, created_by) VALUES (?,?,?,?,?,?,?,0,?)').bind(username, rec.pw_hash, rec.salt, rec.iters, now, now, role, me).run();
    } catch { return fail(409, 'username_taken'); }
    await audit(env, me, 'admin_create', { username, role });
    return json({ ok: true, admin: await getOne(env, username, me) }, 201);
  }
  if (mOne && method === 'GET') {
    const a = await getOne(env, mOne[1], me); return a ? json({ admin: a }) : fail(404, 'admin_not_found');
  }
  if (mOne && method === 'PUT') {
    const u = mOne[1];
    const b = await body(request); if (!b) return fail(400, 'bad_request');
    const cur = await env.DB.prepare('SELECT username, role, disabled FROM admins WHERE username = ?').bind(u).first();
    if (!cur) return fail(404, 'admin_not_found');
    const changes = {};
    if ('role' in b) { if (!ROLES.includes(b.role)) return fail(422, 'bad_role'); if (b.role !== cur.role) changes.role = b.role; }
    if ('disabled' in b) { if (typeof b.disabled !== 'boolean') return fail(422, 'bad_disabled'); if (b.disabled !== !!cur.disabled) changes.disabled = b.disabled; }
    if (!('role' in b) && !('disabled' in b)) return fail(422, 'nothing_to_change');
    if (u === me && Object.keys(changes).length) return fail(409, 'cannot_modify_self', { message: 'you cannot change your own role or disable yourself' });
    const losesOwner = cur.role === 'owner' && !cur.disabled && ((changes.role && changes.role !== 'owner') || changes.disabled === true);
    if (losesOwner && (await otherActiveOwners(env, u)) < 1) return fail(409, 'last_owner', { message: 'at least one active owner must remain' });
    if (Object.keys(changes).length) {
      const stmts = [env.DB.prepare('UPDATE admins SET role = ?, disabled = ?, updated_at = ? WHERE username = ?').bind(changes.role ?? cur.role, (changes.disabled ?? !!cur.disabled) ? 1 : 0, nowIso(), u)];
      if (changes.disabled === true) stmts.push(env.DB.prepare('DELETE FROM sessions WHERE username = ?').bind(u)); // disable → sessions revoked (role is read live per request)
      await env.DB.batch(stmts);
      await audit(env, me, 'admin_update', { username: u, ...changes });
    }
    return json({ ok: true, admin: await getOne(env, u, me) });
  }
  if (mPw && method === 'POST') {
    const u = mPw[1];
    if (u === me) return fail(409, 'use_change_password', { message: 'use POST /admin/api/password to change your own password' });
    const b = await body(request); if (!b) return fail(400, 'bad_request');
    if (!(await env.DB.prepare('SELECT 1 AS x FROM admins WHERE username = ?').bind(u).first())) return fail(404, 'admin_not_found');
    const weak = passwordProblem(b.password, u); if (weak) return fail(422, 'weak_password', { message: weak });
    const rec = await makePasswordRecord(b.password, Number(env.PBKDF2_ITERS) || 50000);
    await env.DB.batch([
      env.DB.prepare('UPDATE admins SET pw_hash = ?, salt = ?, iters = ?, updated_at = ? WHERE username = ?').bind(rec.pw_hash, rec.salt, rec.iters, nowIso(), u),
      env.DB.prepare('DELETE FROM sessions WHERE username = ?').bind(u),
    ]);
    await audit(env, me, 'admin_password_reset', { username: u });
    return json({ ok: true });
  }
  if (mRev && method === 'POST') {
    const u = mRev[1];
    if (u === me) return fail(409, 'cannot_modify_self', { message: 'use POST /admin/api/sessions/revoke_all for your own sessions' });
    if (!(await env.DB.prepare('SELECT 1 AS x FROM admins WHERE username = ?').bind(u).first())) return fail(404, 'admin_not_found');
    const r = await env.DB.prepare('DELETE FROM sessions WHERE username = ?').bind(u).run();
    await audit(env, me, 'admin_sessions_revoke', { username: u, n: r.meta?.changes ?? null });
    return json({ ok: true, revoked: r.meta?.changes ?? 0 });
  }
  if (mOne && method === 'DELETE') {
    const u = mOne[1];
    if (u === me) return fail(409, 'cannot_modify_self', { message: 'you cannot delete yourself' });
    const cur = await env.DB.prepare('SELECT role, disabled FROM admins WHERE username = ?').bind(u).first();
    if (!cur) return fail(404, 'admin_not_found');
    if (cur.role === 'owner' && !cur.disabled && (await otherActiveOwners(env, u)) < 1) return fail(409, 'last_owner', { message: 'at least one active owner must remain' });
    await env.DB.batch([env.DB.prepare('DELETE FROM sessions WHERE username = ?').bind(u), env.DB.prepare('DELETE FROM admins WHERE username = ?').bind(u)]);
    await audit(env, me, 'admin_delete', { username: u, role: cur.role });
    return json({ ok: true });
  }
  return fail(405, 'method_not_allowed');
}
