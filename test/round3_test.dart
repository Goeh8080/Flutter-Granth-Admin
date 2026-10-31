import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin_ui/round3_screens.dart';

void main() {
  test('parseTopicIds', () {
    expect(parseTopicIds('12, vrat 12,,a_b'), ['12', 'vrat', 'a_b']);
    expect(parseTopicIds(''), <String>[]);
    expect(parseTopicIds('bad id!'), isNull);
    expect(parseTopicIds(List.generate(13, (i) => 't$i').join(',')), isNull);
  });

  test('featureFlagKeys: base flags first, then server list, deduped', () {
    expect(
      featureFlagKeys({
        'feature_flags': ['support_enabled', 'ai_enabled', 'daily_enabled'],
      }),
      ['ai_enabled', 'analytics_enabled', 'support_enabled', 'daily_enabled'],
    );
    expect(featureFlagKeys({}), ['ai_enabled', 'analytics_enabled']);
    for (final k in [
      'support_enabled',
      'trending_enabled',
      'daily_enabled',
      'notifications_enabled',
    ]) {
      expect(kFeatureFlagLabels.containsKey(k), isTrue);
    }
    for (final t in ['new_praman', 'new_topic', 'trending', 'daily', 'all']) {
      expect(kNotifyTopicLabels.containsKey(t), isTrue);
    }
  });
}
