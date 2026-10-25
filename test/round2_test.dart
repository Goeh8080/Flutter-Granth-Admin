// Round 2: folders counts, multi-filters, sorting, admin/contact validators + API calls, password eye toggle.
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin/models/panel_models.dart';
import 'package:granthadmin/admin/screens/panel/panel_folders.dart';
import 'package:granthadmin/admin/screens/panel/panel_granths.dart';
import 'package:granthadmin/admin/services/panel_api.dart';
import 'package:granthadmin/admin/services/panel_token_store.dart';
import 'package:granthadmin/admin/widgets/common.dart';
import 'package:granthadmin/admin/widgets/grid_kit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

PanelGranth g(
  String id,
  String leaf, {
  int p = 0,
  bool hidden = false,
  bool isNew = false,
}) => PanelGranth.fromJson({
  'id': id,
  'title': 'T$id',
  'author': 'A',
  'praman_count': p,
  'leaf': leaf,
  'hidden': hidden,
  'is_new': isNew,
});

void main() {
  test('folderSub / folderTotals', () {
    expect(folderSub(3, 0), '3 ग्रंथ');
    expect(folderSub(3, 12), '3 ग्रंथ • 12 प्रमाण');
    final all = [
      g('1', 'a/b', p: 2),
      g('2', 'a/b', p: 5, hidden: true),
      g('3', 'a/c', p: 1),
    ];
    final t = folderTotals(['a/b', 'a/c'], all, const {});
    expect((t.granths, t.pramans), (2, 3));
    final fb = folderTotals(['a/b'], null, {'a/b': 7});
    expect((fb.granths, fb.pramans), (7, 0));
  });

  test('multi filters are ANDed', () {
    final all = [
      g('1', 'other', isNew: true),
      g('2', 'other'),
      g('3', 'x/y', isNew: true, hidden: true),
    ];
    List<String> ids(Set<GranthFilter> f) =>
        filterGranths(all, filters: f).map((e) => e.id).toList();
    expect(ids({GranthFilter.isNew}), ['1', '3']);
    expect(ids({GranthFilter.isNew, GranthFilter.other}), ['1']);
    expect(ids({GranthFilter.isNew, GranthFilter.hidden}), ['3']);
    expect(defaultOrder('number'), 'asc');
    expect(defaultOrder('opens'), 'desc');
  });

  test('sortedBy is stable and case-insensitive', () {
    expect(sortedBy(['b', 'A', 'c'], (s) => s), ['A', 'b', 'c']);
    expect(sortedBy(['b', 'A', 'c'], (s) => s, desc: true), ['c', 'b', 'A']);
    expect(sortedBy([(1, 'x'), (1, 'y'), (0, 'z')], (e) => e.$1), [
      (0, 'z'),
      (1, 'x'),
      (1, 'y'),
    ]);
  });

  test('admin validators', () {
    expect(adminUsernameError('ab'), isNotNull);
    expect(adminUsernameError('Good.Name-1'), isNull);
    expect(adminPasswordError('short', 'bob'), isNotNull);
    expect(adminPasswordError('samename-1', 'samename-1'), isNotNull);
    expect(adminPasswordError('long-enough-pw', 'bob'), isNull);
  });

  test('contact validators', () {
    expect(contactError(const PanelContact(id: '', name: '')), isNotNull);
    expect(
      contactError(const PanelContact(id: '', name: 'A', phone: '12ab')),
      isNotNull,
    );
    expect(
      contactError(const PanelContact(id: '', name: 'A', whatsapp: true)),
      isNotNull,
    );
    expect(
      contactError(
        const PanelContact(
          id: '',
          name: 'A',
          phone: '+919876543210',
          whatsapp: true,
        ),
      ),
      isNull,
    );
    expect(cleanPhone('+91 98765-43210'), '+919876543210');
  });

  group('api', () {
    late List<http.Request> reqs;
    late PanelApi api;
    setUp(() async {
      reqs = [];
      final store = MemoryPanelTokenStore();
      await store.write(
        'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
      );
      final client = MockClient((r) async {
        reqs.add(r);
        Object body = {'ok': true};
        if (r.url.path.endsWith('/admins') && r.method == 'GET') {
          body = {
            'items': [
              {
                'username': 'goutam',
                'role': 'owner',
                'you': true,
                'active_sessions': 1,
              },
            ],
            'roles': ['owner', 'admin'],
            'min_password_length': 10,
          };
        } else if (r.url.path.endsWith('/revoke_sessions')) {
          body = {'ok': true, 'revoked': 3};
        } else if (r.url.path.endsWith('/contacts')) {
          body = {
            'page': {'title': 'विशेष जानकार'},
            'items': [
              {
                'id': 'c1',
                'name': 'राम',
                'phone': '123',
                'whatsapp': true,
                'visible': true,
                'order': 0,
              },
            ],
            'max_contacts': 50,
          };
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      api = PanelApi(
        baseUrl: 'https://panel.test',
        store: store,
        client: client,
      );
    });

    test('admins list + revoke + update', () async {
      final l = await api.admins();
      expect(l.items.single.isOwner, isTrue);
      expect(l.minPasswordLength, 10);
      expect(await api.revokeAdminSessions('bob'), 3);
      expect(reqs.last.url.path, '/admin/api/admins/bob/revoke_sessions');
      await api.updateAdmin('bob', disabled: true);
      expect(reqs.last.method, 'PUT');
      expect(jsonDecode(reqs.last.body), {'disabled': true});
      await api.deleteAdmin('bob');
      expect(reqs.last.method, 'DELETE');
    });

    test('contacts get + put', () async {
      final c = await api.contacts();
      expect(c.items.single.name, 'राम');
      expect(c.maxContacts, 50);
      await api.putContacts(title: 'X', items: c.items);
      expect(reqs.last.method, 'PUT');
      final b = jsonDecode(reqs.last.body) as Map<String, dynamic>;
      expect(b['title'], 'X');
      expect((b['items'] as List).single['whatsapp'], true);
    });
  });

  testWidgets('password field has an eye toggle', (tester) async {
    final c = TextEditingController(text: 'secret');
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: GlassField(label: 'p', controller: c, obscure: true),
        ),
      ),
    );
    EditableText field() =>
        tester.widget<EditableText>(find.byType(EditableText));
    expect(field().obscureText, isTrue);
    await tester.tap(find.byKey(const ValueKey('toggle-password')));
    await tester.pump();
    expect(field().obscureText, isFalse);
    await tester.tap(find.byKey(const ValueKey('toggle-password')));
    await tester.pump();
    expect(field().obscureText, isTrue);
  });
}
