import 'package:flutter/material.dart';

import '../admin/widgets/form_sheet.dart' show runWrite;
import '../theme/colors.dart';
import '../widgets/common.dart';
import 'admin_actions.dart' show AdminPill;
import 'admin_data.dart';

/// Round-4: per-page "User Layout" for the user app — `ui.grid_pages[page]` (CONTRACT §19.5).
/// Page ids match the user app's `kGridPages`: granths, shelves, pramans, topics, gallery, dashboard.
/// Writes a bare `N` (admin default, user choice still wins) or `{force: N}` into the draft via
/// PUT /settings, exactly like the `ui.taskbar` card; users get it after publish.
class GridLayoutButton extends StatelessWidget {
  const GridLayoutButton({super.key, required this.page});
  final String page;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ValueKey('grid-layout-$page'),
    child: AdminPill(
      label: 'यूज़र लेआउट',
      icon: 'layout-grid',
      fontSize: 13,
      height: 38,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _GridLayoutSheet(page: page),
      ),
    ),
  );
}

class _GridLayoutSheet extends StatefulWidget {
  const _GridLayoutSheet({required this.page});
  final String page;
  @override
  State<_GridLayoutSheet> createState() => _GridLayoutSheetState();
}

class _GridLayoutSheetState extends State<_GridLayoutSheet> {
  bool _loading = true, _saving = false;
  int? _cols; // null = not set (falls back to ui.grid)
  bool _force = false;

  static const _pageNames = {
    'granths': 'ग्रंथ',
    'shelves': 'शेल्फ़',
    'pramans': 'प्रमाण',
    'topics': 'टॉपिक',
    'gallery': 'गैलरी',
    'dashboard': 'डैशबोर्ड',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await AdminData.I.app.panel.api.raw('GET', '/settings');
      final ui = s['ui'] is Map ? (s['ui'] as Map) : const {};
      final gp = ui['grid_pages'] is Map ? (ui['grid_pages'] as Map) : const {};
      final v = gp[widget.page];
      if (v is num) {
        _cols = v.toInt();
      } else if (v is Map) {
        if (v['force'] is num) {
          _cols = (v['force'] as num).toInt();
          _force = true;
        } else if (v['default'] is num) {
          _cols = (v['default'] as num).toInt();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(int? cols, bool force) async {
    final pc = _cols, pf = _force;
    setState(() {
      _cols = cols;
      _force = cols != null && force;
      _saving = true;
    });
    final Object? value = cols == null
        ? null
        : (force ? {'force': cols} : cols);
    final ok = await runWrite(
      () => AdminData.I.app.panel.api.raw(
        'PUT',
        '/settings',
        body: {
          'ui': {
            'grid_pages': {widget.page: value},
          },
        },
      ),
      success: 'लेआउट सेव (ड्राफ्ट) — प्रकाशित करें',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) {
        _cols = pc;
        _force = pf;
      }
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GIcon('layout-grid', size: 20, color: GColors.maroon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'यूज़र लेआउट · ${_pageNames[widget.page] ?? widget.page}',
                  style: GText.sans(
                    size: 16,
                    weight: FontWeight.w800,
                    color: GColors.maroon,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'यूज़र ऐप में इस पेज पर कितने कॉलम दिखें। प्रकाशित करने पर लागू।',
            style: GText.sans(size: 12.5, color: GColors.muted),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2, color: GColors.saffron)
          else ...[
            Row(
              children: [
                for (final n in const [1, 2, 3]) ...[
                  Expanded(
                    child: _ColOption(
                      key: ValueKey('grid-${widget.page}-$n'),
                      cols: n,
                      selected: _cols == n,
                      onTap: _saving ? null : () => _save(n, _force),
                    ),
                  ),
                  if (n < 3) const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              key: ValueKey('grid-${widget.page}-force'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'सभी यूज़र के लिए फ़ोर्स करें',
                style: GText.sans(size: 14, weight: FontWeight.w700),
              ),
              subtitle: Text(
                _force
                    ? 'यूज़र इस पेज का लेआउट नहीं बदल पाएँगे'
                    : 'डिफ़ॉल्ट: यूज़र अपनी पसंद चुन सकते हैं',
                style: GText.sans(size: 12, color: GColors.muted),
              ),
              value: _force,
              activeThumbColor: GColors.saffron,
              onChanged: _saving || _cols == null
                  ? null
                  : (v) => _save(_cols, v),
            ),
            if (_cols != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _saving ? null : () => _save(null, false),
                  child: Text(
                    'हटाएँ (ऐप का सामान्य ग्रिड)',
                    style: GText.sans(size: 13, color: GColors.muted),
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

class _ColOption extends StatelessWidget {
  const _ColOption({
    super.key,
    required this.cols,
    required this.selected,
    required this.onTap,
  });
  final int cols;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: selected
            ? GColors.saffron.withValues(alpha: 0.14)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? GColors.saffron : Colors.black12,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 42,
            height: 30,
            child: Row(
              children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected ? GColors.saffron : Colors.black26,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$cols कॉलम',
            style: GText.sans(
              size: 13,
              weight: FontWeight.w700,
              color: selected ? GColors.maroon : GColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}
