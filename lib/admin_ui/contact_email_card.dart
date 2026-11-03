import 'package:flutter/material.dart';

import '../admin/widgets/toast.dart';
import '../services/remote_config.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import 'admin_data.dart';

/// CONTRACT §23 `contact.email`: the support address shown on the legal / about pages of both apps.
/// Save = PUT /settings {contact:{email}} (draft) + POST /publish — live without an app rebuild.
class ContactEmailCard extends StatefulWidget {
  const ContactEmailCard({super.key});
  @override
  State<ContactEmailCard> createState() => _ContactEmailCardState();
}

class _ContactEmailCardState extends State<ContactEmailCard> {
  final _ctl = TextEditingController();
  String? _published;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await AdminData.I.app.panel.api.raw('GET', '/settings');
      final c = s['contact'] is Map ? s['contact'] as Map : const {};
      final p = s['published_contact'] is Map ? s['published_contact'] as Map : const {};
      if (!mounted) return;
      setState(() {
        _ctl.text = (c['email'] as String?) ?? '';
        _published = (p['email'] as String?) ?? '';
      });
    } catch (_) {
      if (mounted) setState(() => _published = '');
    }
  }

  void _snack(String msg, {bool error = false}) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return showToast(msg, error: error);
    m.showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _save() async {
    final v = _ctl.text.trim();
    if (v.isNotEmpty && !isValidEmail(v)) {
      setState(() => _err = 'मान्य ईमेल लिखें / Enter a valid email');
      return;
    }
    setState(() {
      _err = null;
      _busy = true;
    });
    try {
      final api = AdminData.I.app.panel.api;
      await api.raw('PUT', '/settings', body: {
        'contact': {'email': v},
      });
      await api.publish(note: 'contact.email', allowEmpty: true);
      if (!mounted) return;
      setState(() => _published = v);
      _snack(v.isEmpty ? 'संपर्क ईमेल हटाया और प्रकाशित / Contact email cleared' : 'संपर्क ईमेल प्रकाशित / Contact email published');
    } catch (e) {
      if (!mounted) return;
      final msg = e is Exception ? e.toString() : 'त्रुटि';
      _snack('सेव नहीं हुआ / Save failed: $msg', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => GCard(
    key: const ValueKey('contact-email-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const GIcon('send', size: 20, color: GColors.maroon),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'संपर्क ईमेल / Contact Email',
                style: GText.sans(size: 15, weight: FontWeight.w800, color: GColors.maroon),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'नीतियाँ / About पेज पर दिखता है · सेव = तुरंत प्रकाशित · लाइव: ${_published == null ? '…' : (_published!.isEmpty ? '—' : _published)}',
          style: GText.sans(size: 12.5, color: GColors.muted),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('contact-email-field'),
          controller: _ctl,
          enabled: _published != null && !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          maxLength: 254,
          decoration: InputDecoration(
            hintText: 'support@example.com',
            errorText: _err,
            counterText: '',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey('contact-email-save'),
            onPressed: _busy || _published == null ? null : _save,
            child: Text(_busy ? 'सेव हो रहा…' : 'सेव और प्रकाशित करें'),
          ),
        ),
      ],
    ),
  );
}
