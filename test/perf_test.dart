// Performance helpers: debounce/memo, selector rebuild counts, revision reloads, GET de-duplication,
// off-thread JSON decoding, capped fling, optimistic toggles and animated list inserts/removals.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/core/app_state.dart';
import 'package:granthadmin/core/perf.dart';
import 'package:granthadmin/services/granth_api.dart';
import 'package:granthadmin/theme/smooth_scroll.dart';
import 'package:granthadmin/widgets/animated_items.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Reloader extends StatefulWidget {
  const _Reloader(this.onReload);
  final VoidCallback onReload;
  @override
  State<_Reloader> createState() => _ReloaderState();
}

class _ReloaderState extends State<_Reloader> with RevisionReload<_Reloader> {
  @override
  Future<void> reload() async => widget.onReload();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

AppState _state(Future<http.Response> Function(http.Request) h) =>
    AppState(api: GranthApi(ApiClient(client: MockClient(h))));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Debouncer / Memo', () {
    test('Debouncer runs only the last call after the delay', () async {
      final d = Debouncer(const Duration(milliseconds: 30));
      final seen = <int>[];
      for (var i = 0; i < 5; i++) {
        d(() => seen.add(i));
      }
      expect(seen, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(seen, [4]);
      d(() => seen.add(9));
      d.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(seen, [4], reason: 'dispose cancels the pending call');
    });

    test('Memo recomputes only when the key changes', () {
      final m = Memo<String, int>();
      var n = 0;
      expect(m.get('a', () => ++n), 1);
      expect(m.get('a', () => ++n), 1);
      expect(m.get('b', () => ++n), 2);
      m.clear();
      expect(m.get('b', () => ++n), 3);
    });
  });

  group('AppSelector / RevisionReload', () {
    testWidgets('rebuilds only when the selected value changes (also the first change)', (tester) async {
      final app = _state((r) async => http.Response('{"success":true,"data":[]}', 200));
      var builds = 0;
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: AppSelector<int>(
            selector: (a) => a.revision,
            builder: (_, _, v) {
              builds++;
              return Text('$v', textDirection: TextDirection.ltr);
            },
          ),
        ),
      );
      expect(builds, 1);
      app.setOptimisticActive('topic', 1, true); // unrelated state: no AppState notification
      await tester.pump();
      expect(builds, 1);
      app.bump(); // revision 0 -> 1: the very first change must show up
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(builds, 2);
      app.bump();
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      expect(builds, 3);
    });

    testWidgets('does not rebuild when a notification leaves the selection unchanged', (tester) async {
      final app = _state((r) async => http.Response('{"success":true,"data":[]}', 200));
      var builds = 0;
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: AppSelector<String>(
            selector: (a) => a.username,
            builder: (_, _, v) {
              builds++;
              return const SizedBox();
            },
          ),
        ),
      );
      app.bump(); // notifies listeners, username unchanged
      await tester.pump();
      app.bump();
      await tester.pump();
      expect(builds, 1);
    });

    testWidgets('RevisionReload loads once, then once per revision', (tester) async {
      final app = _state((r) async => http.Response('{"success":true,"data":[]}', 200));
      var loads = 0;
      await tester.pumpWidget(AppScope(state: app, child: _Reloader(() => loads++)));
      await tester.pump();
      expect(loads, 1);
      app.bump();
      await tester.pump();
      expect(loads, 2);
      await tester.pumpWidget(const SizedBox()); // disposed: listener removed
      app.bump();
      expect(loads, 2);
    });
  });

  group('ApiClient', () {
    test('identical concurrent GETs share one request', () async {
      final gate = Completer<void>();
      var hits = 0;
      final c = ApiClient(
        client: MockClient((r) async {
          if (r.method == 'GET') {
            hits++;
            await gate.future;
          }
          return http.Response('{"success":true,"isLogin":true,"data":[]}', 200);
        }),
      );
      final a = c.get('get_topics');
      final b = c.get('get_topics');
      final other = c.get('get_granths');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      await Future.wait([a, b, other]);
      expect(hits, 2, reason: 'two distinct URLs, the duplicate joined');
      expect(c.getsSent, 2);
      await c.get('get_topics');
      expect(c.getsSent, 3, reason: 'a finished GET is not cached by the dedupe');
    });

    test('large bodies are decoded off the main isolate, small ones inline', () async {
      final big = jsonEncode({
        'success': true,
        'data': [
          for (var i = 0; i < 4000; i++) {'id': i, 'title': 'ग्रंथ $i ' * 3},
        ],
      });
      expect(big.length, greaterThan(ApiClient.isolateDecodeThreshold));
      final c = ApiClient(
        client: MockClient(
          (r) async => http.Response(
            r.url.queryParameters['action'] == 'big' ? big : '{"success":true}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final before = ApiClient.isolateDecodes;
      final res = await c.get('big');
      expect((res['data'] as List).length, 4000);
      expect(ApiClient.isolateDecodes, before + 1);
      await c.get('small');
      expect(ApiClient.isolateDecodes, before + 1);
    });
  });

  test('SmoothScrollPhysics caps fling velocity', () {
    const physics = SmoothScrollPhysics();
    final m = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1e7,
      pixels: 100,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    final fast = physics.createBallisticSimulation(m, 40000)!;
    final capped = physics.createBallisticSimulation(m, kMaxFling)!;
    expect(fast.x(0.4), closeTo(capped.x(0.4), 0.001));
    expect(physics.maxFlingVelocity, kMaxFling);
  });

  test('optimistic active flag overrides the server value until cleared', () {
    final app = _state((r) async => http.Response('{}', 200));
    var ticks = 0;
    app.optimisticListenable.addListener(() => ticks++);
    expect(app.activeOf('granth', 3, true), isTrue);
    app.setOptimisticActive('granth', 3, false);
    expect(app.activeOf('granth', 3, true), isFalse);
    expect(app.activeOf('granth', 4, true), isTrue);
    expect(app.activeOf('topic', 3, true), isTrue, reason: 'kinds are independent');
    app.clearOptimisticActive('granth', 3);
    expect(app.activeOf('granth', 3, true), isTrue);
    expect(ticks, 2);
    app.clearOptimisticActive('granth', 3); // nothing to clear: no extra notification
    expect(ticks, 2);
  });

  testWidgets('AnimatedItemsSliver animates inserts/removals and keeps rows', (tester) async {
    Widget host(List<int> items) => MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            AnimatedItemsSliver<int>(
              items: items,
              idOf: (i) => i,
              itemBuilder: (_, i, _) => SizedBox(height: 40, child: Text('row $i')),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(host([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(find.text('row 2'), findsOneWidget);
    await tester.pumpWidget(host([1, 2, 3])); // same ids: fast path, nothing animates
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(host([1, 2, 3, 4]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('row 4'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(host([1, 3, 4]));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('row 2'), findsOneWidget, reason: 'removed row is still animating out');
    await tester.pumpAndSettle();
    expect(find.text('row 2'), findsNothing);
    expect(find.text('row 3'), findsOneWidget);
  });
}
