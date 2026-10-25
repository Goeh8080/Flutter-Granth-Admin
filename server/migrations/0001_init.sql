-- Granth admin panel: D1 schema (SQLite). Apply with: wrangler d1 migrations apply granth-admin-db --remote
-- (the live deploy in this project applied the same statements through the Cloudflare API).

CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);

-- ---- auth -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admins (
  username   TEXT PRIMARY KEY,
  pw_hash    TEXT NOT NULL,          -- base64 PBKDF2-SHA256 derived key
  salt       TEXT NOT NULL,          -- base64 random 16 bytes
  iters      INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  id_hash    TEXT PRIMARY KEY,       -- sha256(session id); the raw id only lives in the cookie
  username   TEXT NOT NULL,
  csrf       TEXT NOT NULL,
  created_at INTEGER NOT NULL,       -- epoch seconds
  last_seen  INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  client     TEXT NOT NULL DEFAULT 'web'  -- 'web' = cookie session; anything else = mobile-app bearer token (label from X-Client-Name)
);
CREATE INDEX IF NOT EXISTS sessions_exp ON sessions(expires_at);
-- generic rate-limit / lockout counters. key = '<kind>:<salted hash>' (never a raw IP)
CREATE TABLE IF NOT EXISTS rl (
  k            TEXT PRIMARY KEY,
  n            INTEGER NOT NULL DEFAULT 0,
  win_start    INTEGER NOT NULL,
  level        INTEGER NOT NULL DEFAULT 0,   -- lockout backoff level
  locked_until INTEGER NOT NULL DEFAULT 0,
  expires_at   INTEGER NOT NULL              -- TTL, pruned by cron
);
CREATE INDEX IF NOT EXISTS rl_exp ON rl(expires_at);

CREATE TABLE IF NOT EXISTS audit_log (
  id     INTEGER PRIMARY KEY AUTOINCREMENT,
  ts     TEXT NOT NULL,
  actor  TEXT NOT NULL,
  action TEXT NOT NULL,
  detail TEXT                       -- JSON (before/after, never secrets)
);

-- ---- config versions --------------------------------------------------------
CREATE TABLE IF NOT EXISTS config_versions (
  version    INTEGER PRIMARY KEY,
  etag       TEXT NOT NULL,
  json       TEXT NOT NULL,         -- the exact config.json bytes served
  state      TEXT NOT NULL,         -- {structure,hidden_granth_ids,overrides,flags} snapshot (for diff / rollback)
  kind       TEXT NOT NULL,         -- bootstrap | publish | rollback
  note       TEXT,
  author     TEXT,
  created_at TEXT NOT NULL
);
-- single-row draft (id = 1)
CREATE TABLE IF NOT EXISTS draft (
  id           INTEGER PRIMARY KEY CHECK (id = 1),
  state        TEXT NOT NULL,
  base_version INTEGER NOT NULL,
  force_hide   INTEGER NOT NULL DEFAULT 0,
  updated_at   TEXT NOT NULL,
  updated_by   TEXT
);

-- ---- catalog tracking (new-granth detection) --------------------------------
CREATE TABLE IF NOT EXISTS granths_seen (
  id           TEXT PRIMARY KEY,
  title        TEXT NOT NULL,
  author       TEXT,
  cover        TEXT,
  position     TEXT,
  praman_count INTEGER NOT NULL DEFAULT 0,
  active       INTEGER NOT NULL DEFAULT 1,
  created_at   TEXT,                -- Ashok's created_at
  first_seen   TEXT NOT NULL,
  last_seen    TEXT NOT NULL,
  assigned_at  TEXT,                -- NULL = needs a folder decision
  missing_runs INTEGER NOT NULL DEFAULT 0,
  removed_at   TEXT
);
CREATE TABLE IF NOT EXISTS alerts (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  kind       TEXT NOT NULL,         -- sync_error | removed_granth
  ref        TEXT,
  message    TEXT,
  created_at TEXT NOT NULL,
  acked_at   TEXT
);

-- ---- analytics rollups (no IP, no raw ids) -----------------------------------
CREATE TABLE IF NOT EXISTS batch_seen (batch_id TEXT PRIMARY KEY, day TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS batch_seen_day ON batch_seen(day);
CREATE TABLE IF NOT EXISTS active (
  iid_hash TEXT NOT NULL,           -- first 16 hex of sha256(pepper + iid)
  day      TEXT NOT NULL,
  batches  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (iid_hash, day)
);
CREATE INDEX IF NOT EXISTS active_day ON active(day, iid_hash);
-- one row per install (= per random app-generated iid; reinstall = new iid). Only a pepper-salted hash of the iid, never the raw id. Kept long-term (tiny rows).
CREATE TABLE IF NOT EXISTS installs (
  iid_hash    TEXT PRIMARY KEY,
  first_seen  TEXT NOT NULL,         -- UTC day (YYYY-MM-DD) of the first accepted batch
  last_seen   TEXT NOT NULL,
  app_version TEXT NOT NULL,         -- version reported in the latest batch
  os          TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS installs_first ON installs(first_seen);
CREATE TABLE IF NOT EXISTS daily_granth (day TEXT NOT NULL, gid TEXT NOT NULL, opens INTEGER NOT NULL DEFAULT 0, watch_s INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, gid)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS daily_folder (day TEXT NOT NULL, fkey TEXT NOT NULL, opens INTEGER NOT NULL DEFAULT 0, watch_s INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, fkey)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS daily_screen (day TEXT NOT NULL, scr TEXT NOT NULL, watch_s INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, scr)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS daily_app (
  day TEXT NOT NULL, app TEXT NOT NULL,
  dau INTEGER NOT NULL DEFAULT 0, batches INTEGER NOT NULL DEFAULT 0, sessions INTEGER NOT NULL DEFAULT 0, fg_s INTEGER NOT NULL DEFAULT 0,
  topic_opens INTEGER NOT NULL DEFAULT 0, praman_opens INTEGER NOT NULL DEFAULT 0,
  sync_ok INTEGER NOT NULL DEFAULT 0, sync_fail INTEGER NOT NULL DEFAULT 0,
  pdf_ok INTEGER NOT NULL DEFAULT 0, pdf_fail INTEGER NOT NULL DEFAULT 0,
  ai_asked INTEGER NOT NULL DEFAULT 0, ai_answered INTEGER NOT NULL DEFAULT 0, ai_cite INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, app)
) WITHOUT ROWID;
-- failure kinds: kind = 'sync:timeout' | 'pdf:nospace' ...
CREATE TABLE IF NOT EXISTS daily_kind (day TEXT NOT NULL, kind TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, kind)) WITHOUT ROWID;
