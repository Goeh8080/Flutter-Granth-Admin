import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/api_client.dart' show ApiException;
import '../core/panel_config.dart';
import '../models/ai_models.dart';
import '../models/panel_models.dart';
import 'panel_token_store.dart';

/// Any error from the control server. Extends [ApiException] so the existing toast helpers work.
class PanelApiException extends ApiException {
  const PanelApiException(
    super.message, {
    this.code = 'error',
    this.status,
    this.errors = const [],
    this.extra = const {},
  });

  /// Server error code (`bad_credentials`, `invalid_structure`, ...) or a local one
  /// (`timeout`, `offline`, `network`, `bad_response`).
  final String code;
  final int? status;

  /// Human readable details (`errors[]` in the response).
  final List<String> errors;
  final Map<String, dynamic> extra;

  bool get isNetwork =>
      const {'timeout', 'offline', 'network', 'tls'}.contains(code);

  /// Message plus the server's detail lines (for toasts / dialogs).
  String get fullMessage =>
      errors.isEmpty ? message : '$message\n${errors.take(5).join('\n')}';
}

/// `401 unauthorized` on a protected call: the session is gone, go back to the panel login.
class PanelUnauthorized extends PanelApiException {
  const PanelUnauthorized()
    : super(
        'ऐप कंट्रोल का सत्र समाप्त, फिर से लॉगिन करें / Control session expired, please log in again',
        code: 'unauthorized',
        status: 401,
      );
}

class PanelRateLimited extends PanelApiException {
  const PanelRateLimited(this.retryAfter)
    : super(
        'बहुत ज़्यादा कोशिशें — थोड़ी देर बाद फिर करें / Too many attempts, try later',
        code: 'rate_limited',
        status: 429,
      );
  final int retryAfter;
  @override
  String get fullMessage {
    final m = (retryAfter / 60).ceil();
    return m > 0
        ? 'बहुत ज़्यादा कोशिशें — $m मिनट बाद फिर करें / Too many attempts, retry in $m min'
        : message;
  }
}

/// Hindi/Hinglish text for a server error code. Unknown codes get a generic message.
String panelErrorText(String code, int? status) {
  switch (code) {
    case 'bad_credentials':
      return 'गलत पासवर्ड / Wrong password';
    case 'unauthorized':
      return 'ऐप कंट्रोल का सत्र समाप्त / Control session expired';
    case 'csrf':
    case 'bad_origin':
      return 'अनुरोध अस्वीकृत / Request rejected';
    case 'not_found':
      return 'नहीं मिला / Not found';
    case 'granth_not_found':
      return 'ग्रंथ नहीं मिला / Granth not found';
    case 'version_not_found':
      return 'वह वर्ज़न नहीं मिला / Version not found';
    case 'session_not_found':
      return 'सेशन नहीं मिला / Session not found';
    case 'no_changes':
      return 'कोई बदलाव नहीं है / No changes to publish';
    case 'leaf_in_use':
      return 'इस फ़ोल्डर में ग्रंथ रखे हैं / Granths are placed in a removed folder';
    case 'invalid_structure':
    case 'invalid_config':
    case 'validation_failed':
      return 'फ़ोल्डर/कॉन्फ़िग गलत है / Invalid structure or config';
    case 'unknown_leaf':
      return 'फ़ोल्डर मौजूद नहीं / Unknown folder';
    case 'bad_hidden':
      return 'छिपाने की सूची गलत / Bad hidden list';
    case 'nothing_to_change':
      return 'बदलने को कुछ नहीं / Nothing to change';
    case 'bad_sample':
      return 'analytics_sample 0 से 1 के बीच हो / Sample must be 0..1';
    case 'bad_ids':
      return 'ग्रंथ ID गलत / Bad ids';
    case 'bad_version':
      return 'वर्ज़न गलत / Bad version';
    case 'invalid_announcement':
      return 'घोषणा गलत है / Invalid announcement';
    case 'invalid_endpoint':
      return 'AI endpoint गलत (https चाहिए) / Invalid endpoint (https required)';
    case 'weak_password':
      return 'नया पासवर्ड 10 से 256 अक्षर का हो / New password must be 10–256 characters';
    case 'forbidden':
      return 'सिर्फ़ मालिक (owner) के लिए / Owner only';
    case 'admin_not_found':
      return 'एडमिन नहीं मिला / Admin not found';
    case 'username_taken':
      return 'यह यूज़रनेम पहले से है / Username already taken';
    case 'bad_username':
      return 'यूज़रनेम गलत (3–32: a-z 0-9 _ . -) / Bad username';
    case 'bad_role':
      return 'भूमिका गलत / Bad role';
    case 'cannot_modify_self':
      return 'अपने खाते पर यह नहीं हो सकता / You cannot do this to yourself';
    case 'last_owner':
      return 'कम से कम एक सक्रिय owner ज़रूरी है / At least one active owner is required';
    case 'use_change_password':
      return 'अपना पासवर्ड सेटिंग्स से बदलें / Use change password for yourself';
    case 'contact_not_found':
      return 'संपर्क नहीं मिला / Contact not found';
    case 'rate_limited':
      return 'बहुत ज़्यादा कोशिशें / Too many attempts';
    case 'too_soon':
      return 'थोड़ा रुकें (30 सेकंड) / Please wait a moment';
    case 'bad_request':
      return 'अनुरोध गलत / Bad request';
    default:
      if (status != null && status >= 500)
        return 'सर्वर त्रुटि ($status) / Server error';
      return 'अनुरोध विफल${status != null ? ' ($status)' : ''} / Request failed';
  }
}

