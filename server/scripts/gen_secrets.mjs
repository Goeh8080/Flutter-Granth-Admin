// Generates the admin password, pepper and Ed25519 signing key into secrets/ (gitignored, chmod 600).
// Existing files are never overwritten unless --force. Only the PUBLIC key is printed.
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, writeFileSync, readFileSync, chmodSync } from 'node:fs';
const dir = new URL('../secrets/', import.meta.url).pathname;
mkdirSync(dir, { recursive: true, mode: 0o700 });
const force = process.argv.includes('--force');
function put(name, value) {
  const p = dir + name;
  if (existsSync(p) && !force) return false;
  writeFileSync(p, value + '\n', { mode: 0o600 }); chmodSync(p, 0o600); return true;
}
const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789-_.@#%+=';
function password(n = 28) { const b = randomBytes(n * 2); let s = ''; for (const x of b) { if (x < 256 - (256 % alphabet.length)) s += alphabet[x % alphabet.length]; if (s.length === n) break; } return s.length === n ? s : password(n); }
put('admin_password.txt', password());
put('pepper.txt', randomBytes(32).toString('hex'));
if (!existsSync(dir + 'signing_pkcs8.b64') || force) {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  put('signing_pkcs8.b64', privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64'));
  put('signing_public.b64', publicKey.export({ format: 'der', type: 'spki' }).subarray(12).toString('base64'));
}
console.log('secrets ready in secrets/ ; signing public key (raw Ed25519, base64):', readFileSync(dir + 'signing_public.b64', 'utf8').trim());
