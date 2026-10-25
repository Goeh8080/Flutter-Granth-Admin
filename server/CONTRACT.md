# Granth server contract (config.json · /events · admin API)

Base URL (workers.dev, replaceable by a custom domain via the `BASE` var): `https://granth-admin.vedpuran8090.workers.dev`

| Purpose | URL | Auth | CORS |
|---|---|---|---|
| App remote config | `GET {BASE}/config.json` | none | `*` |
| Analytics ingest | `POST {BASE}/events` | none (anonymous) | `*` |
| Web admin panel (SPA) | `{BASE}/admin/` | cookie login | – |
| Admin API | `{BASE}/admin/api/*` | cookie+CSRF (web) **or** Bearer token (Flutter admin app) | never `*` |

Granth **data** editing (add/edit/delete granths and pramans) is NOT on this server — it stays on the wnm website with its own login. This server only controls *presentation* (folders, visibility, flags) and reads the catalogue (`getGranths`, read-only) to know which granths exist.

---------------------------------------------------------------------------------------------------

## 1. `config.json` (consumed by the Flutter reader app)

### 1.1 HTTP behaviour
* `GET /config.json` → `200` JSON, headers: `ETag: "<32 hex>"` (strong), `Cache-Control: public, max-age=60, stale-while-revalidate=600`, `Access-Control-Allow-Origin: *`, `Content-Type: application/json; charset=utf-8`.
* Send `If-None-Match: "<etag>"` → `304` (no body) when unchanged. Cloudflare may re-compress the body; always compare the ETag you stored from the previous 200 (treat `W/` prefix as equal).
* `version` only ever increases (rollback publishes the old content as a *new, higher* version). The server keeps the last 20 versions.
* Propagation: a publish is visible to new requests within ≈15–60 s (isolate memo 15 s + Cache API 60 s).

### 1.2 Schema (schema = 1)
```jsonc
{
  "schema": 1,                       // int, must be 1. Bump only on a breaking change; apps must refuse unknown *schema* (keep bundled/last-good).
  "version": 7,                      // int, strictly increasing
  "generated_at": "2026-10-25T05:10:28Z", // ISO-8601 UTC
  "min_app": 1,                      // int: minimum app *build number* (the number after '+' in 1.0.0+N) able to use this config. See 1.4.
  "endpoints": {
    "config": "https://…/config.json",   // where to fetch config (follows BASE → allows moving the domain)
    "events": "https://…/events",        // analytics ingest URL
    "ai": "https://granth-ai.vedpuran8090.workers.dev"  // optional string, https only (≤200). Omitted when empty. Server stores it as a plain setting.
  },
  "structure": {                     // same shape as the app's bundled assets/structure/structure.json (+ optional fields below)
    "version": 1,                    // int, bumped by the server on every structure edit
    "note": "free text, ignore",
    "religions": [
      { "id": "hindu",               // slug ^[a-z0-9][a-z0-9_-]{0,39}$, immutable, not "other", unique
        "title": "हिन्दू",            // 1–60 chars, editable
        "tone": "saffron",           // saffron | maroon | gold      (optional)
        "icon": "om",                // om|crescent|khanda|cross|dharma|ektara|misc (optional; unknown ⇒ "misc")
        "visible": true,             // optional bool, default true. false ⇒ hide this folder tile (see 1.5)
        "coming_soon": "जल्द आ रहा है", // optional string ≤200. When set the app shows this text instead of/above an empty folder
        "groups": [
          { "id": "ved", "title": "वेद",
            "icon": "scroll",        // scroll|book-red|book-green|book-blue|book-orange|swords|books|quran|hadees|granth-sahib|dasam|bible|tripitak|dhammapad|kabir-sagar|bijak|shabdavali|misc
            "visible": true, "coming_soon": "…",
            "granthIds": ["44","45"],     // leaf only: ids of granths listed here in this order
            "keywords": ["ऋग्वेद"],       // leaf only: title keywords (see placement)
            "notKeywords": ["…"],         // leaf only
            "subgroups": [               // OPTIONAL one extra level. A group WITH subgroups carries no granthIds/keywords itself.
              { "id": "rigved", "title": "ऋग्वेद", "icon": "scroll", "visible": true, "coming_soon": "…",
                "granthIds": ["44","45","46"], "keywords": ["ऋग्वेद"], "notKeywords": [] } ] } ] } ],
    "other": { "id": "other", "title": "अन्य", "icon": "misc", "tone": "gold",
               "forceIds": ["18","36"],   // granth ids forced into "other"
               "coming_soon": "…" }       // optional
  },
  "hidden_granth_ids": ["12","57"],  // strings ^[0-9]{1,8}$, sorted numerically, unique. Never show these granths anywhere.
  "overrides": { "109": { "leaf": "hindu/puran" } },  // granth id → folder (leaf key). Highest placement priority.
  "unassigned_seen": ["109"],        // informational: granth ids the admin has not placed yet (placed by default rules). Ignore if unknown.
  "announcement": { "enabled": false, "text": "", "id": "a0", "level": "info", "expires_at": "2026-12-31T00:00:00Z" },
  "flags": { "ai_enabled": true, "analytics_enabled": true, "analytics_sample": 1, "max_hidden_pct": 50 },
  "contacts_page": { "title": "विशेष जानकार" },       // NEW (additive, schema stays 1). Title of the "विशेष जानकार" screen. See 1.8.
  "contacts": [                                      // NEW. See 1.8. Show only visible:true, sorted by order.
    { "id": "c1", "name": "अमित दास", "role": "", "phone": "", "whatsapp": false, "order": 1, "visible": true }
  ],
  "sig": "<base64 Ed25519>"          // optional, see 1.6
}
```
Field types: `announcement.text` ≤280 chars, `level` ∈ `info|warn|critical`, `id` `[A-Za-z0-9_-]{1,40}` (change it to re-show a dismissed banner), `expires_at` optional ISO-8601 (app hides after it). `flags.analytics_sample` is 0..1 (fraction of installs that send events; decide once per install with a stable hash of iid). `flags.max_hidden_pct` is informational (50, or 90 after a forced publish).