/// Typed client for `{base}/admin/api/*` (CONTRACT.md §3), using the bearer flow.
///
/// * Login: `POST /login` with `X-Client: app` returns a bearer token which is kept in [store].
/// * Every other call sends `Authorization: Bearer <token>` (no CSRF needed).
/// * Any `401` on a protected call clears the token and fires [onUnauthorized].
/// * The token is never logged and never part of an exception message.
class PanelApi {
  PanelApi({
    String? baseUrl,
    PanelTokenStore? store,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.clientName = kPanelClientName,
  }) : baseUrl = baseUrl ?? kPanelDefaultBase,
       store = store ?? MemoryPanelTokenStore(),
       _http = client ?? http.Client();

  /// Single place for the server address (workers.dev now, a custom domain later).
  String baseUrl;
  final PanelTokenStore store;
  final http.Client _http;
  final Duration timeout;
  final String clientName;

  /// Called after a protected request got `401` (token already cleared).
  void Function()? onUnauthorized;

  String? _token;
  bool _loaded = false;

  Future<void> loadToken() async {
    if (_loaded) return;
    try {
      _token = await store.read().timeout(const Duration(seconds: 5));
    } catch (_) {
      _token = null;
    }
    _loaded = true;
  }

  Future<bool> get hasToken async {
    await loadToken();
    return _token != null && _token!.isNotEmpty;
  }

  Future<void> clearToken() async {
    _token = null;
    _loaded = true;
    await store.write(null);
  }

  Uri uri(String path, [Map<String, String>? query]) {
    final b = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final u = Uri.parse('$b/admin/api$path');
    return query == null || query.isEmpty
        ? u
        : u.replace(queryParameters: query);
  }

