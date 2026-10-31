import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../services/google_login.dart';
import '../services/granth_api.dart';
import '../services/panel_api.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../widgets/common.dart';
import '../widgets/toast.dart';

/// The one sign-in screen shown at app start: BOTH logins at once.
///
/// * "ऐप एडमिन (कंट्रोल सर्वर)" → the control server (`PanelState.loginAs`, token in secure storage).
/// * "wnm सर्वर (डेटा एडिट)" → the wnm website (`AppState.login`, cookie as before).
///
/// The app opens only when both sessions are valid. If one session expires later, only that
/// section is asked again (the other one shows as connected).
class DualLoginScreen extends StatefulWidget {
  const DualLoginScreen({super.key});
  @override
  State<DualLoginScreen> createState() => _DualLoginScreenState();
}

class _DualLoginScreenState extends State<DualLoginScreen>
    with TickerProviderStateMixin {
  // Always blank: nothing is pre-filled from an earlier login.
  final _panelUser = TextEditingController();
  final _panelPass = TextEditingController();
  final _wnmUser = TextEditingController();
  final _wnmPass = TextEditingController();
  bool _busy = false;
  String? _panelError;
  String? _wnmError;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();
  late final CurvedAnimation _introCurve = CurvedAnimation(
    parent: _intro,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _introCurve.dispose();
    _shake.dispose();
    _intro.dispose();
    _panelUser.dispose();
    _panelPass.dispose();
    _wnmUser.dispose();
    _wnmPass.dispose();
    super.dispose();
  }

  static const _needUser = 'कृपया यूज़रनेम डालें / Please enter username';
  static const _needPass = 'कृपया पासवर्ड डालें / Please enter password';

  String? _validate(TextEditingController u, TextEditingController p) {
    if (u.text.trim().isEmpty) return _needUser;
    if (p.text.trim().isEmpty) return _needPass;
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final app = AppScope.of(context);
    final needPanel = !app.panel.loggedIn;
    final needWnm = !app.loggedIn;
    final pe = needPanel ? _validate(_panelUser, _panelPass) : null;
    final we = needWnm ? _validate(_wnmUser, _wnmPass) : null;
    if (pe != null || we != null) {
      setState(() {
        _panelError = pe;
        _wnmError = we;
      });
      _shake.forward(from: 0);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _panelError = null;
      _wnmError = null;
    });
    // Both logins run together; each one reports its own error.
    final results = await Future.wait([
      if (needPanel) _loginPanel(app) else Future.value(true),
      if (needWnm) _loginWnm(app) else Future.value(true),
    ]);
    if (!mounted) return;
    setState(() => _busy = false);
    if (results.every((ok) => ok)) {
      showToast('स्वागत है / Welcome');
    } else {
      _shake.forward(from: 0);
    }
  }

  /// Google login for the panel (allowlisted emails only). The token is never logged.
  Future<void> _google() async {
    if (_busy) return;
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _panelError = null;
    });
    try {
      final t = await GoogleLogin.idToken();
      if (t != null) {
        await app.panel.loginWithFirebaseToken(t);
        showToast('स्वागत है / Welcome');
      }
    } on PanelApiException catch (e) {
      await GoogleLogin.signOut();
      if (mounted) {
        setState(
          () => _panelError = e.code == 'not_allowed'
              ? 'यह Google अकाउंट एडमिन सूची में नहीं है / Not on the admin allowlist'
              : e.fullMessage,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _panelError = e is GoogleLoginUnavailable
              ? e.message
              : 'Google लॉगिन नहीं हो सका / Google login failed',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The password is only passed to the API call; it is never stored or logged here.
  Future<bool> _loginPanel(AppState app) async {
    try {
      await app.panel.loginAs(_panelUser.text.trim(), _panelPass.text);
      _panelPass.clear();
      return true;
    } on PanelApiException catch (e) {
      if (mounted) setState(() => _panelError = e.fullMessage);
    } catch (_) {
      if (mounted)
        setState(() => _panelError = 'कुछ गलत हुआ / Something went wrong');
    }
    return false;
  }

  Future<bool> _loginWnm(AppState app) async {
    try {
      final ok = await app.login(_wnmUser.text.trim(), _wnmPass.text.trim());
      if (ok) {
        _wnmPass.clear();
        return true;
      }
      if (mounted)
        setState(() => _wnmError = 'गलत लॉगिन विवरण / Incorrect login details');
    } on ApiException catch (e) {
      if (mounted) setState(() => _wnmError = e.message);
    } catch (_) {
      if (mounted)
        setState(() => _wnmError = 'कुछ गलत हुआ / Something went wrong');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AppSelector<(bool, bool, String?, String?)>(
      selector: (a) => (
        a.loggedIn,
        a.panel.loggedIn,
        a.expiredMessage,
        a.panel.expiredMessage,
      ),
      builder: (context, app, _) => _page(context, app),
    );
  }

  Widget _page(BuildContext context, AppState app) {
    final p = Palette.of(context);
    final panelOk = app.panel.loggedIn, wnmOk = app.loggedIn;
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: AnimatedBuilder(
                animation: Listenable.merge([_shake, _intro]),
                builder: (_, child) {
                  final dx =
                      math.sin(_shake.value * math.pi * 6) *
                      12 *
                      (1 - _shake.value);
                  return Opacity(
                    opacity: _intro.value.clamp(0, 1),
                    child: Transform.translate(
                      offset: Offset(dx, (1 - _introCurve.value) * 30),
                      child: child,
                    ),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.saffron, AppColors.maroon],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'ग्रं',
                          style: TextStyle(
                            fontFamily: kSerif,
                            fontSize: 30,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'ग्रंथ प्रबंधन',
                        style: TextStyle(
                          fontFamily: kSerif,
                          fontSize: 26,
                          color: p.text,
                          height: 1.3,
                        ),
                      ),
                      Text(
                        'Admin Panel',
                        style: TextStyle(
                          color: p.subtext,
                          fontSize: 15,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        key: const ValueKey('section-panel'),
                        title: 'ऐप एडमिन (कंट्रोल सर्वर)',
                        icon: CupertinoIcons.slider_horizontal_3,
                        connected: panelOk,
                        user: _panelUser,
                        pass: _panelPass,
                        error: _panelError ?? app.panel.expiredMessage,
                        onSubmit: _submit,
                        action: false,
                      ),
                      if (!panelOk)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextButton.icon(
                            key: const ValueKey('google-login'),
                            onPressed: _busy ? null : _google,
                            icon: const Icon(Icons.account_circle_outlined),
                            label: const Text('Google से लॉगिन'),
                          ),
                        ),
                      const SizedBox(height: 14),
                      _Section(
                        key: const ValueKey('section-wnm'),
                        title: 'wnm सर्वर (डेटा एडिट)',
                        icon: CupertinoIcons.cloud,
                        connected: wnmOk,
                        user: _wnmUser,
                        pass: _wnmPass,
                        error: _wnmError ?? app.expiredMessage,
                        onSubmit: _submit,
                        action: true,
                      ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: 'लॉगिन / Login',
                        icon: CupertinoIcons.arrow_right_circle,
                        busy: _busy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'granth.wnmsolutions.com',
                        style: TextStyle(color: p.subtext, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One login card: title, username, password (with eye toggle) and its own error line.
/// When [connected] it collapses to a "connected" row.
class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.title,
    required this.icon,
    required this.connected,
    required this.user,
    required this.pass,
    required this.error,
    required this.onSubmit,
    required this.action,
  });
  final String title;
  final IconData icon;
  final bool connected;
  final TextEditingController user, pass;
  final String? error;
  final VoidCallback onSubmit;

  /// The last field submits (keyboard "go") only in the last section.
  final bool action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final head = Row(
      children: [
        Icon(icon, color: AppColors.saffron),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: p.text,
            ),
          ),
        ),
        if (connected)
          const Icon(
            CupertinoIcons.checkmark_circle_fill,
            color: AppColors.green,
            size: 22,
          ),
      ],
    );
    if (connected) {
      return Glass(
        blur: 0,
        radius: 22,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head,
            const SizedBox(height: 4),
            Text(
              'जुड़ गया / Connected',
              style: TextStyle(color: p.subtext, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return Glass(
      blur: 0,
      radius: 28,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head,
            const SizedBox(height: 14),
            GlassField(
              label: 'यूज़रनेम / Username',
              controller: user,
              prefix: CupertinoIcons.person,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
            ),
            GlassField(
              label: 'पासवर्ड / Password',
              controller: pass,
              obscure: true,
              prefix: CupertinoIcons.lock,
              textInputAction: action
                  ? TextInputAction.go
                  : TextInputAction.next,
              onSubmitted: action ? (_) => onSubmit() : null,
              autofillHints: const [AutofillHints.password],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              child: error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            CupertinoIcons.exclamationmark_circle,
                            color: AppColors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              error!,
                              style: const TextStyle(
                                color: AppColors.red,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
