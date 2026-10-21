// Offline UI smoke test: drives the real widgets against captured live JSON
// (served by a MockClient, so nothing reaches the server).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/core/app_state.dart';
import 'package:granthadmin/main.dart';
import 'package:granthadmin/services/granth_api.dart';
import 'package:granthadmin/widgets/cards.dart';
import 'package:granthadmin/widgets/common.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String fx(String f) => File('_probe/$f').readAsStringSync();

void main() {
  final requested = <String>[];

  http.Client mock() => MockClient((req) async {
    final a = req.url.queryParameters['action'] ?? '';
    requested.add(a);
    String body;
    Map first(String file, String key, String id) {
      final list = (jsonDecode(fx(file))['data'] as List).cast<Map>();
      return list.firstWhere((e) => e[key] == id, orElse: () => list.first);
    }

    switch (a) {
      case 'get_user':
        return http.Response('{"success":true}', 200, headers: {'set-cookie': 'PHPSESSID=test123; path=/'});
      case 'get_stats':
        body = fx('get_stats.json');
      case 'get_topics':
        body = req.url.queryParameters['disabled'] == '1' ? fx('get_topics_disabled_1.json') : fx('get_topics.json');
      case 'get_granths':
        body = fx('get_granths.json');
      case 'get_pramans':
        final q = req.url.queryParameters;
        if (q['is_youtube'] == '1') {
          body = fx('get_pramans_is_youtube_1.json');
        } else if (q['id'] != null) {
          body = jsonEncode({
            'success': true,
            'isLogin': true,
            'data': [first('get_pramans.json', 'id', q['id']!)],
          });
        } else {
          final all = (jsonDecode(fx('get_pramans.json'))['data'] as List).cast<Map>();
          final f = q['topicId'] != null
              ? all.where((e) => e['topic_id'] == q['topicId']).toList()
              : q['granthId'] != null
              ? all.where((e) => e['granth_id'] == q['granthId']).toList()
              : all;
          body = jsonEncode({'success': true, 'isLogin': true, 'data': f});
        }
      case 'get_feedbacks':
        body = fx('get_feedbacks.json');
      case 'get_topic':
        body = jsonEncode({'success': true, 'data': first('get_topics.json', 'id', req.url.queryParameters['topic']!)});
      case 'get_granth':
        body = jsonEncode({
          'success': true,
          'data': first('get_granths.json', 'id', req.url.queryParameters['granth']!),
        });
      case 'get_praman':
        body = jsonEncode({
          'success': true,
          'data': first('get_pramans.json', 'id', req.url.queryParameters['praman']!),
        });
      default:
        body = '{"success":false}';
    }
    return http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json'});
  });

  Future<void> settle(WidgetTester t, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapVisible(WidgetTester t, Finder f) async {
    await t.ensureVisible(f.first);
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(f.first);
  }

  Future<void> run(WidgetTester tester, Brightness b) async {
    NetImage.enabled = false;
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(tester.view.reset);
    final state = AppState(api: GranthApi(ApiClient(client: mock())));
    await tester.runAsync(() => state.boot());
    await tester.pumpWidget(AppScope(state: state, child: const GranthAdminApp()));
    await settle(tester);
    expect(find.text('ग्रंथ प्रबंधन'), findsOneWidget, reason: 'login screen');

    await tester.enterText(find.byType(CupertinoTextField).at(0), 'tester');
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'x');
    await tester.tap(find.text('लॉगिन / Login'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await settle(tester, 20);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await settle(tester, 20);
    expect(state.loggedIn, isTrue);
    expect(find.text('डैशबोर्ड'), findsWidgets);

    Future<void> tab(String label) async {
      await tester.tap(find.text(label).last);
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
      await settle(tester, 15);
    }

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await settle(tester, 10);
    }

    Future<void> io() => tester.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));

    // Topics → detail → edit form (cancel)
    await tab('विषय');
    expect(find.text('विषय / Topics'), findsWidgets);
    final firstTopic = state.topics.first;
    await tester.tap(find.text(oneLine(firstTopic.title)).hitTestable().first);
    await io();
    await settle(tester, 15);
    expect(find.text('Position'), findsOneWidget, reason: 'topic detail');
    await tapVisible(tester, find.text('Edit'));
    await io();
    await settle(tester, 15);
    expect(find.text('विषय संपादित / Edit Topic'), findsOneWidget);
    await tester.tap(find.text('रद्द करें'));
    await settle(tester, 10);
    await back();
    expect(firstTopic.id, greaterThan(0));

    // Granths → detail
    await tab('ग्रंथ');
    expect(find.text('ग्रंथ / Granths'), findsWidgets);
    final g0 = state.granths.first;
    await tester.tap(find.text('${g0.position}. ${oneLine(g0.title)}').hitTestable().first);
    await io();
    await settle(tester, 15);
    expect(find.text('PDF').evaluate().isNotEmpty || find.text('Position').evaluate().isNotEmpty, isTrue);
    await back();

    // Pramans → YouTube filter → detail → edit
    await tab('प्रमाण');
    expect(find.text('प्रमाण / Pramans'), findsWidgets);
    await tester.ensureVisible(find.text('YouTube').first);
    await settle(tester, 5);
    await tester.tap(find.text('YouTube').first);
    await io();
    await settle(tester, 15);
    await io();
    await settle(tester, 15);
    expect(find.textContaining('YouTube प्रमाण'), findsWidgets);
    final yt = (jsonDecode(fx('get_pramans_is_youtube_1.json'))['data'] as List).first;
    await tester.tap(find.text(oneLine(yt['title'] as String)).hitTestable().first);
    await io();
    await settle(tester, 15);
    expect(find.text('Set default ♥').evaluate().isNotEmpty || find.text('Share').evaluate().isNotEmpty, isTrue);
    await tapVisible(tester, find.text('Edit'));
    await io();
    await settle(tester, 15);
    await io();
    await settle(tester, 10);
    expect(find.text('प्रमाण संपादित / Edit Praman'), findsOneWidget);
    await tester.tap(find.text('रद्द करें'));
    await settle(tester, 10);
    await back();

    // More → feedback screen
    await tab('अधिक');
    await tester.tap(find.text('फीडबैक / Feedback').first);
    await io();
    await settle(tester, 15);
    expect(find.textContaining('Reena'), findsWidgets);
    await back();

    // Dashboard → topic reorder screen
    await tab('डैशबोर्ड');
    expect(find.text('333'), findsOneWidget);
    await tester.tap(find.text('विषय क्रम'));
    await io();
    await settle(tester, 15);
    expect(find.text('विषय क्रम / Sort Topics'), findsOneWidget);
    await back();

    // Granth form, feedback form (cancel, nothing saved)
    await tapVisible(tester, find.text('नया ग्रंथ'));
    await io();
    await settle(tester, 15);
    expect(find.text('नया ग्रंथ / New Granth'), findsOneWidget);
    await tester.tap(find.text('रद्द करें'));
    await settle(tester, 10);
    await tapVisible(tester, find.text('+ फीडबैक'));
    await io();
    await settle(tester, 15);
    await io();
    await settle(tester, 10);
    expect(find.text('नया फीडबैक / Create Feedback'), findsOneWidget);
    await tester.tap(find.text('रद्द करें'));
    await settle(tester, 10);

    // Topics: inactive segment, long-press action sheet → Delete → confirm dialog → Cancel
    await tab('विषय');
    await tester.tap(find.text('निष्क्रिय / Inactive'));
    await io();
    await settle(tester, 15);
    final inactive = (jsonDecode(fx('get_topics_disabled_1.json'))['data'] as List).first;
    expect(find.text(oneLine(inactive['title'] as String)), findsWidgets);
    await tester.longPress(find.text(oneLine(inactive['title'] as String)).hitTestable().first);
    await settle(tester, 12);
    expect(find.text('हटाएँ / Delete'), findsWidgets);
    await tapVisible(tester, find.text('हटाएँ / Delete'));
    await settle(tester, 12);
    expect(find.text('यह विषय हटाएँ? / Delete this topic?'), findsOneWidget);
    await tester.tap(find.text('रद्द करें / Cancel'));
    await settle(tester, 10);

    // Pramans: topic filter via picker sheet
    await tab('प्रमाण');
    await tapVisible(tester, find.text('विषय / Topic'));
    await io();
    await settle(tester, 15);
    expect(find.text('विषय से फ़िल्टर / Filter by topic'), findsOneWidget);
    final t0 = state.topics.first;
    await tester.tap(find.text('${t0.position}. ${t0.title}'.replaceAll('\n', ' ')).first);
    await io();
    await settle(tester, 15);
    expect(find.textContaining('विषय: '), findsOneWidget);

    // Settings: dark theme toggle
    await tab('अधिक');
    await tester.tap(find.text('Dark'));
    await settle(tester, 10);
    expect(state.themeMode, ThemeMode.dark);

    // let all pending timers (toasts etc.) finish
    await settle(tester, 40);
    final writes = requested.where(
      (a) => a.startsWith('create') || a.startsWith('delete') || a.startsWith('update') || a.startsWith('set_'),
    );
    expect(writes, isEmpty, reason: 'UI test must not trigger write actions');
  }

  testWidgets('full read-only UI flow (light)', (t) => run(t, Brightness.light));
  testWidgets('full read-only UI flow (dark)', (t) => run(t, Brightness.dark));
}