**Leaf key** = `religionId/groupId` (group without subgroups) or `religionId/groupId/subgroupId`, or the literal `other`. This is also the key used in `/events` (`open.f`, `watch_s.f`) and in `overrides[*].leaf`.

### 1.3 Placement algorithm (identical to the app's bundled `ShelfIndex`)
For every granth in the catalogue, in this order — first match wins:
1. `overrides[id].leaf` exists in the structure → that folder
2. `id` appears in some leaf's `granthIds` → that leaf (first in structure order)
3. `id` ∈ `other.forceIds` → `other`
4. title (case/diacritic-folded: NFD without nukta, ZWJ/ZWNJ removed, chandrabindu→anusvara, lower-case) contains a `keywords` entry of **exactly one** leaf (and no `notKeywords` of it) → that leaf
5. otherwise → `other`
Then drop granths in `hidden_granth_ids`. Order inside a folder with `granthIds` = list order (overrides/keyword matches after, API order).

### 1.4 Old apps, unknown fields, `min_app`
* **Unknown fields are ignored** (top-level, in `structure` nodes, `flags`, `announcement`, `endpoints`). Apps must read every field defensively (missing ⇒ default). New features are added as new optional fields; `schema` stays 1.
* Unknown `icon` ⇒ `misc`; unknown `tone` ⇒ `saffron`; unknown `level` ⇒ `info`.
* An app that gets a config it cannot parse, with `schema != 1`, or whose `version` is lower than the cached one **keeps using its last good config** (cached → bundled structure.json fallback). Never crash on config.
* `min_app`: integer build number. If `min_app > myBuildNumber`, the app must **ignore this config** (keep last-good/bundled) and may show an "update the app" hint. The server currently always publishes `min_app: 1`.
* Verify `sig` if the app embeds the public key; on mismatch ignore the config. `sig` is optional for old apps.

### 1.5 Visibility semantics
* `visible:false` on a religion/group/subgroup hides **that folder tile** only. Granths inside it are still reachable via search/other routes unless listed in `hidden_granth_ids` (granth hiding is only through `hidden_granth_ids`). At least one religion stays visible (server-enforced).
* `coming_soon` (non-empty string) on a folder: show it as a note on the folder (and for an empty folder instead of "no granths").

