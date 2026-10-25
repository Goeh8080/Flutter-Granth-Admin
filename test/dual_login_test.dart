// The start screen asks for BOTH logins (control server + wnm website); the app opens only when
// both sessions are valid, and a later expiry asks again for just the one that expired.
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin/core/app_state.dart';
import 'package:granthadmin/admin/core/panel_state.dart';
import 'package:granthadmin/main.dart';
import 'package:granthadmin/admin/screens/dual_login_screen.dart';
import 'package:granthadmin/screens/home_shell.dart';
import 'package:granthadmin/admin/services/granth_api.dart';
import 'package:granthadmin/admin/services/panel_api.dart';
import 'package:granthadmin/admin/services/panel_token_store.dart';
import 'package:granthadmin/admin/widgets/common.dart';
import 'package:granthadmin/admin_ui/admin_data.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _panelUser = 'ctl',
    _panelPass = 'panel-pass',
    _wnmUser = 'tester',
    _wnmPass = 'wnm-pass';

class _Rig {
  _Rig({MemoryPanelTokenStore? store, MemoryCookieStore? cookies})
    : store = store ?? MemoryPanelTokenStore(),
      cookies = cookies ?? MemoryCookieStore() {
    panel = PanelState(
      api: PanelApi(
        baseUrl: 'https://panel.test',
        store: this.store,
        client: MockClient((req) async {
          panelCalls.add('${req.method} ${req.url.path}');
          if (req.url.path.endsWith('/login')) {
            final b = jsonDecode(req.body) as Map;
            if (b['username'] == _panelUser && b['password'] == _panelPass) {
              return _json({
                'token': 'tok',
                'expires_in': 86400,
                'username': _panelUser,
              });
            }
            return _json({'error': 'bad_credentials'}, 401);
          }
          return _json({
            'ok': true,
            'username': _panelUser,
            'count': 0,
            'items': [],
          });
        }),
      ),
    );
    state = AppState(
      api: GranthApi(
        ApiClient(
          store: this.cookies,
          client: MockClient((req) async {
            final a = req.url.queryParameters['action'] ?? '';
            wnmCalls.add(a);
            if (a == 'get_user') {
              final b = jsonDecode(req.body) as Map;
              final ok = b['username'] == _wnmUser && b['password'] == _wnmPass;
              return http.Response(
                jsonEncode({'success': ok}),
                200,
                headers: {
                  'content-type': 'application/json',
                  if (ok) 'set-cookie': 'PHPSESSID=abc; path=/',
                },
              );
            }
            return http.Response(
              '{"success":true,"isLogin":true,"data":[]}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      ),
      panel: panel,
    );
  }
  final MemoryPanelTokenStore store;
  final MemoryCookieStore cookies;
  late final PanelState panel;
  late final AppState state;
  final panelCalls = <String>[];
  final wnmCalls = <String>[];
  Widget get app =>
      AppScope(state: state, child: const GranthAdminApp(splash: false));
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NetImage.enabled = false;
  });

  Future<void> settle(WidgetTester t, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> net(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await settle(t, 15);
  }

  Future<_Rig> start(WidgetTester t, {_Rig? rig}) async {
    t.view.physicalSize = const Size(1080, 2800);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    ApiClient.isolateDecodeThreshold = 1 << 30;
    addTearDown(() => ApiClient.isolateDecodeThreshold = 64 * 1024);
    rig ??= _Rig();
    AdminData.I = AdminData(rig.state, warmSearch: false);
    await t.runAsync(() => rig!.state.boot());
    await t.pumpWidget(rig.app);
    await settle(t);
    return rig;
  }

  // The two sections make the page taller than a phone: it scrolls, so bring the button into view.
  Future<void> submit(WidgetTester t) async {
    await t.ensureVisible(find.text('लॉगिन / Login'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('लॉगिन / Login'));
  }

  Finder field(int i) => find.byType(CupertinoTextField).at(i);

  testWidgets(
    'shows both sections with blank usernames, eye toggles and one button',
    (t) async {
      final rig = await start(t);
      expect(find.byType(DualLoginScreen), findsOneWidget);
      expect(find.text('ऐप एडमिन (कंट्रोल सर्वर)'), findsOneWidget);
      expect(find.text('wnm सर्वर (डेटा एडिट)'), findsOneWidget);
      expect(find.byType(CupertinoTextField), findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        expect(
          (t.widget(field(i)) as CupertinoTextField).controller!.text,
          isEmpty,
        );
      }
      expect(find.byKey(const ValueKey('toggle-password')), findsNWidgets(2));
      // password fields are hidden until the eye is tapped
      expect((t.widget(field(1)) as CupertinoTextField).obscureText, isTrue);
      await t.tap(find.byKey(const ValueKey('toggle-password')).first);
      await t.pump();
      expect((t.widget(field(1)) as CupertinoTextField).obscureText, isFalse);
      expect((t.widget(field(3)) as CupertinoTextField).obscureText, isTrue);
      expect(find.text('लॉगिन / Login'), findsOneWidget);
      expect(rig.state.anyLoggedIn, isFalse);
      await settle(t, 40);
    },
  );

  testWidgets('empty fields: an error under each section, nothing is sent', (
    t,
  ) async {
    final rig = await start(t);
    await submit(t);
    await settle(t, 6);
    expect(
      find.text('कृपया यूज़रनेम डालें / Please enter username'),
      findsNWidgets(2),
    );
    // only the panel section filled -> only the wnm section complains
    await t.enterText(field(0), _panelUser);
    await t.enterText(field(1), _panelPass);
    await submit(t);
    await settle(t, 6);
    expect(
      find.text('कृपया यूज़रनेम डालें / Please enter username'),
      findsOneWidget,
    );
    expect(rig.panelCalls, isEmpty);
    expect(rig.wnmCalls, isEmpty);
    await settle(t, 40);
  });

  testWidgets('both correct -> both sessions stored and the app opens', (
    t,
  ) async {
    final rig = await start(t);
    await t.enterText(field(0), _panelUser);
    await t.enterText(field(1), _panelPass);
    await t.enterText(field(2), _wnmUser);
    await t.enterText(field(3), _wnmPass);
    await submit(t);
    await net(t);
    await net(t);
    expect(rig.state.loggedIn, isTrue);
    expect(rig.state.panel.loggedIn, isTrue);
    expect(
      await rig.store.read(),
      'tok',
      reason: 'control-server token goes to the token store',
    );
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(DualLoginScreen), findsNothing);
    await settle(t, 40);
  });

  testWidgets(
    'wrong wnm password: error only in the wnm section, panel stays connected',
    (t) async {
      final rig = await start(t);
      await t.enterText(field(0), _panelUser);
      await t.enterText(field(1), _panelPass);
      await t.enterText(field(2), _wnmUser);
      await t.enterText(field(3), 'nope');
      await submit(t);
      await net(t);
      expect(rig.state.panel.loggedIn, isTrue);
      expect(rig.state.loggedIn, isFalse);
      expect(
        find.byType(HomeShell),
        findsNothing,
        reason: 'both logins are required',
      );
      expect(
        find.text('गलत लॉगिन विवरण / Incorrect login details'),
        findsOneWidget,
      );
      expect(find.text('जुड़ गया / Connected'), findsOneWidget);
      // only the wnm fields are left to fill
      expect(find.byType(CupertinoTextField), findsNWidgets(2));
      await t.enterText(field(0), _wnmUser);
      await t.enterText(field(1), _wnmPass);
      await submit(t);
      await net(t);
      await net(t);
      expect(rig.state.loggedIn, isTrue);
      expect(find.byType(HomeShell), findsOneWidget);
      await settle(t, 40);
    },
  );

  testWidgets('wrong panel password: error only in the panel section', (
    t,
  ) async {
    final rig = await start(t);
    await t.enterText(field(0), _panelUser);
    await t.enterText(field(1), 'bad');
    await t.enterText(field(2), _wnmUser);
    await t.enterText(field(3), _wnmPass);
    await submit(t);
    await net(t);
    expect(rig.state.loggedIn, isTrue);
    expect(rig.state.panel.loggedIn, isFalse);
    expect(find.byType(HomeShell), findsNothing);
    expect(find.text('जुड़ गया / Connected'), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(2));
    expect(await rig.store.read(), isNull);
    await settle(t, 40);
  });

  testWidgets('later launch skips the screen while both sessions are valid', (
    t,
  ) async {
    final first = await start(t);
    await t.enterText(field(0), _panelUser);
    await t.enterText(field(1), _panelPass);
    await t.enterText(field(2), _wnmUser);
    await t.enterText(field(3), _wnmPass);
    await submit(t);
    await net(t);
    await net(t);
    expect(find.byType(HomeShell), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await settle(t, 5);
    // "restart": new state objects, same stored token + cookie
    final second = await start(
      t,
      rig: _Rig(store: first.store, cookies: first.cookies),
    );
    expect(second.state.loggedIn, isTrue);
    expect(second.state.panel.loggedIn, isTrue);
    expect(find.byType(DualLoginScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
    await settle(t, 40);
  });

  testWidgets(
    'one expired session asks only for that one; logout asks only for the website',
    (t) async {
      final rig = await start(t);
      await t.enterText(field(0), _panelUser);
      await t.enterText(field(1), _panelPass);
      await t.enterText(field(2), _wnmUser);
      await t.enterText(field(3), _wnmPass);
      await submit(t);
      await net(t);
      await net(t);
      expect(find.byType(HomeShell), findsOneWidget);

      // control-server session expires (401 on a protected call)
      rig.panel.api.onUnauthorized!();
      await settle(t, 20);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(DualLoginScreen), findsOneWidget);
      expect(
        rig.state.loggedIn,
        isTrue,
        reason: 'the wnm session is untouched',
      );
      expect(
        find.byType(CupertinoTextField),
        findsNWidgets(2),
        reason: 'only the expired section is asked',
      );
      expect(find.text('जुड़ गया / Connected'), findsOneWidget);
      await t.enterText(field(0), _panelUser);
      await t.enterText(field(1), _panelPass);
      await submit(t);
      await net(t);
      await net(t);
      expect(find.byType(HomeShell), findsOneWidget);

      // website logout keeps the control-server session and asks only for the website
      await t.runAsync(() => rig.state.logout());
      await settle(t, 20);
      // (while the old home screen fades out its logged-out banner may overflow in the wide test font)
      t.takeException();
      expect(find.byType(DualLoginScreen), findsOneWidget);
      expect(rig.state.panel.loggedIn, isTrue);
      expect(find.byType(CupertinoTextField), findsNWidgets(2));
      await settle(t, 40);
    },
  );
}
