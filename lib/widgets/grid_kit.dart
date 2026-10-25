import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import 'common.dart' show NetImage;
import 'icons/folder_tokens.dart';
import '../screens/panel/panel_widgets.dart' show FilterChipX;

/// Shared 1×1 / 2×2 / 3×3 grid helpers (see admin_ui_tokens.md §4/§5).

const kGridPrefFolders = 'grid_cols_folders';
const kGridPrefPanelGranths = 'grid_cols_panel_granths';
const kGridPrefGranths = 'grid_cols_granths';

/// Reads a saved column count (1..3), or [def]. Never throws.
Future<int> readGridCols(String key, int def) async {
  try {
    final p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
    final v = p.getInt(key);
    return v != null && v >= 1 && v <= 3 ? v : def;
  } catch (_) {
    return def;
  }
}

Future<void> saveGridCols(String key, int cols) async {
  try {
    final p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
    await p.setInt(key, cols);
  } catch (_) {}
}

/// Gap between cards: 1×1 = 14, 2×2 = 10, 3×3 = 8.
double gridGap(int cols) => switch (cols) {
  1 => 14,
  2 => 10,
  _ => 8,
};

/// Columns actually laid out: phones use the chosen 1/2/3, wide screens get 4–6 for folders.
int folderColumns(int cols, double width) {
  if (width < 600) return cols;
  return switch (cols) {
    1 => 2,
    2 => 4,
    _ => width >= 900 ? 6 : 5,
  };
}

/// The small "1×1 · 2×2 · 3×3" switch.
class GridSwitch extends StatelessWidget {
  const GridSwitch({super.key, required this.cols, required this.onChanged, this.options = const [1, 2, 3]});
  final int cols;
  final ValueChanged<int> onChanged;
  final List<int> options;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.fieldFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.glassBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(o),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: o == cols ? AppColors.saffron : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$o×$o',
                  key: ValueKey('grid-$o'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: o == cols ? Colors.white : p.text,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The reader app's card: paper background, 1px creamDark border, radius 12, soft brown shadow.
class PaperCard extends StatefulWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.onTap,
    this.onLongPress,
    this.dim = false,
    this.selected = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap, onLongPress;
  final bool dim, selected;
  @override
  State<PaperCard> createState() => _PaperCardState();
}

class _PaperCardState extends State<PaperCard> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final dark = Palette.of(context).dark;
    final card = AnimatedScale(
      scale: _down ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFFF7F0E1) : GColors.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.selected ? GColors.saffron : GColors.creamDark,
            width: widget.selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(color: GColors.brown.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: widget.child,
      ),
    );
    final c = Opacity(opacity: widget.dim ? 0.55 : 1, child: card);
    if (widget.onTap == null && widget.onLongPress == null) return c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: c,
    );
  }
}

/// A lazily built grid: [cols] cards per row, equal row height, [gap] between cards.
class GridRowsSliver extends StatelessWidget {
  const GridRowsSliver({super.key, required this.cols, required this.count, required this.itemBuilder, this.gap});
  final int cols, count;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double? gap;

  @override
  Widget build(BuildContext context) {
    final g = gap ?? gridGap(cols);
    final rows = (count + cols - 1) ~/ cols;
    return SliverList.builder(
      itemCount: rows,
      itemBuilder: (context, r) => Padding(
        padding: EdgeInsets.only(bottom: g),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < cols; c++) ...[
                if (c > 0) SizedBox(width: g),
                Expanded(child: r * cols + c < count ? itemBuilder(context, r * cols + c) : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A granth cover at its natural aspect ratio with a skeleton while loading.
class CoverImage extends StatelessWidget {
  const CoverImage(this.url, {super.key});
  final String? url;
  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty || !NetImage.enabled) return const SizedBox.shrink();
    Widget skeleton([IconData? i]) => Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GColors.creamDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: i == null ? null : Icon(i, color: GColors.muted),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: u,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (_, _) => skeleton(),
          errorWidget: (_, _, _) => skeleton(CupertinoIcons.photo),
        ),
      ),
    );
  }
}

/// Footer pill of the granth card (tokens §4): plain / maroon / topic tone.
enum PillTone { plain, maroon, topic, danger }

class CardPill extends StatelessWidget {
  const CardPill(
    this.label, {
    super.key,
    this.icon,
    this.tone = PillTone.plain,
    this.onTap,
    this.cols = 2,
    this.tiny = false,
  });
  final String label;
  final IconData? icon;
  final PillTone tone;
  final VoidCallback? onTap;
  final int cols;
  final bool tiny;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.plain => (const Color(0xFFF5EFDF), GColors.brown),
      PillTone.maroon => (const Color(0xFFF2E9EA), GColors.maroon),
      PillTone.topic => (const Color(0xFFFCEEDF), GColors.saffronDark),
      PillTone.danger => (const Color(0xFFFBE9E7), const Color(0xFFB3261E)),
    };
    final small = cols == 3;
    final fs = tiny ? 12.0 : (small ? 13.0 : 15.0);
    final pad = tiny
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 7)
        : (small
              ? const EdgeInsets.symmetric(horizontal: 9, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 10));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: tiny ? 34 : (small ? 36 : 42)),
        padding: pad,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 16, color: fg),
            if (icon != null && label.isNotEmpty) const SizedBox(width: 5),
            if (label.isNotEmpty)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: fs),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One entry of a [SortBar]: [key] is the identifier, [label] the chip text.
class SortOpt {
  const SortOpt(this.key, this.label);
  final String key, label;
}

/// Horizontal row of sort chips. Tapping the active chip flips the direction (↑ / ↓).
class SortBar extends StatelessWidget {
  const SortBar({super.key, required this.options, required this.sortKey, required this.desc, required this.onChanged});
  final List<SortOpt> options;
  final String sortKey;
  final bool desc;
  final void Function(String key, bool desc) onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('क्रम:', style: TextStyle(color: p.subtext, fontSize: 13)),
          ),
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChipX(
                o.key == sortKey ? '${o.label} ${desc ? '↓' : '↑'}' : o.label,
                selected: o.key == sortKey,
                onTap: () => o.key == sortKey ? onChanged(o.key, !desc) : onChanged(o.key, false),
              ),
            ),
        ],
      ),
    );
  }
}

/// Stable sort by a comparable key; strings are compared case-insensitively.
List<T> sortedBy<T>(List<T> list, Comparable Function(T) by, {bool desc = false}) {
  Comparable k(T t) {
    final v = by(t);
    return v is String ? v.toLowerCase() : v;
  }

  final idx = {for (var i = 0; i < list.length; i++) list[i]: i};
  final out = List<T>.of(list)
    ..sort((a, b) {
      final c = k(a).compareTo(k(b));
      if (c != 0) return desc ? -c : c;
      return idx[a]!.compareTo(idx[b]!);
    });
  return out;
}
