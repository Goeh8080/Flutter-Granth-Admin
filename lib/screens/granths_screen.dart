import 'package:flutter/cupertino.dart';

import '../core/app_state.dart';
import '../core/perf.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_items.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/grid_kit.dart';
import '../widgets/toast.dart';
import 'granth_detail_screen.dart';
import 'granth_form.dart';
import 'home_shell.dart';
import 'item_actions.dart';
import 'reorder_screen.dart';

class GranthsScreen extends StatefulWidget {
  const GranthsScreen({super.key});
  @override
  State<GranthsScreen> createState() => _GranthsScreenState();
}

class _GranthsScreenState extends State<GranthsScreen> with RevisionReload<GranthsScreen> {
  final _search = TextEditingController();
  List<Granth> _all = const [];
  String _local = '', _serverQuery = '';
  bool _loading = true;
  Object? _error;
  String _sort = 'position';
  bool _desc = false;
  final _debounce = Debouncer();
  final _memo = Memo<(List<Granth>, String, String, bool), ({List<Granth> items, Map<int, int> index})>();

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show what the app already holds (dashboard/lookups) at once.
    final cached = AppScope.of(context).granths;
    if (cached.isNotEmpty) {
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
    // One rebuild when the request starts (only if something visible changes)...
    if (_error != null || (_all.isEmpty && !_loading)) {
      setState(() {
        _error = null;
        if (_all.isEmpty) _loading = true;
      });
    }
    try {
      final r = await app.api.granths(search: _serverQuery);
      if (_serverQuery.isEmpty) app.granths = r;
      // ...and one when it ends.
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

  ({List<Granth> items, Map<int, int> index}) get _view => _memo.get((_all, _local, _sort, _desc), () {
    final items = _visible;
    return (items: items, index: {for (var i = 0; i < items.length; i++) items[i].id: i});
  });

  Object? _titlesFor;
  List<String> _titlesCache = const [];
  List<String> get _titles {
    if (!identical(_titlesFor, _all)) {
      _titlesFor = _all;
      _titlesCache = _all.map((e) => oneLine(e.title)).toList();
    }
    return _titlesCache;
  }

  List<Granth> get _visible => _sorted(_filtered);

  List<Granth> _sorted(List<Granth> l) => switch (_sort) {
    'title' => sortedBy(l, (g) => g.title, desc: _desc),
    'author' => sortedBy(l, (g) => g.author, desc: _desc),
    'praman' => sortedBy(l, (g) => g.pramanCount, desc: _desc),
    'newest' => sortedBy(l, (g) => g.createdAt, desc: _desc),
    _ => _desc ? l.reversed.toList() : l,
  };

  List<Granth> get _filtered {
    if (_local.isEmpty) return _all;
    final q = _local.toLowerCase();
    return _all
        .where(
          (g) =>
              g.title.toLowerCase().contains(q) ||
              g.author.toLowerCase().contains(q) ||
              g.description.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (:items, :index) = _view;
    final app = AppScope.of(context);
    return GlassPage(
      title: 'ग्रंथ / Granths',
      bottomInset: kTabBarHeight + 20,
      onRefresh: _load,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassIconButton(
            CupertinoIcons.arrow_up_arrow_down,
            tooltip: 'Reorder',
            onTap: () async {
              final list = _serverQuery.isNotEmpty ? await app.api.granths() : _all;
              if (!context.mounted) return;
              Navigator.of(context).push(CupertinoPageRoute(builder: (_) => ReorderScreen.granths(list)));
            },
          ),
          const SizedBox(width: 8),
          GlassIconButton(CupertinoIcons.add, tooltip: 'New granth', onTap: () => showGranthForm(context)),
        ],
      ),
      slivers: [
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SliverToBoxAdapter(
            child: Column(
              children: [
                SuggestSearchField(
                  controller: _search,
                  placeholder: 'ग्रंथ खोजें / Search granth',
                  suggestions: _titles,
                  onChanged: (v) => _debounce(() {
                    if (mounted) setState(() => _local = v.trim());
                  }),
                  onSubmitted: (v) => _debounce.now(() {
                    _serverQuery = v.trim();
                    _local = '';
                    _load();
                  }),
                ),
                const SizedBox(height: 10),
                SortBar(
                  options: const [
                    SortOpt('position', 'क्रम'),
                    SortOpt('title', 'नाम'),
                    SortOpt('author', 'लेखक'),
                    SortOpt('praman', 'प्रमाण'),
                    SortOpt('newest', 'नए'),
                  ],
                  sortKey: _sort,
                  desc: _desc,
                  onChanged: (k, d) => setState(() {
                    _desc = k != _sort && (k == 'newest' || k == 'praman') ? true : d;
                    _sort = k;
                  }),
                ),
                if (_serverQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'खोज: "$_serverQuery" — ${_all.length} परिणाम',
                            style: TextStyle(color: p.subtext, fontSize: 13),
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                          onPressed: () => _debounce.now(() {
                            _search.clear();
                            _serverQuery = '';
                            _local = '';
                            _load();
                          }),
                          child: const Text('हटाएँ / Clear', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_loading && _all.isEmpty)
          const SliverToBoxAdapter(child: LoadingView())
        else if (_error != null && _all.isEmpty)
          SliverToBoxAdapter(
            child: MessageView(icon: CupertinoIcons.wifi_exclamationmark, title: '$_error', onRetry: _load),
          )
        else if (items.isEmpty)
          const SliverToBoxAdapter(
            child: MessageView(icon: CupertinoIcons.book, title: 'कोई ग्रंथ नहीं / No granths'),
          )
        else
          PadSliver(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: AnimatedItemsSliver<Granth>(
              items: items,
              idOf: (g) => g.id,
              itemBuilder: (ctx, g, i) => GranthCard(
                granth: g,
                index: index[g.id] ?? i,
                total: items.length,
                onTap: () =>
                    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => GranthDetailScreen(granth: g))),
                onLongPress: () => showGranthActions(context, g),
              ),
            ),
          ),
      ],
    );
  }
}
