import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_models.dart';
import '../services/panel_api.dart';
import '../services/panel_token_store.dart';
import '../widgets/toast.dart';
import 'panel_config.dart';

/// Route name used for every pushed control-server screen.
const kPanelRouteName = 'panel';

/// Second, independent session: the control server (`granth-admin` Worker).
/// It has its own login and its own secure token; the wnm website session lives in [AppState].
class PanelState extends ChangeNotifier {
  PanelState({PanelApi? api}) : api = api ?? PanelApi(store: SecurePanelTokenStore()) {
    this.api.onUnauthorized = _expired;
  }

  final PanelApi api;
  bool loggedIn = false;
  PanelMe? me;

  /// Unread new-granth + alert count shown as a badge.
  int alertCount = 0;

  /// How many control-server screens are pushed right now (see pushPanel).
  int panelDepth = 0;

  /// Bumped after any server edit so open screens can refresh.
  int revision = 0;

  static const _kBase = 'granth_panel_base';
  static const sessionCheckTimeout = Duration(seconds: 10);

  /// Reads the saved server address + token and checks the session. Never throws.
  Future<void> boot() async {
    try {
      await _boot().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('GranthAdmin panel boot failed (${e.runtimeType})');
    }
    notifyListeners();
  }

  Future<void> _boot() async {
    try {
      final p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      final b = p.getString(_kBase);
      if (b != null) {
        final n = normalizePanelBase(b);
        if (n != null) api.baseUrl = n;
      }
    } catch (_) {}
    if (!await api.hasToken) return;
    try {
      me = await api.me().timeout(sessionCheckTimeout);
      loggedIn = true;
    } on PanelUnauthorized {
      loggedIn = false;
    } on PanelApiException {
      // offline / server trouble: keep the stored token, the next call verifies it
      loggedIn = true;
    } on TimeoutException {
      loggedIn = true;
    }
  }

  /// Re-check when the app comes back to the foreground.
  Future<void> verify() async {
    if (!loggedIn) return;
    try {
      me = await api.me().timeout(sessionCheckTimeout);
      notifyListeners();
    } catch (_) {
      // 401 is handled by onUnauthorized; other errors keep the session
    }
  }

  Future<void> login(String password) => loginAs(kPanelUsername, password);

  Future<void> loginAs(String username, String password) async {
    await api.login(password, username: username);
    loggedIn = true;
    expiredMessage = null;
    try {
      me = await api.me();
    } catch (_) {}
    notifyListeners();
    unawaited(refreshAlerts());
  }

  Future<void> logout() async {
    await api.logout();
    _reset();
    notifyListeners();
  }

  void _reset() {
    loggedIn = false;
    me = null;
    alertCount = 0;
  }

  String? expiredMessage;
  void _expired() {
    if (!loggedIn) return;
    _reset();
    expiredMessage = const PanelUnauthorized().message;
    // Pushed screens above the tabs are either all control-server or all wnm screens.
    if (panelDepth > 0) rootNavKey.currentState?.popUntil((r) => r.isFirst);
    showToast(expiredMessage!, error: true);
    notifyListeners();
  }

  /// Saves a new server address (https only). Pass null/empty to go back to the default.
  Future<bool> setBase(String? raw) async {
    final String base;
    if (raw == null || raw.trim().isEmpty) {
      base = kPanelDefaultBase;
    } else {
      final n = normalizePanelBase(raw);
      if (n == null) return false;
      base = n;
    }
    api.baseUrl = base;
    try {
      final p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      if (base == kPanelDefaultBase) {
        await p.remove(_kBase);
      } else {
        await p.setString(_kBase, base);
      }
    } catch (_) {}
    notifyListeners();
    return true;
  }

  Future<void> refreshMe() async {
    try {
      me = await api.me();
      notifyListeners();
    } on PanelApiException {
      // ignore: shown by the screens that need it
    }
  }

  Future<void> refreshAlerts() async {
    try {
      final a = await api.alerts();
      alertCount = a.count;
      notifyListeners();
    } on PanelApiException {
      // badge only
    }
  }

  /// Call after the draft changed (edit, discard, publish).
  void bump() {
    revision++;
    notifyListeners();
    unawaited(refreshMe());
  }
}
