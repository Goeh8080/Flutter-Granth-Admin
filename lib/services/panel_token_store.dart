import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the control-server bearer token lives between launches.
abstract class PanelTokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

/// Keeps the token in memory only (tests, or when secure storage is unavailable).
class MemoryPanelTokenStore implements PanelTokenStore {
  String? _v;
  @override
  Future<String?> read() async => _v;
  @override
  Future<void> write(String? token) async => _v = token;
}

/// Encrypted storage (Android Keystore / iOS Keychain). The token is never written to
/// SharedPreferences or logs. If the secure store is broken we simply behave as logged out.
class SecurePanelTokenStore implements PanelTokenStore {
  SecurePanelTokenStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _k = 'granth_panel_token';
  static const _t = Duration(seconds: 5);

  @override
  Future<String?> read() async {
    try {
      return await _s.read(key: _k).timeout(_t);
    } catch (e) {
      debugPrint('GranthAdmin panel token read failed (${e.runtimeType})');
      return null;
    }
  }

  @override
  Future<void> write(String? token) async {
    try {
      if (token == null) {
        await _s.delete(key: _k).timeout(_t);
      } else {
        await _s.write(key: _k, value: token).timeout(_t);
      }
    } catch (e) {
      debugPrint('GranthAdmin panel token write failed (${e.runtimeType})');
    }
  }
}
