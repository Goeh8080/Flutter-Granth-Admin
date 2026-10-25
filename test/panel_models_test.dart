// Parsing tests for the control-server models, built from contract-shaped sample JSON
// (CONTRACT.md §3). No network, no fixtures.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin/models/panel_models.dart';
import 'package:granthadmin/admin/models/structure_edit.dart';
import 'package:granthadmin/admin/screens/panel/panel_dashboard.dart';
import 'package:granthadmin/admin/screens/panel/panel_granths.dart';

Map<String, dynamic> j(String s) => jsonDecode(s) as Map<String, dynamic>;

final overviewJson = j('''
{
  "days": 7, "since": "2026-10-19",
  "totals": {
    "total_installs": 4, "first_install_day": "2026-10-25",
    "active_1d": 8, "active_7d": 8, "active_30d": 8, "new_installs_in_range": 4,
    "total_fg_s": 46800, "total_fg_s_all_time": 46800,
    "avg_fg_s_per_active_user": 5850, "avg_fg_s_per_active_user_day": 5850,
    "sessions": 16, "sessions_all_time": 16, "avg_sessions_per_active_user_day": 2,
    "granth_watch_s": 15400, "folder_watch_s": 1000, "granth_opens": 10018,
    "folder_opens": 16, "topic_opens": 4, "praman_opens": 8, "users_in_range": 8
  },
  "dau": [ {"day":"2026-10-19","n":0,"fg_s":0}, {"day":"2026-10-20","n":3,"fg_s":900} ],
  "new_installs": [ {"day":"2026-10-19","n":0}, {"day":"2026-10-20","n":2} ],
  "installs_by_version": [ {"app":"1.0.0+1","n":4} ],
  "installs_by_os": [ {"os":"android","n":4} ],
  "versions": { "1.0.0+1": 8 },
  "sync": {"ok":24,"fail":8,"fail_rate":0.25}, "pdf": {"ok":16,"fail":8}, "ai": {"asked":16,"answered":8,"cite_tap":8},
  "screens": [ {"scr":"reader","watch_s":1600} ],
  "failure_kinds": [ {"kind":"sync:timeout","n":8} ],
  "top_granths_opens": [ {"id":"104","title":"श्रीमद्भगवद्गीता","opens":10004,"watch_s":14600,"avg_watch_s":1} ],
  "top_granths_watch": [ {"id":"104","title":"श्रीमद्भगवद्गीता","opens":10004,"watch_s":14600,"avg_watch_s":1} ],
  "top_folders": [ {"key":"hindu/puran","label":"हिन्दू › पुराण","opens":16,"watch_s":1000} ],
  "top_folders_watch": [ {"key":"hindu/puran","label":"हिन्दू › पुराण","opens":16,"watch_s":1000} ],
  "religions": [ {"key":"hindu","label":"हिन्दू","opens":16,"watch_s":1000} ],
  "new_granths_pending": 3
}
''');

final granthsJson = j('''
{
  "sort": "position", "order": "asc",
  "items": [
    {"id":"104","position":1,"created_at":"2026-03-19 17:26:00","title":"गीता","author":"व्यास","cover":null,"praman_count":4,"active":true,
     "leaf":"hindu/gita","leaf_label":"हिन्दू › गीता","source":"override","default_leaf":"other","hidden":false,"is_new":false,
     "first_seen":"2026-10-01","no_praman":false,"opens_7d":10,"watch_s_7d":600},
    {"id":"105","position":2,"title":"नया ग्रंथ","author":"","cover":"https://x/y.jpg","praman_count":0,"active":true,
     "leaf":"other","leaf_label":"अन्य","source":"fallback","default_leaf":"other","hidden":false,"is_new":true,
     "first_seen":"2026-10-24","no_praman":true,"opens_7d":0,"watch_s_7d":0},
    {"id":"106","position":null,"title":"छिपा","author":"x","praman_count":1,"active":true,
     "leaf":"hindu/gita","leaf_label":"हिन्दू › गीता","source":"id","default_leaf":"hindu/gita","hidden":true,"is_new":false,
     "first_seen":"2026-10-01","no_praman":false,"opens_7d":1,"watch_s_7d":2}
  ],
  "leaves": [
    {"key":"hindu/gita","label":"हिन्दू › गीता","religion":"हिन्दू","religion_id":"hindu","group":"गीता","visible":true},
    {"key":"other","label":"अन्य","religion":"","religion_id":"","group":"","visible":true}
  ],
  "draft": true, "base_version": 7,
  "sync": {"sync_last_ok":"2026-10-25T05:00:00Z","sync_last_count":300},
  "total": 3, "hidden_count": 1
}
''');

