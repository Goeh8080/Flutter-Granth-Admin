import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;

/// Where the session cookie lives between app launches.
abstract class CookieStore {
  Future<String?> read();
  Future<void> write(String? cookie);
}

class MemoryCookieStore implements CookieStore {
  String? _v;
  @override
  Future<String?> read() async => _v;
  @override
  Future<void> write(String? cookie) async => _v = cookie;
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class SessionExpiredException extends ApiException {
  const SessionExpiredException()
    : super(
        'सत्र समाप्त, कृपया फिर से लॉगिन करें / Session expired, please log in again',
      );
}

/// A file to upload as a multipart part.
class UploadFile {
  final String field;
  final String path;
  const UploadFile(this.field, this.path);
}

/// Cookie-aware client for `https://granth.wnmsolutions.com/?action=...`.
class ApiClient {
  ApiClient({
    this.baseUrl = 'https://granth.wnmsolutions.com/',
    CookieStore? store,
    http.Client? client,
  }) : store = store ?? MemoryCookieStore(),
       _http = client ?? http.Client();

  final String baseUrl;
  final CookieStore store;
  final http.Client _http;
  String? _cookie; // "PHPSESSID=..."
  bool _loaded = false;
  static const _timeout = Duration(seconds: 10);
  static const _uploadTimeout = Duration(seconds: 60);

