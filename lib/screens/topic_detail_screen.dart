import 'package:flutter/cupertino.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../widgets/common.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/links.dart';
import '../widgets/praman_sliver.dart';
import '../widgets/toast.dart';
import 'item_actions.dart';
import 'praman_form.dart';
import 'topic_form.dart';

/// showPramanForTopic(): topic info + its pramans (get_pramans&topicId=).
class TopicDetailScreen extends StatefulWidget {
  const TopicDetailScreen({super.key, required this.topic});
  final Topic topic;
  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> with RevisionReload<TopicDetailScreen> {
  late Topic _t = widget.topic;
  List<Praman> _pramans = const [];
  bool _loading = true;
  Object? _error;
  @override
  Future<void> reload() => _load();

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    setState(() => _error = null);
    try {
      final r = await Future.wait([api.topic(_t.id), api.pramans(topicId: _t.id)]);
      if (!mounted) return;
      setState(() {
        final fresh = r[0] as Topic;
        _t = Topic.fromJson({..._t.raw, ...fresh.raw});
        _pramans = r[1] as List<Praman>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
      if (_pramans.isNotEmpty) showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GlassPage(
      title: 'विषय',
      largeTitle: false,
      previousPageTitle: 'विषय',
      onRefresh: _load,
      trailing: GlassIconButton(
        CupertinoIcons.ellipsis,
        onTap: () => showTopicActions(context, _t, onDeleted: () => Navigator.of(context).maybePop()),
      ),
      floating: GlassFab(bottom: 24, onTap: () => showPramanForm(context, topicId: _t.id)),
      slivers: [
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SliverToBoxAdapter(
            child: Glass(
              blur: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Tag('#${_t.position}', color: AppColors.maroon),
                      const SizedBox(width: 6),
                      Tag('${_t.pramanCount} प्रमाण', icon: CupertinoIcons.photo_on_rectangle),
                      const Spacer(),
                      OptimisticActive(
                        kind: 'topic',
                        id: _t.id,
                        server: _t.isActive,
                        builder: (_, a) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusDot(a),
                            const SizedBox(width: 6),
                            Text(a ? 'Active' : 'In-Active', style: TextStyle(color: p.subtext, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t.title,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text, height: 1.5),
                  ),
                  if (_t.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_t.description, style: TextStyle(color: p.subtext, fontSize: 15, height: 1.5)),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PillButton('Edit', CupertinoIcons.pencil, () => showTopicForm(context, topic: _t)),
                      OptimisticActive(
                        kind: 'topic',
                        id: _t.id,
                        server: _t.isActive,
                        builder: (_, a) => PillButton(
                          a ? 'Hide' : 'Show',
                          a ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                          () => toggleTopic(context, _t),
                        ),
                      ),
                      PillButton('Position', CupertinoIcons.number, () => moveTopicFlow(context, _t)),
                      PillButton('Share', CupertinoIcons.share, () => shareItem('topic', _t.id, _t.title)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        PadSliver(child: SliverToBoxAdapter(child: SectionTitle('प्रमाण / Pramans (${_pramans.length})'))),
        PramanSliverList(items: _pramans, heroPrefix: 'tp', loading: _loading, error: _error, onRetry: _load),
      ],
    );
  }
}

class PillButton extends StatelessWidget {
  const PillButton(this.label, this.icon, this.onTap, {super.key});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: Size.zero,
    onPressed: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.saffron.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.saffron.withValues(alpha: 0.25), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.saffron),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: AppColors.saffron, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}
