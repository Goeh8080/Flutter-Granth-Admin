# Granth admin panel

Admin panel + remote `config.json` + anonymous analytics ingest for the Granth app, on **Cloudflare Workers + D1** (free plan).
Live: <https://granth-admin.vedpuran8090.workers.dev> (panel at `/admin/`).

| URL | What |
|---|---|
| `GET /config.json` | Published app config (strong ETag, `max-age=60, stale-while-revalidate=600`, 304, CORS `*`, optional Ed25519 `sig`) |
| `POST /events` | Anonymous usage batches (always `204`, ≤8 KB after gunzip, gzip accepted, CORS `*`) |
| `/admin/` | Panel SPA (mobile-first, Flutter app theme) |
| `/admin/api/*` | Admin API (cookie+CSRF for web, `X-Client: app` + `Authorization: Bearer` for the Flutter admin app; never CORS `*`) |

Full contracts (config schema, `/events`, admin API, `/stats/overview`): **[CONTRACT.md](CONTRACT.md)**.

## Architecture
* `src/index.js` router + CSP; `src/config.js` draft → publish → versions (last 20), rollback = new higher version, §5.2 validation (`src/structure.js`), signing.
* `src/auth.js` PBKDF2-SHA256 password (iterations stored per admin row), random 256-bit session ids stored as SHA-256, sliding 24 h, login rate limit in D1 (`rl`, salted IP hash, 5 failures/10 min → lockout with backoff, global brake).
* `src/events.js` sanitising + dedupe (`batch_seen`) + rollups (`daily_*`, `active`, `installs`); `src/stats.js` read side.
* `src/cron.js`: `*/15 * * * *` diff `getGranths` vs `granths_seen` (new granths → alerts/inbox, read-only GET), `30 21 * * *` (03:00 IST) prune.
* `public/admin/` vanilla-JS SPA, fonts self-hosted (DM Sans, Noto Sans Devanagari, Yatra One).
* `migrations/0001_init.sql` D1 schema. No R2 anywhere – config is stored in D1 and cached (isolate memory 15 s → Cache API 60 s).

