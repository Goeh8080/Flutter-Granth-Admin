// Round 2: arranging granths (manual order saved through the wnm update_granth_order flow).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin/core/app_state.dart';
import 'package:granthadmin/admin/models/models.dart' as w;
import 'package:granthadmin/admin/services/granth_api.dart';
import 'package:granthadmin/admin_ui/admin_data.dart';
import 'package:granthadmin/admin_ui/arrange_granths.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

w.Granth g(int id, int pos, [String? title]) => w.Granth.fromJson({
  'id': '$id',
  'title': title ?? 'ग्रंथ $id',
  'position': '$pos',
  'isActive': '1',
  'extra': 'keep-$id',
});

List<int> ids(List<w.Granth> l) => [for (final x in l) x.id];

Future<void> settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('catalogueForFolderOrder', () {
    final all = [for (var i = 1; i <= 8; i++) g(i, i)];

    test('the folder keeps its slots; others do not move', () {
      // Folder = 2, 4, 7 (slots 1, 3, 6). New order 7, 2, 4.
      final out = catalogueForFolderOrder(all, [7, 2, 4]);
      expect(ids(out), [1, 7, 3, 2, 5, 6, 4, 8]);
    });
    test('whole catalogue reversed', () {
      final out = catalogueForFolderOrder(all, [8, 7, 6, 5, 4, 3, 2, 1]);
      expect(ids(out), [8, 7, 6, 5, 4, 3, 2, 1]);
    });
    test('unknown ids are ignored, nothing is lost or duplicated', () {
      final out = catalogueForFolderOrder(all, [3, 99, 1]);
      expect(ids(out), [3, 2, 1, 4, 5, 6, 7, 8]);
      expect(ids(out).toSet().length, 8);
    });
    test('same order = same catalogue', () {
      expect(ids(catalogueForFolderOrder(all, [2, 4, 7])), ids(all));
    });
  });

  test('moveItem top / bottom / clamp', () {
    final l = [1, 2, 3, 4];
    expect(moveItem(l, 3, 0), [4, 1, 2, 3]);
    expect(moveItem(l, 0, 3), [2, 3, 4, 1]);
    expect(moveItem(l, 1, 2), [1, 3, 2, 4]);
    expect(moveItem(l, 1, 99), [1, 3, 4, 2]);
    expect(identical(moveItem(l, 1, 1), l), isTrue);
  });

  testWidgets('arrange screen: move, save → update_granth_order body', (
    t,
  ) async {
    final posts = <(String, String)>[];
    final all = [for (var i = 1; i <= 6; i++) g(i, i)];
    final state = AppState(
      api: GranthApi(
        ApiClient(
          client: MockClient((req) async {
            if (req.method == 'POST') {
              posts.add((req.url.toString(), req.body));
            }
            return http.Response(
              '{"success":true,"isLogin":true,"data":[]}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      ),
    );
    state.granths = all;
    AdminData.I = AdminData(state, warmSearch: false);
    addTearDown(() => AdminData.I.dispose());

    // The open folder holds 2, 4, 6 (slots 1, 3, 5 of the catalogue).
    await t.pumpWidget(
      MaterialApp(
        home: ArrangeGranthsScreen(
          items: [
            for (final i in [2, 4, 6]) ArrangeItem(i, 'ग्रंथ $i'),
          ],
          folderTitle: 'वेद',
        ),
      ),
    );
    await settle(t);
    expect(find.text('ग्रंथ 2'), findsOneWidget);
    // Save is disabled until something moved.
    await t.tap(find.byKey(const ValueKey('arr-save')));
    await settle(t);
    expect(posts, isEmpty);

    await t.tap(find.byKey(const ValueKey('arr-bottom-2'))); // 4, 6, 2
    await settle(t);
    await t.tap(find.byKey(const ValueKey('arr-top-6'))); // 6, 4, 2
    await settle(t);
    final top = t.getTopLeft(find.text('ग्रंथ 6')).dy;
    expect(top, lessThan(t.getTopLeft(find.text('ग्रंथ 4')).dy));
    expect(
      t.getTopLeft(find.text('ग्रंथ 4')).dy,
      lessThan(t.getTopLeft(find.text('ग्रंथ 2')).dy),
    );

    await t.tap(find.byKey(const ValueKey('arr-save')));
    await settle(t);
    // confirmPop → "सहेजें"
    await t.tap(find.text('सहेजें').last);
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(t);

    final order = posts.where((p) => p.$1.contains('update_granth_order'));
    expect(order, hasLength(1));
    final body = jsonDecode(order.first.$2) as Map<String, dynamic>;
    final sent = [for (final x in body['granths'] as List) x as Map];
    // Whole catalogue, folder re-ordered inside its slots; full objects untouched.
    expect([for (final x in sent) int.parse('${x['id']}')], [1, 6, 3, 4, 5, 2]);
    expect(sent.first['extra'], 'keep-1');
    expect(sent[1]['extra'], 'keep-6');
  });
}