  /// Called when the server tells us the session is gone.
  void Function()? onSessionExpired;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      _cookie = await store.read().timeout(const Duration(seconds: 5));
    } catch (_) {
      _cookie = null; // unreadable store: behave as logged out
    }
    _loaded = true;
  }

  Future<bool> get hasCookie async {
    await _ensureLoaded();
    return _cookie != null && _cookie!.isNotEmpty;
  }

  Future<void> clearCookie() async {
    _cookie = null;
    _loaded = true;
    await store.write(null);
  }

  Uri actionUri(String action, [Map<String, String>? query]) {
    final q = <String, String>{'action': action, ...?query};
    return Uri.parse(baseUrl).replace(queryParameters: q);
  }

  Map<String, String> _headers([Map<String, String>? extra]) => {
    'Accept': 'application/json, text/plain, */*',
    'X-Requested-With': 'XMLHttpRequest',
    'Cookie': ?_cookie,
    ...?extra,
  };

  Future<void> _captureCookie(http.BaseResponse r) async {
    final sc = r.headers['set-cookie'];
    if (sc == null) return;
    final m = RegExp(r'PHPSESSID=([^;,\s]+)').firstMatch(sc);
    if (m != null) {
      final v = m.group(1)!;
      if (v == 'deleted') return;
      _cookie = 'PHPSESSID=$v';
      await store.write(_cookie);
    }
  }

  /// Bodies at least this big (bytes) are UTF-8/JSON decoded on a background isolate, so the
  /// ~100-granth / pramans lists never stall a frame on the UI thread.
  /// Mutable only so widget tests (which need a fake clock) can turn background decoding off.
  static int isolateDecodeThreshold = 64 * 1024;

  /// Test hook: counts background decodes.
  static int isolateDecodes = 0;

  Future<dynamic> _decode(http.Response r) async {
    if (r.statusCode >= 500) {
      throw ApiException('सर्वर त्रुटि (${r.statusCode}) / Server error');
    }
    if (r.statusCode >= 400) {
      throw ApiException('अनुरोध विफल (${r.statusCode}) / Request failed');
    }
    final bytes = r.bodyBytes;
    final res = bytes.length >= isolateDecodeThreshold
        ? await _runOffThread(bytes)
        : decodeBody(bytes);
    if (res.invalid)
      throw const ApiException('अमान्य उत्तर / Invalid server response');
    return res.json;
  }

  Future<DecodedBody> _runOffThread(List<int> bytes) async {
    try {
      isolateDecodes++;
      return await Isolate.run(() => decodeBody(bytes));
    } catch (_) {
      return decodeBody(bytes); // isolates unavailable: decode in place
    }
  }

  Future<T> _guard<T>(
    Future<T> Function() f, {
    Duration timeout = _timeout,
  }) async {
    try {
      return await f().timeout(timeout);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'समय समाप्त, फिर कोशिश करें / Request timed out',
      );
    } on SocketException {
      throw const ApiException('इंटरनेट कनेक्शन नहीं / No internet connection');
    } on HandshakeException {
      throw const ApiException(
        'सुरक्षित कनेक्शन विफल / Secure connection failed',
      );
    } on TlsException {
      throw const ApiException(
        'सुरक्षित कनेक्शन विफल / Secure connection failed',
      );
    } on http.ClientException {
      throw const ApiException('नेटवर्क त्रुटि / Network error');
    } on HttpException {
      throw const ApiException('नेटवर्क त्रुटि / Network error');
    } on FormatException {
      throw const ApiException('अमान्य उत्तर / Invalid server response');
    } on IOException {
      throw const ApiException('नेटवर्क त्रुटि / Network error');
    }
  }

  /// Raises [SessionExpiredException] when the server explicitly reports no login.
  Map<String, dynamic> _checkSession(
    dynamic json, {
    bool requireLogin = false,
  }) {
    final map = json is Map
        ? json.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{'data': json};
    if (requireLogin && map['isLogin'] == false) {
      onSessionExpired?.call();
      throw const SessionExpiredException();
    }
    return map;
  }

  // GETs currently on the wire, by URL: a second identical request (a tab and its detail page,
  // a refresh during a reload...) joins the first instead of hitting the server again. Any
  // write clears the map so nothing read after a write can join a pre-write response.
  final Map<String, Future<Map<String, dynamic>>> _inflight = {};

  /// Test hook: number of real GETs sent.
  int getsSent = 0;

  Future<Map<String, dynamic>> get(
    String action, {
    Map<String, String>? query,
    bool requireLogin = false,
  }) async {
    await _ensureLoaded();
    final uri = actionUri(action, query);
    final key = '${requireLogin ? 'L' : 'P'} $uri';
    final pending = _inflight[key];
    if (pending != null) return pending;
    late final Future<Map<String, dynamic>> f;
    f = _guard(() async {
      getsSent++;
      final r = await _http.get(uri, headers: _headers());
      await _captureCookie(r);
      return _checkSession(await _decode(r), requireLogin: requireLogin);
    });
    _inflight[key] = f;
    try {
      return await f;
    } finally {
      if (identical(_inflight[key], f)) _inflight.remove(key);
    }
  }

  Future<Map<String, dynamic>> postJson(
    String action,
    Map<String, dynamic> body, {
    bool requireLogin = true,
  }) async {
    await _ensureLoaded();
    _inflight.clear();
    return _guard(() async {
      final r = await _http.post(
        actionUri(action),
        headers: _headers({'Content-Type': 'application/json'}),
        body: jsonEncode(body),
      );
      await _captureCookie(r);
      _inflight.clear();
      return _checkSession(await _decode(r), requireLogin: requireLogin);
    });
  }

  Future<Map<String, dynamic>> postMultipart(
    String action,
    Map<String, String> fields, {
    List<UploadFile> files = const [],
    bool requireLogin = true,
  }) async {
    await _ensureLoaded();
    _inflight.clear();
    return _guard(() async {
      final req = http.MultipartRequest('POST', actionUri(action));
      req.headers.addAll(_headers());
      req.fields.addAll(fields);
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath(f.field, f.path));
      }
      final streamed = await _http.send(req);
      final r = await http.Response.fromStream(streamed);
      await _captureCookie(r);
      _inflight.clear();
      return _checkSession(await _decode(r), requireLogin: requireLogin);
    }, timeout: _uploadTimeout);
  }
}

/// Result of [decodeBody]: the JSON value, or [invalid] when the body is not JSON.
class DecodedBody {
  const DecodedBody(this.json, {this.invalid = false});
  final dynamic json;
  final bool invalid;
}

/// UTF-8 + JSON decode of an API body (top-level so it can run on an isolate).
DecodedBody decodeBody(List<int> bytes) {
  final body = utf8.decode(bytes).trim();
  if (body.isEmpty) return DecodedBody(<String, dynamic>{});
  // PHP may emit warnings before the JSON; take from the first brace.
  final start = body.indexOf(RegExp(r'[\{\[]'));
  if (start < 0) return const DecodedBody(null, invalid: true);
  try {
    return DecodedBody(jsonDecode(body.substring(start)));
  } on FormatException {
    return const DecodedBody(null, invalid: true);
  }
}
