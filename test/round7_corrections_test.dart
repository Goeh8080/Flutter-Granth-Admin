import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin_ui/round3_screens.dart';

void main() {
  testWidgets(
    'approve dialog enforces 50..2000 chars and returns trimmed text',
    (t) async {
      String? out;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async => out = await showDialog<String>(
                context: c,
                builder: (_) =>
                    const CorrectionApproveDialog(initial: 'छोटा सुधार'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      final ok = find.byKey(const ValueKey('corr-approve-ok'));
      expect(t.widget<TextButton>(ok).onPressed, isNull);
      final long = '  ${'स' * 60}  ';
      await t.enterText(find.byKey(const ValueKey('corr-answer')), long);
      await t.pump();
      expect(t.widget<TextButton>(ok).onPressed, isNotNull);
      await t.tap(ok);
      await t.pumpAndSettle();
      expect(out, long.trim());
      expect(kCorrectionMin, 50);
      expect(kCorrectionMax, 2000);
    },
  );
}
