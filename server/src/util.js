// Small shared helpers (no dependencies).
export const enc = new TextEncoder();
export const dec = new TextDecoder();

export function nowIso() { return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'); }
export function nowSec() { return Math.floor(Date.now() / 1000); }
export function todayUtc(offsetDays = 0) { return new Date(Date.now() + offsetDays * 864e5).toISOString().slice(0, 10); }

export function b64(buf) {
  const u = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let s = '';
  for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000));
  return btoa(s);
}
export function unb64(s) { const bin = atob(s); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u; }
export function hex(buf) { return [...new Uint8Array(buf)].map((x) => x.toString(16).padStart(2, '0')).join(''); }
export function randomHex(nBytes) { const u = new Uint8Array(nBytes); crypto.getRandomValues(u); return hex(u); }
export async function sha256Hex(str) { return hex(await crypto.subtle.digest('SHA-256', enc.encode(str))); }

/** Constant-time string compare (equal-length hex/base64 strings). */
export function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const x = enc.encode(a), y = enc.encode(b);
  let d = x.length ^ y.length;
  const n = Math.max(x.length, y.length);
  for (let i = 0; i < n; i++) d |= (x[i] || 0) ^ (y[i] || 0);
  return d === 0;
}

/** Canonical JSON (RFC 8785-style): object keys sorted by UTF-16 code units, no whitespace. Used for the Ed25519 signature. */
export function canonical(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(canonical).join(',') + ']';
  const keys = Object.keys(v).filter((k) => v[k] !== undefined).sort();
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + canonical(v[k])).join(',') + '}';
}

export function json(obj, status = 200, headers = {}) {
  return new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers } });
}
export function numCmp(a, b) { return Number(a) - Number(b) || (a < b ? -1 : a > b ? 1 : 0); }
export function clampInt(v, lo, hi) {
  if (typeof v !== 'number' || !Number.isFinite(v)) return null;
  return Math.max(lo, Math.min(hi, Math.floor(v)));
}
export const ID_RE = /^[0-9]{1,8}$/;
