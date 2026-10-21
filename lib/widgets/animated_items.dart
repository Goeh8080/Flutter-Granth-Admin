import 'package:flutter/material.dart';

/// Sliver list that animates inserts/removals when [items] changes
/// (diffed by [idOf]). A full re-order falls back to a fresh list with a staggered fade-in.
class AnimatedItemsSliver<T> extends StatefulWidget {
  const AnimatedItemsSliver({super.key, required this.items, required this.idOf, required this.itemBuilder});
  final List<T> items;
  final Object Function(T) idOf;
  final Widget Function(BuildContext, T, int) itemBuilder;

  @override
  State<AnimatedItemsSliver<T>> createState() => _AnimatedItemsSliverState<T>();
}

class _AnimatedItemsSliverState<T> extends State<AnimatedItemsSliver<T>> {
  var _listKey = GlobalKey<SliverAnimatedListState>();
  late List<T> _items = List.of(widget.items);
  int _generation = 0;

  @override
  void didUpdateWidget(covariant AnimatedItemsSliver<T> old) {
    super.didUpdateWidget(old);
    final next = widget.items;
    final oldIds = _items.map(widget.idOf).toList();
    final newIds = next.map(widget.idOf).toList();
    final newSet = newIds.toSet();
    final oldSet = oldIds.toSet();
    final commonOld = oldIds.where(newSet.contains).toList();
    final commonNew = newIds.where(oldSet.contains).toList();
    final sameOrder =
        commonOld.length == commonNew.length &&
        List.generate(commonOld.length, (i) => commonOld[i] == commonNew[i]).every((e) => e);
    final changes = (oldIds.length - commonOld.length) + (newIds.length - commonNew.length);
    final state = _listKey.currentState;
    if (!sameOrder || state == null || changes > 60) {
      setState(() {
        _items = List.of(next);
        _listKey = GlobalKey<SliverAnimatedListState>();
        _generation++;
      });
      return;
    }
    // removals (from the end so indices stay valid)
    for (var i = _items.length - 1; i >= 0; i--) {
      if (!newSet.contains(widget.idOf(_items[i]))) {
        final removed = _items.removeAt(i);
        state.removeItem(
          i,
          (ctx, a) => _wrap(ctx, removed, i, a, removing: true),
          duration: const Duration(milliseconds: 320),
        );
      }
    }
    // insertions in new order
    for (var i = 0; i < next.length; i++) {
      final id = widget.idOf(next[i]);
      if (!oldSet.contains(id)) {
        _items.insert(i, next[i]);
        state.insertItem(i, duration: const Duration(milliseconds: 420));
      } else {
        _items[i] = next[i]; // refresh data for unchanged ids
      }
    }
  }

  Widget _wrap(BuildContext ctx, T item, int index, Animation<double> a, {bool removing = false}) {
    final curved = CurvedAnimation(parent: a, curve: removing ? Curves.easeInCubic : Curves.easeOutCubic);
    return SizeTransition(
      sizeFactor: curved,
      child: FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(curved),
          child: widget.itemBuilder(ctx, item, index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverAnimatedList(
      key: _listKey,
      initialItemCount: _items.length,
      itemBuilder: (ctx, i, a) {
        if (i >= _items.length) return const SizedBox.shrink();
        final item = _items[i];
        return _StaggerIn(
          key: ValueKey('${_generation}_${widget.idOf(item)}'),
          index: i,
          child: _wrap(ctx, item, i, a),
        );
      },
    );
  }
}

/// Fade + slide-up when first built; staggered for the first rows only.
class _StaggerIn extends StatefulWidget {
  const _StaggerIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  @override
  void initState() {
    super.initState();
    if (widget.index >= 12) {
      _c.value = 1;
      return;
    }
    final delay = widget.index * 35;
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a),
        child: widget.child,
      ),
    );
  }
}
