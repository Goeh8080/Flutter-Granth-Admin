import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin/core/app_state.dart';
import 'admin/screens/dual_login_screen.dart';
import 'admin/theme/app_theme.dart';
import 'admin/widgets/toast.dart' show rootNavKey, showToast;
import 'admin_ui/admin_data.dart';
import 'screens/home_shell.dart';
import 'screens/splash_screen.dart';
import 'services/device_profile.dart';
import 'services/storage.dart';
import 'state/router.dart';
import 'state/ui_prefs.dart';
import 'theme/colors.dart';
import 'widgets/bounded_scroll.dart';
import 'widgets/zoom.dart';

/// Granth Admin — Round 1. The shell, the cards, the folder shelf, the pop-ups and the Photo
/// Highlighter are the user app's own files (Flutter-Granth); only the data behind them and the
/// admin controls are new. One start screen holds both logins (control server + website).
void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _installErrorHandlers();
      // Every init step is guarded: an exception or a hang must never stop runApp.
      try {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]).timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('init: orientation: $e');
      }
      try {
        await Store.I.init().timeout(const Duration(seconds: 6));
      } catch (e) {
        debugPrint('init: store: $e');
      }
      try {
        await DeviceProfile.load().timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('init: profile: $e');
      }
      try {
        AppNav.I.restore();
      } catch (e) {
        debugPrint('init: restore: $e');
      }
      final state = AppState();
      AdminData.I = AdminData(state);
      runApp(
        AppScope(
          state: state,
          child: GranthAdminApp(ready: state.boot()),
        ),
      );
    },
    (error, stack) {
      debugPrint('Uncaught: $error\n$stack');
    },
  );
}

void _installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Platform error: $error\n$stack');
    return true;
  };
  if (kReleaseMode) {
    // A broken widget shows an empty box instead of a grey screen.
    ErrorWidget.builder = (details) => const SizedBox.shrink();
  }
}

class GranthAdminApp extends StatefulWidget {
  const GranthAdminApp({super.key, this.ready, this.splash = true});
  final Future<void>? ready;
  final bool splash;
  @override
  State<GranthAdminApp> createState() => _GranthAdminAppState();
}

class _GranthAdminAppState extends State<GranthAdminApp>
    with WidgetsBindingObserver {
  // Built once: ThemeData is expensive and must not be rebuilt on every state change.
  static final ThemeData _theme = buildAdminTheme();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UiPrefs.I.refresh(start: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      // The shell always handles Back itself (inner screens go up a level; the root asks before
      // exiting). A new MainActivity (after the photo highlighter) starts without that flag.
      SystemNavigator.setFrameworkHandlesBack(true).catchError((Object _) {});
      AppScope.of(context).verifySession();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ग्रंथ प्रबंधन Admin',
    debugShowCheckedModeBanner: false,
    navigatorKey: rootNavKey,
    scrollBehavior: const BoundedScrollBehavior(),
    theme: _theme,
    builder: (context, child) => ValueListenableBuilder<double>(
      valueListenable: UiPrefs.I.textFactor,
      builder: (context, f, zoomed) {
        final phone = MediaQuery.textScalerOf(context);
        final scaler = f == 1.0
            ? phone.clamp(maxScaleFactor: 1.3)
            : TextScaler.linear(phone.scale(100) / 100 * f)
                  .clamp(minScaleFactor: 0.8, maxScaleFactor: 1.3);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: zoomed!,
        );
      },
      child: AppZoom(child: child!),
    ),
    home: widget.splash
        ? AnimatedSplash(ready: widget.ready, child: const AdminGate())
        : const AdminGate(),
  );
}

/// Login ⇄ app. The app opens only when BOTH sessions are valid (website + control server);
/// when one expires only that one is asked again. Pushed routes are popped on logout / expiry.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});
  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  bool? _wasLoggedIn;
  bool? _wasReady;

  @override
  Widget build(BuildContext context) =>
      AppSelector<(bool, bool, bool, String?)>(
        selector: (a) =>
            (a.booting, a.loggedIn, a.panel.loggedIn, a.expiredMessage),
        builder: (context, app, _) => _gate(context, app),
      );

  Widget _gate(BuildContext context, AppState app) {
    final ready = app.loggedIn && app.panel.loggedIn;
    final wnmDropped = _wasLoggedIn == true && !app.loggedIn;
    if (_wasReady == true && !ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        rootNavKey.currentState?.popUntil((r) => r.isFirst);
        if (AdminData.isSet) AdminData.I.reset();
      });
      if (wnmDropped && app.expiredMessage != null) {
        final msg = app.expiredMessage!;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => showToast(msg, error: true),
        );
      }
    }
    if (ready && _wasReady != true && !app.booting) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => AdminData.I.refresh(),
      );
    }
    _wasLoggedIn = app.booting ? null : app.loggedIn;
    _wasReady = app.booting ? null : ready;
    final Widget child;
    if (app.booting) {
      child = const ColoredBox(
        key: ValueKey('boot'),
        color: GColors.cream,
        child: Center(child: CircularProgressIndicator(color: GColors.saffron)),
      );
    } else if (ready) {
      child = const HomeShell(key: ValueKey('home'));
    } else {
      child = const DualLoginScreen(key: ValueKey('login'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
      child: child,
    );
  }
}
