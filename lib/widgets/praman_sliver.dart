import 'package:flutter/cupertino.dart';

import '../models/models.dart';
import '../screens/item_actions.dart';
import '../screens/praman_detail_screen.dart';
import 'animated_items.dart';
import 'cards.dart';
import 'common.dart';

/// Animated sliver list of praman cards; tap → detail (hero), long-press → actions.
class PramanSliverList extends StatelessWidget {
  const PramanSliverList({
    super.key,
    required this.items,
    this.heroPrefix = 'praman',
    this.granthContext,
    this.loading = false,
    this.error,
    this.onRetry,
  });
  final List<Praman> items;
  final String heroPrefix;
  final int? granthContext;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) return const SliverToBoxAdapter(child: LoadingView());
    if (error != null && items.isEmpty) {
      return SliverToBoxAdapter(
        child: MessageView(icon: CupertinoIcons.wifi_exclamationmark, title: '$error', onRetry: onRetry),
      );
    }
    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: MessageView(
          icon: CupertinoIcons.photo_on_rectangle,
          title: 'कोई प्रमाण नहीं / No pramans yet',
          subtitle: 'Upload your first praman with image evidence',
        ),
      );
    }
    final index = {for (var i = 0; i < items.length; i++) items[i].id: i};
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: AnimatedItemsSliver<Praman>(
        items: items,
        idOf: (p) => p.id,
        itemBuilder: (ctx, p, i) => PramanCard(
          praman: p,
          index: index[p.id] ?? i,
          total: items.length,
          heroPrefix: heroPrefix,
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute(
              builder: (_) => PramanDetailScreen(praman: p, heroPrefix: heroPrefix, granthContext: granthContext),
            ),
          ),
          onLongPress: () => showPramanActions(context, p, granthContext: granthContext),
        ),
      ),
    );
  }
}
