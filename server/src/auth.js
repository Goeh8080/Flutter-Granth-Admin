// Admin auth: PBKDF2 password hash in D1, random 256-bit session ids (hashed in D1), CSRF token, login rate limiting.
import { b64, unb64, enc, randomHex, sha256Hex, safeEqual, nowSec, nowIso, json } from './util.js';
import { audit } from './audit.js';

export const COOKIE = '__Host-granth_sid';
const SESSION_TTL = 24 * 3600;
const LOGIN_MAX = 5;          // failures per window per IP
const LOGIN_WINDOW = 600;     // 10 min
const GLOBAL_MAX = 60;        // failed logins per window across all IPs (soft global brake)

export async function pbkdf2(password, saltBytes, iters) {
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  return b64(await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: saltBytes, iterations: iters }, key, 256));
}
export const MIN_PASSWORD = 10;
/** null if OK, else a human message. Passwords are never logged or returned. */
export function passwordProblem(pw, username) {
  if (typeof pw !== 'string' || pw.length < MIN_PASSWORD) return `at least ${MIN_PASSWORD} characters`;
  if (pw.length > 256) return 'at most 256 characters';
  if (username && pw.toLowerCase() === String(username).toLowerCase()) return 'must not equal the username';
  return null;
}
export async function makePasswordRecord(password, iters) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  return { salt: b64(salt), iters, pw_hash: await pbkdf2(password, salt, iters) };
}
export async function ipHash(env, request) {
  const ip = request.headers.get('cf-connecting-ip') || request.headers.get('x-forwarded-for') || 'unknown';
  return (await sha256Hex(`${env.PEPPER || 'dev'}|ip|${ip}`)).slice(0, 24);
}
export function parseCookies(request) {
  const out = {};
  for (const part of (request.headers.get('cookie') || '').split(';')) {
    const i = part.indexOf('=');
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return out;
}
export function sessionCookie(id, maxAge) {
  return `${COOKIE}=${id}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${maxAge}`;
}

/** Returns a Response if the caller is blocked, else null. */
async function checkLocked(env, key) {
  const row = await env.DB.prepare('SELECT n, win_start, level, locked_until FROM rl WHERE k = ?').bind(key).first();
  const now = nowSec();
  if (row && row.locked_until > now) return new Response(JSON.stringify({ error: 'rate_limited', retry_after: row.locked_until - now }), { status: 429, headers: { 'content-type': 'application/json', 'retry-after': String(row.locked_until - now), 'cache-control': 'no-store' } });
  return null;
}
async function recordFailure(env, key, max, lockBase) {
  const now = nowSec();
  const row = await env.DB.prepare('SELECT n, win_start, level, locked_until FROM rl WHERE k = ?').bind(key).first();
  let n = 1, win = now, level = row ? row.level : 0, locked = 0;
  if (row && now - row.win_start <= LOGIN_WINDOW) { n = row.n + 1; win = row.win_start; }
  if (n >= max) { locked = now + Math.min(lockBase * 2 ** level, 86400); level += 1; n = 0; win = now; }
  await env.DB.prepare(`INSERT INTO rl (k, n, win_start, level, locked_until, expires_at) VALUES (?,?,?,?,?,?)
    ON CONFLICT(k) DO UPDATE SET n = excluded.n, win_start = excluded.win_start, level = excluded.level, locked_until = excluded.locked_until, expires_at = excluded.expires_at`)
    .bind(key, n, win, level, locked, Math.max(locked, now) + 86400).run();
}

export async function login(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ error: 'bad_request' }, 400); }
  const username = typeof body.username === 'string' && body.username.trim() ? body.username.trim().toLowerCase().slice(0, 40) : 'goutam'; // omitted username → 'goutam' (backward compatible)
  const password = typeof body.password === 'string' ? body.password : '';
  if (!password || password.length > 256) return json({ error: 'bad_credentials' }, 401);
  const ih = await ipHash(env, request);
  const ipKey = `login:${ih}`;
  const blocked = (await checkLocked(env, ipKey)) || (await checkLocked(env, 'login:global'));
  if (blocked) return blocked;
  const admin = await env.DB.prepare('SELECT username, pw_hash, salt, iters, disabled, role FROM admins WHERE username = ?').bind(username).first();
  let ok = false;
  if (admin) { ok = safeEqual(await pbkdf2(password, unb64(admin.salt), admin.iters), admin.pw_hash); if (admin.disabled) ok = false; } // disabled accounts look exactly like a wrong password
  else await pbkdf2(password, new Uint8Array(16), Number(env.PBKDF2_ITERS) || 50000); // equalise timing
  if (!ok) {
    await recordFailure(env, ipKey, LOGIN_MAX, 600);
    await recordFailure(env, 'login:global', GLOBAL_MAX, 300);
    return json({ error: 'bad_credentials' }, 401);
  }
  await env.DB.prepare('DELETE FROM rl WHERE k = ?').bind(ipKey).run();
  const id = randomHex(32), csrf = randomHex(16), now = nowSec();
  const app = (request.headers.get('x-client') || '').toLowerCase() === 'app';
  const label = app ? String(request.headers.get('x-client-name') || 'app').replace(/[^\w .\-]/g, '').slice(0, 40) || 'app' : 'web';
  await env.DB.batch([
    env.DB.prepare('INSERT INTO sessions (id_hash, username, csrf, created_at, last_seen, expires_at, client) VALUES (?,?,?,?,?,?,?)').bind(await sha256Hex(id), username, csrf, now, now, now + SESSION_TTL, label),
    env.DB.prepare('DELETE FROM sessions WHERE expires_at < ?').bind(now),
  ]);
  await audit(env, username, 'login', { ip_hash: ih.slice(0, 6), client: label });
  if (app) return json({ token: id, token_type: 'Bearer', expires_in: SESSION_TTL, username, role: admin.role, csrf });
  return new Response(null, { status: 204, headers: { 'set-cookie': sessionCookie(id, SESSION_TTL), 'cache-control': 'no-store' } });
}

