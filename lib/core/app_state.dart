import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/granth_api.dart';
import 'panel_state.dart';

class PrefsCookieStore implements CookieStore {
  static const _k = 'granth_admin_cookie';
  @override
  Future<String?> read() async {
    try {
      return (await SharedPreferences.getInstance().timeout(const Duration(seconds: 5))).getString(_k);
    } catch (e) {
      debugPrint('GranthAdmin cookie store read failed: $e');
      return null;
    }
  }
  @override
  Future<void> write(String? cookie) async {
    final SharedPreferences p;
    try {
      p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('GranthAdmin cookie store write failed: $e');
      return;
    }
    if (cookie == null) {
      await p.remove(_k);
    } else {
      await p.setString(_k, cookie);
    }
  }
}

/// Global app state: API, login state, theme, and shared caches used by pickers/suggestions.
class AppState extends ChangeNotifier {
  AppState({GranthApi? api, PanelState? panel})
    : api = api ?? GranthApi(ApiClient(store: PrefsCookieStore())),
      panel = panel ?? PanelState() {
    this.api.client.onSessionExpired = _expired;
    // The control-server session is separate; forward its changes so the gate/tabs rebuild.
    this.panel.addListener(notifyListeners);
  }

  final GranthApi api;

  /// Second login: the control server (app control + analytics). Independent of [loggedIn].
  final PanelState panel;

  /// True when at least one of the two sessions is active (the app works with only one).
  bool get anyLoggedIn => loggedIn || panel.loggedIn;
  bool loggedIn = false;
  bool booting = true;
  String username = '';
  ThemeMode themeMode = ThemeMode.system;

  List<Topic> topics = const [];
  List<Granth> granths = const [];
  List<Praman> pramans = const [];
  Stats? stats;

  /// Increments after any write so open lists can refresh.
  int revision = 0;

  static const _kTheme = 'granth_admin_theme';
  static const _kUser = 'granth_admin_user';

  /// Startup. Whatever happens (plugin failure, no network, slow server, bad JSON)
  /// this always ends with [booting] = false so the UI leaves the loading screen.
  Future<void> boot() async {
    final panelBoot = panel.boot(); // independent; never throws
    try {
      await _boot().timeout(const Duration(seconds: 15));
    } catch (e, st) {
      debugPrint('GranthAdmin boot failed: $e\n$st');
    } finally {
      await panelBoot;
      booting = false;
      notifyListeners();
    }
  }

  Future<void> _boot() async {
    try {
      final p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      themeMode = ThemeMode.values[(p.getInt(_kTheme) ?? 0).clamp(0, 2)];
      username = p.getString(_kUser) ?? '';
    } catch (e) {
      debugPrint('GranthAdmin prefs unavailable: $e');
    }
    bool hasCookie;
    try {
      hasCookie = await api.client.hasCookie;
    } catch (e) {
      debugPrint('GranthAdmin cookie read failed: $e');
      hasCookie = false;
    }
    if (!hasCookie) return;
    try {
      loggedIn = await api.checkSession().timeout(sessionCheckTimeout);
      if (!loggedIn) await api.client.clearCookie();
    } on SessionExpiredException {
      loggedIn = false;
    } on ApiException {
      // offline / server trouble: trust the stored cookie; the next protected call verifies it
      loggedIn = true;
    } on TimeoutException {
      loggedIn = true;
    } catch (e) {
      debugPrint('GranthAdmin session check failed: $e');
      loggedIn = true;
    }
  }

  static const sessionCheckTimeout = Duration(seconds: 10);

  /// Re-check on app resume.
  Future<void> verifySession() async {
    unawaited(panel.verify());
    if (!loggedIn) return;
    try {
      if (!await api.checkSession().timeout(sessionCheckTimeout)) _expired();
    } on SessionExpiredException {
      // already handled by onSessionExpired
    } catch (_) {
      // network trouble / timeout: keep the session
    }
  }

  Future<bool> login(String user, String pass) async {
    final ok = await api.login(user, pass);
    if (ok) {
      loggedIn = true;
      username = user;
      try {
        (await SharedPreferences.getInstance()).setString(_kUser, user);
      } catch (_) {}
      notifyListeners();
    }
    return ok;
  }

  Future<void> logout() async {
    await api.logout();
    loggedIn = false;
    topics = const [];
    granths = const [];
    pramans = const [];
    stats = null;
    notifyListeners();
  }

  String? expiredMessage;
  void _expired() {
    if (!loggedIn) return;
    loggedIn = false;
    expiredMessage = const SessionExpiredException().message;
    api.client.clearCookie();
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setInt(_kTheme, m.index);
    } catch (_) {}
  }

  Future<List<Topic>> loadTopics() async {
    topics = await api.topics();
    notifyListeners();
    return topics;
  }

  Future<List<Granth>> loadGranths() async {
    granths = await api.granths();
    notifyListeners();
    return granths;
  }

  Future<List<Praman>> loadPramans() async {
    pramans = await api.pramans();
    notifyListeners();
    return pramans;
  }

  Future<Stats> loadStats() async {
    stats = await api.stats();
    notifyListeners();
    return stats!;
  }

  Future<void> ensureLookups() async {
    final f = <Future>[];
    if (topics.isEmpty) f.add(loadTopics());
    if (granths.isEmpty) f.add(loadGranths());
    await Future.wait(f);
  }

  void bump() {
    revision++;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context, {bool listen = false}) {
    if (listen) return context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
    return (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
  }
}