void main() {
  group('stats overview', () {
    final s = StatsOverview.fromJson(overviewJson);
    test('totals', () {
      expect(s.days, 7);
      expect(s.totals.totalInstalls, 4);
      expect(s.totals.active1d, 8);
      expect(s.totals.active30d, 8);
      expect(s.totals.newInstallsInRange, 4);
      expect(s.totals.totalFgS, 46800);
      expect(s.totals.avgFgSPerActiveUser, 5850);
      expect(s.totals.granthOpens, 10018);
      expect(s.totals.avgSessionsPerActiveUserDay, 2.0);
    });
    test('lists, rates, pending', () {
      expect(s.dau.length, 2);
      expect(s.dau.last.n, 3);
      expect(s.installsByVersion.single.name, '1.0.0+1');
      expect(s.versions['1.0.0+1'], 8);
      expect(s.syncOk, 24);
      expect(s.syncFail, 8);
      expect(s.syncFailRate, closeTo(0.25, 1e-9));
      expect(s.pdfFail, 8);
      expect(s.screens.single.name, 'reader');
      expect(s.topGranthsOpens.single.title, 'श्रीमद्भगवद्गीता');
      expect(s.topGranthsWatch.single.watchS, 14600);
      expect(s.topFolders.single.label, 'हिन्दू › पुराण');
      expect(s.newGranthsPending, 3);
    });
    test('missing / null fields never throw', () {
      final e = StatsOverview.fromJson({
        'days': 30,
        'totals': null,
        'dau': null,
        'top_granths_opens': 'x',
      });
      expect(e.totals.totalInstalls, 0);
      expect(e.dau, isEmpty);
      expect(e.topGranthsOpens, isEmpty);
      expect(e.newGranthsPending, 0);
    });
    test('falls back to top_screens', () {
      final e = StatsOverview.fromJson({
        'days': 7,
        'top_screens': [
          {'screen': 'home', 'watch_s': 5},
        ],
      });
      expect(e.screens.single.name, 'home');
      expect(e.screens.single.watchS, 5);
    });
  });

  group('granths list', () {
    final d = PanelGranthList.fromJson(granthsJson);
    test('items + leaves + draft', () {
      expect(d.items.length, 3);
      expect(d.items.first.position, 1);
      expect(d.items.last.position, isNull);
      expect(d.items[1].cover, 'https://x/y.jpg');
      expect(d.items[1].isNew, isTrue);
      expect(d.items[1].noPraman, isTrue);
      expect(d.items.last.hidden, isTrue);
      expect(d.leaves.length, 2);
      expect(d.leaves.last.isOther, isTrue);
      expect(d.draft, isTrue);
      expect(d.baseVersion, 7);
      expect(d.hiddenCount, 1);
      expect(d.sync.lastCount, 300);
    });
    test('filters', () {
      List<String> ids(
        GranthFilter f, {
        String q = '',
        String? leaf,
        Map<String, PendingGranth> p = const {},
      }) => filterGranths(
        d.items,
        filter: f,
        query: q,
        leaf: leaf,
        pending: p,
      ).map((g) => g.id).toList();
      expect(ids(GranthFilter.all), ['104', '105', '106']);
      expect(ids(GranthFilter.isNew), ['105']);
      expect(ids(GranthFilter.other), ['105']);
      expect(ids(GranthFilter.hidden), ['106']);
      expect(ids(GranthFilter.noPraman), ['105']);
      expect(ids(GranthFilter.all, q: 'गीता'), ['104']);
      expect(ids(GranthFilter.all, leaf: 'hindu/gita'), ['104', '106']);
    });
    test('pending edits are reflected in filters and hidden count', () {
      final p = {
        '104': PendingGranth(hidden: true),
        '105': PendingGranth(leaf: 'hindu/gita'),
      };
      expect(hiddenAfter(d.items, p), 2);
      expect(
        filterGranths(d.items, filter: GranthFilter.other, pending: p),
        isEmpty,
      );
      expect(
        filterGranths(
          d.items,
          filter: GranthFilter.hidden,
          pending: p,
        ).map((g) => g.id),
        ['104', '106'],
      );
    });
  });

  group('other responses', () {
    test('structure + icons', () {
      final s = PanelStructure.fromJson(
        j(
          '''
      {"structure":{"version":2,"religions":[{"id":"hindu","title":"हिन्दू","groups":[{"id":"ved","title":"वेद","granthIds":["1"]}],"futureField":42}]},
       "counts":{"hindu/ved":1},"leaves":[{"key":"hindu/ved","label":"हिन्दू › वेद","religion":"हिन्दू","religion_id":"hindu","group":"वेद","visible":true}],
       "icons":{"group":["scroll","book-red"],"religion":["om"],"tones":["saffron","maroon","gold"]},"draft":false,"base_version":2}''',
        ),
      );
      expect(s.counts['hindu/ved'], 1);
      expect(s.icons.tones, ['saffron', 'maroon', 'gold']);
      expect(s.icons.group, contains('scroll'));
      // unknown fields are kept so a save round-trips them
      expect((s.structure['religions'] as List).first['futureField'], 42);
    });

    test('diff + draft', () {
      final dr = PanelDraft.fromJson(
        j(
          '''
      {"exists":true,"base_version":7,"next_version":8,"updated_at":"2026-10-25T05:00:00Z",
       "diff":{"granths":[{"id":"105","title":"नया","leaf":{"from":"other","to":"hindu/ved"},"hidden":{"from":false,"to":true}}],
               "folders":[{"path":"hindu/ved","change":"edited","title":"वेद","fields":[{"field":"title","from":"वेद","to":"वेदः"}]}],
               "contacts":[],"settings":[{"field":"flags.ai_enabled","from":"true","to":"false"}],
               "hidden_count":1,"catalog_total":300,"warnings":["hiding >50%"],"changed":3}}''',
        ),
      );
      expect(dr.exists, isTrue);
      expect(dr.nextVersion, 8);
      expect(dr.diff.changed, 3);
      expect(dr.diff.warnings, ['hiding >50%']);
      expect(dr.diff.granths.single.leaf!.to, 'hindu/ved');
      expect(dr.diff.folders.single.fields.single.to, 'वेदः');
      expect(dr.diff.settings.single.field, 'flags.ai_enabled');
    });

    test('alerts', () {
      final a = PanelAlerts.fromJson(
        j(
          '''
      {"new_granths":[{"id":"200","position":9,"title":"नया","author":"क","cover":null,"praman_count":0,"first_seen":"2026-10-25",
        "suggested_leaf":"hindu/puran","suggested_label":"हिन्दू › पुराण","suggestion_source":"keyword"}],
       "alerts":[{"id":5,"kind":"sync_failed","ref":"","message":"sync failed","created_at":"2026-10-25T01:00:00Z"}],"count":2}''',
        ),
      );
      expect(a.count, 2);
      expect(a.newGranths.single.suggestedLeaf, 'hindu/puran');
      expect(a.alerts.single.message, 'sync failed');
    });

    test('settings + announcement', () {
      final s = PanelSettings.fromJson(
        j(
          '''
      {"flags":{"ai_enabled":true,"analytics_enabled":true,"analytics_sample":0.25},
       "announcement":{"enabled":true,"id":"a1","text":"नमस्ते","level":"warn","expires_at":"2026-12-01T00:00:00Z"},
       "ai_endpoint":"https://ai.example","levels":["info","warn","critical"],
       "info":{"base":"https://x","published_version":7,"signing_public_key":"abc","signed":true},"draft":false}''',
        ),
      );
      expect(s.aiEnabled, isTrue);
      expect(s.analyticsSample, 0.25);
      expect(s.announcement.level, 'warn');
      expect(s.announcement.expiresAt, '2026-12-01T00:00:00Z');
      expect(s.aiEndpoint, 'https://ai.example');
      expect(s.publishedVersion, 7);
      expect(s.signed, isTrue);
    });

    test('versions', () {
      final v = PanelVersions.fromJson(
        j(
          '''
      {"items":[{"version":7,"etag":"e7","kind":"publish","note":"n","author":"goutam","created_at":"2026-10-25T05:10:28Z","bytes":1234},
                {"version":6,"etag":"e6","kind":"rollback","note":null,"author":"goutam","created_at":"2026-10-24T05:10:28Z","bytes":1200}],"current":7}''',
        ),
      );
      expect(v.current, 7);
      expect(v.items.length, 2);
      expect(v.items.last.kind, 'rollback');
    });
  });

  group('structure_edit', () {
    test('slug + id + title validation', () {
      expect(validSlug('hindu'), isTrue);
      expect(validSlug('Hindu'), isFalse);
      expect(validSlug('-x'), isFalse);
      expect(validSlug('a' * 41), isFalse);
      expect(idError('other', const [], religion: true), isNotNull);
      expect(idError('other', const []), isNull);
      expect(idError('ved', const ['ved']), isNotNull);
      expect(titleError('  '), isNotNull);
      expect(titleError('x' * 61), isNotNull);
      expect(titleError('वेद'), isNull);
    });

    test(
      'addSubgroup strips leaf-only fields; removing the last restores them',
      () {
        final g = newNode('ved', 'वेद');
        expect(g.containsKey('granthIds'), isTrue);
        addSubgroup(g, newNode('rigved', 'ऋग्वेद'));
        expect(g.containsKey('granthIds'), isFalse);
        expect(g.containsKey('keywords'), isFalse);
        expect(leafKeysUnder(g, 'hindu/ved'), ['hindu/ved/rigved']);
        removeChild(g, 'subgroups', 0);
        expect(g.containsKey('subgroups'), isFalse);
        expect(g['granthIds'], isEmpty);
        expect(leafKeysUnder(g, 'hindu/ved'), ['hindu/ved']);
      },
    );

    test('moveChild + religionLeafKeys + sameTree/deepCopy', () {
      final r = newNode('hindu', 'हिन्दू', religion: true, tone: 'saffron');
      final groups = childList(r, 'groups');
      groups.add(newNode('a', 'A'));
      groups.add(newNode('b', 'B'));
      final copy = deepCopy(r);
      expect(sameTree(r, copy), isTrue);
      expect(moveChild(groups, 1, -1), isTrue);
      expect(moveChild(groups, 0, -1), isFalse);
      expect(groups.map((g) => g['id']), ['b', 'a']);
      expect(sameTree(r, copy), isFalse);
      expect(religionLeafKeys(r), ['hindu/b', 'hindu/a']);
    });
  });

  group('dashboard cards (widget)', () {
    testWidgets('renders key numbers, top lists and the pending-granths card', (
      tester,
    ) async {
      final s = StatsOverview.fromJson(overviewJson);
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => SingleChildScrollView(
                child: Column(children: statsCards(c, s)),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('श्रीमद्भगवद्गीता'), findsWidgets);
      expect(find.textContaining('हिन्दू › पुराण'), findsWidgets);
      expect(
        find.textContaining('3'),
        findsWidgets,
      ); // N new granths need a folder
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty stats show a friendly state, not an error', (
      tester,
    ) async {
      final s = StatsOverview.fromJson({'days': 7});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => SingleChildScrollView(
                child: Column(children: statsCards(c, s)),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