### 1.6 Signature
`sig` = base64(Ed25519(canonicalJSON(config **without** the `sig` key))). Canonical JSON: all object keys sorted by UTF-16 code units, arrays keep order, no whitespace, standard `JSON.stringify` string/number escaping (UTF-8). Public key (raw 32 bytes, base64): `kdPKX/LfjdbPxugpPnpeEejTZlXKzrcoOg88IK83Fb4=` (also in admin `GET /settings` → `info.signing_public_key`).

### 1.8 `contacts_page` / `contacts` (विशेष जानकार)
```jsonc
"contacts_page": { "title": "विशेष जानकार" },        // string, 1–60 chars, editable by the admin
"contacts": [
  { "id": "c1",             // string ^[A-Za-z0-9_-]{1,40}$, unique, stable (never reused for another person)
    "name": "अमित दास",       // string, 1–80 chars, REQUIRED
    "role": "",              // string ≤80 chars, optional ("" = none) – e.g. a title/description to show under the name
    "phone": "",             // string. "" = no number. Else digits with an optional single leading "+", total ≤20 chars: ^(\+[0-9]{1,19}|[0-9]{1,20})$ . Never contains spaces/hyphens (the server strips them on save).
    "whatsapp": false,       // bool. true only when phone is non-empty: this number is on WhatsApp (show a WhatsApp button, e.g. https://wa.me/<digits without '+'>)
    "order": 1,              // int ≥1, unique, display order ascending
    "visible": true }        // bool. false ⇒ the app must NOT show this person (kept in the list so the admin can re-enable)
]
```
* **App rules:** take `contacts` where `visible == true`, sort by `order` ascending, render `name` (+ `role` if non-empty). If `phone == ""` show **no call/WhatsApp button** (just the name). If `phone != ""` show a Call button (`tel:<phone>`) and, when `whatsapp == true`, a WhatsApp button. If `contacts` is missing/empty (old config) hide the screen/entry or show nothing; `contacts_page.title` missing ⇒ use "विशेष जानकार".
* **Old apps** simply ignore the two new top-level fields (see 1.4); `schema` stays `1`. Publishing a config that contains them is safe for every released app.
* **v1 seed** (what the server publishes first; phone numbers are typed by Goutam in the admin panel, never invented): ids `c1..c4` = अमित दास, रामेश्वर दर, गौतम दास, अशोक दास – all `role:""`, `phone:""`, `whatsapp:false`, `visible:true`, `order` 1..4.
* Limits/validation (publish and every contacts endpoint return `422 invalid_contacts{errors[]}`): ≤50 contacts; ids unique; `name` 1–80; `role` ≤80; `phone` format above; `whatsapp` boolean and needs a phone; `order` unique integers ≥1; `visible` boolean; title 1–60.

### 1.7 Server-side validation (publish is rejected with `422 validation_failed`/`invalid_structure`)
version > previous; schema = 1; ≤64 KB; every religion/group/subgroup id is a slug, unique within its parent, titles 1–60 chars; icon/tone in the allowed lists; `visible` boolean; `coming_soon` ≤200; ≥1 visible religion; `structure.other` exists; every `overrides[*].leaf` exists in the structure (or is `other`); every id matches `^[0-9]{1,8}$`; hidden ids unique; **hiding >50% of the catalogue needs `force:true`** (then `flags.max_hidden_pct` = 90), **>90% is never allowed**; `flags.ai_enabled/analytics_enabled` boolean; `analytics_sample` 0..1; announcement valid; `endpoints.ai` https URL ≤200 or empty. Ids are immutable (only titles are editable); removing a folder that granths are assigned to is refused (`409 leaf_in_use`) unless `drop_overrides:true`.

---------------------------------------------------------------------------------------------------

