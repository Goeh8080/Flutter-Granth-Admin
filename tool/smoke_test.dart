// Read-only smoke test of the API layer against the LIVE server.
// Only login, read actions and logout are called. Run with:
//   GRANTH_USER=... GRANTH_PASS=... dart run tool/smoke_test.dart
import 'dart:io';

import 'package:granthadmin/services/granth_api.dart';

Future<void> main() async {
  final user = Platform.environment['GRANTH_USER'];
  final pass = Platform.environment['GRANTH_PASS'];
  if (user == null || pass == null) {
    stderr.writeln('Set GRANTH_USER and GRANTH_PASS');
    exit(2);
  }
  final api = GranthApi(ApiClient());
  var failures = 0;
  Future<void> check(String name, Future<Object?> Function() f) async {
    try {
      final r = await f();
      stdout.writeln('PASS $name -> $r');
    } catch (e) {
      failures++;
      stdout.writeln('FAIL $name -> $e');
    }
  }

  await check('session before login (expect false)', () => api.checkSession());
  await check('login', () async {
    final ok = await api.login(user, pass);
    if (!ok) throw 'login returned false';
    return ok;
  });
  await check('session after login (expect true)', () async {
    final ok = await api.checkSession();
    if (!ok) throw 'session check false';
    return ok;
  });
  await check('stats', () async {
    final s = await api.stats();
    return 'topics=${s.topics} granths=${s.granths} pramans=${s.pramans}';
  });
  final topics = await api.topics();
  await check(
    'topics',
    () async =>
        'n=${topics.length} first=#${topics.first.id} pos=${topics.first.position} pramans=${topics.first.pramanCount} active=${topics.first.isActive}',
  );
  await check('inactive topics', () async {
    final t = await api.topics(onlyInactive: true);
    if (t.any((x) => x.isActive)) throw 'active topic in disabled list';
    return 'n=${t.length}';
  });
  await check('topic search', () async => 'n=${(await api.topics(search: 'गीता')).length}');
  await check('topic detail', () async => (await api.topic(topics.first.id)).title.substring(0, 10));
  final granths = await api.granths();
  await check('granths', () async => 'n=${granths.length} img=${granths.first.imageUrl}');
  await check('granth search', () async => 'n=${(await api.granths(search: 'गीता')).length}');
  await check('granth detail', () async => (await api.granth(granths.first.id)).author);
  final pramans = await api.pramans();
  await check(
    'pramans',
    () async =>
        'n=${pramans.length} nullGranth=${pramans.where((p) => p.granthId == 0).length} img=${pramans.first.imageUrl}',
  );
  await check('pramans by topic', () async => 'n=${(await api.pramans(topicId: pramans.first.topicId)).length}');
  await check('pramans by granth', () async => 'n=${(await api.pramans(granthId: granths.first.id)).length}');
  await check('youtube pramans', () async {
    final y = await api.pramans(youtube: true);
    return 'n=${y.length} first=${y.isEmpty ? '-' : y.first.youtubeWatchUri}';
  });
  await check('praman search', () async => 'n=${(await api.pramans(search: 'गीता')).length}');
  await check('praman by id', () async => 'n=${(await api.pramans(id: pramans.first.id)).length}');
  await check('praman detail', () async => 'page=${(await api.praman(pramans.first.id)).pageNumber}');
  await check('feedbacks', () async => 'n=${(await api.feedbacks()).length}');
  await check('image reachable', () async {
    final c = HttpClient();
    final req = await c.headUrl(Uri.parse(pramans.first.imageUrl!));
    final res = await req.close();
    c.close();
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    return res.statusCode;
  });
  await check('logout', () async {
    await api.logout();
    return 'ok';
  });
  stdout.writeln(failures == 0 ? 'ALL PASSED' : '$failures FAILED');
  exit(failures == 0 ? 0 : 1);
}
