// Round 2: the file-manager style folder picker.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin_ui/folder_picker.dart';
import 'package:granthadmin/models/structure.dart';
import 'package:shared_preferences/shared_preferences.dart';

Structure load() =>
    Structure.parse(File('assets/structure/structure.json').readAsStringSync());

Future<void> settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('FolderTree', () {
    final tree = FolderTree(load());
    test('top level = every religion + अन्य', () {
      final top = tree.children(const []);
      expect(top.length, load().religions.length + 1);
      expect(top.last.id, kOtherId);
      expect(top.last.isLeaf, isTrue);
      expect(top.first.isLeaf, isFalse);
    });
    test('religion → groups → sub-folders; leaves vs folders', () {
      final groups = tree.children(['hindu']);
      expect(groups.map((e) => e.id), containsAll(['ved', 'geeta']));
      expect(groups.firstWhere((e) => e.id == 'ved').isLeaf, isFalse);
      expect(groups.firstWhere((e) => e.id == 'geeta').isLeaf, isTrue);
      expect(
        tree.children(['hindu', 'ved']).map((e) => e.id),
        contains('rigved'),
      );
      expect(tree.isLeaf(['hindu']), isFalse);
      expect(tree.isLeaf(['hindu', 'ved']), isFalse);
      expect(tree.isLeaf(['hindu', 'ved', 'rigved']), isTrue);
      expect(tree.isLeaf(['hindu', 'geeta']), isTrue);
      expect(tree.isLeaf([kOtherId]), isTrue);
    });
    test('keys round-trip', () {
      expect(tree.keyOf(['hindu', 'ved', 'rigved']), 'hindu/ved/rigved');
      expect(tree.keyOf([kOtherId]), kOtherId);
      expect(tree.pathOf('hindu/ved/rigved'), ['hindu', 'ved', 'rigved']);
      expect(tree.pathOf(kOtherId), [kOtherId]);
      expect(tree.titles(['hindu', 'ved', 'rigved']).length, 3);
    });
    test('every leaf of the structure is reachable and is a leaf', () {
      for (final l in load().leaves()) {
        expect(tree.isLeaf(tree.pathOf(l.key)), isTrue, reason: l.key);
      }
    });
  });

  testWidgets(
    'drill down: religions → inside → paste here; पीछे goes up one level',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      String? picked;
      var closed = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FolderPickerSheet(
              structure: load(),
              granthTitle: 'ऋग्वेद भाष्य',
              current: 'hindu/ved/rigved',
              onPick: (k) => picked = k,
              onClose: () => closed = true,
            ),
          ),
        ),
      );
      await settle(t);
      // Level 0: religions; the one holding the granth is marked.
      expect(find.byKey(const ValueKey('fp-row-hindu')), findsOneWidget);
      expect(find.byKey(const ValueKey('fp-row-islam')), findsOneWidget);
      expect(find.byKey(const ValueKey('fp-row-other')), findsOneWidget);
      expect(find.text('ग्रंथ यहाँ है'), findsOneWidget);
      expect(find.byKey(const ValueKey('fp-paste')), findsNothing);

      await t.tap(find.byKey(const ValueKey('fp-row-hindu')));
      await settle(t);
      expect(find.byKey(const ValueKey('fp-row-hindu/ved')), findsOneWidget);
      expect(find.byKey(const ValueKey('fp-row-islam')), findsNothing);
      expect(
        find.byKey(const ValueKey('fp-paste')),
        findsNothing,
      ); // not a leaf

      await t.tap(find.byKey(const ValueKey('fp-row-hindu/geeta')));
      await settle(t);
      expect(find.byKey(const ValueKey('fp-paste')), findsOneWidget);

      // पीछे: up ONE level, the sheet stays open.
      await t.tap(find.text('पीछे'));
      await settle(t);
      expect(closed, isFalse);
      expect(find.byKey(const ValueKey('fp-row-hindu/ved')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('fp-row-hindu/ved')));
      await settle(t);
      expect(
        find.byKey(const ValueKey('fp-row-hindu/ved/rigved')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('fp-row-hindu/ved/yajurved')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('fp-paste')));
      await settle(t);
      expect(picked, 'hindu/ved/yajurved');

      // Breadcrumb jumps to the top; पीछे at the top closes.
      await t.tap(find.text('सभी फ़ोल्डर'));
      await settle(t);
      expect(find.byKey(const ValueKey('fp-row-islam')), findsOneWidget);
      await t.tap(find.text('पीछे'));
      await settle(t);
      expect(closed, isTrue);
      await settle(t, 20);
    },
  );

  testWidgets(
    'अन्य is a leaf at the top level; current folder shows "अभी यहीं है"',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      String? picked;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FolderPickerSheet(
              structure: load(),
              granthTitle: 'x',
              current: kOtherId,
              startAtCurrent: true,
              onPick: (k) => picked = k,
              onClose: () {},
            ),
          ),
        ),
      );
      await settle(t);
      expect(find.byKey(const ValueKey('fp-paste')), findsOneWidget);
      expect(find.text('अभी यहीं है'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('fp-paste')));
      expect(picked, kOtherId);
      await settle(t, 20);
    },
  );
}
