# Granth web admin panel — API notes (reverse-engineered, read-only probing)

Probed 2026-10-21 against https://granth.wnmsolutions.com with an admin session.
Only login, logout and read actions were called. Every write format below is
taken from `/js/script.js` (identical for ?v=5/11/18, md5 75adbe4f…) and the inline
scripts in the PHP pages. It was not sent to the server.

## Base URL and session
* Every admin action is `https://granth.wnmsolutions.com/?action=<name>` (the JS calls
  `fetch('?action=…')` from pages at the site root; `loadfeedbacks` uses `index.php?action=…`, which is the same script).
* Images and files use paths relative to the site root: `uploads/praman_x.jpg` (praman image),
  `granths/praman_x.jpg` (granth image), `granths/praman_editorImagex.jpg` (editor/vivran image).
  Full URL: `https://granth.wnmsolutions.com/<path>` (HEAD returns 200).
* Session: login sets the `PHPSESSID` cookie. Send it on every request.
* Every JSON response looks like `{"success":bool,"isLogin":bool,"data":…}`. **`isLogin` is NOT a reliable
  login indicator**: unauthenticated `get_topics` / `get_stats` / `get_topic` still return `"isLogin":true`.
  Real login signals:
  * `get_feedbacks` without a session returns `{"success":false,"isLogin":false,"data":[]}`. With a session it returns `success:true`.
  * Pages render `isLigin = true|false` inline, server-side.
  * `get_topics` without a session hides inactive topics (330 rows). With a session it includes them (333).
  The app checks the session with `get_feedbacks` and returns to login when that check fails or any response has `isLogin:false`.
* All numbers come back as strings (`"id":"195"`). Some fields can be `null` (`topic_id` on granths;
  `granth_id`, `granth_title`, `granth_image`, `editorImagePath` on pramans; `topic_title`, `praman_title` on feedbacks).

## Read actions (all GET, verified live)
| action | params | response `data` |
|---|---|---|
| `get_stats` | – | `{topics:"333", granths:"104", pramans:"823"}` |
| `get_topics` | `&topic=<search>` (title LIKE) **or** `&disabled=1` (only inactive topics) | list of Topic |
| `get_topic` | `&topic=<id>` | Topic |
| `get_granths` | `&granth=<search>` | list of Granth (`&disabled=1` is ignored) |
| `get_granth` | `&granth=<id>` | Granth |
| `get_pramans` | exactly ONE of `&praman=<search>`, `&topicId=<id>`, `&granthId=<id>`, `&is_youtube=1`, `&id=<id>` (JS overwrites the string, so the last one set wins: id > is_youtube > granthId > topicId > praman) | list of Praman |
| `get_praman` | `&praman=<id>` | Praman |
| `get_feedbacks` | – (needs login) | list of Feedback |
| `logout` | GET | (JS ignores the body) |

Topic: `id,title,description,position,user,isActive("1"/"0"),created_at,granth_count,praman_count`
Granth: `id,title,author,granthURL(PDF url, often ""),topic_id(null),description,imagePath,editorImagePath,position,user,isActive,created_at,pramanCount`
Praman: `id,title,description,is_favorate("0"/"1"),topic_id,granth_id,pageNumber,chapterNumber,image_path,youtube_url(video ID e.g. "HLhZeRregP0", embedded as youtube.com/embed/<id>?start=<s>),youtube_start,youtube_desc,user,isActive,created_at,topic_title,granth_title,granth_image,editorImagePath`
Feedback: `id,name,description,mob,topic_id,granth_id,praman_id,image,status,topic_title,granth_title,praman_title`

Lists are already in `position` order. Logged-in granth/praman lists returned only `isActive=1` rows at probe time, so no inactive ones exist right now, or the server filters them out.

## Login
`POST ?action=get_user`, `Content-Type: application/json`, body `{"username":"…","password":"…"}` →
`{"success":true}` (sets the session) or `{"success":false}`.