## 2. `POST /events` (anonymous analytics, plan §7.4)
* Always answers **204 No Content** (also for invalid, oversized, duplicate, rate-limited or analytics-disabled input — the app must never retry on content errors; retry only on network failure, reusing the same `batch_id`). `OPTIONS` → 204 with CORS `*`.
* Body: JSON, `Content-Type: application/json`, optionally `Content-Encoding: gzip`. **≤ 8 KB after gunzip** (a gzip bomb is dropped).
* Server never stores IP, user agent or free text: iid is stored only as a salted hash prefix (16 hex), per-IP limiter state is a salted hash in memory only.
```jsonc
{
  "v": 1,                              // must be 1
  "batch_id": "Ab12…",                 // ^[0-9A-Za-z_-]{8,64}$ unique per batch (uuid ok); duplicates are ignored
  "iid": "0123456789abcdef0123456789abcdef", // random 128-bit install id, 32 hex, generated on the device, not derived from anything
  "app": "1.0.0+1",                    // ^[0-9A-Za-z.+_-]{1,24}$ app version+build
  "os": "android",                     // android|ios|web (else "other")
  "sdk": 34,                           // int 0..99 (Android API level / iOS major)
  "cfg": 7,                            // config version the app is running (int)
  "day": "2026-10-25",                 // UTC day of the data; must be within ±2 days of server UTC today
  "fg_s": 600,                         // foreground seconds that day (clamped ≤21600)
  "sessions": 2,                       // app sessions (clamped ≤5000)
  "open":    { "g": {"44": 3},         // granth opens by id ^[0-9]{1,8}$ (and known to the catalogue)
               "f": {"hindu/puran": 4},// folder opens by leaf key (unknown keys dropped)
               "t": {"5": 1},          // topic opens (counted only, keys ignored)
               "p": {"7": 2} },        // praman opens (counted only)
  "watch_s": { "g": {"44": 200}, "f": {"hindu/puran": 250}, "scr": {"reader": 400, "home": 100} }, // seconds; per entry clamped ≤7200; scr = screen name ^[a-z0-9_-]{1,24}$
  "sync": { "ok": 3, "fail": 1, "kinds": {"timeout": 1} },   // kinds keys ^[a-z0-9_]{1,24}$
  "pdf":  { "ok": 2, "fail": 1, "kinds": {"nospace": 1} },
  "ai":   { "asked": 2, "answered": 1, "cite_tap": 1 }
}
```
Limits as implemented: body 8192 B (after gunzip); ≤200 keys per map; counts clamped ≤5000, `fg_s` ≤21600, each `watch_s` value ≤7200; `day` ±2 days; ≤6 accepted batches per install per day; ≤60 requests/min per IP-hash (best effort); idempotent on `batch_id` (kept 4 days). Unknown extra fields are ignored. With `flags.analytics_enabled=false` events are dropped (still 204).

---------------------------------------------------------------------------------------------------

## 3. Admin API

Everything is under `{BASE}/admin/api`. JSON in/out (`Content-Type: application/json`). Responses are `Cache-Control: no-store`.

### 3.1 Authentication
**Multiple admins with roles.** `goutam` is the `owner`. Each admin has their own username, password (salted PBKDF2-SHA256, 50 000 iterations, per-user salt + server pepper; the hash/salt are never returned or logged) and their own sessions/tokens. Roles: `owner` = everything incl. managing admins (`/admins*`); `admin` = everything except `/admins*` (edit/publish/rollback etc.). The role is read live on every request (a role change/disable takes effect immediately). Usernames are case-insensitive (stored lowercase). **Password rule: 10–256 characters, not equal to the username** (same for creating an admin, resetting, and `POST /password`; was 16 for the self-change before – relaxed to 10 everywhere). A disabled admin cannot log in (answered exactly like a wrong password) and their sessions are deleted. Every audit entry's `actor` is the acting admin's username.

**Flutter admin app (bearer):**
1. `POST /login` with header `X-Client: app` (optional `X-Client-Name: Goutam Pixel` – label shown in the session list) and body `{"username":"goutam","password":"…"}` (`username` optional, defaults to `goutam`).
   → `200 {"token":"<64 hex>","token_type":"Bearer","expires_in":86400,"username":"goutam","role":"owner","csrf":"…"}` (no cookie is set; `csrf` can be ignored).
2. Send `Authorization: Bearer <token>` on every request. **No CSRF header and no Origin check** for bearer requests; auth is still required (`401 unauthorized` otherwise).
3. Session is **24 h sliding** (refreshed on use). Store the token in secure storage. Only a SHA-256 of it is stored on the server. On any `401` go back to the login screen.
4. Revocable: `GET /sessions` (list; `current:true` marks yours), `DELETE /sessions/{sid}` , `POST /sessions/revoke_all`, `POST /logout`.

**Web panel (cookie):** `POST /login` (no `X-Client`) → `204` + `Set-Cookie: __Host-granth_sid=<64 hex>; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=86400`. Then `GET /me` → `csrf`; every non-GET request must carry `X-Admin-Csrf: <csrf>` and (if sent) `Origin` equal to the panel origin, else `403 csrf` / `403 bad_origin`. A web cookie id cannot be used as a bearer token and vice versa.

