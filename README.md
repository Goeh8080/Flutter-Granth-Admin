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
