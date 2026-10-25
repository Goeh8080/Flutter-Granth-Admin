# ग्रंथ प्रबंधन Admin (Flutter, Android)

Admin app for https://granth.wnmsolutions.com. It talks to the same `?action=` endpoints as the PHP web panel.
See API_NOTES.md for the API map and the parity checklist.

* `lib/core`: cookie-aware `ApiClient` (PHPSESSID is kept in shared_preferences) and `AppState`
* `lib/services/granth_api.dart`: one method per web-panel action
* `lib/models`: null-safe models (string numbers, nulls)
* `lib/theme`: liquid-glass theme (backdrop, `Glass`, spring curve) and bundled Noto Sans Devanagari / Tiro Devanagari fonts
* `lib/widgets`: sheets, dialogs, toast, animated lists, fields, image picker
* `lib/screens`: login, home tabs, dashboard, topics, granths, pramans, details, forms, reorder, feedback, image viewer, more

Build: `flutter build apk --release` → `build_output/granth_admin.apk`

Tests:
* `flutter test`: offline. It runs model, API-payload and full UI flows against the fixtures in `_probe/`.
* Read-only live smoke test: `GRANTH_USER=.. GRANTH_PASS=.. dart run tool/smoke_test.dart`

## Two backends (दो सर्वर)

| | Granth data (विषय / ग्रंथ / प्रमाण) | ऐप कंट्रोल + आँकड़े |
|---|---|---|
| Server | https://granth.wnmsolutions.com (PHP, `?action=`) | Cloudflare Worker `granth-admin` (`server/`) |
| Login | wnm username/password, session cookie | **separate** username `goutam` + its own password, bearer token |
| Code | `lib/services/granth_api.dart`, `AppState.loggedIn` | `lib/services/panel_api.dart`, `lib/core/panel_state.dart` |
| Token storage | cookie in shared_preferences (as before) | `flutter_secure_storage` (Keystore / Keychain), never logged |

Either login works on its own: with only wnm the control tab asks for its login, and with only the control server the
data tabs show a "wnm login" prompt. Nothing about the wnm flows changed.

Tabs: डैशबोर्ड · विषय · ग्रंथ · प्रमाण · **कंट्रोल** · अधिक. The कंट्रोल tab opens: आँकड़े (installs, active users, time used,
top granths/folders, screens, versions, failures), ग्रंथ (folder assignment, show/hide, bulk move, preview diff → publish),
फ़ोल्डर (religion/group/sub-group tree), नए ग्रंथ inbox, history + rollback, settings (flags, announcement, AI endpoint,
password, sessions, audit log). Edits go to one shared server **draft**; nothing reaches the user app until you **Publish**.

Server address: one constant, `kPanelDefaultBase` in `lib/core/panel_config.dart`. Override at build time with
`--dart-define=PANEL_BASE=https://admin.example.com`, or at runtime in अधिक → कंट्रोल सर्वर पता (this logs out of the control
server). Passwords are never stored in the app or the repo; only the session token (24 h sliding) is kept.

`server/` is the Worker source (see `server/README.md` and `server/CONTRACT.md`, the API contract the app follows).
It contains no secrets: `server/secrets/`, `.dev.vars` and `node_modules` are git-ignored.

Tests for the control server (`test/panel_api_test.dart`, `test/panel_models_test.dart`) use a mocked HTTP client and
contract-shaped JSON, so they run in CI without `_probe/` and without any network.