## Write actions (from the JS only, NOT exercised)
| action | method / content-type | body |
|---|---|---|
| `create_topic` | POST JSON | `{title, isActive:"1"/"0", description, formType:"add"/"edit", id:"" or topic id}` |
| `create_granth` | POST multipart | `title, author, description, granthPDF` (a **PDF URL text field**, not a file upload; it comes back as `granthURL`), `formType, id, isActive`, optional files `image`, `editorImage` |
| `create_praman` | POST multipart | `title, isActive, description, topic_id, granth_id, chapterNumber, youtube_url, youtube_desc, youtube_start, pageNumber, formType, id`, file `image` (required when formType=add, optional on edit) |
| `delete_topic` / `delete_granth` / `delete_praman` | GET `&id=<id>` | – (the web panel has these buttons commented out, but the actions exist) |
| `update_topic_order` | POST JSON | `{"topics":[<full topic objects in the new order>]}` (from topic-sort.php drag list) |
| `update_granth_order` | POST JSON | `{"granths":[<full granth objects in the new order>]}` (granth-sort.php) |
| `update_topic_orderByNumber` | POST JSON | `{topicId, currentPostion, newPosition}` (sic: "Postion"; UI commented out on the web) |
| `update_granth_orderByNumber` | POST JSON | `{granthId, currentPostion, newPosition}` |
| `set_pramanAsFavorate` | POST JSON | `{praman:<pramanId>, granthId:<granthId>}` → marks the default praman for a granth (shown only when the list is filtered by granth; UI commented out on the web) |
| `create_feedback` | POST multipart | `description, topic_id, granth_id, praman_id, mob, fname`, optional file `image` |
| `delete_feedback` | GET `&id=<id>` | – |

Validation in the web panel, mirrored in the app:
* topic: title is required.
* granth: title and author are required.
* praman: title, topic, granth and pageNumber (integer > 0) are required, and an image is required on add.
* feedback: name, description and mob are required.

* add vs edit: `formType=add|edit` plus `id`. Everything goes through the `create_*` action.
* isActive: `"1"` (Active) or `"0"` (In-Active) from a select element. It is sent with create/edit, and there is no separate toggle endpoint.
  The app's show/hide toggle therefore re-submits the full edit payload with the new isActive value.
  For granth/praman this is multipart without files, so the existing images are kept; that is the same as editing on the web without picking a new image.
* Write responses are expected as `{"success":true}`.

### Server-side protection of writes: partly confirmed by an accidental, rejected call
Write endpoints were never called on purpose. There was one accidental call:
1. On 2026-10-21, between about 20:20 and 20:35 IST, a bug in the first version of the app's unit test let multipart requests bypass the mock HTTP client.
2. Without a session cookie, that sent `create_praman` (formType=edit, id=9, title "P") 2 times and `create_granth` (formType=add, title "G") 3 times to the live server.
3. The server answered every one with `"isLogin":false` and rejected it. A logged-in read check afterwards confirmed nothing changed:
   * praman 9 still has its original title, page 658, topic 24 and granth 13;
   * no granth "G" exists, and the max granth id is still 110;
   * stats are still 333/104/823.

The bug is fixed: multipart now goes through the injected client, and tests install an HttpOverrides that blocks all real network access.
**Conclusion:** `create_praman` and `create_granth` do check the session server-side.
`create_topic`, the `delete_*` actions (plain GETs), the `update_*order*` actions, `set_pramanAsFavorate`, `create_feedback` and `delete_feedback` remain **unverified**.
`isLogin` on read responses is not meaningful.
**Recommendation:** the owner should confirm in the PHP source that every write and delete checks `$_SESSION`.
Deletes should also move from GET to POST with a CSRF token, because a GET delete can be triggered by any link while an admin is logged in.

## Pages found
`/` (dashboard + stats + feedback list + "Add Feedback" + contact email), `/topic.php`, `/topic-in-active.php`
(`get_topics&disabled=1`), `/topic-sort.php` (drag/move-up/down + Save → update_topic_order), `/granth.php`,
`/granth-sort.php` (→ update_granth_order), `/praman.php` (supports `?topic=`, `?granth=`, `?id=`), `/praman-youtube.php`
(`get_pramans&is_youtube=1`, shows YouTube embeds), `/highlighter.html` (standalone, client-side "Photo Merger & Highlighter"
tool with no API calls), `/login.php` (login modal fragment).