## Develop / test
```
npm i
npx wrangler d1 execute granth-admin-db --local --persist-to .wrangler/state --file migrations/0001_init.sql
node scripts/gen_secrets.mjs                    # → secrets/ (gitignored): admin_password.txt, pepper.txt, signing keys
node scripts/make_password_hash.mjs secrets/admin_password.txt 50000 goutam > secrets/admin_hash.sql
npx wrangler d1 execute granth-admin-db --local --persist-to .wrangler/state --file secrets/admin_hash.sql
printf 'PEPPER=%s\nSIGNING_KEY_PKCS8=%s\n' "$(cat secrets/pepper.txt)" "$(cat secrets/signing_pkcs8.b64)" > .dev.vars
npx wrangler dev --local --persist-to .wrangler/state
npm test                                         # unit tests
BASE=http://127.0.0.1:8787 PW_FILE=secrets/admin_password.txt PUBKEY=$(cat secrets/signing_public.b64) npm run test:e2e
BASE=… PW_FILE=… npm run test:ui                 # jsdom walk of the SPA (no real browser)
```
`e2e.mjs newgranth` needs `NEWID=<id>` of a `granths_seen` row you deleted first; `e2e.mjs ratelimit` locks your IP out of login for 10 min (note: some networks rotate egress IPs, then the per-IP limit can't be exercised from one client – use one keep-alive connection).

## Deploy
Normal path: `wrangler d1 create granth-admin-db`, put the id in `wrangler.toml`, `wrangler d1 migrations apply granth-admin-db --remote`, seed the admin hash (above, `--remote`), `wrangler secret put PEPPER`, `wrangler secret put SIGNING_KEY_PKCS8`, set `SIGNING_PUBLIC_KEY`/`BASE` vars, `wrangler deploy`.

The live deployment was done **without wrangler credentials** through the Cloudflare MCP connector (`scripts/build_deploy.mjs` generates two scripts for its `execute` tool: D1 schema+admin, then Worker upload with cron + workers.dev). That API path cannot send the per-upload JWT header the static-assets upload needs, so the SPA files are **embedded in the Worker bundle** (`deploy/entry.mjs` + `wrangler.embedded.toml`, an `env.ASSETS` shim with the same `fetch()` contract). Behaviour is identical; with `wrangler deploy` the normal `[assets]` binding is used instead.

### Secrets / config
| Name | Kind | Purpose |
|---|---|---|
| `PEPPER` | secret | salts session ids, IP hashes, iid hashes |
| `SIGNING_KEY_PKCS8` | secret | Ed25519 private key (base64 pkcs8) for config `sig` |
| `SIGNING_PUBLIC_KEY` | var | public key (base64 raw) – informational; give it to the app |
| `BASE` | var | public base URL used for `endpoints{}` in config.json |
| `PBKDF2_ITERS` | var | iterations for new passwords (50000) |
| `CATALOG_URL` | var (optional) | override of the getGranths URL (tests) |
Admin password: only as salted PBKDF2 hash in D1 `admins`. Never commit `secrets/`, `.dev.vars`, `deploy/*.generated*`.

### Admins, roles and password reset
* Normal way: **Settings → एडमिन** in the panel (owner only) or the `/admin/api/admins*` endpoints (CONTRACT.md 3.5): create (username + password, role `owner` or `admin`), reset another admin's password, disable/enable, change role, delete. You cannot disable/delete/demote yourself and the last active owner can never be removed. `admin` role = edit/publish only; `owner` also manages admins. Password rule everywhere: **10–256 chars** (PBKDF2-SHA256, per-user salt + pepper).
* Break-glass (owner locked out), directly in D1 – only changes the password, keeps the role, deletes that user's sessions:
```
echo -n 'new-long-password' > secrets/admin_password.txt && chmod 600 secrets/admin_password.txt
node scripts/make_password_hash.mjs secrets/admin_password.txt 50000 goutam owner > secrets/admin_hash.sql
wrangler d1 execute granth-admin-db --remote --file secrets/admin_hash.sql
```
### Upgrading an existing database
Migrations are not re-run by `build_deploy.mjs` once `secrets/admin_password.txt` is gone (so a code redeploy can never reseed or touch an admin hash). Apply new `migrations/NNNN_*.sql` once by hand (`wrangler d1 migrations apply … --remote`, or the D1 query endpoint through the MCP connector): `0002_admin_roles.sql` adds `admins.role/disabled/created_by` and sets `goutam` to `owner` (hash untouched). Apply it **before** deploying code that needs it. Fresh installs: `build_deploy.mjs` applies all migrations and seeds the first owner when `secrets/admin_password.txt` exists.

### Move to a custom domain
Add the route/custom domain to the Worker, set `BASE = "https://granth.example.com"`, deploy, then **publish once** in the panel (Publish with “allow empty”) so `endpoints{}` in config.json are rebuilt. Ship the new config URL to the app via the old URL's `endpoints.config` before retiring the workers.dev name.

## Free-tier limits
* Workers Free: 100k requests/day and 10 ms CPU/request. `/config.json` is cached (isolate + Cache API), `/events` is one small D1 batch per app-day. Roughly fine up to ~8–10k DAU (each DAU ≈ 2–6 requests/day); beyond that use Workers Paid ($5/mo) or move `config.json` to static hosting/R2 later.
* PBKDF2 at 50 000 iterations passes live on the free plan (login ≈ 0.25–0.3 s wall, no CPU error). If you ever see error 1102 on login, lower iterations (20–30k) with `make_password_hash.mjs`.
* D1 Free: 100k rows written/day, 5 GB. Rollups keep writes low; `active` is kept 35 days, `installs` 800 days after last seen, daily tables 400 days.
* Config cache: after publish, other isolates may serve the previous version for up to ~15 s (memory) and the edge up to 60 s.

## Theme provenance
Tokens come from the Flutter app (read-only): palette + font stacks `lib/theme/colors.dart`; card radius/shadow/pill/icon boxes `lib/widgets/common.dart`; icons `assets/icons/*.svg` (lucide 24 px stroke 2); fonts `assets/fonts/*.ttf` → woff2.
