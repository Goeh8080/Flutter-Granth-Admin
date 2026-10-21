import 'package:flutter/cupertino.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../widgets/common.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/links.dart';
import '../widgets/toast.dart';
import 'feedback_form.dart';
import 'feedback_screen.dart';
import 'granth_form.dart';
import 'home_shell.dart';
import 'praman_form.dart';
import 'pramans_screen.dart';
import 'reorder_screen.dart';
import 'topic_form.dart';
import 'topics_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<FeedbackItem> _feedbacks = const [];
  bool _loading = true;
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
    final app = AppScope.of(context);
    try {
      final r = await Future.wait([app.loadStats(), app.api.feedbacks()]);
      if (mounted) setState(() => _feedbacks = r[1] as List<FeedbackItem>);
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _push(Widget w) => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, listen: true);
    final p = Palette.of(context);
    final s = app.stats;
    return GlassPage(
      title: 'डैशबोर्ड',
      bottomInset: kTabBarHeight + 20,
      onRefresh: _load,
      trailing: GlassIconButton(CupertinoIcons.refresh, onTap: _load),
      slivers: [
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SliverToBoxAdapter(
            child: Text(
              'नमस्ते ${app.username} • Overview of your Granth collection',
              style: TextStyle(color: p.subtext, fontSize: 13.5),
            ),
          ),
        ),
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: _Stat(
                    'विषय',
                    'Topics',
                    s?.topics,
                    CupertinoIcons.list_bullet,
                    AppColors.saffron,
                    () => HomeTabs.go(context, 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    'ग्रंथ',
                    'Granths',
                    s?.granths,
                    CupertinoIcons.book_fill,
                    AppColors.maroon,
                    () => HomeTabs.go(context, 2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    'प्रमाण',
                    'Pramans',
                    s?.pramans,
                    CupertinoIcons.photo_fill_on_rectangle_fill,
                    AppColors.gold,
                    () => HomeTabs.go(context, 3),
                  ),
                ),
              ],
            ),
          ),
        ),
        const PadSliver(child: SliverToBoxAdapter(child: SectionTitle('त्वरित कार्य / Quick actions'))),
        PadSliver(
          child: SliverGrid.count(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              _Action('नया विषय', CupertinoIcons.add_circled, () => showTopicForm(context)),
              _Action('नया ग्रंथ', CupertinoIcons.book, () => showGranthForm(context)),
              _Action('नया प्रमाण', CupertinoIcons.photo_on_rectangle, () => showPramanForm(context)),
              _Action('विषय क्रम', CupertinoIcons.arrow_up_arrow_down, () async {
                try {
                  final t = await app.loadTopics();
                  _push(ReorderScreen.topics(t));
                } catch (e) {
                  showError(e);
                }
              }),
              _Action('ग्रंथ क्रम', CupertinoIcons.arrow_up_arrow_down_square, () async {
                try {
                  final g = await app.loadGranths();
                  _push(ReorderScreen.granths(g));
                } catch (e) {
                  showError(e);
                }
              }),
              _Action('निष्क्रिय विषय', CupertinoIcons.eye_slash, () => _push(const TopicsScreen(inactiveOnly: true))),
              _Action(
                'YouTube प्रमाण',
                CupertinoIcons.play_rectangle,
                () => _push(const PramansScreen(initialFilter: PramanFilter.youtube, standalone: true)),
              ),
              _Action('फीडबैक', CupertinoIcons.chat_bubble_2, () => _push(const FeedbackScreen())),
              _Action('+ फीडबैक', CupertinoIcons.plus_bubble, () => showFeedbackForm(context)),
            ],
          ),
        ),
        PadSliver(
          child: SliverToBoxAdapter(
            child: SectionTitle(
              'फीडबैक / Feedback (${_feedbacks.length})',
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 24),
                onPressed: () => _push(const FeedbackScreen()),
                child: const Text('सभी देखें / See all', style: TextStyle(fontSize: 13)),
              ),
            ),
          ),
        ),
        if (_loading)
          const SliverToBoxAdapter(child: LoadingView())
        else
          PadSliver(
            child: SliverList.list(
              children: [
                for (final f in _feedbacks.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PressableGlass(
                      onTap: () => _push(const FeedbackScreen()),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.description.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.text, fontSize: 14.5),
                          ),
                          const SizedBox(height: 4),
                          Text('— ${f.name}', style: TextStyle(color: p.subtext, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        PadSliver(
          child: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: PressableGlass(
                onTap: () => openExternal('mailto:sadgranthpraman@gmail.com'),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.mail, color: AppColors.saffron),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('संपर्क / Contact us at', style: TextStyle(color: p.subtext, fontSize: 12)),
                          Text(
                            'sadgranthpraman@gmail.com',
                            style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
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

class _Stat extends StatelessWidget {
  const _Stat(this.hi, this.en, this.value, this.icon, this.color, this.onTap);
  final String hi, en;
  final int? value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PressableGlass(
      blur: 16,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (value ?? 0).toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Text(
              value == null ? '—' : '${v.round()}',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text, height: 1.2),
            ),
          ),
          Text(
            hi,
            style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Text(en, style: TextStyle(color: p.subtext, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PressableGlass(
      padding: const EdgeInsets.all(8),
      radius: 18,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.saffron, size: 26),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
          ),
        ],
      ),
    );
  }
}
