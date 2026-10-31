// Round 14: on a short phone the folder list scrolls inside the sheet to its last folder.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin_ui/folder_picker.dart';
import 'package:granthadmin/models/structure.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('short screen: the list scrolls to its last folder, no overflow', (t) async {
    t.view.physicalSize = const Size(960, 1200); // 320 x 400 dp
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final s = Structure.parse(File('assets/structure/structure.json').readAsStringSync());
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 400), textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: TextButton(
                onPressed: () => showFolderPicker(c, structure: s, granthTitle: 'ग्रंथ', current: null),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('fp-list')), findsOneWidget);
    final last = find.byKey(const ValueKey('fp-row-other'));
    await t.scrollUntilVisible(last, 80, scrollable: find.descendant(of: find.byKey(const ValueKey('fp-list')), matching: find.byType(Scrollable)));
    await t.pump(const Duration(milliseconds: 300));
    expect(last.hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
