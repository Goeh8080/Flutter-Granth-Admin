import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin_ui/analytics/analytics_kit.dart';

void main() {
  final now = DateTime.utc(2026, 11, 1, 6);
  test('fills missing days with zero rows', () {
    final r = anFillDays(
      [
        {'day': '2026-10-30', 'app_opens': 4},
      ],
      7,
      '6daysAgo',
      null,
      now: now,
    );
    expect(r.length, 7);
    expect(r.first['day'], '2026-10-26');
    expect(r.last['day'], '2026-11-01');
    expect(r[4]['app_opens'], 4);
  });
  test('starts at reset day', () {
    final r = anFillDays(
      [],
      30,
      '2026-10-29',
      '2026-10-28T20:00:00Z',
      now: now,
    );
    expect(r.map((e) => e['day']).toList(), [
      '2026-10-29',
      '2026-10-30',
      '2026-10-31',
      '2026-11-01',
    ]);
  });
}
