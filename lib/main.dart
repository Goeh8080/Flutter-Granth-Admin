import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'screens/home_shell.dart';
import 'screens/dual_login_screen.dart';
import 'theme/app_theme.dart';
import 'theme/glass.dart';
import 'theme/smooth_scroll.dart';
import 'widgets/common.dart';
import 'widgets/toast.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );
  final state = AppState()..boot();
  runApp(AppScope(state: state, child: const GranthAdminApp()));
}

class GranthAdminApp extends StatefulWidget {
  const GranthAdminApp({super.key});
  @override
  State<GranthAdminApp> createState() => _GranthAdminAppState();
}

class _GranthAdminAppState extends State<GranthAdminApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) AppScope.of(context).verifySession();
  }

  // Built once: ColorScheme.fromSeed + ThemeData are expensive and used to be rebuilt (twice)
  // on every AppState notification.
  static final ThemeData _light = buildTheme(Brightness.light);
  static final ThemeData _dark = buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    // Only a theme-mode change rebuilds the MaterialApp.
    return AppSelector<ThemeMode>(
      selector: (a) => a.themeMode,
      builder: (context, app, mode) => MaterialApp(
        title: 'ग्रंथ प्रबंधन Admin',
        debugShowCheckedModeBanner: false,
        navigatorKey: rootNavKey,
        scrollBehavior: const SmoothScrollBehavior(),
        themeMode: mode,
        theme: _light,
        darkTheme: _dark,
        home: const _Gate(),
      ),
    );
  }
}

/// Switches between login and the app with a cross-fade; pops any pushed routes on logout/expiry.
class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool? _wasLoggedIn; // wnm website session
  bool? _wasReady; // both sessions valid (the app is open)
  @override
  Widget build(BuildContext context) {
    // Rebuild only when the gate-relevant flags change (not on every cache fill / panel tick).
    return AppSelector<(bool, bool, bool, String?)>(
      selector: (a) => (a.booting, a.loggedIn, a.panel.loggedIn, a.expiredMessage),
      builder: (context, app, _) => _gate(context, app),
    );
  }

  Widget _gate(BuildContext context, AppState app) {
    // The app needs BOTH sessions (website + control server); one expiring asks only for that one.
    final ready = app.loggedIn && app.panel.loggedIn;
    final wnmDropped = _wasLoggedIn == true && !app.loggedIn;
    if (_wasReady == true && !ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) => rootNavKey.currentState?.popUntil((r) => r.isFirst));
      // (the control server toasts its own expiry)
      if (wnmDropped && app.expiredMessage != null) {
        final msg = app.expiredMessage!;
        WidgetsBinding.instance.addPostFrameCallback((_) => showToast(msg, error: true));
      }
    }
    _wasLoggedIn = app.booting ? null : app.loggedIn;
    _wasReady = app.booting ? null : ready;
    final Widget child;
    if (app.booting) {
      child = const GlassBackdrop(
        key: ValueKey('boot'),
        child: Scaffold(backgroundColor: Colors.transparent, body: LoadingView()),
      );
    } else if (ready) {
      child = const HomeShell(key: ValueKey('home'));
    } else {
      child = const DualLoginScreen(key: ValueKey('login'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: c),
      ),
      child: child,
    );
  }
}