## Parity checklist (web function → app)
| Web panel function | App |
|---|---|
| Login() / get_user | LoginScreen |
| logout() | अधिक (More) tab → Logout with confirm (calls `?action=logout`, clears cookie) |
| session (isLigin) | Startup and resume check via get_feedbacks; auto-return to login |
| loadStats() dashboard + header counts | Dashboard tab: stat cards (tap → tab), pull-to-refresh |
| goTo('topic'/'granth'/'praman') dash cards | Dashboard cards switch tabs |
| Contact email card | Dashboard contact card + More → mailto |
| loadfeedbacks() list | Dashboard: latest 3 + "See all" → Feedback screen (also More → Feedback, Dashboard quick action) |
| saveFeedback() create_feedback | Feedback list → "+" → FeedbackForm (name, mob, description, topic/granth/praman pickers, image) |
| removeFeedback() delete_feedback | Feedback screen → trash button on each card → confirm dialog |
| loadTopics() / search + datalist | Topics tab: search field with live suggestions (local filter + server `&topic=` search) |
| topic-in-active.php (`disabled=1`) | Topics tab segmented control: All / Inactive |
| editTopic / saveTopic (add/edit, isActive) | TopicForm sheet |
| deleteTopic | Topic detail/context → Delete (confirm) |
| green/red dot isActive | Status dot + Show/Hide toggle action |
| showPramanForTopic | Topic detail → its pramans (`topicId`) |
| addPramanForTopic | Topic detail → "+ Praman" (prefilled topic) |
| topic-sort.php drag/up/down + Save (update_topic_order) | Topics → Reorder screen (drag handles + up/down + Save) |
| arrangeTopic (update_topic_orderByNumber) | Topic detail → "Move to position…" |
| shareLink('topic') | Share action (system share sheet, same praman.php?topic=id URL) |
| loadGranths() / search + datalist | Granths tab with search + suggestions |
| editGranth / saveGranth (image, editorImage, PDF URL, isActive) | GranthForm sheet |
| deleteGranth | Granth detail → Delete (confirm) |
| granthURL 👁 link | Granth detail → "Open PDF" (external) |
| showPramanForGranth / addPramanForGranth | Granth detail → pramans (`granthId`) / "+ Praman" |
| granth-sort.php (update_granth_order) | Granths → Reorder screen |
| arrangeGranth (update_granth_orderByNumber) | Granth detail → "Move to position…" |
| shareLink('granth') | Share action |
| loadPramans() / search + datalist | Pramans tab with search + suggestions |
| filter by topic / granth | Pramans tab filter chips (topic picker, granth picker) |
| praman.php?id= | Praman detail (get_praman) |
| praman-youtube.php (is_youtube=1) | Pramans tab filter "YouTube" + YouTube open/thumbnail in detail |
| editPraman / savePraman (all fields, image required on add) | PramanForm sheet |
| deletePraman | Praman detail → Delete (confirm) |
| setFavoratePraman (set_pramanAsFavorate) | Praman detail / list filtered by granth → heart "Set as granth default" |
| is_favorate heart | Heart badge on cards |
| openPopup (praman image + editor image + granth image) | Full-screen zoomable image viewer (pinch, swipe between images) |
| shareLink('praman') | Share action |
| x/y counter tags (1/total) | Index badge on list cards |
| highlighter.html | More → "Photo Merger & Highlighter (web)" opens the page in the browser (pure client-side tool, no API; not re-implemented natively) |
| takeToTop button | Floating ↑ glass button appears after scrolling (all list pages) |

Every app entry point listed above is implemented. The status column below shows what has been checked:
* **UI-tested**: exercised by `test/ui_flow_test.dart` offline with captured live JSON.
* **API-tested**: the payload is verified by `test/api_test.dart` with a mock client.
* **Live-read**: verified against the server with `tool/smoke_test.dart`.

| Area | Status |
|---|---|
| Login, logout, session check | UI-tested, API-tested, live-read |
| Stats, all lists, search, filters (topic/granth/YouTube/inactive), details, feedback list | UI-tested, live-read |
| Topic, granth, praman and feedback forms (open/cancel), action sheet, delete confirm, picker sheet, theme | UI-tested |
| All write payloads (create_* / delete_* / order / favourite) | API-tested against a mock only. **Never exercised on the live server**, so the server's acceptance of the app's multipart/JSON is not proven |
| Image upload from gallery/camera, PDF/YouTube/mail external open, share sheet | Built, but not run on a device (no working emulator on the box) |

---

## Control server (second backend)

Separate from everything above. Base `https://granth-admin.vedpuran8090.workers.dev` (single constant
`kPanelDefaultBase`, overridable). Full contract: `server/CONTRACT.md` (§1 config.json, §2 `/events`, §3 admin API under
`/admin/api`). The app uses the bearer flow: `POST /admin/api/login` with header `X-Client: app` and
`{username,password}` returns `{token}`; every later call sends `Authorization: Bearer <token>` (no CSRF). A 401 (other
than `bad_credentials` on `/password`) means the session ended, so the app returns to the control login. 429 carries
`retry_after`.

Used by the app: login/logout/me/sessions/password, granths (+sort), granths/bulk, structure, draft, draft/diff,
draft/discard, publish, rollback, versions, alerts (+ack), sync, settings, audit, stats/overview|granths|folders|series.
Not used yet: `/admins` and `/contacts` (owner-only user management and the contacts page).
