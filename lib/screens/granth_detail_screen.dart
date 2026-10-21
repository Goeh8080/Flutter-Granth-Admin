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
import 'granth_form.dart';
import 'image_viewer.dart';
import 'item_actions.dart';
import 'praman_form.dart';
import 'topic_detail_screen.dart' show PillButton;

/// showPramanForGranth(): granth info, images, PDF + its pramans (get_pramans&granthId=).
class GranthDetailScreen extends StatefulWidget {
  const GranthDetailScreen({super.key, required this.granth});
  final Granth granth;
  @override
  State<GranthDetailScreen> createState() => _GranthDetailScreenState();
}

class _GranthDetailScreenState extends State<GranthDetailScreen> {
  late Granth _g = widget.granth;
  List<Praman> _pramans = const [];
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
    final api = AppScope.of(context).api;
    setState(() => _error = null);
    try {
      final r = await Future.wait([api.granth(_g.id), api.pramans(granthId: _g.id)]);
      if (!mounted) return;
      setState(() {
        _g = Granth.fromJson({..._g.raw, ...(r[0] as Granth).raw});
        _pramans = r[1] as List<Praman>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
      if (_pramans.isNotEmpty) showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ViewerImage> get _images => [
    if (_g.imageUrl != null) ViewerImage(_g.imageUrl!, 'ग्रंथ चित्र', heroTag: 'granth-img-${_g.id}'),
    if (_g.editorImageUrl != null) ViewerImage(_g.editorImageUrl!, 'विवरण चित्र'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GlassPage(
      title: 'ग्रंथ',
      largeTitle: false,
      previousPageTitle: 'ग्रंथ',
      onRefresh: _load,
      trailing: GlassIconButton(
        CupertinoIcons.ellipsis,
        onTap: () => showGranthActions(context, _g, onDeleted: () => Navigator.of(context).maybePop()),
      ),
      floating: GlassFab(bottom: 24, onTap: () => showPramanForm(context, granthId: _g.id)),
      slivers: [
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SliverToBoxAdapter(
            child: Glass(
              blur: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => openImageViewer(context, _images),
                        child: Hero(
                          tag: 'granth-img-${_g.id}',
                          child: NetImage(_g.imageUrl, width: 110, height: 146, radius: 16),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Tag('#${_g.position}', color: AppColors.maroon),
                                const Spacer(),
                                StatusDot(_g.isActive),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _g.title,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text, height: 1.5),
                            ),
                            if (_g.author.trim().isNotEmpty)
                              Text(
                                '✍️ ${_g.author.trim()}',
                                style: const TextStyle(color: AppColors.saffronDeep, fontWeight: FontWeight.w600),
                              ),
                            const SizedBox(height: 6),
                            Tag('${_g.pramanCount} प्रमाण', icon: CupertinoIcons.photo_on_rectangle),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_g.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_g.description, style: TextStyle(color: p.subtext, fontSize: 15, height: 1.5)),
                  ],
                  if (_g.editorImageUrl != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'विवरण चित्र / Vivran Image',
                      style: TextStyle(color: p.subtext, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => openImageViewer(context, _images, initial: _images.length - 1),
                      child: NetImage(_g.editorImageUrl, height: 160, width: double.infinity),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PillButton('Edit', CupertinoIcons.pencil, () => showGranthForm(context, granth: _g)),
                      PillButton(
                        _g.isActive ? 'Hide' : 'Show',
                        _g.isActive ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                        () => toggleGranth(context, _g),
                      ),
                      if (_g.pdfUrl.isNotEmpty)
                        PillButton('PDF', CupertinoIcons.doc_text, () => openExternal(_g.pdfUrl)),
                      PillButton('Position', CupertinoIcons.number, () => moveGranthFlow(context, _g)),
                      PillButton('Share', CupertinoIcons.share, () => shareItem('granth', _g.id, _g.title)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        PadSliver(
          child: SliverToBoxAdapter(
            child: SectionTitle(
              'प्रमाण / Pramans (${_pramans.length})',
              trailing: Text('♥ = ग्रंथ डिफ़ॉल्ट', style: TextStyle(color: p.subtext, fontSize: 11)),
            ),
          ),
        ),
        PramanSliverList(
          items: _pramans,
          heroPrefix: 'gp',
          granthContext: _g.id,
          loading: _loading,
          error: _error,
          onRetry: _load,
        ),
      ],
    );
  }
}
