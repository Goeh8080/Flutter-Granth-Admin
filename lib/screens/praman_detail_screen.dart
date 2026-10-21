import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../widgets/common.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/links.dart';
import '../widgets/toast.dart';
import 'granth_detail_screen.dart';
import 'image_viewer.dart';
import 'item_actions.dart';
import 'praman_form.dart';
import 'topic_detail_screen.dart';

/// praman.php?id= : one praman with images (openPopup), YouTube, topic/granth links and all actions.
class PramanDetailScreen extends StatefulWidget {
  const PramanDetailScreen({super.key, required this.praman, this.heroPrefix = 'praman', this.granthContext});
  final Praman praman;
  final String heroPrefix;
  final int? granthContext;
  @override
  State<PramanDetailScreen> createState() => _PramanDetailScreenState();
}

class _PramanDetailScreenState extends State<PramanDetailScreen> {
  late Praman _p = widget.praman;
  int _rev = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rev = AppScope.of(context, listen: true).revision;
    if (rev != _rev) {
      final first = _rev == -1;
      _rev = rev;
      Future.microtask(() => _load(silent: first));
    }
  }

  Future<void> _load({bool silent = false}) async {
    try {
      // get_pramans&id= returns the joined titles/images; fall back to get_praman.
      final list = await AppScope.of(context).api.pramans(id: _p.id);
      if (!mounted) return;
      if (list.isNotEmpty) setState(() => _p = list.first);
    } catch (e) {
      if (!silent) showError(e);
    }
  }

  List<ViewerImage> get _images => [
    if (_p.imageUrl != null) ViewerImage(_p.imageUrl!, 'प्रमाण चित्र', heroTag: '${widget.heroPrefix}-img-${_p.id}'),
    if (_p.editorImageUrl != null) ViewerImage(_p.editorImageUrl!, 'विवरण चित्र'),
    if (_p.granthImageUrl != null) ViewerImage(_p.granthImageUrl!, 'ग्रंथ चित्र'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = AppScope.of(context);
    final thumb = _p.imageUrl ?? _p.youtubeThumb ?? _p.granthImageUrl;
    final canFav = (widget.granthContext ?? _p.granthId) != 0;
    return GlassPage(
      title: 'प्रमाण #${_p.id}',
      largeTitle: false,
      previousPageTitle: 'Back',
      onRefresh: _load,
      trailing: GlassIconButton(
        CupertinoIcons.ellipsis,
        onTap: () => showPramanActions(
          context,
          _p,
          granthContext: widget.granthContext,
          onDeleted: () => Navigator.of(context).maybePop(),
        ),
      ),
      slivers: [
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SliverToBoxAdapter(
            child: GestureDetector(
              onTap: () => openImageViewer(context, _images),
              child: Hero(
                tag: '${widget.heroPrefix}-img-${_p.id}',
                child: NetImage(thumb, height: 300, width: double.infinity, radius: 24, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SliverToBoxAdapter(
            child: Glass(
              blur: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusDot(_p.isActive),
                      const SizedBox(width: 6),
                      Text(_p.isActive ? 'Active' : 'In-Active', style: TextStyle(color: p.subtext, fontSize: 12)),
                      const Spacer(),
                      if (_p.isFavorite)
                        const Tag('ग्रंथ डिफ़ॉल्ट', icon: CupertinoIcons.heart_fill, color: AppColors.red),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _p.title,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.text, height: 1.5),
                  ),
                  if (_p.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      _p.description,
                      style: TextStyle(
                        fontFamily: kSerif,
                        fontSize: 17,
                        color: p.text.withValues(alpha: 0.85),
                        height: 1.6,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (_p.pageNumber > 0) Tag('पेज ${_p.pageNumber}', color: AppColors.blue),
                      if (_p.chapterNumber > 0) Tag('अध्याय ${_p.chapterNumber}', color: AppColors.blue),
                      if (_p.createdAt.isNotEmpty)
                        Tag(_p.createdAt.split(' ').first, icon: CupertinoIcons.calendar, color: AppColors.maroon),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SliverToBoxAdapter(
            child: Column(
              children: [
                if (_p.topicId != 0)
                  _LinkRow(
                    icon: CupertinoIcons.list_bullet,
                    label: 'विषय / Topic',
                    value: _p.topicTitle.isEmpty ? '#${_p.topicId}' : _p.topicTitle,
                    onTap: () {
                      final t =
                          app.topics.where((t) => t.id == _p.topicId).firstOrNull ??
                          Topic(id: _p.topicId, title: _p.topicTitle);
                      Navigator.of(context).push(CupertinoPageRoute(builder: (_) => TopicDetailScreen(topic: t)));
                    },
                  ),
                if (_p.granthId != 0)
                  _LinkRow(
                    icon: CupertinoIcons.book,
                    label: 'ग्रंथ / Granth',
                    value: _p.granthTitle.isEmpty ? '#${_p.granthId}' : _p.granthTitle,
                    leading: _p.granthImageUrl == null
                        ? null
                        : NetImage(_p.granthImageUrl, width: 40, height: 40, radius: 10),
                    onTap: () {
                      final g =
                          app.granths.where((g) => g.id == _p.granthId).firstOrNull ??
                          Granth(id: _p.granthId, title: _p.granthTitle);
                      Navigator.of(context).push(CupertinoPageRoute(builder: (_) => GranthDetailScreen(granth: g)));
                    },
                  ),
                if (_p.editorImageUrl != null)
                  _LinkRow(
                    icon: CupertinoIcons.doc_richtext,
                    label: 'विवरण चित्र / Editor Image',
                    value: 'देखें / View',
                    leading: NetImage(_p.editorImageUrl, width: 40, height: 40, radius: 10),
                    onTap: () => openImageViewer(
                      context,
                      _images,
                      initial: _images.indexWhere((e) => e.url == _p.editorImageUrl),
                    ),
                  ),
                if (_p.hasYoutube)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PressableGlass(
                      padding: const EdgeInsets.all(10),
                      onTap: () => openExternal(_p.youtubeWatchUri.toString()),
                      child: Row(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              NetImage(_p.youtubeThumb, width: 120, height: 68, radius: 12),
                              const Icon(
                                CupertinoIcons.play_circle_fill,
                                color: Colors.white,
                                size: 30,
                                shadows: [Shadow(blurRadius: 8)],
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YouTube',
                                  style: TextStyle(color: p.text, fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${_p.youtubeId}${_p.youtubeStart > 0 ? ' • ${_p.youtubeStart}s से' : ''}',
                                  style: TextStyle(color: p.subtext, fontSize: 12),
                                ),
                                if (_p.youtubeDesc.trim().isNotEmpty)
                                  Text(
                                    _p.youtubeDesc,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: p.subtext, fontSize: 13),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    PillButton('Edit', CupertinoIcons.pencil, () => showPramanForm(context, praman: _p)),
                    PillButton(
                      _p.isActive ? 'Hide' : 'Show',
                      _p.isActive ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                      () => togglePraman(context, _p),
                    ),
                    if (canFav && !_p.isFavorite)
                      PillButton(
                        'Set default ♥',
                        CupertinoIcons.heart,
                        () => favoriteFlow(context, _p, granthId: widget.granthContext),
                      ),
                    PillButton('Share', CupertinoIcons.share, () => shareItem('praman', _p.id, _p.title)),
                    PillButton('Delete', CupertinoIcons.trash, () async {
                      if (await deletePramanFlow(context, _p) && context.mounted) Navigator.of(context).maybePop();
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label, required this.value, required this.onTap, this.leading});
  final IconData icon;
  final String label, value;
  final VoidCallback onTap;
  final Widget? leading;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableGlass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: 18,
        onTap: onTap,
        child: Row(
          children: [
            leading ?? Icon(icon, color: AppColors.saffron),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: p.subtext, fontSize: 12)),
                  Text(
                    value.replaceAll('\n', ' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 16, color: p.subtext),
          ],
        ),
      ),
    );
  }
}
