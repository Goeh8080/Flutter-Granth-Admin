import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../theme/smooth_scroll.dart';

/// Large-title iOS page on a glass backdrop. The nav bar is translucent,
/// and Cupertino applies the blur behind it.
class GlassPage extends StatefulWidget {
  const GlassPage({
    super.key,
    required this.title,
    required this.slivers,
    this.trailing,
    this.leading,
    this.onRefresh,
    this.bottomInset = 0,
    this.controller,
    this.previousPageTitle,
    this.largeTitle = true,
    this.floating,
  });
  final String title;
  final List<Widget> slivers;
  final Widget? trailing;
  final Widget? leading;
  final Future<void> Function()? onRefresh;
  final double bottomInset;
  final ScrollController? controller;
  final String? previousPageTitle;
  final bool largeTitle;
  final Widget? floating;

  @override
  State<GlassPage> createState() => _GlassPageState();
}

class _GlassPageState extends State<GlassPage> {
  late final ScrollController _sc = widget.controller ?? ScrollController();

  @override
  void dispose() {
    if (widget.controller == null) _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final trailing = widget.trailing;
    final leading = widget.leading;
    final previousPageTitle = widget.previousPageTitle;
    final onRefresh = widget.onRefresh;
    final slivers = widget.slivers;
    final bottomInset = widget.bottomInset;
    final floating = widget.floating;
    final p = Palette.of(context);
    // Nearly opaque bar with no BackdropFilter: a full-width live blur on every page of the stack
    // was one of the heaviest per-frame costs while scrolling.
    final navBg = p.barFill.withValues(alpha: p.dark ? 0.94 : 0.92);
    final border = Border(bottom: BorderSide(color: p.separator, width: 0.5));
    final titleW = Text(title, maxLines: 1, overflow: TextOverflow.ellipsis);
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            CustomScrollView(
              controller: _sc,
              physics: const SmoothScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              // Build a little ahead of the viewport so fast flicks don't reveal blank rows.
              scrollCacheExtent: const ScrollCacheExtent.pixels(600),
              slivers: [
                if (widget.largeTitle)
                  CupertinoSliverNavigationBar(
                    largeTitle: titleW,
                    backgroundColor: navBg,
                    border: border,
                    trailing: trailing,
                    leading: leading,
                    previousPageTitle: previousPageTitle,
                    stretch: true,
                    enableBackgroundFilterBlur: false,
                  )
                else
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _BarDelegate(
                      CupertinoNavigationBar(
                        middle: titleW,
                        backgroundColor: navBg,
                        border: border,
                        trailing: trailing,
                        leading: leading,
                        previousPageTitle: previousPageTitle,
                        enableBackgroundFilterBlur: false,
                      ),
                      MediaQuery.paddingOf(context).top +
                          kMinInteractiveDimensionCupertino,
                    ),
                  ),
                if (onRefresh != null)
                  CupertinoSliverRefreshControl(onRefresh: onRefresh),
                ...slivers,
                SliverToBoxAdapter(
                  child: SizedBox(
                    height:
                        24 + bottomInset + MediaQuery.paddingOf(context).bottom,
                  ),
                ),
              ],
            ),
            ?floating,
          ],
        ),
      ),
    );
  }
}

class _BarDelegate extends SliverPersistentHeaderDelegate {
  _BarDelegate(this.child, this.height);
  final Widget child;
  final double height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  double get maxExtent => height;
  @override
  double get minExtent => height;
  @override
  bool shouldRebuild(covariant _BarDelegate old) =>
      old.child != child || old.height != height;
}

/// Padding wrapper for sliver content.
class PadSliver extends StatelessWidget {
  const PadSliver({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) =>
      SliverPadding(padding: padding, sliver: child);
}

/// Floating "+" action, glass styled.
class GlassFab extends StatelessWidget {
  const GlassFab({
    super.key,
    required this.onTap,
    this.icon = CupertinoIcons.add,
    this.bottom = 100,
  });
  final VoidCallback onTap;
  final IconData icon;
  final double bottom;
  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: bottom + MediaQuery.paddingOf(context).bottom,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.saffron, AppColors.saffronDeep],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.saffron.withValues(alpha: 0.45),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