**Rate limit:** 5 failed logins per 10 min per IP (salted hash, TTL) → `429 {"error":"rate_limited","retry_after":600}` + `Retry-After`; repeated lockouts back off exponentially (×2, max 1 day); a global brake locks everyone for 5 min after 60 failures. Successful login resets the IP counter.

### 3.2 Error format
`{"error":"<code>", ...extra}` with HTTP status:
`400 bad_request` · `401 unauthorized | bad_credentials` · `403 csrf | bad_origin | forbidden` (forbidden = admin role calling an owner-only endpoint) · `404 not_found | admin_not_found | contact_not_found | granth_not_found | version_not_found | session_not_found` · `409 no_changes | leaf_in_use{message,leaves} | cannot_modify_self | last_owner | username_taken | use_change_password` · `422 invalid_contacts{errors[]} | bad_sort | bad_order | bad_username | bad_role | bad_disabled | invalid_structure{errors[]} | invalid_config{errors[],warnings[]} | unknown_leaf | bad_hidden | nothing_to_change | bad_sample | bad_ids | bad_version | invalid_announcement{errors[]} | invalid_endpoint{errors[]} | weak_password` · `429 rate_limited{retry_after} | too_soon` · `500 internal`.
Treat unknown codes generically; `errors[]` are human-readable strings (Hindi/English mixed OK to show as-is).

### 3.3 Endpoints
`H` = needs auth (bearer or cookie). Non-GET also needs CSRF for cookie sessions.

