import 'package:flutter/material.dart';

import '../admin/models/panel_models.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';

/// Round 5: per-page grid override (CONTRACT §4.1.1 `ui.grid_pages`).
/// Each page: 1×1 / 2×2 / 3×3, or "default" (= `ui.grid`). Saved via PUT /settings (draft) → publish.
class GridPagesCard extends StatefulWidget {
  final int? grid;
  final Map<String, int> pages;
  final void Function(String page, int? n) onSet;
  final bool initiallyExpanded;
  const GridPagesCard({
    super.key,
    required this.grid,
    required this.pages,
    required this.onSet,
    this.initiallyExpanded = false,
  });

  static const labels = {
    'granths': 'ग्रंथ (granths)',
    'shelves': 'शेल्फ़ (shelves)',
    'pramans': 'प्रमाण (pramans)',
    'topics': 'विषय (topics)',
    'gallery': 'गैलरी (gallery)',
    'dashboard': 'डैशबोर्ड (dashboard)',
  };

  @override
  State<GridPagesCard> createState() => _GridPagesCardState();
}

class _GridPagesCardState extends State<GridPagesCard> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final g = widget.grid ?? 3;
    final pages = widget.pages;
    const labels = GridPagesCard.labels;
    return GCard(
      key: const ValueKey('grid-pages-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            key: const ValueKey('grid-pages-toggle'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                const GIcon('layout-grid', size: 20, color: GColors.maroon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'हर पेज का ग्रिड',
                    style: GText.sans(
                      size: 15,
                      weight: FontWeight.w800,
                      color: GColors.maroon,
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  color: GColors.maroon,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${pages.isEmpty ? 'कोई ओवरराइड नहीं' : '${pages.length} पेज ओवरराइड'} · '
            'डिफ़ॉल्ट = ui.grid ($g×$g) · प्रकाशित करने पर लागू',
            style: GText.sans(size: 12.5, color: GColors.muted),
          ),
          if (_open)
            for (final p in PanelSettings.gridPages) ...[
              const SizedBox(height: 10),
              Text(
                labels[p] ?? p,
                style: GText.sans(size: 13.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in const [1, 2, 3])
                    Pill(
                      key: ValueKey('gp-$p-$n'),
                      label: '$n×$n',
                      tone: pages[p] == n ? PillTone.maroon : PillTone.plain,
                      minHeight: 36,
                      fontSize: 13,
                      onTap: () => widget.onSet(p, n),
                    ),
                  Pill(
                    key: ValueKey('gp-$p-default'),
                    label: 'डिफ़ॉल्ट = ui.grid',
                    tone: pages[p] == null ? PillTone.maroon : PillTone.plain,
                    minHeight: 36,
                    fontSize: 13,
                    onTap: () => widget.onSet(p, null),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}
