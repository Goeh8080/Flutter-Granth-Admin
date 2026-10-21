import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../services/granth_api.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../widgets/common.dart';
import '../widgets/toast.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();

  @override
  void initState() {
    super.initState();
    _user.text = AppScope.of(context).username;
  }

  @override
  void dispose() {
    _shake.dispose();
    _intro.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final u = _user.text.trim(), pw = _pass.text.trim();
    if (u.isEmpty || pw.isEmpty) {
      setState(
        () => _error = u.isEmpty
            ? 'कृपया यूज़रनेम डालें / Please enter username'
            : 'कृपया पासवर्ड डालें / Please enter password',
      );
      _shake.forward(from: 0);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await AppScope.of(context).login(u, pw);
      if (!ok && mounted) {
        setState(() => _error = 'गलत लॉगिन विवरण / Incorrect login details');
        _shake.forward(from: 0);
      } else if (ok) {
        showToast('स्वागत है / Welcome, $u');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      _shake.forward(from: 0);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final intro = CurvedAnimation(parent: _intro, curve: const SpringCurve(damping: 0.8));
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AnimatedBuilder(
                animation: Listenable.merge([_shake, _intro]),
                builder: (_, child) {
                  final dx = math.sin(_shake.value * math.pi * 6) * 12 * (1 - _shake.value);
                  return Opacity(
                    opacity: _intro.value.clamp(0, 1),
                    child: Transform.translate(offset: Offset(dx, (1 - intro.value) * 40), child: child),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.saffron, AppColors.maroon],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.saffron.withValues(alpha: 0.45),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'ग्रं',
                          style: TextStyle(fontFamily: kSerif, fontSize: 44, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'ग्रंथ प्रबंधन',
                        style: TextStyle(fontFamily: kSerif, fontSize: 32, color: p.text, height: 1.3),
                      ),
                      Text('Admin Panel', style: TextStyle(color: p.subtext, fontSize: 15, letterSpacing: 1.2)),
                      const SizedBox(height: 28),
                      Glass(
                        blur: 24,
                        radius: 28,
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                        child: AutofillGroup(
                          child: Column(
                            children: [
                              GlassField(
                                label: 'यूज़रनेम / Username',
                                controller: _user,
                                prefix: CupertinoIcons.person,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                              ),
                              GlassField(
                                label: 'पासवर्ड / Password',
                                controller: _pass,
                                obscure: true,
                                prefix: CupertinoIcons.lock,
                                textInputAction: TextInputAction.go,
                                onSubmitted: (_) => _login(),
                                autofillHints: const [AutofillHints.password],
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                child: _error == null
                                    ? const SizedBox(width: double.infinity)
                                    : Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              CupertinoIcons.exclamationmark_circle,
                                              color: AppColors.red,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                _error!,
                                                style: const TextStyle(color: AppColors.red, fontSize: 13),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                              PrimaryButton(
                                label: 'लॉगिन / Login',
                                icon: CupertinoIcons.arrow_right_circle,
                                busy: _busy,
                                onPressed: _login,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('granth.wnmsolutions.com', style: TextStyle(color: p.subtext, fontSize: 12)),
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
