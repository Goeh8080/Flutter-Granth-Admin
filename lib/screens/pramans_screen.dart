import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/perf.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/grid_kit.dart';
import '../widgets/praman_sliver.dart';
import '../widgets/toast.dart';
import 'home_shell.dart';
import 'praman_form.dart';

enum PramanFilter { all, topic, granth, youtube, search }

/// praman.php / praman-youtube.php: list with search, topic/granth filters, YouTube-only view.
class PramansScreen extends StatefulWidget {
  const PramansScreen({super.key, this.initialFilter = PramanFilter.all, this.standalone = false});
  final PramanFilter initialFilter;
  final bool standalone;
  @override
  State<PramansScreen> createState() => _PramansScreenState();
}

class _PramansScreenState extends State<PramansScreen> with RevisionReload<PramansScreen> {
  final _search = TextEditingController();
  late PramanFilter _filter = widget.initialFilter;
  Topic? _topic;
  Granth? _granth;
  String _serverQuery = '';
  String _local = '';
  List<Praman> _all = const [];
  bool _loading = true;
  String _sort = 'position';
  bool _desc = false;
  Object? _error;
  final _debounce = Debouncer();
  final _memo = Memo<(List<Praman>, String, String, bool), List<Praman>>();

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate for the unfiltered list: show the app's cache at once.
    final cached = AppScope.of(context).pramans;
    if (_filter == PramanFilter.all && cached.isNotEmpty) {
      _all = cached;
      _loading = false;
    }
  }

  @override
  void dispose() {
    _debounce.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() => _load();

  Future<void> _load() async {
    final app = AppScope.of(context);
    // The spinner only shows while the list is empty, so a refresh with rows on screen
    // doesn't need a rebuild at its start.
    if (_error != null || (_all.isEmpty && !_loading)) {
      setState(() {
        _error = null;
        _loading = true;
      });
    } else {
      _loading = true;
    }
    try {
      final r = switch (_filter) {
        PramanFilter.topic => await app.api.pramans(topicId: _topic!.id),
        PramanFilter.granth => await app.api.pramans(granthId: _granth!.id),
        PramanFilter.youtube => await app.api.pramans(youtube: true),
        PramanFilter.search => await app.api.pramans(search: _serverQuery),
        PramanFilter.all => await app.api.pramans(),
      };
      if (_filter == PramanFilter.all) app.pramans = r;
      if (mounted) {
        setState(() {
          _all = r;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
      if (_all.isNotEmpty) showError(e);
    }
  }

  Object? _titlesFor;
  List<String> _titlesCache = const [];
  List<String> get _titles {
    if (!identical(_titlesFor, _all)) {
      _titlesFor = _all;
      _titlesCache = _all.map((e) => oneLine(e.title)).toList();
    }
    return _titlesCache;
  }

  void _setFilter(PramanFilter f, {Topic? topic, Granth? granth}) {
    setState(() {
      _filter = f;
      _topic = topic;
      _granth = granth;
      if (f != PramanFilter.search) _serverQuery = '';
      _all = const [];
    });
    _load();
  }

  Future<void> _pickTopic() async {
    final app = AppScope.of(context);
    try {
      await app.ensureLookups();
    } catch (e) {
      showError(e);
      return;
    }
    if (!mounted) return;
    final t = await pickFromList(
      context,
      title: 'विषय से फ़िल्टर / Filter by topic',
      items: app.topics,
      labelOf: (t) => '${t.position}. ${t.title}',
      subtitleOf: (t) => '${t.pramanCount} प्रमाण',
    );
    if (t != null) _setFilter(PramanFilter.topic, topic: t);
  }

  Future<void> _pickGranth() async {
    final app = AppScope.of(context);
    try {
      await app.ensureLookups();
    } catch (e) {
      showError(e);
      return;
    }
    if (!mounted) return;
    final g = await pickFromList(
      context,
      title: 'ग्रंथ से फ़िल्टर / Filter by granth',
      items: app.granths,
      labelOf: (g) => '${g.position}. ${g.title}',
      subtitleOf: (g) => '${g.pramanCount} प्रमाण',
    );
    if (g != null) _setFilter(PramanFilter.granth, granth: g);
  }

  List<Praman> get _visible {
    final base = _local.isEmpty
        ? _all
        : () {
            final q = _local.toLowerCase();
            return _all
                .where(
                  (p) =>
                      p.title.toLowerCase().contains(q) ||
                      p.description.toLowerCase().contains(q) ||
                      p.granthTitle.toLowerCase().contains(q) ||
                      p.topicTitle.toLowerCase().contains(q) ||
                      '${p.id}' == q,
                )
                .toList();
          }();
    return switch (_sort) {
      'title' => sortedBy(base, (p) => p.title, desc: _desc),
      'granth' => sortedBy(base, (p) => p.granthTitle, desc: _desc),
      'page' => sortedBy(base, (p) => p.pageNumber, desc: _desc),
      'newest' => sortedBy(base, (p) => p.id, desc: _desc),
      _ => _desc ? base.reversed.toList() : base,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = _memo.get((_all, _local, _sort, _desc), () => _visible);
    String? banner;
    if (_filter == PramanFilter.topic) banner = 'विषय: ${oneLine(_topic!.title)}';
    if (_filter == PramanFilter.granth) banner = 'ग्रंथ: ${oneLine(_granth!.title)}';
    if (_filter == PramanFilter.search) banner = 'खोज: "$_serverQuery"';
    if (_filter == PramanFilter.youtube) banner = 'YouTube प्रमाण';
    return GlassPage(
      title: widget.standalone && _filter == PramanFilter.youtube ? 'YouTube प्रमाण' : 'प्रमाण / Pramans',
      previousPageTitle: widget.standalone ? 'Back' : null,
      bottomInset: widget.standalone ? 0 : kTabBarHeight + 20,
      onRefresh: _load,
      trailing: GlassIconButton(
        CupertinoIcons.add,
        tooltip: 'New praman',
        onTap: () => showPramanForm(
          context,
          topicId: _filter == PramanFilter.topic ? _topic?.id : null,
          granthId: _filter == PramanFilter.granth ? _granth?.id : null,
        ),
      ),
      slivers: [
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SuggestSearchField(
                  controller: _search,
                  placeholder: 'प्रमाण खोजें / Search praman',
                  suggestions: _titles,
                  onChanged: (v) => _debounce(() {
                    if (mounted) setState(() => _local = v.trim());
                  }),
                  onSubmitted: (v) {
                    _debounce.dispose();
                    final q = v.trim();
                    _local = '';
                    if (q.isEmpty) {
                      if (_filter == PramanFilter.search) _setFilter(PramanFilter.all);
                      return;
                    }
                    _serverQuery = q;
                    _setFilter(PramanFilter.search);
                  },
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Chip(
                        'सभी / All',
                        CupertinoIcons.square_stack,
                        _filter == PramanFilter.all,
                        () => _setFilter(PramanFilter.all),
                      ),
                      _Chip(
                        _filter == PramanFilter.topic ? 'विषय ✓' : 'विषय / Topic',
                        CupertinoIcons.list_bullet,
                        _filter == PramanFilter.topic,
                        _pickTopic,
                      ),
                      _Chip(
                        _filter == PramanFilter.granth ? 'ग्रंथ ✓' : 'ग्रंथ / Granth',
                        CupertinoIcons.book,
                        _filter == PramanFilter.granth,
                        _pickGranth,
                      ),
                      _Chip(
                        'YouTube',
                        CupertinoIcons.play_rectangle,
                        _filter == PramanFilter.youtube,
                        () => _setFilter(PramanFilter.youtube),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SortBar(
                  options: const [
                    SortOpt('position', 'क्रम'),
                    SortOpt('title', 'नाम'),
                    SortOpt('granth', 'ग्रंथ'),
                    SortOpt('page', 'पृष्ठ'),
                    SortOpt('newest', 'नए'),
                  ],
                  sortKey: _sort,
                  desc: _desc,
                  onChanged: (k, d) => setState(() {
                    _desc = k != _sort && k == 'newest' ? true : d;
                    _sort = k;
                  }),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: banner == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$banner  •  ${_all.length}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w600),
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 28),
                                onPressed: () {
                                  _search.clear();
                                  _setFilter(PramanFilter.all);
                                },
                                child: const Icon(CupertinoIcons.xmark_circle_fill, size: 20),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        PramanSliverList(
          items: items,
          heroPrefix: 'praman',
          granthContext: _filter == PramanFilter.granth ? _granth?.id : null,
          loading: _loading,
          error: _error,
          onRetry: _load,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.icon, this.selected, this.onTap);
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected ? AppColors.saffron : p.fieldFill,
            border: Border.all(color: selected ? AppColors.saffron : p.glassBorder, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: selected ? Colors.white : p.subtext),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : p.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
