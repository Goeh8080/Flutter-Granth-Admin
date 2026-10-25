import 'package:flutter/material.dart';

import '../admin/screens/panel/panel_widgets.dart' show showPublishSheet;
import '../admin/widgets/form_sheet.dart' show runWrite;
import '../admin/widgets/toast.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/overlays.dart';
import 'admin_data.dart';
import 'admin_kit.dart';
import 'admin_widgets.dart';

/// The wire map for a pinned/normal announcement (CONTRACT §4.2 + the existing fields).
/// A new `id` is sent when the text changes or the card is switched on again.
Map<String, Object?> announcementBody({
  required String text,
  required String level,
  required bool pinned,
  required String? expiresAt,
  String? newId,
}) => {
  'enabled': true,
  'text': text.trim(),
  'level': level,
  'pinned': pinned,
  'expires_at': expiresAt,
  'id': ?newId,
};

/// The map that removes the announcement (card disappears for readers after publish).
Map<String, Object?> announcementRemoval() => const {
  'enabled': false,
  'text': '',
  'pinned': false,
  'expires_at': null,
};

/// `2026-12-31T18:29:59Z` → `2026-12-31` in IST.
String announcementExpiryLabel(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso.length >= 10 ? iso.substring(0, 10) : iso;
  return d
      .toUtc()
      .add(const Duration(hours: 5, minutes: 30))
      .toIso8601String()
      .substring(0, 10);
}

Future<void> showAnnouncementEditor(BuildContext context) =>
    showPop<void>(context, (_) => const _AnnouncementSheet());

class _AnnouncementSheet extends StatefulWidget {
  const _AnnouncementSheet();
  @override
  State<_AnnouncementSheet> createState() => _AnnouncementSheetState();
}

class _AnnouncementSheetState extends State<_AnnouncementSheet> {
  late final _a = AdminData.I.settings?.announcement;
  late final _text = TextEditingController(text: _a?.text ?? '');
  late String _level = const ['info', 'warn', 'critical'].contains(_a?.level)
      ? _a!.level
      : 'info';
  late bool _pinned = _a == null ? true : (_a.enabled ? _a.pinned : true);
  late String? _expires = _a?.expiresAt;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
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
      // end of the chosen day in IST (23:59:59 IST = 18:29:59 UTC)
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

  Future<void> _publish() async {
    final text = _text.text.trim();
    if (text.isEmpty)
      return showToast('घोषणा का संदेश लिखें / Enter the text', error: true);
    if (text.length > 280)
      return showToast('घोषणा 280 अक्षर तक / max 280 chars', error: true);
    final exp = _expires == null ? null : DateTime.tryParse(_expires!);
    if (exp != null && !exp.isAfter(DateTime.now().toUtc()))
      return showToast(
        'समाप्ति का समय बीत चुका है / Expiry is in the past',
        error: true,
      );
    final prev = _a;
    final changed = prev == null || text != prev.text || !prev.enabled;
    setState(() => _busy = true);
    final ok = await runWrite(
      () => AdminData.I.saveSettings(
        announcement: announcementBody(
          text: text,
          level: _level,
          pinned: _pinned,
          expiresAt: _expires,
          newId: changed
              ? 'a${DateTime.now().millisecondsSinceEpoch ~/ 1000}'
              : null,
        ),
      ),
      success: 'घोषणा ड्राफ्ट में सहेजी / Saved to draft',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      final nav = Navigator.of(context);
      nav.pop();
      await showPublishSheet(nav.context);
      await AdminData.I.refreshControl();
    }
  }

  Future<void> _remove() async {
    final yes = await confirmPopTitled(
      context,
      title: 'घोषणा हटाएँ?',
      message: 'प्रकाशित करने के बाद पाठकों के ऐप से यह कार्ड हट जाएगा।',
      confirm: 'हटाएँ',
      destructive: true,
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    final ok = await runWrite(
      () => AdminData.I.saveSettings(announcement: announcementRemoval()),
      success: 'घोषणा हटाई (ड्राफ्ट) / Removed (draft)',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      final nav = Navigator.of(context);
      nav.pop();
      await showPublishSheet(nav.context);
      await AdminData.I.refreshControl();
    }
  }

  static String _label(String l) => switch (l) {
    'info' => 'सूचना',
    'warn' => 'चेतावनी',
    _ => 'ज़रूरी',
  };

  @override
  Widget build(BuildContext context) {
    final exists = _a?.enabled ?? false;
    return SheetCard(
      children: [
        SheetHead(
          title: 'पिन की हुई घोषणा',
          onBack: () => Navigator.pop(context),
        ),
        AdminField(
          controller: _text,
          label: 'संदेश',
          maxLines: 4,
          hint: 'जैसे: नया अपडेट आ गया है',
          counter: '${_text.text.length}/280',
          onChanged: (_) => setState(() {}),
        ),
        Text(
          'स्तर',
          style: GText.sans(
            size: 13,
            weight: FontWeight.w700,
            color: GColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in const ['info', 'warn', 'critical'])
              Pill(
                label: _label(l),
                tone: l == _level ? PillTone.maroon : PillTone.plain,
                onTap: () => setState(() => _level = l),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'पिन करें',
                    style: GText.sans(
                      size: 15,
                      weight: FontWeight.w800,
                      color: GColors.maroon,
                    ),
                  ),
                  Text(
                    _pinned
                        ? 'पाठक इसे हटा नहीं सकते'
                        : 'पाठक इसे बंद कर सकते हैं',
                    style: GText.sans(size: 12.5, color: GColors.muted),
                  ),
                ],
              ),
            ),
            AdminSwitch(
              key: const ValueKey('pin-switch'),
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                _expires == null
                    ? 'समाप्ति: कभी नहीं (हटाने तक)'
                    : 'समाप्ति: ${announcementExpiryLabel(_expires!)}',
                style: GText.sans(size: 13.5, color: GColors.text),
              ),
            ),
            Pill(icon: 'history', label: 'तारीख', onTap: _pickExpiry),
            if (_expires != null) ...[
              const SizedBox(width: 8),
              Pill(
                label: 'कभी नहीं',
                onTap: () => setState(() => _expires = null),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        SheetButton(
          label: 'ड्राफ्ट में सहेजें और प्रकाशित करें',
          primary: true,
          enabled: !_busy,
          onTap: _publish,
        ),
        if (exists) ...[
          const SizedBox(height: 10),
          SheetButton(label: 'घोषणा हटाएँ', enabled: !_busy, onTap: _remove),
        ],
      ],
    );
  }
}
