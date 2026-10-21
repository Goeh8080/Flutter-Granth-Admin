import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../widgets/cards.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';

/// topic-sort.php / granth-sort.php: drag (or move up/down) and Save Order.
class ReorderScreen extends StatefulWidget {
  const ReorderScreen._(this.kind, this.items);
  factory ReorderScreen.topics(List<Topic> t) =>
      ReorderScreen._('topic', [for (final x in t) ReorderItem(x.id, x.title, x)]);
  factory ReorderScreen.granths(List<Granth> g) =>
      ReorderScreen._('granth', [for (final x in g) ReorderItem(x.id, x.title, x)]);
  final String kind;
  final List<ReorderItem> items;
  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class ReorderItem {
  const ReorderItem(this.id, this.title, this.data);
  final int id;
  final String title;
  final Object data;
}

class _ReorderScreenState extends State<ReorderScreen> {
  late final List<ReorderItem> _items = List.of(widget.items);
  bool _dirty = false, _busy = false;

  void _move(int from, int to) {
    if (to < 0 || to >= _items.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      final it = _items.removeAt(from);
      _items.insert(to, it);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final ok0 = await confirmDialog(
      context,
      title: 'क्रम सहेजें? / Save order?',
      message: 'यह लाइव ऐप का क्रम बदल देगा / This changes the order in the live app.',
      confirm: 'सहेजें / Save',
      destructive: false,
    );
    if (!ok0 || !mounted) return;
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final ok = await runWrite(() async {
      if (widget.kind == 'topic') {
        await app.api.saveTopicOrder(_items.map((e) => e.data as Topic).toList());
      } else {
        await app.api.saveGranthOrder(_items.map((e) => e.data as Granth).toList());
      }
    }, success: 'क्रम सहेजा गया / Order saved');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _dirty = false;
      app.bump();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final title = widget.kind == 'topic' ? 'विषय क्रम / Sort Topics' : 'ग्रंथ क्रम / Sort Granths';
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmDialog(
          context,
          title: 'बिना सहेजे जाएँ? / Discard changes?',
          confirm: 'छोड़ें / Discard',
        );
        if (leave && context.mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: GlassBackdrop(
        child: CupertinoPageScaffold(
          backgroundColor: Colors.transparent,
          navigationBar: CupertinoNavigationBar(
            backgroundColor: p.barFill,
            middle: Text(title),
            previousPageTitle: 'Back',
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _dirty && !_busy ? _save : null,
              child: _busy
                  ? const CupertinoActivityIndicator()
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text(
                    'हैंडल पकड़कर खींचें या ▲▼ दबाएँ, फिर Save करें / Drag the handle or use ▲▼, then Save',
                    style: TextStyle(color: p.subtext, fontSize: 12.5),
                  ),
                ),
                Expanded(
                  child: Material(
                    type: MaterialType.transparency,
                    child: ReorderableListView.builder(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
                      buildDefaultDragHandles: false,
                      itemCount: _items.length,
                      onReorderItem: (a, b) => _move(a, b),
                      proxyDecorator: (child, i, anim) => AnimatedBuilder(
                        animation: anim,
                        builder: (_, c) {
                          final t = Curves.easeOut.transform(anim.value);
                          return Transform.scale(
                            scale: lerpDouble(1, 1.04, t),
                            child: Material(type: MaterialType.transparency, elevation: 0, child: c),
                          );
                        },
                        child: child,
                      ),
                      itemBuilder: (_, i) {
                        final it = _items[i];
                        return Padding(
                          key: ValueKey(it.id),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Glass(
                            padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
                            radius: 16,
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Icon(CupertinoIcons.line_horizontal_3, color: p.subtext),
                                  ),
                                ),
                                Container(
                                  width: 34,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.saffron.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      color: AppColors.saffronDeep,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${it.id}. ${oneLine(it.title)}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: p.text, fontSize: 14),
                                  ),
                                ),
                                CupertinoButton(
                                  padding: const EdgeInsets.all(6),
                                  minimumSize: Size.zero,
                                  onPressed: i == 0 ? null : () => _move(i, i - 1),
                                  child: const Icon(CupertinoIcons.chevron_up, size: 18),
                                ),
                                CupertinoButton(
                                  padding: const EdgeInsets.all(6),
                                  minimumSize: Size.zero,
                                  onPressed: i == _items.length - 1 ? null : () => _move(i, i + 1),
                                  child: const Icon(CupertinoIcons.chevron_down, size: 18),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
