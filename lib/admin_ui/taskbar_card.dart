import 'package:flutter/material.dart';

import '../admin/widgets/form_sheet.dart' show runWrite;
import '../theme/colors.dart';
import '../widgets/common.dart';
import 'admin_data.dart';

/// Round-3: `ui.taskbar` remote flag (CONTRACT Round 19 §19.3). force > user choice > admin default > off. Emits {default: bool} or {force: bool}.
/// Saved to the draft via PUT /settings, applied to users after publish.
class TaskbarCard extends StatefulWidget {
  const TaskbarCard({super.key});
  @override
  State<TaskbarCard> createState() => _TaskbarCardState();
}

class _TaskbarCardState extends State<TaskbarCard> {
  /// user_choice | force_on | force_off
  String? _mode;
  bool _def = false;

  static const _labels = {
    'user_choice': 'यूज़र की मर्ज़ी',
    'force_on': 'सबके लिए चालू',
    'force_off': 'सबके लिए बंद',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var mode = 'user_choice';
    var def = false;
    try {
      final s = await AdminData.I.app.panel.api.raw('GET', '/settings');
      final ui = s['ui'] is Map ? (s['ui'] as Map) : const {};
      final t = ui['taskbar'];
      if (t is bool) {
        def = t;
      } else if (t is Map) {
        if (t['force'] is bool) {
          mode = t['force'] == true ? 'force_on' : 'force_off';
        } else if (t['enabled'] == false) {
          mode = 'force_off';
        } else if (t['default'] is bool) {
          def = t['default'] as bool;
        }
      }
    } catch (_) {}
    if (mounted)
      setState(() {
        _mode = mode;
        _def = def;
      });
  }

  Future<void> _save(String m, bool def) async {
    final pm = _mode, pd = _def;
    setState(() {
      _mode = m;
      _def = def;
    });
    final body = m == 'user_choice'
        ? {'default': def}
        : {'force': m == 'force_on'};
    final ok = await runWrite(
      () => AdminData.I.app.panel.api.raw(
        'PUT',
        '/settings',
        body: {
          'ui': {'taskbar': body},
        },
      ),
      success: 'टास्कबार सेव (ड्राफ्ट) — प्रकाशित करें',
    );
    if (!ok && mounted)
      setState(() {
        _mode = pm;
        _def = pd;
      });
  }

  @override
  Widget build(BuildContext context) => GCard(
    key: const ValueKey('taskbar-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const GIcon('layout-grid', size: 20, color: GColors.maroon),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'टास्कबार (यूज़र ऐप)',
                style: GText.sans(
                  size: 15,
                  weight: FontWeight.w800,
                  color: GColors.maroon,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'प्राथमिकता: फ़ोर्स > यूज़र की पसंद > एडमिन डिफ़ॉल्ट > बंद · प्रकाशित करने पर लागू',
          style: GText.sans(size: 12.5, color: GColors.muted),
        ),
        const SizedBox(height: 10),
        if (_mode == null)
          const LinearProgressIndicator(minHeight: 2, color: GColors.saffron)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _labels.entries)
                ChoiceChip(
                  key: ValueKey('taskbar-${e.key}'),
                  label: Text(e.value),
                  selected: _mode == e.key,
                  selectedColor: GColors.saffron.withValues(alpha: 0.25),
                  onSelected: (_) => _mode == e.key ? null : _save(e.key, _def),
                ),
            ],
          ),
        if (_mode == 'user_choice')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'डिफ़ॉल्ट: चालू (जिसने खुद नहीं बदला उसके लिए)',
                    style: GText.sans(size: 13.5),
                  ),
                ),
                Switch(
                  key: const ValueKey('taskbar-default'),
                  value: _def,
                  activeThumbColor: GColors.saffron,
                  onChanged: (v) => _save('user_choice', v),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
