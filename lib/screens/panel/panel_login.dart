import 'package:flutter/cupertino.dart';

import '../../core/app_state.dart';
import '../../services/panel_api.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/toast.dart';
import 'panel_widgets.dart';

/// Login card for the control server (its own username/password, separate from the website).
class PanelLoginCard extends StatefulWidget {
  const PanelLoginCard({super.key, this.onDone});
  final VoidCallback? onDone;
  @override
  State<PanelLoginCard> createState() => _PanelLoginCardState();
}

class _PanelLoginCardState extends State<PanelLoginCard> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final pw = _pass.text;
    if (_user.text.trim().isEmpty) {
      setState(() => _error = 'कृपया यूज़रनेम डालें / Please enter username');
      return;
    }
    if (pw.trim().isEmpty) {
      setState(() => _error = 'कृपया पासवर्ड डालें / Please enter password');
      return;
    }
    final panel = panelOf(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The password is only passed to the API call; it is never stored or logged.
      await panel.loginAs(_user.text.trim(), pw);
      _pass.clear();
      showToast('कंट्रोल पैनल से जुड़ गए / Connected');
      widget.onDone?.call();
    } on PanelApiException catch (e) {
      if (mounted) setState(() => _error = e.fullMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Glass(
      blur: 0,
      radius: 28,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(CupertinoIcons.slider_horizontal_3, color: AppColors.saffron),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ऐप कंट्रोल लॉगिन',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'यह वेबसाइट वाले लॉगिन से अलग है। इसी से यूज़र ऐप के फ़ोल्डर, छिपाना, प्रकाशन और आँकड़े संभलते हैं।',
              style: TextStyle(color: p.subtext, fontSize: 13),
            ),
            const SizedBox(height: 16),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_circle, color: AppColors.red, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
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
    );
  }
}

/// Full-page version (pushed from the website login or from the placeholder tabs).
class PanelLoginScreen extends StatelessWidget {
  const PanelLoginScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'ऐप कंट्रोल',
      previousPageTitle: 'वापस',
      slivers: [
        PadSliver(
          child: SliverToBoxAdapter(child: PanelLoginCard(onDone: () => Navigator.of(context).maybePop())),
        ),
      ],
    );
  }
}

/// The control tab when not connected.
class PanelLoggedOutView extends StatelessWidget {
  const PanelLoggedOutView({super.key, this.bottomInset = 0});
  final double bottomInset;
  @override
  Widget build(BuildContext context) {
    return AppSelector<String?>(
      selector: (a) => a.panel.expiredMessage,
      builder: (context, app, _) => _page(context, app),
    );
  }

  Widget _page(BuildContext context, AppState app) {
    final p = Palette.of(context);
    return GlassPage(
      title: 'ऐप कंट्रोल',
      bottomInset: bottomInset,
      slivers: [
        PadSliver(
          child: SliverList(
            delegate: SliverChildListDelegate([
              if (app.panel.expiredMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(app.panel.expiredMessage!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'यूज़र ऐप को कंट्रोल करें और उसके आँकड़े देखें।',
                  style: TextStyle(color: p.subtext, fontSize: 14),
                ),
              ),
              const PanelLoginCard(),
            ]),
          ),
        ),
      ],
    );
  }
}
