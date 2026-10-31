// Round 5: per-page grid (ui.grid_pages, CONTRACT §4.1.1) + a PNG render of the Settings screen.
// Mocked servers only.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin/core/app_state.dart';
import 'package:granthadmin/admin/core/panel_state.dart';
import 'package:granthadmin/admin/models/panel_models.dart';
import 'package:granthadmin/admin/screens/panel/panel_settings.dart';
import 'package:granthadmin/admin/services/granth_api.dart';
import 'package:granthadmin/admin/services/panel_api.dart';
import 'package:granthadmin/admin/services/panel_token_store.dart';
import 'package:granthadmin/admin_ui/grid_pages_card.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object b) => http.Response(
  jsonEncode(b),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> _loadFonts() async {
  final fams = {
    'DMSans': ['DMSans-Regular', 'DMSans-Medium', 'DMSans-SemiBold'],
    'NotoDeva': [
      'NotoSansDevanagari-Regular',
      'NotoSansDevanagari-Medium',
      'NotoSansDevanagari-SemiBold',
      'NotoSansDevanagari-Bold',
    ],
    'NotoDevaFull': ['NotoSansDevanagari-Full'],
    'YatraOne': ['YatraOne-Devanagari'],
    'YatraOneLatin': ['YatraOne-Latin'],
    // test fonts don't fall back across families: give the platform defaults a Latin+Devanagari face
    for (final f in const [
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.SF Pro Text',
      '.SF UI Text',
      'Roboto',
    ])
      f: ['NotoSansDevanagari-Full'],
  };
  for (final e in fams.entries) {
    final l = FontLoader(e.key);
    for (final f in e.value) {
      final file = File('assets/fonts/$f.ttf');
      if (file.existsSync()) {
        l.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      }
    }
    await l.load();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('PanelSettings parses ui.grid_pages (valid pages only)', () {
    final s = PanelSettings.fromJson({
      'ui': {
        'grid': 3,
        'grid_pages': {'granths': 2, 'topics': 9, 'foo': 1, 'gallery': '1'},
      },
    });
    expect(s.uiGrid, 3);
    expect(s.uiGridPages, {'granths': 2, 'gallery': 1});
  });

  test('putSettings sends ui.grid_pages', () async {
    final bodies = <String>[];
    final api = PanelApi(
      baseUrl: 'https://panel.test',
      store: MemoryPanelTokenStore(),
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return _json({'token': 'tok', 'expires_in': 86400, 'username': 'u'});
        }
        bodies.add(r.body);
        return _json({'ok': true});
      }),
    );
    await api.login('pw', username: 'u');
    await api.putSettings(uiGridPages: {'shelves': 1, 'topics': null});
    expect(jsonDecode(bodies.last), {
      'ui': {
        'grid_pages': {'shelves': 1, 'topics': null},
      },
    });
  });

  testWidgets('GridPagesCard: 6 pages × (1,2,3,default) and taps', (t) async {
    t.view.physicalSize = const Size(1080, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final taps = <String>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GridPagesCard(
              grid: 3,
              pages: const {'granths': 2},
              onSet: (p, n) => taps.add('$p=$n'),
              initiallyExpanded: true,
            ),
          ),
        ),
      ),
    );
    for (final p in PanelSettings.gridPages) {
      for (final v in ['1', '2', '3', 'default']) {
        expect(find.byKey(ValueKey('gp-$p-$v')), findsOneWidget);
      }
    }
    await t.tap(find.byKey(const ValueKey('gp-dashboard-1')));
    await t.tap(find.byKey(const ValueKey('gp-granths-default')));
    expect(taps, ['dashboard=1', 'granths=null']);
  });

  testWidgets('render Settings screen to PNG', (t) async {
    t.view.physicalSize = const Size(1170, 3400);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.runAsync(_loadFonts);
    final panel = PanelState(
      api: PanelApi(
        baseUrl: 'https://panel.test',
        store: MemoryPanelTokenStore(),
        client: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/login')) {
            return _json({
              'token': 'tok',
              'expires_in': 86400,
              'username': 'demo',
            });
          }
          if (p.endsWith('/me')) {
            return _json({
              'ok': true,
              'username': 'demo',
              'role': 'owner',
              'auth': 'user',
              'version': 55,
              'has_draft': false,
              'base_version': 55,
              'next_version': 56,
              'can_manage_admins': true,
            });
          }
          if (p.endsWith('/settings')) {
            return _json({
              'flags': {
                'ai_enabled': true,
                'analytics_enabled': true,
                'analytics_sample': 1,
              },
              'announcement': {
                'enabled': true,
                'text': 'नमस्ते! नया संस्करण उपलब्ध है',
                'id': 'a1',
                'level': 'info',
              },
              'ai_endpoint': 'https://ai.example.test',
              'ui': {
                'grid': 3,
                'grid_pages': {'granths': 2},
              },
              'levels': ['info', 'warn', 'critical'],
              'info': {
                'base': 'https://panel.example.test',
                'published_version': 55,
                'signed': true,
              },
              'draft': false,
            });
          }
          if (p.endsWith('/ai/summary')) {
            return _json({
              'ok': true,
              'ready': true,
              'questions': {
                'unread': 3,
                'new': 3,
                'answered': 2,
                'rejected': 0,
                'total': 5,
              },
              'knowledge': {'total': 9, 'visible': 8, 'max': 500},
            });
          }
          return _json({'ok': true, 'items': [], 'count': 0});
        }),
      ),
    );
    final state = AppState(
      api: GranthApi(
        ApiClient(
          client: MockClient(
            (r) async => http.Response(
              '{"success":true,"isLogin":true,"data":[]}',
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      ),
      panel: panel,
    );
    await t.runAsync(() async {
      await panel.loginAs('demo', 'pw');
      await panel.refreshMe();
    });
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: AppScope(
          state: state,
          child: const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: PanelSettingsScreen(),
          ),
        ),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final out =
        Platform.environment['SETTINGS_PNG'] ?? 'build/admin_settings_ui.png';
    await t.runAsync(() async {
      final b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File(out)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(File(out).existsSync(), isTrue);
  });
}
