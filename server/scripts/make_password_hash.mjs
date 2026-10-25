// Usage: node scripts/make_password_hash.mjs <password-file> [iterations] [username] > secrets/admin_hash.sql
// Prints SQL that (re)sets an admin's PBKDF2 hash. Output contains a hash — keep it in secrets/ (gitignored).
import { readFileSync } from 'node:fs';
import { pbkdf2Sync, randomBytes } from 'node:crypto';
const [file, itersArg, user = 'goutam', role = 'owner'] = process.argv.slice(2);
if (!file) { console.error('usage: make_password_hash.mjs <password-file> [iterations=50000] [username=goutam] [role=owner|admin]'); process.exit(1); }
const pw = readFileSync(file, 'utf8').replace(/\r?\n$/, '');
const iters = Number(itersArg) || 50000;
const salt = randomBytes(16);
const hash = pbkdf2Sync(pw, salt, iters, 32, 'sha256').toString('base64');
const now = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const u = user.replace(/[^a-z0-9_-]/gi, '');
if (!['owner', 'admin'].includes(role)) { console.error('role must be owner or admin'); process.exit(1); }
// needs migrations/0002 applied first. On conflict only the password changes (role/disabled are left alone).
console.log(`INSERT INTO admins (username, pw_hash, salt, iters, created_at, updated_at, role) VALUES ('${u}', '${hash}', '${salt.toString('base64')}', ${iters}, '${now}', '${now}', '${role}')
ON CONFLICT(username) DO UPDATE SET pw_hash = excluded.pw_hash, salt = excluded.salt, iters = excluded.iters, updated_at = excluded.updated_at;
DELETE FROM sessions WHERE username = '${u}';`);