/** Resolve the session from `Authorization: Bearer <token>` (mobile app) or the cookie (web). Returns
 *  {username, csrf, idHash, bearer, cookie} or null. Sliding 24 h either way. */
export async function getSession(request, env) {
  let id = null, bearer = false;
  const m = /^Bearer\s+([0-9a-f]{64})$/i.exec(request.headers.get('authorization') || '');
  if (m) { id = m[1].toLowerCase(); bearer = true; }
  else { id = parseCookies(request)[COOKIE]; if (!id || !/^[0-9a-f]{64}$/.test(id)) return null; }
  const idHash = await sha256Hex(id);
  const now = nowSec();
  const row = await env.DB.prepare('SELECT s.username, s.csrf, s.last_seen, s.expires_at, s.client, a.role, a.disabled FROM sessions s JOIN admins a ON a.username = s.username WHERE s.id_hash = ?').bind(idHash).first();
  if (!row || row.expires_at < now || row.disabled) return null; // deleted/disabled admins lose access immediately
  if (bearer !== (row.client !== 'web')) return null; // a web cookie id can't be used as a bearer token and vice versa
  let cookie = null;
  if (now - row.last_seen > 300) { // sliding 24 h, written at most every 5 min
    await env.DB.prepare('UPDATE sessions SET last_seen = ?, expires_at = ? WHERE id_hash = ?').bind(now, now + SESSION_TTL, idHash).run();
    if (!bearer) cookie = sessionCookie(id, SESSION_TTL);
  }
  return { username: row.username, role: row.role, csrf: row.csrf, idHash, bearer, client: row.client, cookie };
}
export async function logout(session, env) {
  await env.DB.prepare('DELETE FROM sessions WHERE id_hash = ?').bind(session.idHash).run();
  return new Response(null, { status: 204, headers: { 'set-cookie': sessionCookie('', 0) } });
}

export async function changePassword(request, env, session) {
  let b; try { b = await request.json(); } catch { return json({ error: 'bad_request' }, 400); }
  const weak = passwordProblem(b.new, session.username); if (weak) return json({ error: 'weak_password', message: weak }, 422);
  const admin = await env.DB.prepare('SELECT pw_hash, salt, iters FROM admins WHERE username = ?').bind(session.username).first();
  const ih = await ipHash(env, request);
  const blocked = await checkLocked(env, `pwchg:${ih}`);
  if (blocked) return blocked;
  if (!admin || !safeEqual(await pbkdf2(String(b.current || ''), unb64(admin.salt), admin.iters), admin.pw_hash)) {
    await recordFailure(env, `pwchg:${ih}`, LOGIN_MAX, 600);
    return json({ error: 'bad_credentials' }, 401);
  }
  const rec = await makePasswordRecord(b.new, Number(env.PBKDF2_ITERS) || 50000);
  await env.DB.batch([
    env.DB.prepare('UPDATE admins SET pw_hash = ?, salt = ?, iters = ?, updated_at = ? WHERE username = ?').bind(rec.pw_hash, rec.salt, rec.iters, nowIso(), session.username),
    env.DB.prepare('DELETE FROM sessions WHERE username = ? AND id_hash != ?').bind(session.username, session.idHash),
  ]);
  await audit(env, session.username, 'password_change', {});
  return json({ ok: true });
}
