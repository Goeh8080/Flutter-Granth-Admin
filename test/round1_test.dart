// Round 1: the admin app on top of the user app's files. Pure helpers + widget tests with mocked
// servers (nothing here has touched the live control server or a device).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin/core/app_state.dart';
import 'package:granthadmin/admin/core/panel_state.dart';
import 'package:granthadmin/admin/models/ai_models.dart';
import 'package:granthadmin/admin/screens/panel/panel_settings.dart';
import 'package:granthadmin/admin/models/panel_models.dart' show StatsOverview;
import 'package:granthadmin/admin/services/granth_api.dart';
import 'package:granthadmin/admin/services/panel_api.dart';
import 'package:granthadmin/admin/services/panel_token_store.dart';
import 'package:granthadmin/admin_ui/admin_data.dart';
import 'package:granthadmin/admin_ui/admin_widgets.dart';
import 'package:granthadmin/admin_ui/ai_admin_screens.dart';
import 'package:granthadmin/admin_ui/announcement_editor.dart';
import 'package:granthadmin/screens/admin_panel_screen.dart';
import 'package:granthadmin/widgets/announcement_banner.dart';
import 'package:granthadmin/models/models.dart' as u;
import 'package:granthadmin/services/catalog_store.dart';
import 'package:granthadmin/screens/home_shell.dart';
import 'package:granthadmin/state/router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'panel_models_test.dart' show granthsJson, overviewJson;

