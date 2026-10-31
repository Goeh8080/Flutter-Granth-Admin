import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin_ui/round3_screens.dart';

void main() {
  test('parseTopicIds', () {
    expect(parseTopicIds('12, vrat 12,,a_b'), ['12', 'vrat', 'a_b']);
    expect(parseTopicIds(''), <String>[]);
    expect(parseTopicIds('bad id!'), isNull);
    expect(parseTopicIds(List.generate(13, (i) => 't$i').join(',')), isNull);
  });
}
