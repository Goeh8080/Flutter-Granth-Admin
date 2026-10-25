import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../widgets/bounded_scroll.dart';
import '../widgets/common.dart';

/// A pushed admin sub-page in the user app's look: cream page, "पीछे" pill, one scroller.
class AdminSubPage extends StatelessWidget {
  const AdminSubPage({
    super.key,
    required this.title,
    required this.slivers,
    this.trailing,
    this.onRefresh,
  });
  final String title;
  final List<Widget> slivers;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    Widget scroller = CustomScrollView(
      physics: const BoundedScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Pill(
                  icon: 'chevron-left',
                  label: 'पीछे',
                  onTap: () => Navigator.maybePop(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GText.display(
                      size: 26,
                      color: GColors.maroon,
                      height: 1.2,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
          sliver: SliverMainAxisGroup(slivers: slivers),
        ),
      ],
    );
    if (onRefresh != null)
      scroller = RefreshIndicator(
        color: GColors.maroon,
        onRefresh: onRefresh!,
        child: scroller,
      );
    return Scaffold(
      backgroundColor: GColors.cream,
      body: SafeArea(bottom: false, child: scroller),
    );
  }
}

/// One row of the Admin Panel hub: icon box, title + sub line, optional count badge, chevron.
class AdminTile extends StatelessWidget {
  const AdminTile({
    super.key,
    required this.icon,
    required this.title,
    this.sub,
    this.onTap,
    this.badge = 0,
    this.danger = false,
    this.tone = Tone.maroon,
  });
  final String icon, title;
  final String? sub;
  final VoidCallback? onTap;
  final int badge;
  final bool danger;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final c = danger ? const Color(0xFFB3261E) : GColors.maroon;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            IconBox(tone: tone, icon: icon, size: 40, radius: 12, iconSize: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GText.sans(
                      size: 15,
                      weight: FontWeight.w800,
                      color: c,
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub!,
                      style: GText.sans(
                        size: 12.5,
                        color: GColors.muted,
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),
            if (badge > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: GColors.maroon,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badge',
                  style: GText.sans(
                    size: 12,
                    weight: FontWeight.w800,
                    color: GColors.paper,
                  ),
                ),
              ),
            if (onTap != null)
              GIcon('chevron-right', size: 18, color: GColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Small section label on the Admin Panel / sub-pages.
class AdminLabel extends StatelessWidget {
  const AdminLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Text(text, style: GText.display(size: 19, color: GColors.maroon)),
  );
}

/// Text box in the app's paper/saffron style (same as `promptPop`).
class AdminField extends StatelessWidget {
  const AdminField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.hint,
    this.onChanged,
    this.counter,
  });
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final String? counter;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GText.sans(
                  size: 13,
                  weight: FontWeight.w700,
                  color: GColors.muted,
                ),
              ),
            ),
            if (counter != null)
              Text(counter!, style: GText.sans(size: 12, color: GColors.muted)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: GColors.paper,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: GColors.gold, width: 1.2),
          ),
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: maxLines,
            onChanged: onChanged,
            style: GText.sans(size: 15.5),
            cursorColor: GColors.saffron,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: hint,
              hintStyle: GText.sans(size: 15, color: GColors.muted),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