| Method & path | Request | Response |
|---|---|---|
| `POST /login` | `{username?,password}` | app: `200 {token,token_type,expires_in,username,role,csrf}`; web: `204`+cookie; `401 bad_credentials`; `429 rate_limited` |
| `POST /logout` H | – | `{ok:true}` (revokes this session) |
| `GET /me` H | – | `{username, role:"owner"\|"admin", can_manage_admins:bool, auth:"bearer"\|"cookie", csrf, version, base, has_draft, base_version, next_version}` — `version` = currently published config version |
| `GET /sessions` H | – | `{items:[{sid,client,kind:"web"\|"app",created_at,last_seen,current}]}` |
| `DELETE /sessions/{sid}` H | – (sid = 16 hex from list; cannot revoke the current one) | `{ok:true}`; `404 session_not_found` |
| `POST /sessions/revoke_all` H | – | `{ok:true}` (revokes all other sessions, keeps the current one) |
| `POST /password` H | `{current,new}` (new 10–256 chars) | `{ok:true}`; `401 bad_credentials`; `422 weak_password`; rate-limited |
| `GET /granths?sort=&order=` H | optional query `sort`,`order` (see 3.5) | `{sort,order,items:[Granth],leaves:[Leaf],draft,base_version,sync:{sync_last_ok,sync_last_count,sync_last_error?},total,hidden_count}` |
| `PUT /granths/{id}` H | `{leaf?:string\|null, hidden?:bool}` (`leaf:null` = remove override → default placement) | `{ok,has_draft,base_version,next_version}`; `404 granth_not_found`; `422 unknown_leaf` |
| `POST /granths/bulk` H | `{ids:[…≤300], leaf?, hidden?}` | `{ok,changed,has_draft,…}` |
| `GET /structure` H | – | `{structure, counts:{leafKey:n}, leaves:[Leaf], icons:{group:[],religion:[],tones:[]}, draft, base_version}` |
| `PUT /structure` H | `{structure:{…as in 1.2…}, drop_overrides?:bool}` (send the whole tree; ids immutable; order of arrays = display order) | `{ok,…}`; `422 invalid_structure{errors}`; `409 leaf_in_use` |
| `GET /draft` H | – | `{exists,base_version,next_version,updated_at,diff:Diff}` |
| `GET /draft/diff` H | – | `{exists,from_version,diff:Diff}` |
| `POST /draft/discard` H | – | `{ok:true}` |
| `POST /publish` H | `{note?:string≤200, force?:bool, allow_empty?:bool}` | `{ok,version,etag,published_at,signed,warnings[]}`; `409 no_changes`; `422 validation_failed` |
| `POST /rollback` H | `{to_version:int, note?}` | `{ok,version,etag,…,rolled_back_to}` (creates a NEW higher version with the old content) |
| `GET /versions` H | – | `{items:[{version,etag,kind:"bootstrap"\|"publish"\|"rollback",note,author,created_at,bytes}],current}` (last 20) |
| `GET /versions/{v}?against={v2}` H | – | `{version,etag,kind,note,author,created_at,against,diff:Diff}` (default against v-1) |
| `GET /alerts` H | – | `{new_granths:[{id,position,title,author,cover,praman_count,first_seen,suggested_leaf,suggested_label,suggestion_source}],alerts:[{id,kind,ref,message,created_at}],count}` |
| `POST /alerts/g:{id}/ack` / `a:{n}/ack` H | – | `{ok:true}` (g = mark granth as handled; a = dismiss alert) |
| `POST /sync` H | – | runs the catalogue diff now: `{ok,count,baseline,added:[ids],changed:n,removed:[ids]}` (`{ok:false,error}` if the catalogue could not be fetched); `429 too_soon` (30 s) |
| `GET /settings` H | – | `{flags:{ai_enabled,analytics_enabled,analytics_sample},announcement,ai_endpoint,levels,info:{base,published_version,signing_public_key,signed,pbkdf2_iterations,admins},draft}` |
| `PUT /settings` H | any of `{flags:{ai_enabled?,analytics_enabled?,analytics_sample?}, announcement:{enabled?,text?,id?,level?,expires_at?}, ai_endpoint?:string}` | `{ok,…}`; `422 bad_sample|invalid_announcement|invalid_endpoint` |
| `GET /admins` H(owner) | – | see 3.5 |
| `POST /admins` H(owner) | `{username,password,role?}` | `201` see 3.5 |
| `GET /admins/{u}` · `PUT /admins/{u}` · `DELETE /admins/{u}` H(owner) | `PUT {role?,disabled?}` | see 3.5 |
| `POST /admins/{u}/password` · `POST /admins/{u}/revoke_sessions` H(owner) | `{password}` / – | see 3.5 |
| `GET /contacts` · `PUT /contacts` · `POST /contacts` · `PUT /contacts/{id}` · `DELETE /contacts/{id}` · `POST /contacts/reorder` H | see 3.6 | see 3.6 (edits go to the draft) |
| `GET /audit?limit=100` H | – | `{items:[{id,ts,actor,action,detail(JSON string)}]}` (max 300, newest first) |
| `GET /stats/overview?days=7\|30\|90` H | – | see 3.4 |
| `GET /stats/granths?days=` H | – | `{days,items:[{id,title,opens,watch_s,avg_watch_s}]}` (top 300 by opens) |
| `GET /stats/folders?days=` H | – | `{days,items:[{key,label,opens,watch_s,avg_watch_s}]}` |
| `GET /stats/series?kind=granth\|folder&id=…&days=` H | – | `{days,kind,id,series:[{day,opens,watch_s}]}` (one point per day) |

**Edits are drafts.** `PUT /granths*`, `PUT /structure`, `PUT /settings` modify a single shared *draft*; nothing reaches app users until `POST /publish`. Flow for screens: edit → `GET /draft` (diff, `changed` count) → `POST /publish` (or `/draft/discard`). Publishing with `force:true` is required when `diff.warnings` says >50% hidden.

`Granth` = `{id,position,created_at,title,author,cover(url|null),praman_count,active,leaf,leaf_label,source:"override"|"id"|"forced"|"keyword"|"fallback",default_leaf,hidden,is_new,first_seen,no_praman,opens_7d,watch_s_7d}`.
`Leaf` = `{key,label,religion,religion_id,group,visible}` (label like `हिन्दू › वेद › ऋग्वेद`; `other` is also a valid key with label `अन्य`).
`Diff` = `{granths:[{id,title,leaf?:{from,to},hidden?:{from,to}}],folders:[{path,change:"added"|"edited"|"removed",title,fields?:[{field,from,to}]}],contacts:[{id,name,change:"added"|"removed"|"edited",fields?:[{field,from,to}]}],settings:[{field,from,to}] (title change = field "contacts_page.title"),hidden_count,catalog_total,warnings:[string],changed:int}`.