http.Response _json(Object b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Rig {
  _Rig({
    this.role = 'owner',
    this.aiEnabled = true,
    this.grid,
    this.announcement,
    this.statsStatus = 200,
  }) {
    panel = PanelState(
      api: PanelApi(
        baseUrl: 'https://panel.test',
        store: MemoryPanelTokenStore(),
        client: MockClient((req) async {
          final p = req.url.path;
          calls.add('${req.method} $p');
          if (req.method == 'PUT' || req.method == 'POST') bodies.add(req.body);
          if (p.endsWith('/login'))
            return _json({
              'token': 'tok',
              'expires_in': 86400,
              'username': 'ctl',
            });
          if (p.endsWith('/me'))
            return _json({
              'ok': true,
              'username': 'ctl',
              'role': role,
              'auth': 'user',
              'version': 7,
              'has_draft': false,
              'base_version': 7,
              'next_version': 8,
              'can_manage_admins': role == 'owner',
            });
          if (p.endsWith('/granths')) return _json(granthsJson);
          if (p.endsWith('/structure'))
            return _json({
              'ok': true,
              'structure': {'religions': []},
              'counts': {},
              'leaves': [],
              'icons': {},
              'draft': false,
              'base_version': 7,
            });
          if (p.endsWith('/settings')) {
            if (req.method == 'PUT') return _json({'ok': true});
            return _json({
              'flags': {'ai_enabled': aiEnabled},
              'announcement': announcement ?? {'enabled': false},
              'ui': {'grid': grid},
              'info': {'published_version': 7},
            });
          }
          if (p.endsWith('/ga/overview'))
            return statsStatus == 200
                ? _json({
                    'totals': {
                      'active_users': 16,
                      'ai_answer': 8,
                      'cite_tap': 8,
                      'app_opens': 20,
                      'pdf_download': 3,
                    },
                    'all_time': {'installs': 40},
                  })
                : _json({'error': 'ga_api_disabled'}, statsStatus);
          if (p.endsWith('/stats/overview'))
            return statsStatus == 200
                ? _json(overviewJson)
                : _json({'error': 'migration_pending'}, statsStatus);
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
    state = AppState(
      api: GranthApi(
        ApiClient(
          client: MockClient(
            (req) async => http.Response(
              '{"success":true,"isLogin":true,"data":[]}',
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      ),
      panel: panel,
    );
  }
  final String role;
  final bool aiEnabled;
  final int? grid;
  final Map<String, Object?>? announcement;
  final int statsStatus;
  late final PanelState panel;
  late final AppState state;
  final calls = <String>[];
  final bodies = <String>[];

  Future<void> up(WidgetTester t) async {
    AdminData.I = AdminData(state, warmSearch: false);
    await t.runAsync(() async {
      await panel.loginAs('ctl', 'pw');
      await panel.refreshMe();
      await AdminData.I.refresh();
    });
  }
}

Future<void> settle(WidgetTester t, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> io(WidgetTester t) =>
    t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));

Widget hub() => const MaterialApp(
  home: Scaffold(body: CustomScrollView(slivers: [AdminPanelScreen()])),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('helpers', () {
    test('parseTags: trims, de-duplicates, caps at 10 tags of 30 chars', () {
      expect(parseTags(' a, b ,a,,c\nd'), ['a', 'b', 'c', 'd']);
      expect(parseTags('x' * 40).single.length, 30);
      expect(parseTags(List.generate(14, (i) => 't$i').join(',')).length, 10);
    });
    test('validateKnowledge mirrors server limits (q 5..500, a 50..2000)', () {
      final a = 'क' * 50;
      expect(validateKnowledge('सवाल है', a), isNull);
      expect(validateKnowledge('abc', a), contains('Title'));
      expect(validateKnowledge('सवाल है', 'छोटा'), contains('Description'));
      expect(validateKnowledge('सवाल है', 'क' * 2001), contains('Description'));
    });
    test('announcement bodies', () {
      final b = announcementBody(
        text: '  नमस्ते ',
        level: 'info',
        pinned: true,
        expiresAt: '2026-12-31T18:29:59Z',
        newId: 'n1',
      );
      expect(b, {
        'enabled': true,
        'text': 'नमस्ते',
        'level': 'info',
        'pinned': true,
        'expires_at': '2026-12-31T18:29:59Z',
        'id': 'n1',
      });
      expect(
        announcementBody(
          text: 'x',
          level: 'warn',
          pinned: false,
          expiresAt: null,
        ).containsKey('id'),
        isFalse,
      );
      expect(announcementRemoval(), {
        'enabled': false,
        'text': '',
        'pinned': false,
        'expires_at': null,
      });
    });
    test('AiSummary parses the contract shape and tolerates empties', () {
      final s = AiSummary.fromJson({
        'ready': true,
        'questions': {
          'unread': 3,
          'new': 4,
          'answered': 2,
          'rejected': 1,
          'total': 7,
        },
        'knowledge': {'total': 9, 'visible': 8, 'max': 500},
      });
      expect(
        [
          s.unread,
          s.newCount,
          s.answered,
          s.rejected,
          s.total,
          s.kbTotal,
          s.kbVisible,
          s.kbMax,
        ],
        [3, 4, 2, 1, 7, 9, 8, 500],
      );
      final e = AiSummary.fromJson({});
      expect([e.unread, e.kbTotal, e.kbMax, e.ready], [0, 0, 500, true]);
    });
    test('stats overview carries the ai counters', () {
      final s = StatsOverview.fromJson(overviewJson);
      expect([s.aiAsked, s.aiAnswered, s.aiCiteTap], [16, 8, 8]);
    });
  });

  testWidgets(
    'hub: analytics incl. ai counters, toggles, tiles, owner-only Admins',
    (t) async {
      t.view.physicalSize = const Size(1080, 9000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final rig = _Rig();
      await rig.up(t);
      await t.pumpWidget(hub());
      await io(t);
      await settle(t);
      expect(find.text('Admin Panel'), findsWidgets);
      expect(find.byKey(const ValueKey('analytics-card')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ga-active')),
          matching: find.text('16'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ai-answered')),
          matching: find.text('8'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ai-cite-tap')),
          matching: find.text('8'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ai-toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('grid-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('announcement-card')), findsOneWidget);
      expect(find.text('AI Key Notes'), findsOneWidget);
      expect(find.text('AI Question'), findsOneWidget);
      expect(
        find.text('एडमिन जोड़ें / हटाएँ'),
        findsOneWidget,
        reason: 'owner sees the admins tile',
      );
      expect(find.textContaining('dark', findRichText: true), findsNothing);
      expect(find.textContaining('Dark'), findsNothing);
      expect(find.byKey(const ValueKey('version-line')), findsOneWidget);
      await settle(t, 30);
    },
  );

  testWidgets(
    'hub: a plain admin has no Admins tile; stats 503 degrades gracefully',
    (t) async {
      t.view.physicalSize = const Size(1080, 9000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final rig = _Rig(role: 'admin', statsStatus: 503);
      await rig.up(t);
      await t.pumpWidget(hub());
      await io(t);
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('एडमिन जोड़ें / हटाएँ'), findsNothing);
      expect(find.text('आँकड़े लोड नहीं हुए'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ai-toggle')),
        findsOneWidget,
        reason: 'the rest still works',
      );
      await settle(t, 30);
    },
  );

  testWidgets('grid selector highlights the live value and writes ui.grid', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 9000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final rig = _Rig(grid: 2);
    await rig.up(t);
    await t.pumpWidget(hub());
    await io(t);
    await settle(t);
    expect(find.textContaining('अभी: 2×2'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('grid-1')));
    await io(t);
    await settle(t, 6);
    expect(
      rig.bodies.any(
        (b) => (jsonDecode(b) as Map)['ui'].toString() == '{grid: 1}',
      ),
      isTrue,
    );
    await t.tap(find.byKey(const ValueKey('grid-default')));
    await io(t);
    await settle(t, 6);
    expect(
      rig.bodies.any(
        (b) => (jsonDecode(b) as Map)['ui'].toString() == '{grid: null}',
      ),
      isTrue,
    );
    await settle(t, 40);
  });

  testWidgets('AI toggle shows the server state and writes flags.ai_enabled', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 9000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final rig = _Rig(aiEnabled: true);
    await rig.up(t);
    await t.pumpWidget(hub());
    await io(t);
    await settle(t);
    await t.tap(find.byType(AdminSwitch));
    await io(t);
    await settle(t, 6);
    final put = rig.bodies
        .map((b) => jsonDecode(b) as Map)
        .where((m) => m.containsKey('flags'))
        .toList();
    expect(put.single['flags'], {'ai_enabled': false});
    await settle(t, 40);
  });

  testWidgets(
    'shell: 7 menu entries, last is Admin Panel, DraftStrip hidden without a draft',
    (t) async {
      t.view.physicalSize = const Size(1080, 9000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final rig = _Rig();
      await rig.up(t);
      await t.runAsync(() => rig.state.boot());
      AppNav.I.menuOpen = true;
      await t.pumpWidget(
        MaterialApp(
          home: AppScope(state: rig.state, child: const HomeShell()),
        ),
      );
      await io(t);
      await settle(t, 20);
      final keys = [
        for (final w in t.widgetList(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey &&
                '${(w.key as ValueKey).value}'.startsWith('nav-'),
          ),
        ))
          '${(w.key as ValueKey).value}',
      ];
      expect(keys.toSet().length, 7, reason: '$keys');
      expect(find.text('PHOTO HIGHLIGHTER'), findsOneWidget);
      expect(find.text('ADMIN PANEL'), findsOneWidget);
      expect(find.byKey(const ValueKey('draft-strip')), findsNothing);
      await settle(t, 40);
    },
  );

  for (final pinned in [true, false]) {
    testWidgets(
      'announcement card (pinned=$pinned): shows state, no close button',
      (t) async {
        t.view.physicalSize = const Size(1080, 4000);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final rig = _Rig(
          announcement: {
            'enabled': true,
            'text': 'सभी को नमस्ते',
            'level': 'info',
            'pinned': pinned,
            'id': 'a1',
          },
        );
        await rig.up(t);
        await t.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [SliverToBoxAdapter(child: AnnouncementBanner())],
              ),
            ),
          ),
        );
        await settle(t, 4);
        expect(find.byKey(const ValueKey('announcement')), findsOneWidget);
        expect(find.text('सभी को नमस्ते'), findsOneWidget);
        expect(
          (t.widget(
            find.byKey(const ValueKey('announcement-state')),
          ) as Text).data,
          pinned ? contains('Pinned') : contains('Not pinned'),
        );
        expect(find.byIcon(Icons.close), findsNothing);
        expect(find.byTooltip('Close'), findsNothing);
        await settle(t, 20);
      },
    );
  }

  testWidgets('announcement card: empty state invites to add one', (t) async {
    final rig = _Rig();
    await rig.up(t);
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [SliverToBoxAdapter(child: AnnouncementBanner())],
          ),
        ),
      ),
    );
    await settle(t, 4);
    expect(find.byKey(const ValueKey('announcement-empty')), findsOneWidget);
    await settle(t, 20);
  });

  testWidgets(
    'mast stats: after expire -> re-login the shell starts empty, numbers appear once the catalog loads',
    (t) async {
      t.view.physicalSize = const Size(1080, 4000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final rig = _Rig();
      await rig.up(t);
      // Session expiry: AdminGate resets AdminData and the catalog is empty when the shell is
      // created again after the new login.
      AdminData.I.reset();
      CatalogStore.I.adoptAdminCatalog(
        u.Catalog(topics: [], granths: [], pramans: []),
        warm: false,
      );
      await t.pumpWidget(
        MaterialApp(
          home: AppScope(state: rig.state, child: const HomeShell()),
        ),
      );
      await settle(t, 8);
      expect(find.text('—'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data == '—' && w.style?.fontSize == 22,
        ),
        findsNWidgets(3),
      );
      // The catalog arrives later (the dashboard cards already show it).
      CatalogStore.I.adoptAdminCatalog(
        u.Catalog(
          topics: [
            u.Topic({'id': '1', 'title': 'a'}),
            u.Topic({'id': '2', 'title': 'b'}),
          ],
          granths: [
            u.Granth({'id': '1', 'title': 'g'}),
          ],
          pramans: [
            u.Praman({'id': '1', 'title': 'p'}),
            u.Praman({'id': '2', 'title': 'p'}),
            u.Praman({'id': '3', 'title': 'p'}),
          ],
        ),
        warm: false,
      );
      await settle(t, 14);
      for (final label in [
        'विषय / प्रश्नोत्तरी',
        'पवित्र ग्रन्थ',
        'नए प्रमाण',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      // Header stats no longer show the dash.
      bool mastStat(Widget w) =>
          w is Text && w.style?.fontSize == 22 && w.style?.height == 1.1;
      final shown = [
        for (final w in t.widgetList<Text>(find.byWidgetPredicate(mastStat)))
          w.data,
      ];
      expect(shown, ['2', '1', '3']);
      await settle(t, 30);
    },
  );

  testWidgets(
    'Settings: AI Question (unread badge) + AI Key Notes → Title/Description',
    (t) async {
      t.view.physicalSize = const Size(1080, 4000);
      t.view.devicePixelRatio =
          1; // wide: the test font is far wider than the real one
      addTearDown(t.view.reset);
      final rig = _Rig();
      await rig.up(t);
      await t.pumpWidget(
        AppScope(
          state: rig.state,
          child: const MaterialApp(home: PanelSettingsScreen()),
        ),
      );
      await io(t);
      await settle(t);
      expect(find.text('AI Question'), findsOneWidget);
      expect(find.text('AI Key Notes'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('settings-ai-question')),
          matching: find.text('3'),
        ),
        findsOneWidget,
        reason: 'unread badge',
      );

      // AI Question opens the inbox.
      await t.tap(find.text('AI Question'));
      await io(t);
      await settle(t, 20);
      expect(find.text('AI Question'), findsOneWidget);
      expect(find.text('सब पढ़ा'), findsOneWidget);
      await t.tap(find.text('पीछे'));
      await settle(t, 20);

      // AI Key Notes: Title + Description → POST /ai/knowledge {question, answer}.
      await t.tap(find.text('AI Key Notes'));
      await io(t);
      await settle(t, 20);
      await t.tap(find.text('नया नोट'));
      await settle(t, 20);
      expect(find.textContaining('Title'), findsWidgets);
      expect(find.textContaining('Description'), findsWidgets);
      final fields = find.byType(TextField);
      await t.enterText(fields.at(0), 'एकादशी कब है?');
      await t.enterText(fields.at(1), 'छोटा');
      await t.tap(find.text('सहेजें'));
      await io(t);
      await settle(t, 6);
      expect(
        rig.calls.where((c) => c == 'POST /admin/api/ai/knowledge'),
        isEmpty,
      );

      final desc =
          'यह विवरण पचास अक्षरों से लंबा है ताकि सर्वर इसे स्वीकार करे। ' * 2;
      await t.enterText(fields.at(1), desc);
      await t.tap(find.text('सहेजें'));
      await io(t);
      await settle(t, 6);
      final posted = rig.bodies
          .map((b) => jsonDecode(b))
          .whereType<Map>()
          .where((m) => m.containsKey('question') && m.containsKey('answer'))
          .toList();
      expect(posted, hasLength(1));
      expect(posted.single['question'], 'एकादशी कब है?');
      expect(posted.single['answer'], desc.trim());
      await settle(t, 40);
    },
  );
}
