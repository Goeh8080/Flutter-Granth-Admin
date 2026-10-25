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
    // Fast path (the common case: a parent rebuild with the same rows): no diff, just refresh the data.
    if (next.length == _items.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (widget.idOf(next[i]) != widget.idOf(_items[i])) {
          same = false;
          break;
        }
      }
      if (same) {
        _items = List.of(next);
        return;
      }
    }
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

  Widget _wrap(BuildContext ctx, T item, int index, Animation<double> a, {bool removing = false}) =>
      _ItemTransition(animation: a, removing: removing, child: widget.itemBuilder(ctx, item, index));

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

/// Size + fade + scale for an inserted/removed row. The curve and tweens are created once (not on
/// every parent rebuild) and the row is isolated in its own repaint layer.
class _ItemTransition extends StatefulWidget {
  const _ItemTransition({required this.animation, required this.removing, required this.child});
  final Animation<double> animation;
  final bool removing;
  final Widget child;
  @override
  State<_ItemTransition> createState() => _ItemTransitionState();
}

class _ItemTransitionState extends State<_ItemTransition> {
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: widget.animation,
    curve: widget.removing ? Curves.easeInCubic : Curves.easeOutCubic,
  );
  late final Animation<double> _scale = Tween<double>(begin: 0.92, end: 1.0).animate(_curved);

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizeTransition(
        sizeFactor: _curved,
        child: FadeTransition(
          opacity: _curved,
          child: ScaleTransition(scale: _scale, child: widget.child),
        ),
      ),
    );
  }
}

/// Fade + slide-up when first built; staggered for the first rows only. One controller with an
/// [Interval] per row (no `Future.delayed`), and the curve is built once.
class _StaggerIn extends StatefulWidget {
  const _StaggerIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn> with SingleTickerProviderStateMixin {
  static const _base = 420;
  static const _step = 35;
  static const _staggered = 12;

  late final int _delay = widget.index >= _staggered ? 0 : widget.index * _step;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _base + _delay),
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Interval(_delay / (_base + _delay), 1, curve: Curves.easeOutCubic),
  );
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(_a);

  @override
  void initState() {
    super.initState();
    if (widget.index >= _staggered) {
      _c.value = 1; // rows past the first screenful appear in place
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