### 3.4 `GET /stats/overview?days=7|30|90`
Seconds everywhere are integers; days are UTC `YYYY-MM-DD`. No PII: only counts.
```jsonc
{
  "days": 7, "since": "2026-10-19",
  "totals": {
    // (a) installs
    "total_installs": 4,            // distinct installs ever seen (each reinstall = new random iid)
    "first_install_day": "2026-10-25",
    "active_1d": 8, "active_7d": 8, "active_30d": 8,   // distinct installs active today / last 7 / last 30 days
    "new_installs_in_range": 4,
    // (b) time used
    "total_fg_s": 46800,            // foreground seconds in the selected range
    "total_fg_s_all_time": 46800,   // all retained days (≤400 d)
    "avg_fg_s_per_active_user": 5850,       // range fg / distinct active users in range
    "avg_fg_s_per_active_user_day": 5850,   // range fg / sum of daily actives
    "sessions": 16, "sessions_all_time": 16, "avg_sessions_per_active_user_day": 2,
    "granth_watch_s": 15400, "folder_watch_s": 1000,
    // (c) usage
    "granth_opens": 10018, "granth_opens_all_time": 10018, "granth_watch_s_all_time": 15400,
    "folder_opens": 16, "topic_opens": 4, "praman_opens": 8,
    // legacy/derived
    "users_in_range": 8, "mau_30d": 8, "dau_today": 8, "dau_avg": 1, "batches": 8, "app_fg_s": 46800, "watch_s_per_user_day": 5850
  },
  "dau": [ {"day":"2026-10-19","n":0,"fg_s":0}, … ],          // one per day of the range
  "new_installs": [ {"day":"2026-10-19","n":0}, … ],            // new installs per day
  "installs_by_version": [ {"app":"1.0.0+1","n":4} ],           // installs by their latest reported app version (top 20)
  "installs_by_os": [ {"os":"android","n":4} ],
  "versions": { "1.0.0+1": 8 },                                  // daily-active sum by app version in range
  "sync": {"ok":24,"fail":8,"fail_rate":0.25}, "pdf": {"ok":16,"fail":8}, "ai": {"asked":16,"answered":8,"cite_tap":8},
  "screens": [ {"scr":"reader","watch_s":1600} ],  "top_screens": [ {"screen":"reader","watch_s":1600} ],   // time per screen
  "failure_kinds": [ {"kind":"sync:timeout","n":8} ],
  "top_granths_opens": [ {"id":"104","title":"…","opens":10004,"watch_s":14600,"avg_watch_s":1} ],   // top 10
  "top_granths_watch": [ same shape, sorted by watch_s ],
  "top_folders": [ {"key":"hindu/puran","label":"हिन्दू › पुराण","opens":16,"watch_s":1000} ],
  "top_folders_watch": [ same, sorted by watch_s ],
  "religions": [ {"key":"hindu","label":"हिन्दू","opens":16,"watch_s":1000} ],   // roll-up of folders by religion
  "new_granths_pending": 0       // "N new granths need a folder"
}
```
Retention: installs rows are kept ≥800 days after last seen; daily rollups 400 days; per-install daily activity (`active`) 35 days (so `active_30d` and `users_in_range` are exact up to 30 d; for `days=90` `users_in_range` is capped to the 35-day window).

### 3.5 Granths sort + admins (exact JSON)

**Sort — `GET /granths?sort=<key>&order=asc|desc`.** Without params: `sort=number&order=asc` ⇒ **catalogue number ascending, #1 first**.
* "number" = the granth's `position`: its 1-based place in the catalogue the reader site (wnm `getGranths`) returns, i.e. the first granth is `position:1`. This is **not** the database `id` (ids are not contiguous / not in catalogue order). `id` is available as its own sort.
* `sort` ∈ `number` (alias of `position`) · `position` · `id` (numeric) · `title` (Hindi collation, A–Z) · `opens` (7-day opens) · `watch` (7-day watch seconds) · `praman` (praman count) · `newest` (catalogue `created_at`). Default `order` per key when omitted: `asc` for number/position/id/title, `desc` for opens/watch/praman/newest. Ties are broken by position, then id. Unknown values → `422 {"error":"bad_sort"|"bad_order"}`.
* The response echoes the canonical key: `{"sort":"position","order":"asc","items":[…]}`; each item also has `position` (int|null, null sorts last) and `created_at` (catalogue string, e.g. `"2026-03-19 17:26:00"`).
* The same ascending-by-position default applies to `GET /alerts → new_granths` (items carry `position`).

