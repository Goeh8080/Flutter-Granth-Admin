import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../widgets/animated_items.dart';
import '../widgets/common.dart';
import '../widgets/form_sheet.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/links.dart';
import '../widgets/motion.dart';
import 'feedback_form.dart';
import 'image_viewer.dart';

/// loadfeedbacks() list + removeFeedback() + saveFeedback().
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  List<FeedbackItem> _items = const [];
  bool _loading = true;
  Object? _error;
  int _rev = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rev = AppScope.of(context, listen: true).revision;
    if (rev != _rev) {
      _rev = rev;
      Future.microtask(_load);
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await AppScope.of(context).api.feedbacks();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(FeedbackItem f) async {
    final app = AppScope.of(context);
    if (!await confirmDialog(
      context,
      title: 'क्या आप यह फीडबैक हटाना चाहते हैं? / Delete this feedback?',
      message: f.description,
    )) {
      return;
    }
    final ok = await runWrite(() => app.api.deleteFeedback(f.id), success: 'फीडबैक हटाया गया / Feedback deleted');
    if (ok) app.bump();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GlassPage(
      title: 'फीडबैक / Feedback',
      previousPageTitle: 'Back',
      onRefresh: _load,
      trailing: GlassIconButton(CupertinoIcons.add, onTap: () => showFeedbackForm(context)),
      slivers: [
        if (_loading)
          const SliverToBoxAdapter(child: LoadingView())
        else if (_error != null && _items.isEmpty)
          SliverToBoxAdapter(
            child: MessageView(icon: CupertinoIcons.wifi_exclamationmark, title: '$_error', onRetry: _load),
          )
        else if (_items.isEmpty)
          const SliverToBoxAdapter(
            child: MessageView(icon: CupertinoIcons.chat_bubble_2, title: 'कोई फीडबैक नहीं / No feedback yet'),
          )
        else
          PadSliver(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: AnimatedItemsSliver<FeedbackItem>(
              items: _items,
              idOf: (f) => f.id,
              itemBuilder: (ctx, f, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Glass(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SelectableText(
                              '${_items.indexOf(f) + 1}. ${f.description.trim()}',
                              style: TextStyle(color: p.text, fontSize: 15, height: 1.5),
                            ),
                          ),
                          GlassIconButton(CupertinoIcons.trash, color: AppColors.red, onTap: () => _delete(f)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(CupertinoIcons.person_crop_circle, size: 16, color: p.subtext),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              f.name,
                              style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (f.mob.isNotEmpty)
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 24),
                              onPressed: () => openExternal('tel:${f.mob}'),
                              child: Text(f.mob, style: const TextStyle(fontSize: 13)),
                            ),
                        ],
                      ),
                      if (f.imageUrl != null) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => openImageViewer(context, [ViewerImage(f.imageUrl!, f.name)]),
                          child: NetImage(f.imageUrl, height: 160, width: double.infinity),
                        ),
                      ],
                      if (f.topicTitle.isNotEmpty || f.granthTitle.isNotEmpty || f.pramanTitle.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (f.topicTitle.isNotEmpty)
                              Tag(f.topicTitle.replaceAll('\n', ' '), icon: CupertinoIcons.list_bullet),
                            if (f.granthTitle.isNotEmpty)
                              Tag(f.granthTitle.replaceAll('\n', ' '), icon: CupertinoIcons.book),
                            if (f.pramanTitle.isNotEmpty)
                              Tag(f.pramanTitle.replaceAll('\n', ' '), icon: CupertinoIcons.photo),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
