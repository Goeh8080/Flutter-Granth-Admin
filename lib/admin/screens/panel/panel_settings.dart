import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/panel_config.dart';
import '../../models/panel_models.dart';
import '../../services/panel_api.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/motion.dart';
import '../../widgets/toast.dart';
import 'panel_widgets.dart';

/// सेटिंग्स: flags, announcement, AI endpoint (saved to the draft, then published), password, sessions, audit.
class PanelSettingsScreen extends StatelessWidget {
  const PanelSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PanelPage<PanelSettings>(
      title: 'सेटिंग्स / Settings',
      previousPageTitle: 'कंट्रोल',
      load: (api) => api.settings(),
      builder: (context, s, reload) => [
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          child: SliverList(
            delegate: SliverChildListDelegate([
              const DraftBanner(),
              _SettingsForm(key: ValueKey(identityHashCode(s)), settings: s),
              const SizedBox(height: 18),
              MenuRow(
                CupertinoIcons.lock_rotation,
                'पैनल पासवर्ड बदलें',
                () =>
                    showGlassSheet<void>(context, (_) => const _PasswordForm()),
              ),
              MenuRow(
                CupertinoIcons.device_phone_portrait,
                'लॉगिन सेशन',
                () => pushPanel(context, const PanelSessionsScreen()),
              ),
              MenuRow(
                CupertinoIcons.list_bullet,
                'ऑडिट लॉग',
                () => pushPanel(context, const PanelAuditScreen()),
              ),
              const SizedBox(height: 8),
              Text(
                'सर्वर: ${s.base.isEmpty ? '-' : s.base} • लाइव वर्ज़न v${s.publishedVersion}${s.signed ? ' • हस्ताक्षरित' : ''}',
                style: TextStyle(
                  color: Palette.of(context).subtext,
                  fontSize: 11.5,
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({super.key, required this.settings});
  final PanelSettings settings;
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late bool _ai = widget.settings.aiEnabled;
  late bool _analytics = widget.settings.analyticsEnabled;
  late double _sample = widget.settings.analyticsSample.clamp(0.0, 1.0);
  late bool _annOn = widget.settings.announcement.enabled;
  late String _level =
      widget.settings.levels.contains(widget.settings.announcement.level)
      ? widget.settings.announcement.level
      : 'info';
  late String? _expires = widget.settings.announcement.expiresAt;
  late final _text = TextEditingController(
    text: widget.settings.announcement.text,
  );
  late final _endpoint = TextEditingController(
    text: widget.settings.aiEndpoint,
  );
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  bool get _dirty {
    final s = widget.settings;
    return _ai != s.aiEnabled ||
        _analytics != s.analyticsEnabled ||
        (_sample - s.analyticsSample).abs() > 0.0001 ||
        _annOn != s.announcement.enabled ||
        _level != s.announcement.level ||
        _expires != s.announcement.expiresAt ||
        _text.text != s.announcement.text ||
        _endpoint.text.trim() != s.aiEndpoint;
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (d != null) {
      // end of the chosen day in IST (23:59:59 IST = 18:29:59 UTC), not 05:29 IST of the next day
      setState(
        () => _expires = DateTime.utc(
          d.year,
          d.month,
          d.day,
          18,
          29,
          59,
        ).toIso8601String().replaceFirst(RegExp(r'\.\d+'), ''),
      );
    }
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    final endpoint = _endpoint.text.trim();
    if (_annOn && text.isEmpty) {
      showToast(
        'घोषणा का संदेश लिखें / Enter the announcement text',
        error: true,
      );
      return;
    }
    if (text.length > 280) {
      showToast('घोषणा 280 अक्षर तक / max 280 chars', error: true);
      return;
    }
    if (endpoint.isNotEmpty &&
        (!endpoint.startsWith('https://') || endpoint.length > 200)) {
      showToast(
        'AI endpoint https:// से शुरू हो, अधिकतम 200 अक्षर',
        error: true,
      );
      return;
    }
    final s = widget.settings;
    final exp = _expires == null ? null : DateTime.tryParse(_expires!);
    if (_annOn && exp != null && !exp.isAfter(DateTime.now().toUtc())) {
      showToast(
        'समाप्ति का समय बीत चुका है / Expiry is in the past',
        error: true,
      );
      return;
    }
    final panel = panelOf(context);
    setState(() => _busy = true);
    try {
      // a changed message, or switching the banner on again, needs a NEW id: phones that dismissed the old banner never show the same id again
      final textChanged =
          text != s.announcement.text || (_annOn && !s.announcement.enabled);
      await panel.api.putSettings(
        aiEnabled: _ai,
        analyticsEnabled: _analytics,
        analyticsSample: double.parse(_sample.toStringAsFixed(2)),
        announcement: {
          'enabled': _annOn,
          'text': text,
          'level': _level,
          // a new id re-shows the banner to people who dismissed the old one
          if (textChanged)
            'id': 'a${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          // null = remove the expiry (omitting the key would keep the old one on the server)
          'expires_at': _expires,
        },
        aiEndpoint: endpoint,
      );
      panel.bump();
      if (!mounted) return;
      setState(() => _busy = false);
      showToast('सेटिंग्स ड्राफ्ट में सहेजी / Saved to draft');
      await showPublishSheet(context);
    } on PanelApiException catch (e) {
      showError(e);
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _switch(String label, String sub, bool v, ValueChanged<bool> on) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: p.text, fontSize: 15)),
                Text(sub, style: TextStyle(color: p.subtext, fontSize: 12)),
              ],
            ),
          ),
          CupertinoSwitch(
            value: v,
            activeTrackColor: AppColors.green,
            onChanged: on,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final levels = widget.settings.levels.isEmpty
        ? const ['info', 'warn', 'critical']
        : widget.settings.levels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'फ़्लैग्स / Flags',
          child: Column(
            children: [
              _switch(
                'AI सहायक',
                'यूज़र ऐप में AI चालू/बंद',
                _ai,
                (v) => setState(() => _ai = v),
              ),
              _switch(
                'एनालिटिक्स',
                'गुमनाम उपयोग-आँकड़े भेजना',
                _analytics,
                (v) => setState(() => _analytics = v),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'एनालिटिक्स सैंपल: ${(_sample * 100).round()}% इंस्टॉल',
                  style: TextStyle(color: p.text, fontSize: 14),
                ),
              ),
              CupertinoSlider(
                value: _sample,
                divisions: 20,
                activeColor: AppColors.saffron,
                onChanged: _analytics
                    ? (v) => setState(() => _sample = v)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'घोषणा / Announcement',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _switch(
                'घोषणा दिखाएँ',
                'ऐप के ऊपर बैनर',
                _annOn,
                (v) => setState(() => _annOn = v),
              ),
              const SizedBox(height: 6),
              GlassField(
                label: 'संदेश (≤280)',
                controller: _text,
                maxLines: 3,
                placeholder: 'जैसे: नया अपडेट आ गया है',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final l in levels)
                    FilterChipX(
                      _levelLabel(l),
                      selected: l == _level,
                      onTap: () => setState(() => _level = l),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _expires == null
                          ? 'समाप्ति: कभी नहीं'
                          : 'समाप्ति: ${_expiryLabel(_expires!)}',
                      style: TextStyle(color: p.subtext, fontSize: 13),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: _pickExpiry,
                    child: const Text('तारीख चुनें'),
                  ),
                  if (_expires != null)
                    CupertinoButton(
                      padding: const EdgeInsets.only(left: 12),
                      minimumSize: Size.zero,
                      onPressed: () => setState(() => _expires = null),
                      child: const Text(
                        'हटाएँ',
                        style: TextStyle(color: AppColors.red),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'AI endpoint',
          child: GlassField(
            label: 'https:// पता (खाली = बंद)',
            controller: _endpoint,
            placeholder: 'https://…',
            keyboardType: TextInputType.url,
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          label: 'ड्राफ्ट में सहेजें / प्रीव्यू',
          icon: CupertinoIcons.eye,
          busy: _busy,
          onPressed: _busy
              ? null
              : (_dirty
                    ? _save
                    : () => showToast('कोई बदलाव नहीं / No changes')),
        ),
      ],
    );
  }

  /// `2026-12-31T18:29:59Z` → `2026-12-31` in IST (the panel and the app both talk IST to the owner).
  static String _expiryLabel(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso.length >= 10 ? iso.substring(0, 10) : iso;
    return d
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30))
        .toIso8601String()
        .substring(0, 10);
  }

  static String _levelLabel(String l) => switch (l) {
    'info' => 'सूचना',
    'warn' => 'चेतावनी',
    'critical' => 'ज़रूरी',
    _ => l,
  };
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm();
  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_cur.text.isEmpty)
      return showToast('मौजूदा पासवर्ड डालें', error: true);
    if (_new.text.length < 10 || _new.text.length > 256)
      return showToast(
        'नया पासवर्ड 10 से 256 अक्षर का हो / 10–256 chars',
        error: true,
      );
    if (_new.text != _again.text)
      return showToast('दोनों नए पासवर्ड मेल नहीं खाते', error: true);
    setState(() => _busy = true);
    try {
      await apiOf(context).changePassword(_cur.text, _new.text);
      if (!mounted) return;
      showToast('पासवर्ड बदल गया / Password changed');
      Navigator.pop(context);
    } on PanelApiException catch (e) {
      showError(e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: 'पासवर्ड बदलें',
      busy: _busy,
      onSave: _save,
      children: [
        GlassField(
          label: 'मौजूदा पासवर्ड',
          controller: _cur,
          obscure: true,
          prefix: CupertinoIcons.lock,
        ),
        GlassField(
          label: 'नया पासवर्ड (कम से कम 10 अक्षर)',
          controller: _new,
          obscure: true,
          prefix: CupertinoIcons.lock_shield,
        ),
        GlassField(
          label: 'नया पासवर्ड दोबारा',
          controller: _again,
          obscure: true,
          prefix: CupertinoIcons.lock_shield,
        ),
      ],
    );
  }
}

/// लॉगिन सेशन: this device and others; revoke one or all others.
class PanelSessionsScreen extends StatelessWidget {
  const PanelSessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PanelPage<List<PanelSession>>(
      title: 'लॉगिन सेशन',
      previousPageTitle: 'सेटिंग्स',
      load: (api) => api.sessions(),
      builder: (context, list, reload) => [
        PadSliver(
          child: SliverList(
            delegate: SliverChildListDelegate([
              for (final s in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Glass(
                    radius: 16,
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    child: Row(
                      children: [
                        Icon(
                          s.kind == 'app'
                              ? CupertinoIcons.device_phone_portrait
                              : CupertinoIcons.globe,
                          color: AppColors.saffron,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${s.client.isEmpty ? s.kind : s.client}${s.current ? ' (यह फ़ोन)' : ''}',
                                style: TextStyle(color: p.text, fontSize: 14.5),
                              ),
                              Text(
                                'आख़िरी: ${shortTs(s.lastSeen)}',
                                style: TextStyle(
                                  color: p.subtext,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!s.current)
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            onPressed: () async {
                              try {
                                await apiOf(context).revokeSession(s.sid);
                                reload();
                              } on PanelApiException catch (e) {
                                showError(e);
                              }
                            },
                            child: const Text(
                              'हटाएँ',
                              style: TextStyle(color: AppColors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (list.length > 1)
                CupertinoButton(
                  onPressed: () async {
                    if (!await confirmDialog(
                      context,
                      title: 'बाकी सब सेशन हटाएँ?',
                      message: 'दूसरे सभी डिवाइस लॉग-आउट हो जाएँगे।',
                      confirm: 'हटाएँ',
                    ))
                      return;
                    if (!context.mounted) return;
                    try {
                      await apiOf(context).revokeOtherSessions();
                      reload();
                    } on PanelApiException catch (e) {
                      showError(e);
                    }
                  },
                  child: const Text(
                    'बाकी सब से लॉग-आउट',
                    style: TextStyle(color: AppColors.red),
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// ऑडिट लॉग: who changed what (newest first).
class PanelAuditScreen extends StatelessWidget {
  const PanelAuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PanelPage<List<AuditItem>>(
      title: 'ऑडिट लॉग',
      previousPageTitle: 'सेटिंग्स',
      load: (api) => api.audit(limit: 100),
      builder: (context, items, reload) => [
        PadSliver(
          child: items.isEmpty
              ? const SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageView(
                    icon: CupertinoIcons.list_bullet,
                    title: 'अभी कुछ दर्ज नहीं',
                  ),
                )
              : SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final a = items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Glass(
                        radius: 14,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${a.action} • ${a.actor}',
                              style: TextStyle(
                                color: p.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              shortTs(a.ts),
                              style: TextStyle(
                                color: p.subtext,
                                fontSize: 11.5,
                              ),
                            ),
                            if (a.detail.isNotEmpty &&
                                a.detail != '{}' &&
                                a.detail != 'null')
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  a.detail,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.subtext,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Change the control-server address (https only). Empty = built-in default.
Future<void> showPanelBaseSheet(BuildContext context) =>
    showGlassSheet<void>(context, (_) => const _BaseForm());

class _BaseForm extends StatefulWidget {
  const _BaseForm();
  @override
  State<_BaseForm> createState() => _BaseFormState();
}

class _BaseFormState extends State<_BaseForm> {
  late final _c = TextEditingController(
    text: apiOf(context).baseUrl == kPanelDefaultBase
        ? ''
        : apiOf(context).baseUrl,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final panel = panelOf(context);
    final ok = await panel.setBase(_c.text);
    if (!mounted) return;
    if (!ok)
      return showToast(
        'सही https:// पता डालें / enter a valid https:// address',
        error: true,
      );
    showToast('सर्वर पता सहेजा — दोबारा लॉगिन करें');
    if (panel.loggedIn) await panel.logout();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: 'कंट्रोल सर्वर पता',
    onSave: _save,
    children: [
      GlassField(
        label: 'https:// पता (खाली = डिफ़ॉल्ट)',
        controller: _c,
        placeholder: kPanelDefaultBase,
        keyboardType: TextInputType.url,
      ),
      Text(
        'कस्टम डोमेन आने पर यहाँ बदलें। बदलने पर कंट्रोल से लॉगआउट होगा।',
        style: TextStyle(color: Palette.of(context).subtext, fontSize: 12.5),
      ),
    ],
  );
}