  // ------------------------------------------------------------------ transport

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool auth = true,
    Map<String, String>? headers,
  }) async {
    await loadToken();
    if (auth && (_token == null || _token!.isEmpty)) {
      throw const PanelUnauthorized();
    }
    final h = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (auth) 'Authorization': 'Bearer $_token',
      ...?headers,
    };
    final u = uri(path, query);
    final http.Response r;
    try {
      final Future<http.Response> f = switch (method) {
        'GET' => _http.get(u, headers: h),
        'POST' => _http.post(
          u,
          headers: h,
          body: body == null ? null : jsonEncode(body),
        ),
        'PUT' => _http.put(
          u,
          headers: h,
          body: body == null ? null : jsonEncode(body),
        ),
        'DELETE' => _http.delete(u, headers: h),
        _ => throw ArgumentError('method $method'),
      };
      r = await f.timeout(timeout);
    } on TimeoutException {
      throw const PanelApiException(
        'समय समाप्त, फिर कोशिश करें / Request timed out',
        code: 'timeout',
      );
    } on SocketException {
      throw const PanelApiException(
        'इंटरनेट कनेक्शन नहीं / No internet connection',
        code: 'offline',
      );
    } on HandshakeException {
      throw const PanelApiException(
        'सुरक्षित कनेक्शन विफल / Secure connection failed',
        code: 'tls',
      );
    } on TlsException {
      throw const PanelApiException(
        'सुरक्षित कनेक्शन विफल / Secure connection failed',
        code: 'tls',
      );
    } on http.ClientException {
      throw const PanelApiException(
        'नेटवर्क त्रुटि / Network error',
        code: 'network',
      );
    } on HttpException {
      throw const PanelApiException(
        'नेटवर्क त्रुटि / Network error',
        code: 'network',
      );
    }
    return _handle(r, auth: auth);
  }

  Future<Map<String, dynamic>> _handle(
    http.Response r, {
    required bool auth,
  }) async {
    Map<String, dynamic> j = const {};
    final text = utf8.decode(r.bodyBytes, allowMalformed: true).trim();
    if (text.isNotEmpty) {
      try {
        final d = jsonDecode(text);
        if (d is Map) {
          j = Map<String, dynamic>.from(d);
        } else {
          j = {'data': d};
        }
      } on FormatException {
        if (r.statusCode < 400) {
          throw const PanelApiException(
            'अमान्य उत्तर / Invalid server response',
            code: 'bad_response',
          );
        }
      }
    }
    final s = r.statusCode;
    if (s < 400) return j;
    final code = pStr(j['error'], s >= 500 ? 'internal' : 'error');
    // `401 bad_credentials` on /password means a wrong current password, not an expired session.
    if (s == 401 && auth && code != 'bad_credentials') {
      await clearToken();
      onUnauthorized?.call();
      throw const PanelUnauthorized();
    }
    if (s == 429) {
      final ra = pInt(j['retry_after'], pInt(r.headers['retry-after'], 0));
      throw PanelRateLimited(ra);
    }
    final errors = [
      ...pStrList(j['errors']),
      if (j['message'] is String) pStr(j['message']),
    ];
    final extra = Map<String, dynamic>.from(j)..remove('error');
    throw PanelApiException(
      panelErrorText(code, s),
      code: code,
      status: s,
      errors: errors,
      extra: extra,
    );
  }

  Future<Map<String, dynamic>> _get(String p, [Map<String, String>? q]) =>
      _call('GET', p, query: q);
  Future<Map<String, dynamic>> _post(String p, [Object? body]) =>
      _call('POST', p, body: body ?? const {});
  Future<Map<String, dynamic>> _put(String p, Object body) =>
      _call('PUT', p, body: body);

  // ------------------------------------------------------------------ auth / session

  /// Logs in and keeps the bearer token in the token store. Returns the server answer without the token.
  Future<PanelLogin> login(
    String password, {
    String username = kPanelUsername,
  }) async {
    final j = await _call(
      'POST',
      '/login',
      auth: false,
      body: {'username': username, 'password': password},
      headers: {'X-Client': 'app', 'X-Client-Name': clientName},
    );
    final l = PanelLogin.fromJson(j);
    if (l.token.isEmpty) {
      throw const PanelApiException(
        'अमान्य उत्तर / Invalid server response',
        code: 'bad_response',
      );
    }
    _token = l.token;
    _loaded = true;
    await store.write(l.token);
    return l;
  }

  /// Revokes the session on the server (best effort) and forgets the token locally.
  Future<void> logout() async {
    try {
      if (await hasToken) await _call('POST', '/logout', body: const {});
    } catch (_) {
      // offline or already expired: still forget the token below
    } finally {
      await clearToken();
    }
  }

  Future<PanelMe> me() async => PanelMe.fromJson(await _get('/me'));

  Future<List<PanelSession>> sessions() async =>
      pList((await _get('/sessions'))['items'], PanelSession.fromJson);
  Future<void> revokeSession(String sid) async =>
      _call('DELETE', '/sessions/$sid');
  Future<void> revokeOtherSessions() async => _post('/sessions/revoke_all');

  /// New password must be 10–256 characters (server enforces; `422 weak_password`).
  Future<void> changePassword(String current, String next) async =>
      _post('/password', {'current': current, 'new': next});

  // ------------------------------------------------------------------ admins (owner only)

  Future<PanelAdminList> admins() async =>
      PanelAdminList.fromJson(await _get('/admins'));

  Future<PanelAdmin> createAdmin(
    String username,
    String password, {
    String role = 'admin',
  }) async => PanelAdmin.fromJson(
    pMap(
      (await _post('/admins', {
        'username': username,
        'password': password,
        'role': role,
      }))['admin'],
    ),
  );

  /// Change [role] and/or [disabled] of an admin (not yourself).
  Future<PanelAdmin> updateAdmin(
    String username, {
    String? role,
    bool? disabled,
  }) async => PanelAdmin.fromJson(
    pMap(
      (await _put('/admins/${Uri.encodeComponent(username)}', {
        'role': ?role,
        'disabled': ?disabled,
      }))['admin'],
    ),
  );

  Future<void> resetAdminPassword(String username, String password) async =>
      _post('/admins/${Uri.encodeComponent(username)}/password', {
        'password': password,
      });

  Future<int> revokeAdminSessions(String username) async => pInt(
    (await _post(
      '/admins/${Uri.encodeComponent(username)}/revoke_sessions',
    ))['revoked'],
  );

  Future<void> deleteAdmin(String username) async =>
      _call('DELETE', '/admins/${Uri.encodeComponent(username)}');

  // ------------------------------------------------------------------ contacts (विशेष जानकार)

  Future<PanelContacts> contacts() async =>
      PanelContacts.fromJson(await _get('/contacts'));

  /// "Save screen": replaces the title and the whole list (array order = display order). Goes to the draft.
  Future<PanelContacts> putContacts({
    String? title,
    required List<PanelContact> items,
  }) async => PanelContacts.fromJson(
    await _put('/contacts', {
      'title': ?title,
      'items': [for (final c in items) c.toJson()],
    }),
  );

  // ------------------------------------------------------------------ granths

  /// [sort]: number|position|id|title|opens|watch|praman|newest (server default: catalogue number, #1 first).
  Future<PanelGranthList> granths({String? sort, String? order}) async =>
      PanelGranthList.fromJson(
        await _get('/granths', {'sort': ?sort, 'order': ?order}),
      );

  /// Change one granth in the shared draft. Pass [leaf] to move it, [clearLeaf] to drop the override
  /// (`leaf:null` = default placement) and/or [hidden] to show/hide it.
  Future<void> setGranth(
    String id, {
    String? leaf,
    bool clearLeaf = false,
    bool? hidden,
  }) async {
    final b = <String, Object?>{
      if (clearLeaf) 'leaf': null else 'leaf': ?leaf,
      'hidden': ?hidden,
    };
    if (b.isEmpty) return;
    await _put('/granths/${Uri.encodeComponent(id)}', b);
  }

  /// Apply the same change to up to 300 granths (`POST /granths/bulk`). Returns how many changed.
  Future<int> bulkGranths(
    List<String> ids, {
    String? leaf,
    bool? hidden,
  }) async {
    if (ids.isEmpty) return 0;
    if (ids.length > 300) throw ArgumentError('at most 300 ids per bulk call');
    final j = await _post('/granths/bulk', {
      'ids': ids,
      'leaf': ?leaf,
      'hidden': ?hidden,
    });
    return pInt(j['changed'], ids.length);
  }

  // ------------------------------------------------------------------ structure

  Future<PanelStructure> structure() async =>
      PanelStructure.fromJson(await _get('/structure'));

  /// Sends the whole tree. With [dropOverrides] granths placed in removed folders fall back to default placement.
  Future<void> putStructure(
    Map<String, dynamic> structure, {
    bool dropOverrides = false,
  }) async => _put('/structure', {
    'structure': structure,
    if (dropOverrides) 'drop_overrides': true,
  });

  // ------------------------------------------------------------------ draft / publish / history

  Future<PanelDraft> draft() async => PanelDraft.fromJson(await _get('/draft'));
  Future<PanelDraft> draftDiff() async =>
      PanelDraft.fromJson(await _get('/draft/diff'));
  Future<void> discardDraft() async => _post('/draft/discard');

  Future<PublishResult> publish({
    String? note,
    bool force = false,
    bool allowEmpty = false,
  }) async {
    final n = note?.trim();
    return PublishResult.fromJson(
      await _post('/publish', {
        if (n != null && n.isNotEmpty)
          'note': n.length > 200 ? n.substring(0, 200) : n,
        if (force) 'force': true,
        if (allowEmpty) 'allow_empty': true,
      }),
    );
  }

  Future<PublishResult> rollback(int toVersion, {String? note}) async {
    final n = note?.trim();
    return PublishResult.fromJson(
      await _post('/rollback', {
        'to_version': toVersion,
        if (n != null && n.isNotEmpty)
          'note': n.length > 200 ? n.substring(0, 200) : n,
      }),
    );
  }

  Future<PanelVersions> versions() async =>
      PanelVersions.fromJson(await _get('/versions'));

  Future<PanelVersionDetail> version(int v, {int? against}) async =>
      PanelVersionDetail.fromJson(
        await _get(
          '/versions/$v',
          against == null ? null : {'against': '$against'},
        ),
      );

  // ------------------------------------------------------------------ alerts / sync

  Future<PanelAlerts> alerts() async =>
      PanelAlerts.fromJson(await _get('/alerts'));
  Future<void> ackGranth(String id) async =>
      _post('/alerts/g:${Uri.encodeComponent(id)}/ack');
  Future<void> ackAlert(String n) async =>
      _post('/alerts/a:${Uri.encodeComponent(n)}/ack');
  Future<SyncResult> syncNow() async =>
      SyncResult.fromJson(await _post('/sync'));

  // ------------------------------------------------------------------ settings / audit

  Future<PanelSettings> settings() async =>
      PanelSettings.fromJson(await _get('/settings'));

  /// Only the fields you pass are changed.
  Future<void> putSettings({
    bool? aiEnabled,
    bool? analyticsEnabled,
    double? analyticsSample,
    Map<String, Object?>? announcement,
    String? aiEndpoint,
    // CONTRACT §4.1: `ui.grid` 1|2|3;
    // [clearUiGrid] sends `ui:{grid:null}` (the app then uses its default of 3).
    int? uiGrid,
    bool clearUiGrid = false,
  }) async {
    final flags = <String, Object?>{
      'ai_enabled': ?aiEnabled,
      'analytics_enabled': ?analyticsEnabled,
      'analytics_sample': ?analyticsSample,
    };
    final b = <String, Object?>{
      if (flags.isNotEmpty) 'flags': flags,
      'announcement': ?announcement,
      'ai_endpoint': ?aiEndpoint,
      if (uiGrid != null)
        'ui': {'grid': uiGrid}
      else if (clearUiGrid)
        'ui': {'grid': null},
    };
    if (b.isEmpty) return;
    await _put('/settings', b);
  }

  // ------------------------------------------------------------------ AI tab (CONTRACT §4.3/§4.4)
  // Paths and bodies follow CONTRACT.md §4 (granth_admin_panel/src/ai_admin.js).
  // Server limits: question 5..500, answer 50..2000 chars, 500 items.

  Future<AiKnowledgeList> aiKnowledge({
    int limit = 200,
    int offset = 0,
    String? q,
  }) async => AiKnowledgeList.fromJson(
    await _get('/ai/knowledge', {
      'limit': '$limit',
      'offset': '$offset',
      if (q != null && q.isNotEmpty) 'q': q,
    }),
  );
  Future<AiKnowledge> aiKnowledgeCreate({
    required String question,
    required String answer,
    List<String> tags = const [],
    bool visible = true,
  }) async => AiKnowledge.fromJson(
    pMap(
      (await _post('/ai/knowledge', {
        'question': question,
        'answer': answer,
        'tags': tags,
        'visible': visible,
      }))['item'],
    ),
  );
  Future<AiKnowledge> aiKnowledgeUpdate(
    int id, {
    String? question,
    String? answer,
    List<String>? tags,
    bool? visible,
  }) async => AiKnowledge.fromJson(
    pMap(
      (await _put('/ai/knowledge/$id', {
        'question': ?question,
        'answer': ?answer,
        'tags': ?tags,
        'visible': ?visible,
      }))['item'],
    ),
  );
  Future<void> aiKnowledgeDelete(int id) async =>
      _call('DELETE', '/ai/knowledge/$id');

  Future<AiQuestionList> aiQuestions({
    String status = 'all',
    int limit = 50,
    int offset = 0,
  }) async => AiQuestionList.fromJson(
    await _get('/ai/questions', {
      'status': status,
      'limit': '$limit',
      'offset': '$offset',
    }),
  );
  Future<AiQuestion> aiQuestion(int id) async =>
      AiQuestion.fromJson(pMap((await _get('/ai/questions/$id'))['item']));
  Future<void> aiQuestionsMarkRead({List<int>? ids}) async => _post(
    '/ai/questions/mark_read',
    ids == null ? {'all': true} : {'ids': ids},
  );
  Future<AiQuestion> aiQuestionAnswer(
    int id,
    String answer, {
    bool addToKnowledge = false,
    String? knowledgeQuestion,
    String? knowledgeAnswer,
  }) async => AiQuestion.fromJson(
    pMap(
      (await _post('/ai/questions/$id/answer', {
        'answer': answer,
        if (addToKnowledge) 'add_to_knowledge': true,
        if (addToKnowledge)
          'knowledge': {
            'question': ?knowledgeQuestion,
            'answer': ?knowledgeAnswer,
          },
      }))['item'],
    ),
  );
  /// Round 3 (server CONTRACT §5): support tickets, AI flags, highlights, named events.
  /// Raw JSON on purpose: these screens read the maps directly.
  Future<Map<String, dynamic>> raw(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) => _call(method, path, query: query, body: body);

  Future<AiSummary> aiSummary() async =>
      AiSummary.fromJson(await _get('/ai/summary'));
  Future<void> aiQuestionMark(
    int id, {
    bool? read,
    bool reopen = false,
  }) async => _post('/ai/questions/$id/mark', {
    'read': ?read,
    if (reopen) 'status': 'new',
  });
  Future<void> aiQuestionReject(int id) async =>
      _post('/ai/questions/$id/reject');
  Future<void> aiQuestionDelete(int id) async =>
      _call('DELETE', '/ai/questions/$id');

  Future<List<AuditItem>> audit({int limit = 100}) async => pList(
    (await _get('/audit', {'limit': '${limit.clamp(1, 300)}'}))['items'],
    AuditItem.fromJson,
  );

  // ------------------------------------------------------------------ stats

  static int _days(int d) => const [7, 30, 90].contains(d) ? d : 7;

  Future<StatsOverview> statsOverview({int days = 7}) async =>
      StatsOverview.fromJson(
        await _get('/stats/overview', {'days': '${_days(days)}'}),
      );

  Future<GranthStatsList> statsGranths({int days = 7}) async =>
      GranthStatsList.fromJson(
        await _get('/stats/granths', {'days': '${_days(days)}'}),
      );

  Future<FolderStatsList> statsFolders({int days = 7}) async =>
      FolderStatsList.fromJson(
        await _get('/stats/folders', {'days': '${_days(days)}'}),
      );

  /// [kind] is `granth` or `folder`.
  Future<StatsSeries> statsSeries(
    String kind,
    String id, {
    int days = 30,
  }) async => StatsSeries.fromJson(
    await _get('/stats/series', {
      'kind': kind,
      'id': id,
      'days': '${_days(days)}',
    }),
  );
}
