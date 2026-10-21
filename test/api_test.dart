// API layer against a MockClient: cookie handling, session expiry and the exact
// write payloads (mirroring script.js). Nothing is sent to the live server.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/models/models.dart';
import 'package:granthadmin/services/granth_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Any real network access from these tests fails loudly.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? c) => throw StateError('network disabled in tests');
}

void main() {
  HttpOverrides.global = _NoNetwork();
  late List<http.Request> reqs;
  var loggedIn = true;
  GranthApi make() {
    reqs = [];
    return GranthApi(
      ApiClient(
        client: MockClient((r) async {
          reqs.add(r);
          final a = r.url.queryParameters['action'];
          if (a == 'get_user') {
            return http.Response('{"success":true}', 200, headers: {'set-cookie': 'PHPSESSID=abc; path=/'});
          }
          if (a == 'get_feedbacks') {
            return http.Response(jsonEncode({'success': loggedIn, 'isLogin': loggedIn, 'data': []}), 200);
          }
          return http.Response('{"success":true,"isLogin":true,"data":[]}', 200);
        }),
      ),
    );
  }

  test('login stores PHPSESSID and sends it afterwards', () async {
    final api = make();
    expect(await api.login('u', 'p'), isTrue);
    expect(reqs.first.method, 'POST');
    expect(reqs.first.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(reqs.first.body), {'username': 'u', 'password': 'p'});
    await api.stats().catchError((_) => const Stats());
    expect(reqs.last.headers['Cookie'], 'PHPSESSID=abc');
  });

  test('session expiry raises SessionExpiredException and fires callback', () async {
    final api = make();
    await api.login('u', 'p');
    var fired = false;
    api.client.onSessionExpired = () => fired = true;
    loggedIn = false;
    await expectLater(api.feedbacks(), throwsA(isA<SessionExpiredException>()));
    expect(fired, isTrue);
    expect(await api.checkSession(), isFalse);
    loggedIn = true;
  });

  test('create_topic JSON payload (add + edit)', () async {
    final api = make();
    await api.saveTopic(title: 'T', description: 'D', isActive: true);
    expect(jsonDecode(reqs.last.body), {
      'title': 'T',
      'isActive': '1',
      'description': 'D',
      'formType': 'add',
      'id': '',
    });
    await api.saveTopic(id: 5, title: 'T', isActive: false);
    expect(jsonDecode(reqs.last.body)['formType'], 'edit');
    expect(jsonDecode(reqs.last.body)['id'], '5');
    expect(jsonDecode(reqs.last.body)['isActive'], '0');
  });

  test('create_praman multipart fields', () async {
    final api = make();
    await api.savePraman(
      id: 9,
      title: 'P',
      isActive: true,
      topicId: 1,
      granthId: 2,
      pageNumber: '10',
      chapterNumber: '3',
    );
    final ct = reqs.last.headers['content-type']!;
    expect(ct, startsWith('multipart/form-data'));
    final body = reqs.last.body;
    for (final f in [
      'title',
      'isActive',
      'description',
      'topic_id',
      'granth_id',
      'chapterNumber',
      'youtube_url',
      'youtube_desc',
      'youtube_start',
      'pageNumber',
      'formType',
      'id',
    ]) {
      expect(body, contains('name="$f"'), reason: f);
    }
    expect(reqs.last.url.queryParameters['action'], 'create_praman');
  });

  test('create_granth multipart fields', () async {
    final api = make();
    await api.saveGranth(title: 'G', author: 'A', isActive: true, pdfUrl: 'https://x/y.pdf');
    for (final f in ['title', 'author', 'description', 'granthPDF', 'formType', 'id', 'isActive']) {
      expect(reqs.last.body, contains('name="$f"'), reason: f);
    }
  });

  test('order, favourite, delete formats', () async {
    final api = make();
    final t = Topic.fromJson({'id': '3', 'title': 'x', 'position': '7'});
    await api.moveTopicTo(t, 2);
    expect(jsonDecode(reqs.last.body), {'topicId': 3, 'currentPostion': 7, 'newPosition': '2'});
    await api.saveTopicOrder([t]);
    expect((jsonDecode(reqs.last.body)['topics'] as List).first['id'], '3');
    await api.setFavorite(pramanId: 4, granthId: 8);
    expect(jsonDecode(reqs.last.body), {'praman': '4', 'granthId': '8'});
    await api.deletePraman(11);
    expect(reqs.last.method, 'GET');
    expect(reqs.last.url.queryParameters, {'action': 'delete_praman', 'id': '11'});
  });
}
