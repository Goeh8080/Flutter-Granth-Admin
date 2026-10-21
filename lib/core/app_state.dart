import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/granth_api.dart';

class PrefsCookieStore implements CookieStore {
  static const _k = 'granth_admin_cookie';
  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_k);
  @override
  Future<void> write(String? cookie) async {
    final p = await SharedPreferences.getInstance();
    if (cookie == null) {
      await p.remove(_k);
    } else {
      await p.setString(_k, cookie);
    }
  }
}

/// Global app state: API, login state, theme, and shared caches used by pickers/suggestions.
class AppState extends ChangeNotifier {
  AppState({GranthApi? api}) : api = api ?? GranthApi(ApiClient(store: PrefsCookieStore())) {
    this.api.client.onSessionExpired = _expired;
  }

  final GranthApi api;
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

  Future<void> boot() async {
    final p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[(p.getInt(_kTheme) ?? 0).clamp(0, 2)];
    username = p.getString(_kUser) ?? '';
    if (await api.client.hasCookie) {
      try {
        loggedIn = await api.checkSession();
        if (!loggedIn) await api.client.clearCookie();
      } on SessionExpiredException {
        loggedIn = false;
      } on ApiException {
        // offline: trust the stored cookie; the next protected call will verify it
        loggedIn = true;
      }
    }
    booting = false;
    notifyListeners();
  }

  /// Re-check on app resume.
  Future<void> verifySession() async {
    if (!loggedIn) return;
    try {
      if (!await api.checkSession()) _expired();
    } on ApiException {
      // network trouble: keep the session
    }
  }

  Future<bool> login(String user, String pass) async {
    final ok = await api.login(user, pass);
    if (ok) {
      loggedIn = true;
      username = user;
      (await SharedPreferences.getInstance()).setString(_kUser, user);
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
    (await SharedPreferences.getInstance()).setInt(_kTheme, m.index);
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
