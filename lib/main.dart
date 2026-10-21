import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'theme/glass.dart';
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

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, listen: true);
    return MaterialApp(
      title: 'ग्रंथ प्रबंधन Admin',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavKey,
      themeMode: app.themeMode,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const _Gate(),
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
  bool? _wasLoggedIn;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, listen: true);
    if (_wasLoggedIn == true && !app.loggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        rootNavKey.currentState?.popUntil((r) => r.isFirst);
        final msg = app.expiredMessage;
        if (msg != null) {
          app.expiredMessage = null;
          showToast(msg, error: true);
        }
      });
    }
    _wasLoggedIn = app.booting ? null : app.loggedIn;
    final Widget child;
    if (app.booting) {
      child = const GlassBackdrop(
        key: ValueKey('boot'),
        child: Scaffold(backgroundColor: Colors.transparent, body: LoadingView()),
      );
    } else if (app.loggedIn) {
      child = const HomeShell(key: ValueKey('home'));
    } else {
      child = const LoginScreen(key: ValueKey('login'));
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
