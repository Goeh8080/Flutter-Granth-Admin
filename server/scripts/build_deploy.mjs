// Generates the scripts that are pasted/injected into the Cloudflare MCP `execute` tool (code: "$file:/abs/path").
// Nothing here talks to Cloudflare or reads any API token. Output (gitignored, contains secrets): deploy/*.generated.js
//   node scripts/build_deploy.mjs <d1-database-id> [pbkdf2-iterations=50000]
// It embeds public/ into the bundle (deploy/entry.mjs + wrangler.embedded.toml) because the MCP connector cannot send the
// per-upload JWT header that the Workers static-assets upload API needs.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { buildAssets } from './assets_manifest.mjs';

const [dbId, itersArg] = process.argv.slice(2);
if (!/^[0-9a-f-]{36}$/.test(dbId || '')) { console.error('usage: build_deploy.mjs <d1-database-id> [iters]'); process.exit(1); }
const iters = Number(itersArg) || 50000;
const NAME = 'granth-admin', SUB = 'vedpuran8090';
const BASE = `https://${NAME}.${SUB}.workers.dev`;
const rd = (p) => readFileSync(p, 'utf8').trim();
mkdirSync('deploy', { recursive: true });

// ---- stage 1 (FRESH INSTALL ONLY): D1 schema + first owner. Skipped when secrets/admin_password.txt is absent, so a
// redeploy of the code never reseeds the schema/admin and can never touch an existing admin hash. For an existing
// database, apply new migrations/NNNN_*.sql by hand through the D1 query endpoint (see README "Upgrading").
import { existsSync, readdirSync } from 'node:fs';
let stage1Bytes = 0;
if (existsSync('secrets/admin_password.txt')) {
  const strip = (f) => rd(f).split('\n').map((l) => l.replace(/\s--.*$/, '')).filter((l) => l.trim() && !l.trim().startsWith('--')).join('\n');
  const schema = readdirSync('migrations').filter((f) => /^\d+_.*\.sql$/.test(f)).sort().map((f) => strip('migrations/' + f)).join('\n');
  const adminSql = execFileSync('node', ['scripts/make_password_hash.mjs', 'secrets/admin_password.txt', String(iters), 'goutam', 'owner'], { encoding: 'utf8' });
  const stage1 = `async () => {
  const id = ${JSON.stringify(dbId)};
  const q = (sql) => cloudflare.request({ method: 'POST', path: \`/accounts/\${accountId}/d1/database/\${id}/query\`, body: { sql } });
  const a = await q(${JSON.stringify(schema)});
  const b = await q(${JSON.stringify(adminSql)});
  const t = await q("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
  return { schema_ok: a.success, admin_ok: b.success, tables: t.result[0].results.map((r) => r.name) };
}`;
  writeFileSync('deploy/stage1_db.generated.js', stage1); stage1Bytes = stage1.length;
}

// ---- stage 2: embedded assets + bundle + Worker + cron + workers.dev ---------------------------------------------
const { manifest, payload } = buildAssets('public');
const FILES = {};
for (const [path, m] of Object.entries(manifest)) FILES['/admin' + path.replace(/^\/admin/, '')] = { hash: m.hash, ...payload[m.hash] };
writeFileSync('deploy/embedded_assets.generated.mjs', 'export const FILES = ' + JSON.stringify(FILES) + ';\n');
execFileSync('npx', ['wrangler', 'deploy', '--dry-run', '--config', 'wrangler.embedded.toml', '--outdir', 'deploy/out'], { stdio: 'ignore' });
const workerJs = readFileSync('deploy/out/entry.js', 'utf8');
const meta = {
  main_module: 'index.js',
  compatibility_date: '2025-10-01',
  bindings: [
    { type: 'd1', name: 'DB', id: dbId },
    { type: 'plain_text', name: 'BASE', text: BASE },
    { type: 'plain_text', name: 'PBKDF2_ITERS', text: String(iters) },
    { type: 'plain_text', name: 'SIGNING_PUBLIC_KEY', text: rd('secrets/signing_public.b64') },
    { type: 'secret_text', name: 'PEPPER', text: rd('secrets/pepper.txt') },
    { type: 'secret_text', name: 'SIGNING_KEY_PKCS8', text: rd('secrets/signing_pkcs8.b64') },
  ],
};
const stage2 = `async () => {
  const name = ${JSON.stringify(NAME)};
  const meta = ${JSON.stringify(meta)};
  const worker = ${JSON.stringify(workerJs)};
  const out = {};
  const b = \`----W\${Date.now()}\`;
  const body = [\`--\${b}\`, 'Content-Disposition: form-data; name="metadata"', 'Content-Type: application/json', '', JSON.stringify(meta), \`--\${b}\`, 'Content-Disposition: form-data; name="index.js"; filename="index.js"', 'Content-Type: application/javascript+module', '', worker, \`--\${b}--\`, ''].join('\\r\\n');
  const up = await cloudflare.request({ method: 'PUT', path: \`/accounts/\${accountId}/workers/scripts/\${name}\`, body, contentType: \`multipart/form-data; boundary=\${b}\`, rawBody: true });
  out.worker_uploaded = up.success;
  const cr = await cloudflare.request({ method: 'PUT', path: \`/accounts/\${accountId}/workers/scripts/\${name}/schedules\`, body: [{ cron: '*/15 * * * *' }, { cron: '30 21 * * *' }] });
  out.crons = (cr.result.schedules || []).map((s) => s.cron);
  const sd = await cloudflare.request({ method: 'POST', path: \`/accounts/\${accountId}/workers/scripts/\${name}/subdomain\`, body: { enabled: true, previews_enabled: false } });
  out.workers_dev = sd.result;
  return out;
}`;
writeFileSync('deploy/stage2_worker.generated.js', stage2);
console.log(JSON.stringify({ stage1_bytes: stage1Bytes, stage2_bytes: stage2.length, base: BASE, iters }));
