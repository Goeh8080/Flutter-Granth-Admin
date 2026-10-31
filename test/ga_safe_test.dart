import 'package:flutter_test/flutter_test.dart';
import 'package:granthadmin/admin/services/panel_api.dart';
import 'package:granthadmin/admin_ui/round3_screens.dart';

void main() {
  test('GA 503 becomes a zeros notice, not an error', () {
    final t = gaErrorText(
      const PanelApiException('x', code: 'ga_not_configured', status: 503),
    );
    expect(t, contains('ga_not_configured'));
    expect(t, contains('503'));
    expect(gaErrorText(Exception('net')), contains('शून्य'));
  });
}
