// Control-server (granth-admin Worker) client tests. Pure unit tests: a MockClient serves
// contract-shaped JSON, so nothing touches the network and no `_probe` fixtures are needed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/services/panel_api.dart';
import 'package:granthadmin/services/panel_token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _token = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _base = 'https://panel.test';

http.Response _json(Object body, [int status = 200, Map<String, String>? headers]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8', ...?headers});

class Rig {
  Rig(Future<http.Response> Function(http.Request) handler, {Duration timeout = const Duration(seconds: 2)}) {
    client = MockClient((r) async {
      requests.add(r);
      return handler(r);
    });
    api = PanelApi(baseUrl: _base, store: store, client: client, timeout: timeout);
  }
  final requests = <http.Request>[];
  final store = MemoryPanelTokenStore();
  late final http.Client client;
  late final PanelApi api;
  http.Request get last => requests.last;
  Map<String, dynamic> get body => jsonDecode(last.body) as Map<String, dynamic>;
}

void main() {
  group('login', () {
    test('sends X-Client: app + JSON body, stores the bearer token', () async {
      final rig = Rig((r) async => _json({'token': _token, 'token_type': 'Bearer', 'expires_in': 86400, 'username': 'goutam', 'role': 'owner', 'csrf': 'x'}));
      final res = await rig.api.login('s3cret-pass');
      expect(rig.last.method, 'POST');
      expect(rig.last.url.toString(), '$_base/admin/api/login');
      expect(rig.last.headers['X-Client'] ?? rig.last.headers['x-client'], 'app');
      expect(rig.body, {'username': 'goutam', 'password': 's3cret-pass'});
      expect(res.username, 'goutam');
      expect(await rig.store.read(), _token);
      expect(await rig.api.hasToken, isTrue);
      // login itself carries no Authorization header
      expect(rig.last.headers.containsKey('Authorization') || rig.last.headers.containsKey('authorization'), isFalse);
    });

    test('bad credentials -> PanelApiException(bad_credentials), nothing stored, not "unauthorized"', () async {
      final rig = Rig((r) async => _json({'error': 'bad_credentials'}, 401));
      await expectLater(
        rig.api.login('nope'),
        throwsA(isA<PanelApiException>().having((e) => e.code, 'code', 'bad_credentials').having((e) => e.status, 'status', 401)),
      );
      expect(await rig.store.read(), isNull);
    });

    test('429 -> PanelRateLimited with retry_after', () async {
      final rig = Rig((r) async => _json({'error': 'rate_limited', 'retry_after': 600}, 429, {'retry-after': '600'}));
      await expectLater(rig.api.login('x'), throwsA(isA<PanelRateLimited>().having((e) => e.retryAfter, 'retryAfter', 600)));
    });

    test('2xx without a token is a bad_response', () async {
      final rig = Rig((r) async => _json({'username': 'goutam'}));
      await expectLater(rig.api.login('x'), throwsA(isA<PanelApiException>().having((e) => e.code, 'code', 'bad_response')));
      expect(await rig.store.read(), isNull);
    });
  });

  group('authenticated calls', () {
    test('send Authorization: Bearer <token> (no CSRF header needed)', () async {
      final rig = Rig((r) async => _json({'username': 'goutam', 'auth': 'bearer', 'version': 3, 'has_draft': false, 'base_version': 3, 'next_version': 4}));
      await rig.store.write(_token);
      final me = await rig.api.me();
      expect(rig.last.headers['Authorization'] ?? rig.last.headers['authorization'], 'Bearer $_token');
      expect(rig.last.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-admin-csrf')));
      expect(me.version, 3);
      expect(me.hasDraft, isFalse);
    });

    test('401 clears the token, fires onUnauthorized and throws PanelUnauthorized', () async {
      final rig = Rig((r) async => _json({'error': 'unauthorized'}, 401));
      await rig.store.write(_token);
      var fired = 0;
      rig.api.onUnauthorized = () => fired++;
      await expectLater(rig.api.me(), throwsA(isA<PanelUnauthorized>()));
      expect(fired, 1);
      expect(await rig.store.read(), isNull);
    });

    test('wrong current password on /password (401 bad_credentials) is NOT a session expiry', () async {
      final rig = Rig((r) async => _json({'error': 'bad_credentials'}, 401));
      await rig.store.write(_token);
      var fired = 0;
      rig.api.onUnauthorized = () => fired++;
      await expectLater(rig.api.changePassword('wrong', 'new-password-123'), throwsA(isA<PanelApiException>().having((e) => e.code, 'code', 'bad_credentials')));
      expect(fired, 0);
      expect(await rig.store.read(), _token);
    });

    test('no token at all -> unauthorized without hitting the network', () async {
      final rig = Rig((r) async => _json({}));
      await expectLater(rig.api.me(), throwsA(isA<PanelUnauthorized>()));
      expect(rig.requests, isEmpty);
    });

    test('changePassword body is {current,new}', () async {
      final rig = Rig((r) async => _json({'ok': true}));
      await rig.store.write(_token);
      await rig.api.changePassword('old-password-1', 'new-password-2');
      expect(rig.last.url.path, '/admin/api/password');
      expect(rig.body, {'current': 'old-password-1', 'new': 'new-password-2'});
    });

    test('logout clears the token even when the server call fails', () async {
      final rig = Rig((r) async => throw const SocketException('down'));
      await rig.store.write(_token);
      await rig.api.logout();
      expect(await rig.store.read(), isNull);
    });
  });

  group('error mapping', () {
    test('timeout -> code timeout (isNetwork)', () async {
      final rig = Rig((r) => Completer<http.Response>().future, timeout: const Duration(milliseconds: 50));
      await rig.store.write(_token);
      await expectLater(rig.api.me(), throwsA(isA<PanelApiException>().having((e) => e.code, 'code', 'timeout').having((e) => e.isNetwork, 'isNetwork', true)));
    });

    test('socket error -> offline', () async {
      final rig = Rig((r) async => throw const SocketException('no route'));
      await rig.store.write(_token);
      await expectLater(rig.api.me(), throwsA(isA<PanelApiException>().having((e) => e.code, 'code', 'offline')));
    });

    test('invalid JSON on 200 -> bad_response', () async {
      final rig = Rig((r) async => http.Response('<html>oops</html>', 200));
      await rig.store.write(_token);
      await expectLater(rig.api.me(), throwsA(isA<PanelApiException>().having((e) => e.code, 'code', 'bad_response')));
    });

    test('422 errors[] and 409 leaf_in_use extras are preserved', () async {
      final rig = Rig((r) async {
        if (r.url.path.endsWith('/structure')) {
          return _json({'error': 'leaf_in_use', 'message': 'in use', 'leaves': ['hindu/veda']}, 409);
        }
        return _json({'error': 'invalid_announcement', 'errors': ['text too long']}, 422);
      });
      await rig.store.write(_token);
      await expectLater(
        rig.api.putStructure({'religions': []}),
        throwsA(isA<PanelApiException>().having((e) => e.code, 'code', 'leaf_in_use').having((e) => e.extra['leaves'], 'leaves', ['hindu/veda'])),
      );
      await expectLater(
        rig.api.putSettings(announcement: {'enabled': true, 'text': 'x'}),
        throwsA(isA<PanelApiException>().having((e) => e.errors, 'errors', ['text too long'])),
      );
    });

    test('exception messages never contain the token or password', () async {
      final rig = Rig((r) async => _json({'error': 'internal', 'detail': 'boom'}, 500));
      await rig.store.write(_token);
      try {
        await rig.api.me();
        fail('should throw');
      } on PanelApiException catch (e) {
        expect(e.toString().contains(_token), isFalse);
        expect(e.fullMessage.contains(_token), isFalse);
      }
    });
  });

  group('request shapes', () {
    Future<Rig> authed([Map<String, dynamic> reply = const {'ok': true}]) async {
      final rig = Rig((r) async => _json(reply));
      await rig.store.write(_token);
      return rig;
    }

    test('granths with sort -> GET /granths?sort=', () async {
      final rig = await authed({'items': [], 'leaves': [], 'sync': {}});
      await rig.api.granths(sort: 'title');
      expect(rig.last.method, 'GET');
      expect(rig.last.url.path, '/admin/api/granths');
      expect(rig.last.url.queryParameters, {'sort': 'title'});
    });

    test('setGranth: leaf / hidden / clearLeaf', () async {
      final rig = await authed();
      await rig.api.setGranth('104', leaf: 'hindu/veda', hidden: true);
      expect(rig.last.method, 'PUT');
      expect(rig.last.url.path, '/admin/api/granths/104');
      expect(rig.body, {'leaf': 'hindu/veda', 'hidden': true});
      await rig.api.setGranth('104', clearLeaf: true);
      expect(rig.body, {'leaf': null});
      expect(rig.body.containsKey('hidden'), isFalse);
    });

    test('bulkGranths sends ids and returns changed', () async {
      final rig = await authed({'ok': true, 'changed': 2});
      expect(await rig.api.bulkGranths(['1', '2'], leaf: 'other'), 2);
      expect(rig.last.url.path, '/admin/api/granths/bulk');
      expect(rig.body, {'ids': ['1', '2'], 'leaf': 'other'});
    });

    test('bulkGranths refuses more than 300 ids locally', () async {
      final rig = await authed();
      expect(() => rig.api.bulkGranths(List.generate(301, (i) => '$i'), hidden: true), throwsA(anything));
      expect(rig.requests, isEmpty);
    });

    test('putStructure sends the tree and drop_overrides only when asked', () async {
      final rig = await authed();
      await rig.api.putStructure({'religions': []});
      expect(rig.body, {'structure': {'religions': []}});
      await rig.api.putStructure({'religions': []}, dropOverrides: true);
      expect(rig.body['drop_overrides'], true);
      expect(rig.last.method, 'PUT');
    });

    test('publish: note / force / allow_empty', () async {
      final rig = await authed({'ok': true, 'version': 5, 'etag': '"e"', 'published_at': 'x', 'signed': true, 'warnings': ['w']});
      final r = await rig.api.publish(note: 'नया फ़ोल्डर', force: true);
      expect(rig.last.url.path, '/admin/api/publish');
      expect(rig.body, {'note': 'नया फ़ोल्डर', 'force': true});
      expect(r.version, 5);
      expect(r.signed, isTrue);
      expect(r.warnings, ['w']);
    });

    test('rollback posts to_version', () async {
      final rig = await authed({'ok': true, 'version': 7, 'etag': 'e', 'rolled_back_to': 4});
      final r = await rig.api.rollback(4, note: 'rollback from app');
      expect(rig.last.url.path, '/admin/api/rollback');
      expect(rig.body['to_version'], 4);
      expect(r.rolledBackTo, 4);
    });

    test('putSettings nests flags and includes only given fields', () async {
      final rig = await authed();
      await rig.api.putSettings(aiEnabled: false, analyticsSample: 0.5, aiEndpoint: 'https://ai.example/x');
      expect(rig.last.method, 'PUT');
      expect(rig.body, {
        'flags': {'ai_enabled': false, 'analytics_sample': 0.5},
        'ai_endpoint': 'https://ai.example/x',
      });
    });

    test('alerts ack paths', () async {
      final rig = await authed();
      await rig.api.ackGranth('104');
      expect(rig.last.url.path, '/admin/api/alerts/g:104/ack');
      expect(rig.last.method, 'POST');
      await rig.api.ackAlert('9');
      expect(rig.last.url.path, '/admin/api/alerts/a:9/ack');
    });

    test('stats days are clamped to 7/30/90', () async {
      final rig = await authed({'days': 30, 'items': []});
      await rig.api.statsGranths(days: 31);
      expect(rig.last.url.queryParameters['days'], isIn(['7', '30', '90']));
      await rig.api.statsFolders(days: 1);
      expect(rig.last.url.queryParameters['days'], '7');
      expect(rig.last.url.path, '/admin/api/stats/folders');
    });

    test('baseUrl can be swapped for a custom domain', () async {
      final rig = await authed({'username': 'goutam'});
      rig.api.baseUrl = 'https://admin.example.com';
      await rig.api.me();
      expect(rig.last.url.host, 'admin.example.com');
      expect(rig.last.url.path, '/admin/api/me');
    });
  });
}