**`GET /admins`** (owner only; admin → `403 {"error":"forbidden"}`)
```json
{"items":[{"username":"goutam","role":"owner","disabled":false,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-10-25T05:45:58Z","created_by":null,"active_sessions":4,"last_seen":"2026-10-25T05:47:01.000Z","you":true}],
 "count":1,"roles":["owner","admin"],"min_password_length":10}
```
Order: owners first, then by creation time. `last_seen` is null when never logged in.

**`POST /admins`** `{"username":"ramesh","password":"<10–256 chars>","role":"admin"}` (`role` optional, default `"admin"`; `username` `^[a-z0-9][a-z0-9_.-]{2,31}$`, lower-cased)
→ `201 {"ok":true,"admin":{"username":"ramesh","role":"admin","disabled":false,"created_at":"…","updated_at":"…","created_by":"goutam","active_sessions":0,"last_seen":null,"you":false}}`
Errors: `422 bad_username | bad_role | weak_password`, `409 username_taken`.

**`GET /admins/{username}`** → `{"admin":{…as above…}}` · `404 admin_not_found`.

**`PUT /admins/{username}`** `{"role":"owner"|"admin", "disabled":true|false}` (either or both) → `200 {"ok":true,"admin":{…}}`. Disabling deletes that admin's sessions at once. Errors: `409 cannot_modify_self` (you cannot change your own role or disable yourself), `409 last_owner` (would leave no active owner), `422 nothing_to_change | bad_role | bad_disabled`, `404 admin_not_found`.

**`POST /admins/{username}/password`** `{"password":"<new, 10–256 chars>"}` → `200 {"ok":true}`; revokes all of that admin's sessions. `409 use_change_password` if it targets yourself (use `POST /password`), `422 weak_password`, `404`.

**`POST /admins/{username}/revoke_sessions`** → `200 {"ok":true,"revoked":2}` (`409 cannot_modify_self` for yourself).

**`DELETE /admins/{username}`** → `200 {"ok":true}` (their sessions are deleted). `409 cannot_modify_self`, `409 last_owner`, `404 admin_not_found`.
Passwords/hashes never appear in any response, the audit log or logs. Audit actions: `admin_create`, `admin_update`, `admin_password_reset`, `admin_sessions_revoke`, `admin_delete`, each with `actor` = the acting admin.
The login rate limit (5 failures/10 min/IP) and cookie-CSRF / bearer rules are unchanged.

### 3.6 Contacts — विशेष जानकार (exact JSON)
All edits go to the **draft** (publish/diff/rollback as for everything else); available to both roles. Items are exactly the config `contacts[]` objects of 1.8. Every success response carries the full current draft view:
`{"page":{"title":"विशेष जानकार"},"items":[Contact…],"max_contacts":50,"has_draft":true,"base_version":14,"next_version":15}` (+ `"ok":true`, and `"contact":Contact` on single-item calls).
* `GET /contacts` → the view above (without `ok`); `has_draft` tells whether the shown list is the unpublished draft.
* `PUT /contacts` `{"title"?:string, "items"?:[{"id"?,"name","role"?,"phone"?,"whatsapp"?,"visible"?}]}` — replaces the title and/or the **whole list**; array order becomes `order` 1..n; a missing `id` gets a generated one (`c`+8 hex). Use this for "save screen".
* `POST /contacts` `{"name":"…","role"?,"phone"?,"whatsapp"?,"visible"?}` → `201`, appended at the end (`contact.id` generated).
* `PUT /contacts/{id}` `{name?,role?,phone?,whatsapp?,visible?}` partial update → `200`; `404 contact_not_found`; `422 nothing_to_change`.
* `DELETE /contacts/{id}` → `200` (remaining orders renumbered 1..n); `404 contact_not_found`.
* `POST /contacts/reorder` `{"ids":["c4","c1",…]}` (must list **every** id exactly once) → `200`, `order` = position in `ids`.
* Validation failure → `422 {"error":"invalid_contacts","errors":["contacts[4].name is required (≤80 chars)"]}`. Phone numbers: spaces/hyphens are stripped, then must match the 1.8 format. Audit action `contacts_edit` (never contains phone numbers).
* `GET /draft` / `/draft/diff` show `diff.contacts`; publishing creates the next config version with the new `contacts`/`contacts_page`.

