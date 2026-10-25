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

  /// Same counter as [revision] as a Listenable: screens reload on it without rebuilding on
  /// every unrelated [notifyListeners] (panel changes, cache fills, theme...).
  final ValueNotifier<int> revisionListenable = ValueNotifier<int>(0);

  // ---- optimistic show/hide toggles: the UI flips at once, the write syncs afterwards ----
  final Map<String, bool> _optimisticActive = {};

  /// Bumps whenever an optimistic override is added/removed.
  final ValueNotifier<int> optimisticListenable = ValueNotifier<int>(0);

  /// The displayed Active flag: a pending/just-confirmed toggle wins over [server].
  bool activeOf(String kind, int id, bool server) => _optimisticActive['$kind:$id'] ?? server;

  void setOptimisticActive(String kind, int id, bool active) {
    _optimisticActive['$kind:$id'] = active;
    optimisticListenable.value++;
  }

  void clearOptimisticActive(String kind, int id) {
    if (_optimisticActive.remove('$kind:$id') != null) optimisticListenable.value++;
  }

  /// Keeps the override a few seconds so the refetch triggered by [bump] can land first
  /// (no flicker back to the old value), then drops it.
  void settleOptimisticActive(String kind, int id, {Duration after = const Duration(seconds: 5)}) {
    Future.delayed(after, () => clearOptimisticActive(kind, id));
  }

  static const _kTheme = 'granth_admin_theme';
  static const _kUser = 'granth_admin_user';

  /// Startup. Whatever happens (plugin failure, no network, slow server, bad JSON)
  /// this always ends with [booting] = false so the UI leaves the loading screen.
  Future<void> boot() async {
    // The control-server boot only reads local prefs/token now (its network check runs in the
    // background), so neither session blocks the first frame on the network.
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
    if (loggedIn) unawaited(_verifyStoredSession());
  }

  /// Checks the stored cookie after the UI is already up (a stale cookie ends in the usual
  /// "session expired" flow instead of a splash screen that waits on the network).
  Future<void> _verifyStoredSession() async {
    try {
      if (!await api.checkSession().timeout(sessionCheckTimeout)) _expired();
    } on SessionExpiredException {
      // already handled by onSessionExpired
    } catch (_) {
      // offline / server trouble / timeout: keep the stored session
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
    // Trust the stored cookie now; [boot] verifies it in the background.
    loggedIn = hasCookie;
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
      expiredMessage = null;
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
    revisionListenable.value = revision;
    notifyListeners();
  }
}

/// Rebuilds only when [selector]'s result changes (like `context.select`), instead of on every
/// [AppState.notifyListeners].
class AppSelector<T> extends StatefulWidget {
  const AppSelector({super.key, required this.selector, required this.builder});
  final T Function(AppState app) selector;
  final Widget Function(BuildContext context, AppState app, T value) builder;
  @override
  State<AppSelector<T>> createState() => _AppSelectorState<T>();
}

class _AppSelectorState<T> extends State<AppSelector<T>> {
  late AppState _app;
  late T _value;

  @override
  void initState() {
    super.initState();
    _app = AppScope.of(context);
    _value = widget.selector(_app);
    _app.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = AppScope.of(context);
    if (!identical(a, _app)) {
      _app.removeListener(_changed);
      _app = a..addListener(_changed);
    }
  }

  void _changed() {
    final v = widget.selector(_app);
    if (v != _value) setState(() => _value = v);
  }

  @override
  void dispose() {
    _app.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _value = widget.selector(_app);
    return widget.builder(context, _app, _value);
  }
}

/// Mixin for screens that reload when [AppState.revision] changes (after any write).
/// Replaces `didChangeDependencies` + `AppScope.of(listen: true)`, which rebuilt the whole screen
/// on every app notification.
mixin RevisionReload<T extends StatefulWidget> on State<T> {
  late final AppState _revApp = AppScope.of(context);
  int _revSeen = -1;

  /// (Re)load the screen's data.
  Future<void> reload();

  @override
  void initState() {
    super.initState();
    _revApp.revisionListenable.addListener(_onRevision);
    _revSeen = _revApp.revision;
    Future.microtask(() {
      if (mounted) reload();
    });
  }

  void _onRevision() {
    if (_revApp.revision == _revSeen) return;
    _revSeen = _revApp.revision;
    if (mounted) reload();
  }

  @override
  void dispose() {
    _revApp.revisionListenable.removeListener(_onRevision);
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context, {bool listen = false}) {
    if (listen) return context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
    return (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
  }
}
