import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin/models/models.dart' as w;
import '../admin/widgets/form_sheet.dart' show runWrite;
import '../models/models.dart' as u;
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/overlays.dart';
import 'admin_data.dart';
import 'admin_kit.dart';

/// The list the wnm API must be sent so ONLY the granths of one folder change places.
///
/// The reader app orders a folder by each granth's API `position` (the catalogue order the
/// wnm site returns), and the site's `update_granth_order` renumbers the WHOLE catalogue from
/// the array it is sent. So the folder's granths keep the catalogue slots they already
/// occupy; only the order they fill those slots in changes. Granths of other folders do not
/// move relative to each other.
///
/// [all] is the catalogue in its current order, [folderIdsInNewOrder] the folder's granth ids
/// in the order the admin wants. Ids not in [all] are ignored.
List<w.Granth> catalogueForFolderOrder(
  List<w.Granth> all,
  List<int> folderIdsInNewOrder,
) {
  final byId = {for (final g in all) g.id: g};
  final wanted = <int>[
    for (final id in folderIdsInNewOrder)
      if (byId.containsKey(id)) id,
  ];
  final inFolder = wanted.toSet();
  final slots = [
    for (var i = 0; i < all.length; i++)
      if (inFolder.contains(all[i].id)) i,
  ];
  final out = [...all];
  for (var k = 0; k < slots.length && k < wanted.length; k++) {
    out[slots[k]] = byId[wanted[k]]!;
  }
  return out;
}

/// One row to arrange.
class ArrangeItem {
  const ArrangeItem(this.id, this.title, {this.hidden = false});
  final int id;
  final String title;
  final bool hidden;
}

/// The arrange screen's maths, pure so it is unit-tested.
List<T> moveItem<T>(List<T> list, int from, int to) {
  if (from < 0 || from >= list.length) return list;
  final t = to.clamp(0, list.length - 1);
  if (t == from) return list;
  final out = [...list];
  out.insert(t, out.removeAt(from));
  return out;
}

/// Opens the arrange screen for [granths] (the folder being looked at, in the order the
/// reader app shows them). Resolves true when a new order was saved.
Future<bool?> showArrangeGranths(
  BuildContext context, {
  required List<u.Granth> granths,
  String folderTitle = '',
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => ArrangeGranthsScreen(
        items: [
          for (final g in granths)
            ArrangeItem(
              int.tryParse(g.id) ?? 0,
              g.title,
              hidden: AdminData.I.isHidden(g.id),
            ),
        ],
        folderTitle: folderTitle,
      ),
    ),
  );
}

/// Granth tab → "क्रम बदलें": drag the handle, or use ▲ ▼ / सबसे ऊपर / सबसे नीचे, then save.
/// Saving rewrites the catalogue order on the wnm site (the order the reader app reads).
class ArrangeGranthsScreen extends StatefulWidget {
  const ArrangeGranthsScreen({
    super.key,
    required this.items,
    this.folderTitle = '',
  });
  final List<ArrangeItem> items;
  final String folderTitle;

  @override
  State<ArrangeGranthsScreen> createState() => _ArrangeGranthsScreenState();
}

class _ArrangeGranthsScreenState extends State<ArrangeGranthsScreen> {
  late List<ArrangeItem> _items = [...widget.items];
  bool _dirty = false, _busy = false;

  void _move(int from, int to) {
    final next = moveItem(_items, from, to);
    if (identical(next, _items)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _items = next;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_busy || !_dirty) return;
    final ok0 = await confirmPopTitled(
      context,
      title: 'क्रम सहेजें?',
      message:
          'यह लाइव ऐप में ग्रंथों का क्रम तुरंत बदल देगा (${_items.length} ग्रंथ)।',
      confirm: 'सहेजें',
    );
    if (!ok0 || !mounted) return;
    setState(() => _busy = true);
    final ok = await runWrite(
      () => AdminData.I.saveGranthOrder([for (final i in _items) i.id]),
      success: 'क्रम सहेजा गया',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _dirty = false;
      Navigator.pop(context, true);
    }
  }

  Future<void> _leave() async {
    final leave = await confirmPopTitled(
      context,
      title: 'बिना सहेजे जाएँ?',
      message: 'किया हुआ क्रम सहेजा नहीं गया है।',
      confirm: 'छोड़ें',
      destructive: true,
    );
    if (leave && mounted) {
      setState(() => _dirty = false);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: AdminSubPage(
        title: 'ग्रंथ क्रम',
        trailing: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Pill(
            key: const ValueKey('arr-save'),
            label: _busy ? '…' : 'सहेजें',
            tone: _dirty ? PillTone.maroon : PillTone.plain,
            onTap: _dirty && !_busy ? _save : null,
            minHeight: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            fontSize: 13,
            weight: FontWeight.w700,
          ),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '${widget.folderTitle.isEmpty ? '' : '${widget.folderTitle} · '}'
                'हैंडल पकड़कर खींचें, या ▲ ▼ ⇈ ⇊ दबाएँ। फिर "सहेजें" दबाएँ — '
                'ऐप में यही क्रम दिखेगा।',
                style: GText.sans(
                  size: 12.5,
                  color: GColors.muted,
                  height: 1.4,
                ),
              ),
            ),
          ),
          SliverReorderableList(
            itemCount: _items.length,
            onReorderItem: _move,
            proxyDecorator: (child, i, anim) =>
                Material(color: Colors.transparent, elevation: 0, child: child),
            itemBuilder: (context, i) {
              final it = _items[i];
              return Padding(
                key: ValueKey('arr-${it.id}'),
                padding: const EdgeInsets.only(bottom: 8),
                child: _Row(
                  index: i,
                  count: _items.length,
                  item: it,
                  onMove: (to) => _move(i, to),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.index,
    required this.count,
    required this.item,
    required this.onMove,
  });
  final int index, count;
  final ArrangeItem item;
  final ValueChanged<int> onMove;

  Widget _btn(String key, IconData icon, bool on, int to) => SizedBox(
    width: 32,
    height: 40,
    child: IconButton(
      key: ValueKey('$key-${item.id}'),
      padding: EdgeInsets.zero,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
      color: GColors.maroon,
      disabledColor: GColors.muted.withValues(alpha: 0.35),
      onPressed: on ? () => onMove(to) : null,
      icon: Icon(icon),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final first = index == 0, last = index == count - 1;
    return GCard(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: SizedBox(
              key: ValueKey('arr-handle-${item.id}'),
              width: 38,
              height: 44,
              child: Icon(Icons.drag_indicator, color: GColors.muted, size: 22),
            ),
          ),
          Container(
            width: 30,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GColors.maroon.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${index + 1}',
              style: GText.sans(
                size: 12,
                weight: FontWeight.w800,
                color: GColors.maroon,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Opacity(
              opacity: item.hidden ? 0.55 : 1,
              child: Text(
                item.title.replaceAll(RegExp(r'\s+'), ' ').trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GText.sans(size: 14, color: GColors.brown, height: 1.3),
              ),
            ),
          ),
          _btn('arr-top', Icons.keyboard_double_arrow_up, !first, 0),
          _btn('arr-up', Icons.keyboard_arrow_up, !first, index - 1),
          _btn('arr-down', Icons.keyboard_arrow_down, !last, index + 1),
          _btn(
            'arr-bottom',
            Icons.keyboard_double_arrow_down,
            !last,
            count - 1,
          ),
        ],
      ),
    );
  }
}
