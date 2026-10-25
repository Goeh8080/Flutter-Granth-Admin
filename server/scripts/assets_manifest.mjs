// Builds the Workers static-assets manifest + base64 payloads (hash = first 32 hex of sha256(base64(content) + ext), like wrangler).
import { readdirSync, statSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, extname } from 'node:path';
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json' };
export function buildAssets(dir) {
  const files = [];
  (function walk(d) { for (const n of readdirSync(d)) { const p = join(d, n); if (statSync(p).isDirectory()) walk(p); else files.push(p); } })(dir);
  const manifest = {}, payload = {};
  for (const f of files) {
    const rel = '/' + f.slice(dir.length + 1).split('\\').join('/');
    const buf = readFileSync(f), b64 = buf.toString('base64');
    const hash = createHash('sha256').update(b64 + extname(f).slice(1)).digest('hex').slice(0, 32);
    manifest[rel] = { hash, size: buf.length };
    payload[hash] = { b64, type: MIME[extname(f)] || 'application/octet-stream' };
  }
  return { manifest, payload };
}
